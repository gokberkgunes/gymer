import csv
import os
import uuid
from datetime import datetime
from pathlib import Path


DATA_DIR = Path(os.environ.get("FLET_APP_STORAGE_DATA") or ".").resolve()
WORKOUTS_FILE = DATA_DIR / "workouts.csv"
WORKOUT_EXERCISES_FILE = DATA_DIR / "workout_exercises.csv"
SETS_FILE = DATA_DIR / "sets.csv"

WORKOUT_FIELDS = ["workout_id", "name"]
EXERCISE_FIELDS = ["workout_id", "order_index", "exercise_name"]
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

DEFAULT_WORKOUTS = [
    (
        "A",
        "Workout A",
        ["Leg Press", "SLD", "Leg Curl", "Calf Press"],
    ),
    (
        "B",
        "Workout B",
        ["Lat Pulldown", "Machine Row", "Lying Biceps Curls" ],
    ),
    (
        "C",
        "Workout C",
        ["Incline Bench", "Overhead Cable Triceps", "Lateral Raise"],
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


def ensure_data():
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if not WORKOUTS_FILE.exists():
        _write_csv(
            WORKOUTS_FILE,
            WORKOUT_FIELDS,
            [{"workout_id": wid, "name": name} for wid, name, _ in DEFAULT_WORKOUTS],
        )

    if not WORKOUT_EXERCISES_FILE.exists():
        rows = []
        for wid, _, exercises in DEFAULT_WORKOUTS:
            for i, exercise in enumerate(exercises, start=1):
                rows.append(
                    {
                        "workout_id": wid,
                        "order_index": i,
                        "exercise_name": exercise,
                    }
                )
        _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, rows)

    if not SETS_FILE.exists():
        _write_csv(SETS_FILE, SET_FIELDS, [])


def read_workouts():
    ensure_data()
    return _read_csv(WORKOUTS_FILE)


def read_workout(workout_id):
    ensure_data()
    workouts = read_workouts()
    workout = next((w for w in workouts if w["workout_id"] == workout_id), None)
    if workout is None:
        return None

    exercises = [
        row
        for row in _read_csv(WORKOUT_EXERCISES_FILE)
        if row["workout_id"] == workout_id
    ]
    exercises.sort(key=lambda row: int(row["order_index"]))

    return {
        "workout_id": workout["workout_id"],
        "name": workout["name"],
        "exercises": [row["exercise_name"] for row in exercises],
    }


def save_workout(workout_id, name, exercises):
    ensure_data()

    workouts = read_workouts()
    for workout in workouts:
        if workout["workout_id"] == workout_id:
            workout["name"] = name.strip() or workout["name"]
            break

    all_exercises = [
        row
        for row in _read_csv(WORKOUT_EXERCISES_FILE)
        if row["workout_id"] != workout_id
    ]

    cleaned = [exercise.strip() for exercise in exercises if exercise.strip()]
    for i, exercise in enumerate(cleaned, start=1):
        all_exercises.append(
            {
                "workout_id": workout_id,
                "order_index": i,
                "exercise_name": exercise,
            }
        )

    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)
    _write_csv(WORKOUT_EXERCISES_FILE, EXERCISE_FIELDS, all_exercises)

def create_workout(name=""):
    ensure_data()
    workouts = read_workouts()

    workout_id = uuid.uuid4().hex[:8]

    workouts.append(
        {
            "workout_id": workout_id,
            "name": name,

        }
    )
    _write_csv(WORKOUTS_FILE, WORKOUT_FIELDS, workouts)

    return workout_id





def append_session(workout, rows):
    ensure_data()

    clean_rows = []
    for row in rows:
        weight = row.get("weight", "").strip()
        reps = row.get("reps", "").strip()
        rir = row.get("rir", "").strip()
        note = row.get("note", "").strip()

        if not weight and not reps and not note:
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


def data_path():
    ensure_data()
    return DATA_DIR
