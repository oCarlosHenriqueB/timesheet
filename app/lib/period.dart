import 'package:flutter/material.dart';

import 'format.dart';

/// Atalhos de período. [custom] abre o calendário; [all] não filtra.
enum PeriodPreset { thisWeek, thisMonth, lastMonth, last30Days, all, custom }

extension PeriodPresetLabel on PeriodPreset {
  String get label => switch (this) {
        PeriodPreset.thisWeek => 'Esta semana',
        PeriodPreset.thisMonth => 'Este mês',
        PeriodPreset.lastMonth => 'Mês passado',
        PeriodPreset.last30Days => 'Últimos 30 dias',
        PeriodPreset.all => 'Tudo',
        PeriodPreset.custom => 'Escolher datas…',
      };
}

/// Período com datas inclusivas; from/to nulos significam sem limite.
class Period {
  const Period(this.preset, {this.from, this.to});

  final PeriodPreset preset;
  final DateTime? from;
  final DateTime? to;

  /// Calcula as datas de um atalho em relação a [today]. A semana começa na segunda.
  factory Period.of(PeriodPreset preset, DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    return switch (preset) {
      PeriodPreset.thisWeek => Period(preset,
          from: d.subtract(Duration(days: d.weekday - 1)), to: d.add(Duration(days: 7 - d.weekday))),
      PeriodPreset.thisMonth => Period(preset, from: DateTime(d.year, d.month), to: DateTime(d.year, d.month + 1, 0)),
      PeriodPreset.lastMonth => Period(preset, from: DateTime(d.year, d.month - 1), to: DateTime(d.year, d.month, 0)),
      PeriodPreset.last30Days => Period(preset, from: d.subtract(const Duration(days: 29)), to: d),
      PeriodPreset.all || PeriodPreset.custom => const Period(PeriodPreset.all),
    };
  }

  static Period thisMonth() => Period.of(PeriodPreset.thisMonth, DateTime.now());

  /// Parâmetros date_from/date_to para a API.
  Map<String, String> get query => {
        if (from != null) 'date_from': _iso(from!),
        if (to != null) 'date_to': _iso(to!),
      };

  /// Pedaço do nome do arquivo exportado.
  String get fileSuffix => from == null && to == null ? 'tudo' : '${from == null ? 'inicio' : _iso(from!)}_${to == null ? 'hoje' : _iso(to!)}';

  String get description {
    if (from == null && to == null) return 'Todos os lançamentos';
    return '${from == null ? '…' : formatDate(from!)} a ${to == null ? '…' : formatDate(to!)}';
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
}

/// Botão "Período: Este mês ▾" com os atalhos e a opção de escolher datas.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.period, required this.onChanged});

  final Period period;
  final ValueChanged<Period> onChanged;

  Future<void> _select(BuildContext context, PeriodPreset preset) async {
    if (preset != PeriodPreset.custom) return onChanged(Period.of(preset, DateTime.now()));
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: period.from != null && period.to != null
          ? DateTimeRange(start: period.from!, end: period.to!)
          : DateTimeRange(start: DateTime(today.year, today.month), end: today),
      helpText: 'Escolha o período',
    );
    if (range != null) onChanged(Period(PeriodPreset.custom, from: range.start, to: range.end));
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PeriodPreset>(
      tooltip: 'Mudar o período',
      onSelected: (p) => _select(context, p),
      itemBuilder: (_) => [
        for (final p in PeriodPreset.values)
          CheckedPopupMenuItem(value: p, checked: p == period.preset, child: Text(p.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.date_range, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              period.preset == PeriodPreset.custom
                  ? period.description
                  : '${period.preset.label} · ${period.description}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}
