import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// Gráfico de colunas simples (ex.: horas por dia da semana), sem biblioteca externa.
class ColumnChart extends StatelessWidget {
  const ColumnChart({super.key, required this.items, this.highlight, this.height = 160});

  /// (rótulo, valor em horas)
  final List<(String, double)> items;

  /// Índice destacado (ex.: hoje).
  final int? highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = items.fold<double>(0, (m, i) => i.$2 > m ? i.$2 : m);
    final small = Theme.of(context).textTheme.bodySmall;
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, (label, value)) in items.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(value == 0 ? '' : formatNumber(value), style: small),
                const SizedBox(height: 4),
                Flexible(
                  child: FractionallySizedBox(
                    heightFactor: max == 0 || value == 0 ? 0 : (value / max).clamp(0.02, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == highlight ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(label, style: small?.copyWith(fontWeight: i == highlight ? FontWeight.w700 : null)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Barras horizontais com rótulo e valor (ex.: horas por projeto).
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items, this.maxItems = 10});

  /// (rótulo, valor em horas, detalhe opcional)
  final List<(String, double, String?)> items;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(maxItems).toList();
    final max = shown.fold<double>(0, (m, i) => i.$2 > m ? i.$2 : m);
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(children: [
      for (final (label, value, detail) in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 220,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, overflow: TextOverflow.ellipsis),
                if (detail != null) Text(detail, style: small?.copyWith(color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : value / max,
                  minHeight: 14,
                  color: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            SizedBox(width: 72, child: Text(formatHours(value), textAlign: TextAlign.right)),
          ]),
        ),
    ]);
  }
}
