import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/plates.dart';
import 'package:gymer/models.dart';
import 'package:gymer/store.dart';

void main() {
  test('unlimited plates retain minimum-plate plans and nearest loads', () {
    expect(planPlates(100, 20, defaultPlatesKg).exact!.perSide, [20, 20]);
    expect(planPlates(225, 45, defaultPlatesLb).exact!.perSide, [45, 45]);
    expect(planPlates(80, 20, [20, 15]).exact!.perSide, [15, 15]);
    final odd = planPlates(101, 20, defaultPlatesKg);
    expect((odd.below!.total, odd.above!.total), (100, 102.5));
  });

  test('pair limits never reuse plates and stop at the available inventory', () {
    final limited = planPlates(100, 20, [20, 10, 5], pairs: {20: 1, 10: 1, 5: 1});
    expect(limited.exact, isNull);
    expect(limited.below!.total, 90);
    expect(limited.below!.perSide, [20, 10, 5]);
    expect(limited.above, isNull);
    expect(planPlates(100, 20, [20, 10], pairs: {20: 1, 10: 2}).exact!.perSide, [20, 10, 10]);
    final noPlates = planPlates(50, 20, [20], pairs: {});
    expect(noPlates.below!.total, 20);
    expect(noPlates.above, isNull);
    expect(planPlates(15, 20, [20], pairs: {}).above!.total, 20);
  });

  test('bounded plans find non-greedy combinations and prefer heavier plates on ties', () {
    expect(planPlates(80, 20, [20, 15], pairs: {20: 1, 15: 2}).exact!.perSide, [15, 15]);
    expect(planPlates(32, 0, [9, 8, 7], pairs: {9: 1, 8: 2, 7: 1}).exact!.perSide, [9, 7]);
    final odd = planPlates(67, 20, [20, 2.5], pairs: {20: 1, 2.5: 1});
    expect((odd.below!.total, odd.above), (65, null));
  });

  test('bounded plans match exhaustive inventory combinations', () {
    bool better(List<double> a, List<double> b) {
      if (a.length != b.length) return a.length < b.length;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return a[i] > b[i];
      }
      return false;
    }

    for (var fours = 0; fours <= 2; fours++) {
      for (var threes = 0; threes <= 2; threes++) {
        for (var ones = 0; ones <= 2; ones++) {
          final best = <int, List<double>>{};
          for (var a = 0; a <= fours; a++) {
            for (var b = 0; b <= threes; b++) {
              for (var c = 0; c <= ones; c++) {
                final sum = 4 * a + 3 * b + c;
                final side = [...List.filled(a, 4.0), ...List.filled(b, 3.0), ...List.filled(c, 1.0)];
                if (best[sum] == null || better(side, best[sum]!)) best[sum] = side;
              }
            }
          }
          final reachable = best.keys.toList()..sort();
          for (var goal = 0; goal <= 18; goal++) {
            final plan = planPlates(goal * 2.0, 0, [4, 3, 1], pairs: {4: fours, 3: threes, 1: ones});
            if (best.containsKey(goal)) {
              expect(plan.exact!.perSide, best[goal]);
            } else {
              expect(plan.exact, isNull);
              final below = reachable.where((sum) => sum < goal).lastOrNull;
              final above = reachable.where((sum) => sum > goal).firstOrNull;
              expect(plan.below?.perSide, below == null ? null : best[below]);
              expect(plan.above?.perSide, above == null ? null : best[above]);
            }
          }
        }
      }
    }
  });

  test('old settings migrate to Gym without losing custom bar or plate sizes', () {
    final settings = Settings.fromJson({
      'unit': 'lb',
      'barKg': 15,
      'barLb': 35,
      'platesKg': [17.5, 2.5],
      'platesLb': [45, 5],
    });
    expect(settings.plateProfiles.single.name, 'Gym');
    expect(settings.plateProfile.limitedPairs, isFalse);
    expect(settings.platePairs, isNull);
    expect((settings.barKg, settings.barLb), (15, 35));
    expect(settings.platesKg, [17.5, 2.5]);
    expect(settings.plates, [45, 5]);
    expect(Settings.fromJson({'platesKg': formerPlatesKg}).platesKg, defaultPlatesKg);
  });

  test('profiles keep independent units and counts through backup round trips', () {
    final settings = Settings();
    final home = PlateProfile(
      id: 'home',
      name: 'Home',
      barKg: 15,
      barLb: 35,
      platesKg: formerPlatesKg,
      platesLb: [45, 10],
      limitedPairs: true,
      pairsKg: {20: 2, 2.5: 3},
      pairsLb: {45: 1, 10: 2},
    );
    settings.plateProfiles.add(home);
    settings.selectedPlateProfile = 'home';
    settings.barKg = 10;
    final copy = Settings.fromJson(jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>);
    expect(copy.plateProfile.name, 'Home');
    expect(copy.bar, 10);
    expect(
      copy.platesKg,
      formerPlatesKg,
      reason: 'an intentional profile inventory must not be migrated as old defaults',
    );
    expect(copy.platePairs![20], 2);
    expect(copy.platePairs![10], 1, reason: 'newly enabled sizes default to one pair');
    copy.unit = 'lb';
    expect(copy.bar, 35);
    expect(copy.platePairs, {45.0: 1, 10.0: 2});
    copy.selectedPlateProfile = 'gym';
    expect(copy.bar, defaultBarLb);
    expect(copy.plates, defaultPlatesLb);
    expect(copy.platePairs, isNull);
  });

  test('profile copies do not share inventory and a missing selection falls back safely', () {
    final settings = Settings();
    final copy = PlateProfile.fromJson({...settings.plateProfile.toJson(), 'id': 'home', 'name': 'Home'});
    settings.plateProfiles.add(copy);
    copy.platesKg.remove(20);
    copy.pairsKg[10] = 2;
    expect(settings.platesKg, contains(20));
    expect(settings.plateProfile.pairsKg, isEmpty);
    settings.selectedPlateProfile = 'deleted';
    expect(settings.plateProfile.id, 'gym');
    expect(Settings.fromJson({'plateProfiles': []}).plateProfiles, hasLength(1));
  });

  test('switching profiles updates the store calculator and keeps exercise bar overrides', () async {
    final store = AppStore();
    await store.load();
    store.settings.plateProfiles.add(
      PlateProfile(id: 'home', name: 'Home', barKg: 15, platesKg: [20], limitedPairs: true, pairsKg: {20: 1}),
    );
    expect(store.plates(100).exact, isNotNull);
    store.updateSettings((settings) => settings.selectedPlateProfile = 'home');
    expect(store.plates(100).below!.total, 55);
    expect(store.plates(100).above, isNull);
    store.exercises = [
      const Exercise(name: 'EZ curl', equipment: 'Barbell', barKg: 10),
      const Exercise(name: 'Machine', equipment: 'Plate loaded'),
    ];
    expect(store.plates(50, name: 'EZ curl').exact!.perSide, [20]);
    expect(store.plates(40, name: 'Machine').exact!.perSide, [20]);
    await store.flush();
    store.dispose();
  });
}
