import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import '../main.dart';
import '../theme.dart';

// Emoji offered for place icons.
const _kEmojis = ['🏠','💼','🏋️','❤️','🍺','🎓','🅿️','🛒','🏥','🍽️','☕','📍'];

/// Places: named points with emoji, colour and radius. A place watches the
/// owner's FRIENDS — when a friend crosses it, the owner gets the push.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, this.editId});
  final String? editId;   // if set, open the editor for this place immediately
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  List<dynamic> _places = [];
  bool _openedEdit = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await api.places();
    if (mounted) setState(() => _places = p);
    // deep-link into a specific place editor (from map tap). Defer the push to
    // the next frame so we don't navigate while the navigator is still locked
    // by the push that opened this screen (Failed assertion !_debugLocked).
    if (!_openedEdit && widget.editId != null) {
      _openedEdit = true;
      final target = p.firstWhere((x) => x['id'] == widget.editId, orElse: () => null);
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _edit(existing: target); });
      }
    }
  }

  Future<void> _edit({dynamic existing}) async {
    final result = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => _PlaceEditor(existing: existing)));
    if (result == true) { await tracking.syncGeofences(); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои точки')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(6), child: Text(
          'Вы получаете уведомление, когда друг заходит в вашу точку.',
          textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12))),
        for (final p in _places)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(15), border: Border.all(color: kLine)),
            child: ListTile(
              leading: Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: hexColor(p['color']).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: hexColor(p['color']))),
                child: Text(p['emoji'] ?? '📍', style: const TextStyle(fontSize: 20))),
              title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('радиус ${p['radius']} м', style: const TextStyle(color: kMuted)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => _edit(existing: p),
            ),
          ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPurple, onPressed: () => _edit(), child: const Icon(Icons.add)),
    );
  }
}

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({this.existing});
  final dynamic existing;
  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _radiusField;
  late LatLng _point;
  late double _radius;
  late String _emoji;
  late String _color;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _name.addListener(() => setState(() {}));
    _radius = (e?['radius'] ?? 500).toDouble();
    _radiusField = TextEditingController(text: _radius.round().toString());
    _emoji = e?['emoji'] ?? '📍';
    _color = e?['color'] ?? kPlaceColors.first;
    if (e != null) {
      _point = LatLng(e['lat'], e['lng']);
    } else {
      _point = const LatLng(0, 0);
      _useCurrentPosition();
    }
  }

  Future<void> _useCurrentPosition() async {
    try {
      final loc = await bg.BackgroundGeolocation.getCurrentPosition(samples: 1, persist: false);
      final here = LatLng(loc.coords.latitude, loc.coords.longitude);
      if (mounted) { setState(() => _point = here); _map.move(here, 15); }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (widget.existing != null) {
      await api.updatePlace(widget.existing['id'], _name.text, _emoji, _color, _point.latitude, _point.longitude, _radius.round());
    } else {
      await api.createPlace(_name.text, _emoji, _color, _point.latitude, _point.longitude, _radius.round());
    }
    if (mounted) Navigator.pop(context, true);
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !(_point.latitude == 0 && _point.longitude == 0);

  @override
  Widget build(BuildContext context) {
    final col = hexColor(_color);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Новая метка' : 'Метка'),
        actions: [TextButton(onPressed: _canSave ? _save : null,
            child: Text('Готово', style: TextStyle(fontWeight: FontWeight.w800, color: _canSave ? kPurple : kMuted)))],
      ),
      body: Column(children: [
        Expanded(child: FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: _point, initialZoom: 15,
              onTap: (_, p) => setState(() => _point = p)),
          children: [
            oxTileLayer(),
            CircleLayer(circles: [CircleMarker(point: _point, radius: _radius, useRadiusInMeter: true,
                color: col.withValues(alpha: .18), borderColor: col, borderStrokeWidth: 2)]),
            MarkerLayer(markers: [Marker(point: _point, width: 40, height: 40,
                child: Container(alignment: Alignment.center,
                  decoration: BoxDecoration(color: kCard, shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
                  child: Text(_emoji, style: const TextStyle(fontSize: 18))))]),
          ],
        )),
        Container(
          decoration: const BoxDecoration(color: Color(0xFF0A0A12), border: Border(top: BorderSide(color: kLine))),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            // emoji + name
            Row(children: [
              Container(width: 48, height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
                child: Text(_emoji, style: const TextStyle(fontSize: 24))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _name,
                  decoration: const InputDecoration(hintText: 'Название (напр. Дом)', isDense: true, border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            // emoji picker
            SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in _kEmojis)
                GestureDetector(onTap: () => setState(() => _emoji = e), child: Container(
                  width: 40, height: 40, margin: const EdgeInsets.only(right: 7), alignment: Alignment.center,
                  decoration: BoxDecoration(color: _emoji == e ? kPurple : kCard, borderRadius: BorderRadius.circular(11)),
                  child: Text(e, style: const TextStyle(fontSize: 18)))),
            ])),
            const SizedBox(height: 10),
            // colour picker
            Row(children: [
              const Text('Цвет', style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final c in kPlaceColors)
                  GestureDetector(onTap: () => setState(() => _color = c), child: Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle,
                        border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 2)))),
              ])),
            ]),
            const SizedBox(height: 12),
            // radius
            Row(children: [
              const Text('Радиус', style: TextStyle(color: kMuted, fontSize: 12)),
              Expanded(child: Slider(value: _radius.clamp(50, 2000), min: 50, max: 2000, divisions: 195,
                  label: '${_radius.round()} м', activeColor: kPurple,
                  onChanged: (v) => setState(() { _radius = v; _radiusField.text = v.round().toString(); }))),
              SizedBox(width: 66, child: TextField(controller: _radiusField, keyboardType: TextInputType.number,
                  textAlign: TextAlign.center, decoration: const InputDecoration(suffixText: 'м', isDense: true),
                  onSubmitted: (t) { final v = double.tryParse(t); if (v != null) setState(() => _radius = v.clamp(10, 5000)); })),
            ]),
            if (_point.latitude == 0 && _point.longitude == 0)
              const Padding(padding: EdgeInsets.only(top: 6),
                child: Text('Определяем местоположение… или нажми на карту', style: TextStyle(fontSize: 11, color: kMuted))),
          ]),
        ),
      ]),
    );
  }
}
