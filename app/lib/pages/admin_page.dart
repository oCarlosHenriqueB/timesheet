import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'common.dart';
import 'project_dialog.dart';
import 'project_status.dart';
import 'sap_import_dialog.dart';

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

  Future<void> _editProject([Project? project]) async {
    final draft = await showDialog<ProjectDraft>(
      context: context,
      builder: (_) => ProjectDialog(project: project, onSapLookup: widget.api.lookupSapProject),
    );
    if (draft == null || !mounted) return;
    await runWithFeedback(
      context,
      () => project == null ? widget.api.createProject(draft) : widget.api.updateProject(project.id, draft),
      project == null ? 'Projeto criado.' : 'Projeto atualizado.',
    );
    _reload();
  }

  Future<void> _importSap() async {
    await showDialog<bool>(context: context, builder: (_) => SapImportDialog(api: widget.api));
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
              TextButton.icon(
                onPressed: _importSap,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Catálogo SAP'),
              ),
              TextButton.icon(onPressed: _editProject, icon: const Icon(Icons.add), label: const Text('Novo')),
            ]),
            const HealthLegend(),
            const SizedBox(height: 8),
            for (final p in projects)
              ProjectStatusCard(
                project: p,
                onTap: () => _editProject(p),
                trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editProject(p)),
                  Tooltip(
                    message: p.active ? 'Ativo' : 'Inativo',
                    child: Switch(value: p.active, onChanged: (v) => _toggle(p, v)),
                  ),
                ]),
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
