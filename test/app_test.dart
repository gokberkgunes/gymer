import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/main.dart';
import 'package:gymer/store.dart';
import 'package:gymer/widgets/num_field.dart';
import 'package:gymer/widgets/rest_timer.dart';

void main() {
  testWidgets('tap a workout, Enter through a set, see the rest timer', (tester) async {
    final store = AppStore();
    await store.load();
    await tester.pumpWidget(GymerApp(store: store));

    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();
    expect(find.text('Leg Press'), findsOneWidget);

    // Weight → Enter → reps → Enter → RIR → Enter completes the set.
    await tester.enterText(find.byType(TextField).at(0), '100+20');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '2');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump(const Duration(milliseconds: 300));

    final set = store.active!.exercises.first.sets.first;
    expect((set.weight, set.reps, set.rir, set.done), (120, 10, 2, true));
    expect(store.rest?.exercise, 'Leg Press');
    // The floating round timer shows the elapsed rest time.
    expect(find.byType(FloatingRestTimer), findsOneWidget);

    store.discardSession();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a typed rest time is reported without leaving the field', (tester) async {
    // On Android a tap on Save does not blur the field, so a value reported only on blur was lost.
    var rest = 180;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DurationField(seconds: rest, onChanged: (v) => rest = v),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '90');
    expect(rest, 90);
  });

  testWidgets('a set is not completed from a number the user replaced with unusable text', (tester) async {
    final store = AppStore();
    await store.load();
    await tester.pumpWidget(GymerApp(store: store));
    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.enterText(find.byType(TextField).at(0), '100+');
    await tester.pump();
    final exercise = store.active!.exercises.first;
    expect(store.toggleSet(exercise, 0).ok, isFalse);
    expect(exercise.sets.first.done, isFalse);
    expect(exercise.sets.first.invalid, {'weight'});
    await tester.pump();
    expect(find.text('100+'), findsOneWidget, reason: 'the typed text stays visible so the mistake can be fixed');
    await tester.enterText(find.byType(TextField).at(0), '100+5');
    expect(store.toggleSet(exercise, 0).ok, isTrue);
    expect(exercise.sets.first.weight, 105);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
