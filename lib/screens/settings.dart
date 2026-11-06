import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/numbers.dart';
import '../logic/plates.dart';
import '../logic/status_icons.dart';
import '../models.dart';
import '../services/platform_alerts.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import '../widgets/exercise_actions.dart';
import '../widgets/num_field.dart';
import 'data_io.dart';
import 'exercises.dart';
import 'rep_max.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
          link(Icons.fitness_center_rounded, 'Plates', 'Bar weight and the plates you have', const _PlateSettings()),
          link(Icons.tune_rounded, 'Advanced', 'Celebrations, set rules and keyboard', const _AdvancedSettings()),
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

class _WorkoutSettings extends StatelessWidget {
  const _WorkoutSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    return _Page(
      title: 'Workout',
      children: [
        const SectionLabel('Workout defaults'),
        _group([
          _row(
            context,
            'Units',
            _segmented(s.unit, const {'kg': 'kg', 'lb': 'lb'}, (v) => store.updateSettings((x) => x.unit = v)),
            subtitle: 'Changing units converts every stored weight',
          ),
          _row(
            context,
            'Default number of sets',
            SizedBox(
              width: 80,
              child: NumField(
                value: s.defaultSets.toDouble(),
                kind: NumKind.count,
                align: TextAlign.center,
                onChanged: (v) {
                  if (v != null) store.updateSettings((x) => x.defaultSets = v.round());
                },
              ),
            ),
          ),
        ]),
        const SectionLabel('Workout tracking'),
        _group([
          _row(
            context,
            'Track RIR',
            Switch(value: s.trackRir, onChanged: (v) => store.updateSettings((x) => x.trackRir = v)),
            info: InfoDot(tooltip: 'What is RIR?', onTap: () => showRirInfo(context)),
            subtitle:
                'Turn this off if you do not want to rate effort after each set. Weight and reps will still be tracked normally.',
          ),
          _switch(
            context,
            'Dim completed sets',
            s.dimCompleted,
            (x, v) => x.dimCompleted = v,
            subtitle: 'Adds a subtle grey tint to completed set rows.',
          ),
          _switch(
            context,
            'Collapse completed exercises',
            s.collapseCompleted,
            (x, v) => x.collapseCompleted = v,
            subtitle:
                'Automatically folds an exercise after all of its sets are complete. Use the chevron to reopen it.',
          ),
        ]),
        const SectionLabel('Customisation'),
        _group([
          _row(
            context,
            'Exercise shortcuts',
            Text(
              '${exerciseActions.where((action) => s.pinnedExerciseActions.contains(action.$1)).length} pinned',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            subtitle: 'Quick access beside the exercise menu',
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ExerciseShortcutSettings())),
          ),
        ]),
      ],
    );
  }
}

class _ExerciseShortcutSettings extends StatelessWidget {
  const _ExerciseShortcutSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pinned = exerciseActions.where((action) => store.settings.pinnedExerciseActions.contains(action.$1)).toList();

    void toggle(String key) => store.updateSettings((settings) {
      final selected = !settings.pinnedExerciseActions.contains(key);
      settings.pinnedExerciseActions = [
        for (final action in exerciseActions)
          if (action.$1 == key ? selected : settings.pinnedExerciseActions.contains(action.$1)) action.$1,
      ];
    });

    return _Page(
      title: 'Exercise shortcuts',
      children: [
        const SectionLabel('Preview'),
        // Desaturate and warm the sample so it reads as a preview, not another setting.
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.218,
            0.735,
            0.074,
            0,
            0,
            0.209,
            0.702,
            0.071,
            0,
            0,
            0.191,
            0.642,
            0.065,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Opacity(
            opacity: 0.72,
            child: IgnorePointer(
              child: _SetPreview(
                header: ExerciseActionHeader(
                  title: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bench Press', style: t.titleMedium?.copyWith(fontSize: 18)),
                        Text('Chest · Triceps', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  actions: [
                    for (final (_, label, icon) in pinned)
                      Tooltip(
                        message: label,
                        child: Center(child: Icon(icon, color: cs.onSurfaceVariant)),
                      ),
                  ],
                  menu: Center(child: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text('Tap an action to pin or unpin it.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        const SectionLabel('Actions'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, (key, label, icon)) in exerciseActions.indexed) ...[
                if (index > 0) const Divider(indent: 52, endIndent: 16),
                _ExerciseShortcutRow(
                  label: label,
                  icon: icon,
                  pinned: store.settings.pinnedExerciseActions.contains(key),
                  onTap: () => toggle(key),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseShortcutRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool pinned;
  final VoidCallback onTap;

  const _ExerciseShortcutRow({required this.label, required this.icon, required this.pinned, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      toggled: pinned,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(8)),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pinned ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
                  borderRadius: context.style.brSmall,
                ),
                child: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 18,
                  color: pinned ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerSettings extends StatelessWidget {
  const _TimerSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    return _Page(
      title: 'Rest timers',
      children: [
        const SectionLabel('In the app'),
        _group([
          _row(
            context,
            'Default rest timer',
            SizedBox(
              width: 90,
              child: DurationField(
                seconds: s.defaultRest,
                onChanged: (v) => store.updateSettings((x) => x.defaultRest = v),
              ),
            ),
          ),
          _stackedChoice(context, 'Live timer', s.timerMode, const {
            'both': 'Both',
            'floating': 'Floating',
            'nearset': 'Near set',
            'off': 'Off',
          }, (v) => store.updateSettings((x) => x.timerMode = v)),
          _switch(
            context,
            'Haptic when rest ends',
            s.restHaptics,
            (x, v) => x.restHaptics = v,
            subtitle: 'Vibrates when rest runs out.',
          ),
          _switch(
            context,
            'Sound when rest ends',
            s.restSound,
            (x, v) => x.restSound = v,
            subtitle: 'A short beep at media volume.',
          ),
          _stackedChoice(
            context,
            'Planned rest labels',
            s.plannedRestDisplay,
            const {'hide': 'Hide', 'smart': 'Smart', 'always': 'Always'},
            (v) => store.updateSettings((x) => x.plannedRestDisplay = v),
            note: switch (s.plannedRestDisplay) {
              'smart' => 'Shown when rest times differ or for special sets.',
              'always' => 'Shown beside every set.',
              _ => 'Never shown.',
            },
          ),
          _stackedChoice(
            context,
            'Default timer view',
            s.defaultTimerDisplay,
            const {'elapsed': 'Elapsed', 'countdown': 'Countdown'},
            (v) => store.updateSettings((x) => x.defaultTimerDisplay = v),
            note: 'Hold the round timer to switch.',
          ),
        ]),
        const SectionLabel('Outside the app'),
        _group([
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stackedChoice(
                context,
                'Rest notification',
                s.restNotice,
                const {'live': 'Sticky', 'alarm': 'Alarm', 'both': 'Combined', 'off': 'Off'},
                (v) => store.updateSettings((x) => x.restNotice = v),
                note: switch (s.restNotice) {
                  'live' => 'Silent live timer in the status bar; counts into overtime.',
                  'alarm' => 'A "Rest over" alert, even with the phone locked.',
                  'both' => 'Sticky timer, replaced by the alert when rest ends.',
                  _ => 'Nothing outside the app.',
                },
              ),
              if (s.restNotice != 'off' && store.alerts is PlatformAlerts)
                _NotificationPermission(alerts: store.alerts as PlatformAlerts),
            ],
          ),
          if (s.restNotice == 'live' || s.restNotice == 'both') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabelWithInfo(
                    Text('Chip shows', style: Theme.of(context).textTheme.bodyLarge),
                    InfoDot(tooltip: 'What is the chip?', onTap: () => _chipInfo(context)),
                  ),
                  const SizedBox(height: 8),
                  _segmented(
                    s.chipMode,
                    const {'time': 'Time', 'text': 'Text'},
                    (v) => store.updateSettings((x) => x.chipMode = v),
                    expand: true,
                  ),
                  if (s.chipMode == 'text') ...[
                    const SizedBox(height: 8),
                    _ChipTextField(value: s.chipText, onChanged: (v) => store.updateSettings((x) => x.chipText = v)),
                  ],
                ],
              ),
            ),
            _switch(
              context,
              'Custom icons',
              s.customIcons,
              (x, v) => x.customIcons = v,
              subtitle: s.customIcons ? null : 'Default: muscle during rest, warning in overtime.',
            ),
            if (s.customIcons) ...[
              _StatusIconPicker(
                title: 'During rest',
                prefix: 'rest',
                icons: restIcons,
                selected: s.restIcon,
                onSelected: (v) => store.updateSettings((x) => x.restIcon = v),
              ),
              if (s.restNotice == 'live')
                _StatusIconPicker(
                  title: 'In overtime',
                  subtitle: 'Shown once rest is over and the timer counts the extra time up.',
                  prefix: 'over',
                  icons: overtimeIcons,
                  selected: s.overtimeIcon,
                  onSelected: (v) => store.updateSettings((x) => x.overtimeIcon = v),
                ),
            ],
          ],
          if ((s.restNotice == 'alarm' || s.restNotice == 'both') && store.alerts is PlatformAlerts)
            _PreciseAlarm(alerts: store.alerts as PlatformAlerts),
        ]),
      ],
    );
  }
}

Future<void> _chipInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('The status-bar chip'),
    content: const Text(
      'While you rest with Gymer in the background, Android 16 and newer show a small pill next to the clock '
      'at the top of the screen: the chip. It holds your timer icon and either the live rest time or your own '
      'short text. Android draws it, so its colour and shape are fixed.\n\n'
      'Older Android versions have no chip; the timer appears in the notification shade instead.',
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
  ),
);

/// Optional short label (max 7 characters) shown in the status-bar chip instead of the time, with an
/// always-visible n/7 counter inside the box.
class _ChipTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ChipTextField({required this.value, required this.onChanged});

  @override
  State<_ChipTextField> createState() => _ChipTextFieldState();
}

class _ChipTextFieldState extends State<_ChipTextField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _max = 7;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    // The fill is drawn here, under a transparent field, so the n/7 counter sits on the background:
    // always visible, and behind the text if the text ever reaches it.
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: st.brSmall),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: ListenableBuilder(
              listenable: _c,
              builder: (_, _) => Text(
                '${_c.text.characters.length}/$_max',
                style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontFeatures: tabular),
              ),
            ),
          ),
          TextField(
            controller: _c,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(_max)],
            decoration: const InputDecoration(hintText: 'Up to 7 characters', filled: false),
            onChanged: (v) => widget.onChanged(v.trim()),
          ),
        ],
      ),
    );
  }
}

/// A grid of status-bar icon previews (white silhouettes, as Android draws them).
class _StatusIconPicker extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String prefix;
  final List<(String, String)> icons;
  final String selected;
  final ValueChanged<String> onSelected;
  const _StatusIconPicker({
    required this.title,
    this.subtitle,
    required this.prefix,
    required this.icons,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, label) in icons)
                Tooltip(
                  message: label,
                  child: InkWell(
                    borderRadius: st.brSmall,
                    onTap: () => onSelected(key),
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: key == selected ? cs.primary.withValues(alpha: 0.16) : cs.surfaceContainerHigh,
                        borderRadius: st.brSmall,
                        border: Border.all(color: key == selected ? cs.primary : Colors.transparent, width: 2),
                      ),
                      child: Image.asset(
                        'assets/status_icons/${prefix}_$key.png',
                        color: key == selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressionSettings extends StatelessWidget {
  const _ProgressionSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final t = Theme.of(context).textTheme;
    final lb = s.unit == 'lb';
    return _Page(
      title: 'Progression',
      children: [
        const SectionLabel('Progression weight increments'),
        Text(
          'These are the default smallest available jumps. Each exercise can override its own increment in Exercise '
          'Database → Details.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        _group([
          for (final eq in equipmentTypes)
            _row(
              context,
              eq,
              SizedBox(
                width: 100,
                child: NumField(
                  value: lb ? s.increments[eq]?.$2 : s.increments[eq]?.$1,
                  kind: NumKind.weight,
                  suffix: s.unit,
                  align: TextAlign.center,
                  onChanged: (v) {
                    if (v == null) return;
                    store.updateSettings((x) {
                      final old = x.increments[eq] ?? defaultIncrements[eq]!;
                      x.increments[eq] = lb ? (old.$1, v) : (v, old.$2);
                    });
                  },
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${lb ? 'Barbell default: 10 lb total (+5/+5). ' : 'Barbell default: 5 kg total (+2.5/+2.5). '}'
          'Dumbbell is per dumbbell; Plate loaded is total logged load; Weight-stack machine uses the displayed stack value.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => store.updateSettings((x) => x.increments = Map.of(defaultIncrements)),
          child: const Text('Reset weight increments'),
        ),
      ],
    );
  }
}

Future<void> _addPlate(BuildContext context, AppStore store, bool lb) async {
  double? size;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Add a plate size'),
      content: NumField(
        value: null,
        kind: NumKind.weight,
        placeholder: 'Weight of one plate',
        suffix: store.settings.unit,
        dense: false,
        onChanged: (v) => size = v,
        onSubmitted: () => Navigator.pop(c, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
      ],
    ),
  );
  final v = size;
  if (ok != true || v == null || v <= 0) return;
  store.updateSettings((x) {
    final list = lb ? x.platesLb : x.platesKg;
    if (!list.contains(v)) list.add(v);
    list.sort((a, b) => b.compareTo(a));
  });
}

Route<void> plateSettingsRoute() => MaterialPageRoute(builder: (_) => const _PlateSettings());

/// Plate calculator setup: the default bar and which plate sizes the gym has (pairs are assumed unlimited).
class _PlateSettings extends StatelessWidget {
  const _PlateSettings();

  static const _candidatesKg = [50.0, 25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 2.0, 1.25, 1.0, 0.5, 0.25];
  static const _candidatesLb = [55.0, 45.0, 35.0, 25.0, 15.0, 10.0, 5.0, 2.5, 1.25];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final lb = s.unit == 'lb';
    return _Page(
      title: 'Plates',
      children: [
        const SizedBox(height: 8),
        _group([
          _row(
            context,
            'Bar',
            SizedBox(
              width: 100,
              child: NumField(
                value: s.bar,
                kind: NumKind.load,
                suffix: s.unit,
                align: TextAlign.center,
                onChanged: (v) {
                  if (v == null) return;
                  store.updateSettings((x) {
                    if (lb) {
                      x.barLb = v;
                    } else {
                      x.barKg = v;
                    }
                  });
                },
              ),
            ),
            subtitle: 'Exercises can set their own, e.g. an EZ bar',
          ),
        ]),
        const SectionLabel('Plates you have'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // Common sizes plus any custom size the user added; a custom size disappears when switched off.
            for (final p in {
              ...(lb ? _candidatesLb : _candidatesKg),
              ...s.plates,
            }.toList()..sort((a, b) => b.compareTo(a)))
              FilterChip(
                label: Text(formatNumber(p, NumKind.load), style: const TextStyle(fontFeatures: tabular)),
                showCheckmark: false,
                selected: s.plates.contains(p),
                onSelected: (on) => store.updateSettings((x) {
                  final list = lb ? x.platesLb : x.platesKg;
                  on ? list.add(p) : list.remove(p);
                  list.sort((a, b) => b.compareTo(a));
                }),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Other size'),
              onPressed: () => _addPlate(context, store, lb),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => store.updateSettings((x) {
            if (lb) {
              x
                ..barLb = defaultBarLb
                ..platesLb = List.of(defaultPlatesLb);
            } else {
              x
                ..barKg = defaultBarKg
                ..platesKg = List.of(defaultPlatesKg);
            }
          }),
          child: const Text('Reset bar and plates'),
        ),
      ],
    );
  }
}

class _AdvancedSettings extends StatelessWidget {
  const _AdvancedSettings();

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context).settings;
    return _Page(
      title: 'Advanced',
      children: [
        const SizedBox(height: 8),
        _group([
          ListTile(
            leading: const Icon(Icons.celebration_outlined),
            title: const Text('Celebrations', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Preview workout celebrations'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CelebrationsPreview())),
          ),
        ]),
        const SectionLabel('Workout'),
        _group([
          _switch(
            context,
            'Require previous set',
            s.requirePreviousSet,
            (x, v) => x.requirePreviousSet = v,
            subtitle:
                'When on, a set can only be completed after earlier sets of that same exercise are complete. '
                'Other exercises do not matter.',
          ),
          _switch(
            context,
            'Update following set defaults',
            s.updateFollowingDefaults,
            (x, v) => x.updateFollowingDefaults = v,
            subtitle: 'When on, completing a set refreshes untouched later-set defaults.',
          ),
          _switch(
            context,
            'Keep screen awake',
            s.keepAwake,
            (x, v) => x.keepAwake = v,
            subtitle: 'Stops the screen from turning off while a workout is active.',
          ),
          _switch(
            context,
            'Haptic on set complete',
            s.haptics,
            (x, v) => x.haptics = v,
            subtitle: 'A light tap when you complete a set.',
          ),
          _switch(
            context,
            'Show previous reps in mesocycles',
            s.showPreviousReps,
            (x, v) => x.showPreviousReps = v,
            subtitle:
                'Off by default. When enabled, historical rep counts may appear as workout placeholders during a mesocycle.',
          ),
        ]),
        const SectionLabel('Set keyboard navigation'),
        _group([
          _switch(
            context,
            'Enter completes set',
            s.enterCompletesSet,
            (x, v) => x.enterCompletesSet = v,
            subtitle:
                'Enter on the last editable box can complete the set. This shortcut never starts or resumes the workout clock.',
          ),
          _switch(context, 'Enter moves to next set', s.enterMovesToNextSet, (x, v) => x.enterMovesToNextSet = v),
          _switch(
            context,
            'Enter closes keyboard',
            s.enterClosesKeyboard,
            (x, v) => x.enterClosesKeyboard = v,
            subtitle: 'Enter on the last box of a set hides the keyboard, unless it moves to the next set.',
          ),
          _switch(
            context,
            'Backspace moves to previous set',
            s.backspaceMovesToPreviousSet,
            (x, v) => x.backspaceMovesToPreviousSet = v,
          ),
        ]),
      ],
    );
  }
}

class _DatabaseSettings extends StatelessWidget {
  const _DatabaseSettings();

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return _Page(
      title: 'Databases',
      children: [
        const SizedBox(height: 8),
        _group([
          ListTile(
            title: const Text('Exercise database'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const ExercisesScreen()),
          ),
          ListTile(
            title: const Text('Rep max table'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const RepMaxScreen()),
          ),
          ListTile(
            title: const Text('Set type database'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const SetTypesScreen()),
          ),
        ]),
      ],
    );
  }
}

class _DataSettings extends StatelessWidget {
  const _DataSettings();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Page(
      title: 'Data',
      children: [
        const SizedBox(height: 8),
        _group([
          _row(
            context,
            'Automatic backups',
            Icon(Icons.history_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Last 3 days, 4 weeks and 6 months',
            onTap: () => openAutoBackups(context),
          ),
        ]),
        const SizedBox(height: 12),
        _group([
          _row(
            context,
            'Import from old Gymer',
            Icon(Icons.download_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Backup ZIP exported by the Flet app',
            onTap: () => importFletBackup(context),
          ),
          _row(
            context,
            'Export backup',
            Icon(Icons.upload_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Everything as one JSON file',
            onTap: () => exportBackup(context),
          ),
          _row(
            context,
            'Restore backup',
            Icon(Icons.restore_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Replace all data from a JSON backup',
            onTap: () => restoreBackup(context),
          ),
        ]),
      ],
    );
  }
}

void showRirInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Using RIR'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (title, body) in const [
              (
                'Rate the set after you finish it',
                'RIR is how many clean reps you believe you still had left. If you could have done about three more '
                    'reps, log 3 RIR. If only one good rep remained, log 1 RIR.',
              ),
              (
                'Use it to judge whether the load was right',
                'If your target was 2 RIR but the set felt like 4 RIR, the load was probably conservative. If it felt '
                    'like 0 RIR, it was harder than planned. Use that difference to guide the next session rather than '
                    'chasing a number during the set itself.',
              ),
              (
                'Use higher RIR when you want more margin',
                'Around 3 RIR is useful when you want productive work without pushing close to failure. Around 1 RIR '
                    'is a much harder set. Keep technique consistent and stop the set if form breaks down, regardless '
                    'of the target.',
              ),
              (
                'Look for trends',
                'The most useful signal is repeated performance. If the same weight and reps begin to feel easier over '
                    'time, that is a good reason to progress the load or reps.',
              ),
            ]) ...[
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(body),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Celebrations')),
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
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    void set(void Function(Settings x) f) => store.updateSettings(f);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: subPageInsets,
        children: [
          const SectionLabel('Colors and theme'),
          _group([
            _row(
              context,
              'Theme',
              _segmented(s.themeMode, const {
                'system': 'Auto',
                'light': 'Light',
                'dark': 'Dark',
              }, (v) => set((x) => x.themeMode = v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Accent', style: t.bodyLarge),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final (i, a) in accents.indexed)
                        _Swatch(
                          color: a.$2,
                          label: a.$1,
                          selected: s.accent == i,
                          onTap: () => set((x) => x.accent = i),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Background', style: t.bodyLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final e in backgrounds.entries)
                        _BackgroundChip(
                          label: e.value.$1,
                          color: dark ? e.value.$2 : e.value.$3,
                          selected: s.background == e.key,
                          onTap: () => set((x) => x.background = e.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]),
          const SectionLabel('Layout'),
          _group([
            _SliderRow(
              title: 'Interface size',
              value: s.uiScale,
              min: 0.7,
              max: 1.2,
              divisions: 10,
              format: (v) => '${v.toStringAsFixed(2)}×',
              onChanged: (v) => set((x) => x.uiScale = v),
            ),
            _SliderRow(
              title: 'Font size',
              value: s.fontScale,
              min: 0.8,
              max: 1.4,
              divisions: 6,
              format: (v) => '${v.toStringAsFixed(2)}×',
              onChanged: (v) => set((x) => x.fontScale = v),
            ),
            _SliderRow(
              title: 'Roundedness',
              value: s.rounding.toDouble(),
              min: 0,
              max: 24,
              divisions: 6,
              format: (v) => v == 0 ? 'Sharp' : '${v.round()} px',
              onChanged: (v) => set((x) => x.rounding = v.round()),
            ),
            _row(
              context,
              'Density',
              _segmented(s.density, const {
                'compact': 'Compact',
                'normal': 'Normal',
                'roomy': 'Roomy',
              }, (v) => set((x) => x.density = v)),
            ),
            _SliderRow(
              title: 'Set spacing',
              subtitle: 'Effective gap ${st.setGap.round()} px with ${s.density} density',
              value: s.setSpacing.toDouble(),
              min: 0,
              max: 18,
              divisions: 18,
              format: (v) => '${v.round()} px',
              onChanged: (v) => set((x) => x.setSpacing = v.round()),
            ),
            _row(
              context,
              'Dim completed sets',
              Switch(value: s.dimCompleted, onChanged: (v) => set((x) => x.dimCompleted = v)),
            ),
          ]),
          const SectionLabel('Preview'),
          const _SetPreview(),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => set((x) => x.resetAppearance()),
            child: Text('Reset appearance', style: TextStyle(color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
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
Widget _segmented<T>(T value, Map<T, String> options, ValueChanged<T> onChanged, {bool expand = false}) {
  final button = SegmentedButton<T>(
    showSelectedIcon: false,
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
        _segmented(value, options, onChanged, expand: true),
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

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(context.style.radius.clamp(0, 18)),
            border: Border.all(
              color: selected ? cs.onSurface : Colors.transparent,
              width: 2.5,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _BackgroundChip({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    return InkWell(
      onTap: onTap,
      borderRadius: st.brSmall,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          borderRadius: st.brSmall,
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(st.small.clamp(0, 11)),
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _SetPreview extends StatelessWidget {
  final Widget? header;
  const _SetPreview({this.header});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;

    // Mirrors the workout screen's set rows: same tile colours, input boxes and rounded-square check.
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, Colors.white, 0.07)
        : cs.surface;
    Widget box(String text, bool done) => Expanded(
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: done ? null : fieldFill, borderRadius: st.brSmall),
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular),
        ),
      ),
    );
    Widget setRow(int n, String w, String r, String rir, bool done) => Container(
      margin: EdgeInsets.symmetric(vertical: st.setGap / 2),
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: st.sp(2) + 2),
      decoration: BoxDecoration(
        color: done ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHigh,
        borderRadius: st.setTile(n - 1, 3),
      ),
      child: Opacity(
        opacity: done && st.dimCompleted ? 0.55 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                '$n',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            box(w, done),
            const SizedBox(width: 6),
            box(r, done),
            const SizedBox(width: 6),
            box(rir, done),
            SizedBox(
              width: 48,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: done ? cs.primary : null,
                    border: Border.all(color: done ? cs.primary : cs.outline, width: 2),
                    borderRadius: BorderRadius.circular(st.small.clamp(0, 10)),
                  ),
                  child: done ? Icon(Icons.check_rounded, size: 20, color: cs.onPrimary) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, st.sp(14), 12, st.sp(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header ?? Text('Bench Press', style: t.titleMedium),
            SizedBox(height: st.sp(8)),
            setRow(1, '80', '8', '2', true),
            setRow(2, '80', '7', '1', true),
            setRow(3, '80', '8', '2', false),
          ],
        ),
      ),
    );
  }
}

class _NotificationPermission extends StatefulWidget {
  final PlatformAlerts alerts;
  const _NotificationPermission({required this.alerts});

  @override
  State<_NotificationPermission> createState() => _NotificationPermissionState();
}

class _NotificationPermissionState extends State<_NotificationPermission> with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await widget.alerts.notificationsEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != false) return const SizedBox.shrink();
    return _row(
      context,
      'Notifications are off',
      TextButton(onPressed: widget.alerts.openNotificationSettings, child: const Text('Settings')),
      subtitle: 'Rest notifications cannot appear until they are enabled.',
    );
  }
}

class _PreciseAlarm extends StatefulWidget {
  final PlatformAlerts alerts;
  const _PreciseAlarm({required this.alerts});

  @override
  State<_PreciseAlarm> createState() => _PreciseAlarmState();
}

class _PreciseAlarmState extends State<_PreciseAlarm> with WidgetsBindingObserver {
  bool? _exact;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final v = await widget.alerts.canScheduleExact();
    if (mounted) setState(() => _exact = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_exact != false) return const SizedBox.shrink();
    return _row(
      context,
      'Precise alarm',
      TextButton(onPressed: widget.alerts.requestExact, child: const Text('Allow')),
      subtitle: 'Without it Android may deliver the rest alarm late',
    );
  }
}
