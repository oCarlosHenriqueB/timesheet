import 'package:flutter/material.dart';

import '../api.dart';
import '../budget.dart';
import '../dialogs/members_dialog.dart';
import '../dialogs/project_dialog.dart';
import '../dialogs/sap_import_dialog.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';
import '../widgets/project_status.dart';

enum _ActiveFilter { active, inactive, all }

/// Consulta de projetos: código, cliente, status, horas previstas, realizadas e prazo.
/// O gestor também cria, edita, ativa/desativa e importa o catálogo do SAP.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.api, required this.user});

  final Api api;
  final User user;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> data = _load();
  final search = TextEditingController();
  _ActiveFilter filter = _ActiveFilter.active;

  bool get manager => widget.user.isManager;

  Future<List<Project>> _load() => widget.api.projects(includeInactive: true);

  void _reload() => setState(() => data = _load());

  Future<void> _edit([Project? project]) async {
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

  Future<void> _team(Project p) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => MembersDialog(api: widget.api, project: p));
    if (saved == true) _reload();
  }

  Future<void> _toggle(Project p) async {
    await runWithFeedback(context, () => widget.api.setProjectActive(p.id, !p.active),
        p.active ? 'Projeto desativado.' : 'Projeto reativado.');
    _reload();
  }

  List<Project> _filtered(List<Project> all) {
    final q = search.text.trim().toLowerCase();
    return all.where((p) {
      final status = switch (filter) {
        _ActiveFilter.active => p.active,
        _ActiveFilter.inactive => !p.active,
        _ActiveFilter.all => true,
      };
      final text = q.isEmpty || '${p.code} ${p.client} ${p.description}'.toLowerCase().contains(q);
      return status && text;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return PageBody(children: [
      PageHeader(
        title: 'Projetos',
        subtitle: 'Horas estimadas e realizadas por projeto',
        actions: [
          if (manager)
            OutlinedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => SapImportDialog(api: widget.api)),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Catálogo SAP'),
            ),
          if (manager)
            FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Novo projeto')),
        ],
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: search,
                decoration: const InputDecoration(labelText: 'Buscar por código, cliente ou descrição', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SegmentedButton<_ActiveFilter>(
              segments: const [
                ButtonSegment(value: _ActiveFilter.active, label: Text('Ativos')),
                ButtonSegment(value: _ActiveFilter.inactive, label: Text('Inativos')),
                ButtonSegment(value: _ActiveFilter.all, label: Text('Todos')),
              ],
              selected: {filter},
              onSelectionChanged: (s) => setState(() => filter = s.first),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      const HealthLegend(),
      const SizedBox(height: 12),
      FutureView(
        future: data,
        onRetry: _reload,
        builder: (all) {
          final projects = _filtered(all);
          return SectionCard(
            title: '${projects.length} projeto(s)',
            padding: const EdgeInsets.only(bottom: 8),
            child: projects.isEmpty
                ? const EmptyState(message: 'Nenhum projeto encontrado.', icon: Icons.folder_off_outlined)
                : ScrollableTable(
                    table: DataTable(
                      columnSpacing: 16,
                      columns: [
                        const DataColumn(label: Text('Código')),
                        const DataColumn(label: Text('Cliente')),
                        const DataColumn(label: Text('Status')),
                        if (manager) const DataColumn(label: Text('Equipe')),
                        const DataColumn(label: Text('Estimadas'), numeric: true),
                        const DataColumn(label: Text('Realizadas'), numeric: true),
                        const DataColumn(label: Text('Saldo / uso')),
                        const DataColumn(label: Text('Entrega')),
                        if (manager) const DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final p in projects)
                          DataRow(cells: [
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 4,
                                height: 28,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: (p.active ? projectHealth(p, today) : Health.none).color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Text(p.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ])),
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.client.isEmpty ? '—' : p.client),
                                if (p.description.isNotEmpty)
                                  Text(p.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            )),
                            DataCell(_ActiveChip(active: p.active)),
                            if (manager)
                              DataCell(
                                TextButton.icon(
                                  onPressed: () => _team(p),
                                  icon: const Icon(Icons.group_outlined, size: 18),
                                  label: Text(p.members == 0 ? 'Aberto a todos' : '${p.members} pessoa(s)'),
                                ),
                              ),
                            DataCell(Text(p.budgetHours == null ? '—' : formatHours(p.budgetHours!))),
                            DataCell(Text(formatHours(p.usedHours))),
                            DataCell(SizedBox(width: 190, child: _UsageCell(project: p))),
                            DataCell(StatusBadge(
                              health: dateHealth(p, today),
                              label: dateLabel(p, today).replaceFirst('Entrega ', ''),
                            )),
                            if (manager)
                              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: 'Editar',
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => _edit(p),
                                ),
                                IconButton(
                                  tooltip: p.active ? 'Desativar' : 'Reativar',
                                  icon: Icon(p.active ? Icons.toggle_on : Icons.toggle_off_outlined,
                                      color: p.active ? AppColors.primary : AppColors.textMuted),
                                  onPressed: () => _toggle(p),
                                ),
                              ])),
                          ]),
                      ],
                    ),
                  ),
          );
        },
      ),
    ]);
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2E7D32) : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(active ? 'Ativo' : 'Inativo', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Barra do saldo (cheia no início, esvazia com as horas lançadas) e o texto do saldo.
class _UsageCell extends StatelessWidget {
  const _UsageCell({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final health = hoursHealth(p);
    if (p.budgetHours == null) {
      return const Text('Sem horas previstas', style: TextStyle(color: AppColors.textMuted, fontSize: 12));
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (p.remainingHours! / p.budgetHours!).clamp(0.0, 1.0),
          color: health.color,
          backgroundColor: health.color.withValues(alpha: 0.15),
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 4),
      Text(hoursLabel(p), style: TextStyle(fontSize: 12, color: health.textColor), overflow: TextOverflow.ellipsis),
    ]);
  }
}
