import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';

/// Gestor aprova ou rejeita os apontamentos da equipe, um a um ou vários de uma vez.
/// Abre na fila "Aguardando aprovação" (status enviado), de qualquer data.
/// Aprovado trava para o projetista; rejeitado volta para a fila quando ele corrige.
class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key, required this.api});

  final Api api;

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  Period period = const Period(PeriodPreset.all);
  EntryStatus? status = EntryStatus.enviado;
  int? projectId;
  int? userId;
  final selected = <int>{};

  late Future<(List<Project>, List<User>)> lookups = _loadLookups();
  late Future<List<Entry>> data = _load();

  Future<(List<Project>, List<User>)> _loadLookups() async =>
      (await widget.api.projects(includeInactive: true), await widget.api.users());

  Future<List<Entry>> _load() => widget.api.entries(
        allUsers: true,
        period: period,
        status: status,
        projectId: projectId,
        userId: userId,
      );

  void _reload() => setState(() {
        selected.clear();
        data = _load();
      });

  void _apply(VoidCallback change) {
    change();
    _reload();
  }

  Future<void> _review(List<int> ids, EntryStatus to) async {
    var note = '';
    if (to == EntryStatus.rejeitado) {
      final typed = await showDialog<String>(context: context, builder: (_) => _RejectDialog(count: ids.length));
      if (typed == null) return;
      note = typed;
    }
    if (!mounted) return;
    final done = switch (to) {
      EntryStatus.aprovado => 'aprovado(s)',
      EntryStatus.rejeitado => 'rejeitado(s)',
      _ => 'reaberto(s)',
    };
    await runWithFeedback(
        context, () => widget.api.reviewEntries(ids, to, note: note), '${ids.length} apontamento(s) $done.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: lookups,
      onRetry: () => setState(() => lookups = _loadLookups()),
      builder: (l) {
        final (projects, users) = l;
        return PageBody(children: [
          const PageHeader(title: 'Aprovação', subtitle: 'Apontamentos enviados pela equipe'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PeriodSelector(period: period, onChanged: (p) => _apply(() => period = p)),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<EntryStatus?>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: EntryStatus.enviado, child: Text('Aguardando aprovação')),
                      DropdownMenuItem(value: EntryStatus.aprovado, child: Text('Aprovados')),
                      DropdownMenuItem(value: EntryStatus.rejeitado, child: Text('Rejeitados')),
                      DropdownMenuItem(value: null, child: Text('Todos')),
                    ],
                    onChanged: (v) => _apply(() => status = v),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int?>(
                    initialValue: userId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Pessoa'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toda a equipe')),
                      for (final u in users)
                        DropdownMenuItem(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => _apply(() => userId = v),
                  ),
                ),
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
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FutureView(future: data, onRetry: _reload, builder: _table),
        ]);
      },
    );
  }

  Widget _table(List<Entry> entries) {
    final total = entries.fold<double>(0, (s, e) => s + e.hours);
    final chosen = entries.where((e) => selected.contains(e.id)).toList();
    final chosenHours = chosen.fold<double>(0, (s, e) => s + e.hours);
    final ids = [for (final e in chosen) e.id];
    return SectionCard(
      title: chosen.isEmpty
          ? '${entries.length} apontamento(s) · ${formatHours(total)}'
          : '${chosen.length} selecionado(s) · ${formatHours(chosenHours)}',
      // Sempre visíveis (desativados sem seleção), para a tabela não pular ao marcar a primeira linha.
      actions: [
        OutlinedButton.icon(
          onPressed: chosen.isEmpty ? null : () => _review(ids, EntryStatus.rejeitado),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Rejeitar'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: chosen.isEmpty ? null : () => _review(ids, EntryStatus.aprovado),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Aprovar'),
        ),
      ],
      padding: const EdgeInsets.only(bottom: 8),
      child: entries.isEmpty
          ? EmptyState(
              icon: Icons.task_alt,
              message: status == EntryStatus.enviado
                  ? 'Nada aguardando aprovação com esses filtros.'
                  : 'Nenhum apontamento com esses filtros.',
            )
          : ScrollableTable(
              table: DataTable(
                columnSpacing: 18,
                onSelectAll: (all) => setState(() {
                  selected.clear();
                  if (all == true) selected.addAll(entries.map((e) => e.id));
                }),
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Funcionário')),
                  DataColumn(label: Text('Projeto')),
                  DataColumn(label: Text('Atividade')),
                  DataColumn(label: Text('Horário')),
                  DataColumn(label: Text('Horas'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Descrição')),
                ],
                rows: [
                  for (final e in entries)
                    DataRow(
                      selected: selected.contains(e.id),
                      onSelectChanged: (v) => setState(() => v == true ? selected.add(e.id) : selected.remove(e.id)),
                      cells: [
                        DataCell(_actions(e)),
                        DataCell(Text(formatDate(e.date))),
                        DataCell(Text(e.userName)),
                        DataCell(Text(e.projectLabel)),
                        DataCell(Text(e.activityName ?? '—')),
                        DataCell(Text(e.timeRange)),
                        DataCell(Text(formatNumber(e.hours), style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(StatusChip(e.status, note: e.reviewNote)),
                        DataCell(SizedBox(
                          width: 220,
                          child: Text(e.description, overflow: TextOverflow.ellipsis, maxLines: 2),
                        )),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _actions(Entry e) {
    if (e.status != EntryStatus.enviado) {
      return TextButton.icon(
        onPressed: () => _review([e.id], EntryStatus.enviado),
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Reabrir'),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Aprovar',
        icon: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
        onPressed: () => _review([e.id], EntryStatus.aprovado),
      ),
      IconButton(
        tooltip: 'Rejeitar',
        icon: const Icon(Icons.cancel_outlined, color: Color(0xFFC62828)),
        onPressed: () => _review([e.id], EntryStatus.rejeitado),
      ),
    ]);
  }
}

/// Pede o motivo da rejeição (opcional), que o projetista vê no Histórico.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.count});

  final int count;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.count == 1 ? 'Rejeitar apontamento' : 'Rejeitar ${widget.count} apontamentos'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('O projetista vê o motivo no Histórico. Quando ele corrigir, o apontamento volta para '
              'a fila de aprovação.'),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', hintText: 'Ex.: faltou o número da OS'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
          onPressed: () => Navigator.pop(context, note.text.trim()),
          child: const Text('Rejeitar'),
        ),
      ],
    );
  }
}
