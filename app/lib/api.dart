import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

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

  Future<List<Entry>> entries({bool allUsers = false}) async {
    final data = await _send('GET', '/entries?all_users=$allUsers') as List;
    return data.map((j) => Entry.fromJson(j)).toList();
  }

  Future<void> saveEntry(EntryDraft draft, {int? id}) => id == null
      ? _send('POST', '/entries', draft.toJson())
      : _send('PUT', '/entries/$id', draft.toJson());

  Future<void> deleteEntry(int id) => _send('DELETE', '/entries/$id');

  Future<List<Project>> reportByProject() async {
    final data = await _send('GET', '/reports/by-project') as List;
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
  Future<Uint8List> exportEntriesCsv({DateTime? from, DateTime? to}) async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final query = [if (from != null) 'date_from=${day(from)}', if (to != null) 'date_to=${day(to)}'].join('&');
    final uri = Uri.parse('$apiUrl/exports/entries.csv${query.isEmpty ? '' : '?$query'}');
    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers);
    } catch (_) {
      throw ApiException('Não foi possível falar com a API em $apiUrl. Ela está rodando?');
    }
    if (res.statusCode >= 400) throw ApiException('Erro ${res.statusCode} ao exportar.', res.statusCode);
    return res.bodyBytes;
  }

  Future<List<ReportRow>> reportByUser() async {
    final data = await _send('GET', '/reports/by-user') as List;
    return data
        .map((j) => ReportRow(j['name'] as String, (j['total_hours'] as num).toDouble(),
            '${j['projects']} projeto(s)'))
        .toList();
  }
}
