part of '../store.dart';

/// The workout clock and the rest timer.
extension AppStoreRestClock on AppStore {
  void toggleClock() {
    final s = active;
    if (s == null) return;
    if (!s.clockStarted) {
      s
        ..clockStarted = true
        ..clockElapsed = 0
        ..clockRunningSince = DateTime.now();
    } else if (s.clockRunning) {
      s
        ..clockElapsed = s.clockSeconds
        ..clockRunningSince = null;
    } else {
      s.clockRunningSince = DateTime.now();
    }
    changed();
  }

  void resetClock() {
    final s = active;
    if (s == null) return;
    s
      ..clockStarted = false
      ..clockElapsed = 0
      ..clockRunningSince = null;
    changed();
  }

  void startRest(String exercise, int setIndex, int seconds) {
    if (seconds <= 0) {
      _dismissRest();
      return;
    }
    rest = RestTimer(
      startedAt: DateTime.now(),
      totalSeconds: seconds,
      exercise: exercise,
      setIndex: setIndex,
      countdown: settings.defaultTimerDisplay == 'countdown',
      warmup: active?.activeWarmup?.name == exercise,
    );
    _syncAlerts();
  }

  void _dismissRest() {
    rest = null;
    _syncAlerts();
  }

  /// Holding the round timer switches between the elapsed and countdown views, both ways.
  void toggleRestDisplay() {
    if (rest == null) return;
    rest = rest!.copyWith(countdown: !rest!.countdown);
    changed();
  }

  /// Changes only the running timer's total; zero dismisses it.
  void setRestTotal(int seconds) {
    if (rest == null) return;
    rest = seconds <= 0 ? null : rest!.copyWith(totalSeconds: seconds);
    _syncAlerts();
    changed();
  }

  /// Planned-rest edits affect unfinished entries only.
  void setPlannedRests(SessionExercise e, Iterable<int> indices, int seconds) {
    for (final i in indices) {
      if (i >= 0 && i < e.sets.length && !e.sets[i].done) e.sets[i].rest = seconds;
    }
    changed();
  }

  /// Rest-editor scopes for unfinished entries, as rest_scopes.targets.
  Map<String, List<int>> restScopes(SessionExercise e) {
    final out = <String, List<int>>{};
    void add(String k, int i) => out.putIfAbsent(k, () => []).add(i);
    final roles = [for (final s in e.sets) setRole(s.type)];
    final classified = <int, String>{};
    for (var i = 0; i < e.sets.length; i++) {
      if (roles[i] == 'warmup') classified[i] = 'warmup';
      if (roles[i] == 'conventional') classified[i] = 'conventional';
    }
    // Protocol groups: anchor + continuations, or a run of cluster fragments.
    var i = 0;
    while (i < e.sets.length) {
      final r = roles[i];
      if (r == 'anchor' || r == 'cluster_fragment') {
        var j = i + 1;
        while (j < e.sets.length &&
            !e.sets[j].groupStart &&
            (r == 'anchor' ? roles[j] == 'continuation' : roles[j] == 'cluster_fragment')) {
          j++;
        }
        if (r == 'cluster_fragment' || j - i > 1) {
          for (var k = i; k < j - 1; k++) {
            classified[k] = 'within_protocol';
          }
          classified[j - 1] = 'after_protocol';
        }
        i = j;
      } else {
        i++;
      }
    }
    for (var k = 0; k < e.sets.length; k++) {
      if (e.sets[k].done) continue;
      add('all_pending', k);
      add('set:$k', k);
      final c = classified[k];
      if (c != null) add(c, k);
    }
    return out;
  }
}
