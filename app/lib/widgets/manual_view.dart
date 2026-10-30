import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../manual.dart';
import '../theme.dart';

/// Mostra os blocos do manual com o estilo do app. [headingKeys] recebe uma chave por
/// título de nível 2, para o índice rolar até a seção.
class ManualView extends StatelessWidget {
  const ManualView({super.key, required this.blocks, required this.onLink, this.headingKeys = const {}});

  final List<ManualBlock> blocks;
  final ValueChanged<String> onLink;
  final Map<String, GlobalKey> headingKeys;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = text.bodyLarge?.copyWith(height: 1.5, color: const Color(0xFF1F2933));
    final children = <Widget>[];
    for (final b in blocks) {
      switch (b) {
        case ManualHeading(level: 1):
          continue; // o título já está no cabeçalho da página
        case ManualHeading(level: 2, :final text):
          children.add(Padding(
            key: headingKeys[text],
            padding: const EdgeInsets.only(top: 28, bottom: 8),
            child: Text(text,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    )),
          ));
        case ManualHeading(:final text):
          children.add(Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ));
        case ManualParagraph(:final text):
          children.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _rich(text, body)));
        case ManualList(:final ordered, :final items):
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, item) in items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 28,
                      child: Text(ordered ? '${i + 1}.' : '•',
                          style: body?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: _rich(item, body)),
                  ]),
                ),
            ]),
          ));
        case ManualTable(:final rows):
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Table(
              border: TableBorder.all(color: AppColors.border),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final (r, row) in rows.indexed)
                  TableRow(
                    decoration: BoxDecoration(color: r == 0 ? AppColors.background : null),
                    children: [
                      for (final cell in row)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: _rich(cell, r == 0 ? body?.copyWith(fontWeight: FontWeight.w600) : body),
                        ),
                    ],
                  ),
              ],
            ),
          ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _rich(String text, TextStyle? style) {
    return Text.rich(TextSpan(style: style, children: [
      for (final p in parseInline(text))
        TextSpan(
          text: p.text,
          style: TextStyle(
            fontWeight: p.bold ? FontWeight.w700 : null,
            color: p.url != null ? AppColors.primary : null,
            decoration: p.url != null ? TextDecoration.underline : null,
          ),
          recognizer: p.url == null ? null : (TapGestureRecognizer()..onTap = () => onLink(p.url!)),
        ),
    ]));
  }
}
