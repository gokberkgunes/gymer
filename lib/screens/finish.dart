import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/numbers.dart';
import '../logic/volume.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/achievement.dart';
import '../widgets/common.dart';
import '../widgets/workout_share_button.dart';
import 'achievements.dart';

/// Shown after saving a workout: three headline numbers, any personal bests, how each exercise went against
/// last time, and the muscle breakdown folded away. Plus the workout celebration.
class FinishScreen extends StatelessWidget {
  final FinishSummary summary;
  final bool historical;
  final VoidCallback? onEdit;
  const FinishScreen({super.key, required this.summary, this.historical = false, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = summary;
    final settings = StoreScope.of(context).settings;
    final motion = !MediaQuery.disableAnimationsOf(context);
    final milestone = !historical && s.achievements.isNotEmpty && settings.achievementCelebration != 'off';
    final pbExercises = {for (final b in s.bests) b.exercise};
    // The score is tallied once, right after a workout; reopened summaries are shown at rest.
    final tally = !historical && motion && settings.workoutCelebrations;
    String volume(double v) => '${groupThousands(v)} ${s.unit}';

    return Scaffold(
      appBar: historical
          ? AppBar(
              title: const Text('Workout summary'),
              actions: [
                WorkoutShareButton(summary: s),
                if (onEdit != null)
                  IconButton(tooltip: 'Edit workout', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
              ],
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: historical ? subPageInsets : const EdgeInsets.fromLTRB(16, 24, 16, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            historical ? s.name : 'Workout complete',
                            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            historical ? fmtShortDate(s.date) : s.name,
                            style: t.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (!historical) WorkoutShareButton(summary: s),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        s.duration.inMinutes.toDouble(),
                        (v) => _duration(Duration(minutes: v.round())),
                        'Time',
                        order: 0,
                        animate: tally,
                        haptics: settings.haptics,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Stat(
                        s.sets.toDouble(),
                        (v) => '${v.round()}',
                        s.sets == 1 ? 'Set' : 'Sets',
                        order: 1,
                        animate: tally,
                        haptics: settings.haptics,
                      ),
                    ),
                    if (s.volume > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(s.volume, volume, 'Volume', order: 2, animate: tally, haptics: settings.haptics),
                      ),
                    ],
                  ],
                ),
                if (s.bests.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Slam(animate: tally, haptics: settings.haptics, child: PersonalBestCard(s.bests)),
                ],
                if (milestone) ...[
                  const SizedBox(height: 16),
                  AchievementUnlockCard(
                    achievements: s.achievements,
                    unit: settings.unit,
                    animate: settings.achievementCelebration == 'glow',
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AchievementsScreen())),
                  ),
                ],
                if (s.exercises.isNotEmpty) ...[
                  SectionLabel(
                    'Exercises',
                    trailing: Text('vs last time', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, e) in s.exercises.indexed) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          _ExerciseRow(e, unit: s.unit, record: pbExercises.contains(e.name)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _Muscles(s.report),
                if (!historical && settings.coachCheckIn && s.sessionId != null && s.report.direct.isNotEmpty)
                  _CheckInCard(sessionId: s.sessionId!, muscles: s.report.direct.keys.toList()),
                if (!historical) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ],
              ],
            ),
          ),
          if (!historical &&
              motion &&
              (settings.workoutCelebrations || (milestone && settings.achievementCelebration == 'confetti')))
            Positioned.fill(
              child: WorkoutCelebration(
                headline: milestone && settings.achievementCelebration == 'confetti' ? 'Achievement unlocked' : null,
              ),
            ),
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
  }
}

/// The optional recovery check-in: two taps per trained muscle and two for the day. Answers are saved as they
/// are tapped and read by the Coach tab; nothing is required and unanswered rows stay empty.
class _CheckInCard extends StatelessWidget {
  final String sessionId;
  final List<String> muscles;
  const _CheckInCard({required this.sessionId, required this.muscles});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final answers = store.history.where((s) => s.id == sessionId).firstOrNull?.checkIn;
    Widget choice(String label, List<String> options, int? value, void Function(CheckIn, int?) set) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              segments: [for (final (i, o) in options.indexed) ButtonSegment(value: i, label: Text(o))],
              selected: {?value},
              onSelectionChanged: (v) => store.editCheckIn(sessionId, (c) => set(c, v.firstOrNull)),
            ),
          ),
        ],
      ),
    );
    void put(Map<String, int> map, String key, int? value) => value == null ? map.remove(key) : map[key] = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'Check-in',
          trailing: InfoDot(
            tooltip: 'What the check-in is for',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Recovery check-in'),
                content: const Text(
                  'Optional. Pump is how the muscle felt today. Recovered is how it felt coming into this workout '
                  'from the last time you trained it. The Coach tab uses the answers: still sore counts as fatigue, '
                  'a low pump with early recovery earns an added set sooner, and poor sleep or a poor day holds '
                  'additions back. Turn the check-in off in Settings → Advanced.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
              ),
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in muscles) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(m, style: t.titleSmall),
                  ),
                  choice('Pump', const ['Low', 'Good', 'Great'], answers?.pump[m], (c, v) => put(c.pump, m, v)),
                  choice(
                    'Recovered',
                    const ['Still sore', 'In time', 'Days ago'],
                    answers?.recovered[m],
                    (c, v) => put(c.recovered, m, v),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Today', style: t.titleSmall),
                ),
                choice('Sleep', const ['Poor', 'Normal', 'Good'], answers?.sleep, (c, v) => c.sleep = v),
                choice('Overall', const ['Run down', 'Normal', 'Strong'], answers?.overall, (c, v) => c.overall = v),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One headline number with a small uppercase label beneath. After a workout the number counts up in
/// turn with its neighbours and pops when it lands, like a score being tallied. The final text is laid out
/// invisibly underneath, so nothing moves while the digits change.
class _Stat extends StatefulWidget {
  final double value;
  final String Function(double) format;
  final String label;
  final int order;
  final bool animate;
  final bool haptics;
  const _Stat(this.value, this.format, this.label, {this.order = 0, this.animate = false, this.haptics = true});

  @override
  State<_Stat> createState() => _StatState();
}

class _StatState extends State<_Stat> with SingleTickerProviderStateMixin {
  static const _step = 300, _count = 800, _pop = 450;
  late final int _total = _step * widget.order + _count + _pop;
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _total),
  );
  late final _counting = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _step * widget.order / _total,
      (_step * widget.order + _count) / _total,
      curve: Curves.easeOutCubic,
    ),
  );
  late final double _popStart = (_step * widget.order + _count) / _total;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.addListener(() {
        if (!_landed && _controller.value >= _popStart) {
          _landed = true;
          if (widget.haptics) HapticFeedback.selectionClick();
        }
      });
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final style = t.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: st.br),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final settled = _controller.value >= 1;
                final p = ((_controller.value - _popStart) / (1 - _popStart)).clamp(0.0, 1.0);
                final scale = 1 + 0.18 * math.sin(p * math.pi);
                final color = Color.lerp(cs.primary, cs.onSurface, Curves.easeOut.transform(p));
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Opacity(opacity: 0, child: Text(widget.format(widget.value), maxLines: 1, style: style)),
                    Transform.scale(
                      scale: scale,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.format(widget.value * _counting.value),
                        maxLines: 1,
                        style: style?.copyWith(color: settled ? null : color),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(widget.label.toUpperCase(), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The multiplier moment: personal bests slam in after the tally with a small overshoot and a shake.
/// The card keeps its place in the layout the whole time; only opacity and scale change.
class _Slam extends StatefulWidget {
  final bool animate;
  final bool haptics;
  final Widget child;
  const _Slam({required this.animate, required this.haptics, required this.child});

  @override
  State<_Slam> createState() => _SlamState();
}

class _SlamState extends State<_Slam> with SingleTickerProviderStateMixin {
  static const _delay = 1600, _run = 700;
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _delay + _run),
  );
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.addListener(() {
        if (!_landed && _controller.value >= _delay / (_delay + _run)) {
          _landed = true;
          if (widget.haptics) HapticFeedback.heavyImpact();
        }
      });
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final p = ((_controller.value * (_delay + _run) - _delay) / _run).clamp(0.0, 1.0);
      if (p >= 1) return child!;
      return Opacity(
        opacity: Curves.easeOut.transform((p * 5).clamp(0.0, 1.0)),
        child: Transform.rotate(
          angle: math.sin(p * math.pi * 7) * 0.015 * (1 - p),
          child: Transform.scale(scale: 1.22 - 0.22 * Curves.easeOutBack.transform(p), child: child),
        ),
      );
    },
  );
}

/// Personal bests: a monochrome trophy in the accent colour heads the card, and each record is a row with
/// the exercise and kind on the left and the new value, accent-coloured, on the right.
class PersonalBestCard extends StatelessWidget {
  final List<PersonalBest> bests;
  final String? title;
  const PersonalBestCard(this.bests, {super.key, this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final accent = cs.primary;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: st.br,
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: st.brSmall),
                child: Icon(Icons.emoji_events_outlined, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title ?? (bests.length == 1 ? 'New personal best' : '${bests.length} personal bests'),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final b in bests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.kind == 'workout' ? b.label : b.exercise,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          b.kind == 'workout' ? b.exercise : b.label,
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        b.value,
                        style: t.bodyLarge?.copyWith(color: accent, fontWeight: FontWeight.w700, fontFeatures: tabular),
                      ),
                      Text(
                        b.gain,
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An exercise's sets and best set, a small accent trophy if it set a record, and its change in estimated
/// 1RM since last time (accent when up, muted when down, hidden when unchanged).
class _ExerciseRow extends StatelessWidget {
  final ExerciseResult e;
  final String unit;
  final bool record;
  const _ExerciseRow(this.e, {required this.unit, required this.record});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final change = e.change;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (record) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.emoji_events_outlined, size: 16, color: cs.primary),
                    ],
                  ],
                ),
                Text(
                  [plural(e.sets, 'set'), ?e.best].join(' · '),
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          if (change != null && change.abs() >= 0.5)
            Tooltip(
              message: 'Estimated 1RM compared with last time',
              child: Text(
                '${change > 0 ? '+' : '−'}${formatNumber((change.abs() * 2).round() / 2, NumKind.weight)} $unit',
                style: t.bodyMedium?.copyWith(
                  color: change > 0 ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The muscle breakdown, collapsed by default.
class _Muscles extends StatelessWidget {
  final VolumeReport report;
  const _Muscles(this.report);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = report;
    if (r.direct.isEmpty && r.indirect.isEmpty) return const SizedBox.shrink();
    Widget rows(Map<String, VolumeMetrics> m) => Column(
      children: [
        for (final MapEntry(key: muscle, value: v) in m.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(muscle, style: t.bodyMedium)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    v.describe(),
                    textAlign: TextAlign.end,
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(text.toUpperCase(), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('Muscles worked'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 10),
        children: [
          if (r.direct.isNotEmpty) ...[label('Direct'), rows(r.direct)],
          if (r.indirect.isNotEmpty) ...[label('Also involved'), rows(r.indirect)],
          if (r.totals.completeGroups + r.totals.partialGroups > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Protocol groups: ${r.totals.completeGroups.round()} complete, '
                '${r.totals.partialGroups.round()} partial',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
