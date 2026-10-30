import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

/// Formulário de apontamento: projeto, atividade, data, início, fim, intervalo e descrição.
/// O total é calculado na hora. Usado na tela de Apontamento e na edição do Histórico.
///
/// Lançamentos antigos (sem horários) são editados pelo total de horas.
class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.projects,
    required this.activities,
    required this.onSubmit,
    this.entry,
    this.suggestedStart,
    this.submitLabel = 'Registrar',
    this.onCancel,
  });

  final List<Project> projects;
  final List<Activity> activities;

  /// Devolve true se salvou; aí o formulário se prepara para o próximo apontamento.
  final Future<bool> Function(EntryDraft draft) onSubmit;

  /// Preenchido na edição.
  final Entry? entry;

  /// Início sugerido para um apontamento novo (ex.: o fim do último de hoje).
  final String? suggestedStart;
  final String submitLabel;
  final VoidCallback? onCancel;

  @override
  State<EntryForm> createState() => EntryFormState();
}

class EntryFormState extends State<EntryForm> {
  final form = GlobalKey<FormState>();
  late int? projectId;
  late int? activityId;
  late DateTime date;
  late final start = TextEditingController();
  late final end = TextEditingController();
  late final pause = TextEditingController();
  late final hours = TextEditingController();
  late final description = TextEditingController();
  final endFocus = FocusNode();
  bool busy = false;

  Entry? get entry => widget.entry;

  /// Lançamento antigo, só com total de horas.
  bool get totalOnly => entry != null && entry!.startTime == null;

  @override
  void initState() {
    super.initState();
    final e = entry;
    projectId = e?.projectId ?? (widget.projects.isEmpty ? null : widget.projects.first.id);
    if (e != null && !widget.projects.any((p) => p.id == e.projectId)) projectId = null;
    activityId = e?.activityId;
    if (activityId != null && !widget.activities.any((a) => a.id == activityId)) activityId = null;
    date = e?.date ?? DateUtils.dateOnly(DateTime.now());
    start.text = e?.startTime ?? widget.suggestedStart ?? '08:00';
    end.text = e?.endTime ?? '';
    pause.text = '${e?.breakMinutes ?? 0}';
    hours.text = e == null ? '' : formatNumber(e.hours);
    description.text = e?.description ?? '';
  }

  @override
  void dispose() {
    for (final c in [start, end, pause, hours, description]) {
      c.dispose();
    }
    endFocus.dispose();
    super.dispose();
  }

  int get breakMinutes => int.tryParse(pause.text.trim()) ?? 0;

  double? get total => totalOnly
      ? parseHours(hours.text)
      : workedHours(parseTime(start.text), parseTime(end.text), breakMinutes);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _submit() async {
    if (busy || !form.currentState!.validate()) return;
    final draft = EntryDraft(
      projectId: projectId!,
      activityId: activityId,
      date: date,
      startTime: totalOnly ? null : parseTime(start.text),
      endTime: totalOnly ? null : parseTime(end.text),
      breakMinutes: totalOnly ? 0 : breakMinutes,
      hours: totalOnly ? parseHours(hours.text) : null,
      description: description.text.trim(),
    );
    setState(() => busy = true);
    final ok = await widget.onSubmit(draft);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok && entry == null) {
      // Próximo apontamento começa onde este terminou; projeto, atividade e data ficam.
      setState(() {
        start.text = draft.endTime ?? start.text;
        end.clear();
        pause.text = '0';
        description.clear();
      });
      endFocus.requestFocus();
    }
  }

  String? _timeValidator(String? v) => parseTime(v ?? '') == null ? 'HH:MM' : null;

  Widget _timeField(String label, TextEditingController c, {FocusNode? focus}) {
    return SizedBox(
      width: 120,
      child: TextFormField(
        controller: c,
        focusNode: focus,
        decoration: InputDecoration(
          labelText: label,
          hintText: '08:00',
          suffixIcon: IconButton(
            tooltip: 'Escolher horário',
            icon: const Icon(Icons.schedule, size: 18),
            onPressed: () async {
              final current = parseTime(c.text);
              final picked = await showTimePicker(
                context: context,
                initialTime: current == null
                    ? TimeOfDay.now()
                    : TimeOfDay(hour: timeToMinutes(current) ~/ 60, minute: timeToMinutes(current) % 60),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => c.text = minutesToTime(picked.hour * 60 + picked.minute));
            },
          ),
        ),
        validator: _timeValidator,
        onChanged: (_) => setState(() {}),
        onEditingComplete: () {
          final t = parseTime(c.text);
          if (t != null) setState(() => c.text = t);
          FocusScope.of(context).nextFocus();
        },
        onFieldSubmitted: (_) => _submit(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projects.isEmpty) return const Text('Nenhum projeto ativo para apontar horas.');
    final t = total;
    final invalidRange = !totalOnly && parseTime(start.text) != null && parseTime(end.text) != null && t == null;

    return Form(
      key: form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: 340,
            child: DropdownButtonFormField<int>(
              initialValue: projectId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Projeto'),
              items: [
                for (final p in widget.projects)
                  DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => projectId = v),
              validator: (v) => v == null ? 'Escolha um projeto ativo.' : null,
            ),
          ),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<int>(
              initialValue: activityId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Atividade'),
              items: [for (final a in widget.activities) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => activityId = v),
              validator: (v) => v == null ? 'Escolha a atividade.' : null,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 150,
            child: InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                child: Text(formatDate(date)),
              ),
            ),
          ),
          if (totalOnly)
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: hours,
                decoration: const InputDecoration(labelText: 'Horas'),
                validator: (v) {
                  final h = parseHours(v ?? '');
                  return h == null || h <= 0 || h > 24 ? '0 a 24' : null;
                },
                onChanged: (_) => setState(() {}),
              ),
            )
          else ...[
            _timeField('Início', start),
            _timeField('Fim', end, focus: endFocus),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: pause,
                decoration: const InputDecoration(labelText: 'Intervalo', suffixText: 'min'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final m = int.tryParse((v ?? '').trim());
                  return m == null || m < 0 || m > 720 ? '0 a 720' : null;
                },
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (invalidRange ? Colors.red : AppColors.primary).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              invalidRange ? 'Fim antes do início ou intervalo grande demais' : 'Total: ${t == null ? '—' : formatHours(t)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: invalidRange ? Colors.red.shade700 : AppColors.primary,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: description,
          decoration: const InputDecoration(labelText: 'Descrição do trabalho realizado'),
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        Row(children: [
          FilledButton.icon(
            onPressed: busy || invalidRange ? null : _submit,
            icon: busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(widget.submitLabel),
          ),
          if (widget.onCancel != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: widget.onCancel, child: const Text('Cancelar')),
          ],
          const SizedBox(width: 12),
          if (entry == null)
            const Text('Dica: Enter registra.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ]),
    );
  }
}
