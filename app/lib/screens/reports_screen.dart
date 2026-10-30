import 'package:flutter/material.dart';

import '../api.dart';
import '../budget.dart';
import '../download.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';
import '../widgets/project_status.dart';

/// Relatórios do gestor: horas por projeto, atividade e funcionário no período, com gráfico e tabela.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.api});

  final Api api;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period period = Period.thisMonth();
  late Future<(List<Project>, List<ReportRow>, List<ReportRow>)> data = _load();

  Future<(List<Project>, List<ReportRow>, List<ReportRow>)> _load() async => (
        await widget.api.reportByProject(period: period),
        await widget.api.reportByActivity(period: period),
        await widget.api.reportByUser(period: period),
      );

  void _setPeriod(Period p) => setState(() {
        period = p;
        data = _load();
      });

  /// Baixa em CSV os lançamentos do período (para Excel ou importação no SAP).
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
      length: 3,
      child: PageBody(children: [
        PageHeader(
          title: 'Relatórios',
          subtitle: 'Horas por projeto, atividade e período',
          actions: [
            OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download_outlined), label: const Text('Exportar CSV')),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              PeriodSelector(period: period, onChanged: _setPeriod),
              const Spacer(),
              const SizedBox(
                width: 460,
                child: TabBar(tabs: [Tab(text: 'Por projeto'), Tab(text: 'Por atividade'), Tab(text: 'Por funcionário')]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FutureView(
          future: data,
          onRetry: () => setState(() => data = _load()),
          builder: (r) {
            final (projects, activities, users) = r;
            // Altura fixa: as abas precisam de um tamanho definido dentro da página com rolagem.
            return SizedBox(
              height: 760,
              child: TabBarView(children: [
                _ProjectsReport(projects: projects),
                _RowsReport(rows: activities, title: 'Atividade', detailTitle: 'Projetos'),
                _RowsReport(rows: users, title: 'Funcionário', detailTitle: 'Projetos'),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

class _ProjectsReport extends StatelessWidget {
  const _ProjectsReport({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final withHours = projects.where((p) => p.periodHours > 0).toList()
      ..sort((a, b) => b.periodHours.compareTo(a.periodHours));
    final total = withHours.fold<double>(0, (s, p) => s + p.periodHours);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionCard(
          title: 'Horas no período · ${formatHours(total)}',
          child: withHours.isEmpty
              ? const EmptyState(message: 'Sem horas no período.')
              : BarList(items: [for (final p in withHours) (p.label, p.periodHours, null)]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Situação dos projetos (saldo considera todas as horas)',
          padding: const EdgeInsets.only(bottom: 8),
          child: ScrollableTable(
            table: DataTable(columns: const [
              DataColumn(label: Text('Projeto')),
              DataColumn(label: Text('No período'), numeric: true),
              DataColumn(label: Text('Pessoas'), numeric: true),
              DataColumn(label: Text('Horas')),
              DataColumn(label: Text('Prazo')),
            ], rows: [
              for (final p in projects)
                DataRow(cells: [
                  DataCell(Text(p.label)),
                  DataCell(Text(formatNumber(p.periodHours))),
                  DataCell(Text('${p.people}')),
                  DataCell(StatusBadge(health: hoursHealth(p), label: hoursLabel(p))),
                  DataCell(StatusBadge(health: dateHealth(p, today), label: dateLabel(p, today))),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RowsReport extends StatelessWidget {
  const _RowsReport({required this.rows, required this.title, required this.detailTitle});

  final List<ReportRow> rows;
  final String title;
  final String detailTitle;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(0, (s, r) => s + r.totalHours);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionCard(
          title: 'Horas no período · ${formatHours(total)}',
          child: rows.isEmpty
              ? const EmptyState(message: 'Sem horas no período.')
              : BarList(items: [for (final r in rows.where((r) => r.totalHours > 0)) (r.label, r.totalHours, r.detail)]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.only(bottom: 8),
          child: ScrollableTable(
            table: DataTable(columns: [
              DataColumn(label: Text(title)),
              const DataColumn(label: Text('Horas'), numeric: true),
              const DataColumn(label: Text('% do total'), numeric: true),
              DataColumn(label: Text(detailTitle)),
            ], rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(r.label)),
                  DataCell(Text(formatNumber(r.totalHours))),
                  DataCell(Text(total == 0 ? '—' : '${(r.totalHours / total * 100).round()}%')),
                  DataCell(Text(r.detail)),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
