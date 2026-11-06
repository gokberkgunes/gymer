import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/cycle.dart';
import 'package:gymer/models.dart';
import 'package:gymer/screens/cycle.dart';
import 'package:gymer/screens/cycle_summary.dart';
import 'package:gymer/store.dart';
import 'package:gymer/theme.dart';
import 'package:gymer/widgets/common.dart';

Session trained(
  String id,
  int day,
  double weight, {
  String? cycle = 'old',
  String phase = 'Build',
  String unit = 'kg',
  SetContext context = const SetContext(),
}) => Session(
  id: id,
  templateId: 'upper',
  name: 'Upper',
  unit: unit,
  cycleId: cycle,
  phase: phase,
  startedAt: DateTime(2026, 10, day, 10),
  finishedAt: DateTime(2026, 10, day, 11),
  exercises: [
    SessionExercise(
      name: 'Bench Press',
      sets: [SetEntry(weight: weight, reps: 8, rir: 3, done: true, context: context)],
    ),
  ],
);

AppStore setup() {
  final store = AppStore();
  store.exercises = [
    Exercise(name: 'Bench Press', equipment: 'Barbell'),
    Exercise(name: 'Biceps Curl', equipment: 'Dumbbell'),
    Exercise(name: 'Pull-up', loadMode: 'bodyweight'),
  ];
  store.templates = [
    WorkoutTemplate(
      id: 'upper',
      name: 'Upper',
      exercises: [
        TemplateExercise(name: 'Bench Press', sets: [TemplateSet(weight: 80)]),
        TemplateExercise(name: 'Biceps Curl', sets: [TemplateSet(weight: 12.5)]),
        TemplateExercise(name: 'Pull-up', sets: [TemplateSet(weight: 0)]),
      ],
    ),
  ];
  store.cycles = [
    Mesocycle(
      id: 'old',
      name: 'Strength',
      start: DateTime(2026, 10, 1),
      length: 3,
      deloadMicro: 1,
      active: false,
      schedule: {1: 'upper', 3: 'upper'},
      weekRir: {1: 3, 2: 2, 3: 4},
    ),
  ];
  store.history = [trained('deload', 15, 60, phase: 'Deload'), trained('last', 8, 100), trained('first', 1, 90)];
  return store;
}

void main() {
  test('cloning copies settings, rounds independent starting loads, and seeds only the first workout', () {
    final store = setup();
    addTearDown(store.dispose);
    final source = store.cycles.single;
    source.schedule[5] = 'deleted';
    source.events['2026-10-01'] = DayEvent(templateId: 'upper', sessionId: 'first');
    source.endedAt = DateTime(2026, 10, 21);
    final before = jsonEncode(store.toJson());
    final draft = store.cloneCycle(source, loadPercent: 95);
    expect(jsonEncode(store.toJson()), before, reason: 'opening and canceling a draft must leave stored data intact');
    expect(draft.id, isNot(source.id));
    expect(draft.name, 'Strength · 2');
    expect(draft.schedule, {1: 'upper', 3: 'upper'});
    expect(draft.weekRir, source.weekRir);
    expect((draft.active, draft.setupComplete, draft.endedAt), (false, false, null));
    expect(draft.events, isEmpty);
    final loads = draft.startingLoads['upper']!;
    expect(loads.map((e) => e.name), ['Bench Press', 'Biceps Curl']);
    expect(loads.first.sets.single.weight, 95);
    expect(loads.last.sets.single.weight, 10);
    final restored = Mesocycle.fromJson(draft.toJson());
    restored.weekRir[1] = 1;
    restored.startingLoads['upper']!.first.sets.single.weight = 50;
    expect(draft.weekRir[1], 3);
    expect(source.weekRir[1], 3);
    expect(loads.first.sets.single.weight, 95);

    // Inventory limits and the bar minimum are respected rather than using an unloadable total.
    store.settings.platesKg = [20];
    store.settings.plateProfile.pairsKg = {20: 1};
    store.settings.plateProfile.limitedPairs = true;
    expect(store.cloneCycle(source, loadPercent: 95).startingLoads['upper']!.first.sets.single.weight, 60);
    expect(store.cloneCycle(source, loadPercent: 10).startingLoads['upper']!.first.sets.single.weight, 20);
    store.settings.platesKg = [20, 10, 5, 2.5, 1.25];
    store.settings.plateProfile.limitedPairs = false;

    draft.setupComplete = true;
    store.saveCycle(draft);
    final plan = store.templates.single;
    store.startSession(plan);
    final bench = store.active!.exercises.first;
    expect(bench.sets.single.hintWeight, 95);
    expect(bench.calibrate, isTrue);
    expect(store.calibrationFor('Bench Press', 'Straight', store.active!)!.weight, 95);
    expect(
      plan.exercises.first.sets.single.weight,
      80,
      reason: 'previewing a starting load must not rewrite the template',
    );
    store.applyCalibration(bench, 0, 95, 8, 3);
    bench.sets.single.done = true;
    store.finishSession();
    store.startSession(plan);
    expect(
      store.active!.exercises.first.calibrate,
      isFalse,
      reason: 'normal progression resumes after the first workout',
    );
    store.discardSession();

    // Saved seeds retain their own unit and convert correctly after changing display units.
    final another = Mesocycle.fromJson(draft.toJson()..['id'] = 'another');
    store.saveCycle(another);
    store.updateSettings((s) => s.unit = 'lb');
    store.startSession(plan);
    expect(store.calibrationFor('Bench Press', 'Straight', store.active!)!.weight, closeTo(209.44, 0.01));
    store.discardSession();
  });

  test('cycle review counts moved and extra workouts correctly and compares matching build sets', () {
    final store = setup();
    addTearDown(store.dispose);
    final cycle = store.cycles.single;
    final first = trained('first', 1, 100);
    final moved = trained('moved', 4, 110, cycle: null);
    final last = trained('last', 8, 120);
    final changed = trained('changed', 10, 500, context: const SetContext(loadBasis: 'per_side'));
    final deload = trained('deload', 15, 60, phase: 'Deload');
    final extra = trained('extra', 5, 0)
      ..exercises = [
        SessionExercise(name: 'Pull-up', loadMode: 'bodyweight', sets: [SetEntry(weight: 0, reps: 10, done: true)]),
      ];
    cycle.events['2026-10-03'] = DayEvent(templateId: 'upper', movedTo: DateTime(2026, 10, 4), sessionId: moved.id);
    cycle.events['2026-10-05'] = DayEvent(templateId: 'upper', status: 'unplanned', sessionId: extra.id);
    store.history = [trained('future', 25, 1000, cycle: 'other'), deload, changed, last, extra, moved, first];
    final before = jsonEncode(store.toJson());
    final summary = store.summarizeCycle(cycle, at: DateTime(2026, 11, 1));
    expect((summary.workouts, summary.attended, summary.scheduled, summary.sets), (6, 5, 6, 6));
    expect(summary.duration, const Duration(hours: 6));
    expect(summary.strength.single.name, 'Bench Press');
    expect(summary.strength.single.first, closeTo(estimatedOneRm(100, 8, 0)!, 0.001));
    expect(summary.strength.single.last, closeTo(estimatedOneRm(120, 8, 0)!, 0.001));
    expect(summary.records, greaterThan(0));
    expect(summary.bests.any((b) => b.exercise == 'Bench Press' && b.kind == 'weight'), isTrue);
    expect(jsonEncode(store.toJson()), before);
    cycle.endedAt = DateTime(2026, 10, 10);
    final early = store.summarizeCycle(cycle, at: DateTime(2026, 11, 1));
    expect(early.end, DateTime(2026, 10, 10));
    expect(early.scheduled, 4, reason: 'ending early must not count future scheduled days as missed');
  });

  testWidgets('review opens a prefilled next cycle, cancellation is harmless and Start activates it', (tester) async {
    final store = setup();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, store.settings),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openCycleSummary(context, store.cycles.single),
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start next cycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start next cycle'));
    await tester.pumpAndSettle();
    expect(find.byType(CycleEditor), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Next mesocycle'), findsOneWidget);
    expect(store.cycles, hasLength(1));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(store.cycles, hasLength(1));
    await tester.ensureVisible(find.text('Start next cycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start next cycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    expect(store.cycles, hasLength(2));
    expect(store.activeCycle!.name, 'Strength · 2');
    expect(store.activeCycle!.schedule, {1: 'upper', 3: 'upper'});
    expect(store.activeCycle!.events, isEmpty);
    expect(cycleStatus(store.activeCycle!).phase, 'Build');
    expect(find.text('Review'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
