import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/models.dart';
import 'package:gymer/services/workout_share.dart';
import 'package:gymer/store.dart';
import 'package:gymer/theme.dart';

FinishSummary sharedSummary({int exercises = 5}) => FinishSummary(
  name: 'Upper · Strength',
  unit: 'kg',
  date: DateTime(2026, 11, 6),
  duration: const Duration(minutes: 53),
  sets: exercises * 3,
  volume: 12460,
  report: AppStore().sessionVolume(
    Session(id: 's', templateId: null, name: '', unit: 'kg', startedAt: DateTime(2026), exercises: []),
  ),
  bests: const [PersonalBest('Bench Press', 'weight', '105 kg × 8', '+5 kg')],
  exercises: [
    for (var i = 0; i < exercises; i++)
      ExerciseResult(i == 0 ? 'Bench Press' : 'Exercise ${i + 1}', 3, '100 kg × 8', i == 0 ? 5 : null),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('share renders a real PNG and hands it directly to the Android share channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<dynamic, dynamic>? sent;
    messenger.setMockMethodCallHandler(WorkoutSharing.channel, (call) async {
      expect(call.method, 'image');
      sent = call.arguments as Map<dynamic, dynamic>;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(WorkoutSharing.channel, null));
    await WorkoutSharing.share(sharedSummary(), buildTheme(Brightness.dark, Settings()));
    expect(sent!.keys.toSet(), {'title', 'png'});
    expect(sent!['title'], 'Upper · Strength');
    final bytes = sent!['png'] as Uint8List;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, greaterThan(1000));
    frame.image.dispose();
    codec.dispose();
  });

  test('long workout images grow past the viewport and stay within texture limits', () async {
    final image = await renderWorkoutImage(sharedSummary(exercises: 90), buildTheme(Brightness.light, Settings()));
    final codec = await ui.instantiateImageCodec(image);
    final frame = await codec.getNextFrame();
    expect(frame.image.height, 8192);
    expect(frame.image.width, greaterThan(300));
    expect(frame.image.width, lessThan(1080));
    frame.image.dispose();
    codec.dispose();
  });
}
