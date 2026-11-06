import 'package:flutter/material.dart';

import '../widgets/celebration.dart';
import '../widgets/common.dart';

/// Preview the set confetti and every workout celebration style.
class CelebrationsPreview extends StatefulWidget {
  const CelebrationsPreview({super.key});

  @override
  State<CelebrationsPreview> createState() => _CelebrationsPreviewState();
}

class _CelebrationsPreviewState extends State<CelebrationsPreview> {
  int _set = 0, _workout = 0;
  int? _style;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Celebration styles')),
    body: Stack(
      children: [
        ListView(
          padding: subPageInsets,
          children: [
            FilledButton(onPressed: () => setState(() => _set++), child: const Text('Preview set celebration')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _style = null;
                _workout++;
              }),
              child: const Text('Preview random workout celebration'),
            ),
            const SectionLabel('Workout styles'),
            for (final (i, (message, emojis, _)) in workoutStyles.indexed)
              ListTile(
                title: Text(message),
                subtitle: Text(emojis),
                onTap: () => setState(() {
                  _style = i;
                  _workout++;
                }),
              ),
          ],
        ),
        Positioned.fill(child: SetConfetti(trigger: _set)),
        if (_workout > 0)
          Positioned.fill(
            child: WorkoutCelebration(style: _style, trigger: _workout),
          ),
      ],
    ),
  );
}
