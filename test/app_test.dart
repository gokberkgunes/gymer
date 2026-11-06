import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/main.dart';
import 'package:gymer/store.dart';
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
}
