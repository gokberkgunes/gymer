import 'package:flutter/material.dart';

/// Stable keys for the actions that can be pinned beside an exercise's menu.
const exerciseActions = <(String, String, IconData)>[
  ('repMax', 'Rep max calculator', Icons.calculate_outlined),
  ('rest', 'Rest timers', Icons.timer_outlined),
  ('history', 'History & progress', Icons.show_chart_rounded),
  ('details', 'Exercise details', Icons.info_outline_rounded),
  ('notes', 'Set notes', Icons.notes_rounded),
  ('moveUp', 'Move up', Icons.arrow_upward_rounded),
  ('moveDown', 'Move down', Icons.arrow_downward_rounded),
  ('substitute', 'Substitute exercise', Icons.swap_horiz_rounded),
  ('remove', 'Remove exercise', Icons.delete_outline_rounded),
];

/// Keeps every pinned action on one line, shrinking the controls within a bounded width.
/// Shared by the workout and settings preview so their sizing stays identical.
class ExerciseActionHeader extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final Widget menu;

  const ExerciseActionHeader({super.key, required this.title, required this.actions, required this.menu});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const menuWidth = 28.0;
      final titleWidth = (constraints.maxWidth * 0.36).clamp(96.0, 144.0).toDouble();
      final available = (constraints.maxWidth - titleWidth - menuWidth).clamp(0.0, double.infinity).toDouble();
      final actionWidth = actions.isEmpty ? 0.0 : (available / actions.length).clamp(0.0, 32.0).toDouble();
      final iconSize = (actionWidth - 4).clamp(12.0, 20.0).toDouble();

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          IconButtonTheme(
            data: IconButtonThemeData(
              style: (IconButtonTheme.of(context).style ?? const ButtonStyle()).merge(
                IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  iconSize: iconSize,
                ),
              ),
            ),
            child: IconTheme.merge(
              data: IconThemeData(size: iconSize),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final action in actions) SizedBox(width: actionWidth, height: 44, child: action)],
              ),
            ),
          ),
          SizedBox(
            width: menuWidth,
            height: 44,
            child: IconTheme.merge(data: const IconThemeData(size: 20), child: menu),
          ),
        ],
      );
    },
  );
}
