import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timesheet/budget.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/widgets/team_grid.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('cor do dia: horas acumuladas × previstas e dia × prazo', () {
    final due = DateTime(2026, 11, 20);
    Health h(double acc, DateTime day) => gridHealth(budget: 40, accumulated: acc, due: due, day: day);
    expect(h(10, DateTime(2026, 11, 1)), Health.ok);
    expect(h(30, DateTime(2026, 11, 1)), Health.warning); // 75%
    expect(h(10, DateTime(2026, 11, 15)), Health.warning); // 5 dias do prazo
    expect(h(37, DateTime(2026, 11, 1)), Health.critical); // 92,5%
    expect(h(10, DateTime(2026, 11, 21)), Health.critical); // depois do prazo
    expect(h(41, DateTime(2026, 11, 1)), Health.over); // estourou
    expect(gridHealth(budget: null, accumulated: 50, due: null, day: DateTime(2026, 11, 1)), Health.none);
  });

  testWidgets('grade colore cada dia pelo acumulado e agrupa por colaborador', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final grid = TeamGrid.fromJson({
      'days': ['2026-11-02', '2026-11-03', '2026-11-04'],
      'rows': [
        {
          'user_id': 1,
          'user_name': 'Ana Souza',
          'project_id': 5,
          'project_code': 'PRJ-1',
          'project_client': 'Montadora A',
          'allocated': true,
          'budget_hours': 10,
          'due_date': '2030-01-01',
          'hours_before': 5,
          'total_hours': 12,
          'days': {'2026-11-02': 2, '2026-11-03': 5},
        },
        {
          'user_id': 1,
          'user_name': 'Ana Souza',
          'project_id': 6,
          'project_code': 'INT-1',
          'project_client': '',
          'allocated': false,
          'budget_hours': null,
          'due_date': null,
          'hours_before': 0,
          'total_hours': 1,
          'days': {'2026-11-04': 1},
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeamGridView(grid: grid))));

    expect(find.textContaining('Ana Souza', findRichText: true), findsOneWidget); // um cabeçalho por pessoa
    expect(find.textContaining('8 h no período', findRichText: true), findsOneWidget);
    expect(find.text('INT-1 (sem alocação)'), findsOneWidget);

    // A célula de horas é o Container com fundo colorido (o cabeçalho também tem os números dos dias).
    final coloredBox = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null);
    Color colorOf(String hours) {
      final box = tester.widget<Container>(find.ancestor(of: find.text(hours), matching: coloredBox).first);
      return (box.decoration as BoxDecoration).color!;
    }

    expect(colorOf('2'), Health.warning.color); // 5 + 2 = 7 de 10 → 70%
    expect(colorOf('5'), Health.over.color); // 12 de 10 → estourou
    expect(colorOf('1'), Health.none.color); // sem previsto nem prazo
  });
}
