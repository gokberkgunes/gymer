import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/numbers.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Only summary data is rendered: no notes, bodyweight, settings, controls or hidden screen content.
class WorkoutSharing {
  static const channel = MethodChannel('gymer/share');
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> share(FinishSummary summary, ThemeData theme) async {
    if (!available) throw UnsupportedError('Image sharing is available on Android.');
    final png = await renderWorkoutImage(summary, theme);
    await channel.invokeMethod<void>('image', {'png': png, 'title': summary.name});
  }
}

/// Render every result, independently of scroll position, at up to 3× resolution.
Future<Uint8List> renderWorkoutImage(FinishSummary summary, ThemeData theme) async {
  final recorder = ui.PictureRecorder();
  final drawing = _ShareDrawing(Canvas(recorder), theme);
  final height = drawing.paint(summary).ceilToDouble();
  final picture = recorder.endRecording();
  // Keep long workouts within mobile texture and memory limits without cropping their contents.
  final ratio = math.min(3.0, 8192 / math.max(_ShareDrawing.width, height));
  final scaledRecorder = ui.PictureRecorder();
  Canvas(scaledRecorder)
    ..scale(ratio)
    ..drawPicture(picture);
  final scaled = scaledRecorder.endRecording();
  ui.Image? image;
  try {
    image = await scaled.toImage((_ShareDrawing.width * ratio).ceil(), math.min(8192, (height * ratio).ceil()));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not create workout image.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
    scaled.dispose();
  }
}

class _ShareDrawing {
  static const width = 360.0;
  static const margin = 24.0;
  static const content = width - margin * 2;
  final Canvas canvas;
  final ThemeData theme;
  _ShareDrawing(this.canvas, this.theme);
  ColorScheme get cs => theme.colorScheme;

  TextPainter text(
    String value,
    double x,
    double y,
    double maxWidth, {
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.w400,
    int lines = 1,
    TextAlign align = TextAlign.left,
    double spacing = 0,
    bool fit = false,
  }) {
    TextPainter layout(double fontSize) => TextPainter(
      text: TextSpan(
        text: value,
        style: theme.textTheme.bodyMedium!.copyWith(
          fontSize: fontSize,
          height: 1.3,
          color: color ?? cs.onSurface,
          fontWeight: weight,
          letterSpacing: spacing,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: lines,
      ellipsis: '…',
    )..layout(minWidth: align == TextAlign.right ? maxWidth : 0, maxWidth: maxWidth);
    var fontSize = size;
    var painter = layout(fontSize);
    while (fit && painter.didExceedMaxLines && fontSize > 12) {
      painter.dispose();
      painter = layout(--fontSize);
    }
    painter.paint(canvas, Offset(x, y));
    return painter;
  }

  void line(double y) => canvas.drawLine(
    Offset(margin, y),
    Offset(width - margin, y),
    Paint()..color = cs.outlineVariant.withValues(alpha: 0.5),
  );

  double paint(FinishSummary summary) {
    canvas.drawColor(theme.scaffoldBackgroundColor, BlendMode.src);
    text('GYMER', margin, 28, 100, size: 12, spacing: 3, color: cs.primary, weight: FontWeight.w700);
    text(
      fmtShortDate(summary.date),
      144,
      28,
      width - margin - 144,
      size: 12,
      color: cs.onSurfaceVariant,
      align: TextAlign.right,
    );
    var y = 64.0;
    final title = text(summary.name, margin, y, content, size: 28, weight: FontWeight.w700, lines: 2);
    y += title.height + 24;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, y, content, 84),
        Radius.circular(theme.extension<GymerStyle>()?.radius ?? 12),
      ),
      Paint()..color = cs.surfaceContainerHigh,
    );
    final stats = <(String, String)>[
      (
        summary.duration.inHours > 0
            ? '${summary.duration.inHours}h ${summary.duration.inMinutes % 60}m'
            : '${summary.duration.inMinutes} min',
        'TIME',
      ),
      ('${summary.sets}', summary.sets == 1 ? 'SET' : 'SETS'),
      if (summary.volume > 0) (groupThousands(summary.volume), '${summary.unit.toUpperCase()} VOLUME'),
    ];
    final cell = content / stats.length;
    for (final (i, stat) in stats.indexed) {
      final x = margin + i * cell + 12;
      text(stat.$1, x, y + 14, cell - 24, size: 23, weight: FontWeight.w700, fit: true);
      text(stat.$2, x, y + 52, cell - 24, size: 12, color: cs.onSurfaceVariant);
    }
    y += 108;

    if (summary.bests.isNotEmpty) {
      final trophy = Icons.emoji_events_outlined;
      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(trophy.codePoint),
          style: TextStyle(fontFamily: trophy.fontFamily, package: trophy.fontPackage, fontSize: 18, color: cs.primary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(canvas, Offset(margin, y));
      text('PERSONAL BESTS', margin + 26, y + 2, content - 26, size: 12, color: cs.onSurfaceVariant, spacing: 1);
      y += 30;
      for (final best in summary.bests) {
        final name = text(best.exercise, margin, y, content * 0.55, weight: FontWeight.w600, lines: 2);
        final value = text(
          best.value,
          margin + content * 0.58,
          y,
          content * 0.42,
          color: cs.primary,
          weight: FontWeight.w600,
          align: TextAlign.right,
          lines: 2,
        );
        final detailY = y + math.max(20, math.max(name.height, value.height)) + 4;
        text(best.label, margin, detailY, content * 0.6, size: 12, color: cs.onSurfaceVariant);
        text(
          best.gain,
          margin + content * 0.62,
          detailY,
          content * 0.38,
          size: 12,
          color: cs.onSurfaceVariant,
          align: TextAlign.right,
        );
        y = detailY + 34;
      }
      line(y - 8);
      y += 16;
    }

    if (summary.exercises.isNotEmpty) {
      text('EXERCISES', margin, y, content, size: 12, color: cs.onSurfaceVariant, spacing: 1);
      if (summary.exercises.any((e) => e.change != null && e.change!.abs() >= 0.05)) {
        text(
          'EST. 1RM Δ',
          margin + content * 0.6,
          y,
          content * 0.4,
          size: 12,
          color: cs.onSurfaceVariant,
          align: TextAlign.right,
        );
      }
      y += 28;
      for (final exercise in summary.exercises) {
        final name = text(exercise.name, margin, y, content, weight: FontWeight.w600, lines: 2);
        y += name.height + 6;
        final detail =
            '${exercise.sets} ${exercise.sets == 1 ? 'set' : 'sets'}${exercise.best == null ? '' : ' · ${exercise.best}'}';
        final change = exercise.change;
        final showChange = change != null && change.abs() >= 0.05;
        final description = text(
          detail,
          margin,
          y,
          showChange ? content * 0.72 : content,
          size: 12,
          color: cs.onSurfaceVariant,
          lines: 2,
        );
        if (showChange) {
          text(
            '${change > 0 ? '+' : ''}${formatNumber(change, NumKind.weight)} ${summary.unit}',
            margin + content * 0.74,
            y,
            content * 0.26,
            size: 12,
            color: change > 0 ? cs.primary : cs.onSurfaceVariant,
            align: TextAlign.right,
          );
        }
        y += description.height + 20;
      }
    }
    return y + 16;
  }
}
