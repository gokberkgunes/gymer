import csv
import os
import uuid
from datetime import datetime
from pathlib import Path


DATA_DIR = Path(os.environ.get("FLET_APP_STORAGE_DATA") or ".").resolve()

WORKOUTS_FILE = DATA_DIR / "workouts.csv"
WORKOUT_EXERCISES_FILE = DATA_DIR / "workout_exercises.csv"
SETS_FILE = DATA_DIR / "sets.csv"
SETTINGS_FILE = DATA_DIR / "settings.csv"
ACTIVE_WORKOUT_FILE = DATA_DIR / "active_workout.csv"

WORKOUT_FIELDS = ["workout_id", "name"]

EXERCISE_FIELDS = [
    "workout_id",
    "order_index",
    "exercise_name",
    "target_sets",
    "default_weight",
    "default_reps",
]

SET_FIELDS = [
    "session_id",
    "date",
    "workout_id",
    "workout_name",
    "exercise_name",
    "set_number",
    "weight",
    "reps",
    "rir",
    "note",
]

SETTING_FIELDS = ["key", "value"]

ACTIVE_FIELDS = [
    "workout_id",
    "workout_name",
    "exercise_name",
    "set_number",
    "weight",
    "reps",
    "rir",
    "note",
]

DEFAULT_SETTINGS = {
    "unit": "kg",
    "default_sets": "3",
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
]


def _write_csv(path, fieldnames, rows):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _read_csv(path):
    if not path.exists():
        return []

    with open(path, "r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _migrate_csv(path, fieldnames, defaults=None):
    """Add newly introduced columns without destroying existing user data."""
    defaults = defaults or {}

    if not path.exists():
        return

    rows = _read_csv(path)

    # Empty file with a header may still need migration.
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, [])

    if header == fieldnames:
        return

    migrated = []
    for row in rows:
        migrated.append(
            {
                field: row.get(field, defaults.get(field, ""))
                for field in fieldnames
            }
        )

    _write_csv(path, fieldnames, migrated)


def ensure_data():
    DATA_DIR.mkdir(parents=True, exist_ok=True)

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
                        "default_reps": "",
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
                "default_reps": "",
            },
        )

    if not SETS_FILE.exists():
        _write_csv(SETS_FILE, SET_FIELDS, [])
    else:
        _migrate_csv(SETS_FILE, SET_FIELDS)

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

        if changed:
            save_settings(settings)

    if not ACTIVE_WORKOUT_FILE.exists():
        _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, [])
    else:
        _migrate_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS)


def read_workouts():
    ensure_data()
    return _read_csv(WORKOUTS_FILE)


def read_exercises():
    ensure_data()
    return _read_csv(WORKOUT_EXERCISES_FILE)


def read_workout(workout_id):
    ensure_data()

    workout = next(
        (w for w in read_workouts() if w["workout_id"] == workout_id),
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

    return {
        "workout_id": workout["workout_id"],
        "name": workout["name"],
        "exercises": [
            {
                "exercise_name": row["exercise_name"],
                "target_sets": row.get("target_sets", "3") or "3",
                "default_weight": row.get("default_weight", ""),
                "default_reps": row.get("default_reps", ""),
            }
            for row in exercises
        ],
    }


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


def save_workout(workout_id, name, exercises):
    ensure_data()

    workouts = read_workouts()
    for workout in workouts:
        if workout["workout_id"] == workout_id:
            workout["name"] = name.strip() or workout["name"]
            break

    all_exercises = [
        row
        for row in read_exercises()
        if row["workout_id"] != workout_id
    ]

    cleaned = []
    for exercise in exercises:
        exercise_name = exercise.get("exercise_name", "").strip()
        if not exercise_name:
            continue

        target_sets = exercise.get("target_sets", "").strip()
        if not target_sets.isdigit() or int(target_sets) < 1:
            target_sets = read_settings().get("default_sets", "3")

        cleaned.append(
            {
                "exercise_name": exercise_name,
                "target_sets": target_sets,
                "default_weight": exercise.get("default_weight", "").strip(),
                "default_reps": exercise.get("default_reps", "").strip(),
            }
        )

    for i, exercise in enumerate(cleaned, start=1):
        all_exercises.append(
            {
                "workout_id": workout_id,
                "order_index": i,
                **exercise,
            }
        )

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, all_exercises)


def delete_workout(workout_id):
    """
    Delete the workout template only.

    Historical rows in sets.csv are deliberately preserved.
    """
    ensure_data()

    workouts = [
        workout
        for workout in read_workouts()
        if workout["workout_id"] != workout_id
    ]

    exercises = [
        exercise
        for exercise in read_exercises()
        if exercise["workout_id"] != workout_id
    ]

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, exercises)


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


def save_settings(settings):
    merged = dict(DEFAULT_SETTINGS)
    merged.update(settings)

    _write_csv(
        SETTINGS_FILE,
        SETTING_FIELDS,
        [{"key": key, "value": value} for key, value in merged.items()],
    )


def latest_set_values(workout_id, exercise_name):
    """
    Return latest values by set number for this exercise in this workout.

    Example:
        {
            1: {"weight": "100", "reps": "10", "rir": "2"},
            2: {"weight": "100", "reps": "8", "rir": "1"},
        }
    """
    ensure_data()

    matching = [
        row
        for row in _read_csv(SETS_FILE)
        if row.get("workout_id") == workout_id
        and row.get("exercise_name") == exercise_name
    ]

    latest = {}

    for row in reversed(matching):
        try:
            set_number = int(row.get("set_number", ""))
        except ValueError:
            continue

        if set_number not in latest:
            latest[set_number] = {
                "weight": row.get("weight", ""),
                "reps": row.get("reps", ""),
                "rir": row.get("rir", ""),
            }

    return latest


def build_active_workout(workout):
    """Create the initial rows for a newly started workout."""
    settings = read_settings()
    default_sets = int(settings.get("default_sets", "3") or 3)

    rows = []

    for exercise in workout["exercises"]:
        exercise_name = exercise["exercise_name"]

        try:
            target_sets = int(exercise.get("target_sets", "") or default_sets)
        except ValueError:
            target_sets = default_sets

        previous = latest_set_values(workout["workout_id"], exercise_name)

        for set_number in range(1, target_sets + 1):
            previous_set = previous.get(set_number, {})

            rows.append(
                {
                    "exercise_name": exercise_name,
                    "set_number": set_number,
                    "weight": previous_set.get(
                        "weight",
                        exercise.get("default_weight", ""),
                    ),
                    "reps": previous_set.get(
                        "reps",
                        exercise.get("default_reps", ""),
                    ),
                    "rir": previous_set.get("rir", ""),
                    "note": "",
                }
            )

    return {
        "workout_id": workout["workout_id"],
        "workout_name": workout["name"],
        "rows": rows,
    }


def save_active_workout(active):
    ensure_data()

    if not active:
        clear_active_workout()
        return

    rows = []
    for row in active.get("rows", []):
        rows.append(
            {
                "workout_id": active["workout_id"],
                "workout_name": active["workout_name"],
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": row.get("weight", ""),
                "reps": row.get("reps", ""),
                "rir": row.get("rir", ""),
                "note": row.get("note", ""),
            }
        )

    _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, rows)


def load_active_workout():
    ensure_data()

    rows = _read_csv(ACTIVE_WORKOUT_FILE)
    if not rows:
        return None

    first = rows[0]

    return {
        "workout_id": first["workout_id"],
        "workout_name": first["workout_name"],
        "rows": [
            {
                "exercise_name": row["exercise_name"],
                "set_number": int(row["set_number"]),
                "weight": row.get("weight", ""),
                "reps": row.get("reps", ""),
                "rir": row.get("rir", ""),
                "note": row.get("note", ""),
            }
            for row in rows
        ],
    }


def clear_active_workout():
    _write_csv(ACTIVE_WORKOUT_FILE, ACTIVE_FIELDS, [])


def append_session(workout, rows):
    ensure_data()

    clean_rows = []

    for row in rows:
        weight = str(row.get("weight", "")).strip()
        reps = str(row.get("reps", "")).strip()
        rir = str(row.get("rir", "")).strip()
        note = str(row.get("note", "")).strip()

        # Empty generated rows are ignored.
        if not weight and not reps and not rir and not note:
            continue

        clean_rows.append(
            {
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": weight,
                "reps": reps,
                "rir": rir,
                "note": note,
            }
        )

    if not clean_rows:
        return 0

    session_id = str(uuid.uuid4())
    now = datetime.now().isoformat(timespec="seconds")

    output_rows = []
    for row in clean_rows:
        output_rows.append(
            {
                "session_id": session_id,
                "date": now,
                "workout_id": workout["workout_id"],
                "workout_name": workout["name"],
                "exercise_name": row["exercise_name"],
                "set_number": row["set_number"],
                "weight": row["weight"],
                "reps": row["reps"],
                "rir": row["rir"],
                "note": row["note"],
            }
        )

    file_exists = SETS_FILE.exists()

    with open(SETS_FILE, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=SET_FIELDS)

        if not file_exists:
            writer.writeheader()

        writer.writerows(output_rows)

    return len(output_rows)


def recent_sessions(limit=5):
    ensure_data()

    rows = _read_csv(SETS_FILE)
    sessions = {}

    for row in reversed(rows):
        session_id = row.get("session_id")
        if not session_id:
            continue

        if session_id not in sessions:
            sessions[session_id] = {
                "session_id": session_id,
                "date": row.get("date", ""),
                "workout_name": row.get("workout_name", ""),
                "set_count": 0,
            }

        sessions[session_id]["set_count"] += 1

    return list(sessions.values())[:limit]


def data_path():
    ensure_data()
    return DATA_DIR
