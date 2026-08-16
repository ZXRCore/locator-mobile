import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'api.dart';

// Runs in a separate Dart isolate with NO UI — after the app is terminated or
// the device reboots (startOnBoot). Must be a top-level function registered via
// BackgroundGeolocation.registerHeadlessTask.
@pragma('vm:entry-point')
Future<void> headlessTask(bg.HeadlessEvent event) async {
  // Rebuild a bare API client from stored token (no access to the UI's `api`).
  final api = Api(kApiBase);
  switch (event.name) {
    case bg.Event.LOCATION:
      final bg.Location l = event.event;
      await api.pushLocation(l.coords.latitude, l.coords.longitude,
          battery: (l.battery.level * 100).round(),
          moving: l.isMoving ? 'moving' : 'still');
      break;
    case bg.Event.GEOFENCE:
      final bg.GeofenceEvent g = event.event;
      await api.geofenceEvent(g.identifier, g.action);
      break;
  }
}
