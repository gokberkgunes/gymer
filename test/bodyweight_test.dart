import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/bodyweight.dart';
import 'package:gymer/models.dart';
import 'package:gymer/screens/settings.dart';
import 'package:gymer/store.dart';
import 'package:gymer/theme.dart';
import 'package:gymer/widgets/common.dart';

AppStore bodyweightStore() => AppStore()
  ..exercises = [
    Exercise(name: 'Pull-up', loadMode: 'bodyweight'),
    Exercise(name: 'Assisted pull-up', loadMode: 'assisted'),
  ]
  ..templates = [
    WorkoutTemplate(
      id: 'pull',
      name: 'Pull',
      exercises: [
        TemplateExercise(name: 'Pull-up', sets: [TemplateSet(weight: 0, reps: 8)]),
      ],
    ),
  ];

void main() {
  test('opt-in bodyweight log survives backups and units while finished snapshots stay fixed', () async {
    final store = bodyweightStore();
    addTearDown(store.dispose);
    final day = dateOnly(DateTime.now());
    expect(Settings.fromJson({}).trackBodyweight, isFalse);
    expect(store.logBodyweight(day, 80), isNotNull);
    store.startSession(store.templates.single);
    expect(store.active!.bodyweight, isNull);
    store.updateSettings((s) => s.trackBodyweight = true);
    expect(store.logBodyweight(addDays(day, -7), 81), isNull);
    expect(store.logBodyweight(day, 80), isNull);
    expect(store.logBodyweight(day, 79.5), isNull);
    expect(store.bodyweights, hasLength(2));
    expect(store.active!.bodyweight, 79.5);
    expect(store.bodyweightAt(addDays(day, -8), 'kg'), isNull, reason: 'never borrow a future measurement');
    expect(store.logBodyweight(addDays(day, 1), 80), isNotNull);
    expect(store.logBodyweight(day, double.nan), isNotNull);
    expect(store.logBodyweight(day, 0), isNotNull);
    final set = store.active!.exercises.single.sets.single;
    set
      ..weight = 10
      ..reps = 8
      ..done = true;
    store.finishSession();
    store.logBodyweight(day, 78);
    expect(store.history.single.bodyweight, 79.5);
    expect(store.progress('Pull-up').single.value, 89.5);

    final restored = AppStore();
    addTearDown(restored.dispose);
    await restored.importJson(jsonEncode(store.toJson()));
    expect(restored.bodyweights.map((e) => e.kg), [81, 78]);
    expect(restored.history.single.bodyweight, 79.5);
    store.updateSettings((s) => s.unit = 'lb');
    expect(store.bodyweights.last.kg, 78, reason: 'measurements never round-trip through display units');
    expect(store.history.single.bodyweight, closeTo(175.27, 0.01));
    store.updateSettings((s) => s.unit = 'kg');
    expect(store.bodyweights.last.kg, 78);
    expect(store.history.single.bodyweight, closeTo(79.5, 0.01));
    store.updateSettings((s) => s.trackBodyweight = false);
    expect(store.progress('Pull-up'), isEmpty);
    expect(store.bodyweightAt(day, 'kg'), isNull);
    expect(store.bodyweights, hasLength(2));
    store.startSession(store.templates.single);
    expect(store.active!.bodyweight, isNull);
    store.discardSession();

    final before = jsonEncode(restored.toJson());
    final damaged = restored.toJson()
      ..['bodyweights'] = [
        {'date': dateKey(day), 'kg': -1},
      ];
    await expectLater(restored.importJson(jsonEncode(damaged)), throwsFormatException);
    expect(jsonEncode(restored.toJson()), before);
  });

  test('trend respects calendar gaps; combined loads exclude unknown and ambiguous measurements', () {
    final points = bodyweightTrend([
      BodyweightEntry(DateTime(2026, 10, 8), 78),
      BodyweightEntry(DateTime(2026, 10, 1), 80),
    ], 'kg');
    expect(points.last.trend, closeTo(80 + (1 - math.exp(-1)) * -2, 0.0001));
    final session = Session(
      id: 's',
      templateId: null,
      name: 'Pull',
      unit: 'kg',
      startedAt: DateTime.now(),
      bodyweight: 80,
      exercises: [],
    );
    final added = SessionExercise(name: 'Pull-up', loadMode: 'bodyweight', sets: []);
    final assisted = SessionExercise(name: 'Assisted pull-up', loadMode: 'assisted', sets: []);
    final set = SetEntry(weight: 20, reps: 8, done: true);
    expect(combinedBodyweightLoad(session, added, set), 100);
    expect(combinedBodyweightLoad(session, assisted, set), 60);
    set.context = const SetContext(loadBasis: 'per_side');
    expect(combinedBodyweightLoad(session, added, set), isNull);
    set.context = const SetContext();
    set.type = 'Warm-up';
    expect(combinedBodyweightLoad(session, added, set), isNull);
    set.type = 'Normal';
    session.bodyweight = null;
    expect(combinedBodyweightLoad(session, added, set), isNull);
    expect(set.weight, 20, reason: 'combined load never changes the entered load');
  });

  testWidgets('bodyweight log is revealed only after enabling its setting', (tester) async {
    final store = bodyweightStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, store.settings),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    expect(find.text('Bodyweight log'), findsNothing);
    await tester.tap(find.text('Workout'));
    await tester.pumpAndSettle();
    expect(find.text('Bodyweight log'), findsNothing);
    final row = find.ancestor(of: find.text('Track bodyweight'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(store.settings.trackBodyweight, isTrue);
    await tester.tap(find.text('Bodyweight log'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log bodyweight'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '80');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.bodyweights.single.kg, 80);
    expect(find.text('7-day trend'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
