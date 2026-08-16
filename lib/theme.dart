import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

// 0xMap brand & style C: near-black ground, purple accent, bold type.
const kPurple = Color(0xFF8B5CF6);
const kBg = Color(0xFF050507);
const kCard = Color(0xFF0E0E16);
const kLine = Color(0xFF23232F);
const kMuted = Color(0xFF9A9AAD);
const kGreen = Color(0xFF34D399);
const kAmber = Color(0xFFFBBF24);
const kRed = Color(0xFFF87171);

/// Parse a "#RRGGBB" hex string to a Color (falls back to green).
Color hexColor(String? hex) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return kGreen;
  return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

// Palette offered for place colours.
const kPlaceColors = ['#34D399', '#8B5CF6', '#FBBF24', '#F87171', '#38BDF8', '#F472B6', '#A3E635'];

/// Battery colour by charge: green, amber <30%, red <20%.
Color batteryColor(int? pct) {
  if (pct == null) return kMuted;
  if (pct < 20) return kRed;
  if (pct < 30) return kAmber;
  return kGreen;
}

// ---- UI size: 9 steps, 5 = default (medium). Scales text globally. ----
final uiSize = ValueNotifier<int>(5);
double uiScale(int step) => 0.82 + (step - 1) * 0.045; // 1->0.82 .. 5->1.0 .. 9->1.18

// ---- Map tiles: OSM default (first), CartoDB dark second. ----
class TileSource {
  final String name, url;
  final List<String> subdomains;
  const TileSource(this.name, this.url, this.subdomains);
}

const kTileSources = {
  'osm': TileSource('OpenStreetMap',
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png', []),
  'dark': TileSource('Тёмная (CartoDB)',
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', ['a', 'b', 'c', 'd']),
};

final tileChoice = ValueNotifier<String>('osm');

Widget oxTileLayer() => ValueListenableBuilder<String>(
      valueListenable: tileChoice,
      builder: (_, key, __) {
        final t = kTileSources[key] ?? kTileSources['osm']!;
        return TileLayer(
          urlTemplate: t.url,
          subdomains: t.subdomains,
          userAgentPackageName: 'sh.zxr.locator',
        );
      },
    );

final oxMapTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPurple,
    brightness: Brightness.dark,
    primary: kPurple,
    surface: kBg,
  ),
  cardColor: kCard,
  dividerColor: kLine,
  appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
  useMaterial3: true,
);

// Light theme (§6). ponytail: quick variant — surfaces switch via ThemeData;
// a few screens still use `const kBg/kCard/0xFF0A0A12` directly (drawer, sheets)
// and stay dark until a full Theme.of refactor. Marked at those call sites.
final oxLightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFF7F7FB),
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPurple,
    brightness: Brightness.light,
    primary: kPurple,
  ),
  appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F7FB), elevation: 0, foregroundColor: Color(0xFF14141C)),
  useMaterial3: true,
);

// Theme choice: light / dark / system. Persisted like tileChoice/uiSize.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
const kThemeModes = {'system': ThemeMode.system, 'light': ThemeMode.light, 'dark': ThemeMode.dark};

// Wordmark: "0x" purple + "Map" — second word follows the current text colour.
Widget oxMapWordmark({double size = 24}) => Builder(builder: (ctx) {
      final ink = DefaultTextStyle.of(ctx).style.color ?? Colors.white;
      return Text.rich(TextSpan(children: [
        TextSpan(text: '0x', style: TextStyle(color: kPurple, fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -1)),
        TextSpan(text: 'Map', style: TextStyle(color: ink, fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -1)),
      ]));
    });
