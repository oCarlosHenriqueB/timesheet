import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/pages/project_dialog.dart';

void main() {
  testWidgets('novo projeto exige número e cliente; horas previstas aceitam vírgula', (tester) async {
    ProjectDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showDialog<ProjectDraft>(context: context, builder: (_) => const ProjectDialog()),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Obrigatório.'), findsNWidgets(2));

    await tester.enterText(find.widgetWithText(TextFormField, 'Projeto (número)'), 'PRJ-100');
    await tester.enterText(find.widgetWithText(TextFormField, 'Cliente'), 'Hospital Teste');
    await tester.enterText(find.widgetWithText(TextFormField, 'Horas previstas'), '0');
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Precisa ser maior que zero.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Horas previstas'), '12,5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(result?.code, 'PRJ-100');
    expect(result?.client, 'Hospital Teste');
    expect(result?.budgetHours, 12.5);
    expect(result?.dueDate, isNull);
  });

  testWidgets('edição trava o número e mantém os valores', (tester) async {
    final project = Project(id: 1, code: 'OLD-1', client: '', description: 'Antigo');
    ProjectDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showDialog<ProjectDraft>(context: context, builder: (_) => ProjectDialog(project: project)),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Editar projeto'), findsOneWidget);

    // Projeto antigo sem cliente: o gestor precisa preencher ao editar.
    await tester.enterText(find.widgetWithText(TextFormField, 'Cliente'), 'Cliente Novo');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(result?.client, 'Cliente Novo');
    expect(result?.description, 'Antigo');
    expect(result?.budgetHours, isNull);
  });
}
