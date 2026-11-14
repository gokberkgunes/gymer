part of '../store.dart';

/// Import, export and automatic backups.
extension AppStoreBackups on AppStore {
  /// Replaces all data with a Flet backup's contents, after saving a safety copy.
  Future<List<String>> importLegacy(LegacyData d) async {
    final known = {for (final e in d.exercises) e.name.toLowerCase()};
    final missing = <String>{
      for (final t in d.templates)
        for (final e in t.exercises) e.name,
      for (final s in d.history)
        for (final e in s.exercises) e.name,
    }.where((n) => !known.contains(n.toLowerCase()));
    final newExercises = [...d.exercises, for (final n in missing) Exercise(name: n, loadMode: defaultLoadModeFor(n))]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final newSettings = Settings.fromJson(settings.toJson());
    d.applySettings(newSettings);
    await _backupBeforeReplace();
    exercises = newExercises;
    templates = d.templates.isEmpty ? seedTemplates() : d.templates;
    history = d.history;
    _seenAchievements = {
      for (final p in achievementProgress(history))
        if (p.earned) p.achievement.id,
    };
    cycles = d.cycles;
    settings = newSettings;
    active = null;
    rest = null;
    _writesBlocked = false; // the user chose what to keep
    _syncAlerts();
    changed();
    return [
      'Imported ${d.templates.length} workouts, ${d.history.length} sessions and ${d.cycles.length} mesocycles.',
      ...d.notes,
    ];
  }

  Future<void> importJson(String text) async {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('This file is not a Gymer backup.');
    }
    if (j is! Map<String, dynamic> || j['settings'] == null || j['templates'] == null) {
      throw const FormatException('This file is not a Gymer backup.');
    }
    final incoming = AppStore();
    try {
      incoming._fromJson(j);
    } catch (e) {
      // Parse separately so a damaged backup cannot change the current data.
      throw FormatException('This backup is damaged and was not restored ($e).');
    }
    await _backupBeforeReplace();
    settings = incoming.settings;
    templates = incoming.templates;
    exercises = incoming.exercises;
    history = incoming.history;
    cycles = incoming.cycles;
    bodyweights = incoming.bodyweights;
    measurements = incoming.measurements;
    _seenAchievements = incoming._seenAchievements;
    active = incoming.active;
    rest = incoming.rest;
    _writesBlocked = false; // the user chose what to keep
    _syncAlerts();
    changed();
  }

  /// Progress photos live next to the data file, in the app's private storage, named by their date. They are
  /// deliberately outside the JSON data: backups, exports and restores never contain or touch them, and
  /// uninstalling the app removes them.
  Directory? get _photoDir => _file == null ? null : Directory('${_file.parent.path}/photos');

  /// Whether photos can be kept here at all (not in tests or without app storage).
  bool get photosAvailable => _photoDir != null;

  /// All progress photos with their dates, oldest first.
  Future<List<(DateTime, File)>> progressPhotos() async {
    final dir = _photoDir;
    if (dir == null || !await dir.exists()) return [];
    final photos = <(DateTime, File)>[];
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      final date = f is File && name.length >= 10 ? DateTime.tryParse(name.substring(0, 10)) : null;
      if (date != null) photos.add((date, f as File));
    }
    return photos..sort((a, b) => a.$2.path.compareTo(b.$2.path));
  }

  /// Copies a picked image into app storage under [day]. [extension] is kept so the image decodes as it was.
  Future<String?> addProgressPhoto(List<int> bytes, String extension, DateTime day) async {
    final dir = _photoDir;
    if (dir == null) return 'Photos cannot be stored here.';
    if (bytes.isEmpty) return 'That image is empty.';
    final ext = RegExp(r'^[a-zA-Z0-9]{1,5}$').hasMatch(extension) ? extension.toLowerCase() : 'jpg';
    try {
      await dir.create(recursive: true);
      await File('${dir.path}/${dateKey(day)}-${DateTime.now().microsecondsSinceEpoch}.$ext').writeAsBytes(bytes);
      return null;
    } on FileSystemException catch (e) {
      return 'Could not save the photo: ${e.message}';
    }
  }

  Future<void> deleteProgressPhoto(File photo) async {
    final dir = _photoDir;
    // Only ever a file of the photo folder.
    if (dir == null || photo.parent.path != dir.path) return;
    if (await photo.exists()) await photo.delete();
  }

  /// Copies live next to the data file, in the app's private storage.
  Directory? get _backupDir => _file == null ? null : Directory('${_file.parent.path}/backups');

  Future<List<(DateTime, File)>> _backupFiles() async {
    final dir = _backupDir;
    if (dir == null || !await dir.exists()) return [];
    final out = <(DateTime, File)>[];
    await for (final f in dir.list()) {
      final at = f is File ? snapshotTime(f.uri.pathSegments.last) : null;
      if (at != null) out.add((at, f as File));
    }
    return out..sort((a, b) => b.$1.compareTo(a.$1));
  }

  /// Saves a copy of the current data unless it matches the newest copy, then thins older copies with
  /// [snapshotsToKeep]. Queued behind regular saves, and a failure never disturbs the app.
  Future<void> snapshot() => _saving = _saving.then((_) => _snapshot()).catchError((Object e) {
    debugPrint('gymer: automatic backup failed: $e');
  });

  /// A replacement must stop if its safety copy fails. Keep the save queue usable after that failure.
  Future<void> _backupBeforeReplace() async {
    final backup = _saving.then((_) => _snapshot());
    _saving = backup.catchError((Object e) {
      debugPrint('gymer: safety backup failed: $e');
    });
    try {
      await backup;
    } catch (e) {
      throw FileSystemException('Could not save a safety backup. Your current data was not replaced. ($e)');
    }
  }

  Future<void> _snapshot() async {
    final dir = _backupDir;
    if (dir == null) return;
    await dir.create(recursive: true);
    final text = jsonEncode(toJson());
    final existing = await _backupFiles();
    if (existing.isNotEmpty && await existing.first.$2.readAsString() == text) return;
    var now = DateTime.now();
    var target = File('${dir.path}/${snapshotName(now)}');
    // Names have second precision. Never overwrite an earlier recovery point made in the same second.
    while (await target.exists()) {
      now = now.add(const Duration(seconds: 1));
      target = File('${dir.path}/${snapshotName(now)}');
    }
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
    final keep = snapshotsToKeep([snapshotTime(snapshotName(now))!, for (final (at, _) in existing) at]);
    for (final (at, file) in existing) {
      if (!keep.contains(at)) await file.delete();
    }
  }

  /// At launch, one copy a day: skipped when today already has one.
  Future<void> _dailySnapshot() async {
    try {
      final newest = (await _backupFiles()).firstOrNull?.$1;
      final now = DateTime.now();
      if (newest != null && newest.year == now.year && newest.month == now.month && newest.day == now.day) return;
      await snapshot();
    } catch (e) {
      debugPrint('gymer: automatic backup failed: $e');
    }
  }

  /// Every automatic backup, newest first, with its counts read in a background isolate.
  Future<List<BackupInfo>> backups() async => [
    for (final (at, file) in await _backupFiles())
      await () async {
        final (sessions, workouts) = await _backupCounts(await file.readAsString());
        return (at: at, file: file, sessions: sessions, workouts: workouts);
      }(),
  ];

  /// Replaces all data with [file]'s copy, after backing up the current data so this can be undone.
  Future<void> restoreSnapshot(File file) async {
    final text = await file.readAsString();
    await importJson(text);
  }
}
