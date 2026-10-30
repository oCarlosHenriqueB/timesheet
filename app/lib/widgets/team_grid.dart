import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../theme.dart';
import 'common.dart';
import 'layout.dart';

/// Grade de acompanhamento: cada colaborador, os projetos dele e as horas de cada dia.
/// A cor da célula é a situação da pessoa naquele projeto até aquele dia
/// (horas acumuladas × horas previstas dela, e o dia × o prazo dela).
class TeamGridView extends StatelessWidget {
  const TeamGridView({super.key, required this.grid, this.dayWidth = 42});

  final TeamGrid grid;
  final double dayWidth;

  static const _nameWidth = 270.0;
  static const _sumWidth = 72.0;
  static const _dueWidth = 96.0;
  static const _rowHeight = 34.0;

  @override
  Widget build(BuildContext context) {
    if (grid.rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Ninguém alocado e nenhuma hora no período.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final byUser = <int, List<GridRow>>{};
    for (final r in grid.rows) {
      byUser.putIfAbsent(r.userId, () => []).add(r);
    }
    final children = <Widget>[_header(context, today)];
    for (final rows in byUser.values) {
      final periodTotal = rows.fold<double>(0, (s, r) => s + r.days.values.fold<double>(0, (a, b) => a + b));
      children.add(_personRow(rows.first.userName, periodTotal));
      for (final r in rows) {
        children.add(_projectRow(r, today));
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  bool _weekend(DateTime d) => d.weekday >= 6;

  Widget _cell(double width, Widget child, {Color? color, Alignment align = Alignment.center}) => Container(
        width: width,
        height: _rowHeight,
        alignment: align,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      );

  Widget _header(BuildContext context, DateTime today) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        _cell(_nameWidth, const Text('Colaborador / projeto', style: style), align: Alignment.centerLeft),
        for (final d in grid.days)
          _cell(
            dayWidth,
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(DateFormat('EEE', 'pt_BR').format(d).substring(0, 3), style: style),
              Text('${d.day}',
                  style: style.copyWith(
                    color: DateUtils.isSameDay(d, today) ? AppColors.primary : null,
                    fontWeight: DateUtils.isSameDay(d, today) ? FontWeight.w800 : null,
                  )),
            ]),
            color: _weekend(d) ? AppColors.background : null,
          ),
        _cell(_sumWidth, const Text('Total geral', style: style), align: Alignment.centerRight),
        _cell(_sumWidth, const Text('Previsto', style: style), align: Alignment.centerRight),
        _cell(_dueWidth, const Text('Prazo', style: style)),
        _cell(40, const Text('', style: style)),
      ]),
    );
  }

  Widget _personRow(String name, double periodTotal) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Row(children: [
        _cell(
          _nameWidth + dayWidth * grid.days.length + _sumWidth * 2 + _dueWidth + 40,
          Text.rich(TextSpan(children: [
            TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
              text: '  ·  ${formatHours(periodTotal)} no período',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ])),
          align: Alignment.centerLeft,
        ),
      ]),
    );
  }

  Widget _projectRow(GridRow r, DateTime today) {
    var accumulated = r.hoursBefore;
    final cells = <Widget>[];
    for (final d in grid.days) {
      final h = r.days[d.toIso8601String().substring(0, 10)] ?? 0;
      accumulated += h;
      final health = gridHealth(budget: r.budgetHours, accumulated: accumulated, due: r.dueDate, day: d);
      cells.add(_cell(
        dayWidth,
        h == 0
            ? const SizedBox()
            : Tooltip(
                message: '${formatDate(d)}: ${formatHours(h)} · acumulado ${formatHours(accumulated)}'
                    '${r.budgetHours == null ? '' : ' de ${formatHours(r.budgetHours!)}'}',
                child: Container(
                  width: dayWidth - 6,
                  height: _rowHeight - 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: health.color, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    formatNumber(h),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: health == Health.warning ? const Color(0xFF3D2E00) : Colors.white,
                    ),
                  ),
                ),
              ),
        color: _weekend(d) ? AppColors.background : null,
      ));
    }
    final now = gridHealth(budget: r.budgetHours, accumulated: r.totalHours, due: r.dueDate, day: today);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.6))),
      child: Row(children: [
        _cell(
          _nameWidth,
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              r.allocated ? r.projectLabel : '${r.projectLabel} (sem alocação)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontStyle: r.allocated ? null : FontStyle.italic),
            ),
          ),
          align: Alignment.centerLeft,
        ),
        ...cells,
        _cell(_sumWidth, Text(formatHours(r.totalHours)), align: Alignment.centerRight),
        _cell(_sumWidth, Text(r.budgetHours == null ? '—' : formatHours(r.budgetHours!)), align: Alignment.centerRight),
        _cell(_dueWidth, Text(r.dueDate == null ? '—' : formatDate(r.dueDate!), style: const TextStyle(fontSize: 12))),
        _cell(
          40,
          Tooltip(
            message: _statusText(r, now, today),
            child: Icon(Icons.circle, size: 14, color: now.color),
          ),
        ),
      ]),
    );
  }

  static String _statusText(GridRow r, Health h, DateTime today) {
    final parts = <String>[];
    if (r.budgetHours != null) {
      final left = r.budgetHours! - r.totalHours;
      parts.add(left < 0 ? 'Estourou ${formatHours(-left)}' : 'Saldo ${formatHours(left)}');
    } else {
      parts.add('Sem horas previstas');
    }
    if (r.dueDate != null) {
      final days = daysUntil(r.dueDate!, today);
      parts.add(days < 0 ? 'prazo vencido há ${-days} dia(s)' : 'faltam $days dia(s) para o prazo');
    }
    return parts.join(' · ');
  }
}

/// Legenda das cores da grade.
class TeamGridLegend extends StatelessWidget {
  const TeamGridLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Health.ok, 'Dentro do previsto e do prazo'),
      (Health.warning, '70–90% das horas ou prazo em até 7 dias'),
      (Health.critical, 'Acima de 90% ou depois do prazo'),
      (Health.over, 'Passou das horas previstas'),
      (Health.none, 'Sem horas previstas nem prazo'),
    ];
    return Wrap(spacing: 14, runSpacing: 4, children: [
      for (final (h, label) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: h.color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
    ]);
  }
}

/// Cartão com a grade da equipe e o seletor de período (semana, mês...).
class TeamGridCard extends StatefulWidget {
  const TeamGridCard({super.key, required this.api, this.title = 'Acompanhamento da equipe', this.actions = const []});

  final Api api;
  final String title;
  final List<Widget> actions;

  @override
  State<TeamGridCard> createState() => _TeamGridCardState();
}

class _TeamGridCardState extends State<TeamGridCard> {
  Period period = Period.of(PeriodPreset.thisWeek, DateTime.now());
  late Future<TeamGrid> data = widget.api.teamGrid(period);

  void _setPeriod(Period p) {
    // "Tudo" não cabe numa grade por dia: usa o mês atual.
    final usable = p.from == null || p.to == null ? Period.of(PeriodPreset.thisMonth, DateTime.now()) : p;
    setState(() {
      period = usable;
      data = widget.api.teamGrid(usable);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: widget.title,
      actions: [PeriodSelector(period: period, onChanged: _setPeriod), ...widget.actions],
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TeamGridLegend(),
        const SizedBox(height: 10),
        FutureView(
          future: data,
          onRetry: () => setState(() => data = widget.api.teamGrid(period)),
          builder: (grid) => TeamGridView(grid: grid, dayWidth: grid.days.length > 10 ? 36 : 48),
        ),
      ]),
    );
  }
}
