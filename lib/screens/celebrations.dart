import 'package:flutter/material.dart';

import '../widgets/celebration.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import '../widgets/record_effect.dart';
import '../logic/numbers.dart';

/// Preview the set confetti and every workout celebration style.
class CelebrationsPreview extends StatefulWidget {
  const CelebrationsPreview({super.key});

  @override
  State<CelebrationsPreview> createState() => _CelebrationsPreviewState();
}

class _CelebrationsPreviewState extends State<CelebrationsPreview> {
  int _set = 0, _workout = 0;
  int? _style;
  bool _record = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Celebration styles')),
    body: Stack(
      children: [
        ListView(
          padding: subPageInsets,
          children: [
            SectionLabel(
              'Personal best · preview',
              trailing: IconButton(
                tooltip: _record ? 'Stop personal-best preview' : 'Preview personal-best effect',
                onPressed: () => setState(() => _record = !_record),
                icon: Icon(_record ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: RecordEffect(
                active: _record,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Icon(
                            Icons.emoji_events_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Expanded(
                          flex: 10,
                          child: NumField(
                            value: 105,
                            kind: NumKind.weight,
                            completed: true,
                            align: TextAlign.center,
                            onChanged: (_) {},
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 7,
                          child: NumField(
                            value: 8,
                            kind: NumKind.reps,
                            completed: true,
                            align: TextAlign.center,
                            onChanged: (_) {},
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 7,
                          child: NumField(
                            value: 2,
                            kind: NumKind.rir,
                            completed: true,
                            align: TextAlign.center,
                            onChanged: (_) {},
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Icon(Icons.check_rounded, size: 24, color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SectionLabel('Set and workout'),
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
