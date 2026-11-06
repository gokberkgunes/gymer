import 'package:flutter/material.dart';

import '../logic/circuits.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'num_field.dart';

/// Edits only grouping and its shared rest; each exercise keeps its own sets and loads.
Future<bool> editExerciseCircuit(
  BuildContext context, {
  required String exercise,
  required List<String> exercises,
  required List<ExerciseCircuit> circuits,
  required int defaultRest,
  bool restLocked = false,
}) async {
  final current = circuitFor(circuits, exercise);
  final selected = {...?current?.exercises, exercise};
  var rest = current?.rest ?? defaultRest;
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: LabelWithInfo(
          Text(selected.length > 2 ? 'Circuit' : 'Superset'),
          InfoDot(
            tooltip: 'Supersets and circuits',
            onTap: () => showDialog<void>(
              context: dialog,
              builder: (info) => AlertDialog(
                title: const Text('Supersets and circuits'),
                content: const Text(
                  'Alternate one set per exercise, then rest between rounds. '
                  'Two exercises form a superset; three or more form a circuit. '
                  'Drop sets and other protocol groups stay together as one turn. '
                  'Exercises with fewer sets drop out when finished.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(info), child: const Text('Close'))],
              ),
            ),
          ),
        ),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final name in exercises.toSet())
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    value: selected.contains(name),
                    onChanged: name == exercise
                        ? null
                        : (value) => update(() => value == true ? selected.add(name) : selected.remove(name)),
                  ),
                const SizedBox(height: 12),
                DurationField(
                  seconds: rest,
                  label: 'Rest between rounds',
                  readOnly: restLocked,
                  tooltip: restLocked ? 'Rest time is locked by the active mesocycle' : null,
                  onChanged: (value) => rest = value,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (current != null)
            TextButton(onPressed: () => Navigator.pop(dialog, 'unlink'), child: const Text('Unlink')),
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(
            onPressed: selected.length < 2 ? null : () => Navigator.pop(dialog, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return false;
  if (result == 'unlink') {
    current?.exercises.remove(exercise);
  } else {
    // Taking an exercise into this group removes it from its previous group.
    for (final circuit in circuits) {
      if (circuit != current) circuit.exercises.removeWhere(selected.contains);
    }
    if (current != null) {
      current
        ..exercises = exercises.where(selected.contains).toSet().toList()
        ..rest = rest;
    } else {
      circuits.add(
        ExerciseCircuit(
          id: 'G${DateTime.now().microsecondsSinceEpoch}',
          exercises: exercises.where(selected.contains).toSet().toList(),
          rest: rest,
        ),
      );
    }
  }
  reconcileCircuits(circuits, exercises);
  return true;
}

class CircuitPill extends StatelessWidget {
  final List<ExerciseCircuit> circuits;
  final ExerciseCircuit circuit;
  final String exercise;
  final VoidCallback onTap;

  const CircuitPill({
    super.key,
    required this.circuits,
    required this.circuit,
    required this.exercise,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '${circuitDescription(circuit)} ${circuitLetter(circuits, circuit)} · ${circuit.exercises.join(' → ')}',
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: context.style.brSmall,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              circuitBadge(circuits, circuit, exercise),
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
