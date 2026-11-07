import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/common.dart';
import '../widgets/rest_timer.dart';
import 'cycle.dart';
import 'data_io.dart';
import 'history.dart';
import 'rep_max.dart';
import 'session.dart';
import 'settings.dart';
import 'train.dart';
import '../store.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  Timer? _restWatch;
  late final AppStore _store;
  String? _alerted;

  @override
  void initState() {
    super.initState();
    // A restored timer that already ran out must not buzz on app launch.
    final store = _store = StoreScope.read(context);
    final r = store.rest;
    if (r != null && r.overdue) _alerted = _key(r.startedAt, r.totalSeconds);
    store.addListener(_syncRestWatch);
    _syncRestWatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reportUnreadableData(context);
    });
  }

  /// The rest-over check only runs while a rest timer exists, instead of waking the app twice a second forever.
  void _syncRestWatch() {
    final resting = _store.rest != null;
    if (resting && _restWatch == null) {
      _restWatch = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkRest());
    } else if (!resting && _restWatch != null) {
      _restWatch!.cancel();
      _restWatch = null;
    }
  }

  String _key(DateTime start, int total) => '${start.microsecondsSinceEpoch}/$total';

  void _checkRest() {
    final store = _store = StoreScope.read(context);
    final r = store.rest;
    if (r == null || !r.overdue) return;
    final key = _key(r.startedAt, r.totalSeconds);
    if (_alerted == key) return;
    _alerted = key;
    // If Android paused the app, this check runs late on return; a buzz minutes after rest ended is noise.
    if (r.remainingSeconds < -5) return;
    store.alerts.restDone(haptics: store.settings.restHaptics, sound: store.settings.restSound);
  }

  @override
  void dispose() {
    _store.removeListener(_syncRestWatch);
    _restWatch?.cancel();
    super.dispose();
  }

  void _select(int i) {
    final store = StoreScope.read(context);
    if (i != 2 && store.cancelPendingCycle()) {
      notify(context, 'Mesocycle setup canceled before Start was pressed.');
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showFloating = store.active != null && store.rest != null && store.settings.floatingTimer;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // From a root tab, Back first returns to the in-progress workout.
    final backToWorkout = store.active != null && _tab != 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarDividerColor: bg,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: !backToWorkout,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && backToWorkout) openSession(context);
        },
        child: Scaffold(
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: IndexedStack(
                  index: _tab,
                  children: [
                    for (final (i, tab) in [
                      TrainScreen(onOpenCycle: () => _select(2)),
                      const HistoryScreen(),
                      const CycleScreen(),
                      const RepMaxScreen(asTab: true),
                      const SettingsScreen(),
                    ].indexed)
                      // Hidden tabs keep their state but not their animations (e.g. Train's rainbow border).
                      TickerMode(enabled: i == _tab, child: tab),
                  ],
                ),
              ),
              if (showFloating)
                Positioned(right: 16, bottom: 16, child: FloatingRestTimer(onTap: () => openSession(context))),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (store.active != null && !showFloating) const _ActiveBar(),
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) {
                  _select(i);
                  // Selecting Workout while a session runs opens that session.
                  if (i == 0 && store.active != null) openSession(context);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.bolt_outlined),
                    selectedIcon: Icon(Icons.bolt_rounded),
                    label: 'Train',
                  ),
                  NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: 'Cycle',
                  ),
                  NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'Rep Max'),
                  NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact global entry point back into the in-progress workout.
class _ActiveBar extends StatelessWidget {
  const _ActiveBar();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.18),
      child: InkWell(
        onTap: () => openSession(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.primary.withValues(alpha: 0.42))),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(Icons.fitness_center_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.active!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'ACTIVE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

void openSession(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionScreen()));
}
