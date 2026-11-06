/// Retention for automatic backups, in the spirit of ZFS snapshot rotation: recent copies are dense and
/// older ones thin out. Kept are the [recent] newest copies outright (so a second copy taken the same day
/// never pushes out the first), plus the newest copy of each of the last [daily] days, [weekly] weeks
/// (Monday to Sunday) and [monthly] calendar months that have one. Everything else may be deleted.
Set<DateTime> snapshotsToKeep(
  Iterable<DateTime> stamps, {
  int recent = 3,
  int daily = 3,
  int weekly = 4,
  int monthly = 6,
}) {
  final newestFirst = stamps.toList()..sort((a, b) => b.compareTo(a));
  final keep = {...newestFirst.take(recent)};

  void tier(int count, String Function(DateTime) bucket) {
    final seen = <String>{};
    for (final t in newestFirst) {
      final key = bucket(t);
      if (seen.contains(key)) continue;
      if (seen.length == count) break;
      seen.add(key);
      keep.add(t); // newest first, so this is the bucket's latest copy
    }
  }

  tier(daily, (t) => '${t.year}-${t.month}-${t.day}');
  tier(weekly, (t) {
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  });
  tier(monthly, (t) => '${t.year}-${t.month}');
  return keep;
}

/// Backup file name for [t], e.g. gymer-20261104-183012.json (local time, sorts chronologically).
String snapshotName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'gymer-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
}

final _pattern = RegExp(r'^gymer-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.json$');

/// The time encoded in a backup file name, or null for any other file.
DateTime? snapshotTime(String fileName) {
  final m = _pattern.firstMatch(fileName);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}
