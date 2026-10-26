import csv
import hashlib
import io
import json
import os
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from functools import wraps

import volume_landmarks
import backup_validation
import numeric_input
import set_context
import csv_transactions
import load_modes
import progression
import protocols
import deloads
import volume_accounting
import rest_timer_state


DATA_DIR = Path(os.environ.get("FLET_APP_STORAGE_DATA") or ".").resolve()

WORKOUTS_FILE = DATA_DIR / "workouts.csv"
WORKOUT_EXERCISES_FILE = DATA_DIR / "workout_exercises.csv"
WORKOUT_SET_TEMPLATES_FILE = DATA_DIR / "workout_set_templates.csv"
SETS_FILE = DATA_DIR / "sets.csv"
SETTINGS_FILE = DATA_DIR / "settings.csv"
ACTIVE_WORKOUT_FILE = DATA_DIR / "active_workout.csv"
EXERCISE_CATALOG_FILE = DATA_DIR / "exercise_catalog.csv"
SET_TYPES_FILE = DATA_DIR / "set_types.csv"
EXERCISE_DETAILS_FILE = DATA_DIR / "exercise_details.csv"
WORKOUT_DETAILS_FILE = DATA_DIR / "workout_details.csv"
MESOCYCLES_FILE = DATA_DIR / "mesocycles.csv"
MESOCYCLE_SCHEDULE_FILE = DATA_DIR / "mesocycle_schedule.csv"

# Human-readable backup format: every user-data CSV is stored directly in a
# single ZIP. Per-set templates contain user-authored program data.
BACKUP_DATA_FILES = [
    WORKOUTS_FILE,
    WORKOUT_EXERCISES_FILE,
    WORKOUT_SET_TEMPLATES_FILE,
    SETS_FILE,
    SETTINGS_FILE,
    ACTIVE_WORKOUT_FILE,
    EXERCISE_CATALOG_FILE,
    SET_TYPES_FILE,
    EXERCISE_DETAILS_FILE,
    WORKOUT_DETAILS_FILE,
    MESOCYCLES_FILE,
    MESOCYCLE_SCHEDULE_FILE,
]


WORKOUT_FIELDS = ["workout_id", "name"]

# Keep legacy/default columns so existing files migrate safely.
EXERCISE_FIELDS = [
    "workout_id",
    "order_index",
    "exercise_name",
    "target_sets",
    "default_weight",
    "default_weight_unit",
    "default_reps",
    "rest_seconds",
    "training_method",
]

TEMPLATE_SET_FIELDS = [
    "workout_id",
    "order_index",
    "set_number",
    "weight",
    "weight_unit",
    "reps",
    "rest_seconds",
    "set_type",
    "protocol_group_start",
    "context_override",
    *set_context.FIELDS,
]

SET_FIELDS = [
    "session_id",
    "date",
    "workout_id",
    "workout_name",
    "cycle_id",
    "cycle_microcycle",
    "exercise_name",
    "set_number",
    "weight",
    "weight_unit",
    "reps",
    "rir",
    "target_rir",
    "legacy_rir",
    "load_mode",
    "set_type",
    "training_method",
    "note",
    "completed",
    "rest_seconds",
    *protocols.FIELDS,
    *deloads.FIELDS,
    *volume_accounting.FIELDS,
]

SETTING_FIELDS = ["key", "value"]
CATALOG_FIELDS = ["exercise_name"]
SET_TYPE_FIELDS = ["set_type"]
EXERCISE_DETAIL_FIELDS = [
    *set_context.FIELDS,
    "exercise_name",
    "muscle_groups",
    "primary_muscles",
    "secondary_muscles",
    "description",
    "note",
    "set_seconds",
    "equipment_type",
    "weight_increment_lb",
    "weight_increment_kg",
    "load_mode",
    "straight_rep_min",
    "straight_rep_max",
    "straight_progression",
]
WORKOUT_DETAIL_FIELDS = [
    "workout_id",
    "description",
    "note",
    "set_seconds",
    "set_overhead_seconds",
    "transition_seconds",
    "session_overhead_seconds",
]
MESOCYCLE_FIELDS = [
    "cycle_id",
    "name",
    "start_date",
    "microcycle_days",
    "length_value",
    "length_unit",
    "deload_microcycles",
    "start_rir",
    "end_rir",
    "deload_rir",
    "deload_policy",
    "deload_load_percent",
    "deload_volume_percent",
    "rir_lock",
    "rest_timer_lock",
    "show_last_week_reps",
    "setup_complete",
    "active",
]

MESOCYCLE_SCHEDULE_FIELDS = [
    "cycle_id",
    "day_number",
    "workout_id",
]

ACTIVE_FIELDS = [
    "session_id",
    "performed_at",
    "cycle_id",
    "cycle_microcycle",
    "cycle_phase",
    "cycle_target_rir",
    "workout_id",
    "workout_name",
    "exercise_name",
    "set_number",
    "weight",
    "weight_unit",
    "reps",
    "rir",
    "target_rir",
    "legacy_rir",
    "load_mode",
    "previous_weight",
    "previous_reps",
    "previous_rir",
    "last_week_reps",
    "set_type",
    "training_method",
    "note",
    "completed",
    "calibration_done",
    "rest_seconds",
    "started_at",
    "timer_started",
    "timer_elapsed_seconds",
    "rest_timer_state",
    *protocols.FIELDS,
    *deloads.FIELDS,
    *volume_accounting.FIELDS,
]

# Equipment categories drive realistic progression rounding. The category gives
# a sensible default, while every exercise may override its own available jump.
EQUIPMENT_TYPES = [
    "Barbell",
    "Dumbbell",
    "Plate loaded",
    "Weight-stack machine",
]

# Defaults are intentionally unit-specific rather than converted between kg/lb.
# A gym using metric plates commonly has different available jumps than a gym
# using imperial plates. Values are total logged-weight changes; dumbbell values
# are per dumbbell because that is how GYMER records a dumbbell load.
DEFAULT_WEIGHT_INCREMENTS = {
    "Barbell": {"lb": 10.0, "kg": 5.0},
    "Dumbbell": {"lb": 5.0, "kg": 2.5},
    "Plate loaded": {"lb": 10.0, "kg": 5.0},
    "Weight-stack machine": {"lb": 10.0, "kg": 5.0},
}

# Best-effort defaults for the bundled exercise database. Exercise Details always
# lets the user change these because the same exercise name can use different
# equipment in different gyms.
DEFAULT_EXERCISE_EQUIPMENT = {
    "Leg Press": "Plate loaded",
    "Stiff-Legged Deadlift": "Barbell",
    "Leg Curl": "Weight-stack machine",
    "Calf Press": "Plate loaded",
    "Lat Pulldown": "Weight-stack machine",
    "Machine Row": "Weight-stack machine",
    "Lying Biceps Curls": "Dumbbell",
    "Forearm Curl": "Dumbbell",
    "Incline Bench Press": "Barbell",
    "Overhead Triceps Extension": "Dumbbell",
    "Lateral Raise": "Dumbbell",
}

DEFAULT_EXERCISE_EQUIPMENT.update({
    "Romanian Deadlift": "Barbell",
    "Leg Extension": "Weight-stack machine",
    "Standing Calf Raise": "Plate loaded",
    "Chest-Supported Row": "Plate loaded",
    "Preacher Curl": "Weight-stack machine",
    "Hammer Curl": "Dumbbell",
    "Chest Press": "Weight-stack machine",
    "Seated Shoulder Press": "Dumbbell",
    "Triceps Pushdown": "Weight-stack machine",
    "Hack Squat": "Plate loaded",
    "Hip Thrust": "Barbell",
    "Bulgarian Split Squat": "Dumbbell",
    "Seated Leg Curl": "Weight-stack machine",
    "Bench Press": "Barbell",
    "Incline Dumbbell Press": "Dumbbell",
    "Cable Fly": "Weight-stack machine",
    "Rear Delt Fly": "Weight-stack machine",
    "Pull-Up": "Plate loaded",
    "Cable Row": "Weight-stack machine",
    "Cable Crunch": "Weight-stack machine",
    "Shrug": "Dumbbell",
})

def _equipment_setting_slug(equipment_type):
    # Keep the historic weight_stack key so existing user settings migrate
    # without changing their saved increment. Unsupported/blank equipment
    # uses the old hidden generic key as a fallback, but it is no longer
    # exposed as an equipment choice in the UI.
    return {
        "Barbell": "barbell",
        "Dumbbell": "dumbbell",
        "Plate loaded": "plate_loaded",
        "Weight-stack machine": "weight_stack",
    }.get(equipment_type, "other")


def normalize_equipment_type(value):
    text = str(value or "").strip()
    aliases = {
        "selectorized": "Weight-stack machine",
        "selectorized machine": "Weight-stack machine",
        "weight stack": "Weight-stack machine",
        "weight stack (pin)": "Weight-stack machine",
        "pin loaded machine": "Weight-stack machine",
        "pin-loaded": "Weight-stack machine",
        "cable": "Weight-stack machine",
        "plate-loaded": "Plate loaded",
        # Retired catch-all values intentionally become unassigned.
        "other": "",
        "other / custom": "",
        "custom": "",
    }
    folded = text.casefold()
    if folded in aliases:
        return aliases[folded]
    for name in EQUIPMENT_TYPES:
        if folded == name.casefold():
            return name
    return ""


def weight_increment_setting_key(equipment_type, unit):
    unit = "lb" if str(unit or "kg").strip().lower() == "lb" else "kg"
    return f"weight_increment_{_equipment_setting_slug(normalize_equipment_type(equipment_type))}_{unit}"


def default_weight_increment(equipment_type, unit):
    equipment_type = normalize_equipment_type(equipment_type)
    unit = "lb" if str(unit or "kg").strip().lower() == "lb" else "kg"
    if equipment_type in DEFAULT_WEIGHT_INCREMENTS:
        return DEFAULT_WEIGHT_INCREMENTS[equipment_type][unit]
    # Hidden fallback for legacy/custom exercises whose equipment has not yet
    # been assigned to one of the four supported categories.
    return 5.0 if unit == "lb" else 2.5


def format_increment(value):
    value = float(value)
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.2f}".rstrip("0").rstrip(".")

DEFAULT_SETTINGS = {
    "unit": "kg",
    "default_sets": "3",
    "default_rest_seconds": "180",
    "weight_increment_barbell_lb": "10",
    "weight_increment_barbell_kg": "5",
    "weight_increment_dumbbell_lb": "5",
    "weight_increment_dumbbell_kg": "2.5",
    "weight_increment_plate_loaded_lb": "10",
    "weight_increment_plate_loaded_kg": "5",
    "weight_increment_weight_stack_lb": "10",
    "weight_increment_weight_stack_kg": "5",
    "search_mode": "fuzzy",
    "accent_color": "purple",
    "font_scale": "1.0",
    "rounding": "0",
    "background_color": "auto",
    "theme_mode": "system",
    "density": "normal",
    "show_recent": "1",
    "set_spacing": "3",
    "hide_status_bar": "0",
    "track_rir": "1",
    "dim_completed_sets": "1",
    "collapse_completed_exercises": "1",
    "timer_tracker_mode": "both",
    "show_rest_time_near_sets": "1",
    "planned_rest_display_mode": "hide",
    "update_following_set_defaults": "0",
    "rep_max_target_reps": "8",
    "advanced_rep_max_mode": "0",
    "enter_completes_set": "1",
    "enter_moves_to_next_set": "0",
    "backspace_moves_to_previous_set": "0",
    "advanced_mode": "0",
    "require_previous_sets_completed": "0",
    "default_timer_display_mode": "elapsed",
    # JSON map: cycle_id -> calibrated workout/exercise placements.
    # A repeated exercise in another workout calibrates independently.
    "mesocycle_intro_seen_exercises": "{}",
    # Historical reps are hidden during a mesocycle unless Advanced Mode opts in.
    "show_previous_reps": "0",
    "ui_revision": "12",
}

# Common app tags plus useful hypertrophy/strength techniques.
DEFAULT_SET_TYPES = [
    "Normal",
    "Warm-up",
    "Top Set",
    "Back-off",
    "AMRAP",
    "Failure",
    "Drop Set",
    "Mechanical Drop Set",
    "Rest-Pause",
    "Myo-Reps",
    "Activation",
    "Myo-set",
    "Myo-Rep Match",
    "Cluster Set",
    "Paused",
    "Tempo",
    "Partial",
    "Burnout",
]

# Training method belongs to an exercise *inside a workout*.  Set type is now a
# role/segment inside that method, so incompatible combinations can be blocked.
TRAINING_METHODS = [
    "Straight",
    "AMRAP",
    "Myo-Reps",
    "Rest-Pause",
    "Drop Set",
    "Mechanical Drop Set",
    "Cluster",
    "Myo-Rep Match",
]

METHOD_SET_TYPES = {
    "Straight": ["Normal", "Warm-up", "Top Set", "Back-off"],
    "AMRAP": ["Warm-up", "AMRAP"],
    "Myo-Reps": ["Warm-up", "Activation", "Myo-set"],
    "Rest-Pause": ["Warm-up", "Activation", "Rest-Pause"],
    "Drop Set": ["Warm-up", "Activation", "Drop Set"],
    "Mechanical Drop Set": ["Warm-up", "Activation", "Mechanical Drop Set"],
    "Cluster": ["Warm-up", "Cluster Set"],
    "Myo-Rep Match": ["Warm-up", "Activation", "Myo-Rep Match"],
}

ACTIVATION_FOLLOWUP = {
    "Myo-Reps": "Myo-set",
    "Rest-Pause": "Rest-Pause",
    "Drop Set": "Drop Set",
    "Mechanical Drop Set": "Mechanical Drop Set",
    "Myo-Rep Match": "Myo-Rep Match",
}

DEFAULT_WORKOUTS = [
    (
        "A",
        "Legs",
        ["Leg Press", "Stiff-Legged Deadlift", "Leg Curl", "Calf Press"],
    ),
    (
        "B",
        "Pull",
        ["Lat Pulldown", "Machine Row", "Lying Biceps Curls", "Forearm Curl"],
    ),
    (
        "C",
        "Push",
        ["Incline Bench Press", "Overhead Triceps Extension", "Lateral Raise"],
    ),
    (
        "DEF_UPPER",
        "Upper Body",
        [
            "Incline Bench Press",
            "Lat Pulldown",
            "Chest-Supported Row",
            "Seated Shoulder Press",
            "Lateral Raise",
            "Preacher Curl",
            "Triceps Pushdown",
        ],
    ),
    (
        "DEF_LOWER",
        "Lower Body",
        [
            "Hack Squat",
            "Romanian Deadlift",
            "Leg Curl",
            "Leg Extension",
            "Hip Thrust",
            "Standing Calf Raise",
        ],
    ),
    (
        "DEF_QUAD_GLUTE",
        "Quads & Glutes",
        [
            "Hack Squat",
            "Leg Press",
            "Bulgarian Split Squat",
            "Leg Extension",
            "Hip Thrust",
        ],
    ),
    (
        "DEF_HAM_GLUTE",
        "Hamstrings & Glutes",
        [
            "Romanian Deadlift",
            "Seated Leg Curl",
            "Hip Thrust",
            "Bulgarian Split Squat",
            "Calf Press",
        ],
    ),
    (
        "DEF_CHEST_BACK",
        "Chest & Back",
        [
            "Bench Press",
            "Incline Dumbbell Press",
            "Chest-Supported Row",
            "Lat Pulldown",
            "Cable Fly",
            "Machine Row",
        ],
    ),
    (
        "DEF_SHOULDER_ARMS",
        "Shoulders & Arms",
        [
            "Seated Shoulder Press",
            "Lateral Raise",
            "Rear Delt Fly",
            "Preacher Curl",
            "Hammer Curl",
            "Triceps Pushdown",
            "Overhead Triceps Extension",
        ],
    ),
    (
        "DEF_BACK_BICEPS",
        "Back & Biceps",
        [
            "Pull-Up",
            "Lat Pulldown",
            "Chest-Supported Row",
            "Cable Row",
            "Preacher Curl",
            "Hammer Curl",
        ],
    ),
    (
        "DEF_CHEST_TRICEPS",
        "Chest & Triceps",
        [
            "Bench Press",
            "Incline Dumbbell Press",
            "Chest Press",
            "Cable Fly",
            "Triceps Pushdown",
            "Overhead Triceps Extension",
        ],
    ),
    (
        "DEF_FULL_A",
        "Full Body A",
        [
            "Leg Press",
            "Romanian Deadlift",
            "Bench Press",
            "Lat Pulldown",
            "Lateral Raise",
            "Calf Press",
            "Cable Crunch",
        ],
    ),
    (
        "DEF_FULL_B",
        "Full Body B",
        [
            "Hack Squat",
            "Hip Thrust",
            "Incline Dumbbell Press",
            "Chest-Supported Row",
            "Seated Shoulder Press",
            "Preacher Curl",
            "Triceps Pushdown",
        ],
    ),
    (
        "DEF_ARMS",
        "Arms",
        [
            "Preacher Curl",
            "Hammer Curl",
            "Lying Biceps Curls",
            "Triceps Pushdown",
            "Overhead Triceps Extension",
            "Forearm Curl",
        ],
    ),
    (
        "DEF_DELTS_TRAPS",
        "Delts & Traps",
        [
            "Seated Shoulder Press",
            "Lateral Raise",
            "Rear Delt Fly",
            "Shrug",
        ],
    ),
]

# Increment this only when shipping a new bundled workout pack. Existing users
# receive newly added defaults once, but deleting a default workout later does
# not make it reappear on every launch.
DEFAULT_WORKOUT_PACK_REVISION = 2

# Use the same muscle taxonomy as the RP hypertrophy volume landmarks shown in
# Gymer. Keeping exercise tagging and volume reporting on one vocabulary avoids
# hidden mappings such as Lats + Mid Back -> Back or one generic Shoulders row.
RP_MUSCLE_GROUPS = [
    "Back",
    "Quads",
    "Hamstrings",
    "Glutes",
    "Chest",
    "Front Delts",
    "Side Delts",
    "Rear Delts",
    "Biceps",
    "Triceps",
    "Calves",
    "Abs",
    "Traps",
    "Forearms",
]

# Compatibility name used throughout the UI. The values themselves are now the
# RP groups above.
BODYBUILDING_MUSCLE_GROUPS = RP_MUSCLE_GROUPS

DEFAULT_EXERCISE_DETAILS = {
    "Leg Press": {
        "muscle_groups": "Quads, Glutes; Hamstrings and Calves assist",
        "primary_muscles": "Quads|Glutes",
        "secondary_muscles": "Hamstrings|Calves",
        "description": "A machine-based compound leg press. Control the lowering phase, keep your pelvis supported, and use the deepest comfortable range you can control.",
    },
    "Stiff-Legged Deadlift": {
        "muscle_groups": "Hamstrings, Glutes; Back assists",
        "primary_muscles": "Hamstrings|Glutes",
        "secondary_muscles": "Back",
        "description": "A hip-hinge movement emphasizing the hamstrings. Keep the load close, maintain a controlled torso position, and stop the descent when your available hip range is reached.",
    },
    "Leg Curl": {
        "muscle_groups": "Hamstrings",
        "primary_muscles": "Hamstrings",
        "secondary_muscles": "",
        "description": "A knee-flexion isolation exercise for the hamstrings. Use a controlled range and avoid turning the movement into a hip or torso swing.",
    },
    "Calf Press": {
        "muscle_groups": "Calves",
        "primary_muscles": "Calves",
        "secondary_muscles": "",
        "description": "A loaded plantar-flexion movement for the calves. Use a controlled stretch and full, comfortable contraction rather than bouncing through the bottom.",
    },
    "Lat Pulldown": {
        "muscle_groups": "Back, Biceps",
        "primary_muscles": "Back",
        "secondary_muscles": "Biceps",
        "description": "A vertical pulling exercise. Pull the upper arm down toward the torso while keeping the movement controlled and avoiding excessive torso swing.",
    },
    "Machine Row": {
        "muscle_groups": "Back, Biceps, Traps, Rear Delts",
        "primary_muscles": "Back",
        "secondary_muscles": "Biceps|Traps|Rear Delts",
        "description": "A supported horizontal row. Drive the elbows back while keeping the torso stable and let the shoulder blades move naturally through the repetition.",
    },
    "Lying Biceps Curls": {
        "muscle_groups": "Biceps, Forearms",
        "primary_muscles": "Biceps",
        "secondary_muscles": "Forearms",
        "description": "An elbow-flexion movement that minimizes body English. Keep the upper arm controlled and use the range that keeps tension on the elbow flexors.",
    },
    "Forearm Curl": {
        "muscle_groups": "Forearms",
        "primary_muscles": "Forearms",
        "secondary_muscles": "",
        "description": "A wrist-flexion exercise for the forearms. Keep the forearm supported and move primarily at the wrist with a controlled tempo.",
    },
    "Incline Bench Press": {
        "muscle_groups": "Chest, Front Delts, Triceps",
        "primary_muscles": "Chest",
        "secondary_muscles": "Front Delts|Triceps",
        "description": "An inclined press emphasizing the clavicular portion of the chest while also training the front delts and triceps.",
    },
    "Overhead Triceps Extension": {
        "muscle_groups": "Triceps",
        "primary_muscles": "Triceps",
        "secondary_muscles": "",
        "description": "An elbow-extension movement performed with the arm overhead, placing the long head of the triceps in a lengthened position.",
    },
    "Lateral Raise": {
        "muscle_groups": "Side Delts",
        "primary_muscles": "Side Delts",
        "secondary_muscles": "",
        "description": "A shoulder-abduction isolation exercise. Raise the arm under control and choose a range that keeps tension on the side delts without unnecessary body swing.",
    },
}

DEFAULT_EXERCISE_DETAILS.update({
    "Romanian Deadlift": {
        "muscle_groups": "Hamstrings, Glutes, Back",
        "primary_muscles": "Hamstrings|Glutes",
        "secondary_muscles": "Back",
        "description": "A hip hinge emphasizing the hamstrings and glutes. Keep the load close and use the deepest controlled range your hamstrings allow.",
    },
    "Leg Extension": {
        "muscle_groups": "Quads",
        "primary_muscles": "Quads",
        "secondary_muscles": "",
        "description": "A knee-extension isolation exercise for the quads. Control both directions and use a comfortable full range.",
    },
    "Standing Calf Raise": {
        "muscle_groups": "Calves",
        "primary_muscles": "Calves",
        "secondary_muscles": "",
        "description": "A standing plantar-flexion movement for the calves. Pause through a controlled stretch and contraction instead of bouncing.",
    },
    "Chest-Supported Row": {
        "muscle_groups": "Back, Biceps, Rear Delts, Traps",
        "primary_muscles": "Back",
        "secondary_muscles": "Biceps|Rear Delts|Traps",
        "description": "A chest-supported horizontal row that limits torso movement and lets the upper back perform the pull with less body English.",
    },
    "Preacher Curl": {
        "muscle_groups": "Biceps, Forearms",
        "primary_muscles": "Biceps",
        "secondary_muscles": "Forearms",
        "description": "A supported elbow-flexion exercise for the biceps. Keep the upper arm planted and control the lengthened position.",
    },
    "Hammer Curl": {
        "muscle_groups": "Biceps, Forearms",
        "primary_muscles": "Biceps",
        "secondary_muscles": "Forearms",
        "description": "A neutral-grip curl emphasizing the elbow flexors and brachioradialis. Avoid swinging the upper arm forward.",
    },
    "Chest Press": {
        "muscle_groups": "Chest, Front Delts, Triceps",
        "primary_muscles": "Chest",
        "secondary_muscles": "Front Delts|Triceps",
        "description": "A machine chest press. Keep the shoulder blades controlled and press through a comfortable chest-focused range.",
    },
    "Seated Shoulder Press": {
        "muscle_groups": "Front Delts, Triceps",
        "primary_muscles": "Front Delts",
        "secondary_muscles": "Triceps",
        "description": "A seated overhead press emphasizing the front delts while the triceps assist elbow extension.",
    },
    "Triceps Pushdown": {
        "muscle_groups": "Triceps",
        "primary_muscles": "Triceps",
        "secondary_muscles": "",
        "description": "A cable elbow-extension exercise. Keep the upper arms stable and finish each repetition without excessive torso movement.",
    },
    "Hack Squat": {
        "muscle_groups": "Quads, Glutes",
        "primary_muscles": "Quads|Glutes",
        "secondary_muscles": "",
        "description": "A guided squat pattern emphasizing the quads and glutes. Use a foot position and depth that remain comfortable and controlled.",
    },
    "Hip Thrust": {
        "muscle_groups": "Glutes, Hamstrings",
        "primary_muscles": "Glutes",
        "secondary_muscles": "Hamstrings",
        "description": "A loaded hip-extension exercise with strong glute emphasis. Control the bottom and finish with hip extension rather than lumbar extension.",
    },
    "Bulgarian Split Squat": {
        "muscle_groups": "Quads, Glutes",
        "primary_muscles": "Quads|Glutes",
        "secondary_muscles": "",
        "description": "A rear-foot-elevated unilateral squat. Use a stable stance and controlled depth to train the quads and glutes.",
    },
    "Seated Leg Curl": {
        "muscle_groups": "Hamstrings",
        "primary_muscles": "Hamstrings",
        "secondary_muscles": "",
        "description": "A seated knee-flexion exercise for the hamstrings, typically training them in a relatively lengthened hip position.",
    },
    "Bench Press": {
        "muscle_groups": "Chest, Front Delts, Triceps",
        "primary_muscles": "Chest",
        "secondary_muscles": "Front Delts|Triceps",
        "description": "A horizontal barbell press for the chest with assistance from the front delts and triceps.",
    },
    "Incline Dumbbell Press": {
        "muscle_groups": "Chest, Front Delts, Triceps",
        "primary_muscles": "Chest",
        "secondary_muscles": "Front Delts|Triceps",
        "description": "An inclined dumbbell press emphasizing the upper chest while also training the front delts and triceps.",
    },
    "Cable Fly": {
        "muscle_groups": "Chest",
        "primary_muscles": "Chest",
        "secondary_muscles": "",
        "description": "A cable chest fly. Keep a consistent elbow angle and bring the upper arms across the torso under control.",
    },
    "Rear Delt Fly": {
        "muscle_groups": "Rear Delts, Back",
        "primary_muscles": "Rear Delts",
        "secondary_muscles": "Back",
        "description": "A reverse-fly movement emphasizing the rear delts. Keep the torso stable and move the upper arms outward under control.",
    },
    "Pull-Up": {
        "muscle_groups": "Back, Biceps",
        "primary_muscles": "Back",
        "secondary_muscles": "Biceps",
        "description": "A bodyweight vertical pull. Pull the upper arms toward the torso while keeping the movement controlled.",
    },
    "Cable Row": {
        "muscle_groups": "Back, Biceps, Rear Delts, Traps",
        "primary_muscles": "Back",
        "secondary_muscles": "Biceps|Rear Delts|Traps",
        "description": "A seated cable row for the back with assistance from the biceps, rear delts, and traps.",
    },
    "Cable Crunch": {
        "muscle_groups": "Abs",
        "primary_muscles": "Abs",
        "secondary_muscles": "",
        "description": "A loaded trunk-flexion movement for the abs. Curl the rib cage toward the pelvis instead of turning it into a hip hinge.",
    },
    "Shrug": {
        "muscle_groups": "Traps",
        "primary_muscles": "Traps",
        "secondary_muscles": "",
        "description": "A loaded scapular-elevation exercise for the traps. Lift and lower the shoulders under control without rolling them around.",
    },
})


def _locked(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        with csv_transactions.access(DATA_DIR, BACKUP_DATA_FILES):
            return function(*args, **kwargs)
    return wrapped


def _transactional(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        with storage_transaction():
            return function(*args, **kwargs)
    return wrapped


def storage_transaction():
    return csv_transactions.transaction(DATA_DIR, BACKUP_DATA_FILES)


@_locked
def _write_csv(path, fieldnames, rows):
    # Serialize before touching the destination; a bad row or failed generator
    # must not truncate the user's previous file.
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    _atomic_write_bytes(path, buffer.getvalue().encode("utf-8"))


@_locked
def _atomic_write_bytes(path, data):
    csv_transactions.before_write(DATA_DIR, BACKUP_DATA_FILES)
    csv_transactions.atomic_write(path, data)


@_locked
def _delete_file(path):
    csv_transactions.before_write(DATA_DIR, BACKUP_DATA_FILES)
    path.unlink(missing_ok=True)
    csv_transactions.sync_directory(path.parent)


@_locked
def _read_csv(path):
    if not path.exists():
        return []

    with open(path, "r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


_SETS_ROWS_CACHE = {"signature": None, "rows": [], "sessions": {}}


@_locked
def _read_sets_cached():
    """Parse sets.csv once until the file changes on disk."""
    if not SETS_FILE.exists():
        _SETS_ROWS_CACHE["signature"] = None
        _SETS_ROWS_CACHE["rows"] = []
        _SETS_ROWS_CACHE["sessions"] = {}
        _SETS_ROWS_CACHE["chronological"] = []
        return []
    stat = SETS_FILE.stat()
    signature = (str(SETS_FILE), stat.st_ino, stat.st_mtime_ns, stat.st_size)
    if _SETS_ROWS_CACHE.get("signature") != signature:
        _SETS_ROWS_CACHE["rows"] = _read_csv(SETS_FILE)
        sessions = {}
        for row in _SETS_ROWS_CACHE["rows"]:
            sessions.setdefault(row.get("session_id", ""), []).append(row)
        _SETS_ROWS_CACHE["sessions"] = sessions
        ranks = {session_id: index for index, session_id in enumerate(sessions)}
        dates = {session_id: _timestamp_key(rows[0].get("date", "")) for session_id, rows in sessions.items()}
        _SETS_ROWS_CACHE["chronological"] = sorted(
            _SETS_ROWS_CACHE["rows"],
            key=lambda row: (dates[row.get("session_id", "")], ranks[row.get("session_id", "")]),
        )
        _SETS_ROWS_CACHE["signature"] = signature
    return _SETS_ROWS_CACHE.get("rows", [])


def _saved_session_rows(session_id):
    _read_sets_cached()
    return _SETS_ROWS_CACHE["sessions"].get(session_id, [])


def _timestamp_key(value):
    try:
        return datetime.fromisoformat(str(value)).astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError, OSError):
        return datetime.min.replace(tzinfo=timezone.utc)


def _chronological_sets():
    _read_sets_cached()
    return _SETS_ROWS_CACHE.get("chronological", [])


def _text(value):
    return "" if value is None else str(value).strip()


def _observation_metadata(row):
    return {
        **protocols.metadata(row),
        **deloads.metadata(row),
        **volume_accounting.metadata(row),
        "rest_seconds": _text(row.get("rest_seconds", "")),
        "target_rir": _text(row.get("target_rir", "")),
        "legacy_rir": _text(row.get("legacy_rir", "")),
        "load_mode": load_modes.normalize(row.get("load_mode", "external")),
    }


def _cycle_context(performed_at, *, preferred_id=None, historical=False):
    """Resolve only an in-range cycle; explicit historical correction may use ended cycles."""
    day = datetime.fromisoformat(performed_at).date()
    cycles = _read_csv(MESOCYCLES_FILE)
    candidates = sorted(enumerate(cycles), key=lambda item: (item[1].get("cycle_id") == preferred_id, item[0]), reverse=True)
    for _, cycle in candidates:
        if not historical and cycle.get("active", "0") != "1":
            continue
        status = mesocycle_status(cycle, today=day)
        if status["phase"] in {"Build", "Deload"}:
            return {
                "cycle_id": cycle["cycle_id"],
                "cycle_microcycle": str(status["current_microcycle"]),
                "cycle_phase": status["phase"],
                "cycle_target_rir": str(status["suggested_rir"]),
            }
    return {"cycle_id": "", "cycle_microcycle": "", "cycle_phase": "", "cycle_target_rir": ""}


@_locked
def export_data_zip_bytes():
    """Return a ZIP containing the app's human-readable user CSV files."""
    ensure_data()
    buffer = io.BytesIO()
    with zipfile.ZipFile(
        buffer,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
    ) as archive:
        files = {}
        for path in BACKUP_DATA_FILES:
            if path.exists():
                raw = path.read_bytes()
                archive.writestr(path.name, raw)
                files[path.name] = {"sha256": hashlib.sha256(raw).hexdigest()}
        archive.writestr("manifest.json", json.dumps({
            "format": "gymer-backup", "version": 1, "files": files,
        }, indent=2))
    return buffer.getvalue()


@_transactional
def import_data_zip_bytes(data):
    """Replace user CSV data from a GYMER backup ZIP, then migrate it."""
    if not data:
        raise ValueError("The selected ZIP is empty.")

    allowed = {path.name: path for path in BACKUP_DATA_FILES}
    schemas = {
        "workouts.csv": WORKOUT_FIELDS,
        "workout_exercises.csv": EXERCISE_FIELDS,
        "workout_set_templates.csv": TEMPLATE_SET_FIELDS,
        "sets.csv": SET_FIELDS,
        "settings.csv": SETTING_FIELDS,
        "active_workout.csv": ACTIVE_FIELDS,
        "exercise_catalog.csv": CATALOG_FIELDS,
        "set_types.csv": SET_TYPE_FIELDS,
        "exercise_details.csv": EXERCISE_DETAIL_FIELDS,
        "workout_details.csv": WORKOUT_DETAIL_FIELDS,
        "mesocycles.csv": MESOCYCLE_FIELDS,
        "mesocycle_schedule.csv": MESOCYCLE_SCHEDULE_FIELDS,
    }
    if len(data) > backup_validation.MAX_BACKUP_BYTES:
        raise ValueError("Backup ZIP exceeds the supported size limit.")

    try:
        with zipfile.ZipFile(io.BytesIO(data), mode="r") as archive:
            infos = [info for info in archive.infolist() if not info.is_dir()]
            names = {info.filename for info in infos}
            if len(names) != len(infos):
                raise ValueError("Backup ZIP contains duplicate filenames.")
            if len(infos) > 64 or any(info.file_size > backup_validation.MAX_FILE_BYTES for info in infos):
                raise ValueError("Backup ZIP contains too many files or an oversized file.")
            if sum(info.file_size for info in infos) > backup_validation.MAX_BACKUP_BYTES:
                raise ValueError("Uncompressed backup exceeds the supported size limit.")

            # Backups are intentionally flat: CSV files only, no folders and no
            # arbitrary extraction paths. Unknown non-CSV metadata is ignored so
            # future versions can add a manifest without breaking old imports.
            nested = [name for name in names if Path(name).name != name or "\\" in name]
            if nested:
                raise ValueError("Backup ZIP must contain files at its top level only.")

            unknown_csv = sorted(
                name for name in names
                if name.lower().endswith(".csv") and name not in allowed
            )
            if unknown_csv:
                raise ValueError(
                    "Backup contains unknown CSV file(s): "
                    + ", ".join(unknown_csv)
                )

            recognized = sorted(name for name in names if name in allowed)
            if not recognized or not (set(recognized) & {"workouts.csv", "sets.csv", "settings.csv"}):
                raise ValueError("This does not look like a GYMER data backup.")

            imported = {}
            for name in recognized:
                raw = archive.read(name)
                imported[name] = raw

            if "manifest.json" in names:
                backup_validation.validate_manifest(
                    archive.read("manifest.json"), imported, set(allowed)
                )
            backup_validation.validate_csv_files(imported, schemas, DEFAULT_SETTINGS)

    except zipfile.BadZipFile as exc:
        raise ValueError("The selected file is not a valid ZIP archive.") from exc

    # The outer transaction journals the entire previous state before deletion.
    # Recovery also covers process death during replacement or migrations.
    for path in BACKUP_DATA_FILES:
        _delete_file(path)
    for name, raw in imported.items():
        _atomic_write_bytes(allowed[name], raw.decode("utf-8-sig").encode("utf-8"))
    # Older backups lack templates. Only those archives regenerate them.
    ensure_data()

    return recognized


def _migrate_csv(path, fieldnames, defaults=None):
    defaults = defaults or {}

    if not path.exists():
        return

    rows = _read_csv(path)

    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, [])

    if header == fieldnames:
        return

    if path in {SETS_FILE, ACTIVE_WORKOUT_FILE} and "legacy_rir" not in header:
        for row in rows:
            # Old RIR may have been a locked prescription. Preserve the value
            # without promoting it to an actual effort observation.
            row["legacy_rir"] = row.get("rir", "")
            row["rir"] = ""
            row["previous_rir"] = ""
    if path == EXERCISE_DETAILS_FILE and "load_mode" not in header:
        for row in rows:
            row["load_mode"] = load_modes.default_for(row.get("exercise_name", ""))
    if path == EXERCISE_DETAILS_FILE:
        for row in rows:
            name = row.get("exercise_name", "")
            default = DEFAULT_EXERCISE_DETAILS.get(name, {})
            for key in ("primary_muscles", "secondary_muscles"):
                if key not in header:
                    row[key] = default.get(key, "") or ("|".join(normalize_muscle_list(row.get("muscle_groups", ""), exercise_name=name)) if key == "primary_muscles" else "")

    migrated = []
    for row in rows:
        migrated.append(
            {
                field: row.get(field, defaults.get(field, ""))
                for field in fieldnames
            }
        )

    _write_csv(path, fieldnames, migrated)


@_locked
def read_settings():
    if not SETTINGS_FILE.exists():
        return dict(DEFAULT_SETTINGS)

    settings = {
        row["key"]: row["value"]
        for row in _read_csv(SETTINGS_FILE)
        if row.get("key")
    }

    for key, value in DEFAULT_SETTINGS.items():
        settings.setdefault(key, value)

    return settings


@_locked
def save_settings(settings):
    merged = dict(DEFAULT_SETTINGS)
    merged.update(settings)

    _write_csv(
        SETTINGS_FILE,
        SETTING_FIELDS,
        [{"key": key, "value": value} for key, value in merged.items()],
    )


KG_TO_LB = 2.2046226218487757


def normalize_weight_unit(unit):
    return "lb" if str(unit or "").strip().lower() == "lb" else "kg"


def convert_weight_value(value, from_unit, to_unit):
    text = str(value or "").strip()
    if not text:
        return ""

    from_unit = normalize_weight_unit(from_unit)
    to_unit = normalize_weight_unit(to_unit)
    if from_unit == to_unit:
        return text

    try:
        number = float(text)
    except (TypeError, ValueError):
        # Active fields can persist valid arithmetic before their next blur.
        number = numeric_input.evaluate_numeric_expression(text)
        if number is None:
            return text

    if from_unit == "kg" and to_unit == "lb":
        number *= KG_TO_LB
    elif from_unit == "lb" and to_unit == "kg":
        number /= KG_TO_LB

    # Repeated kg <-> lb conversions can drift a familiar gym load by one cent
    # because the persisted value is intentionally limited to two decimals
    # (for example 260 lb -> kg -> 259.99 lb). If the converted result is
    # already within about one hundredth of a half-unit increment, snap that
    # rounding noise away. Values that are genuinely more precise remain untouched.
    half_step = round(number * 2.0) / 2.0
    if abs(number - half_step) <= 0.0110001:
        number = half_step

    return f"{number:.2f}".rstrip("0").rstrip(".")


@_transactional
def convert_all_weights(from_unit, to_unit):
    """Convert every persisted workout weight when the display unit changes."""
    ensure_data()
    from_unit = normalize_weight_unit(from_unit)
    to_unit = normalize_weight_unit(to_unit)
    if from_unit == to_unit:
        return

    def convert_file(path, fieldnames, weight_keys, unit_key=None):
        rows = _read_csv(path)
        for row in rows:
            stored_unit = normalize_weight_unit(
                row.get(unit_key, from_unit) if unit_key else from_unit
            )
            for key in weight_keys:
                row[key] = convert_weight_value(
                    row.get(key, ""), stored_unit, to_unit
                )
            if unit_key:
                row[unit_key] = to_unit
        _write_csv(path, fieldnames, rows)

    convert_file(
        WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS,
        ["default_weight"], "default_weight_unit"
    )
    convert_file(
        WORKOUT_SET_TEMPLATES_FILE, TEMPLATE_SET_FIELDS,
        ["weight"], "weight_unit"
    )
    convert_file(SETS_FILE, SET_FIELDS, ["weight", "prescribed_weight"], "weight_unit")
    convert_file(
        ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS,
        ["weight", "previous_weight", "prescribed_weight"], "weight_unit"
    )


@_transactional
def change_weight_unit(to_unit):
    """Commit loads/settings and return the converted settings and active state."""
    if to_unit not in {"kg", "lb"}:
        raise ValueError("Weight unit must be kg or lb.")
    settings = read_settings()
    convert_all_weights(settings.get("unit", "kg"), to_unit)
    settings["unit"] = to_unit
    save_settings(settings)
    return settings, load_active_workout()


def _fuzzy_score(query, text):
    """Small fzf-like subsequence score. Lower is better; None means no match."""
    query = query.casefold()
    text_folded = text.casefold()

    if not query:
        return 0

    positions = []
    pos = -1

    for char in query:
        pos = text_folded.find(char, pos + 1)
        if pos < 0:
            return None
        positions.append(pos)

    start = positions[0]
    gaps = sum(
        max(0, positions[i] - positions[i - 1] - 1)
        for i in range(1, len(positions))
    )

    # Prefer earlier starts, tighter matches and then shorter names.
    return start * 5 + gaps * 3 + len(text_folded) * 0.01


def filter_names(values, query="", mode=None):
    """
    Shared picker/database search.

    Normal typing uses fzf-like ordered subsequence matching. Starting the
    query with one space switches that one search to contiguous, literal text
    matching. The old persistent fuzzy/exact setting is intentionally ignored.
    """
    raw_query = str(query or "")
    leading_space_exact = raw_query.startswith(" ")

    if leading_space_exact:
        query = raw_query[1:].strip()
        mode = "exact"
    else:
        query = raw_query.strip()
        mode = mode or "fuzzy"

    unique = []
    seen = set()
    for value in values:
        value = (value or "").strip()
        key = value.casefold()
        if value and key not in seen:
            seen.add(key)
            unique.append(value)

    if not query:
        return sorted(unique, key=str.casefold)

    if mode == "exact":
        needle = query.casefold()
        matches = [
            value for value in unique
            if needle in value.casefold()
        ]
        return sorted(
            matches,
            key=lambda value: (
                value.casefold().find(needle),
                len(value),
                value.casefold(),
            ),
        )

    scored = []
    for value in unique:
        score = _fuzzy_score(query, value)
        if score is not None:
            scored.append((score, value.casefold(), value))

    scored.sort()
    return [value for _, _, value in scored]

def parse_duration(value, default=180):
    """Accept seconds (180) or m:ss (3:00) and return whole seconds."""
    text = "" if value is None else str(value).strip()
    if not text:
        return max(0, int(default))

    try:
        if ":" in text:
            parts = text.split(":")
            if len(parts) != 2:
                raise ValueError

            minutes = int(parts[0] or 0)
            seconds = int(parts[1] or 0)

            if minutes < 0 or seconds < 0 or seconds >= 60:
                raise ValueError

            return minutes * 60 + seconds

        seconds = int(float(text))
        return max(0, seconds)

    except (TypeError, ValueError, OverflowError):
        return max(0, int(default))


def format_duration(value):
    seconds = parse_duration(value, default=0)
    minutes, seconds = divmod(seconds, 60)
    return f"{minutes}:{seconds:02d}"


def _initial_catalog_names():
    names = []

    if WORKOUT_EXERCISES_FILE.exists():
        names.extend(
            row.get("exercise_name", "")
            for row in _read_csv(WORKOUT_EXERCISES_FILE)
        )

    if SETS_FILE.exists():
        names.extend(
            row.get("exercise_name", "")
            for row in _read_csv(SETS_FILE)
        )

    for _, _, exercises in DEFAULT_WORKOUTS:
        names.extend(exercises)

    return filter_names(names)


def _latest_by_set_number(rows):
    latest = {}
    default_unit = read_settings().get("unit", "kg")

    for row in reversed(rows):
        try:
            set_number = int(row.get("set_number", ""))
        except (TypeError, ValueError):
            continue

        if set_number not in latest:
            latest[set_number] = {
                **_observation_metadata(row),
                "weight": row.get("weight", ""),
                "weight_unit": row.get("weight_unit", default_unit) or default_unit,
                "reps": row.get("reps", ""),
                "rir": (
                    row.get("rir", "")
                    if method_set_uses_rir(
                        row.get("training_method", "Straight"),
                        row.get("set_type", "Normal"),
                    )
                    else ""
                ),
                "previous_weight": row.get("previous_weight", ""),
                "previous_reps": row.get("previous_reps", ""),
                "previous_rir": row.get("previous_rir", ""),
                "last_week_reps": row.get("last_week_reps", ""),
                "set_type": row.get("set_type", "Normal") or "Normal",
            }

    return latest


def _latest_raw(workout_id, exercise_name):
    if not SETS_FILE.exists():
        return {}

    rows = [
        row
        for row in _chronological_sets()
        if row.get("workout_id") == workout_id
        and row.get("exercise_name", "").casefold() == exercise_name.casefold()
        and row.get("completed", "1") != "0"
    ]
    return _latest_by_set_number(rows)


def _build_initial_template_rows(exercise_rows):
    settings = read_settings()
    default_sets = int(settings.get("default_sets", "3") or 3)
    default_rest = int(settings.get("default_rest_seconds", "180") or 180)
    weight_unit = settings.get("unit", "kg")

    rows = []

    for exercise in exercise_rows:
        workout_id = exercise.get("workout_id", "")
        order_index = exercise.get("order_index", "")
        exercise_name = exercise.get("exercise_name", "").strip()

        try:
            count = int(exercise.get("target_sets", "") or default_sets)
        except ValueError:
            count = default_sets

        count = max(1, count)

        old_weight = exercise.get("default_weight", "")
        old_reps = exercise.get("default_reps", "")
        old_rest = parse_duration(
            exercise.get("rest_seconds", ""),
            default=default_rest,
        )
        latest = _latest_raw(workout_id, exercise_name)

        for set_number in range(1, count + 1):
            previous = latest.get(set_number, {})
            rows.append(
                {
                    "workout_id": workout_id,
                    "order_index": order_index,
                    "set_number": set_number,
                    "weight": previous.get("weight", old_weight),
                    "weight_unit": settings.get("unit", "kg"),
                    "reps": previous.get("reps", old_reps),
                    "rest_seconds": str(old_rest),
                    "set_type": previous.get("set_type", "Normal"),
                }
            )

    return rows


def _default_workout_pack_needs_install():
    settings = read_settings()
    try:
        revision = int(settings.get("default_workout_pack_revision", "0") or 0)
    except (TypeError, ValueError):
        revision = 0
    return revision < DEFAULT_WORKOUT_PACK_REVISION


def _install_bundled_workouts_if_needed():
    """Append newly shipped default workouts once without replacing user edits."""
    if not _default_workout_pack_needs_install():
        return False

    workouts = _read_csv(WORKOUTS_FILE)
    exercise_rows = _read_csv(WORKOUT_EXERCISES_FILE)
    template_rows = (
        _read_csv(WORKOUT_SET_TEMPLATES_FILE)
        if WORKOUT_SET_TEMPLATES_FILE.exists()
        else []
    )
    detail_rows = (
        _read_csv(WORKOUT_DETAILS_FILE)
        if WORKOUT_DETAILS_FILE.exists()
        else []
    )

    existing_names = {
        str(row.get("name", "") or "").strip().casefold()
        for row in workouts
    }
    existing_ids = {
        str(row.get("workout_id", "") or "").strip()
        for row in workouts
    }
    added_exercises = []

    for default_id, name, exercises in DEFAULT_WORKOUTS:
        if name.casefold() in existing_names:
            continue

        workout_id = default_id
        suffix = 2
        while workout_id in existing_ids:
            workout_id = f"{default_id}_{suffix}"
            suffix += 1

        workouts.append({"workout_id": workout_id, "name": name})
        existing_names.add(name.casefold())
        existing_ids.add(workout_id)

        for order_index, exercise_name in enumerate(exercises, start=1):
            exercise_row = {
                "workout_id": workout_id,
                "order_index": order_index,
                "exercise_name": exercise_name,
                "target_sets": "3",
                "default_weight": "",
                "default_weight_unit": read_settings().get("unit", "kg"),
                "default_reps": "",
                "rest_seconds": "180",
            }
            exercise_rows.append(exercise_row)
            added_exercises.append(exercise_row)

        if WORKOUT_DETAILS_FILE.exists():
            detail_rows.append(
                {
                    "workout_id": workout_id,
                    "description": "",
                    "note": "",
                    "set_seconds": "45",
                    "set_overhead_seconds": "30",
                    "transition_seconds": "300",
                    "session_overhead_seconds": "300",
                }
            )

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, exercise_rows)

    if WORKOUT_SET_TEMPLATES_FILE.exists() and added_exercises:
        template_rows.extend(_build_initial_template_rows(added_exercises))
        _write_csv(WORKOUT_SET_TEMPLATES_FILE, TEMPLATE_SET_FIELDS, template_rows)

    if WORKOUT_DETAILS_FILE.exists():
        _write_csv(WORKOUT_DETAILS_FILE, WORKOUT_DETAIL_FIELDS, detail_rows)

    return True


def _install_bundled_exercises_for_pack():
    """Add catalog/detail rows for the workout pack without overwriting user data."""
    catalog_rows = _read_csv(EXERCISE_CATALOG_FILE)
    catalog_names = {
        str(row.get("exercise_name", "") or "").strip().casefold()
        for row in catalog_rows
    }
    for name in DEFAULT_EXERCISE_DETAILS:
        if name.casefold() not in catalog_names:
            catalog_rows.append({"exercise_name": name})
            catalog_names.add(name.casefold())
    _write_csv(EXERCISE_CATALOG_FILE, CATALOG_FIELDS, catalog_rows)

    detail_rows = _read_csv(EXERCISE_DETAILS_FILE)
    detail_names = {
        str(row.get("exercise_name", "") or "").strip().casefold()
        for row in detail_rows
    }
    for name, details in DEFAULT_EXERCISE_DETAILS.items():
        if name.casefold() in detail_names:
            continue
        detail_rows.append(
            {
                "exercise_name": name,
                "muscle_groups": details.get("muscle_groups", ""),
                "primary_muscles": details.get("primary_muscles", ""),
                "secondary_muscles": details.get("secondary_muscles", ""),
                "description": details.get("description", ""),
                "note": "",
                "set_seconds": "",
                "equipment_type": DEFAULT_EXERCISE_EQUIPMENT.get(
                    name, ""
                ),
                "weight_increment_lb": "",
                "weight_increment_kg": "",
            }
        )
        detail_names.add(name.casefold())
    _write_csv(EXERCISE_DETAILS_FILE, EXERCISE_DETAIL_FIELDS, detail_rows)


def _mark_default_workout_pack_installed():
    settings = read_settings()
    settings["default_workout_pack_revision"] = str(DEFAULT_WORKOUT_PACK_REVISION)
    save_settings(settings)


@_transactional
def ensure_data():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    install_default_pack = False

    if not WORKOUTS_FILE.exists():
        _write_csv(
            WORKOUTS_FILE,
            WORKOUT_FIELDS,
            [
                {"workout_id": workout_id, "name": name}
                for workout_id, name, _ in DEFAULT_WORKOUTS
            ],
        )

    if not WORKOUT_EXERCISES_FILE.exists():
        rows = []
        for workout_id, _, exercises in DEFAULT_WORKOUTS:
            for i, exercise in enumerate(exercises, start=1):
                rows.append(
                    {
                        "workout_id": workout_id,
                        "order_index": i,
                        "exercise_name": exercise,
                        "target_sets": "3",
                        "default_weight": "",
                        "default_weight_unit": read_settings().get("unit", "kg"),
                        "default_reps": "",
                        "rest_seconds": "180",
                        "training_method": "Straight",
                    }
                )

        _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, rows)
    else:
        _migrate_csv(
            WORKOUT_EXERCISES_FILE,
            EXERCISE_FIELDS,
            defaults={
                "target_sets": "3",
                "default_weight": "",
                "default_weight_unit": read_settings().get("unit", "kg"),
                "default_reps": "",
                "rest_seconds": "180",
                "training_method": "",
            },
        )

    if not SETS_FILE.exists():
        _write_csv(SETS_FILE, SET_FIELDS, [])
    else:
        _migrate_csv(
            SETS_FILE,
            SET_FIELDS,
            defaults={
                "set_type": "Normal",
                "completed": "1",
                "weight_unit": read_settings().get("unit", "kg"),
                "cycle_id": "",
                "cycle_microcycle": "",
                "training_method": "",
            },
        )

    if not SETTINGS_FILE.exists():
        _write_csv(
            SETTINGS_FILE,
            SETTING_FIELDS,
            [{"key": key, "value": value} for key, value in DEFAULT_SETTINGS.items()],
        )
    else:
        settings = read_settings()
        changed = False

        for key, value in DEFAULT_SETTINGS.items():
            if key not in settings:
                settings[key] = value
                changed = True

        if settings.get("ui_revision") != "12":
            revision = settings.get("ui_revision")

            # Carry forward the older v6 -> v7 defaults first.
            if revision != "7":
                if settings.get("accent_color") == "blue":
                    settings["accent_color"] = "purple"
                if settings.get("background_color") == "default":
                    settings["background_color"] = "auto"
                if settings.get("theme_mode") == "dark":
                    settings["theme_mode"] = "system"
                if settings.get("set_spacing") == "22":
                    settings["set_spacing"] = "3"

            # v20 shipped charcoal/8px as its defaults. In v21 the default
            # background is mode-aware (dark=#1, light=#2), and set rows are
            # intentionally much tighter. Custom non-default choices survive.
            if revision == "7":
                if settings.get("background_color") == "charcoal":
                    settings["background_color"] = "auto"
                if settings.get("set_spacing") == "8":
                    settings["set_spacing"] = "3"

            settings.setdefault("hide_status_bar", "0")
            settings.setdefault("track_rir", "1")
            settings.setdefault("dim_completed_sets", "1")
            settings.setdefault("collapse_completed_exercises", "1")
            settings.setdefault("timer_tracker_mode", "both")
            settings.setdefault("show_rest_time_near_sets", "1")
            settings.setdefault("planned_rest_display_mode", "hide")
            settings.setdefault("update_following_set_defaults", "0")
            settings.setdefault("enter_completes_set", "1")
            settings.setdefault("enter_moves_to_next_set", "0")
            settings.setdefault("backspace_moves_to_previous_set", "0")
            settings.setdefault("advanced_mode", "0")
            settings.setdefault("require_previous_sets_completed", "0")
            settings.setdefault("default_timer_display_mode", "elapsed")

            # v27 removes completed-set hiding entirely. Drop the obsolete
            # settings so settings.csv stays clean; exercise collapsing remains.
            settings.pop("collapse_completed_sets", None)
            settings.pop("completed_sets_keep", None)

            settings["ui_revision"] = "12"
            changed = True

        if changed:
            save_settings(settings)

    install_default_pack = _install_bundled_workouts_if_needed()

    if not WORKOUT_SET_TEMPLATES_FILE.exists():
        _write_csv(
            WORKOUT_SET_TEMPLATES_FILE,
            TEMPLATE_SET_FIELDS,
            _build_initial_template_rows(_read_csv(WORKOUT_EXERCISES_FILE)),
        )
    else:
        _migrate_csv(
            WORKOUT_SET_TEMPLATES_FILE,
            TEMPLATE_SET_FIELDS,
            defaults={
                "weight": "",
                "weight_unit": read_settings().get("unit", "kg"),
                "reps": "",
                "rest_seconds": read_settings().get("default_rest_seconds", "180"),
                "set_type": "Normal",
            },
        )

    if not ACTIVE_WORKOUT_FILE.exists():
        _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, [])
    else:
        _migrate_csv(
            ACTIVE_WORKOUT_FILE,
            ACTIVE_FIELDS,
            defaults={
                "completed": "0",
                "weight_unit": read_settings().get("unit", "kg"),
                "rest_seconds": read_settings().get("default_rest_seconds", "180"),
                "set_type": "Normal",
                "previous_weight": "",
                "previous_reps": "",
                "previous_rir": "",
                "last_week_reps": "",
                "training_method": "",
                "started_at": "",
            },
        )

    active_rows = _read_csv(ACTIVE_WORKOUT_FILE)
    if active_rows and not active_rows[0].get("session_id"):
        # Upgrade an interrupted workout once, before it can be finished.
        session_id = str(uuid.uuid4())
        for row in active_rows:
            row["session_id"] = session_id
        _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, active_rows)

    if not EXERCISE_CATALOG_FILE.exists():
        _write_csv(
            EXERCISE_CATALOG_FILE,
            CATALOG_FIELDS,
            [{"exercise_name": name} for name in _initial_catalog_names()],
        )
    else:
        _migrate_csv(EXERCISE_CATALOG_FILE, CATALOG_FIELDS)

    if not SET_TYPES_FILE.exists():
        _write_csv(
            SET_TYPES_FILE,
            SET_TYPE_FIELDS,
            [{"set_type": name} for name in DEFAULT_SET_TYPES],
        )
    else:
        _migrate_csv(SET_TYPES_FILE, SET_TYPE_FIELDS)

    if not EXERCISE_DETAILS_FILE.exists():
        rows = []
        for name, details in DEFAULT_EXERCISE_DETAILS.items():
            rows.append(
                {
                    "exercise_name": name,
                    "muscle_groups": details.get("muscle_groups", ""),
                    "primary_muscles": details.get("primary_muscles", ""),
                    "secondary_muscles": details.get("secondary_muscles", ""),
                    "description": details.get("description", ""),
                    "note": "",
                    "set_seconds": "",
                    "equipment_type": DEFAULT_EXERCISE_EQUIPMENT.get(
                        name, ""
                    ),
                    "weight_increment_lb": "",
                    "weight_increment_kg": "",
                }
            )
        _write_csv(EXERCISE_DETAILS_FILE, EXERCISE_DETAIL_FIELDS, rows)
    else:
        _migrate_csv(
            EXERCISE_DETAILS_FILE,
            EXERCISE_DETAIL_FIELDS,
            defaults={
                "set_seconds": "",
                "primary_muscles": "",
                "secondary_muscles": "",
                "equipment_type": "",
                "weight_increment_lb": "",
                "weight_increment_kg": "",
            },
        )

    _migrate_exercise_details_muscles_to_rp()

    if install_default_pack:
        _install_bundled_exercises_for_pack()
        _migrate_exercise_details_muscles_to_rp()
        _mark_default_workout_pack_installed()

    if not WORKOUT_DETAILS_FILE.exists():
        _write_csv(
            WORKOUT_DETAILS_FILE,
            WORKOUT_DETAIL_FIELDS,
            [
                {
                    "workout_id": workout_id,
                    "description": "",
                    "note": "",
                    "set_seconds": "45",
                    "set_overhead_seconds": "30",
                    "transition_seconds": "300",
                    "session_overhead_seconds": "300",
                }
                for workout_id, _, _ in DEFAULT_WORKOUTS
            ],
        )
    else:
        _migrate_csv(
            WORKOUT_DETAILS_FILE,
            WORKOUT_DETAIL_FIELDS,
            defaults={
                "description": "",
                "note": "",
                "set_seconds": "45",
                "set_overhead_seconds": "30",
                "transition_seconds": "300",
                "session_overhead_seconds": "300",
            },
        )

    if not MESOCYCLES_FILE.exists():
        _write_csv(MESOCYCLES_FILE, MESOCYCLE_FIELDS, [])
    else:
        _migrate_csv(
            MESOCYCLES_FILE,
            MESOCYCLE_FIELDS,
            defaults={
                "name": "Mesocycle",
                "start_date": "",
                "microcycle_days": "7",
                "length_value": "5",
                "length_unit": "microcycles",
                "deload_microcycles": "1",
                "start_rir": "3",
                "end_rir": "1",
                "deload_rir": "4",
                "rir_lock": "0",
                "rest_timer_lock": "0",
                "show_last_week_reps": "0",
                "setup_complete": "1",
                "active": "0",
            },
        )

    if not MESOCYCLE_SCHEDULE_FILE.exists():
        _write_csv(MESOCYCLE_SCHEDULE_FILE, MESOCYCLE_SCHEDULE_FIELDS, [])
    else:
        _migrate_csv(
            MESOCYCLE_SCHEDULE_FILE,
            MESOCYCLE_SCHEDULE_FIELDS,
            defaults={"workout_id": ""},
        )

        # Older Gymer versions allowed each later microcycle to override the
        # workout assigned to the corresponding day.  The schedule is now one
        # repeating template, so discard every persisted later-microcycle row.
        cycle_micro_days = {}
        for cycle_row in _read_csv(MESOCYCLES_FILE):
            cycle_id = str(cycle_row.get("cycle_id", "") or "").strip()
            if not cycle_id:
                continue
            try:
                cycle_micro_days[cycle_id] = max(
                    1, int(cycle_row.get("microcycle_days", "7") or 7)
                )
            except (TypeError, ValueError):
                cycle_micro_days[cycle_id] = 7

        schedule_rows = _read_csv(MESOCYCLE_SCHEDULE_FILE)
        repeating_rows = []
        for row in schedule_rows:
            cycle_id = str(row.get("cycle_id", "") or "").strip()
            try:
                day_number = int(row.get("day_number", "0") or 0)
            except (TypeError, ValueError):
                continue
            micro_days = cycle_micro_days.get(cycle_id, 7)
            if cycle_id and 1 <= day_number <= micro_days:
                repeating_rows.append(row)

        if repeating_rows != schedule_rows:
            _write_csv(
                MESOCYCLE_SCHEDULE_FILE,
                MESOCYCLE_SCHEDULE_FIELDS,
                repeating_rows,
            )

    active_rows = _read_csv(ACTIVE_WORKOUT_FILE)
    if active_rows and not active_rows[0].get("performed_at"):
        performed_at = active_rows[0].get("started_at") or datetime.now().isoformat(timespec="seconds")
        context = _cycle_context(performed_at)
        for row in active_rows:
            row.update(performed_at=performed_at, **context)
        _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, active_rows)


# ----------------------------------------------------------------------
# EXERCISE CATALOG / SET TYPES
# ----------------------------------------------------------------------


@_locked
def catalog_exercises(query="", mode=None):
    ensure_data()
    values = [
        row.get("exercise_name", "")
        for row in _read_csv(EXERCISE_CATALOG_FILE)
    ]
    return filter_names(values, query, mode)


@_locked
def catalog_contains(name):
    key = (name or "").strip().casefold()
    if not key:
        return False

    return any(
        value.casefold() == key
        for value in catalog_exercises()
    )


@_locked
def add_catalog_exercise(name):
    ensure_data()
    name = (name or "").strip()

    if not name or catalog_contains(name):
        return False

    rows = _read_csv(EXERCISE_CATALOG_FILE)
    rows.append({"exercise_name": name})
    rows.sort(key=lambda row: row["exercise_name"].casefold())
    _write_csv(EXERCISE_CATALOG_FILE, CATALOG_FIELDS, rows)
    return True


@_locked
def delete_catalog_exercise(name):
    ensure_data()
    key = (name or "").strip().casefold()

    rows = [
        row
        for row in _read_csv(EXERCISE_CATALOG_FILE)
        if row.get("exercise_name", "").strip().casefold() != key
    ]

    _write_csv(EXERCISE_CATALOG_FILE, CATALOG_FIELDS, rows)


@_transactional
def rename_exercise(old_name, new_name):
    """Rename one exercise everywhere without splitting its history."""
    ensure_data()
    old_name = str(old_name or "").strip()
    new_name = str(new_name or "").strip()
    if not old_name or not new_name:
        return False

    old_key = old_name.casefold()
    new_key = new_name.casefold()

    # Do not silently merge two distinct exercises. Historical-only names count
    # too, because merging them would corrupt progression/history semantics.
    if new_key != old_key:
        sources = (
            _read_csv(EXERCISE_CATALOG_FILE),
            _read_csv(EXERCISE_DETAILS_FILE),
            _read_csv(WORKOUT_EXERCISES_FILE),
            _read_csv(SETS_FILE),
            _read_csv(ACTIVE_WORKOUT_FILE),
        )
        if any(
            str(row.get("exercise_name", "") or "").strip().casefold() == new_key
            for rows in sources
            for row in rows
        ):
            return False

    catalog = _read_csv(EXERCISE_CATALOG_FILE)
    replaced_catalog = False
    for row in catalog:
        if str(row.get("exercise_name", "") or "").strip().casefold() == old_key:
            row["exercise_name"] = new_name
            replaced_catalog = True
    if not replaced_catalog:
        catalog.append({"exercise_name": new_name})
    # Collapse any case-only duplicates and keep the catalog deterministic.
    unique_catalog = {}
    for row in catalog:
        name = str(row.get("exercise_name", "") or "").strip()
        if name:
            unique_catalog[name.casefold()] = {"exercise_name": name}
    catalog = sorted(unique_catalog.values(), key=lambda row: row["exercise_name"].casefold())
    _write_csv(EXERCISE_CATALOG_FILE, CATALOG_FIELDS, catalog)

    for path, fields in (
        (EXERCISE_DETAILS_FILE, EXERCISE_DETAIL_FIELDS),
        (WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS),
        (SETS_FILE, SET_FIELDS),
        (ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS),
    ):
        rows = _read_csv(path)
        changed = False
        for row in rows:
            if path == ACTIVE_WORKOUT_FILE and row.get("rest_timer_state"):
                state = rest_timer_state.decode(row["rest_timer_state"])
                if state["exercise_name"].casefold() == old_key:
                    state["exercise_name"] = new_name
                    row["rest_timer_state"] = rest_timer_state.encode(state)
                    changed = True
            if str(row.get("exercise_name", "") or "").strip().casefold() == old_key:
                row["exercise_name"] = new_name
                changed = True
        if changed:
            _write_csv(path, fields, rows)

    # Calibration completion is keyed by exercise name in Settings. Preserve it
    # across a rename so an already-calibrated exercise does not unexpectedly
    # ask for calibration again.
    settings = read_settings()
    raw_seen = settings.get("mesocycle_intro_seen_exercises", "{}")
    try:
        seen = json.loads(raw_seen)
    except (TypeError, ValueError, json.JSONDecodeError):
        seen = {}
    seen_changed = False
    if isinstance(seen, dict):
        for placements in seen.values():
            if not isinstance(placements, list):
                continue
            for placement in placements:
                if isinstance(placement, dict):
                    value = str(placement.get("exercise_name", "") or "").strip()
                    if value.casefold() == old_key:
                        placement["exercise_name"] = new_name
                        seen_changed = True
                elif isinstance(placement, str) and placement.strip().casefold() == old_key:
                    # Legacy string-only placement cannot be changed in place by
                    # reference, so normalize it below if encountered.
                    seen_changed = True
        if seen_changed:
            normalized = {}
            for cycle_id, placements in seen.items():
                updated = []
                for placement in placements if isinstance(placements, list) else []:
                    if isinstance(placement, dict):
                        updated.append(placement)
                    elif isinstance(placement, str):
                        value = placement.strip()
                        updated.append(new_name if value.casefold() == old_key else value)
                normalized[cycle_id] = updated
            settings["mesocycle_intro_seen_exercises"] = json.dumps(
                normalized, ensure_ascii=False
            )
            save_settings(settings)

    return True


@_locked
def all_exercise_names():
    return catalog_exercises()


@_locked
def set_types(query="", mode=None):
    ensure_data()
    values = [
        display_set_type(row.get("set_type", ""))
        for row in _read_csv(SET_TYPES_FILE)
    ]
    # Built-ins are merged at read time so newly introduced structural roles
    # (for example Activation/Myo-set) appear without rewriting user CSVs.
    values.extend(display_set_type(value) for value in DEFAULT_SET_TYPES)
    # Deduplicate aliases such as legacy Normal / Straight while preserving order.
    values = list(dict.fromkeys(value for value in values if value))
    return filter_names(values, query, mode)


@_locked
def set_type_contains(name):
    key = canonical_set_type(name).casefold()
    if not key:
        return False

    return any(
        canonical_set_type(row.get("set_type", "")).casefold() == key
        for row in _read_csv(SET_TYPES_FILE)
    )


@_locked
def add_set_type(name):
    ensure_data()
    name = canonical_set_type(name)

    if not name or set_type_contains(name):
        return False

    rows = _read_csv(SET_TYPES_FILE)
    rows.append({"set_type": name})
    rows.sort(key=lambda row: row["set_type"].casefold())
    _write_csv(SET_TYPES_FILE, SET_TYPE_FIELDS, rows)
    return True


@_locked
def delete_set_type(name):
    """
    Remove only from the selectable set-type database.
    Existing templates/history keep their stored text.
    """
    ensure_data()
    key = canonical_set_type(name).casefold()

    rows = [
        row
        for row in _read_csv(SET_TYPES_FILE)
        if canonical_set_type(row.get("set_type", "")).casefold() != key
    ]

    _write_csv(SET_TYPES_FILE, SET_TYPE_FIELDS, rows)


@_locked
def read_exercise_details(exercise_name):
    ensure_data()
    key = (exercise_name or "").strip().casefold()

    for row in _read_csv(EXERCISE_DETAILS_FILE):
        if row.get("exercise_name", "").strip().casefold() == key:
            default = DEFAULT_EXERCISE_DETAILS.get(exercise_name, {})
            return {
                "exercise_name": row.get("exercise_name", exercise_name),
                **set_context.metadata(row),
                **progression.straight_settings(row.get("straight_rep_min"), row.get("straight_rep_max"), row.get("straight_progression")),
                "muscle_groups": row.get("muscle_groups", ""),
                "primary_muscles": row.get("primary_muscles", ""),
                "secondary_muscles": row.get("secondary_muscles", ""),
                "description": row.get("description", ""),
                "note": row.get("note", ""),
                "set_seconds": row.get("set_seconds", ""),
                "equipment_type": normalize_equipment_type(
                    row.get("equipment_type", "")
                    or DEFAULT_EXERCISE_EQUIPMENT.get(exercise_name, "")
                ),
                "weight_increment_lb": row.get("weight_increment_lb", ""),
                "weight_increment_kg": row.get("weight_increment_kg", ""),
                "load_mode": load_modes.normalize(row.get("load_mode") or load_modes.default_for(exercise_name)),
            }

    default = DEFAULT_EXERCISE_DETAILS.get(exercise_name, {})
    return {
        "exercise_name": exercise_name,
        **set_context.metadata({}),
        **progression.straight_settings(),
        "muscle_groups": default.get("muscle_groups", ""),
        "primary_muscles": default.get("primary_muscles", ""),
        "secondary_muscles": default.get("secondary_muscles", ""),
        "description": default.get("description", ""),
        "note": "",
        "set_seconds": "",
        "equipment_type": normalize_equipment_type(
            DEFAULT_EXERCISE_EQUIPMENT.get(exercise_name, "")
        ),
        "weight_increment_lb": "",
        "weight_increment_kg": "",
        "load_mode": load_modes.default_for(exercise_name),
    }

@_locked
def exercise_weight_increment(exercise_name, unit, settings=None):
    """Return the available load jump for one exercise in the active unit."""
    unit = "lb" if str(unit or "kg").strip().lower() == "lb" else "kg"
    details = read_exercise_details(exercise_name)
    override = str(details.get(f"weight_increment_{unit}", "") or "").strip()
    if override:
        try:
            value = float(override)
            if value > 0:
                return value
        except (TypeError, ValueError):
            pass

    equipment_type = normalize_equipment_type(details.get("equipment_type", ""))
    settings = settings or read_settings()
    key = weight_increment_setting_key(equipment_type, unit)
    try:
        value = float(str(settings.get(key, "") or "").strip())
        if value > 0:
            return value
    except (TypeError, ValueError):
        pass
    return default_weight_increment(equipment_type, unit)


@_locked
def reset_weight_increment_defaults(settings=None):
    settings = dict(settings or read_settings())
    for equipment_type in EQUIPMENT_TYPES:
        for unit in ("lb", "kg"):
            key = weight_increment_setting_key(equipment_type, unit)
            settings[key] = format_increment(
                default_weight_increment(equipment_type, unit)
            )
    save_settings(settings)
    return settings

def _legacy_muscle_targets(item, exercise_name=""):
    """Map pre-RP Gymer muscle tags onto the current RP taxonomy.

    The old generic Shoulders tag cannot be mapped perfectly. Use the exercise
    name when migrating existing data so obvious lateral/rear-delt exercises
    land in the correct RP group; otherwise Front Delts is the safest default
    for pressing-oriented shoulder work.
    """
    key = str(item or "").strip().casefold()
    if not key:
        return []

    current = {name.casefold(): name for name in RP_MUSCLE_GROUPS}
    if key in current:
        return [current[key]]

    if key in {"lats", "mid back", "lower back"}:
        return ["Back"]
    if key == "shoulders":
        name = str(exercise_name or "").casefold()
        if any(token in name for token in ("lateral", "side delt", "side raise")):
            return ["Side Delts"]
        if any(token in name for token in ("rear delt", "reverse fly", "reverse pec", "face pull")):
            return ["Rear Delts"]
        return ["Front Delts"]

    # Neck, Adductors and Tibialis were valid Gymer tags but are not among the
    # RP groups supplied for this app. Do not silently relabel them as another
    # muscle just to keep a count.
    return []


def normalize_muscle_list(value, exercise_name=""):
    if isinstance(value, (list, tuple, set)):
        raw = [str(item).strip() for item in value]
    else:
        raw = [item.strip() for item in str(value or "").replace(",", "|").split("|")]

    seen = set()
    output = []
    for item in raw:
        for mapped in _legacy_muscle_targets(item, exercise_name):
            key = mapped.casefold()
            if key not in seen:
                seen.add(key)
                output.append(mapped)
    return output


def _migrate_exercise_details_muscles_to_rp():
    """Rewrite old exercise-detail muscle tags to the RP taxonomy once loaded."""
    if not EXERCISE_DETAILS_FILE.exists():
        return

    rows = _read_csv(EXERCISE_DETAILS_FILE)
    changed = False
    for row in rows:
        exercise_name = str(row.get("exercise_name", "") or "").strip()
        if not row.get("load_mode"):
            row["load_mode"] = load_modes.default_for(exercise_name)
            changed = True
        primary = normalize_muscle_list(
            row.get("primary_muscles", ""), exercise_name=exercise_name
        )
        primary_keys = {muscle.casefold() for muscle in primary}
        secondary = [
            muscle
            for muscle in normalize_muscle_list(
                row.get("secondary_muscles", ""), exercise_name=exercise_name
            )
            if muscle.casefold() not in primary_keys
        ]

        primary_text = "|".join(primary)
        secondary_text = "|".join(secondary)
        group_text = ", ".join(primary + secondary)
        if (
            row.get("primary_muscles", "") != primary_text
            or row.get("secondary_muscles", "") != secondary_text
            or row.get("muscle_groups", "") != group_text
        ):
            row["primary_muscles"] = primary_text
            row["secondary_muscles"] = secondary_text
            row["muscle_groups"] = group_text
            changed = True

    if changed:
        _write_csv(EXERCISE_DETAILS_FILE, EXERCISE_DETAIL_FIELDS, rows)


def muscle_list_text(value):
    return "|".join(normalize_muscle_list(value))


@_transactional
def save_exercise_details(
    exercise_name,
    primary_muscles,
    secondary_muscles,
    description,
    note,
    set_seconds="",
    equipment_type="",
    weight_increment_lb="",
    weight_increment_kg="",
    load_mode=None,
    straight_rep_min=None,
    straight_rep_max=None,
    straight_progression=None,
    logging_context=None,
):
    ensure_data()
    exercise_name = (exercise_name or "").strip()
    if not exercise_name:
        return
    previous_details = read_exercise_details(exercise_name)
    previous_mode = previous_details["load_mode"]
    context = set_context.validate({**set_context.metadata(previous_details), **(logging_context or {})})
    context_changed = not set_context.matches(previous_details, context)
    mode = load_modes.normalize(load_mode if load_mode is not None else previous_mode)
    straight = progression.straight_settings(
        previous_details["straight_rep_min"] if straight_rep_min is None else straight_rep_min,
        previous_details["straight_rep_max"] if straight_rep_max is None else straight_rep_max,
        previous_details["straight_progression"] if straight_progression is None else straight_progression,
    )

    set_seconds_text = str(set_seconds or "").strip()
    if set_seconds_text:
        try:
            set_seconds_text = str(max(1, int(float(set_seconds_text))))
        except (TypeError, ValueError):
            set_seconds_text = ""

    equipment_type = normalize_equipment_type(equipment_type)

    def clean_increment(value):
        text = str(value or "").strip()
        if not text:
            return ""
        try:
            number = float(text)
        except (TypeError, ValueError):
            return ""
        if number <= 0:
            return ""
        return format_increment(number)

    weight_increment_lb = clean_increment(weight_increment_lb)
    weight_increment_kg = clean_increment(weight_increment_kg)

    primary = normalize_muscle_list(primary_muscles)
    primary_keys = {item.casefold() for item in primary}
    secondary = [
        item for item in normalize_muscle_list(secondary_muscles)
        if item.casefold() not in primary_keys
    ]

    key = exercise_name.casefold()
    rows = _read_csv(EXERCISE_DETAILS_FILE)
    updated = False

    for row in rows:
        if row.get("exercise_name", "").strip().casefold() == key:
            row["exercise_name"] = exercise_name
            row["primary_muscles"] = "|".join(primary)
            row["secondary_muscles"] = "|".join(secondary)
            row["muscle_groups"] = ", ".join(primary + secondary)
            row["description"] = (description or "").strip()
            row["note"] = (note or "").strip()
            row["set_seconds"] = set_seconds_text
            row["equipment_type"] = equipment_type
            row["weight_increment_lb"] = weight_increment_lb
            row["weight_increment_kg"] = weight_increment_kg
            row["load_mode"] = mode
            row.update(straight)
            row.update(context)
            updated = True
            break

    if not updated:
        rows.append(
            {
                "exercise_name": exercise_name,
                "muscle_groups": ", ".join(primary + secondary),
                "primary_muscles": "|".join(primary),
                "secondary_muscles": "|".join(secondary),
                "description": (description or "").strip(),
                "note": (note or "").strip(),
                "set_seconds": set_seconds_text,
                "equipment_type": equipment_type,
                "weight_increment_lb": weight_increment_lb,
                "weight_increment_kg": weight_increment_kg,
                "load_mode": mode,
                **straight,
                **context,
            }
        )

    _write_csv(EXERCISE_DETAILS_FILE, EXERCISE_DETAIL_FIELDS, rows)
    if mode != previous_mode or context_changed:
        # Added load and assistance have different meanings. Do not seed a new
        # plan from numeric defaults authored under the previous load mode.
        exercises = _read_csv(WORKOUT_EXERCISES_FILE)
        templates = _read_csv(WORKOUT_SET_TEMPLATES_FILE)
        placements = set()
        for exercise in exercises:
            if exercise["exercise_name"].strip().casefold() == key:
                placement = (exercise["workout_id"], exercise["order_index"])
                first = next((row for row in templates if (row["workout_id"], row["order_index"]) == placement
                              and str(row["set_number"]) == "1"), {})
                inherited = first.get("context_override") != "1"
                if mode != previous_mode or inherited:
                    exercise["default_weight"] = ""
                if context_changed and inherited:
                    exercise["default_reps"] = ""
                placements.add(placement)
        if placements:
            for template in templates:
                if (template["workout_id"], template["order_index"]) in placements:
                    inherited = template.get("context_override") != "1"
                    if mode != previous_mode or inherited:
                        template["weight"] = ""
                    if context_changed and inherited:
                        template["reps"] = ""
            _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, exercises)
            _write_csv(WORKOUT_SET_TEMPLATES_FILE, TEMPLATE_SET_FIELDS, templates)


@_locked
def workout_primary_muscles(workout_id):
    workout = read_workout(workout_id)
    if not workout:
        return []

    found = set()
    for exercise in workout.get("exercises", []):
        details = read_exercise_details(exercise.get("exercise_name", ""))
        for muscle in normalize_muscle_list(details.get("primary_muscles", "")):
            found.add(muscle)

    return [name for name in BODYBUILDING_MUSCLE_GROUPS if name in found]




def _row_completed(row):
    value = row.get("completed", True)
    if isinstance(value, bool):
        return value
    return str(value or "1").strip().casefold() not in {"0", "false", "no", "off"}


def canonical_training_method(value):
    raw = str(value or "").strip()
    key = raw.casefold()
    aliases = {
        "": "Straight",
        "normal": "Straight",
        "straight (normal)": "Straight",
        "straight": "Straight",
        "cluster set": "Cluster",
        "cluster": "Cluster",
        "myoreps": "Myo-Reps",
        "myo reps": "Myo-Reps",
        "myo-reps": "Myo-Reps",
        "myorep match": "Myo-Rep Match",
        "myo rep match": "Myo-Rep Match",
    }
    if key in aliases:
        return aliases[key]
    for method in TRAINING_METHODS:
        if method.casefold() == key:
            return method
    return "Straight"


def infer_training_method(set_rows):
    types = [canonical_set_type(row.get("set_type", "Normal")) for row in (set_rows or [])]
    work = [value for value in types if not is_warmup_set_type(value)]
    lowered = {value.casefold() for value in work}
    if "myo-set" in lowered or "myo-reps" in lowered:
        return "Myo-Reps"
    if "myo-rep match" in lowered:
        return "Myo-Rep Match"
    if "rest-pause" in lowered:
        return "Rest-Pause"
    if "mechanical drop set" in lowered:
        return "Mechanical Drop Set"
    if "drop set" in lowered:
        return "Drop Set"
    if "cluster set" in lowered:
        return "Cluster"
    if work and all(value.casefold() == "amrap" for value in work):
        return "AMRAP"
    return "Straight"


def resolve_training_method(value, set_rows=None):
    raw = str(value or "").strip()
    if raw:
        return canonical_training_method(raw)
    return infer_training_method(set_rows or [])


def training_methods(query=""):
    query = str(query or "").strip().casefold()
    if not query:
        return list(TRAINING_METHODS)
    return [name for name in TRAINING_METHODS if query in name.casefold()]


def allowed_set_types_for_method(method):
    method = canonical_training_method(method)
    return list(METHOD_SET_TYPES.get(method, METHOD_SET_TYPES["Straight"]))


def set_type_choices_for_method_row(method, set_rows, row_index):
    method = canonical_training_method(method)
    prior_work = any(
        not is_warmup_set_type(row.get("set_type", "Normal"))
        for row in (set_rows or [])[:max(0, int(row_index))]
    )

    if method in ACTIVATION_FOLLOWUP:
        if 0 <= row_index < len(set_rows or []) and set_rows[row_index].get("protocol_group_start") == "1":
            return ["Activation"]
        if prior_work:
            return [ACTIVATION_FOLLOWUP[method]]
        return ["Warm-up", "Activation"]

    allowed = allowed_set_types_for_method(method)
    if prior_work:
        allowed = [value for value in allowed if not is_warmup_set_type(value)]
    return allowed


def default_next_set_type(method, set_rows=None):
    method = canonical_training_method(method)
    rows = set_rows or []
    if method in ACTIVATION_FOLLOWUP:
        has_work = any(not is_warmup_set_type(row.get("set_type", "Normal")) for row in rows)
        return ACTIVATION_FOLLOWUP[method] if has_work else "Activation"
    if method == "AMRAP":
        return "AMRAP"
    if method == "Cluster":
        return "Cluster Set"
    return "Normal"


def reconcile_method_sets(method, set_rows):
    """Return rows whose set roles are valid for the selected exercise method."""
    method = canonical_training_method(method)
    output = [dict(row) for row in (set_rows or [])]
    work_seen = False
    for row in output:
        current = canonical_set_type(row.get("set_type", "Normal"))
        grouped = method in ACTIVATION_FOLLOWUP or method == "Cluster"
        if not grouped:
            row["protocol_group_start"] = ""
        if is_warmup_set_type(current) and not work_seen:
            row["set_type"] = "Warm-up"
            row["protocol_group_start"] = ""
            continue

        first_in_group = not work_seen or (grouped and row.get("protocol_group_start") == "1")
        if method == "Straight":
            row["set_type"] = current if current in {"Normal", "Top Set", "Back-off"} else "Normal"
        elif method == "AMRAP":
            row["set_type"] = "AMRAP"
        elif method == "Cluster":
            row["set_type"] = "Cluster Set"
        elif method in ACTIVATION_FOLLOWUP:
            row["set_type"] = "Activation" if first_in_group else ACTIVATION_FOLLOWUP[method]
        else:
            row["set_type"] = "Normal"
        work_seen = True
    return output


def validate_method_sets(method, set_rows):
    method = canonical_training_method(method)
    rows = set_rows or []
    work = [row for row in rows if not is_warmup_set_type(row.get("set_type", "Normal"))]
    if not work:
        return False, "Add at least one working set."
    reconciled = reconcile_method_sets(method, rows)
    current = [canonical_set_type(row.get("set_type", "Normal")) for row in rows]
    expected = [canonical_set_type(row.get("set_type", "Normal")) for row in reconciled]
    if current != expected:
        return False, f"{method} has an invalid set sequence."
    return True, ""


def method_set_uses_rir(method, set_type):
    """Whether this exercise method meaningfully records RIR for this row."""
    method = canonical_training_method(method)
    if is_warmup_set_type(set_type):
        return False
    # Anchor effort may be observed independently of the method's label.
    # Cluster and continuation fragments do not become ordinary RM tests.
    return method == "Straight" or (method != "Cluster" and method_calibration_anchor(method, set_type))


def method_calibration_anchor(method, set_type):
    """Return True when this row is the method's strength/progression anchor."""
    method = canonical_training_method(method)
    set_type = canonical_set_type(set_type)
    if is_warmup_set_type(set_type):
        return False
    if method == "Straight":
        return set_type == "Normal"
    if method == "AMRAP":
        return set_type == "AMRAP"
    if method == "Cluster":
        return set_type == "Cluster Set"
    if method in ACTIVATION_FOLLOWUP:
        return set_type == "Activation"
    return False


def method_progression_managed_set(method, set_type):
    """Whether the method progression engine owns load guidance for this row."""
    method = canonical_training_method(method)
    set_type = canonical_set_type(set_type)
    if is_warmup_set_type(set_type):
        return False
    if method == "Straight":
        # Top/back-off remain deliberately user-authored until they receive a
        # dedicated role algorithm; ordinary Straight rows use their configured policy.
        return set_type == "Normal"
    return set_type in allowed_set_types_for_method(method)


def canonical_set_type(value):
    """Normalize presentation aliases without rewriting stored legacy history."""
    text = str(value or "").strip()
    if text.casefold() in {"normal", "straight", "straight (normal)"}:
        return "Normal"
    return text


def display_set_type(value):
    """User-facing name for a stored set type."""
    canonical = canonical_set_type(value)
    return "Straight (Normal)" if canonical == "Normal" else canonical


def is_straight_set_type(value):
    return canonical_set_type(value) == "Normal"


def is_warmup_set_type(value):
    """Return True for every supported spelling of the warm-up set type."""
    set_type = str(value or "").strip().casefold()
    return set_type in {"warm-up", "warmup", "warm up"}


def is_hypertrophy_working_set(row):
    """Return True for a completed set that should count toward weekly volume."""
    if not _row_completed(row):
        return False
    return not is_warmup_set_type(row.get("set_type", "Normal"))


def _muscle_snapshot(exercise_name):
    details = read_exercise_details(exercise_name)
    return {"muscle_metadata_recorded": "1", "primary_muscles_snapshot": details.get("primary_muscles", ""),
            "secondary_muscles_snapshot": details.get("secondary_muscles", "")}


@_locked
def initialize_volume_rows(rows):
    """Initialize newly authored active rows; never call on historical migrations."""
    volume_accounting.assign_groups(rows)
    snapshots = {}
    for row in rows:
        if row.get("muscle_metadata_recorded") != "1":
            name = row["exercise_name"]
            if name not in snapshots: snapshots[name] = _muscle_snapshot(name)
            row.update(snapshots[name])
    return rows


@_locked
def volume_report(rows, *, planned=False, report_groups=False):
    """Separate work categories and direct/indirect tagged involvement."""
    prepared, cache = [], {}
    for source in rows or []:
        row = dict(source)
        name = str(row.get("exercise_name", "")).strip()
        if not name:
            continue
        if row.get("muscle_metadata_recorded") == "1":
            primary, secondary = row.get("primary_muscles_snapshot", ""), row.get("secondary_muscles_snapshot", "")
        else:
            if name.casefold() not in cache: cache[name.casefold()] = read_exercise_details(name)
            details = cache[name.casefold()]
            primary, secondary = details.get("primary_muscles", ""), details.get("secondary_muscles", "")
        def tags(value):
            result = normalize_muscle_list(value, exercise_name=name)
            return {volume_landmarks.report_group_for_muscle(tag) if report_groups else tag for tag in result}
        row["_primary"] = tags(primary)
        row["_secondary"] = tags(secondary) - row["_primary"]
        prepared.append(row)
    result = volume_accounting.summarize(prepared, planned=planned)
    for kind in ("direct", "indirect"):
        result[kind] = dict(sorted(result[kind].items(), key=lambda item: (RP_MUSCLE_GROUPS.index(item[0]) if item[0] in RP_MUSCLE_GROUPS else len(RP_MUSCLE_GROUPS), item[0])))
    return result


@_locked
def completed_primary_muscle_set_counts(rows, *, report_groups=False):
    """Compatibility count: conventional direct sets only, never mini-segments."""
    return {name: metrics["conventional_sets"] for name, metrics in volume_report(rows, report_groups=report_groups)["direct"].items()
            if metrics["conventional_sets"]}


def _planned_volume_rows(exercises, scope, snapshots=None):
    """Copy a plan into scoped report rows without changing its stored fields."""
    rows = []
    snapshots = {} if snapshots is None else snapshots
    for index, exercise in enumerate(exercises):
        name = str(exercise.get("exercise_name", "")).strip()
        if not name:
            continue
        key = name.casefold()
        if key not in snapshots:
            snapshots[key] = _muscle_snapshot(name)
        group = [{**source, "exercise_name": name, "set_number": number,
                  "completed": True, "volume_scope": f"{scope}/{index}",
                  "training_method": exercise.get("training_method", "Straight"),
                  **snapshots[key]}
                 for number, source in enumerate(exercise.get("sets", []), 1)]
        volume_accounting.assign_groups(group)
        rows.extend(group)
    return rows


@_locked
def workout_volume_report(exercises, *, report_groups=False):
    """Raw planned work per workout; protocols and indirect tags stay separate."""
    return volume_report(_planned_volume_rows(exercises, "workout"),
                         planned=True, report_groups=report_groups)


@_locked
def mesocycle_volume_report(cycle=None):
    """Repeating Build template accounting, with matching seven-day rates."""
    cycle = _normalize_mesocycle(cycle or active_mesocycle() or _mesocycle_defaults())
    rows, cache, snapshots = [], {}, {}
    for day, entry in sorted(mesocycle_day_schedule_entries(cycle["cycle_id"]).items()):
        wid = entry.get("workout_id", "")
        if not wid: continue
        if wid not in cache: cache[wid] = read_workout(wid)
        workout = cache[wid]
        if not workout: continue
        rows.extend(_planned_volume_rows(workout.get("exercises", []), f"{day}/{wid}", snapshots))
    result = volume_report(rows, planned=True, report_groups=True)
    days = int(cycle["microcycle_days"])
    result.update(period_days=days, weekly_totals=volume_accounting.scaled(result["totals"], days),
                  weekly_direct={key: volume_accounting.scaled(value, days) for key, value in result["direct"].items()},
                  weekly_indirect={key: volume_accounting.scaled(value, days) for key, value in result["indirect"].items()})
    return result


@_locked
def mesocycle_planned_primary_set_counts(cycle=None):
    """Raw period counts of conventional direct sets; protocols are separate."""
    return {name: metrics["conventional_sets"] for name, metrics in mesocycle_volume_report(cycle)["direct"].items() if metrics["conventional_sets"]}


@_locked
def mesocycle_weekly_primary_set_counts(cycle=None):
    """Conventional direct sets normalized to seven days."""
    return {name: metrics["conventional_sets"] for name, metrics in mesocycle_volume_report(cycle)["weekly_direct"].items() if metrics["conventional_sets"]}


@_locked
def read_workout_details(workout_id):
    ensure_data()
    workout_id = str(workout_id or "").strip()

    defaults = {
        "workout_id": workout_id,
        "description": "",
        "note": "",
        "set_seconds": "45",
        "set_overhead_seconds": "30",
        "transition_seconds": "300",
        "session_overhead_seconds": "300",
    }

    for row in _read_csv(WORKOUT_DETAILS_FILE):
        if row.get("workout_id", "") == workout_id:
            result = dict(defaults)
            result.update({key: row.get(key, value) or value for key, value in defaults.items()})
            result["description"] = row.get("description", "")
            result["note"] = row.get("note", "")
            return result

    return defaults


def _positive_int(value, default):
    try:
        return max(0, int(float(value)))
    except (TypeError, ValueError):
        return int(default)


@_locked
def save_workout_details(
    workout_id,
    description,
    note,
    set_seconds=45,
    set_overhead_seconds=30,
    transition_seconds=300,
    session_overhead_seconds=300,
):
    ensure_data()
    workout_id = str(workout_id or "").strip()
    if not workout_id:
        return

    set_seconds = max(1, _positive_int(set_seconds, 45))
    set_overhead_seconds = parse_duration(set_overhead_seconds, default=30)
    transition_seconds = parse_duration(transition_seconds, default=300)
    session_overhead_seconds = parse_duration(session_overhead_seconds, default=300)

    rows = _read_csv(WORKOUT_DETAILS_FILE)
    updated = False
    values = {
        "description": (description or "").strip(),
        "note": (note or "").strip(),
        "set_seconds": str(set_seconds),
        "set_overhead_seconds": str(set_overhead_seconds),
        "transition_seconds": str(transition_seconds),
        "session_overhead_seconds": str(session_overhead_seconds),
    }

    for row in rows:
        if row.get("workout_id", "") == workout_id:
            row.update(values)
            updated = True
            break

    if not updated:
        rows.append({"workout_id": workout_id, **values})

    _write_csv(WORKOUT_DETAILS_FILE, WORKOUT_DETAIL_FIELDS, rows)


@_locked
def estimate_active_workout_seconds(active):
    """Estimate a realistic session duration from work, rest and transitions."""
    if not active:
        return 0

    rows = list(active.get("rows", []))
    if not rows:
        return 0

    details = read_workout_details(active.get("workout_id", ""))
    workout_set_seconds = max(1, _positive_int(details.get("set_seconds"), 45))
    set_overhead = _positive_int(details.get("set_overhead_seconds"), 30)
    transition = _positive_int(details.get("transition_seconds"), 300)
    session_overhead = _positive_int(details.get("session_overhead_seconds"), 300)

    total = session_overhead

    for index, row in enumerate(rows):
        exercise_name = row.get("exercise_name", "")
        exercise_details = read_exercise_details(exercise_name)
        exercise_set_seconds = _positive_int(exercise_details.get("set_seconds", ""), 0)
        if exercise_set_seconds <= 0:
            exercise_set_seconds = workout_set_seconds

        # Lifting time plus a small setup/logging allowance for each set.
        total += exercise_set_seconds + set_overhead

        if index >= len(rows) - 1:
            continue

        next_exercise = rows[index + 1].get("exercise_name", "")
        if next_exercise == exercise_name:
            # Programmed rest applies between sets of the same exercise.
            total += parse_duration(row.get("rest_seconds", 0), default=0)
        else:
            # Moving/setup between exercises replaces the normal set rest.
            total += transition

    return total


def _mesocycle_intro_seen_map():
    """Return persisted calibration state keyed by mesocycle ID."""
    raw = read_settings().get("mesocycle_intro_seen_exercises", "{}")
    try:
        values = json.loads(raw)
    except (TypeError, ValueError, json.JSONDecodeError):
        values = {}

    if not isinstance(values, dict):
        return {}

    output = {}
    for cycle_id, placements in values.items():
        if not isinstance(placements, list):
            continue
        normalized = []
        for placement in placements:
            if isinstance(placement, dict):
                workout_id = str(placement.get("workout_id", "") or "").strip()
                exercise_name = str(
                    placement.get("exercise_name", "") or ""
                ).strip()
                if exercise_name:
                    normalized.append(
                        {
                            "workout_id": workout_id,
                            "exercise_name": exercise_name,
                            "training_method": canonical_training_method(
                                placement.get("training_method", "Straight")
                            ),
                        }
                    )
            elif isinstance(placement, str) and placement.strip():
                # Older builds tracked only exercise name. Do not let that global
                # state suppress the new per-workout calibration requirement.
                normalized.append(
                    {
                        "workout_id": "",
                        "exercise_name": placement.strip(),
                        "training_method": "Straight",
                    }
                )
        output[str(cycle_id)] = normalized
    return output


def _mesocycle_history_has_calibration(
    cycle_id, workout_id, exercise_name, training_method="Straight"
):
    """Recover calibration state from completed sets in this exact mesocycle.

    Calibration markers were introduced and refined over time.  Older cycles can
    therefore contain valid completed anchor sets without the newest
    per-workout/per-method settings marker.  The saved session itself is stronger
    evidence than that auxiliary marker, especially when resuming an accidentally
    ended cycle.
    """
    cycle_key = str(cycle_id or "").strip()
    workout_key = str(workout_id or "").strip().casefold()
    exercise_key = str(exercise_name or "").strip().casefold()
    method = canonical_training_method(training_method)
    if not cycle_key or not workout_key or not exercise_key:
        return False

    grouped = {}
    for row in _read_sets_cached():
        if deloads.is_recovery(row):
            continue
        if str(row.get("cycle_id", "") or "").strip() != cycle_key:
            continue
        if str(row.get("workout_id", "") or "").strip().casefold() != workout_key:
            continue
        if (
            str(row.get("exercise_name", "") or "").strip().casefold()
            != exercise_key
        ):
            continue
        session_id = str(row.get("session_id", "") or "").strip()
        if session_id:
            grouped.setdefault(session_id, []).append(row)

    for session_rows in grouped.values():
        explicit_method = next(
            (
                str(row.get("training_method", "") or "").strip()
                for row in session_rows
                if str(row.get("training_method", "") or "").strip()
            ),
            "",
        )
        session_method = (
            canonical_training_method(explicit_method)
            if explicit_method
            else infer_training_method(session_rows)
        )
        if session_method != method:
            continue

        for row in session_rows:
            if str(row.get("completed", "1") or "1") == "0":
                continue
            if not method_calibration_anchor(method, row.get("set_type", "Normal")):
                continue
            try:
                weight = float(str(row.get("weight", "") or "").strip())
                reps = float(str(row.get("reps", "") or "").strip())
            except (TypeError, ValueError):
                continue
            if weight > 0 and reps > 0:
                return True

    return False


@_locked
def mesocycle_intro_seen(
    cycle_id, workout_id, exercise_name, training_method="Straight"
):
    cycle_id = str(cycle_id or "").strip()
    workout_key = str(workout_id or "").strip().casefold()
    exercise_key = str(exercise_name or "").strip().casefold()
    method_key = canonical_training_method(training_method).casefold()
    if not cycle_id or not workout_key or not exercise_key:
        return False

    for placement in _mesocycle_intro_seen_map().get(cycle_id, []):
        placement_method = canonical_training_method(
            placement.get("training_method", "Straight")
        ).casefold()
        if (
            str(placement.get("workout_id", "")).strip().casefold() == workout_key
            and str(placement.get("exercise_name", "")).strip().casefold() == exercise_key
            and placement_method == method_key
        ):
            return True

    # If the auxiliary marker is missing (common for older/resumed cycles), a
    # completed anchor set saved under this same cycle/workout/method proves that
    # calibration already happened.  Do not force the user to recalibrate.
    return _mesocycle_history_has_calibration(
        cycle_id, workout_key, exercise_key, training_method
    )


@_locked
def mark_mesocycle_intro_seen(
    cycle_id, workout_id, exercise_name, training_method="Straight"
):
    cycle_id = str(cycle_id or "").strip()
    workout_id = str(workout_id or "").strip()
    exercise_name = str(exercise_name or "").strip()
    training_method = canonical_training_method(training_method)
    if not cycle_id or not workout_id or not exercise_name:
        return

    state = _mesocycle_intro_seen_map()
    placements = list(state.get(cycle_id, []))
    workout_key = workout_id.casefold()
    exercise_key = exercise_name.casefold()
    method_key = training_method.casefold()
    if any(
        str(item.get("workout_id", "")).strip().casefold() == workout_key
        and str(item.get("exercise_name", "")).strip().casefold() == exercise_key
        and canonical_training_method(
            item.get("training_method", "Straight")
        ).casefold() == method_key
        for item in placements
    ):
        return

    placements.append(
        {
            "workout_id": workout_id,
            "exercise_name": exercise_name,
            "training_method": training_method,
        }
    )
    state[cycle_id] = placements
    settings = read_settings()
    settings["mesocycle_intro_seen_exercises"] = json.dumps(
        state, ensure_ascii=False
    )
    save_settings(settings)


def _mesocycle_defaults():
    return {
        "cycle_id": "",
        "name": "Mesocycle",
        "start_date": datetime.now().date().isoformat(),
        "microcycle_days": "7",
        "length_value": "5",
        "length_unit": "microcycles",
        "deload_microcycles": "1",
        "start_rir": "3",
        "end_rir": "1",
        "deload_rir": "4",
        **deloads.settings({}),
        "rir_lock": "1",
        "rest_timer_lock": "0",
        "show_last_week_reps": "0",
        "setup_complete": "0",
        "active": "1",
    }


def mesocycle_defaults():
    return dict(_mesocycle_defaults())


def _normalize_mesocycle(row):
    result = _mesocycle_defaults()
    result.update(row or {})
    result.update(deloads.settings(result))
    result["microcycle_days"] = str(max(1, _positive_int(result.get("microcycle_days"), 7)))
    result["length_value"] = str(max(1, _positive_int(result.get("length_value"), 5)))
    unit = str(result.get("length_unit", "microcycles") or "microcycles").lower()
    # New cycles are stored directly as a number of repeating microcycles.
    # Keep weeks/months readable for older CSV rows so their historical dates
    # remain stable until the user edits/saves them in the new UI.
    result["length_unit"] = (
        unit if unit in {"microcycles", "weeks", "months"} else "microcycles"
    )
    result["deload_microcycles"] = str(max(0, _positive_int(result.get("deload_microcycles"), 1)))
    for key, default in (("start_rir", 3), ("end_rir", 1), ("deload_rir", 4)):
        try:
            result[key] = str(float(result.get(key, default)))
        except (TypeError, ValueError):
            result[key] = str(default)
    # RIR is locked by default, but Advanced Mode may deliberately unlock it.
    result["rir_lock"] = (
        "0" if str(result.get("rir_lock", "1")) == "0" else "1"
    )
    result["rest_timer_lock"] = (
        "1" if str(result.get("rest_timer_lock", "0")) == "1" else "0"
    )
    # Retired in v57. Keep the legacy field only so older CSV files remain
    # readable; it no longer changes workout UI or behavior.
    result["show_last_week_reps"] = "0"
    result["setup_complete"] = (
        "1" if str(result.get("setup_complete", "0")) == "1" else "0"
    )
    return result


@_locked
def active_mesocycle():
    ensure_data()
    for row in reversed(_read_csv(MESOCYCLES_FILE)):
        if row.get("active", "0") == "1":
            return _normalize_mesocycle(row)
    return None


@_locked
def mesocycle_history(limit=6):
    ensure_data()
    rows = [_normalize_mesocycle(row) for row in reversed(_read_csv(MESOCYCLES_FILE))]
    return rows[:limit] if limit is not None else rows


@_locked
def get_mesocycle(cycle_id):
    ensure_data()
    cycle_id = str(cycle_id or "").strip()
    for row in _read_csv(MESOCYCLES_FILE):
        if row.get("cycle_id") == cycle_id:
            return _normalize_mesocycle(row)
    return None


@_locked
def update_mesocycle(cycle_id, config):
    """Update an existing cycle without making it the active cycle."""
    ensure_data()
    cycle_id = str(cycle_id or "").strip()
    rows = _read_csv(MESOCYCLES_FILE)
    found = False

    for row in rows:
        if row.get("cycle_id") != cycle_id:
            continue

        active = row.get("active", "0")
        setup_complete = row.get("setup_complete", "1")
        values = _normalize_mesocycle({**row, **(config or {})})
        if error := deloads.effort_error(values):
            raise ValueError(error)
        values["cycle_id"] = cycle_id
        values["name"] = (values.get("name") or "Mesocycle").strip() or "Mesocycle"
        values["start_date"] = (
            values.get("start_date") or datetime.now().date().isoformat()
        ).strip()
        values["active"] = active
        values["setup_complete"] = setup_complete
        row.update(values)
        found = True
        break

    if found:
        _write_csv(MESOCYCLES_FILE, MESOCYCLE_FIELDS, rows)
    return found


@_locked
def save_mesocycle(config):
    ensure_data()
    values = _normalize_mesocycle(config)
    if error := deloads.effort_error(values):
        raise ValueError(error)
    cycle_id = str(values.get("cycle_id", "") or "").strip() or uuid.uuid4().hex[:8]
    values["cycle_id"] = cycle_id
    values["name"] = (values.get("name") or "Mesocycle").strip() or "Mesocycle"
    values["start_date"] = (values.get("start_date") or datetime.now().date().isoformat()).strip()
    values["active"] = "1"

    rows = _read_csv(MESOCYCLES_FILE)
    found = False
    for row in rows:
        if row.get("cycle_id") == cycle_id:
            row.update(values)
            found = True
        else:
            row["active"] = "0"
    if not found:
        for row in rows:
            row["active"] = "0"
        rows.append(values)

    _write_csv(MESOCYCLES_FILE, MESOCYCLE_FIELDS, rows)
    return cycle_id


@_locked
def end_mesocycle(cycle_id):
    ensure_data()
    rows = _read_csv(MESOCYCLES_FILE)
    for row in rows:
        if row.get("cycle_id") == cycle_id:
            row["active"] = "0"
    _write_csv(MESOCYCLES_FILE, MESOCYCLE_FIELDS, rows)


@_locked
def continue_mesocycle(cycle_id):
    """Reactivate the same mesocycle instead of cloning it.

    Continuing is primarily an undo for an accidentally ended cycle.  Keeping
    the same cycle ID preserves the original start date, repeating-workout
    position, calibration state, and history relationship.  Any other active
    mesocycle is ended, matching ``save_mesocycle()``'s single-active-cycle
    invariant.
    """
    ensure_data()
    cycle_id = str(cycle_id or "").strip()
    if not cycle_id:
        return None

    rows = _read_csv(MESOCYCLES_FILE)
    found = False
    for row in rows:
        if row.get("cycle_id") == cycle_id:
            row["active"] = "1"
            found = True
        else:
            row["active"] = "0"

    if not found:
        return None

    _write_csv(MESOCYCLES_FILE, MESOCYCLE_FIELDS, rows)
    return cycle_id


@_transactional
def delete_mesocycle(cycle_id):
    ensure_data()
    cycle_id = str(cycle_id or "")
    _write_csv(
        MESOCYCLES_FILE,
        MESOCYCLE_FIELDS,
        [row for row in _read_csv(MESOCYCLES_FILE) if row.get("cycle_id") != cycle_id],
    )
    _write_csv(
        MESOCYCLE_SCHEDULE_FILE,
        MESOCYCLE_SCHEDULE_FIELDS,
        [row for row in _read_csv(MESOCYCLE_SCHEDULE_FILE) if row.get("cycle_id") != cycle_id],
    )


@_locked
def mesocycle_has_planned_workouts(cycle_id):
    return any(
        bool((row.get("workout_id") or "").strip())
        for row in mesocycle_day_schedule_entries(cycle_id).values()
    )


@_locked
def mark_mesocycle_setup_complete(cycle_id):
    cycle = active_mesocycle()
    if not cycle or cycle.get("cycle_id") != cycle_id:
        return
    if not mesocycle_has_planned_workouts(cycle_id):
        return
    cycle["setup_complete"] = "1"
    save_mesocycle(cycle)


@_locked
def mesocycle_length_microcycles(cycle=None):
    """Return the plan length expressed as repeating microcycles.

    New Gymer plans store length directly in microcycles. Legacy rows may still
    say weeks/months; convert those only for display/editing without mutating the
    historical row on read.
    """
    cycle = _normalize_mesocycle(cycle or active_mesocycle() or _mesocycle_defaults())
    micro_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))
    length_value = max(1, _positive_int(cycle.get("length_value"), 5))
    unit = str(cycle.get("length_unit", "microcycles") or "microcycles").lower()
    if unit == "microcycles":
        return length_value
    legacy_days = length_value * (30 if unit == "months" else 7)
    return max(1, (legacy_days + micro_days - 1) // micro_days)


@_locked
def mesocycle_status(cycle=None, today=None):
    cycle = _normalize_mesocycle(cycle or active_mesocycle() or _mesocycle_defaults())
    try:
        start = datetime.fromisoformat(cycle["start_date"]).date()
    except (TypeError, ValueError):
        start = datetime.now().date()

    if today is None:
        today = datetime.now().date()
    elif isinstance(today, str):
        today = datetime.fromisoformat(today).date()

    micro_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))
    length_value = max(1, _positive_int(cycle.get("length_value"), 5))
    unit = str(cycle.get("length_unit", "microcycles") or "microcycles").lower()
    if unit == "microcycles":
        total_microcycles = length_value
        total_days = total_microcycles * micro_days
    else:
        # Legacy weeks/months retain their original date span until explicitly
        # saved through the new microcycle-based editor.
        total_days = length_value * (30 if unit == "months" else 7)
        total_microcycles = max(1, (total_days + micro_days - 1) // micro_days)
    deload = min(max(0, _positive_int(cycle.get("deload_microcycles"), 1)), max(0, total_microcycles - 1))
    build_microcycles = max(1, total_microcycles - deload)

    elapsed = (today - start).days
    upcoming = elapsed < 0
    complete = elapsed >= total_days
    effective_elapsed = max(0, min(elapsed, max(0, total_days - 1)))
    current_microcycle = min(total_microcycles, effective_elapsed // micro_days + 1)
    day_in_microcycle = effective_elapsed % micro_days + 1

    if upcoming:
        phase = "Upcoming"
    elif complete:
        phase = "Complete"
    elif deload and current_microcycle > build_microcycles:
        phase = "Deload"
    else:
        phase = "Build"

    try:
        # RIR prescriptions are discrete by design. Older data may contain a
        # decimal string, so normalize it once here and keep every downstream
        # caller on integer RIR values.
        start_rir = int(round(float(cycle.get("start_rir", 3))))
        end_rir = int(round(float(cycle.get("end_rir", 1))))
        deload_rir = int(round(float(cycle.get("deload_rir", 4))))
    except (TypeError, ValueError):
        start_rir, end_rir, deload_rir = 3, 1, 4

    if phase == "Deload":
        suggested_rir = deload_rir
    elif phase in {"Build", "Complete"}:
        if build_microcycles <= 1:
            suggested_rir = end_rir
        else:
            position = min(current_microcycle, build_microcycles) - 1
            if position <= 0:
                suggested_rir = start_rir
            elif position >= build_microcycles - 1:
                # Always land exactly on the configured final-build RIR.
                suggested_rir = end_rir
            else:
                direction = 1 if end_rir > start_rir else -1
                distance = abs(end_rir - start_rir)
                suggested_rir = start_rir + direction * min(position, distance)
    else:
        suggested_rir = start_rir

    progress = 0.0 if upcoming else min(1.0, max(0.0, elapsed / max(1, total_days)))
    end_date = start.fromordinal(start.toordinal() + total_days - 1)
    remaining_days = max(0, total_days - max(0, elapsed))

    return {
        "cycle": cycle,
        "start_date": start.isoformat(),
        "end_date": end_date.isoformat(),
        "total_days": total_days,
        "total_microcycles": total_microcycles,
        "build_microcycles": build_microcycles,
        "deload_microcycles": deload,
        "current_microcycle": current_microcycle,
        "day_in_microcycle": day_in_microcycle,
        "phase": phase,
        "complete": complete,
        "upcoming": upcoming,
        "progress": progress,
        "remaining_days": remaining_days,
        "suggested_rir": suggested_rir,
    }


def _mesocycle_for_id(cycle_id):
    cycle_id = str(cycle_id or "").strip()
    if not cycle_id:
        return None
    active = active_mesocycle()
    if active and active.get("cycle_id") == cycle_id:
        return active
    for row in mesocycle_history(limit=None):
        if row.get("cycle_id") == cycle_id:
            return row
    return None


@_locked
def mesocycle_day_schedule_entries(cycle_id):
    """Return the repeating schedule keyed by day within one microcycle.

    A mesocycle has exactly one workout schedule.  The same day-by-day plan is
    reused for every microcycle; later microcycles cannot override exercises or
    workouts independently.
    """
    ensure_data()
    cycle_id = str(cycle_id or "").strip()
    cycle = _normalize_mesocycle(_mesocycle_for_id(cycle_id) or _mesocycle_defaults())
    micro_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))

    result = {}
    for row in _read_csv(MESOCYCLE_SCHEDULE_FILE):
        if row.get("cycle_id") != cycle_id:
            continue
        try:
            day_number = int(row.get("day_number", "0") or 0)
        except (TypeError, ValueError):
            continue
        if 1 <= day_number <= micro_days:
            result[day_number] = {
                "cycle_id": cycle_id,
                "day_number": day_number,
                "workout_id": row.get("workout_id", ""),
            }
    return result


@_locked
def mesocycle_day_schedule(cycle_id):
    return {
        day_number: row.get("workout_id", "")
        for day_number, row in mesocycle_day_schedule_entries(cycle_id).items()
    }


def _write_mesocycle_schedule_entries(cycle_id, entries):
    other_rows = [
        row
        for row in _read_csv(MESOCYCLE_SCHEDULE_FILE)
        if row.get("cycle_id") != cycle_id
    ]
    cycle_rows = []
    for day_number in sorted(entries):
        row = entries[day_number]
        cycle_rows.append(
            {
                "cycle_id": cycle_id,
                "day_number": str(day_number),
                "workout_id": str(row.get("workout_id", "") or ""),
            }
        )
    _write_csv(
        MESOCYCLE_SCHEDULE_FILE,
        MESOCYCLE_SCHEDULE_FIELDS,
        other_rows + cycle_rows,
    )


@_locked
def save_mesocycle_day_schedule(cycle_id, schedule, microcycle_days=None):
    """Replace the complete repeating day schedule for one mesocycle."""
    ensure_data()
    cycle_id = str(cycle_id or "").strip()
    if not cycle_id:
        return
    cycle = _normalize_mesocycle(_mesocycle_for_id(cycle_id) or _mesocycle_defaults())
    if microcycle_days is None:
        microcycle_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))
    else:
        microcycle_days = max(1, _positive_int(microcycle_days, 7))

    entries = {}
    for day_number in range(1, microcycle_days + 1):
        workout_id = str((schedule or {}).get(day_number, "") or "").strip()
        entries[day_number] = {
            "cycle_id": cycle_id,
            "day_number": day_number,
            "workout_id": workout_id,
        }
    _write_mesocycle_schedule_entries(cycle_id, entries)


@_locked
def set_mesocycle_day_workout(cycle_id, day_number, workout_id, cycle=None):
    """Set one day of the repeating mesocycle schedule.

    The caller may pass any absolute cycle day, but it is always mapped back to
    its day inside the repeating microcycle.  There is intentionally no concept
    of a later-microcycle workout override.
    """
    ensure_data()
    try:
        day_number = max(1, int(day_number))
    except (TypeError, ValueError):
        return

    cycle_id = str(cycle_id or "").strip()
    workout_id = str(workout_id or "").strip()
    if not cycle_id:
        return

    cycle = _normalize_mesocycle(cycle or _mesocycle_for_id(cycle_id) or _mesocycle_defaults())
    micro_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))
    template_day = ((day_number - 1) % micro_days) + 1

    entries = mesocycle_day_schedule_entries(cycle_id)
    entries[template_day] = {
        "cycle_id": cycle_id,
        "day_number": template_day,
        "workout_id": workout_id,
    }
    _write_mesocycle_schedule_entries(cycle_id, entries)



def _session_counts_by_date():
    counts = {}
    seen = set()
    for row in _read_sets_cached():
        if row.get("completed", "1") == "0":
            continue
        session_id = row.get("session_id", "")
        raw_date = row.get("date", "")
        if not session_id or not raw_date:
            continue
        try:
            date_key = datetime.fromisoformat(raw_date).date().isoformat()
        except (TypeError, ValueError):
            date_key = str(raw_date)[:10]
        key = (session_id, date_key)
        if key in seen:
            continue
        seen.add(key)
        counts[date_key] = counts.get(date_key, 0) + 1
    return counts


@_locked
def mesocycle_calendar_days(cycle=None):
    ensure_data()
    cycle = _normalize_mesocycle(cycle or active_mesocycle() or _mesocycle_defaults())
    status = mesocycle_status(cycle)
    start = datetime.fromisoformat(status["start_date"]).date()
    micro_days = max(1, _positive_int(cycle.get("microcycle_days"), 7))
    schedule_entries = mesocycle_day_schedule_entries(cycle.get("cycle_id", ""))
    workouts = {row["workout_id"]: row["name"] for row in read_workouts()}
    session_counts = _session_counts_by_date()
    today = datetime.now().date()

    days = []
    for index in range(status["total_days"]):
        day_number = index + 1
        date = start + timedelta(days=index)
        microcycle = index // micro_days + 1
        day_in_microcycle = index % micro_days + 1
        schedule_entry = schedule_entries.get(day_in_microcycle, {})
        workout_id = schedule_entry.get("workout_id", "")
        days.append(
            {
                "day_number": day_number,
                "date": date.isoformat(),
                "microcycle": microcycle,
                "day_in_microcycle": day_in_microcycle,
                "workout_id": workout_id,
                "workout_name": workouts.get(workout_id, ""),
                "completed_sessions": session_counts.get(date.isoformat(), 0),
                "is_today": date == today,
            }
        )
    return days


@_locked
def active_cycle_locks():
    cycle = active_mesocycle()
    if not cycle:
        return {
            "rir_lock": False,
            "rest_timer_lock": False,
            "suggested_rir": None,
        }
    status = mesocycle_status(cycle)
    if status["phase"] not in {"Build", "Deload"}:
        return {"rir_lock": False, "rest_timer_lock": False, "suggested_rir": None}
    return {
        "rir_lock": cycle.get("rir_lock", "1") != "0",
        "rest_timer_lock": cycle.get("rest_timer_lock", "0") == "1",
        "suggested_rir": status.get("suggested_rir"),
    }


@_locked
def workout_has_active_cycle_warning(workout_id):
    cycle = active_mesocycle()
    if not cycle:
        return False
    # A cycle deliberately allows program edits, but keeping this signal in
    # storage makes the UI warning independent of how the editor was opened.
    return bool(workout_id)


@_locked
def read_workouts():
    ensure_data()
    return _read_csv(WORKOUTS_FILE)


@_locked
def read_exercises():
    ensure_data()
    return _read_csv(WORKOUT_EXERCISES_FILE)


@_locked
def workout_list_summaries():
    """Return lightweight workout-card data using one pass over each CSV.

    The Workout tab only needs exercise names, set counts, and primary muscles.
    Avoid loading full per-set templates and repeatedly rereading settings/details
    once for every workout card.
    """
    ensure_data()
    workouts = _read_csv(WORKOUTS_FILE)
    exercise_rows = _read_csv(WORKOUT_EXERCISES_FILE)
    template_rows = _read_csv(WORKOUT_SET_TEMPLATES_FILE)
    detail_rows = _read_csv(EXERCISE_DETAILS_FILE)

    template_counts = {}
    for row in template_rows:
        key = (row.get("workout_id", ""), str(row.get("order_index", "") or ""))
        template_counts[key] = template_counts.get(key, 0) + 1

    details_by_name = {
        str(row.get("exercise_name", "") or "").strip().casefold(): row
        for row in detail_rows
        if str(row.get("exercise_name", "") or "").strip()
    }
    grouped = {}
    for row in exercise_rows:
        grouped.setdefault(row.get("workout_id", ""), []).append(row)

    output = {}
    for workout in workouts:
        workout_id = workout.get("workout_id", "")
        rows = grouped.get(workout_id, [])
        rows = sorted(rows, key=lambda row: _positive_int(row.get("order_index"), 0))
        exercises = []
        muscles = set()
        has_sets = False

        for row in rows:
            name = str(row.get("exercise_name", "") or "").strip()
            if not name:
                continue
            set_count = max(0, _positive_int(row.get("target_sets"), 0))
            if set_count <= 0:
                set_count = template_counts.get(
                    (workout_id, str(row.get("order_index", "") or "")),
                    0,
                )
            has_sets = has_sets or set_count > 0
            exercises.append({"exercise_name": name, "set_count": set_count})

            raw_details = details_by_name.get(name.casefold(), {})
            default = DEFAULT_EXERCISE_DETAILS.get(name, {})
            primary_raw = (
                raw_details.get("primary_muscles", "")
                or default.get("primary_muscles", "")
            )
            muscles.update(normalize_muscle_list(primary_raw))

        output[workout_id] = {
            "workout_id": workout_id,
            "name": workout.get("name", "Workout"),
            "exercises": exercises,
            "has_sets": has_sets,
            "primary_muscles": [
                name for name in BODYBUILDING_MUSCLE_GROUPS if name in muscles
            ],
        }
    return output


@_locked
def read_workout(workout_id):
    ensure_data()

    workout = next(
        (row for row in read_workouts() if row["workout_id"] == workout_id),
        None,
    )

    if workout is None:
        return None

    exercises = [
        row
        for row in read_exercises()
        if row["workout_id"] == workout_id
    ]
    exercises.sort(key=lambda row: int(row["order_index"] or 0))

    template_rows = [
        row
        for row in _read_csv(WORKOUT_SET_TEMPLATES_FILE)
        if row["workout_id"] == workout_id
    ]

    output = []

    for exercise in exercises:
        order_index = exercise["order_index"]

        sets = [
            row
            for row in template_rows
            if row["order_index"] == order_index
        ]
        sets.sort(key=lambda row: int(row["set_number"] or 0))

        if not sets:
            sets = _build_initial_template_rows([exercise])

        training_method = resolve_training_method(exercise.get("training_method", ""), sets)
        output.append(
            {
                "exercise_name": exercise["exercise_name"],
                "training_method": training_method,
                "sets": [
                    {
                        "set_number": int(row.get("set_number", 1) or 1),
                        "weight": row.get("weight", ""),
                        "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
                        "reps": row.get("reps", ""),
                        "rest_seconds": parse_duration(
                            row.get("rest_seconds", ""),
                            default=int(
                                read_settings().get(
                                    "default_rest_seconds",
                                    "180",
                                )
                            ),
                        ),
                        "set_type": row.get("set_type", "Normal") or "Normal",
                        "protocol_group_start": row.get("protocol_group_start", ""),
                        **set_context.template_metadata(row),
                    }
                    for row in sets
                ],
            }
        )

    return {
        "workout_id": workout["workout_id"],
        "name": workout["name"],
        "exercises": output,
    }


@_transactional
def create_workout(name="New Workout"):
    ensure_data()

    workout_id = uuid.uuid4().hex[:8]
    workouts = read_workouts()

    workouts.append(
        {
            "workout_id": workout_id,
            "name": name.strip() or "New Workout",
        }
    )

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    return workout_id


@_transactional
def save_workout(workout_id, name, exercises):
    ensure_data()

    workouts = read_workouts()

    for workout in workouts:
        if workout["workout_id"] == workout_id:
            workout["name"] = name.strip() or workout["name"]
            break

    other_exercises = [
        row
        for row in read_exercises()
        if row["workout_id"] != workout_id
    ]

    other_templates = [
        row
        for row in _read_csv(WORKOUT_SET_TEMPLATES_FILE)
        if row["workout_id"] != workout_id
    ]

    new_exercises = []
    new_templates = []

    settings = read_settings()
    default_rest = int(settings.get("default_rest_seconds", "180") or 180)
    weight_unit = settings.get("unit", "kg")

    for order_index, exercise in enumerate(exercises, start=1):
        exercise_name = (exercise.get("exercise_name") or "").strip()
        if not exercise_name:
            continue

        training_method = canonical_training_method(exercise.get("training_method", "Straight"))
        set_rows = exercise.get("sets") or []
        if not set_rows:
            set_rows = [
                {
                    "weight": "",
                    "weight_unit": weight_unit,
                    "reps": "",
                    "rest_seconds": default_rest,
                    "set_type": "Normal",
                }
            ]
        set_rows = reconcile_method_sets(training_method, set_rows)

        first = set_rows[0]

        new_exercises.append(
            {
                "workout_id": workout_id,
                "order_index": order_index,
                "exercise_name": exercise_name,
                "target_sets": len(set_rows),
                "default_weight": str(first.get("weight", "") or "").strip(),
                "default_weight_unit": weight_unit,
                "default_reps": str(first.get("reps", "") or "").strip(),
                "rest_seconds": str(
                    parse_duration(
                        first.get("rest_seconds", ""),
                        default=default_rest,
                    )
                ),
                "training_method": training_method,
            }
        )

        for set_number, set_row in enumerate(set_rows, start=1):
            set_type = (set_row.get("set_type") or "Normal").strip() or "Normal"

            new_templates.append(
                {
                    "workout_id": workout_id,
                    "order_index": order_index,
                    "set_number": set_number,
                    "weight": str(set_row.get("weight", "") or "").strip(),
                    "weight_unit": weight_unit,
                    "reps": str(set_row.get("reps", "") or "").strip(),
                    "rest_seconds": str(
                        parse_duration(
                            set_row.get("rest_seconds", ""),
                            default=default_rest,
                        )
                    ),
                    "set_type": set_type,
                    "protocol_group_start": set_row.get("protocol_group_start", ""),
                    **set_context.template_metadata(set_row),
                }
            )

        add_catalog_exercise(exercise_name)

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(
        WORKOUT_EXERCISES_FILE,
        EXERCISE_FIELDS,
        other_exercises + new_exercises,
    )
    _write_csv(
        WORKOUT_SET_TEMPLATES_FILE,
        TEMPLATE_SET_FIELDS,
        other_templates + new_templates,
    )


@_transactional
def delete_workout(workout_id):
    """Delete a template while preserving completed workout history."""
    ensure_data()

    workouts = [
        row
        for row in read_workouts()
        if row["workout_id"] != workout_id
    ]

    exercises = [
        row
        for row in read_exercises()
        if row["workout_id"] != workout_id
    ]

    templates = [
        row
        for row in _read_csv(WORKOUT_SET_TEMPLATES_FILE)
        if row["workout_id"] != workout_id
    ]

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, exercises)
    _write_csv(WORKOUT_SET_TEMPLATES_FILE, TEMPLATE_SET_FIELDS, templates)

    workout_details = [
        row
        for row in _read_csv(WORKOUT_DETAILS_FILE)
        if row.get("workout_id") != workout_id
    ]
    _write_csv(WORKOUT_DETAILS_FILE, WORKOUT_DETAIL_FIELDS, workout_details)


# ----------------------------------------------------------------------
# HISTORY / ACTIVE WORKOUT
# ----------------------------------------------------------------------


@_locked
def latest_set_values(workout_id, exercise_name):
    ensure_data()

    matching = [
        row
        for row in _chronological_sets()
        if not deloads.is_recovery(row)
        and row.get("workout_id") == workout_id
        and row.get("exercise_name", "").casefold() == exercise_name.casefold()
        and row.get("completed", "1") != "0"
    ]

    return _latest_by_set_number(matching)


@_locked
def latest_exercise_values(exercise_name):
    ensure_data()

    matching = [
        row
        for row in _chronological_sets()
        if not deloads.is_recovery(row)
        and row.get("exercise_name", "").casefold() == exercise_name.casefold()
        and row.get("completed", "1") != "0"
    ]

    return _latest_by_set_number(matching)


@_locked
def latest_completed_exercise_set(exercise_name):
    """Return the newest completed exercise set with usable weight/reps."""
    ensure_data()

    for row in reversed(_chronological_sets()):
        if deloads.is_recovery(row):
            continue
        if (
            row.get("exercise_name", "").casefold() != exercise_name.casefold()
            or row.get("completed", "1") == "0"
        ):
            continue

        try:
            weight = float(str(row.get("weight", "") or "").strip())
            reps = float(str(row.get("reps", "") or "").strip())
        except (TypeError, ValueError):
            continue

        if weight <= 0 or reps <= 0:
            continue

        return dict(row)

    return None


@_locked
def latest_completed_straight_session(exercise_name, workout_id=None):
    """Newest saved Straight session, including missed and invalid working rows."""
    return [row for row in latest_completed_method_session(exercise_name, "Straight", workout_id=workout_id)
            if is_straight_set_type(row.get("set_type", "Normal"))]


@_locked
def latest_completed_straight_set(exercise_name):
    """
    Return the newest usable completed straight set for an exercise.

    "Normal" is accepted as the legacy/default straight-set label so older
    history still works if the user later renames that set type to "Straight".
    """
    ensure_data()

    for row in reversed(_chronological_sets()):
        if deloads.is_recovery(row):
            continue
        if (
            row.get("exercise_name", "").casefold() != exercise_name.casefold()
            or row.get("completed", "1") == "0"
            or not is_straight_set_type(row.get("set_type", "Normal"))
        ):
            continue

        try:
            weight = float(str(row.get("weight", "") or "").strip())
            reps = float(str(row.get("reps", "") or "").strip())
        except (TypeError, ValueError):
            continue

        if weight <= 0 or reps <= 0:
            continue

        return dict(row)

    return None


@_locked
def latest_completed_method_session(exercise_name, training_method, workout_id=None):
    """Return the newest saved session for one exercise/method, including missed rows."""
    ensure_data()
    exercise_key = str(exercise_name or "").strip().casefold()
    method = canonical_training_method(training_method)
    rows = [row for row in _chronological_sets()
            if not deloads.is_recovery(row) and (workout_id is None or row.get("workout_id") == workout_id)]

    grouped = {}
    for row in rows:
        if row.get("exercise_name", "").strip().casefold() != exercise_key:
            continue
        session_id = row.get("session_id", "")
        if session_id:
            grouped.setdefault(session_id, []).append(row)

    session_methods = {}
    for session_id, session_rows in grouped.items():
        explicit = next(
            (
                str(row.get("training_method", "") or "").strip()
                for row in session_rows
                if str(row.get("training_method", "") or "").strip()
            ),
            "",
        )
        session_methods[session_id] = (
            canonical_training_method(explicit)
            if explicit
            else infer_training_method(session_rows)
        )

    latest_session_id = ""
    for row in reversed(rows):
        if row.get("exercise_name", "").strip().casefold() != exercise_key:
            continue
        if is_warmup_set_type(row.get("set_type", "Normal")):
            continue
        session_id = row.get("session_id", "")
        if session_methods.get(session_id, "Straight") != method:
            continue
        latest_session_id = session_id
        if latest_session_id:
            break

    if not latest_session_id:
        return []

    output = []
    for row in grouped.get(latest_session_id, []):
        output.append({
            **_observation_metadata(row),
            "weight": row.get("weight", ""),
            "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
            "reps": row.get("reps", ""),
            "rir": row.get("rir", ""),
            "set_type": row.get("set_type", "Normal") or "Normal",
            "training_method": method,
            "completed": row.get("completed", "1") != "0",
            "set_number": int(row.get("set_number", 0) or 0),
            "session_id": latest_session_id,
            "date": row.get("date", ""),
        })
    output.sort(key=lambda item: item.get("set_number", 0))
    return output


@_locked
def latest_completed_method_anchor_set(exercise_name, training_method):
    """Newest usable progression-anchor row for the selected training method."""
    method = canonical_training_method(training_method)
    rows = latest_completed_method_session(exercise_name, method)
    for row in rows:
        if not row.get("completed", False):
            continue
        if not method_calibration_anchor(method, row.get("set_type", "Normal")):
            continue
        try:
            weight = float(str(row.get("weight", "") or "").strip())
            reps = float(str(row.get("reps", "") or "").strip())
        except (TypeError, ValueError):
            continue
        if weight > 0 and reps > 0:
            return dict(row)
    return None


@_locked
def pre_deload_session(cycle_id, workout_id, exercise_name, method):
    """Latest matching session before the fixed Build/Deload boundary."""
    cycle = get_mesocycle(cycle_id)
    if not cycle:
        return []
    start = datetime.fromisoformat(cycle["start_date"]).date()
    status = mesocycle_status(cycle, today=start)
    boundary = start + timedelta(days=status["build_microcycles"] * int(cycle["microcycle_days"]))
    grouped = {}
    for row in _chronological_sets():
        if row.get("cycle_id") != cycle_id or row.get("workout_id") != workout_id:
            continue
        if row.get("exercise_name", "").strip().casefold() != exercise_name.strip().casefold() or deloads.is_recovery(row):
            continue
        try:
            day = datetime.fromisoformat(row.get("date", "")).date()
        except (TypeError, ValueError):
            continue
        if start <= day < boundary:
            grouped.setdefault(row["session_id"], []).append(row)
    for group in reversed(list(grouped.values())):
        recorded = next((row.get("training_method") for row in group if row.get("training_method")), "")
        if resolve_training_method(recorded, group) == method:
            return sorted(group, key=lambda row: int(row.get("set_number", 0) or 0))
    return []


def _build_deload_rows(workout, rows, context):
    cycle = get_mesocycle(context.get("cycle_id"))
    if not cycle:
        return rows
    config = deloads.settings(cycle)
    effort_error = deloads.effort_error(cycle)
    manual = config["deload_policy"] == "manual" or bool(effort_error)
    if effort_error:
        # Keep legacy cycle data intact, but do not prescribe an invalid target.
        context["cycle_target_rir"] = ""
    output = []
    for name in dict.fromkeys(row["exercise_name"] for row in rows):
        group = [dict(row) for row in rows if row["exercise_name"] == name]
        work = [row for row in group if not is_warmup_set_type(row.get("set_type"))]
        method = group[0]["training_method"]
        reference = pre_deload_session(cycle["cycle_id"], workout["workout_id"], name, method)
        reference_work = [row for row in reference if not is_warmup_set_type(row.get("set_type"))]
        count = len(work) if manual else deloads.recovery_count(method, len(work), config["deload_volume_percent"])
        selected = group if manual else [row for row in group if is_warmup_set_type(row.get("set_type"))] + work[:count]
        working_index = 0
        for index, row in enumerate(selected, 1):
            warmup = is_warmup_set_type(row.get("set_type"))
            row.update(prescription_kind="deload_manual" if manual else "deload", source_method=method,
                       original_work_count=str(len(work)), deload_load_percent=config["deload_load_percent"],
                       deload_volume_percent=config["deload_volume_percent"])
            if effort_error:
                row["target_rir"] = ""
            if not manual:
                row.update(training_method="Straight", set_type="Warm-up" if warmup else "Normal",
                           planned_work_count=str(count) if count else "", set_number=index,
                           protocol_group_start="",
                           previous_weight="", previous_reps="", previous_rir="")
            if not warmup:
                ref = reference_work[working_index] if working_index < len(reference_work) else {}
                working_index += 1
                if ref.get("completed", "1") == "0" or set_context.comparison_error([ref], [row]):
                    ref = {}
                row.update(reference_session_id=ref.get("session_id", ""), reference_weight=ref.get("weight", ""),
                           reference_weight_unit=ref.get("weight_unit", row["weight_unit"]))
                if not manual:
                    details = read_exercise_details(name)
                    source_reps = progression._number(ref.get("reps"))
                    low = min(int(details["straight_rep_min"]), progression.CLUSTER_TARGET_REPS) if method == "Cluster" else int(details["straight_rep_min"])
                    row["target_reps"] = str(max(1, min(low, int(source_reps)))) if source_reps is not None and source_reps > 0 else str(low)
                    row["target_rir"] = context["cycle_target_rir"]
                    value = progression._number(convert_weight_value(ref.get("weight", ""), ref.get("weight_unit") or row["weight_unit"], row["weight_unit"]))
                    eligible = (row["load_mode"] == "external" and ref.get("load_mode", "external") == "external"
                                and method not in {"Cluster", "Mechanical Drop Set"}
                                and not (method == "Straight" and details["straight_progression"] == "manual"))
                    if eligible and value is not None and value > 0 and source_reps is not None and source_reps > 0:
                        step = exercise_weight_increment(name, row["weight_unit"])
                        row["prescribed_weight"] = deloads.recovery_weight(value, percent=config["deload_load_percent"], unit=row["weight_unit"], step=step)
            output.append(row)
    return output


@_locked
def build_active_workout(workout):
    rows = []
    started_at = ""
    weight_unit = read_settings().get("unit", "kg")
    performed_at = datetime.now().isoformat(timespec="seconds")
    context = _cycle_context(performed_at)

    for exercise in workout["exercises"]:
        exercise_name = exercise["exercise_name"]
        details = read_exercise_details(exercise_name)
        mode = details["load_mode"]
        training_method = resolve_training_method(
            exercise.get("training_method", ""), exercise.get("sets", [])
        )

        # Previous load may seed the active workout, but previously performed
        # reps are deliberately not surfaced as placeholders. Historical reps
        # remain available only to the progression algorithm.
        latest = latest_set_values(
            workout["workout_id"],
            exercise_name,
        )

        for set_number, set_row in enumerate(exercise.get("sets", []), start=1):
            previous = latest.get(set_number, {})
            row_context = set_context.resolve(set_row, details)
            if load_modes.normalize(previous.get("load_mode", "external")) != mode or not set_context.matches(previous, row_context):
                previous = {}

            previous_weight = str(
                previous.get("weight", "")
                or set_row.get("weight", "")
                or ""
            )
            # Keep the historical rep value in active-workout state so the
            # Advanced Mode opt-in can display it. Workout UI decides whether it
            # is visible; during a mesocycle the default is always hidden.
            history_reps = str(previous.get("reps", "") or "")
            previous_reps = str(
                history_reps or set_row.get("reps", "") or ""
            )
            previous_rir = str(previous.get("rir", "") or "")

            rows.append(
                {
                    "exercise_name": exercise_name,
                    "set_number": set_number,
                    "weight": "",
                    "weight_unit": weight_unit,
                    "reps": "",
                    "rir": "",
                    "target_rir": context["cycle_target_rir"] if method_set_uses_rir(training_method, set_row.get("set_type", "Normal")) else "",
                    "legacy_rir": "",
                    "load_mode": mode,
                    "previous_weight": previous_weight,
                    "previous_reps": previous_reps,
                    "previous_rir": previous_rir,
                    "last_week_reps": history_reps,
                    "set_type": set_row.get("set_type", "Normal") or "Normal",
                    "training_method": training_method,
                    "planned_work_count": str(sum(not is_warmup_set_type(item.get("set_type", "Normal")) for item in exercise.get("sets", []))),
                    "protocol_group_start": set_row.get("protocol_group_start", ""),
                    **row_context,
                    "context_override": set_context.template_metadata(set_row)["context_override"],
                    "stop_reason": "",
                    "actual_rest_seconds": "",
                    "note": "",
                    "completed": False,
                    "calibration_done": False,
                    "rest_seconds": parse_duration(
                        set_row.get("rest_seconds", ""),
                        default=int(
                            read_settings().get(
                                "default_rest_seconds",
                                "180",
                            )
                        ),
                    ),
                }
            )

    if context.get("cycle_phase") == "Deload":
        rows = _build_deload_rows(workout, rows, context)
    initialize_volume_rows(rows)

    return {
        "performed_at": performed_at,
        **context,
        "session_id": str(uuid.uuid4()),
        "workout_id": workout["workout_id"],
        "workout_name": workout["name"],
        "started_at": started_at,
        "timer_started": False,
        "timer_elapsed_seconds": 0,
        "rows": rows,
    }


@_locked
def save_active_workout(active):
    ensure_data()

    if not active:
        clear_active_workout()
        return

    rows = []
    if not active.get("session_id"):
        active["session_id"] = str(uuid.uuid4())
    # A delayed UI event must not resurrect a successfully finished session.
    if _saved_session_rows(active["session_id"]):
        return

    for row in active.get("rows", []):
        rows.append(
            {
                "session_id": active["session_id"],
                **{key: active.get(key, "") for key in ("performed_at", "cycle_id", "cycle_microcycle", "cycle_phase", "cycle_target_rir")},
                **_observation_metadata(row),
                "workout_id": active["workout_id"],
                "workout_name": active["workout_name"],
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": row.get("weight", ""),
                "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
                "reps": row.get("reps", ""),
                "rir": (
                    row.get("rir", "")
                    if method_set_uses_rir(
                        row.get("training_method", "Straight"),
                        row.get("set_type", "Normal"),
                    )
                    else ""
                ),
                "previous_weight": row.get("previous_weight", ""),
                "previous_reps": row.get("previous_reps", ""),
                "previous_rir": (
                    row.get("previous_rir", "")
                    if method_set_uses_rir(
                        row.get("training_method", "Straight"),
                        row.get("set_type", "Normal"),
                    )
                    else ""
                ),
                "last_week_reps": row.get("last_week_reps", ""),
                "set_type": row.get("set_type", "Normal") or "Normal",
                "training_method": canonical_training_method(row.get("training_method", "Straight")),
                "note": row.get("note", ""),
                "completed": "1" if row.get("completed", False) else "0",
                "calibration_done": (
                    "1" if row.get("calibration_done", False) else "0"
                ),
                "rest_seconds": str(row.get("rest_seconds", 180)),
                "rest_timer_state": active.get("rest_timer_state", ""),
                "started_at": active.get("started_at", ""),
                "timer_started": (
                    "1" if active.get("timer_started", False) else "0"
                ),
                "timer_elapsed_seconds": str(
                    max(0, int(active.get("timer_elapsed_seconds", 0) or 0))
                ),
            }
        )

    _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, rows)


@_locked
def load_active_workout():
    ensure_data()

    rows = _read_csv(ACTIVE_WORKOUT_FILE)
    if not rows:
        return None

    first = rows[0]
    started_at = first.get("started_at", "")
    timer_started = (
        first.get("timer_started", "0") == "1"
        or bool((started_at or "").strip())
    )
    try:
        timer_elapsed_seconds = max(
            0, int(first.get("timer_elapsed_seconds", "0") or 0)
        )
    except (TypeError, ValueError):
        timer_elapsed_seconds = 0

    inferred_methods = {}
    for row in rows:
        key = str(row.get("exercise_name", "") or "").strip().casefold()
        if not key or key in inferred_methods:
            continue
        same_exercise = [
            candidate for candidate in rows
            if str(candidate.get("exercise_name", "") or "").strip().casefold() == key
        ]
        explicit = next(
            (str(candidate.get("training_method", "") or "").strip() for candidate in same_exercise
             if str(candidate.get("training_method", "") or "").strip()),
            "",
        )
        inferred_methods[key] = resolve_training_method(explicit, same_exercise)

    loaded_rows = []
    for row in rows:
        key = str(row.get("exercise_name", "") or "").strip().casefold()
        loaded_rows.append({
            "exercise_name": row["exercise_name"],
            "set_number": int(row["set_number"]),
            **_observation_metadata(row),
            "weight": row.get("weight", ""),
            "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
            "reps": row.get("reps", ""),
            "rir": (
                row.get("rir", "")
                if method_set_uses_rir(
                    inferred_methods.get(key, "Straight"),
                    row.get("set_type", "Normal"),
                )
                else ""
            ),
            "previous_weight": row.get("previous_weight", ""),
            "previous_reps": row.get("previous_reps", ""),
            "last_week_reps": row.get("last_week_reps", ""),
            "previous_rir": (
                row.get("previous_rir", "")
                if method_set_uses_rir(
                    inferred_methods.get(key, "Straight"),
                    row.get("set_type", "Normal"),
                )
                else ""
            ),
            "set_type": row.get("set_type", "Normal") or "Normal",
            "training_method": inferred_methods.get(key, "Straight"),
            "note": row.get("note", ""),
            "completed": row.get("completed", "0") == "1",
            "calibration_done": row.get("calibration_done", "0") == "1",
            "rest_seconds": parse_duration(row.get("rest_seconds", "180"), default=180),
        })

    return {
        **{key: first.get(key, "") for key in ("performed_at", "cycle_id", "cycle_microcycle", "cycle_phase", "cycle_target_rir")},
        "session_id": first.get("session_id", ""),
        "workout_id": first["workout_id"],
        "workout_name": first["workout_name"],
        "started_at": started_at,
        "timer_started": timer_started,
        "timer_elapsed_seconds": timer_elapsed_seconds,
        "rest_timer_state": first.get("rest_timer_state", ""),
        "rows": loaded_rows,
    }


@_locked
def clear_active_workout():
    _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, [])


def _update_template_weights_from_session(workout_id, rows):
    """
    Keep Manage's per-set weight/reps aligned with the latest completed workout.
    Rest time and set type remain user-managed template settings.
    """
    if not WORKOUT_SET_TEMPLATES_FILE.exists():
        return

    workout = read_workout(workout_id)
    if workout is None:
        return

    templates = _read_csv(WORKOUT_SET_TEMPLATES_FILE)

    # Map exercise name -> order index in the current template.
    order_map = {}
    for row in read_exercises():
        if row["workout_id"] == workout_id:
            order_map[row["exercise_name"].casefold()] = row["order_index"]

    for completed in rows:
        if deloads.is_recovery(completed):
            continue
        if not completed.get("completed", False):
            continue
        if load_modes.normalize(completed.get("load_mode", "external")) != read_exercise_details(completed.get("exercise_name", ""))["load_mode"]:
            continue

        order_index = order_map.get(
            completed.get("exercise_name", "").casefold()
        )
        if order_index is None:
            continue

        set_number = str(completed.get("set_number", ""))

        for template in templates:
            if (
                template["workout_id"] == workout_id
                and template["order_index"] == order_index
                and template["set_number"] == set_number
            ):
                target_context = set_context.resolve(template, read_exercise_details(completed.get("exercise_name", "")))
                if not set_context.matches(completed, target_context):
                    continue
                template["weight"] = str(completed.get("weight", "") or "")
                template["weight_unit"] = read_settings().get("unit", "kg")
                template["reps"] = str(completed.get("reps", "") or "")
                # Set roles/methods are program structure. They are persisted
                # only when the user explicitly chooses "Save for next time"
                # at workout completion.
                break

    _write_csv(
        WORKOUT_SET_TEMPLATES_FILE,
        TEMPLATE_SET_FIELDS,
        templates,
    )


@_transactional
def append_session(workout, rows, *, session_id=None, performed_at=None, cycle_context=None):
    """Append one finished workout session, preserving unfinished planned sets."""
    ensure_data()

    session_id = session_id or str(uuid.uuid4())
    existing_rows = _saved_session_rows(session_id)
    if existing_rows:
        if any(row.get("workout_id") != workout["workout_id"] for row in existing_rows):
            raise ValueError("This session ID belongs to a different workout.")
        return sum(row.get("completed", "1") != "0" for row in existing_rows)

    clean_rows = []
    completed_count = 0

    for row in rows:
        completed = bool(row.get("completed", False))
        if completed:
            completed_count += 1

        set_type = (row.get("set_type") or "Normal").strip() or "Normal"
        training_method = canonical_training_method(
            row.get("training_method", "Straight")
        )
        clean_rows.append(
            {
                **_observation_metadata(row),
                **(_muscle_snapshot(row["exercise_name"]) if row.get("muscle_metadata_recorded") != "1" else {}),
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": _text(row.get("weight", "")),
                "weight_unit": row.get("weight_unit") or read_settings().get("unit", "kg"),
                "reps": str(row.get("reps", "") or "").strip(),
                # RIR is meaningful only for working sets. Never persist it on
                # warmups, even if stale UI/import state contains a value.
                "rir": (
                    _text(row.get("rir", ""))
                    if method_set_uses_rir(training_method, set_type)
                    else ""
                ),
                "set_type": set_type,
                "training_method": training_method,
                "note": str(row.get("note", "") or "").strip(),
                "completed": completed,
            }
        )

    # A session is still considered performed only when at least one set was
    # completed. Once it is saved, however, keep every unfinished row too so
    # History can show what was planned but missed.
    if completed_count == 0:
        return 0

    now = performed_at or datetime.now().isoformat(timespec="seconds")
    context = _cycle_context(now) if cycle_context is None else cycle_context
    if context.get("cycle_phase") == "Deload":
        for row in clean_rows:
            if not deloads.is_recovery(row):
                row["prescription_kind"] = "deload_manual"
    cycle_id = context.get("cycle_id", "")
    cycle_microcycle = context.get("cycle_microcycle", "")

    output_rows = []

    for row in clean_rows:
        output_rows.append(
            {
                **_observation_metadata(row),
                "session_id": session_id,
                "date": now,
                "workout_id": workout["workout_id"],
                "workout_name": workout["name"],
                "cycle_id": cycle_id,
                "cycle_microcycle": cycle_microcycle,
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": row["weight"],
                "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
                "reps": row["reps"],
                "rir": row["rir"],
                "set_type": row["set_type"],
                "training_method": row.get("training_method", "Straight"),
                "note": row["note"],
                "completed": "1" if row["completed"] else "0",
            }
        )

    _write_csv(SETS_FILE, SET_FIELDS, _read_csv(SETS_FILE) + output_rows)

    # Only completed rows update future workout defaults.
    if context.get("cycle_phase") != "Deload":
        _update_template_weights_from_session(workout["workout_id"], clean_rows)

    return completed_count


@_transactional
def finish_active_workout(active, *, save_template=None):
    """Save every completion effect once, or leave the workout fully retryable."""
    ensure_data()
    session_id = str(active.get("session_id", "") or "")
    if not session_id:
        raise ValueError("Save the active workout before finishing it.")
    previous = _saved_session_rows(session_id)
    if previous:
        if any(row.get("workout_id") != active["workout_id"] for row in previous):
            raise ValueError("This session ID belongs to a different workout.")
        return sum(row.get("completed", "1") != "0" for row in previous)
    stored = _read_csv(ACTIVE_WORKOUT_FILE)
    if not stored or stored[0].get("session_id") != session_id:
        raise ValueError("This workout is no longer the saved active workout. Reopen the current workout.")
    if not any(row.get("completed", False) for row in active.get("rows", [])):
        return 0
    if save_template is not None and active.get("cycle_phase") != "Deload":
        save_template()
    count = append_session(
        {"workout_id": active["workout_id"], "name": active["workout_name"]},
        active["rows"], session_id=session_id,
        performed_at=active.get("performed_at"), cycle_context=active,
    )
    cycle = get_mesocycle(active.get("cycle_id", ""))
    if cycle and active.get("cycle_phase") != "Deload":
        for row in active["rows"]:
            if row.get("completed", False) and row.get("calibration_done", False) and not is_warmup_set_type(row.get("set_type")):
                mark_mesocycle_intro_seen(cycle["cycle_id"], active["workout_id"], row["exercise_name"], row.get("training_method", "Straight"))
    clear_active_workout()
    return count

def _session_overviews(limit=None, workout_id=None):
    """Newest sessions with performed and planned entry totals kept separate."""
    sessions = {}
    for row in reversed(_chronological_sets()):
        if workout_id is not None and row.get("workout_id") != workout_id:
            continue
        session_id = row.get("session_id")
        if not session_id:
            continue
        session = sessions.setdefault(session_id, {
            "session_id": session_id,
            "date": row.get("date", ""),
            "workout_id": row.get("workout_id", ""),
            "workout_name": row.get("workout_name", ""),
            "completed_count": 0,
            "planned_count": 0,
            "set_count": 0,
        })
        session["planned_count"] += 1
        if row.get("completed", "1") != "0":
            session["completed_count"] += 1
            # Compatibility field now counts completed entries, including warmups.
            session["set_count"] += 1
    return list(sessions.values())[:limit]


@_locked
def recent_sessions(limit=5):
    ensure_data()
    return _session_overviews(limit)


@_locked
def read_session(session_id):
    ensure_data()

    rows = [
        row
        for row in _read_csv(SETS_FILE)
        if row.get("session_id") == session_id
    ]

    if not rows:
        return None

    first = rows[0]

    return {
        "session_id": session_id,
        "date": first.get("date", ""),
        "workout_id": first.get("workout_id", ""),
        "workout_name": first.get("workout_name", ""),
        "cycle_id": first.get("cycle_id", ""),
        "cycle_microcycle": first.get("cycle_microcycle", ""),
        "rows": [
            {
                "exercise_name": row.get("exercise_name", ""),
                "set_number": int(row.get("set_number", "1") or 1),
                **_observation_metadata(row),
                "weight": row.get("weight", ""),
                "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
                "reps": row.get("reps", ""),
                "rir": row.get("rir", ""),
                "set_type": row.get("set_type", "Normal") or "Normal",
                "training_method": canonical_training_method(row.get("training_method", "Straight")),
                "note": row.get("note", ""),
                "completed": row.get("completed", "1") != "0",
            }
            for row in rows
        ],
    }


@_locked
def save_session(session_id, workout_name, rows, session_date=None):
    """
    Rewrite one historical session in place while preserving its original
    session_id and workout_id. A YYYY-MM-DD session_date may replace only the
    calendar date while retaining the original time-of-day when one exists.
    """
    ensure_data()

    all_rows = _read_csv(SETS_FILE)
    old_rows = [
        row
        for row in all_rows
        if row.get("session_id") == session_id
    ]

    if not old_rows:
        return 0

    first = old_rows[0]
    date = first.get("date", "")
    requested_date = str(session_date or "").strip()
    if requested_date:
        try:
            requested_day = datetime.fromisoformat(requested_date).date().isoformat()
        except (TypeError, ValueError) as exc:
            raise ValueError("Workout date must use YYYY-MM-DD.") from exc
        if requested_day > datetime.now().date().isoformat():
            raise ValueError("A performed workout cannot be dated in the future.")

        # Completed sessions normally carry an ISO timestamp. Editing the date
        # should not unexpectedly reset the original workout time.
        suffix = ""
        if len(str(date)) > 10 and str(date)[10:11] in {"T", " "}:
            suffix = str(date)[10:]
        date = requested_day + suffix

    workout_id = first.get("workout_id", "")
    cycle_id = first.get("cycle_id", "")
    cycle_microcycle = first.get("cycle_microcycle", "")
    if str(date)[:10] != str(first.get("date", ""))[:10]:
        context = _cycle_context(date, preferred_id=cycle_id, historical=True)
        cycle_id, cycle_microcycle = context["cycle_id"], context["cycle_microcycle"]
    stored_name = (workout_name or "").strip() or first.get("workout_name", "")

    clean_rows = []
    counters = {}

    for row in rows:
        exercise_name = (row.get("exercise_name") or "").strip()
        if not exercise_name:
            continue

        counters[exercise_name] = counters.get(exercise_name, 0) + 1

        set_type = (row.get("set_type") or "Normal").strip() or "Normal"
        training_method = canonical_training_method(
            row.get("training_method", "")
            or next(
                (old.get("training_method", "") for old in old_rows
                 if old.get("exercise_name", "").casefold() == exercise_name.casefold()
                 and old.get("training_method", "")),
                "Straight",
            )
        )
        clean_rows.append(
            {
                **_observation_metadata(row),
                "session_id": session_id,
                "date": date,
                "workout_id": workout_id,
                "workout_name": stored_name,
                "cycle_id": cycle_id,
                "cycle_microcycle": cycle_microcycle,
                "exercise_name": exercise_name,
                "set_number": counters[exercise_name],
                "weight": _text(row.get("weight", "")),
                "weight_unit": row.get("weight_unit") or read_settings().get("unit", "kg"),
                "reps": str(row.get("reps", "") or "").strip(),
                "rir": (
                    _text(row.get("rir", ""))
                    if method_set_uses_rir(training_method, set_type)
                    else ""
                ),
                "set_type": set_type,
                "training_method": training_method,
                "note": str(row.get("note", "") or "").strip(),
                "completed": "1" if row.get("completed", False) else "0",
            }
        )

    output = []
    inserted = False

    for row in all_rows:
        if row.get("session_id") == session_id:
            if not inserted:
                output.extend(clean_rows)
                inserted = True
            continue

        output.append(row)

    _write_csv(SETS_FILE, SET_FIELDS, output)
    return len(clean_rows)


@_locked
def delete_session(session_id):
    ensure_data()

    rows = [
        row
        for row in _read_csv(SETS_FILE)
        if row.get("session_id") != session_id
    ]

    _write_csv(SETS_FILE, SET_FIELDS, rows)


@_locked
def all_sessions(limit=None):
    ensure_data()
    return _session_overviews(limit)


@_locked
def workout_sessions(workout_id, limit=12):
    ensure_data()
    return _session_overviews(limit, workout_id=workout_id)


@_locked
def exercise_sessions(exercise_name, limit=100):
    """Return completed history for one exercise, newest session first."""
    ensure_data()

    target = str(exercise_name or "").strip().casefold()
    if not target:
        return []

    sessions = {}
    order = []
    default_unit = read_settings().get("unit", "kg")

    # Use performed timestamps, including corrected dates, for newest first.
    for row in reversed(_chronological_sets()):
        if str(row.get("exercise_name", "") or "").strip().casefold() != target:
            continue
        if row.get("completed", "1") == "0":
            continue

        session_id = str(row.get("session_id", "") or "").strip()
        if not session_id:
            continue

        if session_id not in sessions:
            if limit is not None and len(order) >= int(limit):
                continue
            sessions[session_id] = {
                "session_id": session_id,
                "date": row.get("date", ""),
                "workout_id": row.get("workout_id", ""),
                "workout_name": row.get("workout_name", ""),
                "rows": [],
            }
            order.append(session_id)

        sessions[session_id]["rows"].append(
            {
                "set_number": _positive_int(row.get("set_number"), 1),
                **_observation_metadata(row),
                "weight": row.get("weight", ""),
                "weight_unit": row.get("weight_unit", read_settings().get("unit", "kg")),
                "reps": row.get("reps", ""),
                "rir": row.get("rir", ""),
                "set_type": row.get("set_type", "Normal") or "Normal",
            }
        )

    result = []
    for session_id in order:
        session = sessions[session_id]
        session["rows"].sort(key=lambda item: item.get("set_number", 1))
        result.append(session)
    return result


@_locked
def data_path():
    ensure_data()
    return DATA_DIR
