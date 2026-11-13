import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/progression.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

AppStore suggestionStore({int repMin = 8, int repMax = 12}) => AppStore()
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
  ];

void recordBaseline(AppStore store, int reps, int? rir, {String? cycleId, String unit = 'kg', double weight = 100}) {
  store.history = [
    Session(
      id: 'baseline',
      templateId: 'press',
      name: 'Press day',
      unit: unit,
      startedAt: DateTime(2026, 1, 1),
      finishedAt: DateTime(2026, 1, 1, 1),
      cycleId: cycleId,
      phase: cycleId == null ? null : 'Build',
      exercises: [
        SessionExercise(
          name: 'Press',
          sets: [for (var i = 0; i < 3; i++) SetEntry(weight: weight, reps: reps, rir: rir, done: true)],
        ),
      ],
    ),
  ];
}

void expectSupported(SessionExercise exercise, List<SetEntry> evidence) {
  for (var i = 0; i < exercise.sets.length; i++) {
    final set = exercise.sets[i];
    final source = evidence[i];
    expect(set.targetReps, isPositive);
    expect(set.targetRir, isNotNull);
    final requested = setOneRm(set.weight ?? set.hintWeight, set.targetReps, set.targetRir)!;
    expect(requested, lessThanOrEqualTo(setOneRm(source.weight, source.reps, source.rir)! + 1e-6));
  }
}

void main() {
  test('all 7–13 rep and 0–4 RIR boundaries keep the load, including calibration and changed cycle effort', () {
    for (var reps = 7; reps <= 13; reps++) {
      for (var actualRir = 0; actualRir <= 4; actualRir++) {
        for (var targetRir = 0; targetRir <= 4; targetRir++) {
          final source = SetEntry(weight: 100, reps: reps, rir: actualRir, done: true);
          final rec = recommend(
            previous: [source],
            method: 'Straight',
            targetRir: targetRir,
            unit: 'kg',
            increment: 2.5,
          )!;
          expect((rec.action, rec.weight), ('hold', 100), reason: '$reps reps @ $actualRir → $targetRir RIR');
          expect(rec.targetReps, reps + actualRir - targetRir);
          final calibration = calibrationRecommendation(
            weight: 100,
            reps: reps,
            rir: actualRir,
            method: 'Straight',
            targetRir: targetRir,
            unit: 'kg',
            increment: 2.5,
          )!;
          expect((calibration.weight, calibration.targetReps, calibration.targetRir), (100, rec.targetReps, targetRir));
        }
      }
    }
  });

  test('outside the window the formula sets the load, and rounding or caps never leave impossible rep goals', () {
    final source = SetEntry(weight: 100, reps: 6, rir: 2, done: true);
    final down = recommend(previous: [source], method: 'Straight', targetRir: 2, unit: 'kg', increment: 2.5)!;
    // The estimated load for eight reps at 2 RIR is 94.75 kg, rounded down to 92.5.
    expect((down.action, down.weight, down.targetReps, down.targetRir), ('decrease', 92.5, 8, 2));

    for (final reps in [1, 2, 6, 14, 20]) {
      for (final rir in [0, 2, 4, 8]) {
        for (final step in [2.5, 5.0, 25.0]) {
          final row = SetEntry(weight: 100, reps: reps, rir: rir, done: true);
          final rec = recommend(previous: [row], method: 'Straight', targetRir: 2, unit: 'kg', increment: step)!;
          expect(rec.weight, inInclusiveRange(90, 110));
          if (rec.applyWeight) {
            expect(setOneRm(rec.weight, rec.targetReps, rec.targetRir)!, lessThanOrEqualTo(row.e1rm! + 1e-6));
          }
        }
      }
    }
    final capped = recommend(
      previous: [SetEntry(weight: 100, reps: 2, rir: 1, done: true)],
      method: 'Straight',
      targetRir: 1,
      unit: 'kg',
      increment: 2.5,
      repMin: 14,
      repMax: 18,
    )!;
    expect(capped.weight, 90);
    expect(capped.targetReps, lessThan(14), reason: 'the 10% limit must change the rep goal too');
  });

  test('without a cycle, suggestions preserve actual 2 RIR instead of forcing old 14-rep defaults', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 9, 2);
    final original = jsonEncode(store.history.single.toJson());
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    final exercise = store.active!.exercises.single;
    expect(store.active!.cycleId, isNull);
    expect(exercise.calibrate, isFalse);
    for (var i = 0; i < exercise.sets.length; i++) {
      final set = exercise.sets[i];
      expect((set.weight, set.targetReps, set.targetRir, set.rir), (100, 9, 2, null));
      expect(store.fallbackValue(exercise, i, 'reps'), 9);
    }
    expectSupported(exercise, store.history.single.exercises.single.sets);
    expect(jsonEncode(store.history.single.toJson()), original);
  });

  test('the first mesocycle workout and later build workouts agree on achievable targets', () {
    final store = suggestionStore(repMin: 14, repMax: 18);
    addTearDown(store.dispose);
    recordBaseline(store, 9, 1);
    final cycle = Mesocycle(id: 'cycle', start: DateTime(2026, 1, 2), startRir: 3, endRir: 3, deloadMicro: 0);
    store.saveCycle(cycle);
    store.startSession(store.templates.single, at: cycle.start);
    final first = store.active!.exercises.single;
    expect(first.calibrate, isTrue);
    final calibration = store.calibrationFor('Press', 'Straight', store.active!)!;
    expect((calibration.weight, calibration.targetReps, calibration.targetRir), (100, 7, 3));
    expect(store.fallbackValue(first, 0, 'reps'), 7, reason: 'the old 14-rep template must not override calibration');
    first.sets.first
      ..weight = 100
      ..reps = 9
      ..rir = 1;
    expect(store.toggleSet(first, 0).ok, isTrue);
    expect(first.calibrate, isFalse);
    for (var i = 1; i < first.sets.length; i++) {
      expect((first.sets[i].hintWeight, first.sets[i].targetReps, first.sets[i].targetRir), (100, 7, 3));
      expect(store.fallbackValue(first, i, 'reps'), 7);
    }
    expect(store.toggleSet(first, 1).ok, isTrue);
    expect(first.sets[1].reps, 7);

    // The same history inside this cycle must use the same load/effort calculation.
    store.discardSession();
    recordBaseline(store, 9, 1, cycleId: cycle.id);
    store.history.single.startedAt = cycle.start;
    store.startSession(store.templates.single, at: DateTime(2026, 1, 3));
    final next = store.active!.exercises.single;
    expect(next.calibrate, isFalse);
    expect(next.sets.map((s) => (s.weight, s.targetReps, s.targetRir)), everyElement((100, 7, 3)));
    expectSupported(next, store.history.single.exercises.single.sets);
  });

  test('formula-based reductions are applied with and without a mesocycle and survive resume', () async {
    for (final inCycle in [false, true]) {
      final store = suggestionStore();
      addTearDown(store.dispose);
      recordBaseline(store, 6, 2, cycleId: inCycle ? 'cycle' : null);
      if (inCycle) {
        store.saveCycle(Mesocycle(id: 'cycle', start: DateTime(2025, 12, 31), startRir: 2, endRir: 2, deloadMicro: 0));
      }
      store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
      final exercise = store.active!.exercises.single;
      expect(exercise.sets.map((s) => (s.weight, s.targetReps, s.targetRir)), everyElement((92.5, 8, 2)));
      expectSupported(exercise, store.history.single.exercises.single.sets);
      final resumed = AppStore();
      addTearDown(resumed.dispose);
      await resumed.importJson(jsonEncode(store.toJson()));
      final restored = resumed.active!.exercises.single;
      expect(resumed.fallbackValue(restored, 0, 'reps'), 8);
      expect(resumed.toggleSet(restored, 0).ok, isTrue);
      expect((restored.sets.first.weight, restored.sets.first.reps, restored.sets.first.rir), (92.5, 8, null));
    }
  });

  test('first-day calibration also uses the calculated reduction for the remaining working sets', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 6, 2);
    store.saveCycle(Mesocycle(id: 'cycle', start: DateTime(2026, 1, 2), startRir: 2, endRir: 2));
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    final exercise = store.active!.exercises.single;
    expect(exercise.calibrate, isTrue);
    final calibration = store.calibrationFor('Press', 'Straight', store.active!)!;
    expect((calibration.weight, calibration.targetReps, calibration.targetRir), (92.5, 8, 2));
    expect((exercise.sets.first.hintWeight, store.fallbackValue(exercise, 0, 'reps')), (92.5, 8));
    // A new, honest baseline can differ from the starting hint. The rest of the workout must use it.
    store.applyCalibration(exercise, 0, 100, 6, 2);
    for (var i = 1; i < exercise.sets.length; i++) {
      expect((exercise.sets[i].hintWeight, exercise.sets[i].targetReps, exercise.sets[i].targetRir), (92.5, 8, 2));
      expect(store.fallbackValue(exercise, i, 'reps'), 8);
    }
  });

  test('plate inventory and bar minimums cannot produce an unsupported load and rep combination', () {
    for (final (load, reps) in [(60.0, 6), (20.0, 2)]) {
      final store = suggestionStore();
      addTearDown(store.dispose);
      store.exercises = [store.exercises.single.copyWith(equipment: 'Barbell')];
      store.settings.plateProfile
        ..platesKg = [20]
        ..limitedPairs = true
        ..pairsKg = {20: 1};
      recordBaseline(store, reps, 2, weight: load);
      store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
      final exercise = store.active!.exercises.single;
      expect(exercise.sets.map((s) => s.weight), everyElement(load));
      expect(exercise.sets.map((s) => s.targetReps), everyElement(reps));
      expectSupported(exercise, store.history.single.exercises.single.sets);
      for (final set in exercise.sets) {
        expect(store.plates(set.weight!, name: exercise.name).exact, isNotNull);
      }
    }
  });

  test('protocol anchors keep the same working window and AMRAP uses the weakest completed set', () {
    for (final method in ['AMRAP', 'Drop Set', 'Myo-Reps', 'Rest-Pause', 'Myo-Rep Match']) {
      final activation = method == 'AMRAP' ? 'AMRAP' : 'Activation';
      final followup = switch (method) {
        'AMRAP' => 'AMRAP',
        'Drop Set' => 'Drop Set',
        'Myo-Reps' => 'Myo-set',
        'Rest-Pause' => 'Rest-Pause',
        _ => 'Myo-Rep Match',
      };
      final rec = recommend(
        previous: [
          SetEntry(type: activation, weight: 100, reps: 13, rir: 2, done: true),
          SetEntry(type: followup, weight: method == 'Drop Set' ? 75 : 100, reps: 13, rir: 2, done: true),
        ],
        method: method,
        targetRir: 2,
        unit: 'kg',
        increment: 2.5,
      )!;
      expect((rec.weight, rec.targetReps), (100, 13), reason: method);
    }
    final weaker = SetEntry(type: 'AMRAP', weight: 100, reps: 6, rir: 2, done: true);
    final rec = recommend(
      previous: [
        SetEntry(type: 'AMRAP', weight: 100, reps: 14, rir: 2, done: true),
        weaker,
      ],
      method: 'AMRAP',
      targetRir: 2,
      unit: 'kg',
      increment: 2.5,
    )!;
    expect(rec.weight, 92.5);
    expect(setOneRm(rec.weight, rec.setRepTargets.last, rec.targetRir)!, lessThanOrEqualTo(weaker.e1rm! + 1e-6));
    final incomplete = recommend(
      previous: [
        SetEntry(type: 'AMRAP', weight: 100, reps: 14, rir: 2, done: true),
        SetEntry(type: 'AMRAP'),
      ],
      method: 'AMRAP',
      targetRir: 2,
      unit: 'kg',
      increment: 2.5,
    )!;
    expect(incomplete.applyWeight, isFalse);
  });

  test('unit conversions keep evidence exact and suggestions achievable without changing history', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 9, 2, weight: 220, unit: 'lb');
    final original = jsonEncode(store.history.single.toJson());
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    final exercise = store.active!.exercises.single;
    expect(exercise.sets.map((s) => s.weight), everyElement(97.5));
    expect(exercise.sets.map((s) => s.targetReps), everyElement(9));
    expect(jsonEncode(store.history.single.toJson()), original);
  });

  test('calibration uses matching external-load history and leaves manually entered later results intact', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 9, 2);
    final valid = store.history.single;
    final wrong = Session.fromJson({...valid.toJson(), 'id': 'wrong'})..startedAt = DateTime(2026, 1, 2);
    for (final set in wrong.exercises.single.sets) {
      set
        ..weight = 300
        ..context = const SetContext(setup: 'different machine');
    }
    store.history = [wrong, valid];
    store.saveCycle(Mesocycle(id: 'cycle', start: DateTime(2026, 1, 3), startRir: 2, endRir: 2));
    store.startSession(store.templates.single, at: DateTime(2026, 1, 3));
    final exercise = store.active!.exercises.single;
    expect(store.calibrationFor('Press', 'Straight', store.active!)!.weight, 100);
    exercise.sets[1]
      ..weight = 80
      ..reps = 11
      ..rir = 2;
    store.applyCalibration(exercise, 0, 100, 9, 2);
    expect((exercise.sets[1].weight, exercise.sets[1].reps, exercise.sets[1].rir), (80, 11, 2));
    expect((exercise.sets[2].hintWeight, exercise.sets[2].targetReps), (100, 9));
  });

  test('first-day calibration does not borrow capacity from a stronger working-set position', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 9, 2);
    store.history.single.exercises.single.sets.last.rir = 4;
    store.saveCycle(Mesocycle(id: 'cycle', start: DateTime(2026, 1, 2), startRir: 3, endRir: 3));
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    final calibration = store.calibrationFor('Press', 'Straight', store.active!)!;
    expect((calibration.weight, calibration.targetReps, calibration.targetRir), (100, 8, 3));
  });

  test('unknown effort, manual progression and changed contexts do not invent prescriptions', () {
    final store = suggestionStore();
    addTearDown(store.dispose);
    recordBaseline(store, 6, null);
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    expect(store.active!.exercises.single.sets.map((s) => s.weight), everyElement(100));
    expect(store.active!.exercises.single.sets.map((s) => s.targetRir), everyElement(isNull));
    store.discardSession();
    store.exercises = [store.exercises.single.copyWith(autoProgression: false)];
    recordBaseline(store, 6, 2);
    store.startSession(store.templates.single, at: DateTime(2026, 1, 2));
    expect(store.active!.exercises.single.sets.map((s) => s.prescribed), everyElement(isFalse));
    expect(store.active!.exercises.single.sets.map((s) => s.targetReps), everyElement(isNull));
  });
}
