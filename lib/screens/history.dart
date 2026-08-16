import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart';
import '../theme.dart';

/// 7-day history: pick a day, draw the route + stops + daily stats + playback.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.uuid, this.name});
  final String uuid;
  final String? name;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _dayOffset = 0;
  List<dynamic> _pts = [];        // raw points with ts
  List<LatLng> _route = [];
  List<dynamic> _stops = [];
  // §11 playback
  int _playIdx = 0;
  Timer? _playTimer;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _playTimer?.cancel(); super.dispose(); }

  String get _dayStr {
    final d = DateTime.now().toUtc().subtract(Duration(days: _dayOffset));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final pts = await api.history(widget.uuid, day: _dayStr);
    final stops = await api.stops(widget.uuid, day: _dayStr);
    if (mounted) {
      setState(() {
        _pts = pts;
        _route = [for (final p in pts) LatLng(p['lat'], p['lng'])];
        _stops = stops;
        _playIdx = 0;
        _playTimer?.cancel();
      });
    }
  }

  String _hm(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // §12 daily stats computed client-side from already-loaded data.
  double get _km {
    double m = 0;
    for (var i = 1; i < _route.length; i++) { m += const Distance()(_route[i - 1], _route[i]); }
    return m / 1000;
  }
  String get _activeWindow {
    if (_pts.isEmpty) return '—';
    final a = DateTime.tryParse(_pts.first['ts'])?.toLocal();
    final b = DateTime.tryParse(_pts.last['ts'])?.toLocal();
    if (a == null || b == null) return '—';
    two(int n) => n.toString().padLeft(2, '0');
    return '${two(a.hour)}:${two(a.minute)}–${two(b.hour)}:${two(b.minute)}';
  }

  // §11 play/pause the route.
  void _togglePlay() {
    if (_playTimer != null) { _playTimer!.cancel(); setState(() => _playTimer = null); return; }
    if (_playIdx >= _route.length - 1) _playIdx = 0;
    setState(() => _playTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (_playIdx >= _route.length - 1) { t.cancel(); setState(() => _playTimer = null); return; }
      setState(() => _playIdx++);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.name ?? ''} · история')),
      body: Column(children: [
        SizedBox(height: 56, child: ListView.builder(
          scrollDirection: Axis.horizontal, itemCount: 7, padding: const EdgeInsets.symmetric(horizontal: 8),
          itemBuilder: (_, i) {
            final d = DateTime.now().subtract(Duration(days: i));
            return Padding(padding: const EdgeInsets.all(6), child: ChoiceChip(
              label: Text(i == 0 ? 'Сегодня' : i == 1 ? 'Вчера' : '${d.day}.${d.month}'),
              selected: i == _dayOffset, selectedColor: kPurple,
              onSelected: (_) { setState(() => _dayOffset = i); _load(); }));
          },
        )),
        // §12 daily stats
        if (_route.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat('${_km.toStringAsFixed(1)} км', 'пройдено'),
              _stat('${_stops.length}', 'остановок'),
              _stat(_activeWindow, 'в пути'),
            ])),
        Expanded(flex: 3, child: _route.isEmpty
            ? const Center(child: Text('Нет данных за этот день', style: TextStyle(color: kMuted)))
            : FlutterMap(
                options: MapOptions(initialCenter: _route.last, initialZoom: 13),
                children: [
                  oxTileLayer(),
                  PolylineLayer(polylines: [Polyline(points: _route, strokeWidth: 4, color: kPurple)]),
                  MarkerLayer(markers: [
                    for (final s in _stops)
                      Marker(point: LatLng(s['lat'], s['lng']), width: 46, height: 46,
                        child: Container(alignment: Alignment.center,
                          decoration: BoxDecoration(color: kAmber.withValues(alpha: .2), shape: BoxShape.circle, border: Border.all(color: kAmber, width: 2)),
                          child: Text('${s['minutes']}′', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kAmber)))),
                    Marker(point: _route.first, child: const Icon(Icons.trip_origin, color: kGreen, size: 18)),
                    Marker(point: _route.last, child: const Icon(Icons.location_on, color: kRed)),
                    // §11 playback marker
                    Marker(point: _route[_playIdx.clamp(0, _route.length - 1)], width: 26, height: 26,
                      child: Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                          border: Border.all(color: kPurple, width: 3)))),
                  ]),
                ],
              )),
        // §11 playback controls
        if (_route.length > 1)
          Row(children: [
            IconButton(onPressed: _togglePlay,
                icon: Icon(_playTimer != null ? Icons.pause_circle : Icons.play_circle, color: kPurple, size: 30)),
            Expanded(child: Slider(value: _playIdx.toDouble(), min: 0, max: (_route.length - 1).toDouble(),
                activeColor: kPurple,
                onChanged: (v) { _playTimer?.cancel(); setState(() { _playTimer = null; _playIdx = v.round(); }); })),
            if (_pts.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 12),
                child: Text(_hm(_pts[_playIdx.clamp(0, _pts.length - 1)]['ts']),
                    style: const TextStyle(color: kMuted, fontSize: 12))),
          ]),
        // stops list
        Expanded(flex: 2, child: Container(
          decoration: const BoxDecoration(color: Color(0xFF0A0A12), border: Border(top: BorderSide(color: kLine))),
          child: _stops.isEmpty
              ? const Center(child: Text('Остановок не найдено', style: TextStyle(color: kMuted, fontSize: 12)))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Padding(padding: const EdgeInsets.only(bottom: 6),
                    child: Text('ОСТАНОВКИ · ${_stops.length}', style: const TextStyle(fontSize: 11, letterSpacing: 2, color: kMuted, fontWeight: FontWeight.w800))),
                  for (final s in _stops)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
                      Container(width: 34, height: 34, alignment: Alignment.center,
                        decoration: BoxDecoration(color: kAmber.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
                        child: const Text('📍', style: TextStyle(fontSize: 15))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Остановка', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        Text('${_hm(s['start'])} – ${_hm(s['end'])}', style: const TextStyle(color: kMuted, fontSize: 11)),
                      ])),
                      Text('${s['minutes']} мин', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kAmber)),
                    ])),
                ]),
        )),
      ]),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kPurple)),
    Text(label, style: const TextStyle(fontSize: 10, color: kMuted)),
  ]);
}
