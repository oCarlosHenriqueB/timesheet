import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/entry_form.dart';

/// Edição de um apontamento existente. Fecha devolvendo true quando salva.
class EntryDialog extends StatelessWidget {
  const EntryDialog({super.key, required this.api, required this.entry, required this.projects, required this.activities});

  final Api api;
  final Entry entry;
  final List<Project> projects;
  final List<Activity> activities;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar apontamento'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: EntryForm(
            entry: entry,
            projects: projects,
            activities: activities,
            submitLabel: 'Salvar',
            onCancel: () => Navigator.pop(context, false),
            onSubmit: (draft) async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              try {
                await api.saveEntry(draft, id: entry.id);
                navigator.pop(true);
                messenger.showSnackBar(const SnackBar(content: Text('Apontamento atualizado.')));
                return true;
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
                return false;
              }
            },
          ),
        ),
      ),
    );
  }
}
