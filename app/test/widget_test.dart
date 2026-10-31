import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/format.dart';
import 'package:timesheet/models.dart';

void main() {
  test('parseHours aceita vírgula e ponto', () {
    expect(parseHours('1,5'), 1.5);
    expect(parseHours(' 2.25 '), 2.25);
    expect(parseHours('abc'), isNull);
  });

  test('formatHours usa formato brasileiro', () {
    expect(formatHours(1.5), '1,5 h');
    expect(formatHours(8), '8 h');
  });

  test('Entry traz o motivo da rejeição e quem revisou', () {
    final e = Entry.fromJson({
      'id': 1, 'user_name': 'Ana', 'project_id': 2, 'project_code': 'PRJ-001', 'work_date': '2026-10-05',
      'hours': 2, 'status': 'rejeitado', 'review_note': 'Faltou a OS', 'reviewer_name': 'Marina',
    });
    expect(e.status, EntryStatus.rejeitado);
    expect(e.reviewNote, 'Faltou a OS');
    expect(e.reviewerName, 'Marina');
    final old = {'id': 1, 'user_name': 'Ana', 'project_id': 2, 'project_code': 'P', 'work_date': '2026-10-05', 'hours': 1};
    expect(Entry.fromJson(old).reviewNote, ''); // API antiga, sem os campos novos
  });

  test('Report lê status com nome da API, prints e data em UTC', () {
    final r = Report.fromJson({
      'id': 3, 'user_name': 'Ana', 'kind': 'melhoria', 'title': 'Modo escuro', 'status': 'em_analise',
      'created_at': '2026-10-30T15:00:00+00:00', 'image_ids': [7, 8],
    });
    expect(r.kind, ReportKind.melhoria);
    expect(r.status, ReportStatus.emAnalise);
    expect(r.status.apiName, 'em_analise');
    expect(r.imageIds, [7, 8]);
    expect(r.createdAt.toUtc(), DateTime.utc(2026, 10, 30, 15));
    expect(PickedImage('image/png', Uint8List.fromList([1, 2, 3])).toJson()['data'], 'AQID');
  });

  test('EntryDraft envia só a data, sem hora', () {
    final json = EntryDraft(projectId: 1, date: DateTime(2026, 10, 5), hours: 2).toJson();
    expect(json['work_date'], '2026-10-05');
  });
}
