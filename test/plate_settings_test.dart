import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/screens/plates.dart';
import 'package:gymer/screens/settings.dart';
import 'package:gymer/store.dart';
import 'package:gymer/theme.dart';
import 'package:gymer/widgets/common.dart';

void main() {
  testWidgets('create a location, edit pairs and switch inventories from the calculator', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore();
    await store.load();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, store.settings),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(plateSettingsRoute()),
                    child: const Text('Plate settings'),
                  ),
                  TextButton(
                    onPressed: () => showPlates(context, 140, onUse: (_) {}),
                    child: const Text('Calculator'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Plate settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage plate profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Home');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(store.settings.plateProfile.name, 'Home');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 ×1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.settings.platePairs![20], 2);
    expect(find.text('20 ×2'), findsOneWidget);
    store.updateSettings((settings) => settings.platesKg = [20]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculator'));
    await tester.pumpAndSettle();
    expect(find.text('Use 100 kg'), findsOneWidget);
    await tester.tap(find.byTooltip('Plate profile'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem<String> && widget.value == 'gym'),
    );
    await tester.pumpAndSettle();
    expect(store.settings.plateProfile.name, 'Gym');
    expect(find.text('140 kg'), findsOneWidget);
    expect(find.text('Use 100 kg'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.flush();
    store.dispose();
  });
}
