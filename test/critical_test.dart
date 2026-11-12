import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/circuits.dart';
import 'package:gymer/logic/plates.dart';
import 'package:gymer/logic/warmup.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

void main() {
  test('imports preserve recoverable unfinished work and abort when the safety backup fails', () async {
    final directory = await Directory.systemTemp.createTemp('gymer-recovery-');
    final file = File('${directory.path}/gymer.json');
    final store = AppStore(file: file);
    addTearDown(() async {
      await store.flush();
      store.dispose();
      await directory.delete(recursive: true);
    });
    await store.load();
    store.startSession(store.templates.first);
    await store.flush();
    store.active!.exercises.first.sets.first.weight = 42.5; // Not yet saved to disk.
    final before = jsonDecode(jsonEncode(store.toJson()));
    final replacement = jsonEncode({...store.toJson(), 'templates': <Object>[], 'active': null});
    await store.importJson(replacement);
    final backups = Directory('${directory.path}/backups');
    final recovery = (await backups.list().where((entry) => entry is File).toList()).single as File;
    expect(jsonDecode(await recovery.readAsString()), before);
    await store.restoreSnapshot(recovery);
    expect(store.toJson(), before);

    await store.flush();
    final saved = await file.readAsString();
    await backups.rename('${directory.path}/saved-backups');
    await File(backups.path).writeAsString('Blocks backup creation');
    await expectLater(store.importJson(replacement), throwsA(isA<FileSystemException>()));
    expect(store.toJson(), before);
    expect(await file.readAsString(), saved);
  });

  test('plate plans use only available pairs and offer achievable nearest loads', () {
    final inventory = {20.0: 1, 15.0: 2};
    final exact = planPlates(80, 20, [20, 15], pairs: inventory);
    expect(exact.exact!.perSide, [15, 15]); // Taking the heaviest plate first would fail.
    final unavailable = planPlates(100, 20, [20, 15], pairs: inventory);
    expect(unavailable.exact, isNull); // There is only one pair of 20s.
    expect((unavailable.below!.total, unavailable.above!.total), (90, 120));
    // Heavy loads stay cheap to plan, and ties prefer the heavier plate.
    expect(planPlates(310, 20, [20, 10, 5, 2.5, 1.25]).exact!.perSide, [...List.filled(7, 20.0), 5.0]);
  });

  test('one damaged bodyweight entry or plate profile never makes a backup unreadable', () async {
    final store = AppStore();
    addTearDown(store.dispose);
    final data = store.toJson();
    final settings = {
      ...data['settings'] as Map<String, dynamic>,
      'plateProfiles': [
        {'id': 'bad', 'name': 'Broken', 'platesKg': ['x']},
        {'id': 'gym', 'name': 'Gym'},
      ],
      'selectedPlateProfile': 'gym',
    };
    await store.importJson(
      jsonEncode({
        ...data,
        'settings': settings,
        'bodyweights': [
          {'date': '2026-01-01', 'kg': -5},
          {'date': '2026-01-02', 'kg': 80},
        ],
      }),
    );
    expect(store.bodyweights.map((e) => e.kg), [80]);
    expect(store.settings.plateProfiles.map((p) => p.id), ['gym']);
  });

  test('resumed warm-ups never change working loads, volume or the next workout', () async {
    expect(warmupRamp(100).map((s) => (s.weight, s.reps)), [(40, 8), (60, 5), (80, 3)]);
    expect(warmupRamp(100, sets: 2).map((s) => s.weight), [40, 80]);
    expect(warmupRamp(25, bar: 20, plates: [20, 10, 5, 2.5, 1.25]).map((s) => s.weight), [20]);
    expect(warmupRamp(10, increment: 5).map((s) => s.weight), [5]);
    final store = AppStore(), resumed = AppStore();
    addTearDown(store.dispose);
    addTearDown(resumed.dispose);
    store.exercises = [const Exercise(name: 'Bench', equipment: 'Barbell')];
    store.templates = [
      WorkoutTemplate(
        id: 'bench',
        name: 'Bench day',
        exercises: [
          TemplateExercise(name: 'Bench', sets: [TemplateSet(weight: 100, reps: 8), TemplateSet(weight: 100, reps: 8)]),
        ],
      ),
    ];
    final plan = jsonDecode(jsonEncode(store.templates.single.toJson()));
    store.startSession(store.templates.single);
    store.settings.updateFollowingDefaults = true;
    expect(store.startWarmups(), isNull);
    final ramp = store.active!.activeWarmup!;
    expect(ramp.sets.map((s) => s.weight), [40, 60, 80]);
    ramp.sets[1]
      ..weight = null
      ..reps = null;
    expect(store.toggleSet(store.active!.activeWarmup!, 0).ok, isTrue);
    expect((ramp.sets[1].hintWeight, ramp.sets[1].hintReps), (60, 5));
    await resumed.importJson(jsonEncode(store.toJson()));
    expect(resumed.active!.activeWarmup!.sets.first.done, isTrue);
    expect(resumed.rest!.warmup, isTrue);
    expect(resumed.toggleSet(resumed.active!.activeWarmup!, 1).ok, isTrue);
    expect(resumed.active!.activeWarmup!.sets[1].weight, 60);
    expect(resumed.toggleSet(resumed.active!.activeWarmup!, 2).ok, isTrue);
    expect(resumed.active!.warmingUp, isFalse);
    expect(resumed.active!.doneSets, 0);
    final working = resumed.active!.exercises.single;
    expect(resumed.toggleSet(working, 0).ok, isTrue);
    expect(resumed.rest!.warmup, isFalse);
    expect(resumed.toggleSet(working, 1).ok, isTrue);
    final summary = resumed.finishSession()!;
    expect((summary.sets, summary.volume), (2, 1600));
    expect(resumed.templates.single.toJson(), plan);
    resumed.startSession(resumed.templates.single);
    expect(resumed.active!.exercises.single.sets.map((s) => s.hintWeight), [100, 100]);
    resumed.startSession(
      WorkoutTemplate(
        id: 'other',
        name: 'Other workout',
        exercises: [
          TemplateExercise(name: 'Bench', sets: [TemplateSet(reps: 8)]),
        ],
      ),
    );
    expect(resumed.startWarmups(), isNull); // Reuse the working load from the other workout.
    expect(resumed.active!.activeWarmup!.sets.map((s) => s.weight), [40, 60, 80]);
    expect(resumed.active!.exercises.single.sets.single.weight, isNull);
    final manual = SessionExercise(
      name: 'Manual exercise',
      sets: [
        SetEntry(type: 'Warm-up', weight: 20, reps: 8),
        SetEntry(),
      ],
    );
    expect(resumed.fallbackValue(manual, 1, 'weight'), isNull);
  });

  test('supersets enforce round order and retain shared rest correctly through undo and edits', () {
    final store = AppStore();
    addTearDown(store.dispose);
    final template = WorkoutTemplate(
      id: 'pair',
      name: 'Push and pull',
      exercises: [
        for (final name in ['Bench', 'Row'])
          TemplateExercise(name: name, sets: [TemplateSet(weight: 40, reps: 8), TemplateSet(weight: 40, reps: 8)]),
      ],
      circuits: [
        ExerciseCircuit(id: 'a', exercises: ['Bench', 'Row'], rest: 90),
      ],
    );
    store.templates = [template];
    store.settings.requirePreviousSet = true;
    store.startSession(template);
    final session = store.active!;
    expect(session.estimatedSeconds, store.templateTiming(template).total, reason: 'shared rests count only once');
    final bench = session.exercises.first, row = session.exercises.last;
    expect(store.toggleSet(row, 0).ok, isFalse);
    expect(store.toggleSet(bench, 0).ok, isTrue);
    expect(store.rest, isNull);
    expect(store.toggleSet(bench, 1).ok, isFalse);
    expect(store.toggleSet(row, 0).ok, isTrue);
    expect(store.rest!.totalSeconds, 90);
    store.toggleSet(bench, 0); // Undoing either member must cancel the round's timer.
    expect(store.rest, isNull);
    expect(store.toggleSet(bench, 0).ok, isTrue);
    session.circuits.single.rest = 60;
    expect(sessionSteps(session).firstWhere((step) => step.set == row.sets.first).restAfter, 90);
    expect(template.circuits.single.rest, 90);
    expect(store.toggleSet(bench, 1).ok, isTrue);
    expect(store.rest, isNull);
    expect(store.toggleSet(row, 1).ok, isTrue);
    expect(store.rest, isNull);
    expect((session.doneSets, session.volume), (4, 1280));
  });

  test('historical records ignore future workouts and compare loads in the recorded unit', () {
    final store = AppStore();
    addTearDown(store.dispose);
    Session workout(String id, int day, double weight, String unit) => Session(
      id: id,
      templateId: 'upper',
      name: 'Upper',
      unit: unit,
      startedAt: DateTime(2026, 10, day),
      finishedAt: DateTime(2026, 10, day, 1),
      exercises: [
        SessionExercise(
          name: 'Bench',
          sets: [SetEntry(weight: weight, reps: 8, done: true)],
        ),
      ],
    );
    final first = workout('first', 1, 100, 'kg');
    final target = workout('target', 8, 240, 'lb');
    store.history = [workout('later', 15, 200, 'kg'), target, first];
    final before = jsonEncode(store.toJson());
    final summary = store.summarizeSession(target);
    expect(summary.bests.firstWhere((b) => b.kind == 'weight').value, '240 lb × 8');
    expect(
      summary.exercises.single.change,
      closeTo(estimatedOneRm(240, 8, 0)! - estimatedOneRm(220.462262185, 8, 0)!, 0.001),
    );
    expect(store.summarizeSession(first).bests, isEmpty);
    expect(jsonEncode(store.toJson()), before);
  });
}
