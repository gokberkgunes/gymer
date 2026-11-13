import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data/seed.dart';
import 'logic/achievements.dart';
import 'logic/circuits.dart';
import 'logic/bodyweight.dart';
import 'logic/coach.dart';
import 'logic/cycle.dart';
import 'logic/cycle_review.dart';
import 'logic/estimate.dart';
import 'logic/legacy_import.dart';
import 'logic/methods.dart';
import 'logic/numbers.dart';
import 'logic/plates.dart';
import 'logic/progression.dart';
import 'logic/snapshots.dart';
import 'logic/volume.dart';
import 'logic/warmup.dart';
import 'models.dart';

part 'store/types.dart';
part 'store/catalog.dart';
part 'store/cycles.dart';
part 'store/records.dart';
part 'store/session_start.dart';
part 'store/session_edits.dart';
part 'store/rest_clock.dart';
part 'store/finishing.dart';
part 'store/history.dart';
part 'store/backups.dart';
part 'store/coach.dart';

class AppStore extends ChangeNotifier {
  AppStore({File? file, Alerts? alerts})
    // ignore: prefer_initializing_formals
    : _file = file,
      alerts = alerts ?? NoAlerts();

  final File? _file;
  final Alerts alerts;
  Timer? _saveDebounce;

  Settings settings = Settings();
  List<WorkoutTemplate> templates = [];
  List<Exercise> exercises = [];
  List<Session> history = [];
  List<Mesocycle> cycles = [];
  List<BodyweightEntry> bodyweights = [];
  Set<String> _seenAchievements = {};
  Session? active;
  RestTimer? rest;

  /// Bumped when a set is completed, so the UI can play its confetti.
  int setCelebration = 0;

  /// Set when the data file could not be read at launch: the path of the copy kept aside, so the UI can
  /// tell the user and offer to save it. Cleared once shown.
  String? unreadableCopy;

  Future<void> load() async {
    final file = _file;
    if (file != null && await file.exists()) {
      try {
        _fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        _syncAlerts();
        notifyListeners();
        unawaited(_dailySnapshot()); // only after a good load: never let fresh data replace a real copy
        return;
      } catch (e) {
        debugPrint('gymer: unreadable data file, keeping a copy: $e');
        final copy = '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        try {
          await file.copy(copy);
          unreadableCopy = copy;
        } catch (copyError) {
          // Without a safe copy the unreadable file is the only trace of the user's data: leave it
          // untouched rather than overwrite it with fresh data.
          debugPrint('gymer: could not keep a copy of the unreadable data file: $copyError');
          unreadableCopy = file.path;
          _writesBlocked = true;
        }
      }
    }
    exercises = List.of(seedExercises);
    templates = seedTemplates();
    notifyListeners();
    await _persist();
  }

  /// Parses everything before replacing anything, so a file that fails halfway leaves the current data
  /// untouched instead of half-replaced.
  void _fromJson(Map<String, dynamic> j) {
    final newSettings = Settings.fromJson(j['settings'] as Map<String, dynamic>? ?? {});
    final newTemplates = [
      for (final t in j['templates'] as List? ?? []) WorkoutTemplate.fromJson(t as Map<String, dynamic>),
    ];
    final newExercises = [for (final e in j['exercises'] as List? ?? []) Exercise.fromJson(e as Map<String, dynamic>)];
    // Newest first, always: every "last time" lookup takes the first match, so an unsorted (hand-edited or
    // merged) file must not decide progression.
    final newHistory = [for (final s in j['history'] as List? ?? []) Session.fromJson(s as Map<String, dynamic>)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    // A provisional cycle abandoned during its first calendar setup is discarded.
    final newCycles = [for (final c in j['cycles'] as List? ?? []) Mesocycle.fromJson(c as Map<String, dynamic>)]
      ..removeWhere((c) => !c.setupComplete);
    final newActive = j['active'] == null ? null : Session.fromJson(j['active'] as Map<String, dynamic>);
    // One damaged measurement must not make the whole data file unreadable; skip it.
    final newBodyweights = <String, BodyweightEntry>{
      for (final parsed in [for (final entry in j['bodyweights'] as List? ?? []) ?_tryBodyweight(entry)])
        dateKey(parsed.date): parsed,
    }.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final r = j['rest'];
    final newRest = r == null || newActive == null ? null : _tryRest(r);
    final seen = j['seenAchievements'];
    final newSeen = seen is List
        ? seen.whereType<String>().toSet()
        : {
            for (final p in achievementProgress(newHistory))
              if (p.earned) p.achievement.id,
          };
    settings = newSettings;
    templates = newTemplates;
    exercises = newExercises;
    history = newHistory;
    cycles = newCycles;
    active = newActive;
    bodyweights = newBodyweights;
    rest = newRest;
    _seenAchievements = newSeen;
  }

  /// A damaged rest timer is dropped: transient state must never make the whole data file unreadable.
  static RestTimer? _tryRest(Object? entry) {
    try {
      return RestTimer.fromJson(entry as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static BodyweightEntry? _tryBodyweight(Object? entry) {
    try {
      return BodyweightEntry.fromJson(entry as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 3,
    'settings': settings.toJson(),
    'templates': templates.map((t) => t.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'history': history.map((s) => s.toJson()).toList(),
    'cycles': cycles.map((c) => c.toJson()).toList(),
    if (bodyweights.isNotEmpty) 'bodyweights': bodyweights.map((e) => e.toJson()).toList(),
    if (_seenAchievements.isNotEmpty) 'seenAchievements': _seenAchievements.toList()..sort(),
    'active': active?.toJson(),
    'rest': rest?.toJson(),
  };

  /// Saves run one after another: an autosave and the save on leaving the app must never write the
  /// temporary file at the same time.
  Future<void> _saving = Future.value();

  Future<void> _persist() => _saving = _saving.then((_) => _write()).catchError((Object e) {
    debugPrint('gymer: save failed: $e');
  });

  /// Set when the unreadable data file could not be copied aside; nothing may overwrite it then.
  bool _writesBlocked = false;

  Future<void> _write() async {
    final file = _file;
    if (file == null || _writesBlocked) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Call after mutating any model object in place.
  void changed() {
    notifyListeners();
    if (_file == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    await _persist();
  }

  void _syncAlerts() {
    alerts.keepAwake(active != null && settings.keepAwake);
    final r = rest;
    final notice = settings.restNotice;
    final alarm = notice == 'alarm' || notice == 'both';
    if (r != null && alarm && !r.overdue) {
      alerts.scheduleRest(r.endsAt, r.exercise);
    } else {
      alerts.cancelRest();
    }
    if (r != null && active != null && (notice == 'live' || notice == 'both')) {
      // With both, the alarm replaces the live timer when rest ends (one notification at a time);
      // the sticky timer alone keeps counting into overtime.
      alerts.showLiveRest(
        r.endsAt,
        r.exercise,
        endAtZero: alarm,
        // Defaults unless the user turned on custom icons (their picks are kept either way).
        icon: settings.customIcons ? settings.restIcon : 'muscle',
        overtimeIcon: settings.customIcons ? settings.overtimeIcon : 'warning',
        chipText: settings.chipMode == 'text' ? settings.chipText : '',
        vibrate: settings.restHaptics,
      );
    } else {
      alerts.clearLiveRest();
    }
  }

  final _planCache = <String, PlatePlan>{};

  // Previous-set and record lookups run on every rebuild of the workout, so
  // they are cached until the history (or the display unit) changes.
  int _historyVersion = 0;
  Object? _historyCacheKey;
  final _previousCache = <String, List<SetEntry>?>{};
  final _bestCache = <(String, SetContext), LiftBest?>{};
  final _comparisonCache = <(String, String, String, String?, DateTime), List<SetEntry>?>{};
  final _progressCache = <(String, bool, String?), List<ExercisePoint>>{};

  static double _tenth(double v) => (v * 10).round() / 10;
}

/// Logged sessions and saved workouts in a backup, decoded off the UI thread; (-1, -1) if unreadable.
/// Top-level so the isolate receives only the text, never the store.
Future<(int, int)> _backupCounts(String text) => Isolate.run(() {
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return ((j['history'] as List?)?.length ?? 0, (j['templates'] as List?)?.length ?? 0);
  } catch (_) {
    return (-1, -1);
  }
});
