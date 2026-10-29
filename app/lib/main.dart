import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'pages/admin_page.dart';
import 'pages/entries_page.dart';
import 'pages/login_page.dart';
import 'pages/reports_page.dart';

void main() => runApp(const TimesheetApp());

class TimesheetApp extends StatelessWidget {
  const TimesheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timesheet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0099CC), useMaterial3: true),
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
    if (u == null) return LoginPage(api: api, onLogin: _onLogin);
    return HomeShell(api: api, user: u, onLogout: _logout);
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api, required this.user, required this.onLogout});

  final Api api;
  final User user;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final manager = widget.user.isManager;
    final pages = <(String, IconData, Widget)>[
      ('Minhas horas', Icons.schedule, EntriesPage(api: widget.api)),
      if (manager) ('Relatórios', Icons.bar_chart, ReportsPage(api: widget.api)),
      if (manager) ('Cadastros', Icons.settings, AdminPage(api: widget.api)),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: Text(pages[index].$1),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: Text(widget.user.name))),
          IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: Row(
        children: [
          if (wide && pages.length > 1)
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [
                for (final p in pages) NavigationRailDestination(icon: Icon(p.$2), label: Text(p.$1)),
              ],
            ),
          Expanded(child: pages[index].$3),
        ],
      ),
      bottomNavigationBar: !wide && pages.length > 1
          ? NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [for (final p in pages) NavigationDestination(icon: Icon(p.$2), label: p.$1)],
            )
          : null,
    );
  }
}
