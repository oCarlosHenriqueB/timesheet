import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timesheet/api.dart';
import 'package:timesheet/format.dart';
import 'package:timesheet/models.dart';
import 'package:timesheet/widgets/timer_card.dart';

/// API em memória: só o que o cartão do cronômetro usa.
class FakeApi extends Api {
  RunningTimer? current;
  final stops = <DateTime>[];
  bool discarded = false;

  @override
  Future<RunningTimer?> timer() async => current;

  @override
  Future<RunningTimer> startTimer(int projectId, {int? activityId, String description = ''}) async =>
      current = RunningTimer(
        projectId: projectId,
        projectLabel: 'PRJ-$projectId · Cliente',
        startedAt: DateTime.now().toUtc(),
        description: description,
        elapsedSeconds: 0,
      );

  @override
  Future<double> stopTimer(DateTime workDate, {String? startTime, String? endTime, String? description}) async {
    stops.add(workDate);
    current = null;
    return 1.5;
  }

  @override
  Future<void> discardTimer() async {
    discarded = true;
    current = null;
  }
}

void main() {
  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 309)), '0:05:09');
    expect(formatDuration(const Duration(hours: 12)), '12:00:00');
  });

  test('tempo decorrido soma o que o servidor informou ao tempo local desde a busca', () {
    final fetched = DateTime(2026, 10, 29, 10);
    final t = RunningTimer(
      projectId: 1,
      projectLabel: 'P',
      startedAt: DateTime.utc(2026, 10, 29, 12),
      description: '',
      elapsedSeconds: 600,
      fetchedAt: fetched,
    );
    expect(t.elapsed(fetched.add(const Duration(seconds: 5))), const Duration(seconds: 605));
  });

  test('dia do lançamento é a data local do início', () {
    final t = RunningTimer.fromJson({
      'project_id': 1,
      'project_code': 'PRJ-1',
      'project_client': '',
      'started_at': '2026-10-29T12:00:00+00:00',
      'elapsed_seconds': 0,
    });
    final local = DateTime.utc(2026, 10, 29, 12).toLocal();
    expect(t.workDate, DateTime(local.year, local.month, local.day));
    expect(t.projectLabel, 'PRJ-1');
  });

  testWidgets('iniciar, contar e parar e lançar', (tester) async {
    final api = FakeApi();
    var created = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TimerCard(
          api: api,
          projects: [Project(id: 7, code: 'PRJ-7', client: 'Cliente')],
          onEntryCreated: () => created++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'O que vai fazer? (opcional)'), 'Montagem');
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    expect(api.current?.projectId, 7);
    expect(api.current?.description, 'Montagem');
    expect(find.text('Parar e lançar'), findsOneWidget);
    expect(find.text('0:00:00'), findsOneWidget);

    await tester.tap(find.text('Parar e lançar'));
    await tester.pump();
    expect(api.stops, hasLength(1));
    expect(created, 1);
    expect(find.text('Iniciar'), findsOneWidget);
    expect(find.textContaining('Lançado 1,5 h'), findsOneWidget);
  });

  testWidgets('descartar pede confirmação', (tester) async {
    final api = FakeApi();
    await api.startTimer(7);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TimerCard(api: api, projects: [Project(id: 7, code: 'PRJ-7', client: 'C')], onEntryCreated: () {}),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('Descartar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(api.discarded, isTrue);
    expect(find.text('Iniciar'), findsOneWidget);
  });
}
