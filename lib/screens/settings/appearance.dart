part of '../settings.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    void set(void Function(Settings x) f) => store.updateSettings(f);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: subPageInsets,
        children: [
          const SectionLabel('Colors and theme'),
          _group([
            _row(
              context,
              'Theme',
              _segmented(s.themeMode, const {
                'system': 'Auto',
                'light': 'Light',
                'dark': 'Dark',
              }, (v) => set((x) => x.themeMode = v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Accent', style: t.bodyLarge),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final (i, a) in accents.indexed)
                        _Swatch(
                          color: a.$2,
                          label: a.$1,
                          selected: s.accent == i,
                          onTap: () => set((x) => x.accent = i),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Background', style: t.bodyLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final e in backgrounds.entries)
                        _BackgroundChip(
                          label: e.value.$1,
                          color: dark ? e.value.$2 : e.value.$3,
                          selected: s.background == e.key,
                          onTap: () => set((x) => x.background = e.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]),
          const SectionLabel('Layout'),
          _group([
            _SliderRow(
              title: 'Interface size',
              value: s.uiScale,
              min: 0.7,
              max: 1.2,
              divisions: 10,
              format: (v) => '${v.toStringAsFixed(2)}×',
              onChanged: (v) => set((x) => x.uiScale = v),
            ),
            _SliderRow(
              title: 'Font size',
              value: s.fontScale,
              min: 0.8,
              max: 1.4,
              divisions: 6,
              format: (v) => '${v.toStringAsFixed(2)}×',
              onChanged: (v) => set((x) => x.fontScale = v),
            ),
            _SliderRow(
              title: 'Roundedness',
              value: s.rounding.toDouble(),
              min: 0,
              max: 24,
              divisions: 6,
              format: (v) => v == 0 ? 'Sharp' : '${v.round()} px',
              onChanged: (v) => set((x) => x.rounding = v.round()),
            ),
            _row(
              context,
              'Density',
              _segmented(s.density, const {
                'compact': 'Compact',
                'normal': 'Normal',
                'roomy': 'Roomy',
              }, (v) => set((x) => x.density = v)),
            ),
            _SliderRow(
              title: 'Set spacing',
              subtitle: 'Effective gap ${st.setGap.round()} px with ${s.density} density',
              value: s.setSpacing.toDouble(),
              min: 0,
              max: 18,
              divisions: 18,
              format: (v) => '${v.round()} px',
              onChanged: (v) => set((x) => x.setSpacing = v.round()),
            ),
            _row(
              context,
              'Dim completed sets',
              Switch(value: s.dimCompleted, onChanged: (v) => set((x) => x.dimCompleted = v)),
            ),
          ]),
          const SectionLabel('Warm-up appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _segmented(
                s.warmupAppearance,
                const {'fire': 'Fire', 'embers': 'Embers', 'heat': 'Heat', 'stripes': 'Stripes', 'plain': 'Plain'},
                (v) => set((x) => x.warmupAppearance = v),
                expand: true,
                compact: true,
              ),
            ),
          ),
          const SectionLabel('Preview'),
          _SetPreview(warmupStyle: s.warmupAppearance),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => set((x) => x.resetAppearance()),
            child: Text('Reset appearance', style: TextStyle(color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(context.style.radius.clamp(0, 18)),
            border: Border.all(
              color: selected ? cs.onSurface : Colors.transparent,
              width: 2.5,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _BackgroundChip({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    return InkWell(
      onTap: onTap,
      borderRadius: st.brSmall,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          borderRadius: st.brSmall,
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(st.small.clamp(0, 11)),
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _SetPreview extends StatelessWidget {
  final Widget? header;
  final String? warmupStyle;
  const _SetPreview({this.header, this.warmupStyle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;
    final warmup = warmupStyle != null;

    // Mirrors the workout screen's set rows: same tile colours, input boxes and rounded-square check.
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, Colors.white, 0.07)
        : cs.surface;
    Widget box(String text, bool done) => Expanded(
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: done ? null : fieldFill, borderRadius: st.brSmall),
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular),
        ),
      ),
    );
    Widget setRow(int n, String w, String r, String rir, bool done) => Container(
      margin: EdgeInsets.symmetric(vertical: st.setGap / 2),
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: st.sp(2) + 2),
      decoration: BoxDecoration(
        color: done
            ? warmup
                  ? Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.surface)
                  : cs.primary.withValues(alpha: 0.12)
            : cs.surfaceContainerHigh,
        borderRadius: st.setTile(n - 1, 3),
      ),
      child: Opacity(
        opacity: done && st.dimCompleted ? 0.55 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                warmup ? 'W$n' : '$n',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            box(w, done),
            const SizedBox(width: 6),
            box(r, done),
            const SizedBox(width: 6),
            if (warmup) const Expanded(child: SizedBox.shrink()) else box(rir, done),
            SizedBox(
              width: 48,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: done ? cs.primary : null,
                    border: Border.all(color: done ? cs.primary : cs.outline, width: 2),
                    borderRadius: BorderRadius.circular(st.small.clamp(0, 10)),
                  ),
                  child: done ? Icon(Icons.check_rounded, size: 20, color: cs.onPrimary) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: WarmupBackground(
        active: warmup,
        style: warmupStyle ?? 'plain',
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, st.sp(14), 12, st.sp(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header ??
                  Row(
                    children: [
                      Text('Bench Press', style: t.titleMedium),
                      if (warmup) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.local_fire_department_outlined, size: 16, color: cs.primary),
                      ],
                    ],
                  ),
              SizedBox(height: st.sp(8)),
              setRow(1, warmup ? '40' : '80', '8', '2', true),
              setRow(2, warmup ? '60' : '80', warmup ? '5' : '7', '1', !warmup),
              setRow(3, '80', warmup ? '3' : '8', '2', false),
            ],
          ),
        ),
      ),
    );
  }
}
