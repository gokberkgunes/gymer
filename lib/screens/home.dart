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

const _workoutRouteName = '/workout';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final _shown = List.generate(5, (i) => ValueNotifier(i == 0));
  final _navigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  late final _observers = List.generate(5, (_) => _TabObserver(_navigationChanged));
  bool _navigationUpdatePending = false;
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
    store.addListener(_closeEndedWorkout);
    _syncRestWatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reportUnreadableData(_navigators[_tab].currentContext!);
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

  /// A workout page must not outlive its workout: a restore or import from another tab ends the workout while
  /// its page is still on a tab's stack, which would leave a blank page with the bottom bar hidden. Checked
  /// after the frame, because finishing and discarding replace or pop that page themselves right after the
  /// store changes.
  bool _endedCheckPending = false;
  void _closeEndedWorkout() {
    if (_store.active != null || _endedCheckPending) return;
    if (!_observers.any((o) => o.workoutRoute != null)) return;
    _endedCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endedCheckPending = false;
      if (!mounted || _store.active != null) return;
      for (var i = 0; i < _observers.length; i++) {
        final route = _observers[i].workoutRoute;
        if (route != null && route.isActive) _navigators[i].currentState?.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String _key(DateTime start, int total) => '${start.microsecondsSinceEpoch}/$total';

  void _checkRest() {
    final store = _store;
    final r = store.rest;
    if (r == null || !r.overdue) return;
    final key = _key(r.startedAt, r.totalSeconds);
    if (_alerted == key) return;
    _alerted = key;
    // If Android paused the app, this check runs late on return; a buzz minutes after rest ended is noise.
    if (r.remainingSeconds < -5) return;
    store.alerts.restDone(haptics: store.settings.restHaptics);
  }

  @override
  void dispose() {
    _store.removeListener(_syncRestWatch);
    _store.removeListener(_closeEndedWorkout);
    for (final shown in _shown) {
      shown.dispose();
    }
    _restWatch?.cancel();
    super.dispose();
  }

  void _select(int i) {
    final store = StoreScope.read(context);
    if (i != 2 && store.cancelPendingCycle()) {
      _navigators[2].currentState?.popUntil((route) => route.isFirst);
      notify(context, 'Mesocycle setup canceled before Start was pressed.');
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = i);
    for (final (n, shown) in _shown.indexed) {
      shown.value = n == i;
    }
  }

  void _navigationChanged() {
    if (!mounted || _navigationUpdatePending) return;
    // Cold-start route creation can build widgets while the scheduler is still idle.
    // Always defer the shell refresh until the current build has finished.
    _navigationUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationUpdatePending = false;
      if (mounted) setState(() {});
    });
  }

  void _openWorkout() {
    if (_store.active == null) return;
    // Reuse the existing workout even when it was opened from another tab.
    for (var i = 0; i < _observers.length; i++) {
      final route = _observers[i].workoutRoute;
      if (route == null) continue;
      if (_tab != i) _select(i);
      _navigators[i].currentState!.popUntil((candidate) => candidate == route);
      return;
    }
    unawaited(
      _navigators[_tab].currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: _workoutRouteName),
          builder: (_) => const SessionScreen(),
        ),
      ),
    );
  }

  Widget _tabNavigator(int i, Widget tab) {
    final canPop = _observers[i].canPop;
    // Capture this stack's state before a Back callback can open the workout on another stack.
    final selected = i == _tab;
    return TickerMode(
      enabled: selected,
      child: NavigatorPopHandler<Object?>(
        enabled: selected,
        onPopWithResult: (result) {
          if (selected && i == _tab && canPop) unawaited(_navigators[i].currentState!.maybePop(result));
        },
        child: HeroControllerScope.none(
          child: Navigator(
            key: _navigators[i],
            observers: [_observers[i]],
            // Root pages rebuild on store changes only while shown (see StoreGate).
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => StoreGate(selected: _shown[i], child: tab),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inWorkout = _observers[_tab].inWorkout;
    final showFloating = !inWorkout && store.active != null && store.rest != null && store.settings.floatingTimer;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // From a root tab, Back first returns to the in-progress workout.
    final backToWorkout = store.active != null && _tab != 0 && !_observers[_tab].canPop;
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
          if (!didPop && backToWorkout) _openWorkout();
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
                      // Each tab retains its pages and drafts without animating while hidden.
                      _tabNavigator(i, tab),
                  ],
                ),
              ),
              if (showFloating) Positioned(right: 16, bottom: 16, child: FloatingRestTimer(onTap: _openWorkout)),
            ],
          ),
          bottomNavigationBar: inWorkout
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (store.active != null && !showFloating) const _ActiveBar(),
                    NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (i) {
                        _select(i);
                        if (i == 0 && store.active != null) _openWorkout();
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

/// Tracks pages independently of popups, so a dialog never reveals the bar over a workout.
class _TabObserver extends NavigatorObserver {
  _TabObserver(this.onChanged);

  final VoidCallback onChanged;
  final _routes = <Route<dynamic>>[];

  bool get canPop => _routes.length > 1;
  bool get inWorkout => _routes.whereType<PageRoute<dynamic>>().lastOrNull?.settings.name == _workoutRouteName;
  Route<dynamic>? get workoutRoute => _routes.where((route) => route.settings.name == _workoutRouteName).firstOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = _routes.indexOf(oldRoute!);
    if (index >= 0 && newRoute != null) _routes[index] = newRoute;
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) => onChanged();
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
  final shell = context.findAncestorStateOfType<_HomeShellState>();
  if (shell != null) {
    shell._openWorkout();
  } else {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionScreen())));
  }
}
