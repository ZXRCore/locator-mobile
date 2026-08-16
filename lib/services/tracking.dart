import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'api.dart';
import 'push.dart';

/// Battery-efficient background tracking (ТЗ §0).
/// The plugin does the heavy lifting: motion detection, adaptive frequency,
/// batching, geofence-style stationary handling. We just configure it and
/// forward each fix to the API.
class Tracking {
  Tracking(this.api);
  final Api api;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    bg.BackgroundGeolocation.onLocation((bg.Location l) {
      api.pushLocation(
        l.coords.latitude,
        l.coords.longitude,
        battery: ((l.battery.level) * 100).round(),
        moving: l.isMoving ? 'moving' : 'still',
      );
      _maybeResync();
    });

    // §6a: native geofence events -> notify friends via API. Zero extra battery,
    // the OS wakes us only on enter/exit/dwell.
    bg.BackgroundGeolocation.onGeofence((bg.GeofenceEvent e) {
      api.geofenceEvent(e.identifier, e.action);  // identifier == place_id
    });

    await bg.BackgroundGeolocation.ready(bg.Config(
      // Accuracy vs battery: HIGH only fires when actually moving; the plugin
      // drops to a low-power stationary state on its own.
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 50,          // meters between fixes while moving (battery-tuned)
      stopTimeout: 5,              // minutes still -> enter stationary/geofence mode
      stopOnTerminate: false,      // keep tracking after app is killed
      startOnBoot: true,           // resume tracking after device reboot
      enableHeadless: true,        // run Dart headless task with no UI (see headless.dart)
      foregroundService: true,     // persistent notification = Android won't kill us
      // Batching: don't spend radio per-fix; flush in groups.
      autoSync: true,
      batchSync: true,
      maxBatchSize: 20,
      autoSyncThreshold: 5,
      // We POST ourselves in onLocation, so no plugin HTTP url needed.
      debug: false,
      logLevel: bg.Config.LOG_LEVEL_OFF,
    ));

    await bg.BackgroundGeolocation.start();
    await syncGeofences();
  }

  /// Register FRIENDS' places as OS geofences: this device reports when the
  /// user (visitor) crosses a friend's place, and the friend (owner) is notified.
  /// Shared with the silent-push path in push.dart.
  Future<void> syncGeofences() => resyncGeofences(api);

  // Fallback in case a silent push is missed: refresh geofences at most every
  // 15 min, piggy-backing on location updates (no extra wakeups, no battery cost).
  DateTime _lastResync = DateTime.fromMillisecondsSinceEpoch(0);
  void _maybeResync() {
    if (DateTime.now().difference(_lastResync) < const Duration(minutes: 15)) return;
    _lastResync = DateTime.now();
    resyncGeofences(api).catchError((_) {});
  }

  /// §6 realtime "someone is watching me": crank up accuracy temporarily.
  Future<void> boostAccuracy() =>
      bg.BackgroundGeolocation.setConfig(bg.Config(distanceFilter: 5));

  Future<void> normalAccuracy() =>
      bg.BackgroundGeolocation.setConfig(bg.Config(distanceFilter: 50));

  Future<void> stop() async {
    _started = false;
    await bg.BackgroundGeolocation.stop();
  }
}
