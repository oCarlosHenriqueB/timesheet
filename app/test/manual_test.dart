import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/manual.dart';
import 'package:timesheet/widgets/manual_view.dart';

void main() {
  test('lê títulos, parágrafos, listas e tabelas', () {
    final blocks = parseManual('# T\n\nUm texto\ncontinua.\n\n1. um\n2. dois\n\n- a\n- b\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n');
    expect(blocks[0], isA<ManualHeading>());
    expect((blocks[1] as ManualParagraph).text, 'Um texto continua.');
    expect((blocks[2] as ManualList).ordered, isTrue);
    expect((blocks[2] as ManualList).items, ['um', 'dois']);
    expect((blocks[3] as ManualList).items, ['a', 'b']);
    expect((blocks[4] as ManualTable).rows, [['A', 'B'], ['1', '2']]);
  });

  test('negrito e links no texto', () {
    final parts = parseInline('Clique em **Registrar** ou veja [o site](https://x.y).');
    expect(parts.map((p) => p.text).join(), 'Clique em Registrar ou veja o site.');
    expect(parts[1].bold, isTrue);
    expect(parts[3].url, 'https://x.y');
  });

  test('o manual do app: projetista não vê a seção do gestor', () {
    final blocks = parseManual(File('assets/MANUAL.md').readAsStringSync());
    String titles(List<ManualBlock> b) =>
        b.whereType<ManualHeading>().where((h) => h.level == 2).map((h) => h.text).join(' | ');
    expect(titles(manualFor(blocks, isManager: true)),
        '1. Acesso | 2. Para o projetista | 3. Para o gestor | 4. O que as cores significam | 5. Dúvidas comuns');
    final designer = manualFor(blocks, isManager: false);
    expect(titles(designer), '1. Acesso | 2. Para o projetista | 4. O que as cores significam | 5. Dúvidas comuns');
    expect(designer.whereType<ManualHeading>().any((h) => h.text == 'Equipe do projeto'), isFalse);
  });

  testWidgets('mostra o manual e abre links', (tester) async {
    String? opened;
    final blocks = parseManual('# T\n\n## Seção\n\nVeja [o app](https://app).\n');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ManualView(blocks: blocks, onLink: (u) => opened = u)),
    ));
    expect(find.text('Seção'), findsOneWidget);
    expect(find.text('T'), findsNothing); // o título fica no cabeçalho da página
    await tester.tapOnText(find.textRange.ofSubstring('o app'));
    expect(opened, 'https://app');
  });
}
