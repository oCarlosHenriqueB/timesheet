import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'dashboard_screen.dart';
import 'help_screen.dart';
import 'history_screen.dart';
import 'management_screen.dart';
import 'projects_screen.dart';
import 'reports_screen.dart';
import 'timesheet_screen.dart';

enum AppPage {
  dashboard('Dashboard', Icons.space_dashboard_outlined),
  timesheet('Apontamento', Icons.more_time),
  history('Histórico', Icons.history),
  projects('Projetos', Icons.folder_outlined),
  reports('Relatórios', Icons.bar_chart, managerOnly: true),
  management('Gestão', Icons.admin_panel_settings_outlined, managerOnly: true),
  help('Ajuda', Icons.help_outline);

  const AppPage(this.label, this.icon, {this.managerOnly = false});
  final String label;
  final IconData icon;
  final bool managerOnly;
}

/// Estrutura do app logado: menu lateral fixo + conteúdo da página escolhida.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.user, required this.onLogout, required this.onUserChanged});

  final Api api;
  final User user;
  final VoidCallback onLogout;
  final ValueChanged<User> onUserChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage page = AppPage.dashboard;

  void _go(AppPage p) => setState(() => page = p);

  Future<void> _toggleTimer(bool value) async {
    try {
      widget.onUserChanged(await widget.api.setUseTimer(value));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _content() {
    final api = widget.api;
    final user = widget.user;
    return switch (page) {
      AppPage.dashboard => DashboardScreen(api: api, user: user, onNavigate: _go),
      AppPage.timesheet => TimesheetScreen(api: api, user: user),
      AppPage.history => HistoryScreen(api: api, user: user),
      AppPage.projects => ProjectsScreen(api: api, user: user),
      AppPage.reports => ReportsScreen(api: api),
      AppPage.management => ManagementScreen(api: api, user: user),
      AppPage.help => HelpScreen(user: user),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pages = AppPage.values.where((p) => !p.managerOnly || widget.user.isManager).toList();
    final compact = MediaQuery.sizeOf(context).width < 1000;
    return Scaffold(
      body: Row(children: [
        _Sidebar(
          pages: pages,
          current: page,
          compact: compact,
          user: widget.user,
          onSelect: _go,
          onLogout: widget.onLogout,
          onToggleTimer: _toggleTimer,
        ),
        // A chave faz cada página começar do zero (e recarregar) ao ser aberta.
        Expanded(child: KeyedSubtree(key: ValueKey(page), child: _content())),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.pages,
    required this.current,
    required this.compact,
    required this.user,
    required this.onSelect,
    required this.onLogout,
    required this.onToggleTimer,
  });

  final List<AppPage> pages;
  final AppPage current;
  final bool compact;
  final User user;
  final ValueChanged<AppPage> onSelect;
  final VoidCallback onLogout;
  final ValueChanged<bool> onToggleTimer;

  @override
  Widget build(BuildContext context) {
    final main = pages.where((p) => !p.managerOnly);
    final manager = pages.where((p) => p.managerOnly);
    return Container(
      width: compact ? 76 : 236,
      color: AppColors.navy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 0 : 20, 22, 12, 22),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            // Espaço reservado para o logo da empresa (quando houver autorização de uso).
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.schedule, color: Colors.white, size: 20),
            ),
            if (!compact) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Timesheet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Horas por projeto', style: TextStyle(color: AppColors.sidebarText, fontSize: 12)),
                ]),
              ),
            ],
          ]),
        ),
        for (final p in main) _NavItem(page: p, selected: p == current, compact: compact, onTap: () => onSelect(p)),
        if (manager.isNotEmpty) ...[
          if (!compact)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 12, 6),
              child: Text('GESTÃO', style: TextStyle(color: AppColors.sidebarText, fontSize: 11, letterSpacing: 1)),
            )
          else
            const SizedBox(height: 16),
          for (final p in manager)
            _NavItem(page: p, selected: p == current, compact: compact, onTap: () => onSelect(p)),
        ],
        const Spacer(),
        const Divider(color: AppColors.navyLight, height: 1),
        PopupMenuButton<String>(
          tooltip: 'Conta e preferências',
          offset: const Offset(0, -110),
          onSelected: (v) => v == 'logout' ? onLogout() : onToggleTimer(!user.useTimer),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: 'timer', checked: user.useTimer, child: const Text('Usar cronômetro')),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(leading: Icon(Icons.logout), title: Text('Sair'), dense: true, contentPadding: EdgeInsets.zero),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.navyLight,
                child: Text(user.name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(user.roleLabel, style: const TextStyle(color: AppColors.sidebarText, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.more_vert, color: AppColors.sidebarText, size: 18),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.page, required this.selected, required this.compact, required this.onTap});

  final AppPage page;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.sidebarText;
    final item = Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        hoverColor: AppColors.navyLight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Icon(page.icon, color: color, size: 20),
            if (!compact) ...[
              const SizedBox(width: 12),
              Text(page.label, style: TextStyle(color: color, fontWeight: selected ? FontWeight.w600 : null)),
            ],
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: compact ? Tooltip(message: page.label, child: item) : item,
    );
  }
}
