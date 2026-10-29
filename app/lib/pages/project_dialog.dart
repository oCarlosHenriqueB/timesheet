import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';

/// Formulário de projeto: número, cliente, descrição, horas previstas, entrega
/// e as referências do SAP. Na edição o número do projeto fica travado.
class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.project, this.onSapLookup});

  final Project? project;

  /// Busca o projeto no SAP pelo número (null quando não encontra).
  /// Sem ele, o botão "Buscar no SAP" não aparece.
  final Future<ProjectDraft?> Function(String code)? onSapLookup;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  final form = GlobalKey<FormState>();
  late final code = TextEditingController(text: widget.project?.code ?? '');
  late final client = TextEditingController(text: widget.project?.client ?? '');
  late final description = TextEditingController(text: widget.project?.description ?? '');
  late final budget = TextEditingController(
      text: widget.project?.budgetHours == null ? '' : formatNumber(widget.project!.budgetHours!));
  late DateTime? dueDate = widget.project?.dueDate;
  late final sapWbs = TextEditingController(text: widget.project?.sapWbs ?? '');
  late final sapSalesOrder = TextEditingController(text: widget.project?.sapSalesOrder ?? '');
  bool searching = false;
  String? sapMessage;

  bool get editing => widget.project != null;

  /// Preenche o formulário com o que o SAP tiver; campos vazios no SAP não apagam o que foi digitado.
  Future<void> _lookupSap() async {
    final number = code.text.trim();
    if (number.isEmpty) {
      setState(() => sapMessage = 'Digite o número do projeto primeiro.');
      return;
    }
    setState(() {
      searching = true;
      sapMessage = null;
    });
    try {
      final found = await widget.onSapLookup!(number);
      setState(() {
        if (found == null) {
          sapMessage = 'Projeto não encontrado no catálogo do SAP. Preencha à mão.';
          return;
        }
        void fill(TextEditingController c, String v) => v.isEmpty ? null : c.text = v;
        fill(client, found.client);
        fill(sapWbs, found.sapWbs);
        fill(sapSalesOrder, found.sapSalesOrder);
        if (found.budgetHours != null) budget.text = formatNumber(found.budgetHours!);
        dueDate = found.dueDate ?? dueDate;
        sapMessage = 'Dados preenchidos a partir do SAP. Confira antes de salvar.';
      });
    } catch (e) {
      setState(() => sapMessage = '$e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

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
        sapWbs: sapWbs.text.trim(),
        sapSalesOrder: sapSalesOrder.text.trim(),
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
                decoration: InputDecoration(
                  labelText: 'Projeto (número)',
                  hintText: 'ex.: PRJ-1234',
                  suffixIcon: editing || widget.onSapLookup == null
                      ? null
                      : searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: 'Buscar no SAP',
                              icon: const Icon(Icons.cloud_download_outlined),
                              onPressed: _lookupSap,
                            ),
                ),
                onFieldSubmitted: editing || widget.onSapLookup == null ? null : (_) => _lookupSap(),
                validator: _required,
              ),
              if (sapMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(sapMessage!, style: Theme.of(context).textTheme.bodySmall),
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
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: sapWbs,
                    decoration: const InputDecoration(labelText: 'Elemento PEP (SAP)', hintText: 'opcional'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: sapSalesOrder,
                    decoration: const InputDecoration(labelText: 'Ordem de venda (SAP)', hintText: 'opcional'),
                  ),
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
