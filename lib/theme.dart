import 'package:flutter/material.dart';

import 'models.dart';

const accents = <(String, Color)>[
  ('Violet', Color(0xFF9D8CFF)),
  ('Lime', Color(0xFFC5F24A)),
  ('Coral', Color(0xFFFF8364)),
  ('Sky', Color(0xFF5BB8FF)),
  ('Mint', Color(0xFF4FE0A6)),
  ('Rose', Color(0xFFFF6B9A)),
];

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

/// The accent as used in light mode. The accent also colours text and icons (trophies, gains, pills, the RIR
/// stepper), and the bright accents made for dark mode are unreadable on light surfaces (Lime on white is about
/// 1.3:1). Keep the hue and saturation and lower the lightness until it reaches 4.5:1 (WCAG AA for text) against
/// [against], the darkest light surface it sits on. Dark mode uses the accent unchanged.
Color readableAccent(Color accent, Color against, {double target = 4.5}) {
  var hsl = HSLColor.fromColor(accent);
  while (contrastRatio(hsl.toColor(), against) < target && hsl.lightness > 0.05) {
    hsl = hsl.withLightness(hsl.lightness - 0.01);
  }
  return hsl.toColor();
}

/// (label, dark, light). Presets after 'auto' are carried over from the Flet app.
const backgrounds = <String, (String, Color, Color)>{
  'auto': ('Ink', Color(0xFF0D0E10), Color(0xFFF6F6F4)),
  'charcoal': ('Charcoal', Color(0xFF15171A), Color(0xFFF3F4F6)),
  'default': ('Default', Color(0xFF1C1B1F), Color(0xFFFFFBFE)),
  'black': ('Black', Color(0xFF000000), Color(0xFFFFFFFF)),
  'slate': ('Slate', Color(0xFF20252D), Color(0xFFE9EDF2)),
  'navy': ('Navy', Color(0xFF111827), Color(0xFFEEF2FF)),
};

const densities = {'compact': 0.75, 'normal': 1.0, 'roomy': 1.3};
const _setGapOffset = {'compact': -3, 'normal': 0, 'roomy': 5};

const tabular = [FontFeature.tabularFigures()];

/// The two button heights: 52 for main actions (theme default) and this one
/// for buttons that sit inline in a row, card or top bar.
const compactButton = Size(0, 44);

class GymerStyle extends ThemeExtension<GymerStyle> {
  final double radius;
  final double density;
  final double setGap;
  final bool dimCompleted;

  const GymerStyle({required this.radius, required this.density, required this.setGap, required this.dimCompleted});

  double get small => (radius * 0.66).roundToDouble();
  BorderRadius get br => BorderRadius.circular(radius);
  BorderRadius get brSmall => BorderRadius.circular(small);
  double sp(double v) => v * density;

  /// At set gaps of 0–2 px the set tiles join into one block: only the outer corners stay rounded.
  bool get joinSets => setGap <= 2;

  /// Corner shape of set tile [index] of [count] (workout, editor and the Appearance preview).
  BorderRadius setTile(int index, int count) {
    if (!joinSets) return brSmall;
    final r = Radius.circular(small);
    return BorderRadius.vertical(top: index == 0 ? r : Radius.zero, bottom: index == count - 1 ? r : Radius.zero);
  }

  @override
  GymerStyle copyWith({double? radius, double? density, double? setGap, bool? dimCompleted}) => GymerStyle(
    radius: radius ?? this.radius,
    density: density ?? this.density,
    setGap: setGap ?? this.setGap,
    dimCompleted: dimCompleted ?? this.dimCompleted,
  );

  @override
  GymerStyle lerp(GymerStyle? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Status colours with light and dark variants. Danger is [ColorScheme.error].
extension StatusColors on ColorScheme {
  bool get _dark => brightness == Brightness.dark;
  Color get success => _dark ? const Color(0xFF6FD08C) : const Color(0xFF2E7D32);
  Color get warning => _dark ? const Color(0xFFFFB454) : const Color(0xFFB86200);
  Color get info => _dark ? const Color(0xFF64A8FF) : const Color(0xFF1976D2);
}

extension StyleContext on BuildContext {
  GymerStyle get style => Theme.of(this).extension<GymerStyle>()!;
}

/// Everything in [Settings] that changes the theme, for caching.
Object themeKey(Brightness b, Settings s) =>
    (b, s.accent, s.background, s.rounding, s.density, s.setSpacing, s.dimCompleted);

ThemeData buildTheme(Brightness brightness, Settings s) {
  final dark = brightness == Brightness.dark;
  final chosen = accents[s.accent.clamp(0, accents.length - 1)].$2;
  final preset = backgrounds[s.background] ?? backgrounds['auto']!;
  final bg = dark ? preset.$2 : preset.$3;
  final ink = s.background == 'auto' || !backgrounds.containsKey(s.background);

  final Color surface, surfaceHigh, line;
  if (ink) {
    surface = dark ? const Color(0xFF16181B) : Colors.white;
    surfaceHigh = dark ? const Color(0xFF1F2226) : const Color(0xFFEDEDEA);
    line = dark ? const Color(0xFF26292E) : const Color(0xFFE2E2DE);
  } else if (dark) {
    surface = Color.lerp(bg, Colors.white, 0.05)!;
    surfaceHigh = Color.lerp(bg, Colors.white, 0.10)!;
    line = Color.lerp(bg, Colors.white, 0.13)!;
  } else {
    surface = Color.lerp(bg, Colors.white, 0.75)!;
    surfaceHigh = Color.lerp(bg, Colors.black, 0.05)!;
    line = Color.lerp(bg, Colors.black, 0.10)!;
  }
  final accent = dark ? chosen : readableAccent(chosen, surfaceHigh);
  final text = dark ? const Color(0xFFF2F2F0) : const Color(0xFF111214);
  final muted = dark ? const Color(0xFF8A8F98) : const Color(0xFF6E727A);
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;

  final style = GymerStyle(
    radius: s.rounding.clamp(0, 24).toDouble(),
    density: densities[s.density] ?? 1.0,
    // 0 means exactly 0 at every density; other values get the density offset but never collapse to 0.
    setGap: s.setSpacing <= 0 ? 0 : (s.setSpacing + (_setGapOffset[s.density] ?? 0)).clamp(1, 23).toDouble(),
    dimCompleted: s.dimCompleted,
  );
  final r = style.radius, rs = style.small;
  RoundedRectangleBorder shape(double radius, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,
    error: dark ? const Color(0xFFFF5C5C) : const Color(0xFFD32F2F),
    onError: Colors.white,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    surfaceContainerLowest: bg,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHigh,
    outline: muted,
    outlineVariant: line,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final tt = base.textTheme.apply(bodyColor: text, displayColor: text);

  return base.copyWith(
    extensions: [style],
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: switch (s.density) {
      'compact' => VisualDensity.compact,
      'roomy' => VisualDensity.comfortable,
      _ => VisualDensity.standard,
    },
    textTheme: tt.copyWith(
      displaySmall: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2),
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: tt.labelSmall?.copyWith(color: muted, letterSpacing: 0.8),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.16),
      indicatorShape: shape(rs),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      iconTheme: WidgetStateProperty.resolveWith(
        (st) => IconThemeData(color: st.contains(WidgetState.selected) ? accent : muted),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape(r, BorderSide(color: line)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: line,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(r))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, shape: shape(r)),
    popupMenuTheme: PopupMenuThemeData(color: surfaceHigh, shape: shape(rs)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHigh,
      isDense: true,
      hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: style.sp(12)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(rs), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: shape(r),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: line),
        shape: shape(r),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape(rs),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: shape(rs))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: muted,
        selectedBackgroundColor: accent,
        selectedForegroundColor: onAccent,
        side: BorderSide(color: line),
        shape: shape(rs),
      ),
    ),
    chipTheme: ChipThemeData(shape: shape(rs, BorderSide(color: line))),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: surfaceHigh,
      thumbColor: accent,
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surfaceHigh,
      contentTextStyle: TextStyle(color: text),
      shape: shape(rs),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? onAccent : muted),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? accent : surfaceHigh),
    ),
  );
}
