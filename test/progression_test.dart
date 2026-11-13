// Working loads stay stable in the 7–13 rep / 0–4 RIR window.
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/progression.dart';
import 'package:gymer/models.dart';

List<SetEntry> sets(List<(double, int, int)> v, [String type = 'Normal']) => [
  for (final (w, r, rir) in v) SetEntry(weight: w, reps: r, rir: rir, done: true, type: type),
];

Recommendation rec(List<SetEntry> s, {double inc = 5}) =>
    recommend(previous: s, method: 'Straight', targetRir: 2, unit: 'kg', increment: inc)!;

void main() {
  test('straight progression preserves the load in the working window and fits reps to effort', () {
    final up = rec(sets([(100, 12, 2), (100, 12, 2), (100, 12, 3)]));
    expect(
      [up.action, up.weight, up.setRepTargets],
      [
        'hold',
        100.0,
        [12, 12, 13],
      ],
    );

    final build = rec(sets([(100, 9, 2), (100, 8, 2), (100, 8, 3)]));
    expect(
      [build.action, build.weight, build.setRepTargets],
      [
        'hold',
        100.0,
        [9, 8, 9],
      ],
    );

    final effort = rec(sets([(100, 10, 0), (100, 9, 1), (100, 9, 2)]));
    expect(
      [effort.action, effort.setRepTargets],
      [
        'hold',
        [8, 8, 9],
      ],
    );

    final down = rec(sets([(100, 6, 1), (100, 6, 1), (100, 5, 1)]), inc: 2.5);
    expect((down.action, down.weight), ('decrease', 90.0));
  });

  test('light loads stay stable too; reps alone decide without RIR using the same working window', () {
    // Reaching 12 reps does not force a 25% jump from 20 to 25 kg.
    final light = rec(sets([(20, 12, 2), (20, 12, 2)]));
    expect(
      [light.action, light.weight, light.setRepTargets],
      [
        'hold',
        20.0,
        [12, 12],
      ],
    );
    Recommendation repsOnly(List<(double, int)> v) => recommend(
      previous: [for (final (w, r) in v) SetEntry(weight: w, reps: r, done: true)],
      method: 'Straight',
      targetRir: 2,
      unit: 'kg',
      increment: 5,
      rirTracked: false,
    )!;
    expect((repsOnly([(100, 12), (100, 12)]).action, repsOnly([(100, 12), (100, 12)]).weight), ('hold', 100.0));
    expect((repsOnly([(100, 14), (100, 14)]).action, repsOnly([(100, 14), (100, 14)]).weight), ('increase', 105.0));
    expect(repsOnly([(100, 10), (100, 9)]).setRepTargets, [10, 9]);
    expect(repsOnly([(100, 7), (100, 9)]).weight, 100.0);
    expect(repsOnly([(100, 6), (100, 9)]).weight, 95.0);
    // With RIR tracked, a blank RIR still holds.
    final blank = recommend(
      previous: [SetEntry(weight: 100, reps: 12, done: true)],
      method: 'Straight',
      targetRir: 2,
      unit: 'kg',
      increment: 5,
    )!;
    expect(blank.action, 'hold');
  });

  test('drop set progresses unless a recorded observation contradicts the protocol', () {
    const ctx = SetContext(setup: 'stack');
    List<SetEntry> drop({bool evidence = true}) => [
      SetEntry(
        weight: 100,
        reps: 14,
        rir: 2,
        done: true,
        type: 'Activation',
        context: ctx,
        rest: 10,
        actualRest: evidence ? 10 : null,
        stopReason: 'target_rir',
      ),
      SetEntry(weight: 75, reps: 6, done: true, type: 'Drop Set', context: ctx, rest: 10, actualRest: 10),
      SetEntry(weight: 55, reps: 5, done: true, type: 'Drop Set', context: ctx, rest: 10),
    ];
    Recommendation run(List<SetEntry> rows) =>
        recommend(previous: rows, method: 'Drop Set', targetRir: 2, unit: 'kg', increment: 2.5)!;

    // Unknown actual rest is accepted; a recorded rest that differs from the plan holds the load.
    expect(run(drop(evidence: false)).action, 'increase');
    final differs = drop();
    differs[0].actualRest = 30;
    expect(run(differs).action, 'hold');
    final r = run(drop());
    expect(r.action, 'increase');
    expect(r.weight, greaterThan(100));
    final drops = [weightForSet(r, 'Drop Set', 1)!, weightForSet(r, 'Drop Set', 2)!];
    expect(drops[0], lessThan(r.weight));
    expect(drops[1], lessThan(drops[0]));

    // An extended exercise range still holds 14 reps inside 12–20.
    final wide = recommend(
      previous: drop(),
      method: 'Drop Set',
      targetRir: 2,
      unit: 'kg',
      increment: 2.5,
      repMin: 12,
      repMax: 20,
    )!;
    expect((wide.action, wide.weight, wide.targetReps), ('hold', 100, 14));
  });

  test('deload weights round down, set counts round to nearest, at least one set', () {
    expect(recoveryWeight(102.5, 90, 2.5), 90);
    expect(
      (recoveryCount('Straight', 3, 50), recoveryCount('Straight', 5, 50), recoveryCount('Myo-Reps', 4, 50)),
      (2, 3, 1),
    );
  });

  test('Wathan e1RM counts reps in reserve', () {
    expect(estimatedOneRm(100, 8, 2), closeTo(134.7467, 1e-3));
  });
}
