import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/warmup.dart';
import 'package:gymer/main.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

Future<AppStore> rampStore({bool manualWarmup = false}) async {
  final store = AppStore();
  await store.load();
  store.exercises = [const Exercise(name: 'Ramp press', equipment: 'Barbell')];
  store.templates = [
    WorkoutTemplate(
      id: 'ramp',
      name: 'Ramp test',
      exercises: [
        TemplateExercise(
          name: 'Ramp press',
          sets: [
            if (manualWarmup) TemplateSet(type: 'Warm-up', weight: 20, reps: 10),
            for (var i = 0; i < 3; i++) TemplateSet(weight: 100, reps: 8),
          ],
        ),
      ],
    ),
  ];
  return store;
}

void main() {
  test('ramps use two or three steps, loadable plates, bar minimum and inventory limits', () {
    expect(warmupRamp(100, bar: 20, plates: [20, 10, 5]), [
      (weight: 40.0, reps: 8),
      (weight: 60.0, reps: 5),
      (weight: 80.0, reps: 3),
    ]);
    expect(warmupRamp(100, sets: 2, bar: 20, plates: [20, 10, 5]), [(weight: 40.0, reps: 8), (weight: 80.0, reps: 3)]);
    expect(warmupRamp(75, bar: 15, plates: [20, 10], pairs: {20: 1, 10: 1}).map((step) => step.weight), [15, 35, 55]);
    expect(warmupRamp(20, increment: 2.5).map((step) => step.weight), [7.5, 10, 15]);
    expect(warmupRamp(0), isEmpty);
    expect(warmupRamp(15, bar: 20, plates: [20]), isEmpty);
  });

  test('warm-ups hand off to untouched working sets without contaminating history or defaults', () async {
    final store = await rampStore();
    store.startSession(store.templates.single);
    final session = store.active!;
    final working = session.exercises.single;
    final before = jsonEncode(working.toJson());
    expect(store.startWarmups(), isNull);
    expect(session.visibleExercises, session.warmupExercises);
    expect(working.sets, hasLength(3));
    final warmup = session.warmupExercises.single;
    expect(warmup.sets, hasLength(3));
    for (var i = 0; i < warmup.sets.length; i++) {
      expect(store.toggleSet(warmup, i).ok, isTrue);
    }
    expect(session.warmingUp, isFalse);
    expect(session.doneSets, 0);
    expect(jsonEncode(working.toJson()), before);
    expect(store.templateChanged(), isFalse);
    expect(store.rest!.warmup, isTrue);
    for (var i = 0; i < working.sets.length; i++) {
      expect(store.toggleSet(working, i).ok, isTrue);
    }
    final summary = store.finishSession()!;
    expect((summary.sets, summary.volume), (3, 2400));
    expect(store.history.single.warmupExercises.single.sets.every((set) => set.done), isTrue);
    expect(store.templates.single.exercises.single.sets.map((set) => set.weight), everyElement(100));
    store.startSession(store.templates.single);
    expect(store.active!.exercises.single.sets.map((set) => set.hintWeight), everyElement(100));
    expect(store.startWarmups(sets: 2), isNull);
    expect(store.active!.warmupExercises.single.sets, hasLength(2));
    await store.flush();
    store.dispose();
  });

  test('phase, completed warm-ups and their rest timer survive saving and loading', () async {
    final store = await rampStore();
    store.startSession(store.templates.single);
    store.startWarmups();
    store.toggleSet(store.active!.warmupExercises.single, 0);
    final copy = AppStore();
    await copy.importJson(jsonEncode(store.toJson()));
    expect(copy.active!.warmingUp, isTrue);
    expect(copy.active!.warmupExercises.single.sets.map((set) => set.done), [true, false, false]);
    expect(copy.rest!.warmup, isTrue);
    copy.showWorkoutPhase(warmup: false);
    expect(copy.active!.visibleExercises, copy.active!.exercises);
    copy.showWorkoutPhase(warmup: true);
    expect(copy.active!.visibleExercises.single.sets.first.done, isTrue);
    await store.flush();
    await copy.flush();
    store.dispose();
    copy.dispose();
  });

  test('ramp mode supersedes manual warm-up rows without blocking set order or changing the plan', () async {
    final store = await rampStore(manualWarmup: true);
    store.settings.requirePreviousSet = true;
    store.startSession(store.templates.single);
    store.startWarmups();
    store.showWorkoutPhase(warmup: false);
    final session = store.active!;
    final working = session.exercises.single;
    expect(session.visibleSetsFor(working), hasLength(3));
    expect(working.sets.first.warmup, isTrue);
    expect(store.toggleSet(working, 1).ok, isTrue);
    expect(store.setOrderViolation(), isNull);
    expect(store.templateChanged(), isFalse);
    await store.flush();
    store.dispose();
  });

  test('missing working loads do not invent a ramp or mutate the session', () async {
    final store = await rampStore();
    for (final set in store.templates.single.exercises.single.sets) {
      set.weight = null;
    }
    store.startSession(store.templates.single);
    expect(store.startWarmups(), isNotNull);
    expect(store.active!.warmingUp, isFalse);
    expect(store.active!.warmupExercises, isEmpty);
    expect(store.active!.exercises.single.sets, hasLength(3));
    await store.flush();
    store.dispose();
  });

  testWidgets('workout shows only the warm-up rows, then replaces them with working rows', (tester) async {
    final store = await rampStore();
    await tester.pumpWidget(GymerApp(store: store));
    await tester.tap(find.text('Ramp test'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout phase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm-up · 3 sets'));
    await tester.pumpAndSettle();
    expect(store.active!.warmingUp, isTrue);
    expect(find.byType(TextField), findsNWidgets(6));
    for (var i = 1; i <= 3; i++) {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'Ramp press, set W$i, not completed',
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(store.active!.warmingUp, isFalse);
    expect(find.byType(TextField), findsNWidgets(9));
    expect(find.text('0/3 sets'), findsOneWidget);
    expect(store.templateChanged(), isFalse);
    store.discardSession();
    await tester.pumpWidget(const SizedBox());
    await store.flush();
    store.dispose();
  });
}
