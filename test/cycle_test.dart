// Expected statuses come from the Flet app's storage.mesocycle_status().
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/coach.dart';
import 'package:gymer/logic/cycle.dart';
import 'package:gymer/logic/volume.dart';
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

  test(
    'weekly sets count direct as 1, indirect as 0.5, special methods as estimates; the coach reads and adjusts them',
    () {
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
      // Myo-reps count in straight-set equivalents: activation 1, each myo-set half a set.
      expect(v['Hamstrings']!.sets, closeTo((0.5 * 2 + 2) * 7 / 3, 1e-9));
      expect(v['Hamstrings']!.direct.protocolGroups, closeTo(7 / 3, 1e-9));
      expect(v['Quads']!.directDaysPerWeek, closeTo(7 / 3, 1e-9));
      expect(v['Hamstrings']!.directDaysPerWeek, closeTo(7 / 3, 1e-9)); // Protocol work is a training day too.
      expect(v['Quads']!.countedSets(includePartialSets: false), closeTo(2 * 7 / 3, 1e-9));
      expect(v['Hamstrings']!.countedSets(includePartialSets: false), closeTo(2 * 7 / 3, 1e-9));

      // One group counts at most three sets; a cluster group is one set, scaled by the fragments done; a drop
      // without its activation set is still half a set.
      VolumeRow row(String type, {bool done = true, bool start = false}) => VolumeRow(
        scope: 'x',
        type: type,
        active: done,
        groupStart: start,
        primary: const ['Quads'],
        secondary: const [],
      );
      double equivalent(List<VolumeRow> rows) => summarizeVolume(rows).direct['Quads']?.equivalent ?? 0;
      expect(equivalent([row('Activation'), for (var i = 0; i < 6; i++) row('Drop Set')]), 3);
      expect(equivalent([row('Activation', done: false), row('Rest-Pause'), row('Rest-Pause', done: false)]), 0.5);
      expect(
        equivalent([
          row('Cluster Set', start: true),
          row('Cluster Set'),
          row('Cluster Set', start: true),
          row('Cluster Set', done: false),
        ]),
        1.5,
      );
      final store = AppStore()
        ..templates = [a]
        ..cycles = [c]
        ..exercises = [
          const Exercise(name: 'Leg Press', primary: ['Quads'], secondary: ['Hamstrings']),
          const Exercise(name: 'Leg Curl', primary: ['Hamstrings']),
        ];
      addTearDown(store.dispose);
      expect(Settings.fromJson({}).includePartialSets, isTrue);
      expect(store.editorWeeklySets(a).after['Hamstrings'], closeTo(3 * 7 / 3, 1e-9));
      store.settings.includePartialSets = false;
      expect(store.editorWeeklySets(a).after['Hamstrings'], closeTo(2 * 7 / 3, 1e-9));
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

      // Coach: three build weeks logged, the fourth running. Bench held twice without fatigue (+1 set), squat
      // fell (−1 set), curls fell too but are already under maintenance volume, rows progressed.
      final start = addDays(dateOnly(DateTime.now()), -21);
      final plan = WorkoutTemplate(
        id: 'P',
        name: 'Push',
        exercises: [
          for (final n in ['Bench', 'Squat', 'Curl', 'Row']) TemplateExercise(name: n),
        ],
      );
      Session logged(int weekIndex, Map<String, (int, int)> repsRir) => Session(
        id: 'w$weekIndex',
        templateId: 'P',
        name: 'Push',
        unit: 'kg',
        cycleId: 'coach',
        phase: 'Build',
        startedAt: addDays(start, weekIndex * 7).add(const Duration(hours: 10)),
        exercises: [
          for (final MapEntry(key: name, value: (reps, rir)) in repsRir.entries)
            SessionExercise(
              name: name,
              sets: [for (var i = 0; i < 3; i++) SetEntry(weight: 100, reps: reps, rir: rir, done: true)],
            ),
        ],
      );
      final coach = AppStore()
        ..templates = [plan]
        ..exercises = const [
          Exercise(name: 'Bench', primary: ['Chest']),
          Exercise(name: 'Squat', primary: ['Quads']),
          Exercise(name: 'Curl', primary: ['Biceps']),
          Exercise(name: 'Row', primary: ['Back']),
        ]
        ..cycles = [
          Mesocycle(id: 'coach', start: start, length: 6, schedule: {1: 'P'}),
        ]
        ..history = [
          logged(2, {'Bench': (10, 2), 'Squat': (8, 2), 'Curl': (8, 2), 'Row': (12, 2)}),
          logged(1, {'Bench': (10, 2), 'Squat': (10, 2), 'Curl': (10, 2), 'Row': (11, 2)}),
          logged(0, {'Bench': (10, 2), 'Squat': (10, 2), 'Curl': (10, 2), 'Row': (10, 2)}),
        ];
      addTearDown(coach.dispose);
      // Quads and biceps fell, half of the four judged muscles: whole-body fatigue. The coach offers the deload
      // early and holds set changes back until that is taken or dismissed.
      expect(coach.coachReport().deload.map((v) => v.muscle), ['Quads', 'Biceps']);
      expect(coach.coachReport().suggestions, isEmpty);
      final early = Mesocycle.fromJson(coach.cycles.single.toJson())..weekRir = {2: 2, 5: 0, 6: 5};
      final real = coach.cycles.single;
      coach.cycles = [early];
      coach.startDeloadNow(); // week 4 becomes the deload: three build weeks stay, later build overrides go
      expect((early.length, early.deloadMicro, cycleStatus(early).phase), (4, 1, 'Deload'));
      expect(early.weekRir, {2: 2, 4: 5});
      expect(coach.coachReport().suggestions, isEmpty);
      coach.cycles = [real];
      coach.dismissDeloadHint();
      expect(coach.coachReport().deload, isEmpty);
      expect(Mesocycle.fromJson(real.toJson()).deloadHintDismissed, 4);
      // Three weekly quad sets are under MEV: by default the coach removes nothing there.
      expect(coach.coachReport().suggestions.map((s) => (s.muscle, s.delta)), [('Chest', 1)]);
      expect(Settings.fromJson((coach.settings..coachKeepMev = false).toJson()).coachKeepMev, isFalse);
      var report = coach.coachReport();
      expect(
        {for (final v in report.verdicts.values) v.muscle: v.trend},
        {'Chest': Trend.holding, 'Quads': Trend.falling, 'Biceps': Trend.falling, 'Back': Trend.progressing},
      );
      expect(report.verdicts['Quads']!.fatigue, ['the first set was weaker than the time before']);
      expect(
        [for (final s in report.suggestions) (s.muscle, s.delta, s.exercise, s.templateId)],
        [('Quads', -1, 'Squat', 'P'), ('Chest', 1, 'Bench', 'P')],
      );
      expect(report.rising.map((v) => v.muscle), ['Back']);
      // Each change is read against the volume landmarks: the same drop means different things low and high.
      expect(
        [
          for (final sets in [1.0, 3.0, 5.0, 10.0, 18.0, 30.0]) volumeZone('Chest', sets),
        ],
        ['Below MV', 'MV', 'MEV', 'MAV', 'MRV', 'Above MRV'],
      );
      expect((volumeZone('Back', 25), volumeZone('Neck', 5)), ('Above MAV', null));
      expect(zoneAdvice(Trend.falling, 'MV'), contains('too little work'));
      expect(zoneAdvice(Trend.falling, 'MRV'), contains('Fewer sets'));
      expect(zoneAdvice(Trend.holding, 'MAV'), isEmpty);
      // Same load and reps closer to failure: weaker by estimated 1RM, unchanged by volume. Special methods are
      // always compared by total volume, whatever the setting.
      SessionExercise straight(int rir) => SessionExercise(
        name: 'Bench',
        sets: [for (var i = 0; i < 3; i++) SetEntry(weight: 100, reps: 10, rir: rir, done: true)],
      );
      expect(compareExercise(straight(1), 'kg', straight(3), 'kg')!.trend, Trend.falling);
      expect(compareExercise(straight(1), 'kg', straight(3), 'kg', byVolume: true)!.percent, 0);
      SessionExercise myo(List<int> reps) => SessionExercise(
        name: 'Curl',
        method: 'Myo-Reps',
        sets: [
          for (final (i, r) in reps.indexed)
            SetEntry(weight: 50, reps: r, type: i == 0 ? 'Activation' : 'Myo-set', done: true),
        ],
      );
      expect(compareExercise(myo([15, 5, 5]), 'kg', myo([15, 5, 4]), 'kg')!.percent, closeTo(100 / 24, 1e-9));
      expect(compareExercise(myo([13, 5]), 'kg', myo([15, 5]), 'kg')!.fatigue, isNotEmpty);
      expect(compareExercise(myo([15, 5]), 'kg', straight(2), 'kg'), isNull); // a changed method is not comparable
      coach.settings.coachCompare = 'volume';
      expect(coach.coachReport().verdicts['Quads']!.percent, closeTo(-20, 1e-9)); // 3 × 8 against 3 × 10
      expect(Settings.fromJson(coach.settings.toJson()).coachCompare, 'volume');
      expect(Settings.fromJson({'coachCompare': 'x'}).coachCompare, 'strength');
      coach.settings.coachCompare = 'strength';
      // Cycle review: average weekly sets and compounded change per muscle, and where to start next time. Chest
      // only ever held (start higher), quads ended falling (start lower), biceps too but sit under maintenance.
      final response = coach.cycleResponses(real);
      expect(
        {for (final r in response.values) r.muscle: (r.sets, r.nextStart)},
        {'Back': (3.0, 0), 'Quads': (3.0, -1), 'Chest': (3.0, 1), 'Biceps': (3.0, -1)},
      );
      expect(response['Back']!.percent, greaterThan(response['Chest']!.percent));
      expect(coach.summarizeCycle(real).response.map((r) => r.muscle), response.keys);
      final next = coach.cloneCycle(real);
      expect(
        [for (final a in coach.startingVolumes(real, next)) (a.muscle, a.exercise, a.delta, a.micro)],
        [('Quads', 'Squat', -1, 0), ('Chest', 'Bench', 1, 0)],
      );
      // Personal landmarks need the muscle in two cycles: fewest sets that progressed, fewest above that fell.
      MuscleResponse weeks(List<(double, Trend)> rows) =>
          MuscleResponse('Chest', [for (final (sets, trend) in rows) (micro: 2, sets: sets, trend: trend, percent: 0)]);
      final first = {
        'Chest': weeks([(10, Trend.progressing), (6, Trend.progressing), (5, Trend.falling), (14, Trend.falling)]),
      };
      // Sets that bought nothing: as much progress at 8 weekly sets as at 12 means starting lower.
      MuscleResponse gains(List<(double, double)> rows) => MuscleResponse('Triceps', [
        for (final (sets, percent) in rows) (micro: 2, sets: sets, trend: trendOf(percent), percent: percent),
      ]);
      expect(gains([(8, 2.5), (10, 2), (12, 2.4)]).sameAtFewer, (fewer: 8.0, more: 12.0));
      expect(gains([(8, 2.5), (10, 2), (12, 2.4)]).nextStart, -1);
      expect((gains([(8, 1.2), (12, 3)]).sameAtFewer, gains([(8, 2), (9, 2)]).sameAtFewer), (null, null));
      expect(personalRanges([first]), isEmpty);
      expect(
        personalRanges([
          first,
          {
            'Chest': weeks([(8, Trend.holding)]),
          },
        ])['Chest'],
        (low: 6.0, high: 14.0, cycles: 2),
      );
      // Rep drop-off counts once it repeats (or has no earlier week to compare): no added set goes there.
      MuscleVerdict drops(bool dropOff) => MuscleVerdict('Chest', [
        ExerciseTrend(name: 'Bench', templateId: 'P', percent: 0, pairs: 3, dropOff: dropOff),
      ]);
      expect(droppingOff(drops(true), null), {'bench'});
      expect(droppingOff(drops(true), drops(false)), isEmpty);
      expect(adjustmentTarget(real, {'P': plan}, coach.musclesOf, 'Chest', 1, drops(true), avoid: {'bench'}), isNull);
      // Muscle goals: a maintained muscle is never changed; the choice survives saving and the next cycle.
      coach.setMuscleGoal('Chest', 'maintain');
      expect(coach.coachReport().suggestions.map((s) => s.muscle), ['Quads']);
      expect(
        Mesocycle.fromJson({
          ...real.toJson(),
          'muscleGoals': {'Chest': 'maintain', 'Back': 'x'},
        }).muscleGoals,
        {'Chest': 'maintain'},
      );
      expect(coach.cloneCycle(real).muscleGoals, {'Chest': 'maintain'});
      coach.setMuscleGoal('Chest', 'priority');
      expect(coach.coachReport().suggestions.last.reason, contains('Priority'));
      coach.setMuscleGoal('Chest', '');
      expect(real.muscleGoals, isEmpty);
      // Recovery check-ins of the finished week: soreness turns a flat muscle into a removal, a run-down week
      // blocks additions, and a low pump with early recovery earns a set after a single flat week.
      final lastWeek = coach.history.first;
      List<(String, int)> suggested() => [for (final s in coach.coachReport().suggestions) (s.muscle, s.delta)];
      coach.editCheckIn(lastWeek.id, (c) => c.recovered['Chest'] = 0);
      expect(suggested(), [('Quads', -1), ('Chest', -1)]);
      lastWeek.checkIn = CheckIn(sleep: 0);
      expect(suggested(), [('Quads', -1)]);
      lastWeek.checkIn = CheckIn(pump: {'Chest': 0}, recovered: {'Chest': 2}, overall: 2);
      final earlier = coach.history.removeLast();
      expect(coach.coachReport().suggestions.last.reason, contains('the pump was low'));
      expect(Session.fromJson(lastWeek.toJson()).checkIn!.toJson(), lastWeek.checkIn!.toJson());
      expect(
        Session.fromJson({
          ...lastWeek.toJson(),
          'checkIn': {
            'pump': {'Chest': 9},
            'sleep': 'x',
          },
        }).checkIn,
        isNull,
      );
      coach.history.add(earlier);
      lastWeek.checkIn = null;
      for (final s in report.suggestions) {
        coach.applySuggestion(s);
        coach.applySuggestion(s); // one change per muscle per week
      }
      report = coach.coachReport();
      expect(report.suggestions.map((s) => s.applied?.delta), [-1, 1]);
      expect((report.volume['Chest']!.sets, report.volume['Quads']!.sets), (4, 2));
      expect(report.performed!['Chest'], isNull); // nothing trained yet in the running week
      coach.startSession(plan);
      expect([for (final e in coach.active!.exercises) e.sets.length], [4, 2, 3, 3]);
      expect(coach.templateChanged(), isFalse); // the coach's sets are the plan, not an edit to ask about
      expect(plan.exercises.map((e) => e.sets.length), everyElement(3)); // the saved workout is never rewritten
      // Planned against done: three of the four planned bench sets completed so far this week.
      for (final set in coach.active!.exercises.first.sets.take(3)) {
        set
          ..weight = 100
          ..reps = 10
          ..done = true;
      }
      final thisWeek = coach.active!..finishedAt = DateTime.now();
      coach.history.insert(0, thisWeek);
      final live = coach.coachReport();
      expect((live.volume['Chest']!.sets, live.performed!['Chest']!.sets), (4, 3));
      expect(live.performed!['Quads'], isNull);
      coach.history.removeAt(0);
      coach.discardSession();
      final kept = Mesocycle.fromJson(coach.cycles.single.toJson());
      expect(kept.setAdjustments.map((a) => (a.muscle, a.exercise, a.delta, a.micro)), [
        ('Quads', 'Squat', -1, 4),
        ('Chest', 'Bench', 1, 4),
      ]);
      expect(coach.cloneCycle(coach.cycles.single).setAdjustments, isEmpty); // the next cycle starts from the base
      coach.undoSuggestion(report.suggestions.last);
      expect(coach.coachReport().volume['Chest']!.sets, 3);
      // A missed workout in the finished week blocks additions, never removals.
      coach.undoSuggestion(report.suggestions.first);
      coach.cycles.single.schedule[3] = 'P';
      expect(coach.coachReport().suggestions.map((s) => s.muscle), ['Quads']);
      // Outside a cycle: completed sets of the last seven days, arrows by calendar week, falling muscles listed.
      coach.cycles = [];
      final free = coach.coachReport();
      expect((free.planned, free.suggestions.length), (false, 0));
      expect(free.declining.map((v) => v.muscle), ['Quads', 'Biceps']);
    },
  );
}
