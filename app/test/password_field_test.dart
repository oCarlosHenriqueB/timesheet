import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/widgets/password_field.dart';

void main() {
  testWidgets('o olho mostra e esconde a senha', (tester) async {
    final c = TextEditingController(text: 'Segredo1');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PasswordField(controller: c, label: 'Senha'))));
    bool obscured() => tester.widget<EditableText>(find.byType(EditableText)).obscureText;

    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pump();
    expect(obscured(), isFalse);
    expect(find.text('Segredo1'), findsOneWidget);
    await tester.tap(find.byTooltip('Esconder senha'));
    await tester.pump();
    expect(obscured(), isTrue);
  });
}
