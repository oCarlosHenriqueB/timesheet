import 'package:flutter/material.dart';

import '../budget.dart';
import '../format.dart';
import '../models.dart';

/// Cartão de projeto com saldo de horas, entrega e a cor de alerta.
/// Usado em Cadastros e no relatório por projeto.
class ProjectStatusCard extends StatelessWidget {
  const ProjectStatusCard({super.key, required this.project, this.trailing, this.onTap});

  final Project project;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final today = DateTime.now();
    final health = p.active ? projectHealth(p, today) : Health.none;
    final text = Theme.of(context).textTheme;
    final budget = p.budgetHours;
    final remaining = p.remainingHours;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: health.color, width: 6))),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.label, style: text.titleSmall),
                    if (p.description.isNotEmpty) Text(p.description, style: text.bodySmall),
                    const SizedBox(height: 6),
                    if (budget != null) ...[
                      LinearProgressIndicator(
                        // Barra decrescente: cheia no início, esvazia conforme as horas são lançadas.
                        value: (remaining! / budget).clamp(0.0, 1.0),
                        color: hoursHealth(p).color,
                        backgroundColor: hoursHealth(p).color.withValues(alpha: 0.15),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 4),
                      Text(_hoursText(p), style: text.bodySmall?.copyWith(color: _strong(hoursHealth(p)))),
                    ] else
                      Text('Lançadas ${formatHours(p.usedHours)} · sem horas previstas', style: text.bodySmall),
                    if (p.dueDate != null)
                      Text(_dateText(p.dueDate!, today),
                          style: text.bodySmall?.copyWith(color: _strong(dateHealth(p, today)))),
                    if (!p.active) Text('Inativo: não aceita novos lançamentos', style: text.bodySmall),
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

  /// Só destaca o texto quando há alerta; verde/cinza ficam na cor normal.
  /// O amarelo da barra é claro demais para texto; usa um tom mais escuro.
  Color? _strong(Health h) => switch (h) {
        Health.warning => const Color(0xFF8D6E00),
        Health.critical || Health.over => h.color,
        _ => null,
      };

  static String _hoursText(Project p) {
    final budget = p.budgetHours!;
    final remaining = p.remainingHours!;
    if (remaining < 0) {
      return 'Estourado em ${formatHours(-remaining)} · ${formatHours(p.usedHours)} de ${formatHours(budget)}';
    }
    final pct = (remaining / budget * 100).round();
    return 'Saldo ${formatHours(remaining)} de ${formatHours(budget)} ($pct%)';
  }

  static String _dateText(DateTime due, DateTime today) {
    final days = daysUntil(due, today);
    final when = switch (days) {
      < 0 => 'vencida há ${-days} dia(s)',
      0 => 'hoje',
      1 => 'amanhã',
      _ => 'em $days dias',
    };
    return 'Entrega ${formatDate(due)} ($when)';
  }
}

/// Legenda das cores, para o gestor entender as faixas.
class HealthLegend extends StatelessWidget {
  const HealthLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Health.ok, 'Saldo > 30%'),
      (Health.warning, '≤ 30% ou entrega em 7 dias'),
      (Health.critical, '≤ 10% ou entrega em 2 dias'),
      (Health.over, 'Estourado ou vencido'),
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
