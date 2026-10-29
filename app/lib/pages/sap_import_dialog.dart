import 'package:flutter/material.dart';

import '../api.dart';

/// Importa o catálogo de projetos do SAP colando o conteúdo do CSV ou as células do Excel.
/// Fecha devolvendo true quando algo foi importado.
class SapImportDialog extends StatefulWidget {
  const SapImportDialog({super.key, required this.api});

  final Api api;

  @override
  State<SapImportDialog> createState() => _SapImportDialogState();
}

class _SapImportDialogState extends State<SapImportDialog> {
  static const columns = 'projeto;cliente;pep;ordem_venda;horas_previstas;data_entrega';
  final text = TextEditingController();
  bool busy = false;
  int? imported;
  List<String> errors = const [];

  Future<void> _import() async {
    setState(() => busy = true);
    try {
      final (count, errs) = await widget.api.importSapCatalog(text.text);
      setState(() {
        imported = count;
        errors = errs;
      });
    } on ApiException catch (e) {
      setState(() => errors = [e.message]);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Importar projetos do SAP'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Exporte a lista de projetos do SAP para Excel, copie as linhas (com o cabeçalho) e cole abaixo.'),
            const SizedBox(height: 4),
            Text('Colunas: $columns', style: small),
            Text('Obrigatórias: projeto e cliente. Datas em dd/mm/aaaa ou dd.mm.aaaa.', style: small),
            const SizedBox(height: 8),
            TextField(
              controller: text,
              minLines: 6,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '$columns\nPRJ-1234;Cliente;...'),
            ),
            if (imported != null) ...[
              const SizedBox(height: 8),
              Text('$imported projeto(s) importado(s) ou atualizado(s).'),
            ],
            for (final e in errors)
              Text(e, style: small?.copyWith(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, (imported ?? 0) > 0), child: const Text('Fechar')),
        FilledButton(onPressed: busy ? null : _import, child: Text(busy ? 'Importando…' : 'Importar')),
      ],
    );
  }
}
