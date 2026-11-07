import 'dart:math' as math;

import 'logic/methods.dart';
import 'logic/plates.dart';
import 'logic/status_icons.dart';

part 'models/exercise.dart';
part 'models/template.dart';
part 'models/session.dart';
part 'models/cycle.dart';
part 'models/settings.dart';

int? _int(Object? v) => v is int ? v : (v is num ? v.round() : null);
double? _dbl(Object? v) => (v as num?)?.toDouble();

/// A saved plate list; the untouched former default becomes the current default (null).
List<double>? _plates(Object? v, List<double> former) {
  if (v is! List) return null;
  final list = [for (final x in v) (x as num).toDouble()];
  if (list.length != former.length) return list;
  for (var i = 0; i < list.length; i++) {
    if (list[i] != former[i]) return list;
  }
  return null;
}

String _str(Object? v) => v is String ? v : '';

/// Exercise names match ignoring case and surrounding spaces, everywhere: an import or an old rename that
/// differs only in case must never split an exercise's history.
bool sameExercise(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic; Duration(days:) drifts by an hour across DST.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
