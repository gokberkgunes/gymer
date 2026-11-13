import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/methods.dart';
import 'package:gymer/logic/numbers.dart';
import 'package:gymer/logic/plates.dart';
import 'package:gymer/logic/snapshots.dart';
import 'package:gymer/widgets/common.dart';

void main() {
  test('numeric entry: arithmetic, ranges, snapping and warnings', () {
    expect(evaluateExpression('45+45'), 90);
    expect(evaluateExpression('100*0.9'), 90);
    expect(evaluateExpression('2*(20+2.5)'), 45);
    expect(evaluateExpression('1/0'), isNull);
    expect(evaluateExpression('abc'), isNull);
    expect(
      (numberAllowed(2.5, NumKind.reps), numberAllowed(0, NumKind.weight), numberAllowed(0, NumKind.load)),
      (false, false, true),
    );
    expect(formatNumber(99.99, NumKind.weight), '100');
    expect(unusualReason(NumKind.reps, 30), isNotNull);
    expect(unusualReason(NumKind.weight, 200, usualWeight: 100), isNotNull);
    expect(unusualReason(NumKind.weight, 110, usualWeight: 100), isNull);
    expect(parseRest('1:30'), 90);
    expect(() => parseRest('1:75'), throwsFormatException);
  });

  test('method rules match the Flet app', () {
    expect(
      reconcileMethodSets('Myo-Reps', [('Warm-up', false), ('Normal', false), ('Normal', false), ('Normal', true)]),
      [('Warm-up', false), ('Activation', false), ('Myo-set', false), ('Activation', true)],
    );
    expect(setTypeChoices('Straight', [('Warm-up', false), ('Normal', false)], 1), [
      'Normal',
      'Warm-up',
      'Top Set',
      'Back-off',
    ]);
    expect(setTypeChoices('Straight', [('Normal', false), ('Normal', false)], 1), ['Normal', 'Top Set', 'Back-off']);
    expect(setTypeChoices('Drop Set', [('Activation', false), ('Drop Set', false)], 1), ['Drop Set']);
    expect((methodSetUsesRir('Cluster', 'Cluster Set'), methodSetUsesRir('Myo-Reps', 'Myo-set')), (false, false));
    // New exercises start with a rep range that suits their type.
    (int, int) range(String equipment, List<String> primary, [List<String> secondary = const []]) =>
        defaultRepRange(equipment: equipment, primary: primary, secondary: secondary);
    expect(range('Barbell', ['Chest'], ['Triceps']), (5, 8));
    expect(range('Dumbbell', ['Chest'], ['Triceps']), (8, 12));
    expect(range('Barbell', ['Biceps']), (10, 20)); // an isolation, whatever the implement
    expect(range('Plate loaded', ['Calves'], ['Quads']), (10, 20));
    expect(range('', []), (8, 12));
  });

  test('fuzzy search, with a leading space for exact text', () {
    const names = ['Bench Press', 'Leg Press', 'Lateral Raise'];
    expect(filterNames(names, 'lp').first, 'Leg Press');
    expect(filterNames(names, ' press'), ['Leg Press', 'Bench Press']);
    expect(filterNames(names, ' lp'), isEmpty);
  });

  test('automatic backups thin out like ZFS: 3 newest, 3 days, 4 weeks, 6 months', () {
    // Wed 4 Nov 2026 has two copies; before that, one a day at noon for over a year.
    final stamps = [
      DateTime(2026, 11, 4, 18),
      DateTime(2026, 11, 4, 10),
      for (var i = 1; i < 400; i++) DateTime(2026, 11, 4 - i, 12),
    ];
    String d(DateTime t) => '${t.month}/${t.day}${t.hour == 12 ? '' : ' ${t.hour}h'}';
    final kept = snapshotsToKeep(stamps).toList()..sort((a, b) => b.compareTo(a));
    expect(kept.map(d), [
      '11/4 18h', '11/4 10h', '11/3', '11/2', // newest copies and days
      '11/1', '10/31', '10/25', '10/18', // weeks, and October's last day
      '9/30', '8/31', '7/31', '6/30', // months
    ]);
    final name = snapshotName(DateTime(2026, 1, 2, 3, 4, 5));
    expect(name, 'gymer-20260102-030405.json');
    expect(snapshotTime(name), DateTime(2026, 1, 2, 3, 4, 5));
    expect(snapshotTime('gymer.json'), isNull);
  });

  test('plate calculator: fewest plates, heavier first, nearest loads when inexact', () {
    expect(planPlates(100, 20, defaultPlatesKg).exact!.perSide, [20, 20]);
    expect(planPlates(100, 20, [25, 20, 15, 10]).exact!.perSide, [25, 15]);
    expect(
      [
        for (final w in <double>[25, 20, 15, 10, 5, 2.5, 1.25]) plateColorClass(w, 'kg'),
      ],
      ['red', 'blue', 'yellow', 'green', 'white', 'red', 'chrome'],
    );
    expect(plateColorClass(45, 'lb'), 'blue');
    expect(planPlates(225, 45, defaultPlatesLb).exact!.perSide, [45, 45]);
    expect(planPlates(20, 20, defaultPlatesKg).exact!.perSide, isEmpty);
    final odd = planPlates(101, 20, defaultPlatesKg);
    expect(odd.exact, isNull);
    expect([odd.below!.total, odd.above!.total], [100, 102.5]);
    final light = planPlates(15, 20, defaultPlatesKg);
    expect([light.below, light.above!.total], [null, 20]);
    // Greedy would stop at 20 per side; 15 + 15 makes 30 exactly.
    expect(planPlates(80, 20, [20, 15]).exact!.perSide, [15, 15]);
  });
}
