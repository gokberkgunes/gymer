// Suggested reps stay within the configured range at the next RIR target.
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
        [12, 12, 12],
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

    // Per-set progression: different loads across sets are expected, and each set follows the rules alone.
    final mixed = sets([(102.5, 8, 2), (100, 10, 2), (100, 9, 2)]);
    expect(rec(mixed).applyWeight, isFalse); // together: working loads differ, so no automatic load
    final own = recommend(previous: mixed, method: 'Straight', targetRir: 2, unit: 'kg', increment: 2.5, perSet: true)!;
    expect(own.applyWeight, isTrue);
    expect(own.setWeights, [102.5, 100.0, 100.0]);
    expect(own.setRepTargets, [8, 10, 9]);
    expect([for (var i = 0; i < 3; i++) weightForSet(own, 'Normal', i)], [102.5, 100.0, 100.0]);
    final first = recommend(
      previous: sets([(100, 15, 2), (100, 9, 2)]),
      method: 'Straight',
      targetRir: 2,
      unit: 'kg',
      increment: 2.5,
      perSet: true,
    )!;
    expect((first.action, first.setWeights.first > 100, first.setWeights.last), ('increase', true, 100.0));
    // A missed set still blocks progression in this mode.
    final missed = [
      ...sets([(100, 10, 2)]),
      SetEntry(weight: 100),
    ];
    expect(
      recommend(previous: missed, method: 'Straight', targetRir: 2, unit: 'kg', perSet: true)!.setWeights,
      isEmpty,
    );
    // Fit the next effort target before deciding to keep the weight, including both former grace edges.
    for (final reps in [7, 8, 12, 13]) {
      for (final actualRir in [0, 4]) {
        for (final targetRir in [0, 4]) {
          final result = recommend(
            previous: sets([(100, reps, actualRir)]),
            method: 'Straight',
            targetRir: targetRir,
            unit: 'kg',
          )!;
          if (result.applyWeight) {
            expect(result.setRepTargets, everyElement(inInclusiveRange(8, 12)));
            expect(
              setOneRm(result.weight, result.targetReps, targetRir)!,
              lessThanOrEqualTo(setOneRm(100, reps, actualRir)! + 1e-6),
              reason: '$reps reps @ $actualRir → $targetRir RIR',
            );
          } else {
            expect(result.setRepTargets, isEmpty);
            expect(result.reason, contains('manually'));
          }
        }
      }
    }
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
    expect(light.reason, contains('goes up once every set reaches'));
    // A 1.25 kg step on a 5 kg raise is 25 %: the range widens, and the load moves exactly one step once every
    // set has out-repped that jump, instead of never (the 10 % limit) or at the top of the normal range.
    final earn = repsToEarnStep(5, 6.25, 8, 2);
    expect(earn, inInclusiveRange(15, 22));
    final building = rec(sets([(5, earn - 1, 2), (5, earn - 1, 2)]), inc: 1.25);
    expect((building.action, building.weight), ('hold', 5.0));
    final earned = rec(sets([(5, earn, 2), (5, earn, 2)]), inc: 1.25);
    expect((earned.action, earned.weight, earned.setRepTargets.every((reps) => reps >= 8)), ('increase', 6.25, true));
    Recommendation lightRepsOnly(int reps) => recommend(
      previous: [for (var i = 0; i < 2; i++) SetEntry(weight: 5, reps: reps, done: true)],
      method: 'Straight',
      targetRir: null,
      unit: 'kg',
      increment: 1.25,
      rirTracked: false,
    )!;
    final lightEarn = repsToEarnStep(5, 6.25, 8, 0);
    expect(
      (lightRepsOnly(14).action, lightRepsOnly(lightEarn - 1).action, lightRepsOnly(lightEarn).action),
      ('hold', 'hold', 'increase'),
    );
    Recommendation repsOnly(List<(double, int)> v) => recommend(
      previous: [for (final (w, r) in v) SetEntry(weight: w, reps: r, done: true)],
      method: 'Straight',
      targetRir: 2,
      unit: 'kg',
      increment: 5,
      rirTracked: false,
    )!;
    expect((repsOnly([(100, 12), (100, 12)]).action, repsOnly([(100, 12), (100, 12)]).weight), ('increase', 105.0));
    expect((repsOnly([(100, 14), (100, 14)]).action, repsOnly([(100, 14), (100, 14)]).weight), ('increase', 105.0));
    expect(repsOnly([(100, 10), (100, 9)]).setRepTargets, [10, 9]);
    expect(repsOnly([(100, 7), (100, 9)]).weight, 95.0);
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

  test('protocol progression respects quality gates and effort targets', () {
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

    for (final (method, anchor, continuation, reps) in [
      ('AMRAP', 'AMRAP', 'AMRAP', 12),
      ('Drop Set', 'Activation', 'Drop Set', 3),
      ('Myo-Reps', 'Activation', 'Myo-set', 3),
      ('Rest-Pause', 'Activation', 'Rest-Pause', 3),
      ('Myo-Rep Match', 'Activation', 'Myo-Rep Match', 12),
    ]) {
      final result = recommend(
        previous: [
          SetEntry(type: anchor, weight: 100, reps: 12, rir: 2, done: true),
          SetEntry(type: continuation, weight: method == 'Drop Set' ? 75 : 100, reps: reps, rir: 2, done: true),
        ],
        method: method,
        targetRir: 2,
        unit: 'kg',
        increment: 2.5,
      )!;
      expect((result.weight, result.targetReps), (100, 12), reason: method);
    }
    Recommendation amrap(List<SetEntry> rows) =>
        recommend(previous: rows, method: 'AMRAP', targetRir: 2, unit: 'kg', increment: 2.5)!;
    final rows = sets([(100, 14, 2), (100, 6, 2)], 'AMRAP');
    expect((amrap(rows).weight, amrap(rows).setRepTargets.last), (92.5, 8));
    rows[1] = SetEntry(type: 'AMRAP');
    expect(amrap(rows).applyWeight, isFalse);
  });

  test('deload weights round down, set counts round to nearest, at least one set', () {
    expect(recoveryWeight(102.5, 90, 2.5), 90);
    expect(
      (recoveryCount('Straight', 3, 50), recoveryCount('Straight', 5, 50), recoveryCount('Myo-Reps', 4, 50)),
      (2, 3, 1),
    );
  });

  test('Wathan estimates count reserve reps and fit rounded load targets', () {
    expect(estimatedOneRm(100, 8, 2), closeTo(134.7467, 1e-3));
    // Reps/RIR, increment and rep minimum → rounded load and attainable goal.
    for (final (reps, rir, step, minimum, load, goal) in [
      (6, 2, 2.5, 8, 92.5, 8), // Uses the estimate, not a single-increment reduction.
      (2, 2, 2.5, 14, 90.0, null), // A capped reduction cannot support the range: decline automatic targets.
      (2, 2, 25.0, 14, 100.0, null), // No available increment fits the 10% limit.
      (14, 2, 2.5, 8, 110.0, 9), // Increase only outside the working window.
      (6, 8, 2.5, 8, 100.0, 8), // An inflated RIR counts as at most four.
    ]) {
      final source = SetEntry(weight: 100, reps: reps, rir: rir, done: true);
      final result = recommend(
        previous: [source],
        method: 'Straight',
        targetRir: 2,
        unit: 'kg',
        increment: step,
        repMin: minimum,
        repMax: minimum == 14 ? 18 : 12,
      )!;
      expect(
        (result.weight, result.applyWeight ? result.targetReps : null),
        (load, goal),
        reason: '$reps reps @ $rir, step $step, minimum $minimum',
      );
      if (result.applyWeight) {
        expect(setOneRm(result.weight, result.targetReps, result.targetRir)!, lessThanOrEqualTo(source.e1rm! + 1e-6));
      } else {
        expect(result.setRepTargets, isEmpty);
      }
    }
  });
}
