// Expected statuses come from the Flet app's storage.mesocycle_status().
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/cycle.dart';
import 'package:gymer/models.dart';

Mesocycle cycle() => Mesocycle(id: 'c', start: DateTime(2026, 1, 5), endRir: 0, schedule: {1: 'A', 3: 'B'});

void main() {
  test('status steps RIR weekly, then deloads and completes', () {
    final c = cycle();
    String at(int y, int m, int d) {
      final s = cycleStatus(c, DateTime(y, m, d));
      return '${s.phase} ${s.currentMicro} ${s.dayInMicro} ${s.suggestedRir}';
    }

    expect(at(2026, 1, 4), 'Upcoming 1 1 3');
    expect(at(2026, 1, 5), 'Build 1 1 3');
    expect(at(2026, 1, 19), 'Build 3 1 1');
    expect(at(2026, 1, 26), 'Build 4 1 0');
    expect(at(2026, 2, 8), 'Deload 5 7 4');
    expect(at(2026, 2, 9), 'Complete 5 7 0');

    c
      ..endRir = 1
      ..weekRir[2] = 2;
    expect([for (var w = 1; w <= 5; w++) rirForWeek(c, w)], [3, 2, 1, 1, 4]);
  });

  test('calendar tracks done, missed and moved days', () {
    final c = cycle();
    Session s(String id, DateTime at, String template) =>
        Session(id: id, templateId: template, name: template, unit: 'kg', startedAt: at, exercises: [], cycleId: 'c');

    final done = s('s1', DateTime(2026, 1, 5, 18), 'A');
    linkSession(c, done);
    c.events['2026-01-07'] = DayEvent(templateId: 'B', movedTo: DateTime(2026, 1, 8));
    final moved = s('s2', DateTime(2026, 1, 8, 18), 'B');
    linkSession(c, moved);
    c.events['2026-01-12'] = DayEvent(templateId: 'A', status: 'missed');

    final days = {
      for (final d in calendarDays(c, [moved, done])) dateKey(d.date): d,
    };
    expect(days['2026-01-05']!.status, 'done');
    expect(days['2026-01-07']!.status, 'moved_done');
    expect(days['2026-01-07']!.sessionId, 's2');
    expect(days['2026-01-06']!.status, 'rest');
    expect(days['2026-01-12']!.status, 'missed');
    expect(days['2026-01-14']!.status, 'planned');
  });

  test('calendar days stay distinct across a DST change', () {
    final c = Mesocycle(id: 'c', start: DateTime(2026, 10, 19), length: 2);
    final keys = [for (final d in calendarDays(c, const [])) dateKey(d.date)];
    expect(keys.toSet(), hasLength(14));
    expect(keys.last, '2026-11-01');
    expect(cycleStatus(c, DateTime(2026, 10, 26, 0, 30)).currentMicro, 2);
  });

  test('weekly sets count direct as 1, indirect as 0.5; protocols stay separate', () {
    final c = Mesocycle(id: 'c', start: DateTime(2026, 1, 5), microDays: 3, schedule: {1: 'A'});
    final a = WorkoutTemplate(
      id: 'A',
      name: 'A',
      exercises: [
        TemplateExercise.typed(name: 'Leg Press', types: ['Warm-up', 'Normal', 'Normal']),
        TemplateExercise.typed(name: 'Leg Curl', method: 'Myo-Reps', types: ['Activation', 'Myo-set', 'Myo-set']),
      ],
    );
    final v = plannedWeeklyVolume(c, {
      'A': a,
    }, (n) => n == 'Leg Press' ? (['Quads'], ['Hamstrings']) : (['Hamstrings'], <String>[]));
    expect(v['Quads']!.sets, closeTo(2 * 7 / 3, 1e-9));
    expect(v['Hamstrings']!.sets, closeTo(0.5 * 2 * 7 / 3, 1e-9));
    expect(v['Hamstrings']!.direct.protocolGroups, closeTo(7 / 3, 1e-9));
  });
}
