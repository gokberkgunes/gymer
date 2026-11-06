// Generated from the Flet app's CSV data.
import '../logic/methods.dart';
import '../models.dart';

const seedExercises = <Exercise>[
  Exercise(
    name: "Bench Press",
    primary: ["Chest"],
    secondary: ["Front Delts", "Triceps"],
    equipment: "Barbell",
    description: "A horizontal barbell press for the chest with assistance from the front delts and triceps.",
  ),
  Exercise(
    name: "Bulgarian Split Squat",
    primary: ["Quads", "Glutes"],
    secondary: [],
    equipment: "Dumbbell",
    description:
        "A rear-foot-elevated unilateral squat. Use a stable stance and controlled depth to train the quads and glutes.",
  ),
  Exercise(
    name: "Cable Crunch",
    primary: ["Abs"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A loaded trunk-flexion movement for the abs. Curl the rib cage toward the pelvis instead of turning it into a hip hinge.",
  ),
  Exercise(
    name: "Cable Fly",
    primary: ["Chest"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A cable chest fly. Keep a consistent elbow angle and bring the upper arms across the torso under control.",
  ),
  Exercise(
    name: "Cable Row",
    primary: ["Back"],
    secondary: ["Biceps", "Rear Delts", "Traps"],
    equipment: "Weight-stack machine",
    description: "A seated cable row for the back with assistance from the biceps, rear delts, and traps.",
  ),
  Exercise(
    name: "Calf Press",
    primary: ["Calves"],
    secondary: [],
    equipment: "Plate loaded",
    description:
        "A loaded plantar-flexion movement for the calves. Use a controlled stretch and full, comfortable contraction rather than bouncing through the bottom.",
  ),
  Exercise(
    name: "Chest Press",
    primary: ["Chest"],
    secondary: ["Front Delts", "Triceps"],
    equipment: "Weight-stack machine",
    description:
        "A machine chest press. Keep the shoulder blades controlled and press through a comfortable chest-focused range.",
  ),
  Exercise(
    name: "Chest-Supported Row",
    primary: ["Back"],
    secondary: ["Biceps", "Rear Delts", "Traps"],
    equipment: "Plate loaded",
    description:
        "A chest-supported horizontal row that limits torso movement and lets the upper back perform the pull with less body English.",
  ),
  Exercise(
    name: "Forearm Curl",
    primary: ["Forearms"],
    secondary: [],
    equipment: "Dumbbell",
    description:
        "A wrist-flexion exercise for the forearms. Keep the forearm supported and move primarily at the wrist with a controlled tempo.",
  ),
  Exercise(
    name: "Hack Squat",
    primary: ["Quads", "Glutes"],
    secondary: [],
    equipment: "Plate loaded",
    description:
        "A guided squat pattern emphasizing the quads and glutes. Use a foot position and depth that remain comfortable and controlled.",
  ),
  Exercise(
    name: "Hammer Curl",
    primary: ["Biceps"],
    secondary: ["Forearms"],
    equipment: "Dumbbell",
    description:
        "A neutral-grip curl emphasizing the elbow flexors and brachioradialis. Avoid swinging the upper arm forward.",
  ),
  Exercise(
    name: "Hip Thrust",
    primary: ["Glutes"],
    secondary: ["Hamstrings"],
    equipment: "Barbell",
    description:
        "A loaded hip-extension exercise with strong glute emphasis. Control the bottom and finish with hip extension rather than lumbar extension.",
  ),
  Exercise(
    name: "Incline Bench Press",
    primary: ["Chest"],
    secondary: ["Front Delts", "Triceps"],
    equipment: "Barbell",
    description:
        "An inclined press emphasizing the clavicular portion of the chest while also training the front delts and triceps.",
  ),
  Exercise(
    name: "Incline Dumbbell Press",
    primary: ["Chest"],
    secondary: ["Front Delts", "Triceps"],
    equipment: "Dumbbell",
    description:
        "An inclined dumbbell press emphasizing the upper chest while also training the front delts and triceps.",
  ),
  Exercise(
    name: "Lat Pulldown",
    primary: ["Back"],
    secondary: ["Biceps"],
    equipment: "Weight-stack machine",
    description:
        "A vertical pulling exercise. Pull the upper arm down toward the torso while keeping the movement controlled and avoiding excessive torso swing.",
  ),
  Exercise(
    name: "Lateral Raise",
    primary: ["Side Delts"],
    secondary: [],
    equipment: "Dumbbell",
    description:
        "A shoulder-abduction isolation exercise. Raise the arm under control and choose a range that keeps tension on the side delts without unnecessary body swing.",
  ),
  Exercise(
    name: "Leg Curl",
    primary: ["Hamstrings"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A knee-flexion isolation exercise for the hamstrings. Use a controlled range and avoid turning the movement into a hip or torso swing.",
  ),
  Exercise(
    name: "Leg Extension",
    primary: ["Quads"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A knee-extension isolation exercise for the quads. Control both directions and use a comfortable full range.",
  ),
  Exercise(
    name: "Leg Press",
    primary: ["Quads", "Glutes"],
    secondary: ["Hamstrings", "Calves"],
    equipment: "Plate loaded",
    description:
        "A machine-based compound leg press. Control the lowering phase, keep your pelvis supported, and use the deepest comfortable range you can control.",
  ),
  Exercise(
    name: "Lying Biceps Curls",
    primary: ["Biceps"],
    secondary: ["Forearms"],
    equipment: "Dumbbell",
    description:
        "An elbow-flexion movement that minimizes body English. Keep the upper arm controlled and use the range that keeps tension on the elbow flexors.",
  ),
  Exercise(
    name: "Machine Row",
    primary: ["Back"],
    secondary: ["Biceps", "Traps", "Rear Delts"],
    equipment: "Weight-stack machine",
    description:
        "A supported horizontal row. Drive the elbows back while keeping the torso stable and let the shoulder blades move naturally through the repetition.",
  ),
  Exercise(
    name: "Overhead Triceps Extension",
    primary: ["Triceps"],
    secondary: [],
    equipment: "Dumbbell",
    description:
        "An elbow-extension movement performed with the arm overhead, placing the long head of the triceps in a lengthened position.",
  ),
  Exercise(
    name: "Preacher Curl",
    primary: ["Biceps"],
    secondary: ["Forearms"],
    equipment: "Weight-stack machine",
    description:
        "A supported elbow-flexion exercise for the biceps. Keep the upper arm planted and control the lengthened position.",
  ),
  Exercise(
    name: "Pull-Up",
    primary: ["Back"],
    secondary: ["Biceps"],
    equipment: "Plate loaded",
    description:
        "A bodyweight vertical pull. Pull the upper arms toward the torso while keeping the movement controlled.",
    loadMode: "bodyweight",
  ),
  Exercise(
    name: "Rear Delt Fly",
    primary: ["Rear Delts"],
    secondary: ["Back"],
    equipment: "Weight-stack machine",
    description:
        "A reverse-fly movement emphasizing the rear delts. Keep the torso stable and move the upper arms outward under control.",
  ),
  Exercise(
    name: "Romanian Deadlift",
    primary: ["Hamstrings", "Glutes"],
    secondary: ["Back"],
    equipment: "Barbell",
    description:
        "A hip hinge emphasizing the hamstrings and glutes. Keep the load close and use the deepest controlled range your hamstrings allow.",
  ),
  Exercise(
    name: "Seated Leg Curl",
    primary: ["Hamstrings"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A seated knee-flexion exercise for the hamstrings, typically training them in a relatively lengthened hip position.",
  ),
  Exercise(
    name: "Seated Shoulder Press",
    primary: ["Front Delts"],
    secondary: ["Triceps"],
    equipment: "Dumbbell",
    description: "A seated overhead press emphasizing the front delts while the triceps assist elbow extension.",
  ),
  Exercise(
    name: "Shrug",
    primary: ["Traps"],
    secondary: [],
    equipment: "Dumbbell",
    description:
        "A loaded scapular-elevation exercise for the traps. Lift and lower the shoulders under control without rolling them around.",
  ),
  Exercise(
    name: "Standing Calf Raise",
    primary: ["Calves"],
    secondary: [],
    equipment: "Plate loaded",
    description:
        "A standing plantar-flexion movement for the calves. Pause through a controlled stretch and contraction instead of bouncing.",
  ),
  Exercise(
    name: "Stiff-Legged Deadlift",
    primary: ["Hamstrings", "Glutes"],
    secondary: ["Back"],
    equipment: "Barbell",
    description:
        "A hip-hinge movement emphasizing the hamstrings. Keep the load close, maintain a controlled torso position, and stop the descent when your available hip range is reached.",
  ),
  Exercise(
    name: "Triceps Pushdown",
    primary: ["Triceps"],
    secondary: [],
    equipment: "Weight-stack machine",
    description:
        "A cable elbow-extension exercise. Keep the upper arms stable and finish each repetition without excessive torso movement.",
  ),
];

List<WorkoutTemplate> seedTemplates() => [
  WorkoutTemplate(
    id: "A",
    name: "Legs",
    exercises: [
      TemplateExercise.typed(
        name: "Leg Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Stiff-Legged Deadlift",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Leg Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Calf Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "B",
    name: "Pull",
    exercises: [
      TemplateExercise.typed(
        name: "Lat Pulldown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Machine Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lying Biceps Curls",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Forearm Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "C",
    name: "Push",
    exercises: [
      TemplateExercise.typed(
        name: "Incline Bench Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Overhead Triceps Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lateral Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_UPPER",
    name: "Upper Body",
    exercises: [
      TemplateExercise.typed(
        name: "Incline Bench Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lat Pulldown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Chest-Supported Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Seated Shoulder Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lateral Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Preacher Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Triceps Pushdown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_LOWER",
    name: "Lower Body",
    exercises: [
      TemplateExercise.typed(
        name: "Hack Squat",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Romanian Deadlift",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Leg Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Leg Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hip Thrust",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Standing Calf Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_QUAD_GLUTE",
    name: "Quads & Glutes",
    exercises: [
      TemplateExercise.typed(
        name: "Hack Squat",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Leg Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Bulgarian Split Squat",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Leg Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hip Thrust",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_HAM_GLUTE",
    name: "Hamstrings & Glutes",
    exercises: [
      TemplateExercise.typed(
        name: "Romanian Deadlift",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Seated Leg Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hip Thrust",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Bulgarian Split Squat",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Calf Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_CHEST_BACK",
    name: "Chest & Back",
    exercises: [
      TemplateExercise.typed(
        name: "Bench Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Incline Dumbbell Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Chest-Supported Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lat Pulldown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Cable Fly",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Machine Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_SHOULDER_ARMS",
    name: "Shoulders & Arms",
    exercises: [
      TemplateExercise.typed(
        name: "Seated Shoulder Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lateral Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Rear Delt Fly",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Preacher Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hammer Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Triceps Pushdown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Overhead Triceps Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_BACK_BICEPS",
    name: "Back & Biceps",
    exercises: [
      TemplateExercise.typed(
        name: "Pull-Up",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lat Pulldown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Chest-Supported Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Cable Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Preacher Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hammer Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_CHEST_TRICEPS",
    name: "Chest & Triceps",
    exercises: [
      TemplateExercise.typed(
        name: "Bench Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Incline Dumbbell Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Chest Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Cable Fly",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Triceps Pushdown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Overhead Triceps Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_FULL_A",
    name: "Full Body A",
    exercises: [
      TemplateExercise.typed(
        name: "Leg Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Romanian Deadlift",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Bench Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lat Pulldown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lateral Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Calf Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Cable Crunch",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_FULL_B",
    name: "Full Body B",
    exercises: [
      TemplateExercise.typed(
        name: "Hack Squat",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hip Thrust",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Incline Dumbbell Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Chest-Supported Row",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Seated Shoulder Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Preacher Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Triceps Pushdown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_ARMS",
    name: "Arms",
    exercises: [
      TemplateExercise.typed(
        name: "Preacher Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Hammer Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lying Biceps Curls",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Triceps Pushdown",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Overhead Triceps Extension",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Forearm Curl",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
  WorkoutTemplate(
    id: "DEF_DELTS_TRAPS",
    name: "Delts & Traps",
    exercises: [
      TemplateExercise.typed(
        name: "Seated Shoulder Press",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Lateral Raise",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Rear Delt Fly",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
      TemplateExercise.typed(
        name: "Shrug",
        method: "Straight",
        rest: 180,
        types: plannedSetTypes("Straight", warmups: 0, work: 3),
      ),
    ],
  ),
];
