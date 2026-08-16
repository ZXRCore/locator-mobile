import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'theme.dart';
import 'services/api.dart';
import 'services/tracking.dart';
import 'services/headless.dart';
import 'screens/login.dart';
import 'screens/map.dart';

final api = Api(kApiBase);  // kApiBase defined in services/api.dart
final tracking = Tracking(api);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the headless handler so tracking survives app-kill and reboot.
  bg.BackgroundGeolocation.registerHeadlessTask(headlessTask);
  // Restore saved prefs: map tiles + UI size.
  final savedTiles = await api.getPref('tiles');
  if (savedTiles != null && kTileSources.containsKey(savedTiles)) tileChoice.value = savedTiles;
  final savedSize = await api.getPref('ui_size');
  if (savedSize != null) uiSize.value = int.tryParse(savedSize)?.clamp(1, 9) ?? 5;
  final savedTheme = await api.getPref('theme');
  if (savedTheme != null && kThemeModes.containsKey(savedTheme)) themeMode.value = kThemeModes[savedTheme]!;
  runApp(const OxMapApp());
}

class OxMapApp extends StatelessWidget {
  const OxMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: '0xMap',
        theme: oxLightTheme,
        darkTheme: oxMapTheme,
        themeMode: mode,
        // Global UI size: rescale all text by the chosen step.
        builder: (context, child) => ValueListenableBuilder<int>(
          valueListenable: uiSize,
          builder: (_, step, __) => MediaQuery.withClampedTextScaling(
            minScaleFactor: uiScale(step),
            maxScaleFactor: uiScale(step),
            child: child!,
          ),
        ),
        home: FutureBuilder<String?>(
          future: api.token,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return snap.data == null ? const LoginScreen() : const MapScreen();
          },
        ),
      ),
    );
  }
}
