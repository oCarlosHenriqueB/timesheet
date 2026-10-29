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

  test('EntryDraft envia só a data, sem hora', () {
    final json = EntryDraft(projectId: 1, date: DateTime(2026, 10, 5), hours: 2).toJson();
    expect(json['work_date'], '2026-10-05');
  });
}
