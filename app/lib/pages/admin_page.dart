import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'common.dart';

/// Cadastro de projetos e usuários (só gestores).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api});

  final Api api;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<(List<Project>, List<User>)> data = _load();

  Future<(List<Project>, List<User>)> _load() async =>
      (await widget.api.projects(includeInactive: true), await widget.api.users());

  void _reload() => setState(() => data = _load());

  Future<void> _newProject() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _FormDialog(title: 'Novo projeto', fields: ['Código', 'Nome']),
    );
    if (values == null || !mounted) return;
    await runWithFeedback(context, () => widget.api.createProject(values[0], values[1]), 'Projeto criado.');
    _reload();
  }

  Future<void> _newUser() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _FormDialog(
        title: 'Novo usuário',
        fields: ['Nome', 'E-mail', 'Senha inicial'],
        withRole: true,
      ),
    );
    if (values == null || !mounted) return;
    await runWithFeedback(
        context, () => widget.api.createUser(values[0], values[1], values[2], values[3]), 'Usuário criado.');
    _reload();
  }

  Future<void> _toggle(Project p, bool active) async {
    await runWithFeedback(context, () => widget.api.setProjectActive(p.id, active),
        active ? 'Projeto reativado.' : 'Projeto desativado.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return FutureView(
      future: data,
      onRetry: _reload,
      builder: (result) {
        final (projects, users) = result;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(child: Text('Projetos', style: titleStyle)),
              TextButton.icon(onPressed: _newProject, icon: const Icon(Icons.add), label: const Text('Novo')),
            ]),
            for (final p in projects)
              Card(
                child: SwitchListTile(
                  title: Text(p.label),
                  subtitle: Text(p.active ? 'Ativo' : 'Inativo: não aceita novos lançamentos'),
                  value: p.active,
                  onChanged: (v) => _toggle(p, v),
                ),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Usuários', style: titleStyle)),
              TextButton.icon(onPressed: _newUser, icon: const Icon(Icons.person_add), label: const Text('Novo')),
            ]),
            for (final u in users)
              Card(
                child: ListTile(
                  leading: Icon(u.isManager ? Icons.admin_panel_settings : Icons.engineering),
                  title: Text(u.name),
                  subtitle: Text('${u.email} · ${u.isManager ? 'gestor' : 'técnico'}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Diálogo genérico de campos de texto obrigatórios; devolve os valores na ordem.
/// Com [withRole], acrescenta a escolha de papel como último valor.
class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.title, required this.fields, this.withRole = false});

  final String title;
  final List<String> fields;
  final bool withRole;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final form = GlobalKey<FormState>();
  late final controllers = [for (final _ in widget.fields) TextEditingController()];
  String role = 'tecnico';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < widget.fields.length; i++)
              TextFormField(
                controller: controllers[i],
                autofocus: i == 0,
                obscureText: widget.fields[i].startsWith('Senha'),
                decoration: InputDecoration(labelText: widget.fields[i]),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Obrigatório.';
                  if (widget.fields[i].startsWith('Senha') && v.length < 6) return 'Mínimo de 6 caracteres.';
                  return null;
                },
              ),
            if (widget.withRole) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'tecnico', label: Text('Técnico')),
                  ButtonSegment(value: 'gestor', label: Text('Gestor')),
                ],
                selected: {role},
                onSelectionChanged: (s) => setState(() => role = s.first),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, [for (final c in controllers) c.text.trim(), if (widget.withRole) role]);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
