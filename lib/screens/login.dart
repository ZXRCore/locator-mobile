import 'package:flutter/material.dart';
import '../main.dart';
import '../theme.dart';
import 'map.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_register) {
        await api.register(_user.text.trim(), _pass.text);
      } else {
        await api.login(_user.text.trim(), _pass.text);
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MapScreen()));
      }
    } catch (e) {
      setState(() => _error = 'Не удалось войти. Проверь логин/пароль.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                oxMapWordmark(size: 40),
                const SizedBox(height: 32),
                TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 12),
                TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_register ? 'Зарегистрироваться' : 'Войти'),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'У меня есть аккаунт' : 'Создать аккаунт'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
