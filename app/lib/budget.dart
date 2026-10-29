import 'package:flutter/material.dart';

import 'models.dart';

/// Situação do projeto quanto ao saldo de horas e à data de entrega.
/// A ordem importa: quanto mais para o fim, mais grave.
enum Health { none, ok, warning, critical, over }

extension HealthStyle on Health {
  Color get color => switch (this) {
        Health.none => const Color(0xFF9E9E9E),
        Health.ok => const Color(0xFF2E7D32),
        Health.warning => const Color(0xFFF9A825),
        Health.critical => const Color(0xFFEF6C00),
        Health.over => const Color(0xFFC62828),
      };
}

/// Faixas pelo saldo de horas que ainda resta:
/// verde acima de 30%, amarelo até 30%, laranja até 10%, vermelho quando fica negativo.
Health hoursHealth(Project p) {
  final budget = p.budgetHours;
  if (budget == null || budget <= 0) return Health.none;
  final remaining = (budget - p.usedHours) / budget;
  if (remaining < 0) return Health.over;
  if (remaining <= 0.10) return Health.critical;
  if (remaining <= 0.30) return Health.warning;
  return Health.ok;
}

/// Faixas pela data de entrega: amarelo a 7 dias, laranja a 2 dias, vermelho vencida.
Health dateHealth(Project p, DateTime today) {
  final due = p.dueDate;
  if (due == null) return Health.none;
  final days = daysUntil(due, today);
  if (days < 0) return Health.over;
  if (days <= 2) return Health.critical;
  if (days <= 7) return Health.warning;
  return Health.ok;
}

/// A cor do projeto é a pior entre horas e data.
Health projectHealth(Project p, DateTime today) {
  final h = hoursHealth(p);
  final d = dateHealth(p, today);
  return h.index >= d.index ? h : d;
}

/// Dias corridos entre as datas (em UTC, para não errar em horário de verão).
int daysUntil(DateTime due, DateTime today) => DateTime.utc(due.year, due.month, due.day)
    .difference(DateTime.utc(today.year, today.month, today.day))
    .inDays;
