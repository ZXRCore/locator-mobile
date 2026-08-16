import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'api.dart';
import '../main.dart' show tracking;

/// Re-register friends' places as OS geofences. Called on silent push, so a
/// friend's new place starts being watched without opening the app.
Future<void> resyncGeofences(Api api) async {
  await bg.BackgroundGeolocation.removeGeofences();
  for (final p in await api.friendsPlaces()) {
    await bg.BackgroundGeolocation.addGeofence(bg.Geofence(
      identifier: p['id'],
      latitude: p['lat'],
      longitude: p['lng'],
      radius: (p['radius'] as num).toDouble(),
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: true,
      loiteringDelay: 60000,
    ));
  }
}

/// Runs in its own isolate when a push arrives and the app is backgrounded or
/// killed. Must be top-level and annotated.
@pragma('vm:entry-point')
Future<void> backgroundPushHandler(RemoteMessage message) async {
  if (message.data['action'] != 'resync_geofences') return;
  await Firebase.initializeApp();
  await resyncGeofences(Api(kApiBase));
}

/// Register for FCM and hand the device token to the backend so friends'
/// geofence events and silent resync pushes can reach this device.
Future<void> initPush(Api api) async {
  await Firebase.initializeApp();
  final fm = FirebaseMessaging.instance;
  await fm.requestPermission();
  final token = await fm.getToken();
  if (token != null) await api.setPushToken(token);
  fm.onTokenRefresh.listen((t) => api.setPushToken(t));

  FirebaseMessaging.onBackgroundMessage(backgroundPushHandler);
  FirebaseMessaging.onMessage.listen((m) {
    final action = m.data['action'];
    if (action == 'resync_geofences') resyncGeofences(api);
    if (action == 'boost_accuracy') {
      // §1: a friend is watching — high accuracy for ~90s, then back to normal
      tracking.boostAccuracy();
      Timer(const Duration(seconds: 90), () => tracking.normalAccuracy());
    }
  });
}
