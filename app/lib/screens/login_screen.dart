import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/password_field.dart';

/// Login com painel institucional à esquerda (desktop) e formulário à direita.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onLogin});

  final Api api;
  final void Function(String token, User user) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: Row(children: [
        if (wide) const Expanded(flex: 5, child: _BrandPanel()),
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _form(context),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Entrar', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Acesse com seu e-mail corporativo.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
      const SizedBox(height: 28),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
      ),
      const SizedBox(height: 14),
      PasswordField(
        controller: password,
        label: 'Senha',
        prefixIcon: const Icon(Icons.lock_outline),
        onSubmitted: (_) => _submit(),
      ),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 22),
      FilledButton(onPressed: busy ? null : _submit, child: Text(busy ? 'Entrando…' : 'Entrar')),
      if (busy) ...[
        const SizedBox(height: 10),
        Text(
          'O servidor de testes dorme quando fica parado; o primeiro acesso pode levar até 1 minuto.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    ]);
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: AppColors.sidebarText, fontSize: 15, height: 1.4);
    Widget bullet(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: muted)),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyLight],
        ),
      ),
      padding: const EdgeInsets.all(56),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.schedule, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text('Timesheet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        const Text(
          'Controle de horas\npor projeto',
          style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w700, height: 1.15),
        ),
        const SizedBox(height: 16),
        const Text('Registre, acompanhe e reporte as horas da equipe de projetos em um só lugar.', style: muted),
        const SizedBox(height: 32),
        bullet(Icons.more_time, 'Apontamento rápido por início e fim, com cronômetro opcional'),
        bullet(Icons.folder_outlined, 'Horas previstas e realizadas por projeto, com alertas de prazo'),
        bullet(Icons.bar_chart, 'Relatórios por projeto, atividade e período, com exportação'),
        const Spacer(),
        const Text('Protótipo · dados fictícios', style: TextStyle(color: AppColors.sidebarText, fontSize: 12)),
      ]),
    );
  }
}
