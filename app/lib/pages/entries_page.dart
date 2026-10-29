import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import 'common.dart';

/// Lista os lançamentos do usuário logado e permite criar, editar e apagar.
class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key, required this.api});

  final Api api;

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  Period period = Period.thisMonth();
  late Future<(List<Entry>, List<Project>)> data = _load();

  Future<(List<Entry>, List<Project>)> _load() async =>
      (await widget.api.entries(period: period), await widget.api.projects());

  void _setPeriod(Period p) => setState(() {
        period = p;
        data = _load();
      });

  void _reload() => setState(() => data = _load());

  Future<void> _edit(List<Project> projects, [Entry? entry]) async {
    final draft = await showDialog<EntryDraft>(
      context: context,
      builder: (_) => EntryDialog(projects: projects, entry: entry),
    );
    if (draft == null || !mounted) return;
    await runWithFeedback(context, () => widget.api.saveEntry(draft, id: entry?.id),
        entry == null ? 'Horas lançadas.' : 'Lançamento atualizado.');
    _reload();
  }

  Future<void> _delete(Entry entry) async {
    final ok = await confirm(context, 'Apagar o lançamento de ${formatHours(entry.hours)} em ${formatDate(entry.date)}?');
    if (!ok || !mounted) return;
    await runWithFeedback(context, () => widget.api.deleteEntry(entry.id), 'Lançamento apagado.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: data,
      onRetry: _reload,
      builder: (result) {
        final (entries, projects) = result;
        final total = entries.fold<double>(0, (s, e) => s + e.hours);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: projects.isEmpty ? null : () => _edit(projects),
            icon: const Icon(Icons.add),
            label: const Text('Lançar horas'),
          ),
          body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    PeriodSelector(period: period, onChanged: _setPeriod),
                    if (entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Center(child: Text('Nenhum lançamento neste período. Use "Lançar horas".')),
                      )
                    else
                      Text('Total: ${formatHours(total)} em ${entries.length} lançamento(s)',
                          style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final e in entries)
                      Card(
                        child: ListTile(
                          title: Text(e.projectLabel),
                          subtitle: Text(
                              [formatDate(e.date), if (e.description.isNotEmpty) e.description].join(' · ')),
                          leading: CircleAvatar(child: Text(formatNumber(e.hours))),
                          onTap: () => _edit(projects, e),
                          trailing: IconButton(
                            tooltip: 'Apagar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(e),
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({super.key, required this.projects, this.entry});

  final List<Project> projects;
  final Entry? entry;

  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final form = GlobalKey<FormState>();
  late int? projectId = widget.entry?.projectId ?? widget.projects.first.id;
  late DateTime date = widget.entry?.date ?? DateUtils.dateOnly(DateTime.now());
  late final hours = TextEditingController(text: widget.entry?.hours.toString() ?? '');
  late final description = TextEditingController(text: widget.entry?.description ?? '');

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => date = picked);
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(
      context,
      EntryDraft(projectId: projectId!, date: date, hours: parseHours(hours.text)!, description: description.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Um lançamento antigo pode apontar para um projeto que foi desativado.
    final known = widget.projects.any((p) => p.id == projectId);
    return AlertDialog(
      title: Text(widget.entry == null ? 'Lançar horas' : 'Editar lançamento'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: known ? projectId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Projeto'),
                items: [
                  for (final p in widget.projects)
                    DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => projectId = v),
                validator: (v) => v == null ? 'Escolha um projeto ativo.' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data', suffixIcon: Icon(Icons.calendar_today)),
                  child: Text(formatDate(date)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: hours,
                autofocus: widget.entry == null,
                decoration: const InputDecoration(labelText: 'Horas', hintText: 'ex.: 1,5'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final h = parseHours(v ?? '');
                  if (h == null) return 'Informe um número.';
                  if (h <= 0 || h > 24) return 'Entre 0 e 24 horas.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
                maxLines: 2,
              ),
            ],
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
