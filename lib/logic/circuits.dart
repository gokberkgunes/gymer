import '../models.dart';
import 'methods.dart';

ExerciseCircuit? circuitFor(List<ExerciseCircuit> circuits, String name) =>
    circuits.where((c) => c.exercises.contains(name) && c.exercises.length >= 2).firstOrNull;

List<ExerciseCircuit> copyCircuits(List<ExerciseCircuit> circuits) => [
  for (final c in circuits) ExerciseCircuit.fromJson(c.toJson()),
];

/// Keep membership unique and remove groups which no longer have two exercises.
void reconcileCircuits(List<ExerciseCircuit> circuits, Iterable<String> names) {
  final available = names.toSet();
  final used = <String>{};
  circuits.removeWhere((c) {
    c.exercises = available.where((name) => c.exercises.contains(name) && !used.contains(name)).toList();
    if (c.exercises.length < 2) return true;
    used.addAll(c.exercises);
    return false;
  });
}

void renameCircuitExercise(List<ExerciseCircuit> circuits, String oldName, String newName) {
  for (final c in circuits) {
    c.exercises = [for (final name in c.exercises) name == oldName ? newName : name];
  }
}

String circuitLetter(List<ExerciseCircuit> circuits, ExerciseCircuit circuit) {
  var number = circuits.indexOf(circuit) + 1;
  var label = '';
  while (number > 0) {
    number--;
    label = String.fromCharCode(65 + number % 26) + label;
    number ~/= 26;
  }
  return label;
}

String circuitBadge(List<ExerciseCircuit> circuits, ExerciseCircuit circuit, String name) =>
    '${circuitLetter(circuits, circuit)}${circuit.exercises.indexOf(name) + 1}';

String circuitDescription(ExerciseCircuit circuit) => circuit.exercises.length == 2 ? 'Superset' : 'Circuit';

/// Keep linked cards in one list child so their next set is mounted for scroll navigation.
List<List<SessionExercise>> exerciseBlocks(Session session) {
  final blocks = <List<SessionExercise>>[];
  final visited = <String>{};
  for (final exercise in session.visibleExercises) {
    final circuit = session.warmingUp ? null : circuitFor(session.circuits, exercise.name);
    if (circuit == null) {
      blocks.add([exercise]);
    } else if (visited.add(circuit.id)) {
      blocks.add([for (final name in circuit.exercises) ...session.exercises.where((e) => e.name == name)]);
    }
  }
  return blocks;
}

class WorkoutStep {
  final SessionExercise exercise;
  final int index;
  final int _restAfter;
  final ExerciseCircuit? circuit;
  final int? round;
  final bool endsTurn;

  const WorkoutStep(this.exercise, this.index, this._restAfter, {this.circuit, this.round, this.endsTurn = true});

  SetEntry get set => exercise.sets[index];
  int get restAfter => set.done ? set.circuitRestAfter ?? _restAfter : _restAfter;
}

/// A protocol group is one turn: never alternate away in the middle of drops or mini-sets.
List<List<int>> _turns(SessionExercise exercise) {
  final turns = <List<int>>[];
  for (final (index, set) in exercise.sets.indexed) {
    if (set.warmup) continue;
    if (!isGroupedMethod(exercise.method) || turns.isEmpty || set.groupStart || setRole(set.type) == 'anchor') {
      turns.add([]);
    }
    turns.last.add(index);
  }
  return turns;
}

/// The actual workout order, shared by navigation, rest timers and time estimates.
/// Manual warm-ups precede a circuit; the separate ramp phase passes no circuits.
List<WorkoutStep> workoutSteps(
  List<SessionExercise> exercises,
  List<ExerciseCircuit> circuits, {
  bool hideWarmups = false,
}) {
  final steps = <WorkoutStep>[];
  final visited = <String>{};
  for (final exercise in exercises) {
    final circuit = circuitFor(circuits, exercise.name);
    final members = circuit == null
        ? <SessionExercise>[]
        : [for (final name in circuit.exercises) ...exercises.where((e) => e.name == name)];
    if (circuit == null || members.length < 2) {
      for (final (index, set) in exercise.sets.indexed) {
        if (!hideWarmups || !set.warmup) steps.add(WorkoutStep(exercise, index, set.rest));
      }
      continue;
    }
    if (!visited.add(circuit.id)) continue;
    if (!hideWarmups) {
      for (final member in members) {
        for (final (index, set) in member.sets.indexed) {
          if (set.warmup) steps.add(WorkoutStep(member, index, set.rest));
        }
      }
    }
    final turns = {for (final member in members) member: _turns(member)};
    final roundCount = turns.values.fold<int>(0, (count, turns) => count < turns.length ? turns.length : count);
    for (var round = 0; round < roundCount; round++) {
      final remaining = members.where((member) => round < turns[member]!.length).toList();
      for (final member in remaining) {
        final indices = turns[member]![round];
        for (final index in indices) {
          final endsTurn = index == indices.last;
          steps.add(
            WorkoutStep(
              member,
              index,
              !endsTurn
                  ? member.sets[index].rest
                  : (member == remaining.last && round + 1 < roundCount ? circuit.rest : 0),
              circuit: circuit,
              round: round,
              endsTurn: endsTurn,
            ),
          );
        }
      }
    }
  }
  return steps;
}

List<WorkoutStep> sessionSteps(Session session) => workoutSteps(
  session.visibleExercises,
  session.warmingUp ? [] : session.circuits,
  hideWarmups: !session.warmingUp && session.warmupExercises.isNotEmpty,
);

/// After any member's completion, suggest the earliest unfinished step in that group.
WorkoutStep? nextCircuitStep(Session session, SessionExercise exercise) {
  if (session.warmingUp) return null;
  final circuit = circuitFor(session.circuits, exercise.name);
  if (circuit == null) return null;
  return sessionSteps(session)
      .where((step) => (step.circuit == circuit || circuit.exercises.contains(step.exercise.name)) && !step.set.done)
      .firstOrNull;
}
