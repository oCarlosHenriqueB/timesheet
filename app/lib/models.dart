import 'dart:convert';
import 'dart:typed_data';

class User {
  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
    this.useTimer = true,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final bool active;

  /// Preferência de cada pessoa: mostrar ou não o cronômetro no apontamento.
  final bool useTimer;

  bool get isManager => role == 'gestor';
  /// O papel continua "tecnico" na API; nas telas, quem lança horas é o projetista.
  String get roleLabel => isManager ? 'Gestor' : 'Projetista';

  User copyWith({bool? useTimer}) =>
      User(id: id, name: name, email: email, role: role, active: active, useTimer: useTimer ?? this.useTimer);

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        name: j['name'],
        email: j['email'],
        role: j['role'],
        active: j['active'] ?? true,
        useTimer: j['use_timer'] ?? true,
      );
}

/// Tipo de atividade do apontamento (Instalação, Calibração...).
class Activity {
  Activity({required this.id, required this.name, this.active = true});

  final int id;
  final String name;
  final bool active;

  factory Activity.fromJson(Map<String, dynamic> j) =>
      Activity(id: j['id'], name: j['name'], active: j['active'] ?? true);
}

/// Situação do apontamento. Tudo nasce "enviado"; o gestor aprova ou rejeita na tela Aprovação.
enum EntryStatus {
  rascunho('Rascunho'),
  enviado('Enviado'),
  aprovado('Aprovado'),
  rejeitado('Rejeitado');

  const EntryStatus(this.label);
  final String label;

  static EntryStatus parse(String? value) =>
      EntryStatus.values.where((s) => s.name == value).firstOrNull ?? EntryStatus.enviado;
}

class Project {
  Project({
    required this.id,
    required this.code,
    required this.client,
    this.description = '',
    this.active = true,
    this.budgetHours,
    this.dueDate,
    this.usedHours = 0,
    this.people = 0,
    this.sapWbs = '',
    this.sapSalesOrder = '',
    double? periodHours,
    this.members = 0,
  }) : periodHours = periodHours ?? usedHours;

  final int id;

  /// Número do projeto.
  final String code;
  final String client;
  final String description;
  final bool active;

  /// Horas previstas; null em projetos antigos ou sem orçamento.
  final double? budgetHours;

  /// Data de entrega, opcional.
  final DateTime? dueDate;
  /// Total lançado no projeto (base do saldo).
  final double usedHours;
  final int people;

  /// Horas lançadas no período filtrado do relatório (igual a [usedHours] sem filtro).
  final double periodHours;

  /// Quantos projetistas estão alocados (0 = aberto a todos).
  final int members;

  /// Elemento PEP e ordem de venda no SAP, para casar os dados na integração.
  final String sapWbs;
  final String sapSalesOrder;

  /// Horas previstas menos as lançadas; negativo quando estoura.
  double? get remainingHours => budgetHours == null ? null : budgetHours! - usedHours;

  String get label => '$code · ${client.isNotEmpty ? client : description}';

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'],
        code: j['code'],
        client: j['client'] ?? '',
        description: j['name'] ?? '',
        active: j['active'] ?? true,
        budgetHours: (j['budget_hours'] as num?)?.toDouble(),
        dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date']),
        usedHours: (j['used_hours'] as num? ?? 0).toDouble(),
        people: j['people'] ?? 0,
        sapWbs: j['sap_wbs'] ?? '',
        sapSalesOrder: j['sap_sales_order'] ?? '',
        periodHours: (j['total_hours'] as num?)?.toDouble(),
        members: j['members'] ?? 0,
      );
}

/// Projetista alocado num projeto, com horas e prazo próprios.
class Member {
  Member({required this.userId, required this.userName, this.budgetHours, this.dueDate, this.usedHours = 0});

  final int userId;
  final String userName;
  final double? budgetHours;

  /// Null = entrega do projeto.
  final DateTime? dueDate;
  final double usedHours;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        userId: j['user_id'],
        userName: j['user_name'],
        budgetHours: (j['budget_hours'] as num?)?.toDouble(),
        dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date']),
        usedHours: (j['used_hours'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'budget_hours': budgetHours,
        'due_date': dueDate?.toIso8601String().substring(0, 10),
      };
}

/// Dados do formulário de projeto, antes de ir para a API.
class ProjectDraft {
  ProjectDraft({
    required this.code,
    required this.client,
    this.description = '',
    this.budgetHours,
    this.dueDate,
    this.sapWbs = '',
    this.sapSalesOrder = '',
  });

  /// Dados vindos da busca no SAP (GET /sap/projects/{code}).
  factory ProjectDraft.fromSap(Map<String, dynamic> j) => ProjectDraft(
        code: j['code'],
        client: j['client'] ?? '',
        budgetHours: (j['budget_hours'] as num?)?.toDouble(),
        dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date']),
        sapWbs: j['sap_wbs'] ?? '',
        sapSalesOrder: j['sap_sales_order'] ?? '',
      );

  final String code;
  final String client;
  final String description;
  final double? budgetHours;
  final DateTime? dueDate;
  final String sapWbs;
  final String sapSalesOrder;

  Map<String, dynamic> toJson() => {
        'code': code,
        'client': client,
        'name': description,
        'budget_hours': budgetHours,
        'due_date': dueDate?.toIso8601String().substring(0, 10),
        'sap_wbs': sapWbs,
        'sap_sales_order': sapSalesOrder,
      };
}

class Entry {
  Entry({
    required this.id,
    required this.userName,
    required this.projectId,
    required this.projectCode,
    required this.projectClient,
    required this.date,
    required this.hours,
    this.activityId,
    this.activityName,
    this.startTime,
    this.endTime,
    this.breakMinutes = 0,
    this.description = '',
    this.status = EntryStatus.enviado,
    this.projectName = '',
    this.reviewNote = '',
    this.reviewerName,
  });

  final int id;
  final String userName;
  final int projectId;
  final String projectCode;
  final String projectClient;
  final String projectName;
  final int? activityId;
  final String? activityName;
  final DateTime date;

  /// "08:00"; nulos em lançamentos antigos (só total de horas).
  final String? startTime;
  final String? endTime;
  final int breakMinutes;
  final double hours;
  final String description;
  final EntryStatus status;

  /// Motivo da rejeição (vazio nos demais status) e quem aprovou/rejeitou.
  final String reviewNote;
  final String? reviewerName;

  String get projectLabel => '$projectCode · ${projectClient.isNotEmpty ? projectClient : projectName}';
  String get timeRange => startTime == null ? '—' : '$startTime – $endTime';
  bool get locked => status == EntryStatus.aprovado;

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'],
        userName: j['user_name'],
        projectId: j['project_id'],
        projectCode: j['project_code'],
        projectClient: j['project_client'] ?? '',
        projectName: j['project_name'] ?? '',
        activityId: j['activity_id'],
        activityName: j['activity_name'],
        date: DateTime.parse(j['work_date']),
        startTime: j['start_time'],
        endTime: j['end_time'],
        breakMinutes: j['break_minutes'] ?? 0,
        hours: (j['hours'] as num).toDouble(),
        description: j['description'] ?? '',
        status: EntryStatus.parse(j['status']),
        reviewNote: j['review_note'] ?? '',
        reviewerName: j['reviewer_name'],
      );
}

/// Dados do formulário de apontamento, antes de ir para a API.
/// Com início e fim, a API calcula as horas; sem eles, vale [hours].
class EntryDraft {
  EntryDraft({
    required this.projectId,
    required this.date,
    this.activityId,
    this.startTime,
    this.endTime,
    this.breakMinutes = 0,
    this.hours,
    this.description = '',
  });

  final int projectId;
  final int? activityId;
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final int breakMinutes;
  final double? hours;
  final String description;

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'activity_id': activityId,
        'work_date': date.toIso8601String().substring(0, 10),
        if (startTime != null) ...{'start_time': startTime, 'end_time': endTime, 'break_minutes': breakMinutes},
        if (startTime == null) 'hours': hours,
        'description': description,
      };
}

class ReportRow {
  ReportRow(this.label, this.totalHours, this.detail);

  final String label;
  final double totalHours;
  final String detail;
}

/// Cronômetro em andamento do usuário (GET /timer).
class RunningTimer {
  RunningTimer({
    required this.projectId,
    required this.projectLabel,
    this.activityName,
    required this.startedAt,
    required this.description,
    required int elapsedSeconds,
    DateTime? fetchedAt,
  })  : _elapsedAtFetch = Duration(seconds: elapsedSeconds),
        _fetchedAt = fetchedAt ?? DateTime.now();

  final int projectId;
  final String projectLabel;
  final String? activityName;

  /// Início em UTC, como o servidor guarda.
  final DateTime startedAt;
  final String description;
  final Duration _elapsedAtFetch;
  final DateTime _fetchedAt;

  /// Tempo decorrido: o que o servidor informou mais o que passou desde então
  /// (assim não depende do relógio do aparelho estar certo).
  Duration elapsed([DateTime? now]) => _elapsedAtFetch + (now ?? DateTime.now()).difference(_fetchedAt);

  /// Dia do lançamento: a data local em que o cronômetro começou.
  DateTime get workDate {
    final local = startedAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  factory RunningTimer.fromJson(Map<String, dynamic> j) {
    final client = (j['project_client'] as String?) ?? '';
    return RunningTimer(
      projectId: j['project_id'],
      projectLabel: client.isEmpty ? j['project_code'] : '${j['project_code']} · $client',
      activityName: j['activity_name'],
      startedAt: DateTime.parse(j['started_at']),
      description: j['description'] ?? '',
      elapsedSeconds: j['elapsed_seconds'] ?? 0,
    );
  }
}

/// Resumo da tela inicial (GET /dashboard).
class DashboardData {
  DashboardData({
    required this.todayHours,
    required this.weekHours,
    required this.monthHours,
    required this.weekDays,
    required this.projects,
    required this.recent,
    this.teamWeekHours,
  });

  final double todayHours;
  final double weekHours;
  final double monthHours;

  /// Segunda a domingo da semana atual.
  final List<(DateTime, double)> weekDays;
  final List<Project> projects;
  final List<Entry> recent;

  /// Só para o gestor.
  final double? teamWeekHours;

  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
        todayHours: (j['today_hours'] as num).toDouble(),
        weekHours: (j['week_hours'] as num).toDouble(),
        monthHours: (j['month_hours'] as num).toDouble(),
        weekDays: [
          for (final d in j['week_days'] as List) (DateTime.parse(d['date']), (d['hours'] as num).toDouble()),
        ],
        projects: [for (final p in j['projects_in_progress'] as List) Project.fromJson(p)],
        recent: [for (final e in j['recent_entries'] as List) Entry.fromJson(e)],
        teamWeekHours: (j['team_week_hours'] as num?)?.toDouble(),
      );
}

/// Linha da grade da equipe: uma pessoa em um projeto, com as horas de cada dia.
class GridRow {
  GridRow({
    required this.userId,
    required this.userName,
    required this.projectId,
    required this.projectCode,
    required this.projectClient,
    required this.allocated,
    required this.hoursBefore,
    required this.totalHours,
    required this.days,
    this.budgetHours,
    this.dueDate,
  });

  final int userId;
  final String userName;
  final int projectId;
  final String projectCode;
  final String projectClient;

  /// false = apontou sem estar alocado (projeto aberto ou lançamento do gestor).
  final bool allocated;

  /// Horas previstas para a pessoa nesse projeto.
  final double? budgetHours;

  /// Prazo da pessoa (ou entrega do projeto).
  final DateTime? dueDate;

  /// Horas lançadas antes do primeiro dia da grade.
  final double hoursBefore;
  final double totalHours;

  /// "aaaa-mm-dd" → horas do dia.
  final Map<String, double> days;

  String get projectLabel => projectClient.isEmpty ? projectCode : '$projectCode · $projectClient';

  factory GridRow.fromJson(Map<String, dynamic> j) => GridRow(
        userId: j['user_id'],
        userName: j['user_name'],
        projectId: j['project_id'],
        projectCode: j['project_code'],
        projectClient: j['project_client'] ?? '',
        allocated: j['allocated'] ?? false,
        budgetHours: (j['budget_hours'] as num?)?.toDouble(),
        dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date']),
        hoursBefore: (j['hours_before'] as num).toDouble(),
        totalHours: (j['total_hours'] as num).toDouble(),
        days: {for (final e in (j['days'] as Map).entries) e.key as String: (e.value as num).toDouble()},
      );
}

class TeamGrid {
  TeamGrid({required this.days, required this.rows});

  final List<DateTime> days;
  final List<GridRow> rows;

  factory TeamGrid.fromJson(Map<String, dynamic> j) => TeamGrid(
        days: [for (final d in j['days'] as List) DateTime.parse(d)],
        rows: [for (final r in j['rows'] as List) GridRow.fromJson(r)],
      );
}

enum ReportKind {
  erro('Erro', 'Algo não funcionou'),
  melhoria('Melhoria', 'Ideia ou sugestão');

  const ReportKind(this.label, this.hint);
  final String label;
  final String hint;

  static ReportKind parse(String? value) =>
      ReportKind.values.where((k) => k.name == value).firstOrNull ?? ReportKind.erro;
}

enum ReportStatus {
  aberto('Aberto'),
  emAnalise('Em análise', 'em_analise'),
  resolvido('Resolvido'),
  recusado('Não será feito');

  const ReportStatus(this.label, [this._api]);
  final String label;
  final String? _api;

  /// Valor usado na API ("em_analise").
  String get apiName => _api ?? name;

  static ReportStatus parse(String? value) =>
      ReportStatus.values.where((s) => s.apiName == value).firstOrNull ?? ReportStatus.aberto;
}

/// Relato de erro ou sugestão de melhoria, com os prints anexados e a resposta do gestor.
class Report {
  Report({
    required this.id,
    required this.userName,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.description = '',
    this.page = '',
    this.device = '',
    this.status = ReportStatus.aberto,
    this.response = '',
    this.imageIds = const [],
  });

  final int id;
  final String userName;
  final ReportKind kind;
  final String title;
  final String description;

  /// Tela do app em que aconteceu ("Apontamento"); vazio = não informado.
  final String page;

  /// Navegador e tamanho da tela de quem enviou, preenchido pelo app.
  final String device;
  final ReportStatus status;
  final String response;
  final DateTime createdAt;
  final List<int> imageIds;

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'],
        userName: j['user_name'],
        kind: ReportKind.parse(j['kind']),
        title: j['title'],
        description: j['description'] ?? '',
        page: j['page'] ?? '',
        device: j['device'] ?? '',
        status: ReportStatus.parse(j['status']),
        response: j['response'] ?? '',
        createdAt: DateTime.parse(j['created_at']).toLocal(),
        imageIds: (j['image_ids'] as List? ?? const []).cast<int>(),
      );
}

/// Print escolhido ou colado, antes de ir para a API.
class PickedImage {
  PickedImage(this.contentType, this.bytes);

  final String contentType;
  final Uint8List bytes;

  Map<String, dynamic> toJson() => {'content_type': contentType, 'data': base64Encode(bytes)};
}
