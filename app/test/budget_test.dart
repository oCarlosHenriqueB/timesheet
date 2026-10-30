import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/budget.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/widgets/project_status.dart';

Project p({double? budget, double used = 0, DateTime? due}) =>
    Project(id: 1, code: 'P', client: 'C', budgetHours: budget, usedHours: used, dueDate: due);

void main() {
  final today = DateTime(2026, 10, 29);

  test('faixas pelas horas usadas: 70% / 90% / 100%', () {
    expect(hoursHealth(p()), Health.none); // sem horas previstas
    expect(hoursHealth(p(budget: 100, used: 0)), Health.ok);
    expect(hoursHealth(p(budget: 100, used: 69.9)), Health.ok);
    expect(hoursHealth(p(budget: 100, used: 70)), Health.warning);
    expect(hoursHealth(p(budget: 100, used: 90)), Health.warning);
    expect(hoursHealth(p(budget: 100, used: 90.5)), Health.critical);
    expect(hoursHealth(p(budget: 100, used: 100)), Health.critical); // saldo zero
    expect(hoursHealth(p(budget: 100, used: 100.5)), Health.over); // estourado
  });

  test('data de entrega: amarelo a 7 dias, vermelho atrasada', () {
    expect(dateHealth(p(), today), Health.none);
    expect(dateHealth(p(due: DateTime(2026, 11, 6)), today), Health.ok); // 8 dias
    expect(dateHealth(p(due: DateTime(2026, 11, 5)), today), Health.warning); // 7 dias
    expect(dateHealth(p(due: today), today), Health.warning); // hoje
    expect(dateHealth(p(due: DateTime(2026, 10, 28)), today), Health.critical); // atrasada
  });

  test('a faixa do cartão é a pior entre horas e data', () {
    expect(projectHealth(p(budget: 100, used: 10, due: DateTime(2026, 10, 28)), today), Health.critical);
    expect(projectHealth(p(budget: 100, used: 120, due: DateTime(2027, 1, 1)), today), Health.over);
  });

  test('saldo e rótulo do projeto', () {
    expect(p(budget: 80, used: 30).remainingHours, 50);
    expect(p().remainingHours, isNull);
    expect(Project(id: 1, code: 'OLD', client: '', description: 'Antigo').label, 'OLD · Antigo');
  });

  test('selos de horas e prazo', () {
    expect(hoursLabel(p()), 'Sem horas previstas');
    expect(hoursLabel(p(budget: 80, used: 60)), 'Saldo 20 h de 80 h (25%)');
    expect(hoursLabel(p(budget: 5, used: 7)), 'Estourado em 2 h (7 h de 5 h)');
    expect(dateLabel(p(), today), 'Sem prazo');
    expect(dateLabel(p(due: DateTime(2026, 11, 3)), today), 'Entrega 03/11/2026 · faltam 5 dias');
    expect(dateLabel(p(due: DateTime(2026, 10, 27)), today), 'Entrega 27/10/2026 · atrasada há 2 dia(s)');
  });

  test('ProjectDraft envia data só com o dia', () {
    final json = ProjectDraft(code: 'P', client: 'C', budgetHours: 10, dueDate: DateTime(2026, 12, 1)).toJson();
    expect(json['due_date'], '2026-12-01');
    expect(ProjectDraft(code: 'P', client: 'C').toJson()['budget_hours'], isNull);
  });
}
