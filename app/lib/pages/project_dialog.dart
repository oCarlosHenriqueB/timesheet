import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';

/// Formulário de projeto: número, cliente, descrição, horas previstas e entrega.
/// Na edição o número do projeto fica travado.
class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.project});

  final Project? project;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  final form = GlobalKey<FormState>();
  late final code = TextEditingController(text: widget.project?.code ?? '');
  // No futuro o cliente poderá ser preenchido sozinho a partir do número do projeto.
  late final client = TextEditingController(text: widget.project?.client ?? '');
  late final description = TextEditingController(text: widget.project?.description ?? '');
  late final budget = TextEditingController(
      text: widget.project?.budgetHours == null ? '' : formatNumber(widget.project!.budgetHours!));
  late DateTime? dueDate = widget.project?.dueDate;

  bool get editing => widget.project != null;

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null) setState(() => dueDate = picked);
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProjectDraft(
        code: code.text.trim(),
        client: client.text.trim(),
        description: description.text.trim(),
        budgetHours: budget.text.trim().isEmpty ? null : parseHours(budget.text),
        dueDate: dueDate,
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(editing ? 'Editar projeto' : 'Novo projeto'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: code,
                enabled: !editing,
                autofocus: !editing,
                decoration: const InputDecoration(labelText: 'Projeto (número)', hintText: 'ex.: PRJ-1234'),
                validator: _required,
              ),
              TextFormField(
                controller: client,
                autofocus: editing,
                decoration: const InputDecoration(labelText: 'Cliente'),
                validator: _required,
              ),
              TextFormField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
              ),
              TextFormField(
                controller: budget,
                decoration: const InputDecoration(
                  labelText: 'Horas previstas',
                  hintText: 'ex.: 120',
                  helperText: 'Deixe vazio se ainda não houver orçamento de horas.',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final h = parseHours(v);
                  if (h == null) return 'Informe um número.';
                  if (h <= 0) return 'Precisa ser maior que zero.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Data de entrega (opcional)', suffixIcon: Icon(Icons.calendar_today)),
                      child: Text(dueDate == null ? '—' : formatDate(dueDate!)),
                    ),
                  ),
                ),
                if (dueDate != null)
                  IconButton(
                    tooltip: 'Remover data',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => dueDate = null),
                  ),
              ]),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
