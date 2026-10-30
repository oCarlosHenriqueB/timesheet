import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timesheet/api.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/pages/launch_panel.dart';

class FakeApi extends Api {
  final saved = <EntryDraft>[];

  @override
  Future<RunningTimer?> timer() async => null;

  @override
  Future<void> saveEntry(EntryDraft draft, {int? id}) async => saved.add(draft);
}

Future<void> pumpPanel(WidgetTester tester, FakeApi api, {VoidCallback? onCreated}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LaunchPanel(
          api: api,
          projects: [Project(id: 3, code: 'PRJ-3', client: 'Cliente')],
          onEntryCreated: onCreated ?? () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('começa no cronômetro e troca para manual', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPanel(tester, FakeApi());
    expect(find.text('Iniciar'), findsOneWidget);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(find.text('Lançar'), findsOneWidget);
    expect(find.text('Iniciar'), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('launch_mode'), 'manual');
  });

  testWidgets('lembra o último modo usado', (tester) async {
    SharedPreferences.setMockInitialValues({'launch_mode': 'manual'});
    await pumpPanel(tester, FakeApi());
    expect(find.text('Lançar'), findsOneWidget);
  });

  testWidgets('lançamento manual valida e salva', (tester) async {
    SharedPreferences.setMockInitialValues({'launch_mode': 'manual'});
    final api = FakeApi();
    var created = 0;
    await pumpPanel(tester, api, onCreated: () => created++);

    await tester.tap(find.text('Lançar'));
    await tester.pump();
    expect(find.text('Número'), findsOneWidget);
    expect(api.saved, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Horas'), '2,5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição (opcional)'), 'Visita');
    await tester.tap(find.text('Lançar'));
    await tester.pumpAndSettle();
    expect(api.saved.single.projectId, 3);
    expect(api.saved.single.hours, 2.5);
    expect(api.saved.single.description, 'Visita');
    expect(api.saved.single.date, DateUtils.dateOnly(DateTime.now()));
    expect(created, 1);
    expect(find.textContaining('Lançado 2,5 h'), findsOneWidget);
  });
}
