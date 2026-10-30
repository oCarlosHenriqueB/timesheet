import 'package:flutter/material.dart';

import '../api.dart';

/// Mostra carregando / erro com "Tentar de novo" / conteúdo.
class FutureView<T> extends StatelessWidget {
  const FutureView({super.key, required this.future, required this.builder, required this.onRetry});

  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
              ]),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return builder(snap.data as T);
      },
    );
  }
}

/// Executa uma chamada à API e mostra o resultado num SnackBar.
Future<void> runWithFeedback(BuildContext context, Future<void> Function() action, String success) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<bool> confirm(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
      ],
    ),
  );
  return ok ?? false;
}
