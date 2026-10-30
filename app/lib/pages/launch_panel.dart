import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import 'timer_card.dart';

enum LaunchMode { timer, manual }

/// Painel do topo de "Minhas horas": escolha entre cronômetro e lançamento manual.
/// O app lembra o último modo usado neste navegador.
class LaunchPanel extends StatefulWidget {
  const LaunchPanel({super.key, required this.api, required this.projects, required this.onEntryCreated});

  final Api api;
  final List<Project> projects;
  final VoidCallback onEntryCreated;

  @override
  State<LaunchPanel> createState() => _LaunchPanelState();
}

class _LaunchPanelState extends State<LaunchPanel> {
  static const _modeKey = 'launch_mode';
  LaunchMode mode = LaunchMode.timer;
  bool timerRunning = false;

  @override
  void initState() {
    super.initState();
    _restoreMode();
  }

  Future<void> _restoreMode() async {
    final saved = (await SharedPreferences.getInstance()).getString(_modeKey);
    final restored = LaunchMode.values.where((m) => m.name == saved).firstOrNull;
    if (restored != null && mounted) setState(() => mode = restored);
  }

  void _setMode(LaunchMode m) {
    setState(() => mode = m);
    SharedPreferences.getInstance().then((p) => p.setString(_modeKey, m.name));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<LaunchMode>(
            segments: [
              ButtonSegment(
                value: LaunchMode.timer,
                icon: const Icon(Icons.timer_outlined),
                label: Text(timerRunning ? 'Cronômetro (rodando)' : 'Cronômetro'),
              ),
              const ButtonSegment(value: LaunchMode.manual, icon: Icon(Icons.edit_outlined), label: Text('Manual')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const SizedBox(height: 8),
          // O cronômetro continua montado (e contando) mesmo com o modo manual na tela.
          Visibility(
            visible: mode == LaunchMode.timer,
            maintainState: true,
            child: TimerCard(
              api: widget.api,
              projects: widget.projects,
              onEntryCreated: widget.onEntryCreated,
              onRunningChanged: (r) => setState(() => timerRunning = r),
            ),
          ),
          if (mode == LaunchMode.manual)
            ManualEntryForm(api: widget.api, projects: widget.projects, onEntryCreated: widget.onEntryCreated),
        ]),
      ),
    );
  }
}

/// Lançamento manual direto na tela: projeto, data, horas e descrição.
class ManualEntryForm extends StatefulWidget {
  const ManualEntryForm({super.key, required this.api, required this.projects, required this.onEntryCreated});

  final Api api;
  final List<Project> projects;
  final VoidCallback onEntryCreated;

  @override
  State<ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends State<ManualEntryForm> {
  final form = GlobalKey<FormState>();
  late int? projectId = widget.projects.isEmpty ? null : widget.projects.first.id;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  final hours = TextEditingController();
  final description = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    hours.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final h = parseHours(hours.text)!;
    setState(() => busy = true);
    try {
      await widget.api.saveEntry(
        EntryDraft(projectId: projectId!, date: date, hours: h, description: description.text.trim()),
      );
      hours.clear();
      description.clear();
      messenger.showSnackBar(SnackBar(content: Text('Lançado ${formatHours(h)} em ${formatDate(date)}.')));
      widget.onEntryCreated();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projects.isEmpty) return const Text('Nenhum projeto ativo para lançar horas.');
    return Form(
      key: form,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<int>(
              initialValue: projectId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Projeto'),
              items: [
                for (final p in widget.projects)
                  DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => projectId = v),
            ),
          ),
          SizedBox(
            width: 140,
            child: InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                child: Text(formatDate(date)),
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: hours,
              decoration: const InputDecoration(labelText: 'Horas', hintText: '1,5'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final h = parseHours(v ?? '');
                if (h == null) return 'Número';
                if (h <= 0 || h > 24) return '0 a 24';
                return null;
              },
              onFieldSubmitted: (_) => busy ? null : _save(),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
              onFieldSubmitted: (_) => busy ? null : _save(),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: busy ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Lançar'),
          ),
        ],
      ),
    );
  }
}
