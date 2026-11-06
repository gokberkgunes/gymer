import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/circuits.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

WorkoutTemplate circuitTemplate() => WorkoutTemplate(
  id: 'pair',
  name: 'Push and pull',
  exercises: [
    for (final name in ['Bench', 'Row'])
      TemplateExercise(name: name, sets: [for (var i = 0; i < 2; i++) TemplateSet(weight: 40, reps: 8, rest: 180)]),
  ],
  circuits: [
    ExerciseCircuit(id: 'a', exercises: ['Bench', 'Row'], rest: 90),
  ],
);

void main() {
  test('alternating sets share one rest per round, respect order and undo safely', () {
    final store = AppStore();
    addTearDown(store.dispose);
    final template = circuitTemplate();
    store.templates = [template];
    store.settings.requirePreviousSet = true;
    store.startSession(template);
    final session = store.active!;
    final bench = session.exercises[0], row = session.exercises[1];
    expect(store.toggleSet(row, 0).ok, isFalse);
    expect(store.toggleSet(bench, 0).ok, isTrue);
    expect(store.rest, isNull);
    expect(nextCircuitStep(session, bench)?.exercise, row);
    expect(store.toggleSet(bench, 1).ok, isFalse);
    expect(store.toggleSet(row, 0).ok, isTrue);
    expect(store.rest?.totalSeconds, 90);
    expect(store.rest?.exercise, 'Row');
    store.toggleSet(bench, 0); // Undo an earlier member, not the timer's owner.
    expect(store.rest, isNull);
    expect(store.setOrderViolation(), isNotNull);
    store.toggleSet(bench, 0);
    expect(store.rest?.totalSeconds, 90);
    store.toggleSet(bench, 1);
    expect(store.rest, isNull);
    store.toggleSet(row, 1);
    expect(store.rest, isNull);
    expect(session.doneSets, 4);
    expect(session.volume, 1280);
    expect(template.exercises.first.sets.first.rest, 180);
  });

  test('circuits retain protocol groups, handle unequal rounds, and keep warm-ups separate', () {
    final drops = SessionExercise(
      name: 'Drops',
      method: 'Drop Set',
      sets: [
        SetEntry(type: 'Warm-up', rest: 60),
        SetEntry(type: 'Activation', rest: 15),
        SetEntry(type: 'Drop Set', rest: 15),
        SetEntry(type: 'Activation', groupStart: true, rest: 15),
        SetEntry(type: 'Drop Set'),
      ],
    );
    final rows = SessionExercise(name: 'Row', sets: [SetEntry()]);
    final curls = SessionExercise(name: 'Curl', sets: [SetEntry(), SetEntry(), SetEntry()]);
    final circuit = ExerciseCircuit(id: 'a', exercises: ['Drops', 'Row', 'Curl'], rest: 90);
    final steps = workoutSteps([drops, rows, curls], [circuit]);
    expect(steps.map((step) => (step.exercise.name, step.index)), [
      ('Drops', 0),
      ('Drops', 1),
      ('Drops', 2),
      ('Row', 0),
      ('Curl', 0),
      ('Drops', 3),
      ('Drops', 4),
      ('Curl', 1),
      ('Curl', 2),
    ]);
    expect(steps.map((step) => step.restAfter), [60, 15, 0, 0, 90, 15, 0, 90, 0]);
    expect(steps.first.circuit, isNull);
    final working = workoutSteps([drops, rows, curls], [circuit], hideWarmups: true);
    expect(working, hasLength(8));
    expect(working.any((step) => step.set.warmup), isFalse);
  });

  test('grouping survives resume, history, replacement and saving next workout without shared state', () async {
    final store = AppStore(), restored = AppStore();
    addTearDown(store.dispose);
    addTearDown(restored.dispose);
    final template = circuitTemplate();
    store.templates = [template];
    store.startSession(template);
    store.toggleSet(store.active!.exercises.first, 0);
    await restored.importJson(jsonEncode(store.toJson()));
    expect(nextCircuitStep(restored.active!, restored.active!.exercises.first)?.exercise.name, 'Row');
    expect(restored.active!.circuits.single.rest, 90);
    expect(restored.rest, isNull);
    final row = restored.active!.exercises.last;
    expect(restored.substituteExercise(row, 'Cable row'), isNull);
    expect(restored.active!.circuits.single.exercises, ['Bench', 'Cable row']);
    row.sets.first
      ..weight = 40
      ..reps = 8;
    expect(restored.toggleSet(row, 0).ok, isTrue);
    restored.active!.circuits.single.rest = 75;
    expect(restored.rest?.totalSeconds, 90);
    expect(sessionSteps(restored.active!).firstWhere((step) => step.set == row.sets.first).restAfter, 90);
    expect(restored.templates.single.circuits.single.rest, 90);
    expect(restored.templateChanged(), isTrue);
    restored.finishSession(saveStructure: true);
    expect(restored.history.single.circuits.single.exercises, ['Bench', 'Cable row']);
    expect(restored.history.single.exercises.last.sets.first.circuitRestAfter, 90);
    expect(restored.templates.single.circuits.single.rest, 75);
    restored.startSession(restored.templates.single);
    restored.active!.circuits.single.rest = 60;
    expect(restored.history.single.circuits.single.rest, 75);
    expect(restored.templates.single.circuits.single.rest, 75);
    final timing = store.templateTiming(template);
    expect(timing.rest, 90);
    expect(timing.transitions, 0);
  });
}
