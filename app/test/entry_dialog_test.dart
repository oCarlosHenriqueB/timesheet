import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/pages/entries_page.dart';

void main() {
  testWidgets('EntryDialog valida e devolve o rascunho', (tester) async {
    final projects = [Project(id: 7, code: 'PRJ-1', name: 'Teste', active: true)];
    EntryDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showDialog<EntryDraft>(context: context, builder: (_) => EntryDialog(projects: projects)),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Lançar horas'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Informe um número.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Horas'), '1,5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(result?.hours, 1.5);
    expect(result?.projectId, 7);
  });
}
