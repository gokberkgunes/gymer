part of '../template_editor.dart';

/// Workout Time Approximator: tune the estimate to your normal pace.
class TimeApproximator extends StatefulWidget {
  final WorkoutTemplate template;
  const TimeApproximator({super.key, required this.template});

  @override
  State<TimeApproximator> createState() => _TimeApproximatorState();
}

class _TimeApproximatorState extends State<TimeApproximator> {
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final w = widget.template;
    final b = store.templateTiming(w);
    final target = formatTargetDuration(b.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Time Approximator')),
      body: ListView(
        padding: subPageInsets,
        children: [
          Text('Target ~$target', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Use this estimate to check whether the workout fits the time you actually have. If your real sessions '
            'consistently run longer or shorter, adjust the values below until the estimate matches your normal pace.',
          ),
          const SizedBox(height: 16),
          NumField(
            value: w.setSeconds.toDouble(),
            kind: NumKind.count,
            placeholder: 'Default entry duration (seconds)',
            suffix: 's',
            dense: false,
            onChanged: (v) => setState(() => w.setSeconds = v?.round() ?? 45),
          ),
          const SizedBox(height: 4),
          Text('Default entry duration (seconds)', style: t.bodySmall),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.setOverhead,
            label: 'Setup / logging per entry',
            onChanged: (v) => setState(() => w.setOverhead = v),
          ),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.transition,
            label: 'Between exercises',
            onChanged: (v) => setState(() => w.transition = v),
          ),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.sessionOverhead,
            label: 'Session overhead',
            onChanged: (v) => setState(() => w.sessionOverhead = v),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tune it to your routine', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Each programmed row contributes to timing, including warmups and protocol fragments. Tune Entry '
                    'duration to your routine. If changing plates or logging takes time, increase Setup / logging.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Use Between exercises for walking, waiting for equipment, and setting up the next station. Session '
                    'overhead covers everything else that regularly adds a few minutes.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Keep your programmed Rest values realistic. The goal is not to make the estimate smaller; it is to '
                    'make it resemble your actual sessions.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lifting ${compactMinutes(b.lifting)} · setup/logging ${compactMinutes(b.setup)} · programmed rest '
                    '${compactMinutes(b.rest)} · exercise changes ${compactMinutes(b.transitions)} · session overhead '
                    '${compactMinutes(b.session)} = ${compactMinutes(b.total)}. The displayed target rounds up to the next 5 minutes.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'After a few real workouts, adjust these values once and leave them alone. The estimate becomes most useful '
            'when it reflects your normal pace.',
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}
