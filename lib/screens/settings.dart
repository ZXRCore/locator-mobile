import 'package:flutter/material.dart';
import '../main.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _changePassword() async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новый пароль'),
        content: TextField(controller: ctrl, obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Сменить')),
        ],
      ),
    );
    if (pw != null && pw.isNotEmpty) {
      await api.changePassword(pw);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль изменён')));
    }
  }

  Widget _hdr(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
    child: Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 2, color: kMuted, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(children: [
        // UI size: 9-step slider (1 small, 5 medium, 9 large)
        _hdr('РАЗМЕР ИНТЕРФЕЙСА'),
        ValueListenableBuilder<int>(
          valueListenable: uiSize,
          builder: (_, step, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(children: [
              Row(children: [
                const Text('A', style: TextStyle(fontSize: 12, color: kMuted)),
                Expanded(child: Slider(
                  value: step.toDouble(), min: 1, max: 9, divisions: 8, activeColor: kPurple,
                  onChanged: (v) async { uiSize.value = v.round(); await api.setPref('ui_size', v.round().toString()); },
                )),
                const Text('A', style: TextStyle(fontSize: 20, color: kMuted, fontWeight: FontWeight.w700)),
              ]),
              Text(step == 1 ? 'Маленький' : step == 9 ? 'Большой' : step == 5 ? 'Средний' : '$step / 9',
                  style: const TextStyle(color: kPurple, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        // Theme: light / dark / system (§6)
        _hdr('ТЕМА'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (_, current, __) => RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (v) async {
              if (v == null) return;
              themeMode.value = v;
              final key = kThemeModes.entries.firstWhere((e) => e.value == v).key;
              await api.setPref('theme', key);
            },
            child: const Column(children: [
              RadioListTile<ThemeMode>(title: Text('Светлая'), value: ThemeMode.light, activeColor: kPurple),
              RadioListTile<ThemeMode>(title: Text('Тёмная'), value: ThemeMode.dark, activeColor: kPurple),
              RadioListTile<ThemeMode>(title: Text('Как на телефоне'), value: ThemeMode.system, activeColor: kPurple),
            ]),
          ),
        ),
        // Map tiles — OSM first (default) per theme order
        _hdr('КАРТА'),
        ValueListenableBuilder<String>(
          valueListenable: tileChoice,
          builder: (_, current, __) => RadioGroup<String>(
            groupValue: current,
            onChanged: (v) async { if (v == null) return; tileChoice.value = v; await api.setPref('tiles', v); },
            child: Column(children: [
              for (final e in kTileSources.entries)
                RadioListTile<String>(title: Text(e.value.name), value: e.key, activeColor: kPurple),
            ]),
          ),
        ),
        _hdr('АККАУНТ'),
        ListTile(leading: const Icon(Icons.lock, color: kPurple), title: const Text('Сменить пароль'), onTap: _changePassword),
        _hdr('О ПРИЛОЖЕНИИ'),
        Center(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(children: [oxMapWordmark(size: 20), const SizedBox(height: 4),
            const Text('v1.0.0', style: TextStyle(color: kMuted, fontSize: 12))]))),
      ]),
    );
  }
}
