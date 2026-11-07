import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'tick.dart';
import '../store.dart';

String _mss(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Signed remaining time, e.g. "1:37" or "-0:12" once rest is over.
String signedRest(int remaining) => remaining < 0 ? '-${_mss(-remaining)}' : _mss(remaining);

/// Compact time for the round timer: the countdown, or elapsed time without the total.
String _roundDisplay(RestTimer r) => r.countdown ? signedRest(r.remainingSeconds) : _mss(r.elapsed);

/// The floating rest timer: a small round dial in the bottom-right corner.
/// Tap returns to the workout; hold switches to the countdown view.
class FloatingRestTimer extends StatelessWidget {
  final VoidCallback onTap;
  const FloatingRestTimer({super.key, required this.onTap});

  static const size = 64.0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final r = store.rest;
    if (r == null || !store.settings.floatingTimer || store.active == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Tooltip(
      message: '${r.overdue ? 'Rest complete' : 'Rest'} · ${r.exercise}\nTap to open the workout · hold for countdown',
      child: TickBuilder(
        anchor: r.startedAt,
        builder: (context) {
          final overdue = r.overdue;
          final color = overdue ? cs.error : cs.primary;
          final progress = r.totalSeconds <= 0 ? 1.0 : (r.elapsed / r.totalSeconds).clamp(0.0, 1.0);
          return Material(
            color: cs.surfaceContainerHigh,
            elevation: 3,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              onLongPress: store.showRestCountdown,
              child: SizedBox.square(
                dimension: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                          value: overdue ? 1 : 1 - progress,
                          strokeWidth: 3,
                          color: color,
                          backgroundColor: cs.outlineVariant,
                        ),
                      ),
                    ),
                    Text(
                      _roundDisplay(r),
                      style: t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabular,
                        color: overdue ? color : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
