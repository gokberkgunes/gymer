// Expected statuses come from the Flet app's storage.mesocycle_status().
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/cycle.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

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
    expect([for (var w = 1; w <= 5; w++) rirForWeek(c, w)], [3, 2, 2, 1, 4]);
    // Effort ramps evenly instead of reaching failure early and staying there.
    final long = Mesocycle(id: 'l', start: DateTime(2026, 1, 5), startRir: 3, endRir: 0, length: 7);
    expect([for (var w = 1; w <= 7; w++) rirForWeek(long, w)], [3, 2, 2, 1, 1, 0, 4]);
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
    expect(v['Quads']!.directDaysPerWeek, closeTo(7 / 3, 1e-9));
    expect(v['Hamstrings']!.directDaysPerWeek, closeTo(7 / 3, 1e-9)); // Protocol work is a training day too.
    expect(v['Quads']!.countedSets(includePartialSets: false), closeTo(2 * 7 / 3, 1e-9));
    expect(v['Hamstrings']!.countedSets(includePartialSets: false), 0);

    final store = AppStore()
      ..templates = [a]
      ..cycles = [c]
      ..exercises = [
        const Exercise(name: 'Leg Press', primary: ['Quads'], secondary: ['Hamstrings']),
        const Exercise(name: 'Leg Curl', primary: ['Hamstrings']),
      ];
    addTearDown(store.dispose);
    expect(Settings.fromJson({}).includePartialSets, isTrue);
    expect(store.editorWeeklySets(a).after['Hamstrings'], closeTo(7 / 3, 1e-9));
    store.settings.includePartialSets = false;
    expect(store.editorWeeklySets(a).after['Hamstrings'], 0);
    expect(store.editorWeeklySets(a).after['Quads'], closeTo(2 * 7 / 3, 1e-9));
    expect(Settings.fromJson(store.settings.toJson()).includePartialSets, isFalse);

    final b = WorkoutTemplate(
      id: 'B',
      name: 'B',
      exercises: [
        TemplateExercise.typed(name: 'Leg Press', types: ['Normal', 'Normal']),
        TemplateExercise.typed(name: 'Leg Extension', types: ['Top Set']),
        TemplateExercise.typed(name: 'Calf Press', types: ['Warm-up']),
        TemplateExercise(name: 'Lateral Raise', sets: []),
      ],
    );
    final templates = {'A': a, 'B': b};
    (List<String>, List<String>) muscles(String name) => switch (name) {
      'Leg Press' || 'Leg Extension' => (['Quads'], ['Hamstrings', 'Glutes']),
      'Leg Curl' => (['Hamstrings'], []),
      'Calf Press' => (['Calves'], []),
      _ => (['Side Delts'], []),
    };
    final eightDays = Mesocycle(
      id: 'eight',
      start: c.start,
      microDays: 8,
      schedule: {1: 'A', 3: 'A', 5: 'B', 8: 'missing'},
    );
    final repeated = plannedWeeklyVolume(eightDays, templates, muscles);
    expect(repeated['Quads']!.directDaysPerWeek, 3 * 7 / 8); // Several sets/exercises still count as one day.
    expect(repeated['Hamstrings']!.directDaysPerWeek, 2 * 7 / 8); // Secondary work on day 5 adds no day.
    expect(repeated['Glutes']!.directDaysPerWeek, 0);
    expect(repeated.containsKey('Calves'), isFalse); // Warm-up-only work does not add a day.
    expect(repeated.containsKey('Side Delts'), isFalse); // Empty exercises do not add a day.
    final week = Mesocycle(id: 'week', start: c.start, schedule: {1: 'B', 4: 'B'});
    expect(plannedWeeklyVolume(week, templates, muscles)['Quads']!.directDaysPerWeek, 2);
  });
}
