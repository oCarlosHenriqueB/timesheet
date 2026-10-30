import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Título da página com subtítulo e ações à direita.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ]),
        ),
        Wrap(spacing: 8, children: actions),
      ]),
    );
  }
}

/// Área com rolagem e largura máxima, padrão de todas as telas.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// Cartão com título, ações opcionais e conteúdo.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.actions = const [], required this.child, this.padding});

  final String? title;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(children: [
              Expanded(
                child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              ...actions,
            ]),
          ),
        Padding(padding: padding ?? const EdgeInsets.fromLTRB(16, 4, 16, 16), child: child),
      ]),
    );
  }
}

/// Indicador numérico do dashboard.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.icon, this.caption});

  final String label;
  final String value;
  final IconData icon;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              Text(value, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (caption != null) Text(caption!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Distribui cartões em colunas que quebram linha em telas estreitas.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({super.key, required this.children, this.minChildWidth = 220, this.spacing = 16});

  final List<Widget> children;
  final double minChildWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final perRow = (c.maxWidth / (minChildWidth + spacing)).floor().clamp(1, children.length);
      final width = (c.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    });
  }
}

/// Selo do status do apontamento.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final EntryStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EntryStatus.rascunho => const Color(0xFF6B7280),
      EntryStatus.enviado => AppColors.primary,
      EntryStatus.aprovado => const Color(0xFF2E7D32),
      EntryStatus.rejeitado => const Color(0xFFC62828),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Mensagem para listas vazias.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(children: [
        Icon(icon, size: 36, color: AppColors.textMuted),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Tabela com rolagem horizontal, para não quebrar em telas menores.
class ScrollableTable extends StatelessWidget {
  const ScrollableTable({super.key, required this.table});

  final DataTable table;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: table),
      ),
    );
  }
}
