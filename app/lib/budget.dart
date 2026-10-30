import 'package:flutter/material.dart';

import 'models.dart';

/// Situação do projeto quanto às horas e à data de entrega.
/// A ordem importa: quanto mais para o fim, mais grave.
enum Health { none, ok, warning, critical, over }

extension HealthStyle on Health {
  Color get color => switch (this) {
        Health.none => const Color(0xFF9E9E9E),
        Health.ok => const Color(0xFF2E7D32),
        Health.warning => const Color(0xFFF9A825),
        Health.critical => const Color(0xFFC62828),
        Health.over => const Color(0xFF6A1B9A), // destaque próprio: horas estouradas
      };

  /// O amarelo é claro demais para texto; usa um tom mais escuro.
  Color get textColor => this == Health.warning ? const Color(0xFF8D6E00) : color;
}

/// Faixas pelas horas já usadas do orçamento:
/// verde até 70%, amarelo de 70% a 90%, vermelho acima de 90%, roxo acima de 100% (estourado).
Health hoursHealth(Project p) => hoursHealthOf(p.budgetHours, p.usedHours);

Health hoursHealthOf(double? budget, double used) {
  if (budget == null || budget <= 0) return Health.none;
  final share = used / budget;
  if (share > 1.0) return Health.over;
  if (share > 0.90) return Health.critical;
  if (share >= 0.70) return Health.warning;
  return Health.ok;
}

/// Faixas pela data de entrega: amarelo a partir de 7 dias antes (inclui hoje),
/// vermelho quando atrasada.
Health dateHealth(Project p, DateTime today) => dateHealthOf(p.dueDate, today);

Health dateHealthOf(DateTime? due, DateTime day) {
  if (due == null) return Health.none;
  final days = daysUntil(due, day);
  if (days < 0) return Health.critical;
  if (days <= 7) return Health.warning;
  return Health.ok;
}

Health worst(Health a, Health b) => a.index >= b.index ? a : b;

/// Situação de uma pessoa num projeto em um dia da grade: horas acumuladas até aquele dia
/// contra as horas previstas dela, e aquele dia contra o prazo dela.
Health gridHealth({required double? budget, required double accumulated, required DateTime? due, required DateTime day}) =>
    worst(hoursHealthOf(budget, accumulated), dateHealthOf(due, day));

/// A faixa lateral do cartão usa a pior situação entre horas e data.
Health projectHealth(Project p, DateTime today) => worst(hoursHealth(p), dateHealth(p, today));

/// Dias corridos entre as datas (em UTC, para não errar em horário de verão).
int daysUntil(DateTime due, DateTime today) => DateTime.utc(due.year, due.month, due.day)
    .difference(DateTime.utc(today.year, today.month, today.day))
    .inDays;
