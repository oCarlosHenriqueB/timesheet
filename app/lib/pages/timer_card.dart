import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import 'common.dart';

/// Cronômetro por projeto. Fica guardado no servidor, então continua contando
/// se a página for recarregada ou aberta em outro aparelho.
/// Não desenha cartão próprio: fica dentro do painel de lançamento.
class TimerCard extends StatefulWidget {
  const TimerCard({
    super.key,
    required this.api,
    required this.projects,
    required this.onEntryCreated,
    this.onRunningChanged,
  });

  final Api api;
  final List<Project> projects;

  /// Chamado depois que o cronômetro vira lançamento, para a lista atualizar.
  final VoidCallback onEntryCreated;

  /// Avisa quando o cronômetro começa ou para (o painel mostra "rodando").
  final ValueChanged<bool>? onRunningChanged;

  @override
  State<TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<TimerCard> {
  RunningTimer? running;
  bool loading = true;
  bool busy = false;
  int? projectId;
  final description = TextEditingController();
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    projectId = widget.projects.isEmpty ? null : widget.projects.first.id;
    _load();
  }

  @override
  void dispose() {
    ticker?.cancel();
    description.dispose();
    super.dispose();
  }

  void _setRunning(RunningTimer? t) {
    if ((running != null) != (t != null)) widget.onRunningChanged?.call(t != null);
    running = t;
    ticker?.cancel();
    if (t != null) ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _load() async {
    try {
      final t = await widget.api.timer();
      if (mounted) setState(() => _setRunning(t));
    } catch (_) {
      // Sem cronômetro visível se a API falhar; a lista de lançamentos já mostra o erro.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _start() => _run(() async {
        final t = await widget.api.startTimer(projectId!, description: description.text.trim());
        description.clear();
        setState(() => _setRunning(t));
      });

  Future<void> _stop() => _run(() async {
        final t = running!;
        final hours = await widget.api.stopTimer(t.workDate);
        setState(() => _setRunning(null));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Lançado ${formatHours(hours)} em ${t.projectLabel}.')));
        }
        widget.onEntryCreated();
      });

  Future<void> _discard() async {
    if (!await confirm(context, 'Descartar o cronômetro? O tempo contado não será lançado.')) return;
    await _run(() async {
      await widget.api.discardTimer();
      setState(() => _setRunning(null));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final t = running;

    if (t != null) {
      return Container(
        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatDuration(t.elapsed()),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ])),
                Text(t.projectLabel, overflow: TextOverflow.ellipsis),
                if (t.description.isNotEmpty) Text(t.description, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            IconButton(tooltip: 'Descartar', onPressed: busy ? null : _discard, icon: const Icon(Icons.close)),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: busy ? null : _stop,
              icon: const Icon(Icons.stop),
              label: const Text('Parar e lançar'),
            ),
          ]),
        ),
      );
    }

    if (widget.projects.isEmpty) return const Text('Nenhum projeto ativo para cronometrar.');
    return Wrap(
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
          width: 220,
          child: TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'O que vai fazer? (opcional)'),
            onSubmitted: (_) => busy || projectId == null ? null : _start(),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || projectId == null ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar'),
        ),
      ],
    );
  }
}
