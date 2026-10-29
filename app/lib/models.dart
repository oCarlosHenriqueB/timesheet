class User {
  User({required this.id, required this.name, required this.email, required this.role, this.active = true});

  final int id;
  final String name;
  final String email;
  final String role;
  final bool active;

  bool get isManager => role == 'gestor';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        name: j['name'],
        email: j['email'],
        role: j['role'],
        active: j['active'] ?? true,
      );
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
  });

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
  final double usedHours;
  final int people;

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
      );
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
    required this.projectLabel,
    required this.date,
    required this.hours,
    required this.description,
  });

  final int id;
  final String userName;
  final int projectId;
  final String projectLabel;
  final DateTime date;
  final double hours;
  final String description;

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'],
        userName: j['user_name'],
        projectId: j['project_id'],
        projectLabel: '${j['project_code']} · ${j['project_name']}',
        date: DateTime.parse(j['work_date']),
        hours: (j['hours'] as num).toDouble(),
        description: j['description'] ?? '',
      );
}

/// Dados do formulário de lançamento, antes de ir para a API.
class EntryDraft {
  EntryDraft({required this.projectId, required this.date, required this.hours, this.description = ''});

  final int projectId;
  final DateTime date;
  final double hours;
  final String description;

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'work_date': date.toIso8601String().substring(0, 10),
        'hours': hours,
        'description': description,
      };
}

class ReportRow {
  ReportRow(this.label, this.totalHours, this.detail);

  final String label;
  final double totalHours;
  final String detail;
}
