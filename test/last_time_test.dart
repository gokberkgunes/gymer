import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

void main() {
  test('planned load markers compare compatible working sets in one unit without changing plans', () {
    final store = AppStore();
    addTearDown(store.dispose);
    final previous = SessionExercise(
      name: 'Bench Press',
      sets: [
        SetEntry(type: 'Warm-up', weight: 40, reps: 8, done: true),
        SetEntry(weight: 220.462262185, reps: 8, done: true),
        SetEntry(weight: 220.462262185, reps: 8, done: true),
      ],
    );
    store.history = [
      Session(
        id: 'old',
        templateId: 'upper',
        name: 'Upper',
        unit: 'lb',
        startedAt: DateTime(2026, 10, 1),
        exercises: [previous],
      ),
    ];
    final current = SessionExercise(name: 'Bench Press', sets: [SetEntry(hintWeight: 105), SetEntry(weight: 100)]);
    store.active = Session(
      id: 'new',
      templateId: 'upper',
      name: 'Upper',
      unit: 'kg',
      startedAt: DateTime(2026, 10, 8),
      exercises: [current],
    );
    final comparison = store.plannedLoadIncrease(current, 0)!;
    expect(comparison.previous, closeTo(100, 0.0001));
    expect(comparison.increase, closeTo(5, 0.0001));
    expect(current.sets.first.weight, isNull);
    expect(current.sets.first.hintWeight, 105);
    expect(store.plannedLoadIncrease(current, 1), isNull, reason: 'conversion noise is not a load increase');
    current.sets.first.done = true;
    expect(store.plannedLoadIncrease(current, 0), isNull);
    current.sets.first.done = false;
    current.sets.first.context = const SetContext(loadBasis: 'per_side');
    expect(store.plannedLoadIncrease(current, 0), isNull);
    current.sets.first.context = const SetContext();
    current.sets.first.type = 'Drop';
    expect(store.plannedLoadIncrease(current, 0), isNull);
    current.sets.first.type = 'Warm-up';
    expect(store.plannedLoadIncrease(current, 0), isNull);
    current.sets.first.type = 'Normal';
    store.active!.phase = 'Deload';
    expect(store.plannedLoadIncrease(current, 0), isNull);
    store.active!.phase = 'Build';
    current.method = 'Cluster';
    expect(store.plannedLoadIncrease(current, 0), isNull);
    current.method = 'Straight';
    current.loadMode = 'assisted';
    expect(store.plannedLoadIncrease(current, 0), isNull);
  });
}
