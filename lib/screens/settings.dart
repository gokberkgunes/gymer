import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/numbers.dart';
import '../logic/estimate.dart';
import '../logic/plates.dart';
import '../logic/status_icons.dart';
import '../models.dart';
import '../services/platform_alerts.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/exercise_actions.dart';
import '../widgets/num_field.dart';
import '../widgets/plate_profile_picker.dart';
import '../widgets/warmup_background.dart';
import 'celebrations.dart';
import 'data_io.dart';
import 'bodyweight.dart';
import 'exercises.dart';
import 'measurements.dart';
import 'photos.dart';
import 'rep_max.dart';
import 'achievements.dart';

part 'settings/workout.dart';
part 'settings/timers.dart';
part 'settings/timing.dart';
part 'settings/plates.dart';
part 'settings/data.dart';
part 'settings/appearance.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    Widget link(IconData icon, String title, String subtitle, Widget page) => ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => open(page),
    );
    return ListView(
      padding: pageInsets,
      children: [
        const PageHeader('Settings'),
        _group([
          link(Icons.palette_outlined, 'Appearance', 'Theme, colors, density and size', const AppearanceScreen()),
          link(Icons.bolt_outlined, 'Workout', 'Units, defaults and tracking', const _WorkoutSettings()),
          link(Icons.timer_outlined, 'Rest timers', 'Live timer, alerts and labels', const _TimerSettings()),
          link(Icons.trending_up_rounded, 'Progression', 'Weight increments', const _ProgressionSettings()),
          link(
            Icons.fitness_center_rounded,
            'Plates',
            'Profiles, bar weight and available plates',
            const _PlateSettings(),
          ),
          link(Icons.emoji_events_outlined, 'Achievements', 'Milestones and progress', const AchievementsScreen()),
          link(
            Icons.celebration_outlined,
            'Celebrations',
            'Confetti, personal-best effects and milestones',
            const CelebrationSettings(),
          ),
          link(Icons.tune_rounded, 'Advanced', 'Weekly sets, coach, timing and keyboard', const _AdvancedSettings()),
          link(Icons.storage_outlined, 'Databases', 'Exercises, set types and rep max', const _DatabaseSettings()),
          link(Icons.save_outlined, 'Data', 'Backups, import and export', const _DataSettings()),
        ]),
        const SizedBox(height: 32),
        Center(child: Text('GYMER', style: t.labelSmall?.copyWith(letterSpacing: 4))),
      ],
    );
  }
}

/// A settings subpage with a title and grouped rows.
class _Page extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Page({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: subPageInsets, children: children),
  );
}

Widget _switch(BuildContext context, String title, bool value, void Function(Settings, bool) set, {String? subtitle}) {
  final store = StoreScope.of(context);
  return _row(
    context,
    title,
    Switch(value: value, onChanged: (v) => store.updateSettings((x) => set(x, v))),
    subtitle: subtitle,
  );
}

Widget _group(List<Widget> children) => Card(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), c],
    ],
  ),
);

Widget _row(
  BuildContext context,
  String title,
  Widget trailing, {
  String? subtitle,
  VoidCallback? onTap,
  InfoDot? info,
}) {
  final t = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info == null ? Text(title, style: t.bodyLarge) : LabelWithInfo(Text(title, style: t.bodyLarge), info),
                if (subtitle != null) Text(subtitle, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    ),
  );
}

/// [expand]: full width, for a choice stacked under its title (all stacked choices use this so they line up).
Widget _segmented<T>(
  T value,
  Map<T, String> options,
  ValueChanged<T> onChanged, {
  bool expand = false,
  bool compact = false,
}) {
  final button = SegmentedButton<T>(
    showSelectedIcon: false,
    // Five short options need tighter padding and smaller text to share one row.
    style: compact
        ? const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          )
        : null,
    segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
  return expand ? SizedBox(width: double.infinity, child: button) : button;
}

/// A title with a full-width choice beneath it and an optional one-line muted note.
Widget _stackedChoice<T>(
  BuildContext context,
  String title,
  T value,
  Map<T, String> options,
  ValueChanged<T> onChanged, {
  String? note,
  InfoDot? info,
  bool compact = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final label = Text(title, style: Theme.of(context).textTheme.bodyLarge);
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        info == null ? label : LabelWithInfo(label, info),
        const SizedBox(height: 8),
        _segmented(value, options, onChanged, expand: true, compact: compact),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    ),
  );
}

/// Shows the live value while dragging and saves only on release, so the
/// whole app does not relayout on every slider tick.
class _SliderRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, context.style.sp(12), 16, context.style.sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.title, style: t.bodyLarge)),
              Text(
                widget.format(v),
                style: t.bodyLarge?.copyWith(color: cs.primary, fontFeatures: tabular),
              ),
            ],
          ),
          if (widget.subtitle != null) Text(widget.subtitle!, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: widget.format(v),
            padding: const EdgeInsets.symmetric(vertical: 12),
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onChanged(x);
            },
          ),
        ],
      ),
    );
  }
}
