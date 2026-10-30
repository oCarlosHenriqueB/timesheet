import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'period.dart';

/// Endereço da API. Troque com: flutter run --dart-define=API_URL=http://...
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class Api {
  Api({this.token});

  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$apiUrl$path');
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await req.send());
    } catch (_) {
      throw ApiException('Não foi possível falar com a API em $apiUrl. Ela está rodando?');
    }
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiException(detail is String ? detail : 'Erro ${res.statusCode}: dados inválidos.', res.statusCode);
    }
    return data;
  }

  Future<(String, User)> login(String email, String password) async {
    final data = await _send('POST', '/auth/login', {'email': email, 'password': password});
    return (data['token'] as String, User.fromJson(data['user']));
  }

  Future<void> logout() => _send('POST', '/auth/logout');

  Future<User> me() async => User.fromJson(await _send('GET', '/me'));

  Future<User> setUseTimer(bool useTimer) async =>
      User.fromJson(await _send('PATCH', '/me/preferences', {'use_timer': useTimer}));

  Future<List<Activity>> activities({bool includeInactive = false}) async {
    final data = await _send('GET', '/activities?include_inactive=$includeInactive') as List;
    return data.map((j) => Activity.fromJson(j)).toList();
  }

  Future<void> createActivity(String name) => _send('POST', '/activities', {'name': name});

  Future<void> updateActivity(int id, {String? name, bool? active}) =>
      _send('PATCH', '/activities/$id', {'name': ?name, 'active': ?active});

  /// [today] é a data local de quem usa (a semana vai de segunda a domingo).
  Future<DashboardData> dashboard(DateTime today) async => DashboardData.fromJson(
      await _send('GET', '/dashboard?today=${today.toIso8601String().substring(0, 10)}'));

  Future<List<Project>> projects({bool includeInactive = false}) async {
    final data = await _send('GET', '/projects?include_inactive=$includeInactive') as List;
    return data.map((j) => Project.fromJson(j)).toList();
  }

  Future<void> createProject(ProjectDraft draft) => _send('POST', '/projects', draft.toJson());

  /// Envia todos os campos editáveis (o número do projeto não muda).
  Future<void> updateProject(int id, ProjectDraft draft) {
    final body = draft.toJson()..remove('code');
    return _send('PATCH', '/projects/$id', body);
  }

  Future<void> setProjectActive(int id, bool active) =>
      _send('PATCH', '/projects/$id', {'active': active});

  Future<List<User>> users() async {
    final data = await _send('GET', '/users') as List;
    return data.map((j) => User.fromJson(j)).toList();
  }

  Future<void> createUser(String name, String email, String password, String role) =>
      _send('POST', '/users', {'name': name, 'email': email, 'password': password, 'role': role});

  /// Monta "?a=1&b=2" (ou "" sem parâmetros).
  static String _qs(Map<String, String> params) =>
      params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';

  Future<List<Entry>> entries({
    bool allUsers = false,
    Period? period,
    int? projectId,
    int? activityId,
    EntryStatus? status,
    int? userId,
  }) async {
    final params = {
      'all_users': '$allUsers',
      ...?period?.query,
      if (projectId != null) 'project_id': '$projectId',
      if (activityId != null) 'activity_id': '$activityId',
      if (status != null) 'status': status.name,
      if (userId != null) 'user_id': '$userId',
    };
    final data = await _send('GET', '/entries${_qs(params)}') as List;
    return data.map((j) => Entry.fromJson(j)).toList();
  }

  Future<void> saveEntry(EntryDraft draft, {int? id}) => id == null
      ? _send('POST', '/entries', draft.toJson())
      : _send('PUT', '/entries/$id', draft.toJson());

  Future<void> deleteEntry(int id) => _send('DELETE', '/entries/$id');

  /// Cronômetro em andamento, ou null.
  Future<RunningTimer?> timer() async {
    final data = await _send('GET', '/timer');
    return data == null ? null : RunningTimer.fromJson(data);
  }

  Future<RunningTimer> startTimer(int projectId, {int? activityId, String description = ''}) async =>
      RunningTimer.fromJson(await _send(
          'POST', '/timer', {'project_id': projectId, 'activity_id': activityId, 'description': description}));

  /// Para o cronômetro e cria o lançamento; devolve as horas lançadas.
  /// [startTime]/[endTime] ("HH:MM" locais) só aparecem no histórico.
  Future<double> stopTimer(DateTime workDate, {String? startTime, String? endTime, String? description}) async {
    final data = await _send('POST', '/timer/stop', {
      'work_date': workDate.toIso8601String().substring(0, 10),
      'start_time': ?startTime,
      'end_time': ?endTime,
      'description': ?description,
    });
    return (data['hours'] as num).toDouble();
  }

  Future<void> discardTimer() => _send('DELETE', '/timer');

  Future<List<Project>> reportByProject({Period? period}) async {
    final data = await _send('GET', '/reports/by-project${_qs({...?period?.query})}') as List;
    return data.map((j) => Project.fromJson(j)).toList();
  }

  /// Dados do projeto no SAP pelo número; null se não estiver no catálogo.
  Future<ProjectDraft?> lookupSapProject(String code) async {
    try {
      return ProjectDraft.fromSap(await _send('GET', '/sap/projects/${Uri.encodeComponent(code.trim())}'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Importa o catálogo de projetos do SAP; devolve (quantos importou, erros por linha).
  Future<(int, List<String>)> importSapCatalog(String csv) async {
    final data = await _send('POST', '/sap/catalog', {'csv': csv});
    return (data['imported'] as int, (data['errors'] as List).cast<String>());
  }

  /// Lançamentos do período em CSV (layout próximo ao CATS do SAP).
  Future<Uint8List> exportEntriesCsv({Period? period}) async {
    final uri = Uri.parse('$apiUrl/exports/entries.csv${_qs({...?period?.query})}');
    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers);
    } catch (_) {
      throw ApiException('Não foi possível falar com a API em $apiUrl. Ela está rodando?');
    }
    if (res.statusCode >= 400) throw ApiException('Erro ${res.statusCode} ao exportar.', res.statusCode);
    return res.bodyBytes;
  }

  Future<List<ReportRow>> reportByActivity({Period? period}) async {
    final data = await _send('GET', '/reports/by-activity${_qs({...?period?.query})}') as List;
    return data
        .map((j) => ReportRow(j['name'] as String, (j['total_hours'] as num).toDouble(),
            '${j['projects']} projeto(s)'))
        .toList();
  }

  Future<List<ReportRow>> reportByUser({Period? period}) async {
    final data = await _send('GET', '/reports/by-user${_qs({...?period?.query})}') as List;
    return data
        .map((j) => ReportRow(j['name'] as String, (j['total_hours'] as num).toDouble(),
            '${j['projects']} projeto(s)'))
        .toList();
  }
}
