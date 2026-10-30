import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';
import '../widgets/project_status.dart';
import '../widgets/team_grid.dart';
import 'shell.dart';

/// Tela inicial: horas do dia, da semana e do mês, projetos em andamento e atividades recentes.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api, required this.user, required this.onNavigate});

  final Api api;
  final User user;
  final ValueChanged<AppPage> onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final today = DateUtils.dateOnly(DateTime.now());
  late Future<DashboardData> data = widget.api.dashboard(today);

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: data,
      onRetry: () => setState(() => data = widget.api.dashboard(today)),
      builder: (d) => PageBody(children: [
        PageHeader(
          title: 'Olá, ${widget.user.name}',
          subtitle: toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR').format(today)),
          actions: [
            FilledButton.icon(
              onPressed: () => widget.onNavigate(AppPage.timesheet),
              icon: const Icon(Icons.add),
              label: const Text('Novo apontamento'),
            ),
          ],
        ),
        ResponsiveRow(children: [
          KpiCard(label: 'Horas hoje', value: formatHours(d.todayHours), icon: Icons.today, caption: formatDate(today)),
          KpiCard(label: 'Horas na semana', value: formatHours(d.weekHours), icon: Icons.date_range, caption: 'Segunda a domingo'),
          KpiCard(
            label: 'Horas no mês',
            value: formatHours(d.monthHours),
            icon: Icons.calendar_month,
            caption: toBeginningOfSentenceCase(DateFormat('MMMM', 'pt_BR').format(today)),
          ),
          if (d.teamWeekHours != null)
            KpiCard(
              label: 'Equipe na semana',
              value: formatHours(d.teamWeekHours!),
              icon: Icons.groups_outlined,
              caption: 'Todos os projetistas',
            )
          else
            KpiCard(
              label: 'Projetos em andamento',
              value: '${d.projects.length}',
              icon: Icons.folder_open,
              caption: 'Últimos 30 dias',
            ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final week = SectionCard(
            title: 'Horas da semana',
            child: ColumnChart(
              items: [
                for (final (day, h) in d.weekDays) (DateFormat('EEE', 'pt_BR').format(day).replaceAll('.', ''), h),
              ],
              highlight: d.weekDays.indexWhere((w) => DateUtils.isSameDay(w.$1, today)),
            ),
          );
          final projects = _ProjectsCard(projects: d.projects, onOpen: () => widget.onNavigate(AppPage.projects));
          if (c.maxWidth < 900) return Column(children: [week, const SizedBox(height: 16), projects]);
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: week),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: projects),
            ]),
          );
        }),
        if (widget.user.isManager) ...[
          const SizedBox(height: 16),
          TeamGridCard(
            api: widget.api,
            actions: [
              TextButton(onPressed: () => widget.onNavigate(AppPage.management), child: const Text('Abrir em Gestão')),
            ],
          ),
        ],
        const SizedBox(height: 16),
        SectionCard(
          title: 'Atividades recentes',
          actions: [
            TextButton(onPressed: () => widget.onNavigate(AppPage.history), child: const Text('Ver histórico')),
          ],
          padding: const EdgeInsets.only(bottom: 8),
          child: d.recent.isEmpty
              ? const EmptyState(message: 'Nenhum apontamento ainda.')
              : ScrollableTable(
                  table: DataTable(columns: const [
                    DataColumn(label: Text('Data')),
                    DataColumn(label: Text('Projeto')),
                    DataColumn(label: Text('Atividade')),
                    DataColumn(label: Text('Horário')),
                    DataColumn(label: Text('Horas'), numeric: true),
                    DataColumn(label: Text('Status')),
                  ], rows: [
                    for (final e in d.recent)
                      DataRow(cells: [
                        DataCell(Text(formatDate(e.date))),
                        DataCell(Text(e.projectLabel)),
                        DataCell(Text(e.activityName ?? '—')),
                        DataCell(Text(e.timeRange)),
                        DataCell(Text(formatNumber(e.hours))),
                        DataCell(StatusChip(e.status)),
                      ]),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({required this.projects, required this.onOpen});

  final List<Project> projects;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sorted = [...projects]
      ..sort((a, b) => projectHealth(b, today).index.compareTo(projectHealth(a, today).index));
    return SectionCard(
      title: 'Projetos em andamento',
      actions: [TextButton(onPressed: onOpen, child: const Text('Ver todos'))],
      child: sorted.isEmpty
          ? const EmptyState(message: 'Sem lançamentos nos últimos 30 dias.', icon: Icons.folder_off_outlined)
          : Column(children: [
              for (final p in sorted.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(
                      width: 4,
                      height: 34,
                      decoration: BoxDecoration(
                        color: projectHealth(p, today).color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(hoursLabel(p), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
            ]),
    );
  }
}
