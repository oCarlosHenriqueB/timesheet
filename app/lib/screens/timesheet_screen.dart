import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_form.dart';
import '../widgets/layout.dart';
import '../widgets/timer_card.dart';

/// Apontamento de horas: formulário rápido (início, fim, intervalo), cronômetro opcional
/// por pessoa e a lista do que já foi registrado hoje.
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key, required this.api, required this.user});

  final Api api;
  final User user;

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  final today = DateUtils.dateOnly(DateTime.now());
  late Future<List<Entry>> todays = _loadToday();
  late Future<(List<Project>, List<Activity>, String?)> base = _loadBase();

  /// Projetos, atividades e o início sugerido (fim do último apontamento de hoje), calculado uma vez.
  /// Depois de cada registro o próprio formulário passa o fim para o início.
  Future<(List<Project>, List<Activity>, String?)> _loadBase() async {
    final entries = await todays;
    final lastEnd = entries.map((e) => e.endTime).whereType<String>().fold<String?>(
        null, (m, t) => m == null || t.compareTo(m) > 0 ? t : m);
    return (await widget.api.projects(), await widget.api.activities(), lastEnd);
  }

  Future<List<Entry>> _loadToday() =>
      widget.api.entries(period: Period(PeriodPreset.custom, from: today, to: today));

  void _refreshToday() => setState(() => todays = _loadToday());

  Future<bool> _save(EntryDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.saveEntry(draft);
      final h = draft.startTime == null ? draft.hours! : workedHours(draft.startTime, draft.endTime, draft.breakMinutes)!;
      messenger.showSnackBar(SnackBar(content: Text('Registrado ${formatHours(h)} em ${formatDate(draft.date)}.')));
      _refreshToday();
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: base,
      onRetry: () => setState(() {
        todays = _loadToday();
        base = _loadBase();
      }),
      builder: (b) {
        final (projects, activities, lastEnd) = b;
        return PageBody(children: [
          const PageHeader(
            title: 'Apontamento de horas',
            subtitle: 'Informe o projeto, a atividade e o horário. O total é calculado automaticamente.',
          ),
          if (widget.user.useTimer) ...[
            SectionCard(
              title: 'Cronômetro',
              actions: const [
                Tooltip(
                  message: 'Cada pessoa liga ou desliga o cronômetro no menu da conta (canto inferior esquerdo).',
                  child: Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
                ),
              ],
              child: TimerCard(
                api: widget.api,
                projects: projects,
                activities: activities,
                onEntryCreated: _refreshToday,
              ),
            ),
            const SizedBox(height: 16),
          ],
          FutureBuilder<List<Entry>>(
            future: todays,
            builder: (context, snap) {
              final list = snap.data ?? const <Entry>[];
              final form = SectionCard(
                title: 'Novo apontamento',
                child: EntryForm(
                  key: const ValueKey('novo-apontamento'),
                  projects: projects,
                  activities: activities,
                  suggestedStart: lastEnd,
                  onSubmit: _save,
                ),
              );
              final todayCard = _TodayCard(entries: list, loading: snap.connectionState != ConnectionState.done);
              return LayoutBuilder(builder: (context, c) {
                if (c.maxWidth < 1100) return Column(children: [form, const SizedBox(height: 16), todayCard]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: todayCard),
                ]);
              });
            },
          ),
        ]);
      },
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.entries, required this.loading});

  final List<Entry> entries;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (s, e) => s + e.hours);
    final sorted = [...entries]..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
    return SectionCard(
      title: 'Hoje · ${formatHours(total)}',
      child: loading
          ? const LinearProgressIndicator()
          : sorted.isEmpty
              ? const EmptyState(message: 'Nada registrado hoje.', icon: Icons.wb_sunny_outlined)
              : Column(children: [
                  for (final e in sorted)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 92,
                        child: Text(e.timeRange, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                      title: Text(e.projectLabel, overflow: TextOverflow.ellipsis),
                      subtitle: Text([?e.activityName, if (e.description.isNotEmpty) e.description].join(' · ')),
                      trailing: Text(formatHours(e.hours), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ]),
    );
  }
}
