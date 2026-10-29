import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, required this.onLogin});

  final Api api;
  final void Function(String token, User user) onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final (token, user) = await widget.api.login(email.text, password.text);
      widget.onLogin(token, user);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Timesheet', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                const Text('Horas por projeto', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder()),
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: Text(busy ? 'Entrando…' : 'Entrar'),
                ),
                if (busy) ...[
                  const SizedBox(height: 8),
                  Text(
                    'O servidor gratuito dorme quando fica parado; o primeiro acesso pode levar até 1 minuto.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
