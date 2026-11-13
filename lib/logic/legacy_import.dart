/// Reads a backup ZIP exported by the Flet app (format "gymer-backup").
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

import '../models.dart';
import 'methods.dart';
import 'progression.dart';

class LegacyData {
  final List<WorkoutTemplate> templates;
  final List<Exercise> exercises;
  final List<Session> history;
  final List<Mesocycle> cycles;
  final void Function(Settings) applySettings;
  final List<String> notes;

  LegacyData({
    required this.templates,
    required this.exercises,
    required this.history,
    required this.cycles,
    required this.applySettings,
    required this.notes,
  });
}

/// RFC 4180 CSV: quoted fields may contain commas, quotes and newlines.
List<Map<String, String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  if (rows.isEmpty) return [];
  final header = rows.first.map((h) => h.trim()).toList();
  return [
    for (final r in rows.skip(1))
      if (r.any((v) => v.trim().isNotEmpty))
        {for (var i = 0; i < header.length; i++) header[i]: i < r.length ? r[i].trim() : ''},
  ];
}

Map<String, String> readBackupZip(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = <String, String>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    files[f.name.split(RegExp(r'[\\/]')).last] = utf8.decode(f.content, allowMalformed: true);
  }
  if (!files.containsKey('workouts.csv') && !files.containsKey('sets.csv')) {
    throw const FormatException('This ZIP is not a GYMER backup.');
  }
  final manifest = files['manifest.json'];
  if (manifest != null) {
    final m = jsonDecode(manifest);
    if (m is! Map || m['format'] != 'gymer-backup') throw const FormatException('Unknown backup format.');
  }
  return files;
}

double? _num(String? v) {
  final d = double.tryParse((v ?? '').trim());
  return d != null && d.isFinite ? d : null;
}

int? _int(String? v) => _num(v)?.round();

String? _text(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();

const _accentNames = {'purple': 0, 'green': 1, 'orange': 2, 'red': 2, 'blue': 3, 'teal': 4, 'pink': 5};

/// Converts a Flet backup. A file with unexpected columns or values gets a plain message instead of a
/// null-check error; nothing has been replaced at this point.
LegacyData convertLegacy(Map<String, String> files) {
  try {
    return _convertLegacy(files);
  } on FormatException {
    rethrow;
  } on Error catch (e) {
    throw FormatException('This backup does not look like a complete GYMER export ($e).');
  }
}

LegacyData _convertLegacy(Map<String, String> files) {
  List<Map<String, String>> csv(String name) => files[name] == null ? const [] : parseCsv(files[name]!);
  final notes = <String>[];
  final s = {for (final r in csv('settings.csv')) r['key']!: r['value'] ?? ''};
  final unitSetting = s['unit'] == 'lb' ? 'lb' : 'kg';

  final details = {for (final r in csv('exercise_details.csv')) r['exercise_name']!: r};
  final names = <String>{for (final r in csv('exercise_catalog.csv')) ?_text(r['exercise_name']), ...details.keys};
  List<String> split(String? v) => [
    for (final m in (v ?? '').split('|'))
      if (m.trim().isNotEmpty) m.trim(),
  ];
  final exercises = [
    for (final n in names)
      () {
        final d = details[n] ?? const <String, String>{};
        final lo = _int(d['straight_rep_min']) ?? 8, hi = _int(d['straight_rep_max']) ?? 12;
        return Exercise(
          name: n,
          primary: split(d['primary_muscles']),
          secondary: split(d['secondary_muscles']),
          equipment: d['equipment_type'] ?? '',
          description: d['description'] ?? '',
          note: d['note'] ?? '',
          loadMode: _text(d['load_mode']) == null ? defaultLoadModeFor(n) : normalizeLoadMode(d['load_mode']),
          incrementKg: _num(d['weight_increment_kg']),
          incrementLb: _num(d['weight_increment_lb']),
          repMin: math.min(lo, hi),
          repMax: math.max(lo, hi),
          autoProgression: d['straight_progression'] != 'manual',
          setSeconds: _int(d['set_seconds']),
          context: _context(d),
        );
      }(),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final setTemplates = <String, List<Map<String, String>>>{};
  for (final r in csv('workout_set_templates.csv')) {
    setTemplates.putIfAbsent('${r['workout_id']}/${r['order_index']}', () => []).add(r);
  }
  final templateRows = <String, List<Map<String, String>>>{};
  for (final r in csv('workout_exercises.csv')) {
    templateRows.putIfAbsent(r['workout_id']!, () => []).add(r);
  }
  final workoutDetails = {for (final r in csv('workout_details.csv')) r['workout_id']!: r};
  int? detail(String id, String key) => _int(workoutDetails[id]?[key]);
  final templates = [
    for (final w in csv('workouts.csv'))
      WorkoutTemplate(
        id: w['workout_id']!,
        name: w['name'] ?? w['workout_id']!,
        description: workoutDetails[w['workout_id']]?['description'] ?? '',
        setSeconds: detail(w['workout_id']!, 'set_seconds') ?? 45,
        setOverhead: detail(w['workout_id']!, 'set_overhead_seconds') ?? 30,
        transition: detail(w['workout_id']!, 'transition_seconds') ?? 300,
        sessionOverhead: detail(w['workout_id']!, 'session_overhead_seconds') ?? 300,
        exercises: [
          for (final r
              in (templateRows[w['workout_id']] ?? <Map<String, String>>[])
                ..sort((a, b) => (_int(a['order_index']) ?? 0).compareTo(_int(b['order_index']) ?? 0)))
            () {
              final method = canonicalMethod(r['training_method']);
              final perSet = (setTemplates['${r['workout_id']}/${r['order_index']}'] ?? <Map<String, String>>[])
                ..sort((a, b) => (_int(a['set_number']) ?? 0).compareTo(_int(b['set_number']) ?? 0));
              final count = _int(r['target_sets']) ?? 3;
              final rest = _int(r['rest_seconds']) ?? 180;
              return TemplateExercise(
                name: r['exercise_name']!,
                method: method,
                sets: perSet.isNotEmpty
                    ? [
                        for (final t in perSet)
                          TemplateSet(
                            type: canonicalSetType(t['set_type']),
                            weight: _weightIn(
                              t['weight'],
                              _text(t['weight_unit']) ?? r['default_weight_unit'],
                              unitSetting,
                            ),
                            reps: _int(t['reps']),
                            rest: _parseRest(t['rest_seconds']) ?? rest,
                            groupStart: t['protocol_group_start'] == '1',
                            context: t['context_override'] == '1' ? _context(t) : null,
                          ),
                      ]
                    : [
                        for (final t in plannedSetTypes(method, warmups: 0, work: count))
                          TemplateSet(type: t, rest: rest),
                      ],
              )..reconcile();
            }(),
        ],
      ),
  ];

  final bySession = <String, List<Map<String, String>>>{};
  var skipped = 0;
  for (final r in csv('sets.csv')) {
    final id = _text(r['session_id']);
    if (id == null || DateTime.tryParse(r['date'] ?? '') == null) {
      skipped++;
      continue;
    }
    bySession.putIfAbsent(id, () => []).add(r);
  }
  if (skipped > 0) notes.add('Skipped $skipped set rows without a session or date.');
  final history = <Session>[];
  for (final MapEntry(key: id, value: rows) in bySession.entries) {
    // A session counts only when at least one set was completed; its unfinished
    // planned rows are kept so History shows what was missed.
    if (!rows.any((r) => r['completed'] != '0')) continue;
    final first = rows.first;
    final unit = (first['weight_unit'] ?? '').trim().toLowerCase() == 'lb' ? 'lb' : 'kg';
    final start = DateTime.parse(first['date']!);
    // The same exercise done twice with different methods (e.g. straight sets then a back-off block)
    // stays two entries instead of being merged and re-sorted together.
    final byExercise = <(String, String), List<Map<String, String>>>{};
    for (final r in rows) {
      byExercise.putIfAbsent((r['exercise_name'] ?? '', canonicalMethod(r['training_method'])), () => []).add(r);
    }
    final seconds = _int(
      first['duration_seconds'] ?? first['session_seconds'] ?? first['elapsed_seconds'] ?? first['clock_seconds'],
    );
    history.add(
      Session(
        id: id,
        templateId: _text(first['workout_id']),
        name: _text(first['workout_name']) ?? 'Workout',
        unit: unit,
        startedAt: start,
        finishedAt: seconds != null && seconds > 0 ? start.add(Duration(seconds: seconds)) : start,
        cycleId: _text(first['cycle_id']),
        microcycle: _int(first['cycle_microcycle']),
        phase: _text(first['cycle_phase']),
        targetRir: _int(first['cycle_target_rir']),
        exercises: [
          for (final MapEntry(key: (name, _), value: sets) in byExercise.entries)
            SessionExercise(
              name: name,
              method: canonicalMethod(sets.first['training_method']),
              loadMode: normalizeLoadMode(sets.first['load_mode']),
              sets: [
                for (final r
                    in sets..sort((a, b) => (_int(a['set_number']) ?? 0).compareTo(_int(b['set_number']) ?? 0)))
                  SetEntry(
                    weight: _weightIn(r['weight'], r['weight_unit'], unit),
                    reps: _int(r['reps']),
                    rir: _int(r['rir']),
                    done: r['completed'] != '0',
                    type: canonicalSetType(r['set_type']),
                    note: r['note'] ?? '',
                    rest: _parseRest(r['rest_seconds']) ?? 180,
                    groupStart: r['protocol_group_start'] == '1',
                    context: _context(r),
                    stopReason: stopReasons.containsKey(r['stop_reason']) ? r['stop_reason']! : '',
                    actualRest: _int(r['actual_rest_seconds']),
                    targetReps: _int(r['target_reps']),
                    targetRir: _int(r['target_rir']),
                  ),
              ],
            ),
        ],
      ),
    );
  }
  history.sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final schedules = <String, Map<int, String>>{};
  for (final r in csv('mesocycle_schedule.csv')) {
    final day = _int(r['day_number']);
    if (day != null && _text(r['workout_id']) != null) {
      schedules.putIfAbsent(r['cycle_id']!, () => {})[day] = r['workout_id']!;
    }
  }
  final events = <String, Map<String, DayEvent>>{};
  for (final r in csv('cycle_day_events.csv')) {
    final planned = DateTime.tryParse(r['planned_date'] ?? '');
    if (planned == null || _text(r['workout_id']) == null) continue;
    events.putIfAbsent(r['cycle_id']!, () => {})[dateKey(planned)] = DayEvent(
      templateId: r['workout_id']!,
      status: const {'planned', 'missed', 'unplanned'}.contains(r['status']) ? r['status']! : 'planned',
      movedTo: DateTime.tryParse(r['moved_to'] ?? ''),
      sessionId: _text(r['session_id']),
    );
  }
  final cycles = <Mesocycle>[];
  for (final r in csv('mesocycles.csv')) {
    if (r['setup_complete'] == '0') continue;
    final start = DateTime.tryParse(r['start_date'] ?? '');
    if (start == null) continue;
    final micro = math.max(1, _int(r['microcycle_days']) ?? 7);
    final value = math.max(1, _int(r['length_value']) ?? 5);
    final lengthUnit = r['length_unit'] ?? 'microcycles';
    final length = lengthUnit == 'microcycles' ? value : ((value * (lengthUnit == 'months' ? 30 : 7)) / micro).ceil();
    final weekRir = <int, int>{};
    try {
      final plan = jsonDecode(r['week_prescriptions']?.isNotEmpty == true ? r['week_prescriptions']! : '{}') as Map;
      for (final e in plan.entries) {
        final rir = _int('${(e.value as Map)['rir'] ?? ''}');
        if (rir != null) weekRir[int.parse('${e.key}')] = rir;
      }
    } catch (_) {
      notes.add('Ignored unreadable weekly RIR overrides for "${r['name']}".');
    }
    cycles.add(
      Mesocycle(
        id: r['cycle_id']!,
        name: r['name'] ?? 'Mesocycle',
        start: start,
        microDays: micro,
        length: length,
        deloadMicro: math.max(0, _int(r['deload_microcycles']) ?? 1),
        startRir: _int(r['start_rir']) ?? 3,
        endRir: _int(r['end_rir']) ?? 1,
        deloadRir: _int(r['deload_rir']) ?? 4,
        deloadManual: r['deload_policy'] == 'manual',
        deloadLoadPct: _int(r['deload_load_percent']) ?? 90,
        deloadVolumePct: _int(r['deload_volume_percent']) ?? 50,
        weekRir: weekRir,
        rirScheduleMode: const {'steady', 'custom'}.contains(r['rir_schedule_mode']) ? r['rir_schedule_mode']! : '',
        rirLock: r['rir_lock'] != '0',
        restLock: r['rest_timer_lock'] == '1',
        active: r['active'] == '1',
        schedule: schedules[r['cycle_id']] ?? {},
        events: events[r['cycle_id']] ?? {},
      ),
    );
  }

  final setTypes = [
    for (final r in csv('set_types.csv'))
      if (_text(r['set_type']) != null) canonicalSetType(r['set_type']),
  ];
  void applySettings(Settings x) {
    bool flag(String k, bool fallback) => s[k] == null ? fallback : s[k] == '1';
    String pick(String k, String fallback, Set<String> allowed) => allowed.contains(s[k]) ? s[k]! : fallback;
    x.unit = unitSetting;
    x.defaultRest = _parseRest(s['default_rest_seconds']) ?? x.defaultRest;
    x.defaultSets = _int(s['default_sets']) ?? x.defaultSets;
    x.trackRir = flag('track_rir', x.trackRir);
    x.haptics = flag('set_haptics', x.haptics);
    x.restHaptics = flag('rest_haptics', x.restHaptics);
    x.keepAwake = flag('keep_screen_awake', x.keepAwake);
    x.showPreviousReps = flag('show_previous_reps', x.showPreviousReps);
    x.dimCompleted = flag('dim_completed_sets', x.dimCompleted);
    x.collapseCompleted = flag('collapse_completed_exercises', x.collapseCompleted);
    x.requirePreviousSet = flag('require_previous_sets_completed', x.requirePreviousSet);
    x.updateFollowingDefaults = flag('update_following_set_defaults', x.updateFollowingDefaults);
    x.enterCompletesSet = flag('enter_completes_set', x.enterCompletesSet);
    x.enterMovesToNextSet = flag('enter_moves_to_next_set', x.enterMovesToNextSet);
    x.backspaceMovesToPreviousSet = flag('backspace_moves_to_previous_set', x.backspaceMovesToPreviousSet);
    x.timerMode = pick('timer_tracker_mode', x.timerMode, {'both', 'floating', 'nearset', 'off'});
    x.plannedRestDisplay = pick('planned_rest_display_mode', x.plannedRestDisplay, {'hide', 'smart', 'always'});
    x.defaultTimerDisplay = pick('default_timer_display_mode', x.defaultTimerDisplay, {'elapsed', 'countdown'});
    x.repMaxTargetReps = _int(s['rep_max_target_reps']) ?? x.repMaxTargetReps;
    if (setTypes.isNotEmpty) x.setTypes = setTypes;
    // Background and corner rounding stay modern; the Flet values would
    // recreate the old look this variant exists to replace.
    x.accent = _accentNames[s['accent_color']] ?? x.accent;
    x.themeMode = pick('theme_mode', x.themeMode, {'system', 'light', 'dark'});
    x.density = pick('density', x.density, {'compact', 'normal', 'roomy'});
    x.setSpacing = _int(s['set_spacing']) ?? x.setSpacing;
    x.fontScale = _num(s['font_scale']) ?? x.fontScale;
    x.uiScale = _num(s['ui_scale']) ?? x.uiScale;
    const equipment = {
      'barbell': 'Barbell',
      'dumbbell': 'Dumbbell',
      'plate_loaded': 'Plate loaded',
      'weight_stack': 'Weight-stack machine',
    };
    for (final MapEntry(key: k, value: label) in equipment.entries) {
      final current = x.increments[label] ?? defaultIncrements[label]!;
      x.increments[label] = (
        _num(s['weight_increment_${k}_kg']) ?? current.$1,
        _num(s['weight_increment_${k}_lb']) ?? current.$2,
      );
    }
    x.normalizeNumeric();
  }

  if (files.containsKey('active_workout.csv') && csv('active_workout.csv').isNotEmpty) {
    notes.add('An unfinished workout in the backup was not imported.');
  }
  return LegacyData(
    templates: templates,
    exercises: exercises,
    history: history,
    cycles: cycles,
    applySettings: applySettings,
    notes: notes,
  );
}

int? _parseRest(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final m = RegExp(r'^(\d+):(\d{2})$').firstMatch(text);
  if (m != null) {
    final seconds = int.parse(m[2]!);
    // As parseRest: "1:75" is not a time; fall back to the default rest instead of reading 135 s.
    return seconds < 60 ? int.parse(m[1]!) * 60 + seconds : null;
  }
  return _int(text);
}

double? _weightIn(String? raw, String? from, String to) {
  final w = _num(raw);
  if (w == null) return null;
  final src = (from ?? '').trim().toLowerCase() == 'lb' ? 'lb' : 'kg';
  return convertWeight(w, src, to);
}

SetContext _context(Map<String, String> r) => SetContext(
  setup: (r['setup'] ?? '').trim(),
  loadBasis: SetContext.loadBasisLabels.containsKey(r['load_convention']) ? r['load_convention']! : '',
  repBasis: SetContext.repBasisLabels.containsKey(r['rep_convention']) ? r['rep_convention']! : '',
  side: SetContext.sideLabels.containsKey(r['side']) ? r['side']! : '',
);
