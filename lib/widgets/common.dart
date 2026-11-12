import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../store.dart';

/// Gives the store to the widgets below and rebuilds those that asked with [of] when it changes.
class StoreScope extends InheritedNotifier<Listenable> {
  final AppStore store;
  const StoreScope({super.key, required this.store, required super.child}) : super(notifier: store);

  /// The same store, but rebuilding on [notifier] instead of on every store change; see [StoreGate].
  const StoreScope.gated({super.key, required this.store, required Listenable super.notifier, required super.child});

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.store;

  static AppStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.store;
}

/// Keeps a root page from rebuilding while nobody can see it. The store notifies on every typed digit of a
/// workout, and each of the five root pages (Train, History, Cycle, Rep Max, Settings) stays alive in the
/// background; without this gate one keystroke rebuilt all of them, calendars and reviews included.
/// The page below rebuilds on store changes only while [selected] says it is the shown one and no other page
/// lies on top of it; changes missed meanwhile are applied in the same frame it becomes visible again.
/// Only for root pages: anything opened on top of them listens to the store directly.
class StoreGate extends StatefulWidget {
  final ValueListenable<bool> selected;
  final Widget child;
  const StoreGate({super.key, required this.selected, required this.child});

  @override
  State<StoreGate> createState() => _StoreGateState();
}

class _GatePulse extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _StoreGateState extends State<StoreGate> {
  AppStore? _store;
  var _pulse = _GatePulse();
  bool _visible = false;
  bool _missed = false;

  void _onStore() {
    if (_visible) {
      _pulse.fire();
    } else {
      _missed = true;
    }
  }

  void _onSelected() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onSelected);
  }

  @override
  void didUpdateWidget(covariant StoreGate old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      old.selected.removeListener(_onSelected);
      widget.selected.addListener(_onSelected);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.read(context);
    if (store != _store) {
      _store?.removeListener(_onStore);
      _store = store..addListener(_onStore);
    }
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onSelected);
    _store?.removeListener(_onStore);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Depending on the route rebuilds this gate when a page is pushed over it or popped off it.
    _visible = widget.selected.value && (ModalRoute.of(context)?.isCurrent ?? true);
    if (_visible && _missed) {
      // A new notifier makes the scope below rebuild its dependents within this very build.
      _missed = false;
      final old = _pulse;
      _pulse = _GatePulse();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return StoreScope.gated(store: _store!, notifier: _pulse, child: widget.child);
  }
}

String fmtNum(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
}

String fmtClock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String fmtDuration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
}

String fmtVolume(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.round().toString();
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon", "Tue" and so on.
String fmtWeekday(DateTime d) => _weekdays[d.weekday - 1];

String fmtDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "1 set", "2 sets".
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

String fmtShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// The app's only style of (i) button: a small icon placed right after a label, never a full-size
/// button, so it never makes a row taller (see CLAUDE.md).
class InfoDot extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  const InfoDot({super.key, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(Icons.info_outline_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// A label followed by an [InfoDot]; the label wraps or shrinks before the dot moves.
class LabelWithInfo extends StatelessWidget {
  final Widget label;
  final InfoDot info;
  const LabelWithInfo(this.label, this.info, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: label),
      info,
    ],
  );
}

/// Padding of every root tab's list, so headers line up across tabs.
const pageInsets = EdgeInsets.fromLTRB(16, 16, 16, 96);

/// Padding of every sub-page body; its title lives in the top bar.
const subPageInsets = EdgeInsets.fromLTRB(16, 0, 16, 40);

/// The same header on every root tab: an optional small line above, a large
/// title, an optional inline control and up to a few actions, all at a fixed height so switching
/// tabs never moves the title.
class PageHeader extends StatelessWidget {
  final String title;
  final String? overline;
  final List<Widget> actions;
  final InfoDot? info;
  final Widget? trailing;
  const PageHeader(this.title, {super.key, this.overline, this.actions = const [], this.info, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
      child: SizedBox(
        height: 72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(height: 16, child: Text(overline?.toUpperCase() ?? '', style: t.labelSmall, maxLines: 1)),
                  SizedBox(
                    height: 52,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: info == null
                          ? Text(title, style: t.displaySmall, maxLines: 1, overflow: TextOverflow.ellipsis)
                          : LabelWithInfo(
                              Text(title, style: t.displaySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              info!,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: SizedBox(
                  height: 52,
                  child: Align(alignment: Alignment.centerRight, child: trailing),
                ),
              ),
            ],
            for (final a in actions) SizedBox(width: 52, height: 52, child: Center(child: a)),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

class Stat extends StatelessWidget {
  final String value;
  final String label;
  const Stat(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 2),
        Text(label, style: t.labelSmall),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
  bool destructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: destructive ? cs.error : cs.primary),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

const _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "2 November" (+ year when not this year), with the time in the phone's own 12- or 24-hour setting.
String fmtRecent(DateTime d, {bool includeTime = true}) {
  var text = '${d.day} ${_monthsLong[d.month - 1]}';
  if (d.year != DateTime.now().year) text += ' ${d.year}';
  if (!includeTime) return text;
  final String time;
  if (!WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'AM' : 'PM';
    time = d.minute == 0 ? '$h$suffix' : '$h:${d.minute.toString().padLeft(2, '0')}$suffix';
  } else {
    time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '$text, $time';
}

/// fzf-like ordered-subsequence score; lower is better, null is no match.
double? _fuzzyScore(String query, String text) {
  final q = query.toLowerCase(), t = text.toLowerCase();
  if (q.isEmpty) return 0;
  final positions = <int>[];
  var pos = -1;
  for (final ch in q.split('')) {
    pos = t.indexOf(ch, pos + 1);
    if (pos < 0) return null;
    positions.add(pos);
  }
  var gaps = 0;
  for (var i = 1; i < positions.length; i++) {
    gaps += (positions[i] - positions[i - 1] - 1).clamp(0, 1 << 20);
  }
  return positions.first * 5 + gaps * 3 + t.length * 0.01;
}

/// Shared picker search: fuzzy by default; a leading space switches that
/// search to contiguous, literal matching.
List<String> filterNames(Iterable<String> values, String rawQuery) {
  final exact = rawQuery.startsWith(' ');
  final query = (exact ? rawQuery.substring(1) : rawQuery).trim();
  final unique = <String>[];
  final seen = <String>{};
  for (final v in values) {
    final t = v.trim();
    if (t.isNotEmpty && seen.add(t.toLowerCase())) unique.add(t);
  }
  if (query.isEmpty) return unique..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (exact) {
    final needle = query.toLowerCase();
    return unique.where((v) => v.toLowerCase().contains(needle)).toList()..sort((a, b) {
      final c = a.toLowerCase().indexOf(needle).compareTo(b.toLowerCase().indexOf(needle));
      return c != 0 ? c : a.length.compareTo(b.length);
    });
  }
  final scored = [
    for (final v in unique)
      if (_fuzzyScore(query, v) case final s?) (s, v),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  return [for (final (_, v) in scored) v];
}

void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
