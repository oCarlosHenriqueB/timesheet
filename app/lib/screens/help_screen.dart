import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../download.dart';
import '../manual.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';
import '../widgets/manual_view.dart';

/// Ajuda: o manual (assets/MANUAL.md) dentro do app. Projetista não vê a parte do gestor.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, required this.user});

  final User user;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late final Future<List<ManualBlock>> data = rootBundle
      .loadString('assets/MANUAL.md')
      .then((md) => manualFor(parseManual(md), isManager: widget.user.isManager));
  final keys = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    return FutureView(
      future: data,
      onRetry: () {},
      builder: (blocks) {
        final sections = [for (final b in blocks) if (b is ManualHeading && b.level == 2) b.text];
        for (final s in sections) {
          keys.putIfAbsent(s, GlobalKey.new);
        }
        return PageBody(children: [
          PageHeader(
            title: 'Ajuda',
            subtitle: widget.user.isManager
                ? 'Manual do Timesheet para projetistas e gestores'
                : 'Manual do Timesheet para projetistas',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in sections)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => Scrollable.ensureVisible(
                      keys[s]!.currentContext!,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ManualView(blocks: blocks, onLink: openUrl, headingKeys: keys),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
