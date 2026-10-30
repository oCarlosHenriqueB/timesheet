import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

void main() => runApp(const TimesheetApp());

class TimesheetApp extends StatelessWidget {
  const TimesheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timesheet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Calendários, botões e textos padrão do Flutter em português.
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const SessionGate(),
    );
  }
}

/// Decide entre a tela de login e o app, e guarda o token entre recargas.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  static const _tokenKey = 'token';
  final api = Api();
  User? user;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(_tokenKey);
    if (api.token != null) {
      try {
        user = await api.me();
      } catch (_) {
        api.token = null;
        await prefs.remove(_tokenKey);
      }
    }
    setState(() => loading = false);
  }

  Future<void> _onLogin(String token, User u) async {
    api.token = token;
    (await SharedPreferences.getInstance()).setString(_tokenKey, token);
    setState(() => user = u);
  }

  Future<void> _logout() async {
    try {
      await api.logout();
    } catch (_) {}
    api.token = null;
    (await SharedPreferences.getInstance()).remove(_tokenKey);
    setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final u = user;
    if (u == null) return LoginScreen(api: api, onLogin: _onLogin);
    return AppShell(api: api, user: u, onLogout: _logout, onUserChanged: (u) => setState(() => user = u));
  }
}
