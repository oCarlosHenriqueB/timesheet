import 'package:flutter/material.dart';

import '../budget.dart';
import '../format.dart';
import '../models.dart';

/// Cartão de projeto com o saldo de horas e o prazo, cada um com seu selo colorido.
/// Usado em Cadastros e no relatório por projeto.
class ProjectStatusCard extends StatelessWidget {
  const ProjectStatusCard({super.key, required this.project, this.trailing, this.onTap, this.note});

  final Project project;

  /// Texto extra no selo neutro, ex.: horas no período do relatório.
  final String? note;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final today = DateTime.now();
    final text = Theme.of(context).textTheme;
    final hours = hoursHealth(p);
    final budget = p.budgetHours;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(color: (p.active ? projectHealth(p, today) : Health.none).color, width: 6)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.label, style: text.titleSmall),
                    if (p.description.isNotEmpty) Text(p.description, style: text.bodySmall),
                    if (budget != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        // Barra decrescente: cheia no início, esvazia conforme as horas são lançadas.
                        value: (p.remainingHours! / budget).clamp(0.0, 1.0),
                        color: hours.color,
                        backgroundColor: hours.color.withValues(alpha: 0.15),
                        minHeight: 6,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      StatusBadge(health: hours, label: hoursLabel(p)),
                      StatusBadge(health: dateHealth(p, today), label: dateLabel(p, today)),
                      if (note != null) StatusBadge(health: Health.none, label: note!),
                      if (!p.active) const StatusBadge(health: Health.none, label: 'Inativo'),
                    ]),
                    if (budget == null) ...[
                      const SizedBox(height: 4),
                      Text('Lançadas ${formatHours(p.usedHours)}', style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

String hoursLabel(Project p) {
  final budget = p.budgetHours;
  if (budget == null) return 'Sem horas previstas';
  final remaining = p.remainingHours!;
  if (remaining < 0) return 'Estourado em ${formatHours(-remaining)} (${formatHours(p.usedHours)} de ${formatHours(budget)})';
  final pct = (remaining / budget * 100).round();
  return 'Saldo ${formatHours(remaining)} de ${formatHours(budget)} ($pct%)';
}

String dateLabel(Project p, DateTime today) {
  final due = p.dueDate;
  if (due == null) return 'Sem prazo';
  final days = daysUntil(due, today);
  final when = switch (days) {
    < 0 => 'atrasada há ${-days} dia(s)',
    0 => 'hoje',
    1 => 'amanhã',
    _ => 'faltam $days dias',
  };
  return 'Entrega ${formatDate(due)} · $when';
}

/// Selo com bolinha e texto na cor da situação.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.health, required this.label});

  final Health health;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: health.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: health.color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: health == Health.none ? null : health.textColor,
                    fontWeight: health.index >= Health.critical.index ? FontWeight.w600 : null,
                  )),
        ),
      ]),
    );
  }
}

/// Legenda das cores, para o gestor entender as faixas.
class HealthLegend extends StatelessWidget {
  const HealthLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Health.ok, 'Até 70% das horas · entrega em mais de 7 dias'),
      (Health.warning, '70–90% · entrega em até 7 dias'),
      (Health.critical, 'Acima de 90% · entrega atrasada'),
      (Health.over, 'Horas estouradas (> 100%)'),
      (Health.none, 'Sem horas previstas / sem prazo'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (h, label) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: h.color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
      ],
    );
  }
}
