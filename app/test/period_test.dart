import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/period.dart';

void main() {
  final thursday = DateTime(2026, 10, 29, 15, 30); // quinta-feira, com horário

  test('esta semana vai de segunda a domingo', () {
    final p = Period.of(PeriodPreset.thisWeek, thursday);
    expect(p.query, {'date_from': '2026-10-26', 'date_to': '2026-11-01'});
  });

  test('este mês e mês passado, inclusive virada de ano', () {
    expect(Period.of(PeriodPreset.thisMonth, thursday).query, {'date_from': '2026-10-01', 'date_to': '2026-10-31'});
    expect(Period.of(PeriodPreset.lastMonth, thursday).query, {'date_from': '2026-09-01', 'date_to': '2026-09-30'});
    final january = DateTime(2027, 1, 15);
    expect(Period.of(PeriodPreset.lastMonth, january).query, {'date_from': '2026-12-01', 'date_to': '2026-12-31'});
    expect(Period.of(PeriodPreset.thisMonth, DateTime(2028, 2, 10)).query['date_to'], '2028-02-29'); // bissexto
  });

  test('últimos 30 dias inclui hoje', () {
    expect(Period.of(PeriodPreset.last30Days, thursday).query, {'date_from': '2026-09-30', 'date_to': '2026-10-29'});
  });

  test('tudo não filtra', () {
    final p = Period.of(PeriodPreset.all, thursday);
    expect(p.query, isEmpty);
    expect(p.description, 'Todos os lançamentos');
    expect(p.fileSuffix, 'tudo');
  });

  test('texto e nome do arquivo', () {
    final p = Period.of(PeriodPreset.thisMonth, thursday);
    expect(p.description, '01/10/2026 a 31/10/2026');
    expect(p.fileSuffix, '2026-10-01_2026-10-31');
  });
}
