import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../pick_image.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/layout.dart';

const _maxImages = 3;

/// Relatar erro ou sugerir melhoria, com prints (escolhidos ou colados com Ctrl+V / Cmd+V).
/// Abaixo, a lista de relatos: o projetista vê os dele; o gestor vê os de todos, muda o status e responde.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.api, required this.user, required this.pages});

  final Api api;
  final User user;

  /// Nomes das telas do app, para a pessoa dizer onde aconteceu.
  final List<String> pages;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportKind kind = ReportKind.erro;
  String? page;
  final title = TextEditingController();
  final description = TextEditingController();
  final images = <PickedImage>[];
  bool sending = false;

  ReportStatus? filter;
  late Future<List<Report>> data = _load();
  late final void Function() _stopPaste;

  @override
  void initState() {
    super.initState();
    _stopPaste = listenPastedImages(_addImages);
  }

  @override
  void dispose() {
    _stopPaste();
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<List<Report>> _load() => widget.api.reports(status: filter);

  void _reload() => setState(() => data = _load());

  void _addImages(List<PickedImage> picked) {
    if (!mounted || picked.isEmpty) return;
    final room = _maxImages - images.length;
    setState(() => images.addAll(picked.take(room)));
    if (picked.length > room) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No máximo $_maxImages prints por relato.')));
    }
  }

  Future<void> _send() async {
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escreva um título curto.')));
      return;
    }
    setState(() => sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.sendReport(
        kind: kind,
        title: title.text.trim(),
        description: description.text.trim(),
        page: page ?? '',
        device: deviceInfo(),
        images: images,
      );
      title.clear();
      description.clear();
      setState(() {
        images.clear();
        page = null;
        data = _load();
      });
      messenger.showSnackBar(const SnackBar(content: Text('Relato enviado. Obrigado!')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _open(Report r) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(api: widget.api, report: r, isManager: widget.user.isManager),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.user.isManager;
    return PageBody(children: [
      const PageHeader(title: 'Reportar', subtitle: 'Avise sobre um erro ou sugira uma melhoria no app'),
      SectionCard(title: 'Novo relato', child: _form()),
      const SizedBox(height: 16),
      FutureView(
        future: data,
        onRetry: _reload,
        builder: (reports) => SectionCard(
          title: manager ? 'Relatos da equipe (${reports.length})' : 'Meus relatos (${reports.length})',
          actions: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<ReportStatus?>(
                initialValue: filter,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  for (final s in ReportStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) {
                  filter = v;
                  _reload();
                },
              ),
            ),
          ],
          padding: const EdgeInsets.only(bottom: 8),
          child: reports.isEmpty
              ? const EmptyState(message: 'Nenhum relato por aqui.', icon: Icons.mark_chat_read_outlined)
              : Column(children: [
                  for (final r in reports)
                    ListTile(
                      leading: _KindIcon(r.kind),
                      title: Text(r.title, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (manager) r.userName,
                        '${formatDate(r.createdAt)} ${clockTime(r.createdAt)}',
                        if (r.page.isNotEmpty) r.page,
                        if (r.imageIds.isNotEmpty) '${r.imageIds.length} print(s)',
                        if (r.response.isNotEmpty) 'respondido',
                      ].join(' · ')),
                      trailing: ReportStatusChip(r.status),
                      onTap: () => _open(r),
                    ),
                ]),
        ),
      ),
    ]);
  }

  Widget _form() {
    final isBug = kind == ReportKind.erro;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<ReportKind>(
        segments: const [
          ButtonSegment(value: ReportKind.erro, icon: Icon(Icons.bug_report_outlined), label: Text('Erro')),
          ButtonSegment(value: ReportKind.melhoria, icon: Icon(Icons.lightbulb_outline), label: Text('Melhoria')),
        ],
        selected: {kind},
        onSelectionChanged: (s) => setState(() => kind = s.first),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 16, runSpacing: 12, children: [
        SizedBox(
          width: 420,
          child: TextField(
            controller: title,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'Título',
              hintText: isBug ? 'Ex.: Botão Registrar não responde' : 'Ex.: Mostrar o total do dia no Apontamento',
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String?>(
            initialValue: page,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Em qual tela?'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Não sei / várias')),
              for (final p in widget.pages) DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => page = v),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      TextField(
        controller: description,
        minLines: 3,
        maxLines: 8,
        maxLength: 4000,
        decoration: InputDecoration(
          labelText: isBug ? 'O que aconteceu?' : 'Descreva a ideia',
          hintText: isBug
              ? 'O que você fez, o que esperava e o que apareceu (mensagem de erro, se houver).'
              : 'O que ajudaria no seu dia a dia e por quê.',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final (i, img) in images.indexed)
          Stack(clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(img.bytes, width: 120, height: 80, fit: BoxFit.cover),
            ),
            Positioned(
              right: -10,
              top: -10,
              child: IconButton.filledTonal(
                tooltip: 'Remover',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => images.removeAt(i)),
                icon: const Icon(Icons.close),
              ),
            ),
          ]),
        if (images.length < _maxImages)
          OutlinedButton.icon(
            onPressed: () async => _addImages(await pickImages()),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Anexar print'),
          ),
      ]),
      const SizedBox(height: 8),
      const Text(
        'Também dá para colar um print com Ctrl+V (Windows) ou Cmd+V (Mac). Para copiar só uma parte da tela: '
        'Windows + Shift + S no Windows; Cmd + Ctrl + Shift + 4 no Mac. Até $_maxImages prints.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: sending ? null : _send,
        icon: sending
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send),
        label: const Text('Enviar'),
      ),
    ]);
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon(this.kind);

  final ReportKind kind;

  @override
  Widget build(BuildContext context) {
    final bug = kind == ReportKind.erro;
    return Tooltip(
      message: kind.label,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: (bug ? const Color(0xFFC62828) : const Color(0xFFB26A00)).withValues(alpha: 0.1),
        child: Icon(bug ? Icons.bug_report_outlined : Icons.lightbulb_outline,
            size: 20, color: bug ? const Color(0xFFC62828) : const Color(0xFFB26A00)),
      ),
    );
  }
}

/// Selo do status do relato.
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip(this.status, {super.key});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ReportStatus.aberto => AppColors.primary,
      ReportStatus.emAnalise => const Color(0xFFB26A00),
      ReportStatus.resolvido => const Color(0xFF2E7D32),
      ReportStatus.recusado => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Detalhes do relato, com os prints. O gestor muda o status e responde.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.api, required this.report, required this.isManager});

  final Api api;
  final Report report;
  final bool isManager;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late ReportStatus status = widget.report.status;
  late final response = TextEditingController(text: widget.report.response);

  /// Cada print é baixado uma vez, mesmo que o diálogo redesenhe.
  late final images = {for (final id in widget.report.imageIds) id: widget.api.reportImage(widget.report.id, id)};

  @override
  void dispose() {
    response.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await runWithFeedback(
      context,
      () => widget.api.updateReport(widget.report.id, status: status, response: response.text.trim()),
      'Relato atualizado.',
    );
    navigator.pop(true);
  }

  void _zoom(Future<Uint8List> bytes) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Stack(children: [
            InteractiveViewer(maxScale: 5, child: _ImageView(bytes: bytes, fit: BoxFit.contain)),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return AlertDialog(
      title: Row(children: [
        _KindIcon(r.kind),
        const SizedBox(width: 12),
        Expanded(child: Text(r.title)),
      ]),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [
                '${r.kind.label} enviado por ${r.userName}',
                '${formatDate(r.createdAt)} ${clockTime(r.createdAt)}',
                if (r.page.isNotEmpty) 'tela ${r.page}',
              ].join(' · '),
              style: muted,
            ),
            const SizedBox(height: 12),
            SelectableText(r.description.isEmpty ? '(sem descrição)' : r.description),
            if (r.imageIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final bytes in images.values)
                  InkWell(
                    onTap: () => _zoom(bytes),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(width: 180, height: 120, child: _ImageView(bytes: bytes, fit: BoxFit.cover)),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('Clique no print para ampliar.', style: muted),
            ],
            if (widget.isManager && r.device.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText('Navegador: ${r.device}', style: muted),
            ],
            const Divider(height: 32),
            if (widget.isManager) ...[
              DropdownButtonFormField<ReportStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final s in ReportStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (v) => setState(() => status = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: response,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Resposta para quem enviou',
                  hintText: 'Ex.: Corrigido na próxima versão.',
                  alignLabelWithHint: true,
                ),
              ),
            ] else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ReportStatusChip(r.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.response.isEmpty ? 'Ainda sem resposta do gestor.' : 'Resposta: ${r.response}'),
                ),
              ]),
          ]),
        ),
      ),
      actions: widget.isManager
          ? [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: _save, child: const Text('Salvar')),
            ]
          : [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

/// Mostra um print carregado da API (com login), com indicador enquanto baixa.
class _ImageView extends StatelessWidget {
  const _ImageView({required this.bytes, required this.fit});

  final Future<Uint8List> bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        return Image.memory(snap.data!, fit: fit);
      },
    );
  }
}
