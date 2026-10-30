import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';
import '../widgets/team_grid.dart';

/// Área do gestor: acompanhamento da equipe, usuários e atividades.
/// A aprovação de horas entra aqui na fase gerencial.
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key, required this.api, required this.user});

  final Api api;

  /// Gestor logado (não pode excluir a si mesmo).
  final User user;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  late Future<(List<User>, List<Activity>, List<ReportRow>)> data = _load();

  Future<(List<User>, List<Activity>, List<ReportRow>)> _load() async => (
        await widget.api.users(),
        await widget.api.activities(includeInactive: true),
        await widget.api.reportByUser(period: Period.of(PeriodPreset.thisWeek, DateTime.now())),
      );

  void _reload() => setState(() => data = _load());

  Future<void> _newUser() async {
    final values = await showDialog<List<String>>(context: context, builder: (_) => const _UserDialog());
    if (values == null || !mounted) return;
    await runWithFeedback(
        context, () => widget.api.createUser(values[0], values[1], values[2], values[3]), 'Usuário criado.');
    _reload();
  }

  Future<void> _editUser(User u) async {
    final values = await showDialog<List<String>>(context: context, builder: (_) => _UserDialog(user: u));
    if (values == null || !mounted) return;
    final [name, email, password, role] = values;
    await runWithFeedback(
      context,
      () => widget.api.updateUser(
        u.id,
        name: name,
        email: email,
        role: role,
        password: password.isEmpty ? null : password,
      ),
      password.isEmpty ? 'Usuário atualizado.' : 'Usuário atualizado e senha redefinida.',
    );
    _reload();
  }

  Future<void> _deleteUser(User u) async {
    final ok = await confirm(
      context,
      'Excluir ${u.name}? A pessoa perde o acesso e sai das equipes dos projetos. '
      'Se já lançou horas, o usuário fica desativado para manter o histórico e os relatórios.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await widget.api.deleteUser(u.id);
      messenger.showSnackBar(SnackBar(
        content: Text(deleted ? '${u.name} foi excluído.' : '${u.name} foi desativado; as horas lançadas continuam no histórico.'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    _reload();
  }

  Future<void> _reactivate(User u) async {
    await runWithFeedback(context, () => widget.api.updateUser(u.id, active: true), '${u.name} foi reativado.');
    _reload();
  }

  Future<void> _activityName([Activity? activity]) async {
    final controller = TextEditingController(text: activity?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activity == null ? 'Nova atividade' : 'Renomear atividade'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome'),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await runWithFeedback(
      context,
      () => activity == null ? widget.api.createActivity(name) : widget.api.updateActivity(activity.id, name: name),
      activity == null ? 'Atividade criada.' : 'Atividade renomeada.',
    );
    _reload();
  }

  Future<void> _toggleActivity(Activity a) async {
    await runWithFeedback(context, () => widget.api.updateActivity(a.id, active: !a.active),
        a.active ? 'Atividade desativada.' : 'Atividade reativada.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: PageBody(children: [
        const PageHeader(title: 'Gestão', subtitle: 'Equipe, usuários e atividades'),
        const Card(
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Acompanhamento da equipe'), Tab(text: 'Usuários'), Tab(text: 'Atividades')],
          ),
        ),
        const SizedBox(height: 16),
        FutureView(
          future: data,
          onRetry: _reload,
          builder: (d) {
            final (users, activities, week) = d;
            return SizedBox(
              height: 900,
              child: TabBarView(children: [
                _team(week),
                _users(users),
                _activities(activities),
              ]),
            );
          },
        ),
      ]),
    );
  }

  Widget _team(List<ReportRow> week) {
    final total = week.fold<double>(0, (s, r) => s + r.totalHours);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          color: AppColors.primary.withValues(alpha: 0.06),
          child: const ListTile(
            leading: Icon(Icons.fact_check_outlined, color: AppColors.primary),
            title: Text('Aprovação de horas (próxima fase)'),
            subtitle: Text(
                'Os apontamentos já têm status (Enviado, Aprovado, Rejeitado). Aqui o gestor vai aprovar ou '
                'devolver os apontamentos da equipe. Por enquanto, use o Histórico com "Toda a equipe" para consultar.'),
          ),
        ),
        const SizedBox(height: 16),
        TeamGridCard(api: widget.api, title: 'Dia a dia por colaborador e projeto'),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Horas da equipe nesta semana · ${formatHours(total)}',
          child: week.isEmpty
              ? const EmptyState(message: 'Sem horas nesta semana.')
              : BarList(items: [for (final r in week) (r.label, r.totalHours, r.detail)]),
        ),
      ]),
    );
  }

  Widget _users(List<User> users) {
    return SingleChildScrollView(
      child: SectionCard(
        title: '${users.length} usuário(s)',
        actions: [FilledButton.icon(onPressed: _newUser, icon: const Icon(Icons.person_add), label: const Text('Novo usuário'))],
        padding: const EdgeInsets.only(bottom: 8),
        child: ScrollableTable(
          table: DataTable(columns: const [
            DataColumn(label: Text('Nome')),
            DataColumn(label: Text('E-mail')),
            DataColumn(label: Text('Perfil')),
            DataColumn(label: Text('Situação')),
            DataColumn(label: Text('')),
          ], rows: [
            for (final u in users)
              DataRow(cells: [
                DataCell(Text(u.name, style: TextStyle(color: u.active ? null : AppColors.textMuted))),
                DataCell(Text(u.email, style: TextStyle(color: u.active ? null : AppColors.textMuted))),
                DataCell(Text(u.roleLabel)),
                DataCell(Text(u.active ? 'Ativo' : 'Desativado (sem acesso)',
                    style: TextStyle(color: u.active ? null : AppColors.textMuted))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editUser(u),
                  ),
                  if (u.active)
                    IconButton(
                      tooltip: u.id == widget.user.id ? 'Você não pode excluir o próprio usuário' : 'Excluir',
                      icon: const Icon(Icons.person_remove_outlined, size: 18),
                      color: Colors.red.shade700,
                      onPressed: u.id == widget.user.id ? null : () => _deleteUser(u),
                    )
                  else
                    IconButton(
                      tooltip: 'Reativar',
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18, color: AppColors.primary),
                      onPressed: () => _reactivate(u),
                    ),
                ])),
              ]),
          ]),
        ),
      ),
    );
  }

  Widget _activities(List<Activity> activities) {
    return SingleChildScrollView(
      child: SectionCard(
        title: 'Atividades do apontamento',
        actions: [FilledButton.icon(onPressed: _activityName, icon: const Icon(Icons.add), label: const Text('Nova atividade'))],
        padding: const EdgeInsets.only(bottom: 8),
        child: ScrollableTable(
          table: DataTable(columns: const [
            DataColumn(label: Text('Atividade')),
            DataColumn(label: Text('Situação')),
            DataColumn(label: Text('')),
          ], rows: [
            for (final a in activities)
              DataRow(cells: [
                DataCell(Text(a.name)),
                DataCell(Text(a.active ? 'Ativa' : 'Inativa (não aparece no apontamento)',
                    style: TextStyle(color: a.active ? null : AppColors.textMuted))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Renomear',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _activityName(a),
                  ),
                  IconButton(
                    tooltip: a.active ? 'Desativar' : 'Reativar',
                    icon: Icon(a.active ? Icons.toggle_on : Icons.toggle_off_outlined,
                        color: a.active ? AppColors.primary : AppColors.textMuted),
                    onPressed: () => _toggleActivity(a),
                  ),
                ])),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Novo usuário ou edição: nome, e-mail, senha e perfil. Devolve [nome, email, senha, papel].
/// Na edição a senha é opcional (vazia = mantém a atual).
class _UserDialog extends StatefulWidget {
  const _UserDialog({this.user});

  final User? user;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.user?.name ?? '');
  late final email = TextEditingController(text: widget.user?.email ?? '');
  final password = TextEditingController();
  late String role = widget.user?.role ?? 'tecnico';

  bool get editing => widget.user != null;

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(editing ? 'Editar usuário' : 'Novo usuário'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nome'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: email, decoration: const InputDecoration(labelText: 'E-mail'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: editing ? 'Nova senha (opcional)' : 'Senha inicial',
                helperText: editing ? 'Deixe vazio para manter a senha atual.' : null,
              ),
              validator: (v) {
                final value = v ?? '';
                if (editing && value.isEmpty) return null;
                return value.length < 6 ? 'Mínimo de 6 caracteres.' : null;
              },
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'tecnico', label: Text('Projetista')),
                ButtonSegment(value: 'gestor', label: Text('Gestor')),
              ],
              selected: {role},
              onSelectionChanged: (s) => setState(() => role = s.first),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, [name.text.trim(), email.text.trim(), password.text, role]);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
