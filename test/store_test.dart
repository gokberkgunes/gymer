import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

class RecordingAlerts extends Alerts {
  final calls = <String>[];
  @override
  void keepAwake(bool on) => calls.add('awake:$on');
  @override
  void scheduleRest(DateTime at, String exercise) => calls.add('rest:$exercise');
  @override
  void cancelRest() => calls.add('cancel');
  @override
  void showLiveRest(
    DateTime endsAt,
    String exercise, {
    required bool endAtZero,
    String icon = 'muscle',
    String overtimeIcon = 'warning',
    String chipText = '',
    bool vibrate = false,
  }) => calls.add('live:$exercise:$icon');
  @override
  void clearLiveRest() => calls.add('liveclear');
}

Future<AppStore> seeded([Alerts? alerts]) async {
  final store = AppStore(alerts: alerts);
  await store.load();
  return store;
}

void logAll(AppStore store, double weight, int reps, int rir) {
  for (final e in store.active!.exercises) {
    for (final s in e.sets) {
      s
        ..weight = weight
        ..reps = reps
        ..rir = rir
        ..done = true;
    }
  }
}

AppStore suggestionStore(
  int reps,
  int? rir, {
  int repMin = 8,
  int repMax = 12,
  double weight = 100,
  String unit = 'kg',
}) {
  final store = AppStore()
    ..exercises = [
      Exercise(name: 'Press', equipment: 'Weight-stack machine', incrementKg: 2.5, repMin: repMin, repMax: repMax),
    ]
    ..templates = [
      WorkoutTemplate(
        id: 'press',
        name: 'Press day',
        exercises: [
          TemplateExercise(name: 'Press', sets: [for (var i = 0; i < 3; i++) TemplateSet(weight: 100, reps: 14)]),
        ],
      ),
    ]
    ..history = [
      Session(
        id: 'baseline',
        templateId: 'press',
        name: 'Press day',
        unit: unit,
        startedAt: DateTime(2026, 1, 1),
        finishedAt: DateTime(2026, 1, 1, 1),
        exercises: [
          SessionExercise(
            name: 'Press',
            sets: [for (var i = 0; i < 3; i++) SetEntry(weight: weight, reps: reps, rir: rir, done: true)],
          ),
        ],
      ),
    ];
  addTearDown(store.dispose);
  return store;
}

void main() {
  test('exercise favourites persist and recents contain performed exercises only', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    final name = legs.exercises.first.name;
    store.toggleExerciseFavourite(name);
    final saved = Exercise.fromJson(store.exercise(name)!.toJson());
    expect(saved.favourite, isTrue);
    expect(saved.copyWith(note: 'Seat 4').favourite, isTrue);
    expect(Exercise.fromJson({'name': 'Old exercise'}).favourite, isFalse);

    store.startSession(legs);
    store.active!.exercises.first.sets.first.done = true;
    store.finishSession();
    expect(store.recentExercises(), [name]);
    store.toggleExerciseFavourite(name);
    expect(store.exercise(name)!.favourite, isFalse);
  });

  test('next-session prescriptions preserve effort, manual choices and one-tap completion', () async {
    // Recorded reps/RIR and automatic mode → next load and rep goal.
    for (final (reps, rir, automatic, load, goal) in <(int, int?, bool, double?, int?)>[
      (9, 2, true, 100, 9),
      (6, 2, true, 92.5, 8),
      (6, null, true, 100, 6),
      (6, 2, false, null, null),
    ]) {
      final store = suggestionStore(reps, rir);
      store.exercises = [store.exercises.single.copyWith(autoProgression: automatic)];
      final history = jsonEncode(store.history.single.toJson());
      store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
      final exercise = store.active!.exercises.single;
      expect((store.active!.cycleId, exercise.calibrate), (null, false));
      expect(
        exercise.sets.map((s) => (s.weight, s.targetReps, s.targetRir, s.rir, s.prescribed)),
        everyElement((load, goal, automatic ? rir : null, null, automatic)),
        reason: '$reps reps @ $rir, auto=$automatic',
      );
      expect(store.fallbackValue(exercise, 0, 'reps'), goal ?? reps);
      expect(store.toggleSet(exercise, 0).ok, isTrue);
      expect((exercise.sets.first.weight, exercise.sets.first.reps), (load ?? 100, goal ?? reps));
      expect(store.rest, isNotNull);
      expect(jsonEncode(store.history.single.toJson()), history);
    }
  });

  test('inside a cycle sessions carry the week, lock RIR and adjust reps before changing load', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    final start = DateTime.now().subtract(const Duration(days: 8));
    store.saveCycle(Mesocycle(id: 'c', start: start, schedule: {1: legs.id}));

    store.startSession(legs, at: start.add(const Duration(hours: 18)));
    logAll(store, 100, 12, 3);
    store.finishSession();

    store.startSession(legs);
    final s = store.active!;
    expect((s.cycleId, s.microcycle, s.phase, s.targetRir, s.rirLocked), ('c', 2, 'Build', 2, true));
    final set = s.exercises.first.sets.first;
    // The progression load is filled in; actual RIR stays blank (only the target is set).
    expect((set.weight, set.targetReps, set.rir, set.targetRir, set.hintReps), (100, 13, null, 2, null));
    expect(store.fallbackValue(s.exercises.first, 0, 'reps'), 13);

    // Baseline reps/RIR and next effort/range → first-day and later build targets.
    for (final (reps, rir, target, minimum, maximum, load, goal) in [
      (9, 1, 3, 14, 18, 100.0, 7),
      (6, 2, 2, 8, 12, 92.5, 8),
      (9, 2, 3, 8, 12, 100.0, 8),
    ]) {
      final store = suggestionStore(reps, rir, repMin: minimum, repMax: maximum);
      final baseline = store.history.single;
      baseline.exercises.single.sets.last.rir = 4; // A stronger position must not inflate calibration.
      final wrong = Session.fromJson({...baseline.toJson(), 'id': 'wrong'})..startedAt = DateTime(2026, 1, 1, 12);
      for (final set in wrong.exercises.single.sets) {
        set
          ..weight = 300
          ..context = const SetContext(setup: 'different machine');
      }
      store.history = [wrong, baseline];
      final cycle = Mesocycle(
        id: 'cycle',
        start: DateTime(2026, 1, 2),
        startRir: target,
        endRir: target,
        deloadMicro: 0,
      );
      store.saveCycle(cycle);
      store.startSession(store.templates.single, at: cycle.start);
      final exercise = store.active!.exercises.single;
      final calibration = store.calibrationFor('Press', 'Straight', store.active!)!;
      expect(exercise.calibrate, isTrue);
      expect((calibration.weight, calibration.targetReps, calibration.targetRir), (load, goal, target));
      expect((exercise.sets.first.hintWeight, store.fallbackValue(exercise, 0, 'reps')), (load, goal));
      exercise.sets[1]
        ..weight = 80
        ..reps = 11
        ..rir = 2; // Keep manually entered later results.
      exercise.sets.first
        ..weight = 100
        ..reps = reps
        ..rir = rir;
      expect(store.toggleSet(exercise, 0).ok, isTrue);
      expect((exercise.calibrate, exercise.calibrationEntered), (false, true));
      expect((exercise.sets[1].weight, exercise.sets[1].reps, exercise.sets[1].rir), (80, 11, 2));
      expect(
        (exercise.sets.last.hintWeight, store.fallbackValue(exercise, 2, 'reps'), exercise.sets.last.targetRir),
        (load, goal, target),
      );
      logAll(store, 100, reps, rir);
      store.finishSession();
      store.startSession(store.templates.single, at: DateTime(2026, 1, 3));
      expect(store.active!.exercises.single.calibrate, isFalse);
      expect(
        store.active!.exercises.single.sets.map((s) => (s.weight, s.targetReps, s.targetRir)),
        everyElement((load, goal, target)),
      );
    }
  });

  test('deload weeks prescribe fewer, lighter straight sets', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    final start = DateTime.now().subtract(const Duration(days: 29));
    store.saveCycle(Mesocycle(id: 'c', start: start, length: 5, deloadMicro: 1));
    store.startSession(legs, at: start.add(const Duration(days: 22)));
    logAll(store, 102.5, 9, 1);
    store.finishSession();

    final saved = jsonEncode(store.toJson());
    final estimate = store.plannedTiming(legs).total;
    expect(jsonEncode(store.toJson()), saved, reason: 'previewing must not start a workout or change its plan');
    store.startSession(legs);
    final press = store.active!.exercises.first;
    expect(store.active!.phase, 'Deload');
    expect(store.active!.estimatedSeconds, estimate);
    expect(estimate, lessThan(store.templateTiming(legs).total));
    // Half of three working sets rounds to two, rather than flooring to one.
    expect(press.sets, hasLength(2));
    // 90% of 102.5 rounded down on Leg Press's 5 kg plate-loaded lattice.
    expect(press.sets.map((set) => (set.weight, set.targetReps, set.targetRir)), everyElement((87.5, 8, 4)));
    store.activeCycle!.deloadManual = true;
    store.startSession(legs);
    expect(store.active!.estimatedSeconds, store.plannedTiming(legs).total);
    expect(store.active!.estimatedSeconds, store.templateTiming(legs).total);

    // A finished deload must never become the next cycle's baseline: calibration reads the last build set.
    store.activeCycle!.deloadManual = false;
    store.startSession(legs);
    logAll(store, 87.5, 8, 4);
    store.finishSession();
    store.saveCycle(Mesocycle(id: 'c2', start: DateTime.now()));
    store.startSession(legs);
    expect(store.calibrationFor(press.name, 'Straight', store.active!)!.weight, greaterThanOrEqualTo(95));
  });

  test('alerts follow the workout and rest timer', () async {
    final alerts = RecordingAlerts();
    final store = await seeded(alerts);
    store.startSession(store.templates.first);
    final e = store.active!.exercises.first;
    e.sets[0]
      ..weight = 50
      ..reps = 10;
    store.toggleSet(e, 0);
    store.setRestTotal(0);
    store.discardSession();
    // Default: the sticky status-bar timer, no "Rest over" alarm.
    expect(alerts.calls, containsAllInOrder(['awake:true', 'live:${e.name}:muscle', 'liveclear', 'awake:false']));
    expect(alerts.calls.where((c) => c.startsWith('rest:')), isEmpty);

    // The alarm is still available as an option.
    alerts.calls.clear();
    store.updateSettings((s) => s.restNotice = 'alarm');
    store.startSession(store.templates.first);
    final f = store.active!.exercises.first;
    f.sets[0]
      ..weight = 50
      ..reps = 10;
    store.toggleSet(f, 0);
    store.discardSession();
    expect(alerts.calls, containsAllInOrder(['rest:${f.name}', 'cancel']));

    store.rest = RestTimer(
      startedAt: DateTime.now().subtract(const Duration(seconds: 70)),
      totalSeconds: 60,
      exercise: 'x',
    );
    expect((store.rest!.overdue, store.rest!.remainingSeconds <= -10), (true, true));
  });

  test('persists, restores and round-trips a JSON backup', () async {
    final dir = await Directory.systemTemp.createTemp('gymer');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/gymer.json');

    final a = AppStore(file: file);
    await a.load();
    a.settings.includePartialSets = false;
    final originalEstimate = a.templateTiming(a.templates.first).total;
    a.startSession(a.templates.first);
    expect(a.active!.estimatedSeconds, originalEstimate);
    a.active!.exercises.first.sets.first.weight = 42.5;
    a.saveCycle(Mesocycle(id: 'c', start: DateTime(2026, 1, 5), weekRir: {2: 1}));
    await a.flush();
    // The home-screen widget gets each coming day's workout and cycle week; days outside the cycle are absent.
    final legsId = a.templates.firstWhere((t) => t.name == 'Legs').id;
    a.activeCycle!.schedule = {1: legsId};
    final widget = a.widgetPlan(from: DateTime(2026, 1, 12), days: 2)['days'] as Map;
    expect(widget, {
      '2026-01-12': {'workout': 'Legs', 'week': 'W2 · Build'},
      '2026-01-13': {'workout': '', 'week': 'W2 · Build'},
    });
    expect((a.widgetPlan(from: DateTime(2025, 12, 1), days: 3)['days'] as Map).isEmpty, isTrue);
    a.activeCycle!.schedule = {};

    // CSV export: one row per completed set, quoted where needed, in the workout's own unit.
    final csv = AppStore()
      ..history = [
        Session(
          id: 's',
          templateId: null,
          name: 'Push, "heavy"',
          unit: 'lb',
          startedAt: DateTime(2026, 3, 4, 18),
          exercises: [
            SessionExercise(
              name: 'Bench',
              sets: [
                SetEntry(weight: 225, reps: 5, rir: 1, done: true, note: 'felt\ngood'),
                SetEntry(weight: 225, reps: 4),
              ],
            ),
          ],
        ),
      ];
    addTearDown(csv.dispose);
    expect(csv.historyCsv().split('\r\n'), [
      'date,workout,exercise,set,type,weight,unit,reps,rir,method,note',
      '2026-03-04,"Push, ""heavy""",Bench,1,Normal,225,lb,5,1,Straight,"felt\ngood"',
      '',
    ]);
    // Workouts can be reordered on Train: after another workout, or to the top.
    final order = AppStore()
      ..templates = [
        for (final n in ['A', 'B', 'C']) WorkoutTemplate(id: n, name: n, exercises: []),
      ];
    addTearDown(order.dispose);
    order.moveTemplate('A', after: 'C');
    order.moveTemplate('C');
    order.moveTemplate('missing', after: 'A');
    expect(order.templates.map((t) => t.id), ['C', 'B', 'A']);
    // Other chart views of the same sessions: heaviest set, reps at that weight, and volume.
    csv.history.single.exercises.single.sets.addAll([
      SetEntry(weight: 225, reps: 3, done: true),
      SetEntry(weight: 185, reps: 8, done: true),
    ]);
    expect(
      [
        for (final m in ['weight', 'reps', 'volume']) csv.exerciseMetric('bench', m).single.$2,
      ],
      [
        closeTo(102.058, 0.001), // 225 lb shown in the display unit, kg
        8,
        closeTo((225 * 8 + 185 * 8) / 2.2046226218, 1e-6),
      ],
    );
    // Progress photos sit beside the data file by date, never inside the saved data.
    expect((AppStore().photosAvailable, a.photosAvailable, (await a.progressPhotos()).length), (false, true, 0));
    expect(await a.addProgressPhoto([1, 2, 3], 'PNG', DateTime(2026, 2, 1)), isNull);
    expect(await a.addProgressPhoto([4], '../x', DateTime(2026, 1, 1)), isNull);
    expect(await a.addProgressPhoto([], 'jpg', DateTime(2026, 1, 1)), isNotNull);
    final photos = await a.progressPhotos();
    expect(
      [for (final (date, f) in photos) (dateKey(date), f.path.split('.').last)],
      [('2026-01-01', 'jpg'), ('2026-02-01', 'png')],
    );
    await a.deleteProgressPhoto(file); // only files of the photo folder are ever deleted
    await a.deleteProgressPhoto(photos.first.$2);
    expect((await a.progressPhotos()).length, 1);
    expect((file.existsSync(), jsonEncode(a.toJson()).contains('photo')), (true, false));

    final b = AppStore(file: file);
    await b.load();
    expect(b.active?.exercises.first.sets.first.weight, 42.5);
    expect(b.activeCycle?.weekRir, {2: 1});
    expect(b.active?.estimatedSeconds, originalEstimate);
    expect(b.settings.includePartialSets, isFalse);

    final c = await seeded();
    await c.importJson(file.readAsStringSync());
    expect(c.active?.exercises.first.sets.first.weight, 42.5);
    await expectLater(c.importJson('{"x":1}'), throwsFormatException);

    // Editing the plan after resume cannot rewrite the original estimate used for comparisons.
    c.templates.first.setSeconds += 60;
    c.addSet(c.active!.exercises.first);
    expect(c.active!.estimatedSeconds, originalEstimate);
    c.active!
      ..clockStarted = true
      ..clockElapsed = originalEstimate + 120;
    c.active!.exercises.first.sets.first
      ..done = true
      ..reps = 8;
    c.finishSession();
    final recorded = Session.fromJson(c.history.first.toJson());
    expect(recorded.estimatedSeconds, originalEstimate);
    expect(recorded.duration.inSeconds, originalEstimate + 120);
    final legacy = recorded.toJson()..remove('estimatedSeconds');
    expect(Session.fromJson(legacy).estimatedSeconds, isNull, reason: 'never invent an estimate for old history');

    // Resume a generated prescription with a completed working set as its live baseline.
    final coached = suggestionStore(6, 2);
    coached.startSession(coached.templates.single, at: DateTime(2026, 1, 2));
    coached.active!.exercises.single.sets.first.rir = 2;
    coached.toggleSet(coached.active!.exercises.single, 0);
    final resumed = AppStore();
    addTearDown(resumed.dispose);
    await resumed.importJson(jsonEncode(coached.toJson()));
    final restored = resumed.active!.exercises.single;
    expect(restored.sets.first.done, isTrue);
    expect(
      (restored.sets[1].weight, resumed.fallbackValue(restored, 1, 'reps'), restored.sets[1].targetRir),
      (92.5, 8, 2),
    );
    expect(resumed.toggleSet(restored, 1).ok, isTrue);
    expect((restored.sets[1].weight, restored.sets[1].reps, restored.sets[1].rir), (92.5, 8, null));
  });

  test('set completion validates values, bounds defaults and preserves entered results', () async {
    final store = await seeded();
    store.startSession(null);
    expect(store.addSessionExercise('Leg Curl'), isNull);
    expect(store.addSessionExercise('Leg Curl'), isNotNull, reason: 'duplicates are blocked');
    final e = store.active!.exercises.single;

    expect(store.toggleSet(e, 0).ok, isFalse);
    expect(e.sets[0].invalid, {'weight', 'reps'});

    e.sets[0]
      ..weight = 40
      ..reps = 10;
    expect(store.toggleSet(e, 0).ok, isTrue);
    expect((store.rest?.exercise, store.rest?.setIndex), ('Leg Curl', 0));
    expect((e.sets[1].hintWeight, e.sets[1].hintReps), (40, 10), reason: 'later sets inherit placeholders');

    expect(store.toggleSet(e, 1).ok, isTrue, reason: 'blank fields fall back to the placeholder');
    expect((e.sets[1].weight, e.sets[1].reps), (40, 10));

    store.toggleSet(e, 2);
    expect(store.rest, isNull, reason: 'no rest after the exercise\'s last set');
    expect(store.removeSessionExercise(e), isNotNull, reason: 'completed exercises stay');

    // Stale 14-rep defaults must yield to a freshly logged 9 reps at 1 RIR.
    e.sets = [
      SetEntry(weight: 40, reps: 9, rir: 1),
      SetEntry(weight: 40, prescribed: true, hintReps: 14),
      SetEntry(weight: 40, hintReps: 14),
      SetEntry(reps: 8, hintWeight: 50),
    ];
    expect(store.toggleSet(e, 0).ok, isTrue);
    expect(
      [
        for (final i in [1, 2]) store.fallbackValue(e, i, 'reps'),
      ],
      [9, 9],
    );
    store.settings.updateFollowingDefaults = true;
    store.toggleSet(e, 0);
    store.toggleSet(e, 0);
    expect([e.sets[1].hintReps, e.sets[2].hintReps, e.sets[3].hintWeight, e.sets[3].reps], [9, 9, 40, 8]);
    e.sets[1].reps = 12; // An entered result is an observation, not an automatic default.
    expect(store.toggleSet(e, 1).ok, isTrue);
    expect(e.sets[1].reps, 12);

    e.sets = [SetEntry(weight: 100, reps: 9, rir: 1, done: true), SetEntry(hintWeight: 100, hintReps: 14)];
    final next = e.sets.last;
    for (final (load, target, reps) in <(double, int, int?)>[
      (100, 3, 7),
      (100, 0, 10),
      (95, 1, 11),
      (110, 1, 5),
      (200, 1, null),
    ]) {
      next
        ..weight = load
        ..targetRir = target;
      expect(store.fallbackValue(e, 1, 'reps'), reps, reason: '$load kg at $target RIR');
    }
    expect(store.toggleSet(e, 1).ok, isFalse);
    expect(next.invalid, contains('reps'));
    next.weight = 95;
    e.sets.first.type = 'Warm-up';
    expect(store.fallbackValue(e, 1, 'reps'), 14);
    e.sets.first
      ..type = 'Normal'
      ..context = const SetContext(setup: 'different machine');
    expect(store.fallbackValue(e, 1, 'reps'), 14);
    e.calibrationEntered = true;
    e.sets.first
      ..context = next.context
      ..done = false;
    expect(store.fallbackValue(e, 1, 'reps'), 11);
  });

  test('require previous set blocks out-of-order completion', () async {
    final store = await seeded();
    store.updateSettings((s) => s.requirePreviousSet = true);
    store.startSession(null);
    store.addSessionExercise('Leg Curl');
    final e = store.active!.exercises.single;
    e.sets[1]
      ..weight = 40
      ..reps = 10;
    expect(store.toggleSet(e, 1).message, contains('Complete set 1'));
  });

  test('finished plans and load suggestions respect units, inventory and recorded history', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    store.startSession(legs);
    logAll(store, 100, 8, 2);
    store.addSet(store.active!.exercises.first);
    expect(store.templateChanged(), isTrue);
    store.finishSession(saveStructure: true);

    final press = legs.exercises.first;
    expect(press.sets, hasLength(4));
    expect((press.sets.first.weight, press.sets.first.reps), (100, 8));
    expect(store.history.first.exercises.first.sets.last.done, isFalse, reason: 'unfinished sets are kept');

    store.updateSettings((s) => s.unit = 'lb');
    // Plans follow the unit; finished workouts keep what was recorded and are converted when read.
    expect((store.history.first.unit, store.history.first.exercises.first.sets.first.weight), ('kg', 100));
    expect(store.lastTimeSets(press.name, legs.id)!.first.weight, 220);
    // Plans become loads the gym can make in the new unit, never 220.46, and switching back restores 100 kg.
    expect(press.sets.first.weight, 220);
    store.updateSettings((s) => s.unit = 'kg');
    expect(press.sets.first.weight, 100);

    // History load/reps/unit and restricted plates → achievable suggested load.
    for (final (load, reps, unit, limited, expected) in [
      (220.0, 9, 'lb', false, 97.5),
      (60.0, 6, 'kg', true, 60.0),
      (20.0, 2, 'kg', true, 20.0),
    ]) {
      final store = suggestionStore(reps, 2, weight: load, unit: unit);
      if (limited) {
        store.exercises = [store.exercises.single.copyWith(equipment: 'Barbell')];
        store.settings.plateProfile
          ..platesKg = [20]
          ..limitedPairs = true
          ..pairsKg = {20: 1};
      }
      final history = jsonEncode(store.history.single.toJson());
      store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
      expect(
        store.active!.exercises.single.sets.map((s) => (s.weight, s.targetReps, s.targetRir)),
        everyElement((expected, reps, 2)),
      );
      if (limited) expect(store.plates(expected, name: 'Press').exact, isNotNull);
      expect(jsonEncode(store.history.single.toJson()), history);
    }
  });

  test('records, last-time values, set undo and exercise moves', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    store.startSession(legs);
    logAll(store, 100, 10, 2);
    final first = store.finishSession()!;
    expect(first.bests, isEmpty, reason: 'a first session has nothing to beat');

    store.startSession(legs);
    final e = store.active!.exercises.first;
    expect(store.lastTimeSets(e.name, legs.id)!.first.weight, 100);
    logAll(store, 100, 10, 2);
    e.sets.first
      ..weight = 105
      ..reps = 8;
    expect(store.recordKind(e, e.sets.first), 'weight');
    expect(store.recordKind(e, e.sets[1]), isNull);

    final removed = e.sets[1];
    store.removeSet(e, removed);
    store.restoreSet(e, 1, removed);
    expect(e.sets[1], same(removed));

    final second = store.active!.exercises[1];
    store.moveSessionExercise(second, -1);
    expect(store.active!.exercises.first, same(second));
    store.moveSessionExercise(second, -1);
    expect(store.active!.exercises.first, same(second), reason: 'cannot move past the top');

    final summary = store.finishSession()!;
    expect(
      [for (final b in summary.bests) '${b.exercise}|${b.kind}|${b.value}|${b.gain}'],
      ['${e.name}|weight|105 kg × 8|+5 kg'],
    );
    expect(summary.exercises.firstWhere((x) => x.name == e.name).best, '105 kg × 8');
  });

  test('a damaged backup is rejected without touching current data', () async {
    final store = await seeded();
    final names = [for (final t in store.templates) t.name];
    final json = store.toJson()
      ..['templates'] = <Object>[]
      ..['history'] = ['not a session'];
    await expectLater(store.importJson(jsonEncode(json)), throwsFormatException);
    expect([for (final t in store.templates) t.name], names);
    expect(store.history, isEmpty);
  });
}
