import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Single source of truth for the server address (UI + headless isolate).
// Real device on same wifi -> PC's LAN IP.
const kApiBase = 'https://locator.zxr.sh';

// Flips to true when the server rejects our token (401) — e.g. this device was
// evicted by a login elsewhere. The app root listens and returns to login.
final sessionExpired = ValueNotifier<bool>(false);

/// Thin client for the 0xMap FastAPI backend.
/// Set [base] to your server (use 10.0.2.2 for Android emulator -> host).
class Api {
  Api(this.base);
  final String base;
  // encryptedSharedPreferences: survives app restarts reliably on Android.
  final _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  String? _token;

  Future<String?> get token async => _token ??= await _store.read(key: 'token');

  // Local per-friend nicknames (#4) — stored on device, not sent to server.
  Future<String?> localAlias(String uuid) => _store.read(key: 'alias_$uuid');
  Future<void> setLocalAlias(String uuid, String name) =>
      _store.write(key: 'alias_$uuid', value: name);

  // Local preferences (e.g. chosen map tiles).
  Future<String?> getPref(String key) => _store.read(key: 'pref_$key');
  Future<void> setPref(String key, String value) => _store.write(key: 'pref_$key', value: value);

  Future<Map<String, String>> _authHeaders() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await token}',
      };

  Future<void> _saveToken(String t) async {
    _token = t;
    await _store.write(key: 'token', value: t);
  }

  Future<void> logout() async {
    _token = null;
    await _store.delete(key: 'token');
  }

  // Detect an evicted/expired session (401 on an authenticated call) and signal
  // the UI to return to login. Call on responses from authed requests.
  void _check401(int status) {
    if (status == 401) {
      _token = null;
      _store.delete(key: 'token');
      sessionExpired.value = true;
    }
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final r = await http.post(Uri.parse('$base/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}));
    if (r.statusCode != 200) throw Exception(r.body);
    final data = jsonDecode(r.body);
    await _saveToken(data['token']);
    return data;
  }

  Future<void> login(String username, String password) async {
    // OAuth2 password form
    final r = await http.post(Uri.parse('$base/auth/login'),
        body: {'username': username, 'password': password});
    if (r.statusCode != 200) throw Exception(r.body);
    await _saveToken(jsonDecode(r.body)['token']);
  }

  Future<void> pushLocation(double lat, double lng, {int? battery, String? moving}) async {
    await http.post(Uri.parse('$base/location'),
        headers: await _authHeaders(),
        body: jsonEncode({'lat': lat, 'lng': lng, 'battery': battery, 'moving_state': moving}));
  }

  Future<Map<String, dynamic>> me() async {
    final r = await http.get(Uri.parse('$base/me'), headers: await _authHeaders());
    _check401(r.statusCode);
    if (r.statusCode != 200) return {};
    return jsonDecode(r.body);
  }

  Future<List<dynamic>> friends() async {
    final r = await http.get(Uri.parse('$base/friends'), headers: await _authHeaders());
    _check401(r.statusCode);
    if (r.statusCode != 200) return [];
    return jsonDecode(r.body);
  }

  /// Add by username or UUID. Returns false if the target wasn't found.
  Future<bool> addFriend(String target) async {
    final r = await http.post(Uri.parse('$base/friends/$target'), headers: await _authHeaders());
    return r.statusCode == 200;
  }

  Future<void> acceptFriend(String requesterUuid) async {
    await http.post(Uri.parse('$base/friends/$requesterUuid/accept'), headers: await _authHeaders());
  }

  Future<void> removeFriend(String uuid) async {
    await http.delete(Uri.parse('$base/friends/$uuid'), headers: await _authHeaders());
  }

  Future<Map<String, dynamic>?> location(String uuid) async {
    final r = await http.get(Uri.parse('$base/location/$uuid'), headers: await _authHeaders());
    return r.statusCode == 200 ? jsonDecode(r.body) : null;
  }

  Future<List<dynamic>> history(String uuid, {String? day}) async {
    final q = day != null ? '?day=$day' : '';
    final r = await http.get(Uri.parse('$base/history/$uuid$q'), headers: await _authHeaders());
    return r.statusCode == 200 ? jsonDecode(r.body) : [];
  }


  Future<void> changePassword(String newPassword) async {
    await http.put(Uri.parse('$base/settings/password'),
        headers: await _authHeaders(), body: jsonEncode({'new_password': newPassword}));
  }

  Future<void> setPushToken(String token) async {
    await http.put(Uri.parse('$base/device/token'),
        headers: await _authHeaders(), body: jsonEncode({'push_token': token}));
  }

  Future<List<dynamic>> places() async {
    final r = await http.get(Uri.parse('$base/places'), headers: await _authHeaders());
    return jsonDecode(r.body);
  }

  // Friends' places — registered as geofences so I'm reported when I cross them.
  Future<List<dynamic>> friendsPlaces() async {
    final r = await http.get(Uri.parse('$base/places/friends'), headers: await _authHeaders());
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> createPlace(String name, String emoji, String color, double lat, double lng, int radius) async {
    final r = await http.post(Uri.parse('$base/places'),
        headers: await _authHeaders(),
        body: jsonEncode({'name': name, 'emoji': emoji, 'color': color, 'lat': lat, 'lng': lng, 'radius': radius}));
    return jsonDecode(r.body);
  }

  Future<void> updatePlace(String id, String name, String emoji, String color, double lat, double lng, int radius) async {
    await http.put(Uri.parse('$base/places/$id'),
        headers: await _authHeaders(),
        body: jsonEncode({'name': name, 'emoji': emoji, 'color': color, 'lat': lat, 'lng': lng, 'radius': radius}));
  }

  Future<void> deletePlace(String id) async {
    await http.delete(Uri.parse('$base/places/$id'), headers: await _authHeaders());
  }

  Future<List<dynamic>> stops(String uuid, {String? day}) async {
    final u = day != null ? '$base/history/$uuid/stops?day=$day' : '$base/history/$uuid/stops';
    final r = await http.get(Uri.parse(u), headers: await _authHeaders());
    return jsonDecode(r.body);
  }

  Future<void> geofenceEvent(String placeId, String action) async {
    await http.post(Uri.parse('$base/geofence'),
        headers: await _authHeaders(), body: jsonEncode({'place_id': placeId, 'action': action}));
  }

  // §1 ask a friend's device to boost accuracy briefly
  Future<void> requestPrecise(String uuid) async {
    await http.post(Uri.parse('$base/request-precise/$uuid'), headers: await _authHeaders());
  }

  // §13 temporary share
  Future<bool> shareWith(String target, int hours) async {
    final r = await http.post(Uri.parse('$base/share/$target?hours=$hours'), headers: await _authHeaders());
    return r.statusCode == 200;
  }

  Future<void> revokeShare(String uuid) async {
    await http.delete(Uri.parse('$base/share/$uuid'), headers: await _authHeaders());
  }

  Future<List<dynamic>> shares() async {
    final r = await http.get(Uri.parse('$base/shares'), headers: await _authHeaders());
    return jsonDecode(r.body);
  }
}
