import 'package:flutter/material.dart';

import '../api.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../download.dart';
import 'common.dart';
import 'project_status.dart';

/// Totais de horas por projeto e por funcionário (só gestores).
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.api});

  final Api api;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  Period period = Period.thisMonth();
  late Future<(List<Project>, List<ReportRow>)> data = _load();

  Future<(List<Project>, List<ReportRow>)> _load() async =>
      (await widget.api.reportByProject(period: period), await widget.api.reportByUser(period: period));

  void _setPeriod(Period p) => setState(() {
        period = p;
        data = _load();
      });

  /// Baixa em CSV os lançamentos do período selecionado (para Excel ou importação no SAP).
  Future<void> _export() async {
    final p = period;
    await runWithFeedback(context, () async {
      final bytes = await widget.api.exportEntriesCsv(period: p);
      downloadFile(bytes, 'horas_${p.fileSuffix}.csv');
    }, 'Arquivo de horas baixado.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Por projeto'), Tab(text: 'Por funcionário')]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: PeriodSelector(period: period, onChanged: _setPeriod)),
              TextButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportar CSV'),
              ),
            ]),
          ),
          Expanded(
            child: FutureView(
              future: data,
              onRetry: () => setState(() => data = _load()),
              builder: (result) => RefreshIndicator(
                onRefresh: () async {
                  setState(() => data = _load());
                  await data;
                },
                child: TabBarView(children: [_ProjectReport(projects: result.$1), _ReportList(rows: result.$2)]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Projetos mais críticos primeiro: estourados/vencidos, depois perto do limite.
class _ProjectReport extends StatelessWidget {
  const _ProjectReport({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sorted = [...projects]..sort((a, b) {
        final byHealth = projectHealth(b, today).index.compareTo(projectHealth(a, today).index);
        return byHealth != 0 ? byHealth : b.usedHours.compareTo(a.usedHours);
      });
    final total = projects.fold<double>(0, (s, p) => s + p.periodHours);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text('Horas no período: ${formatHours(total)}', style: Theme.of(context).textTheme.titleMedium),
        Text('Saldo e cores consideram todas as horas do projeto, não só o período.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        const HealthLegend(),
        const SizedBox(height: 8),
        for (final p in sorted)
          ProjectStatusCard(project: p, note: 'No período: ${formatHours(p.periodHours)}'),
      ],
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.rows});

  final List<ReportRow> rows;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(0, (s, r) => s + r.totalHours);
    final max = rows.fold<double>(0, (m, r) => r.totalHours > m ? r.totalHours : m);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Horas no período: ${formatHours(total)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final r in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(r.label, style: Theme.of(context).textTheme.titleSmall)),
                    Text(formatHours(r.totalHours), style: Theme.of(context).textTheme.titleSmall),
                  ]),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: max == 0 ? 0 : r.totalHours / max, minHeight: 6),
                  const SizedBox(height: 4),
                  Text(r.detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
