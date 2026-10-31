import 'package:flutter/material.dart';

import '../api.dart';
import '../dialogs/entry_dialog.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';

/// Histórico de apontamentos em tabela, com filtros por período, projeto e status.
/// O gestor também escolhe de quem ver (ele mesmo, a equipe toda ou uma pessoa).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api, required this.user});

  final Api api;
  final User user;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// De quem o gestor está vendo: null = só ele; -1 = equipe toda; id = uma pessoa.
const _team = -1;

class _HistoryScreenState extends State<HistoryScreen> {
  Period period = Period.thisMonth();
  int? projectId;
  EntryStatus? status;
  int? person;

  late Future<(List<Project>, List<Activity>, List<User>)> lookups = _loadLookups();
  late Future<List<Entry>> data = _load();

  Future<(List<Project>, List<Activity>, List<User>)> _loadLookups() async => (
        await widget.api.projects(includeInactive: true),
        await widget.api.activities(includeInactive: true),
        widget.user.isManager ? await widget.api.users() : <User>[],
      );

  Future<List<Entry>> _load() => widget.api.entries(
        period: period,
        projectId: projectId,
        status: status,
        allUsers: person == _team,
        userId: person != null && person != _team ? person : null,
      );

  void _reload() => setState(() => data = _load());

  void _apply(VoidCallback change) {
    change();
    _reload();
  }

  Future<void> _edit(Entry e, List<Project> projects, List<Activity> activities) async {
    // Projetos inativos não aparecem para escolha, mas o próprio projeto do apontamento sim.
    final choosable = projects.where((p) => p.active || p.id == e.projectId).toList();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EntryDialog(
        api: widget.api,
        entry: e,
        projects: choosable,
        activities: activities.where((a) => a.active || a.id == e.activityId).toList(),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Entry e) async {
    final ok = await confirm(context, 'Apagar o apontamento de ${formatHours(e.hours)} em ${formatDate(e.date)}?');
    if (!ok || !mounted) return;
    await runWithFeedback(context, () => widget.api.deleteEntry(e.id), 'Apontamento apagado.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: lookups,
      onRetry: () => setState(() => lookups = _loadLookups()),
      builder: (l) {
        final (projects, activities, users) = l;
        final showPerson = person != null;
        return PageBody(children: [
          const PageHeader(title: 'Histórico', subtitle: 'Apontamentos realizados'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PeriodSelector(period: period, onChanged: (p) => _apply(() => period = p)),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<int?>(
                    initialValue: projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Projeto'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos os projetos')),
                      for (final p in projects)
                        DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => _apply(() => projectId = v),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<EntryStatus?>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final s in EntryStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) => _apply(() => status = v),
                  ),
                ),
                if (widget.user.isManager)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int?>(
                      initialValue: person,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Pessoa'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Meus apontamentos')),
                        const DropdownMenuItem(value: _team, child: Text('Toda a equipe')),
                        for (final u in users.where((u) => u.id != widget.user.id))
                          DropdownMenuItem(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => _apply(() => person = v),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FutureView(
            future: data,
            onRetry: _reload,
            builder: (entries) {
              final total = entries.fold<double>(0, (s, e) => s + e.hours);
              return SectionCard(
                title: '${entries.length} apontamento(s) · ${formatHours(total)}',
                padding: const EdgeInsets.only(bottom: 8),
                child: entries.isEmpty
                    ? const EmptyState(message: 'Nenhum apontamento com esses filtros.')
                    : ScrollableTable(
                        table: DataTable(
                          columnSpacing: 18,
                          columns: [
                            const DataColumn(label: Text('')),
                            const DataColumn(label: Text('Data')),
                            if (showPerson) const DataColumn(label: Text('Funcionário')),
                            const DataColumn(label: Text('Projeto')),
                            const DataColumn(label: Text('Atividade')),
                            const DataColumn(label: Text('Início')),
                            const DataColumn(label: Text('Fim')),
                            const DataColumn(label: Text('Intervalo'), numeric: true),
                            const DataColumn(label: Text('Horas'), numeric: true),
                            const DataColumn(label: Text('Status')),
                            const DataColumn(label: Text('Descrição')),
                          ],
                          rows: [
                            for (final e in entries)
                              DataRow(cells: [
                                DataCell(_actions(e, projects, activities)),
                                DataCell(Text(formatDate(e.date))),
                                if (showPerson) DataCell(Text(e.userName)),
                                DataCell(Text(e.projectLabel)),
                                DataCell(Text(e.activityName ?? '—')),
                                DataCell(Text(e.startTime ?? '—')),
                                DataCell(Text(e.endTime ?? '—')),
                                DataCell(Text(e.startTime == null ? '—' : '${e.breakMinutes} min')),
                                DataCell(Text(formatNumber(e.hours), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(StatusChip(e.status, note: e.reviewNote)),
                                DataCell(SizedBox(
                                  width: 200,
                                  child: Text(e.description, overflow: TextOverflow.ellipsis, maxLines: 2),
                                )),
                              ]),
                          ],
                        ),
                      ),
              );
            },
          ),
        ]);
      },
    );
  }

  Widget _actions(Entry e, List<Project> projects, List<Activity> activities) {
    final locked = e.locked && !widget.user.isManager;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: locked ? 'Aprovado: não pode ser alterado' : 'Editar',
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: locked ? null : () => _edit(e, projects, activities),
      ),
      IconButton(
        tooltip: locked ? 'Aprovado: não pode ser apagado' : 'Apagar',
        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted),
        onPressed: locked ? null : () => _delete(e),
      ),
    ]);
  }
}
