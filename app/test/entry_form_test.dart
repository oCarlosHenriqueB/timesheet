import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/format.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/widgets/entry_form.dart';

final projects = [Project(id: 7, code: 'PRJ-7', client: 'Cliente')];
final activities = [Activity(id: 2, name: 'Instalação'), Activity(id: 3, name: 'Calibração')];

Future<List<EntryDraft>> pumpForm(WidgetTester tester, {Entry? entry, String? suggestedStart}) async {
  final saved = <EntryDraft>[];
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: EntryForm(
          projects: projects,
          activities: activities,
          entry: entry,
          suggestedStart: suggestedStart,
          onSubmit: (d) async {
            saved.add(d);
            return true;
          },
        ),
      ),
    ),
  ));
  return saved;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  test('parseTime aceita formatos comuns', () {
    expect(parseTime('8'), '08:00');
    expect(parseTime('830'), '08:30');
    expect(parseTime('0830'), '08:30');
    expect(parseTime('8:30'), '08:30');
    expect(parseTime('8h30'), '08:30');
    expect(parseTime('17:05'), '17:05');
    expect(parseTime('24:00'), isNull);
    expect(parseTime('8:75'), isNull);
    expect(parseTime('abc'), isNull);
  });

  test('workedHours desconta o intervalo e recusa período inválido', () {
    expect(workedHours('08:00', '12:30', 15), 4.25);
    expect(workedHours('08:00', '07:00', 0), isNull);
    expect(workedHours('08:00', '09:00', 60), isNull);
    expect(workedHours(null, '09:00', 0), isNull);
  });

  testWidgets('calcula o total, exige atividade e prepara o próximo apontamento', (tester) async {
    final saved = await pumpForm(tester, suggestedStart: '13:00');
    expect(find.text('13:00'), findsOneWidget);

    await tester.enterText(field('Fim'), '1715');
    await tester.enterText(field('Intervalo'), '15');
    await tester.pump();
    expect(find.text('Total: 4 h'), findsOneWidget);

    await tester.tap(find.text('Registrar'));
    await tester.pump();
    expect(find.text('Escolha a atividade.'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.tap(find.text('Atividade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calibração').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Descrição do trabalho realizado'), 'Calibração do compressor');
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();

    final d = saved.single;
    expect((d.projectId, d.activityId, d.startTime, d.endTime, d.breakMinutes), (7, 3, '13:00', '17:15', 15));
    expect(d.description, 'Calibração do compressor');
    expect(d.toJson().containsKey('hours'), isFalse);
    // Próximo começa onde este terminou; projeto e atividade ficam
    expect(find.text('17:15'), findsOneWidget);
    expect(find.text('Calibração'), findsOneWidget);
  });

  testWidgets('fim antes do início bloqueia o registro', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Fim'), '07:00');
    await tester.pump();
    expect(find.textContaining('Fim antes do início'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(of: find.text('Registrar'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('lançamento antigo (sem horários) é editado pelo total', (tester) async {
    final old = Entry(
      id: 1,
      userName: 'Ana',
      projectId: 7,
      projectCode: 'PRJ-7',
      projectClient: 'Cliente',
      date: DateTime(2026, 10, 1),
      hours: 2.5,
    );
    final saved = await pumpForm(tester, entry: old);
    expect(field('Início'), findsNothing);
    expect(find.text('2,5'), findsOneWidget);
    await tester.tap(find.text('Atividade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalação').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(saved.single.hours, 2.5);
    expect(saved.single.startTime, isNull);
  });
}
