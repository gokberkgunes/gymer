import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

Session workout(String id, int day, double weight, {String unit = 'kg', String template = 'upper'}) => Session(
  id: id,
  templateId: template,
  name: 'Upper',
  unit: unit,
  startedAt: DateTime(2026, 10, day, 10),
  finishedAt: DateTime(2026, 10, day, 11),
  exercises: [
    SessionExercise(
      name: 'Bench Press',
      sets: [SetEntry(weight: weight, reps: 8, done: true)],
    ),
  ],
);

void main() {
  test('saved summaries compare only earlier history, in the recorded unit, without changing data', () {
    final store = AppStore();
    addTearDown(store.dispose);
    final first = workout('first', 1, 100);
    final target = workout('target', 8, 240, unit: 'lb');
    final later = workout('later', 15, 200);
    target.exercises.first.sets.addAll([
      SetEntry(type: 'Warm-up', weight: 300, reps: 10, done: true),
      SetEntry(weight: 300, reps: 10),
    ]);
    store
      ..history =
          [later, first, target] // Deliberately unsorted, as imported history can be.
      ..active = workout('active', 22, 250);
    final before = jsonEncode(store.toJson());
    final summary = store.summarizeSession(target);
    expect(summary.unit, 'lb');
    expect(summary.date, target.startedAt);
    expect(summary.duration, const Duration(hours: 1));
    expect(summary.sets, 1);
    expect(summary.volume, 1920);
    expect(summary.exercises.single.best, '240 lb × 8');
    final expectedChange = estimatedOneRm(240, 8, 0)! - estimatedOneRm(100 * 2.20462262185, 8, 0)!;
    expect(summary.exercises.single.change, closeTo(expectedChange, 0.001));
    expect(summary.bests.map((b) => b.kind), containsAll(['weight', 'e1rm', 'volume', 'workout']));
    expect(store.summarizeSession(first).bests, isEmpty);
    expect(jsonEncode(store.toJson()), before);

    // The original finish and a later reopening agree, despite newer workouts and display settings.
    store.settings.unit = 'lb';
    final reopened = store.summarizeSession(target);
    expect(reopened.exercises.single.change, summary.exercises.single.change);
    expect(reopened.bests.map((b) => (b.kind, b.value, b.gain)), summary.bests.map((b) => (b.kind, b.value, b.gain)));
  });

  test('last-time comparison prefers the same workout and falls back to another workout', () {
    final store = AppStore();
    addTearDown(store.dispose);
    final same = workout('same', 1, 90);
    final other = workout('other', 6, 95, template: 'push');
    final deload = workout('deload', 7, 60)..phase = 'Deload';
    final target = workout('target', 8, 100);
    store.history = [target, deload, other, same];
    expect(
      store.summarizeSession(target).exercises.single.change,
      closeTo(estimatedOneRm(100, 8, 0)! - estimatedOneRm(90, 8, 0)!, 0.001),
    );
    store.history.remove(same);
    expect(
      store.summarizeSession(target).exercises.single.change,
      closeTo(estimatedOneRm(100, 8, 0)! - estimatedOneRm(95, 8, 0)!, 0.001),
    );
  });
}
