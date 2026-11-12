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

  test('next session is prescribed from the last one; one tap follows it', () async {
    final store = await seeded();
    final legs = store.templates.firstWhere((t) => t.name == 'Legs');
    store.startSession(legs);
    logAll(store, 100, 12, 2);
    store.finishSession();
    expect(store.history.single.exercises, hasLength(4));

    // Outside a cycle there is no RIR target, so the load holds.
    store.startSession(legs);
    final press = store.active!.exercises.first;
    // Outside a cycle previous weight and reps are placeholders; RIR never is.
    expect((press.sets.first.hintWeight, press.sets.first.hintReps, press.sets.first.rir), (100, 12, null));
    store.toggleSet(press, 0);
    expect((press.sets.first.weight, press.sets.first.reps), (100, 12));
    expect(store.rest, isNotNull);
  });

  test('inside a cycle sessions carry the week, lock RIR and progress load', () async {
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
    expect((set.weight, set.targetReps, set.rir, set.targetRir, set.hintReps), (105, 8, null, 2, null));
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
  });

  test('completing sets: fallbacks, validation, rest between sets only, overdue timer', () async {
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

    store.rest = RestTimer(
      startedAt: DateTime.now().subtract(const Duration(seconds: 70)),
      totalSeconds: 60,
      exercise: 'x',
    );
    expect((store.rest!.overdue, store.rest!.remainingSeconds <= -10), (true, true));
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

  test('finishing saves template defaults and structure; unit switch converts weights', () async {
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
