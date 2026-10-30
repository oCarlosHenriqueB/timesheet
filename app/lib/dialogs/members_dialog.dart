import 'package:flutter/material.dart';

import '../api.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';

/// Equipe do projeto: o gestor escolhe os projetistas e define horas previstas e prazo de cada um.
/// Fecha devolvendo true quando salva.
class MembersDialog extends StatefulWidget {
  const MembersDialog({super.key, required this.api, required this.project});

  final Api api;
  final Project project;

  @override
  State<MembersDialog> createState() => _MembersDialogState();
}

class _Row {
  _Row(this.userId, this.userName, {double? budget, this.due, this.used = 0})
      : budget = TextEditingController(text: budget == null ? '' : formatNumber(budget));

  final int userId;
  final String userName;
  final TextEditingController budget;
  DateTime? due;
  final double used;
}

class _MembersDialogState extends State<MembersDialog> {
  final form = GlobalKey<FormState>();
  List<_Row>? rows;
  List<User> designers = const [];
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (members, users) = (await widget.api.members(widget.project.id), await widget.api.users());
      setState(() {
        designers = users.where((u) => !u.isManager && u.active).toList();
        rows = [
          for (final m in members) _Row(m.userId, m.userName, budget: m.budgetHours, due: m.dueDate, used: m.usedHours),
        ];
      });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _pickDate(_Row r) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: r.due ?? widget.project.dueDate ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
      helpText: 'Prazo de ${r.userName}',
    );
    if (picked != null) setState(() => r.due = picked);
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await widget.api.saveMembers(widget.project.id, [
        for (final r in rows!)
          Member(
            userId: r.userId,
            userName: r.userName,
            budgetHours: r.budget.text.trim().isEmpty ? null : parseHours(r.budget.text),
            dueDate: r.due,
          ),
      ]);
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Equipe do projeto atualizada.')));
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    final available = designers.where((u) => !(list ?? const []).any((r) => r.userId == u.id)).toList();
    final projectDue = widget.project.dueDate;
    final today = DateTime.now();
    return AlertDialog(
      title: Text('Equipe · ${widget.project.label}'),
      content: SizedBox(
        width: 720,
        child: list == null
            ? (error == null ? const LinearProgressIndicator() : Text(error!))
            : Form(
                key: form,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    list.isEmpty
                        ? 'Ninguém alocado: o projeto fica aberto para todos apontarem.'
                        : 'Só os projetistas abaixo podem apontar horas neste projeto.',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('Já lançou ${formatHours(r.used)}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ]),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextFormField(
                            controller: r.budget,
                            decoration: const InputDecoration(labelText: 'Horas previstas', suffixText: 'h'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final h = parseHours(v);
                              return h == null || h <= 0 ? '> 0' : null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 220,
                          child: InkWell(
                            onTap: () => _pickDate(r),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Prazo',
                                suffixIcon: r.due == null
                                    ? const Icon(Icons.calendar_today, size: 18)
                                    : IconButton(
                                        tooltip: 'Usar a entrega do projeto',
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () => setState(() => r.due = null),
                                      ),
                              ),
                              child: Text(
                                r.due != null
                                    ? formatDate(r.due!)
                                    : projectDue == null
                                        ? 'Sem prazo'
                                        : 'Projeto: ${formatDate(projectDue)}',
                                style: TextStyle(color: r.due == null ? AppColors.textMuted : null),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Situação atual da pessoa, para o gestor já ver ao alocar.
                        Tooltip(
                          message: 'Situação atual',
                          child: Icon(Icons.circle,
                              size: 12,
                              color: gridHealth(
                                budget: parseHours(r.budget.text),
                                accumulated: r.used,
                                due: r.due ?? projectDue,
                                day: today,
                              ).color),
                        ),
                        IconButton(
                          tooltip: 'Tirar do projeto',
                          icon: const Icon(Icons.person_remove_outlined, size: 20),
                          onPressed: () => setState(() => list.remove(r)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  if (available.isNotEmpty)
                    PopupMenuButton<User>(
                      tooltip: 'Alocar projetista',
                      onSelected: (u) => setState(() => list.add(_Row(u.id, u.name))),
                      itemBuilder: (_) => [for (final u in available) PopupMenuItem(value: u, child: Text(u.name))],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add_alt_1, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text('Alocar projetista', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    )
                  else if (designers.isEmpty)
                    const Text('Cadastre projetistas em Gestão → Usuários.'),
                  if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: busy || list == null ? null : _save, child: const Text('Salvar equipe')),
      ],
    );
  }
}
