import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import '../main.dart';
import '../theme.dart';
import '../services/push.dart';
import 'friends.dart';
import 'settings.dart';
import 'history.dart';
import 'places.dart';
import 'login.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _Friend {
  final String uuid, label;
  final LatLng pos;
  final int? battery;
  final String? moving;
  final DateTime? updated;
  _Friend(this.uuid, this.label, this.pos, this.battery, this.moving, this.updated);
}

class _MapScreenState extends State<MapScreen> {
  List<_Friend> _friends = [];
  List<dynamic> _places = [];
  LatLng? _me;
  int? _myBattery;
  Timer? _refresh;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    tracking.start();
    initPush(api).catchError((_) {});
    _loadFriends();
    _loadPlaces();
    _updateMe();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) { _loadFriends(); _updateMe(); });
  }

  @override
  void dispose() { _refresh?.cancel(); super.dispose(); }

  Future<void> _loadPlaces() async {
    final p = await api.places();
    if (mounted) setState(() => _places = p);
  }

  Future<void> _updateMe() async {
    try {
      final loc = await bg.BackgroundGeolocation.getCurrentPosition(samples: 1, persist: false);
      if (mounted) {
        setState(() {
          _me = LatLng(loc.coords.latitude, loc.coords.longitude);
          _myBattery = (loc.battery.level * 100).round();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFriends() async {
    final friends = await api.friends();
    final out = <_Friend>[];
    for (final f in friends) {
      if (f['status'] != 'accepted') continue;
      final loc = await api.location(f['uuid']);
      if (loc == null) continue;
      final alias = await api.localAlias(f['uuid']);
      out.add(_Friend(
        f['uuid'], alias ?? f['name'] ?? '',
        LatLng(loc['lat'], loc['lng']),
        loc['battery'], loc['moving_state'],
        loc['updated_at'] != null ? DateTime.tryParse(loc['updated_at'])?.toLocal() : null,
      ));
    }
    if (mounted) setState(() => _friends = out);
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
      .then((_) { _loadFriends(); _loadPlaces(); });

  Future<void> _logout() async {
    await tracking.stop();
    await api.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'только что';
    if (m < 60) return '$m мин назад';
    if (m < 60 * 24) return '${m ~/ 60} ч назад';
    return '${m ~/ (60 * 24)} дн назад';
  }

  // §2: is this friend's fix stale (>5 min old)?
  bool _stale(DateTime? t) => t == null || DateTime.now().difference(t).inMinutes >= 5;

  // §3: distance from me to a friend, human-readable.
  String? _distanceTo(LatLng p) {
    if (_me == null) return null;
    final m = const Distance()(_me!, p);
    return m < 1000 ? '${m.round()} м от вас' : '${(m / 1000).toStringAsFixed(1)} км от вас';
  }

  // Tap a friend pin -> bottom card: name, battery, when, rename + history.
  void _friendCard(_Friend f) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard, borderRadius: BorderRadius.circular(22),
          border: const Border(top: BorderSide(color: kPurple, width: 2.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(16)),
              child: Text(f.label.isNotEmpty ? f.label[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
                if ((f.battery ?? 100) < 20) const Padding(padding: EdgeInsets.only(left: 4), child: Text('⚠️', style: TextStyle(fontSize: 15))),
                IconButton(icon: const Icon(Icons.edit, size: 18, color: kMuted),
                    onPressed: () { Navigator.pop(sheet); _renameFriend(f); }),
              ]),
              // §2 last-seen + §3 distance
              Text([
                _stale(f.updated) ? 'был ${_ago(f.updated)}' : (f.moving == 'moving' ? 'в движении' : 'на месте'),
                if (_distanceTo(f.pos) != null) _distanceTo(f.pos),
              ].join(' · '), style: const TextStyle(fontSize: 12, color: kMuted)),
            ])),
            Column(children: [
              Text('${f.battery ?? "—"}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: batteryColor(f.battery))),
              const Text('🔋 заряд', style: TextStyle(fontSize: 10, color: kMuted)),
            ]),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kPurple, padding: const EdgeInsets.symmetric(vertical: 13)),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('История', style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () { Navigator.pop(sheet);
                WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => HistoryScreen(uuid: f.uuid, name: f.label)))); },
            )),
            const SizedBox(width: 8),
            // §1 request precise location
            IconButton.filledTonal(
              tooltip: 'Обновить точнее',
              icon: const Icon(Icons.my_location, size: 20),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await api.requestPrecise(f.uuid);
                messenger.showSnackBar(const SnackBar(content: Text('Запрошена точная позиция')));
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _renameFriend(_Friend f) async {
    final ctrl = TextEditingController(text: f.label);
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Своё имя для друга'),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
      ],
    ));
    if (name != null && name.isNotEmpty) { await api.setLocalAlias(f.uuid, name); _loadFriends(); }
  }

  void _placeCard(dynamic p) {
    showModalBottomSheet(context: context, builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Text(p['emoji'] ?? '📍', style: const TextStyle(fontSize: 24)),
          title: Text(p['name'] ?? ''), subtitle: Text('радиус ${p['radius']} м')),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.edit), title: const Text('Редактировать'),
          onTap: () { Navigator.pop(sheet);
            WidgetsBinding.instance.addPostFrameCallback((_) => _open(PlacesScreen(editId: p['id']))); }),
      ListTile(leading: const Icon(Icons.delete, color: kRed), title: const Text('Удалить'),
          onTap: () async { Navigator.pop(sheet); await api.deletePlace(p['id']); await tracking.syncGeofences(); _loadPlaces(); }),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    final myMarker = _me == null ? null : Marker(
      point: _me!, width: 70, height: 56,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.my_location, color: Colors.white, size: 28),
        _battTag('Я', _myBattery, me: true),
      ]),
    );

    return Scaffold(
      // Flutter Drawer is on the LEFT by default (opened by the leading hamburger).
      drawer: _drawer(),
      body: _me == null
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: kPurple),
              SizedBox(height: 12),
              Text('Определяем ваше местоположение…'),
            ]))
          : Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(initialCenter: _me!, initialZoom: 15),
                children: [
                  oxTileLayer(),
                  CircleLayer(circles: [
                    for (final p in _places)
                      CircleMarker(point: LatLng(p['lat'], p['lng']),
                        radius: (p['radius'] as num).toDouble(), useRadiusInMeter: true,
                        color: hexColor(p['color']).withValues(alpha: 0.14),
                        borderColor: hexColor(p['color']), borderStrokeWidth: 2),
                  ]),
                  MarkerLayer(markers: [
                    for (final p in _places)
                      Marker(point: LatLng(p['lat'], p['lng']), width: 70, height: 44,
                        child: GestureDetector(onTap: () => _placeCard(p),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 30, height: 30, alignment: Alignment.center,
                              decoration: BoxDecoration(color: kCard, shape: BoxShape.circle,
                                  border: Border.all(color: hexColor(p['color']), width: 2)),
                              child: Text(p['emoji'] ?? '📍', style: const TextStyle(fontSize: 15))),
                            Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 9, color: hexColor(p['color']), fontWeight: FontWeight.bold)),
                          ]))),
                    // §14 clustered friend markers
                    ..._clusterMarkers(),
                    if (myMarker != null) myMarker,
                  ]),
                ],
              ),
              // top bar overlay — pills so controls stay readable on any tiles
              SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 14, 0),
                child: Row(children: [
                  Builder(builder: (ctx) => Material(
                    color: Colors.black.withValues(alpha: .45), shape: const CircleBorder(), clipBehavior: Clip.antiAlias,
                    child: IconButton(icon: const Icon(Icons.menu, size: 22, color: Colors.white),
                        onPressed: () => Scaffold.of(ctx).openDrawer()))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(14)),
                    // force white "Map" on the dark pill regardless of app theme
                    child: DefaultTextStyle(style: const TextStyle(color: Colors.white),
                        child: oxMapWordmark(size: 20)),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ]),
              )),
            ]),
      floatingActionButton: _me == null ? null : Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(heroTag: 'me', backgroundColor: kCard, mini: true,
            onPressed: () { if (_me != null) _map.move(_me!, 15); },
            child: const Icon(Icons.my_location, color: kPurple)),
        const SizedBox(height: 12),
        FloatingActionButton(heroTag: 'refresh', backgroundColor: kPurple,
            onPressed: () { _loadFriends(); _updateMe(); _loadPlaces(); },
            child: const Icon(Icons.refresh)),
      ]),
    );
  }

  Widget _battTag(String? label, int? pct, {bool me = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .75), borderRadius: BorderRadius.circular(7)),
    child: Text('${label != null ? "$label " : ""}🔋${pct ?? "—"}%',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: me ? Colors.white : batteryColor(pct))),
  );

  // §14: group friends whose pins would overlap into one cluster marker.
  // Screen-space clustering using the current camera; re-runs each build.
  List<Marker> _clusterMarkers() {
    // Camera isn't available until FlutterMap has painted once — on the first
    // frame, draw friends unclustered; the next rebuild will cluster them.
    final MapCamera cam;
    try {
      cam = _map.camera;
    } catch (_) {
      return [for (final f in _friends) _friendMarker(f)];
    }
    final used = List.filled(_friends.length, false);
    final markers = <Marker>[];
    for (var i = 0; i < _friends.length; i++) {
      if (used[i]) continue;
      final group = [_friends[i]];
      used[i] = true;
      final pi = cam.latLngToScreenPoint(_friends[i].pos);
      for (var j = i + 1; j < _friends.length; j++) {
        if (used[j]) continue;
        final pj = cam.latLngToScreenPoint(_friends[j].pos);
        if (pi.distanceTo(pj) < 44) { group.add(_friends[j]); used[j] = true; }
      }
      markers.add(group.length == 1 ? _friendMarker(group.first) : _clusterMarker(group));
    }
    return markers;
  }

  Marker _friendMarker(_Friend f) => Marker(
    point: f.pos, width: 70, height: 56,
    child: GestureDetector(onTap: () => _friendCard(f),
      child: Opacity(opacity: _stale(f.updated) ? 0.55 : 1.0,  // §2 dim stale
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (f.battery ?? 100) < 20 ? kRed : kPurple,  // §7 red pin on low batt
              shape: BoxShape.circle, border: Border.all(color: kBg, width: 2)),
            child: Text(f.label.isNotEmpty ? f.label[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          _battTag(null, f.battery),
        ]))),
  );

  Marker _clusterMarker(List<_Friend> group) {
    final center = LatLng(
      group.map((f) => f.pos.latitude).reduce((a, b) => a + b) / group.length,
      group.map((f) => f.pos.longitude).reduce((a, b) => a + b) / group.length);
    return Marker(point: center, width: 44, height: 44,
      child: GestureDetector(onTap: () => _clusterList(group),
        child: Container(alignment: Alignment.center,
          decoration: BoxDecoration(color: kPurple, shape: BoxShape.circle, border: Border.all(color: kBg, width: 2)),
          child: Text('${group.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)))));
  }

  // §14: tap a cluster -> list of friends inside it.
  void _clusterList(List<_Friend> group) {
    showModalBottomSheet(context: context, builder: (sheet) => SafeArea(child: ListView(
      shrinkWrap: true, padding: const EdgeInsets.all(8),
      children: [for (final f in group) ListTile(
        leading: CircleAvatar(backgroundColor: (f.battery ?? 100) < 20 ? kRed : kPurple,
            child: Text(f.label.isNotEmpty ? f.label[0].toUpperCase() : '?')),
        title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('🔋 ${f.battery ?? "—"}% · ${_stale(f.updated) ? "был ${_ago(f.updated)}" : "сейчас"}'),
        onTap: () { Navigator.pop(sheet); _map.move(f.pos, 16);
          WidgetsBinding.instance.addPostFrameCallback((_) => _friendCard(f)); },
      )],
    )));
  }

  Widget _drawer() => Drawer(
    backgroundColor: const Color(0xFF0A0A12),
    child: Column(children: [
      const SizedBox(height: 50),
      Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: Row(children: [
        Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(13)),
            child: const Text('Z', style: TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 10),
        FutureBuilder(future: api.me(), builder: (_, snap) => Text(
            snap.hasData ? (snap.data!['username'] ?? '') : '…',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ])),
      const Divider(height: 1, color: kLine),
      _dItem(Icons.people, kPurple, 'Друзья', () => _open(const FriendsScreen())),
      _dItem(Icons.place, kGreen, 'Мои точки', () => _open(const PlacesScreen())),
      _dItem(Icons.share_location, kAmber, 'Временный доступ', _shareDialog),
      _dItem(Icons.settings, kMuted, 'Настройки', () => _open(const SettingsScreen())),
      const Spacer(),
      _dItem(Icons.logout, kRed, 'Выйти из аккаунта', _logout),
      const SizedBox(height: 12),
    ]),
  );

  Widget _dItem(IconData ic, Color c, String label, VoidCallback onTap) => ListTile(
    leading: Icon(ic, color: c, size: 21),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    onTap: () { Navigator.pop(context); onTap(); },
  );

  // §13: temporarily share my location with any user (uuid or username) for N hours.
  Future<void> _shareDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    int hours = 2;
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(
      builder: (_, setD) => AlertDialog(
        title: const Text('Временный доступ'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Username или UUID')),
          const SizedBox(height: 16),
          const Text('На сколько:', style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final h in [1, 2, 8])
              ChoiceChip(label: Text('$h ч'), selected: hours == h,
                  selectedColor: kPurple, onSelected: (_) => setD(() => hours = h)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Поделиться')),
        ],
      ),
    ));
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final done = await api.shareWith(ctrl.text.trim(), hours);
      messenger.showSnackBar(SnackBar(
          content: Text(done ? 'Доступ выдан на $hours ч' : 'Пользователь не найден')));
    }
  }
}
