part of '../settings.dart';

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
                compact: true,
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
