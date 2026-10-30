/// Leitura do manual (assets/MANUAL.md) em blocos simples, para a tela Ajuda.
/// Entende só o que o manual usa: títulos #/##/###, parágrafos, listas
/// (- e 1.), tabelas com | e, dentro do texto, **negrito** e [links](url).
sealed class ManualBlock {}

class ManualHeading extends ManualBlock {
  ManualHeading(this.level, this.text);
  final int level;
  final String text;
}

class ManualParagraph extends ManualBlock {
  ManualParagraph(this.text);
  final String text;
}

class ManualList extends ManualBlock {
  ManualList({required this.ordered, required this.items});
  final bool ordered;
  final List<String> items;
}

class ManualTable extends ManualBlock {
  ManualTable(this.rows);

  /// A primeira linha é o cabeçalho.
  final List<List<String>> rows;
}

final _ordered = RegExp(r'^\d+\.\s+');

List<ManualBlock> parseManual(String markdown) {
  final blocks = <ManualBlock>[];
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trimRight();
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      blocks.add(ManualHeading(heading.group(1)!.length, heading.group(2)!.trim()));
      i++;
    } else if (line.startsWith('|')) {
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = lines[i].trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
        final isSeparator = cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));
        if (!isSeparator) rows.add(cells);
        i++;
      }
      blocks.add(ManualTable(rows));
    } else if (line.startsWith('- ') || _ordered.hasMatch(line)) {
      final ordered = !line.startsWith('- ');
      final items = <String>[];
      while (i < lines.length) {
        final l = lines[i].trimRight();
        if (ordered && _ordered.hasMatch(l)) {
          items.add(l.replaceFirst(_ordered, ''));
        } else if (!ordered && l.startsWith('- ')) {
          items.add(l.substring(2));
        } else {
          break;
        }
        i++;
      }
      blocks.add(ManualList(ordered: ordered, items: items));
    } else {
      // Parágrafo: linhas seguidas até uma em branco ou outro tipo de bloco.
      final buffer = <String>[line.trim()];
      i++;
      while (i < lines.length) {
        final l = lines[i].trim();
        if (l.isEmpty || l.startsWith('#') || l.startsWith('|') || l.startsWith('- ') || _ordered.hasMatch(l)) break;
        buffer.add(l);
        i++;
      }
      blocks.add(ManualParagraph(buffer.join(' ')));
    }
  }
  return blocks;
}

/// Projetista não vê a seção do gestor (o título de nível 2 com "Para o gestor" e o que vem até o próximo).
List<ManualBlock> manualFor(List<ManualBlock> blocks, {required bool isManager}) {
  if (isManager) return blocks;
  final out = <ManualBlock>[];
  var skipping = false;
  for (final b in blocks) {
    if (b is ManualHeading && b.level <= 2) skipping = b.level == 2 && b.text.contains('Para o gestor');
    if (!skipping) out.add(b);
  }
  return out;
}

/// Trecho de texto com marcação: negrito e/ou link.
typedef InlinePart = ({String text, bool bold, String? url});

final _inline = RegExp(r'\*\*(.+?)\*\*|\[(.+?)\]\((.+?)\)');

List<InlinePart> parseInline(String text) {
  final parts = <InlinePart>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) parts.add((text: text.substring(last, m.start), bold: false, url: null));
    if (m.group(1) != null) {
      parts.add((text: m.group(1)!, bold: true, url: null));
    } else {
      parts.add((text: m.group(2)!, bold: false, url: m.group(3)));
    }
    last = m.end;
  }
  if (last < text.length) parts.add((text: text.substring(last), bold: false, url: null));
  return parts;
}
