import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import 'common.dart';

/// Totais de horas por projeto e por funcionário (só gestores).
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.api});

  final Api api;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late Future<(List<ReportRow>, List<ReportRow>)> data = _load();

  Future<(List<ReportRow>, List<ReportRow>)> _load() async =>
      (await widget.api.reportByProject(), await widget.api.reportByUser());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Por projeto'), Tab(text: 'Por funcionário')]),
          Expanded(
            child: FutureView(
              future: data,
              onRetry: () => setState(() => data = _load()),
              builder: (result) => RefreshIndicator(
                onRefresh: () async {
                  setState(() => data = _load());
                  await data;
                },
                child: TabBarView(children: [_ReportList(rows: result.$1), _ReportList(rows: result.$2)]),
              ),
            ),
          ),
        ],
      ),
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
        Text('Total geral: ${formatHours(total)}', style: Theme.of(context).textTheme.titleMedium),
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
