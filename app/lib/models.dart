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
  Project({required this.id, required this.code, required this.name, required this.active});

  final int id;
  final String code;
  final String name;
  final bool active;

  String get label => '$code · $name';

  factory Project.fromJson(Map<String, dynamic> j) =>
      Project(id: j['id'], code: j['code'], name: j['name'], active: j['active']);
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
