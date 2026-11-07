/// Numeric entry rules from the Flet app: arithmetic input, per-kind ranges,
/// display formatting and unusual-value warnings.
library;

import 'dart:math' as math;

final _numberChar = RegExp(r'[0-9.]');

/// Evaluates + - * / with parentheses and unary signs, e.g. "45+45" or
/// "100*0.9". Returns null for anything else, like the Python ast evaluator.
double? evaluateExpression(String? input) {
  final text = (input ?? '').replaceAll('​', '').replaceAll(',', '.').replaceAll(' ', '');
  if (text.isEmpty || text.length > 40) return null;
  var i = 0;

  double? number() {
    final start = i;
    while (i < text.length && _numberChar.hasMatch(text[i])) {
      i++;
    }
    if (start == i) return null;
    return double.tryParse(text.substring(start, i));
  }

  late double? Function() expression;

  double? factor() {
    if (i >= text.length) return null;
    final c = text[i];
    if (c == '+' || c == '-') {
      i++;
      final v = factor();
      return v == null ? null : (c == '-' ? -v : v);
    }
    if (c == '(') {
      i++;
      final v = expression();
      if (v == null || i >= text.length || text[i] != ')') return null;
      i++;
      return v;
    }
    return number();
  }

  double? term() {
    var v = factor();
    while (v != null && i < text.length && (text[i] == '*' || text[i] == '/')) {
      final op = text[i++];
      final r = factor();
      if (r == null || (op == '/' && r == 0)) return null;
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  expression = () {
    var v = term();
    while (v != null && i < text.length && (text[i] == '+' || text[i] == '-')) {
      final op = text[i++];
      final r = term();
      if (r == null) return null;
      v = op == '+' ? v + r : v - r;
    }
    return v;
  };

  final v = expression();
  if (v == null || i != text.length || !v.isFinite || v.abs() > 1000000) return null;
  return v;
}

enum NumKind { weight, load, reps, rir, rm, targetReps, count, seconds }

const _ranges = {
  NumKind.weight: (0.000001, 10000.0, false),
  NumKind.load: (0.0, 10000.0, false),
  NumKind.reps: (1.0, 999.0, true),
  NumKind.rir: (0.0, 99.0, true),
  NumKind.rm: (1.0, 999.0, true),
  NumKind.targetReps: (1.0, 999.0, true),
  NumKind.count: (1.0, 9999.0, true),
  NumKind.seconds: (0.0, 86400.0, true),
};

bool isIntegerKind(NumKind k) => _ranges[k]!.$3;

bool numberAllowed(double v, NumKind kind) {
  final (lo, hi, integer) = _ranges[kind]!;
  if (integer && (v - v.roundToDouble()).abs() > 1e-9) return false;
  return v >= lo && v <= hi;
}

/// Hides two-decimal kg/lb round-trip noise (99.99 → 100, 22.51 → 22.5).
double snapWeight(double v) {
  final half = (v * 2).roundToDouble() / 2;
  return (v - half).abs() <= 0.0110001 ? half : v;
}

String formatNumber(double v, NumKind kind) {
  if (kind == NumKind.weight || kind == NumKind.load) v = snapWeight(v);
  if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Orange-warning reason for a valid but unusual value, or null.
String? unusualReason(NumKind kind, double v, {double? usualWeight}) {
  if (kind == NumKind.reps && v >= 30) return 'Unusually high rep count';
  if (kind == NumKind.rir && v >= 5) return 'Unusually high RIR';
  if (kind == NumKind.weight) {
    if (v >= 1000) return 'Unusually high weight';
    final ref = usualWeight;
    if (ref != null && ref > 0 && (v - ref).abs() >= 10 && (v >= ref * 2 || v <= ref * 0.5)) {
      return 'Large change from your usual weight';
    }
  }
  return null;
}

double median(List<double> v) {
  if (v.isEmpty) throw ArgumentError.value(v, 'v', 'median of no values');
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Seconds or m:ss. Throws FormatException with a user-facing message.
int parseRest(String input) {
  final text = input.trim();
  if (RegExp(r'^\d+:\d{2}$').hasMatch(text)) {
    final [m, s] = text.split(':').map(int.parse).toList();
    if (s >= 60) throw const FormatException('Use seconds or m:ss (seconds must be 00–59).');
    return _boundRest(m * 60 + s);
  }
  if (RegExp(r'^\d+(\.0+)?$').hasMatch(text)) return _boundRest(int.parse(text.split('.').first));
  throw const FormatException('Enter whole seconds or m:ss, for example 90 or 1:30.');
}

int _boundRest(int v) {
  if (v > 86400) throw const FormatException('Rest must be between 0 and 86400 seconds.');
  return v;
}

/// Lenient m:ss/seconds parse with a fallback, like storage.parse_duration.
int parseDuration(String? input, int fallback) {
  try {
    return parseRest(input ?? '');
  } on FormatException {
    return math.max(0, fallback);
  }
}

String formatDuration(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// A whole number with thousands separators, e.g. 12,450.
String groupThousands(double v) {
  final digits = v.round().abs().toString();
  final out = StringBuffer(v.round() < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
