import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../main.dart';
import '../theme.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<dynamic> _friends = [];
  Map<String, String> _aliases = {}; // uuid -> local nickname
  String _myUuid = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await api.me();
    final f = await api.friends();
    final aliases = <String, String>{};
    for (final fr in f) {
      final a = await api.localAlias(fr['uuid']);
      if (a != null) aliases[fr['uuid']] = a;
    }
    if (mounted) setState(() { _friends = f; _myUuid = me['uuid']; _aliases = aliases; });
  }

  Future<void> _rename(dynamic f) async {
    final ctrl = TextEditingController(text: _aliases[f['uuid']] ?? f['name'] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Своё имя для друга'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Как показывать')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) { await api.setLocalAlias(f['uuid'], name); _load(); }
  }

  Future<void> _remove(dynamic f) async {
    final label = _aliases[f['uuid']] ?? f['name'] ?? f['uuid'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить друга?'),
        content: Text('$label больше не будет видеть вашу геолокацию, а вы — его.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) { await api.removeFriend(f['uuid']); _load(); }
  }

  Future<void> _addByUuid() async {
    final ctrl = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить друга'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Username или UUID')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Добавить')),
        ],
      ),
    );
    if (target != null && target.isNotEmpty) {
      final ok = await api.addFriend(target);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пользователь не найден')));
      }
      _load();
    }
  }

  void _showMyQr() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Мой QR'),
        content: SizedBox(
          width: 220, height: 220,
          child: QrImageView(data: _myUuid, backgroundColor: Colors.white),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
      ),
    );
  }

  Future<void> _scanQr() async {
    final uuid = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Сканировать QR')),
        body: MobileScanner(onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null && code.isNotEmpty) Navigator.pop(context, code);
        }),
      )),
    );
    if (uuid != null && uuid.isNotEmpty) {
      await api.addFriend(uuid);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Друзья')),
      body: Column(children: [
        // My UUID — tap to copy, this is how friends add me
        Card(
          margin: const EdgeInsets.all(12),
          child: ListTile(
            title: const Text('Мой UUID'),
            subtitle: Text(_myUuid, style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.qr_code), tooltip: 'Показать QR', onPressed: _showMyQr),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _myUuid));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                },
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final f in _friends)
              ListTile(
                leading: const Icon(Icons.person, color: kPurple),
                // show local alias if set, with real name underneath
                title: Text(_aliases[f['uuid']] ?? f['name'] ?? f['uuid']),
                subtitle: Text(_aliases.containsKey(f['uuid'])
                    ? '${f['name']} · ${f['status']}'
                    : f['status']),
                onLongPress: f['status'] == 'accepted' ? () => _rename(f) : null,
                trailing: f['incoming'] == true
                    ? FilledButton(
                        onPressed: () async { await api.acceptFriend(f['uuid']); _load(); },
                        child: const Text('Принять'))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (f['status'] == 'accepted')
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            tooltip: 'Своё имя',
                            onPressed: () => _rename(f),
                          ),
                        IconButton(
                          icon: const Icon(Icons.person_remove, size: 20, color: Colors.redAccent),
                          tooltip: 'Удалить',
                          onPressed: () => _remove(f),
                        ),
                      ]),
              ),
          ]),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'scan',
            backgroundColor: kPurple,
            onPressed: _scanQr,
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            backgroundColor: kPurple,
            onPressed: _addByUuid,
            child: const Icon(Icons.person_add),
          ),
        ],
      ),
    );
  }
}
