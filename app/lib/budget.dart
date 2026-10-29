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
Health hoursHealth(Project p) {
  final budget = p.budgetHours;
  if (budget == null || budget <= 0) return Health.none;
  final used = p.usedHours / budget;
  if (used > 1.0) return Health.over;
  if (used > 0.90) return Health.critical;
  if (used >= 0.70) return Health.warning;
  return Health.ok;
}

/// Faixas pela data de entrega: amarelo a partir de 7 dias antes (inclui hoje),
/// vermelho quando atrasada.
Health dateHealth(Project p, DateTime today) {
  final due = p.dueDate;
  if (due == null) return Health.none;
  final days = daysUntil(due, today);
  if (days < 0) return Health.critical;
  if (days <= 7) return Health.warning;
  return Health.ok;
}

/// A faixa lateral do cartão usa a pior situação entre horas e data.
Health projectHealth(Project p, DateTime today) {
  final h = hoursHealth(p);
  final d = dateHealth(p, today);
  return h.index >= d.index ? h : d;
}

/// Dias corridos entre as datas (em UTC, para não errar em horário de verão).
int daysUntil(DateTime due, DateTime today) => DateTime.utc(due.year, due.month, due.day)
    .difference(DateTime.utc(today.year, today.month, today.day))
    .inDays;
