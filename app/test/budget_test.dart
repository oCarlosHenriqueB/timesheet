import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/budget.dart';
import 'package:timesheet/models.dart';

Project p({double? budget, double used = 0, DateTime? due}) =>
    Project(id: 1, code: 'P', client: 'C', budgetHours: budget, usedHours: used, dueDate: due);

void main() {
  final today = DateTime(2026, 10, 29);

  test('saldo de horas decrescente muda a cor', () {
    expect(hoursHealth(p()), Health.none); // sem horas previstas
    expect(hoursHealth(p(budget: 100, used: 0)), Health.ok); // 100% de saldo
    expect(hoursHealth(p(budget: 100, used: 69)), Health.ok); // 31%
    expect(hoursHealth(p(budget: 100, used: 70)), Health.warning); // 30%
    expect(hoursHealth(p(budget: 100, used: 90)), Health.critical); // 10%
    expect(hoursHealth(p(budget: 100, used: 100)), Health.critical); // saldo zero
    expect(hoursHealth(p(budget: 100, used: 100.5)), Health.over); // negativo
  });

  test('data de entrega muda a cor', () {
    expect(dateHealth(p(), today), Health.none);
    expect(dateHealth(p(due: DateTime(2026, 11, 6)), today), Health.ok); // 8 dias
    expect(dateHealth(p(due: DateTime(2026, 11, 5)), today), Health.warning); // 7 dias
    expect(dateHealth(p(due: DateTime(2026, 10, 31)), today), Health.critical); // 2 dias
    expect(dateHealth(p(due: today), today), Health.critical); // hoje
    expect(dateHealth(p(due: DateTime(2026, 10, 28)), today), Health.over); // vencida
  });

  test('a cor do projeto é a pior entre horas e data', () {
    expect(projectHealth(p(budget: 100, used: 10, due: DateTime(2026, 10, 30)), today), Health.critical);
    expect(projectHealth(p(budget: 100, used: 120, due: DateTime(2027, 1, 1)), today), Health.over);
  });

  test('saldo e rótulo do projeto', () {
    expect(p(budget: 80, used: 30).remainingHours, 50);
    expect(p().remainingHours, isNull);
    expect(Project(id: 1, code: 'OLD', client: '', description: 'Antigo').label, 'OLD · Antigo');
  });

  test('ProjectDraft envia data só com o dia', () {
    final json = ProjectDraft(code: 'P', client: 'C', budgetHours: 10, dueDate: DateTime(2026, 12, 1)).toJson();
    expect(json['due_date'], '2026-12-01');
    expect(ProjectDraft(code: 'P', client: 'C').toJson()['budget_hours'], isNull);
  });
}
