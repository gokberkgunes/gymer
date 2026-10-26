"""Validate backup contents in memory before replacing any user files."""

import csv
import hashlib
import io
import json
import math
import load_modes
import set_context
import progression
import protocols
import deloads
import volume_accounting
import rest_timer_state
from datetime import datetime


MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_BACKUP_BYTES = 128 * 1024 * 1024

# Other columns may be absent in older versions and receive migration defaults.
REQUIRED_COLUMNS = {
    "workouts.csv": {"workout_id", "name"},
    "workout_exercises.csv": {"workout_id", "order_index", "exercise_name"},
    "workout_set_templates.csv": {"workout_id", "order_index", "set_number"},
    "sets.csv": {"session_id", "date", "exercise_name", "set_number", "weight", "reps"},
    "settings.csv": {"key", "value"},
    "active_workout.csv": {"workout_id", "workout_name", "exercise_name", "set_number"},
    "exercise_catalog.csv": {"exercise_name"},
    "set_types.csv": {"set_type"},
    "exercise_details.csv": {"exercise_name"},
    "workout_details.csv": {"workout_id"},
    "mesocycles.csv": {"cycle_id", "start_date"},
    "mesocycle_schedule.csv": {"cycle_id", "day_number", "workout_id"},
}

REQUIRED_VALUES = {
    name: fields - {"weight", "reps", "workout_id", "workout_name"}
    for name, fields in REQUIRED_COLUMNS.items()
}
for _name in ("workouts.csv", "workout_exercises.csv", "workout_set_templates.csv", "active_workout.csv", "workout_details.csv"):
    REQUIRED_VALUES[_name].add("workout_id")
# Empty settings values are legitimate for some optional/custom preferences.
REQUIRED_VALUES["settings.csv"] = {"key"}

INTEGER_MINIMUMS = {
    "set_number": 1, "order_index": 1, "target_sets": 1,
    "cycle_microcycle": 1, "day_number": 1, "microcycle_days": 1,
    "length_value": 1, "deload_microcycles": 0,
    "timer_elapsed_seconds": 0, "reps": 1, "default_reps": 1,
    "previous_reps": 1, "last_week_reps": 1,
    "straight_rep_min": 1, "straight_rep_max": 1,
    "planned_work_count": 1,
    "target_reps": 1, "original_work_count": 1,
    "group_planned_count": 1,
}
NUMBER_MINIMUMS = {
    "weight": 0, "default_weight": 0, "previous_weight": 0,
    "rir": 0, "previous_rir": 0, "start_rir": 0, "end_rir": 0,
    "deload_rir": 0, "weight_increment_lb": 0, "weight_increment_kg": 0,
    "target_rir": 0, "legacy_rir": 0, "cycle_target_rir": 0,
    "set_seconds": 0, "set_overhead_seconds": 0,
    "transition_seconds": 0, "session_overhead_seconds": 0,
    "actual_rest_seconds": 0,
    "reference_weight": 0, "prescribed_weight": 0,
    "deload_load_percent": 1, "deload_volume_percent": 1,
}
BOOLEAN_FIELDS = {
    "completed", "calibration_done", "timer_started", "rir_lock",
    "rest_timer_lock", "show_last_week_reps", "setup_complete", "active",
    "muscle_metadata_recorded", "protocol_group_start", "context_override",
}


def validate_manifest(raw, imported, allowed_names):
    try:
        manifest = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ValueError("manifest.json is not valid UTF-8 JSON.") from exc
    if not isinstance(manifest, dict) or manifest.get("format") != "gymer-backup":
        raise ValueError("manifest.json is not a GYMER backup manifest.")
    if type(manifest.get("version")) is not int or manifest["version"] != 1:
        raise ValueError("Unsupported backup version; update GYMER before importing it.")
    files = manifest.get("files")
    if not isinstance(files, dict) or set(files) != allowed_names or set(imported) != allowed_names:
        raise ValueError("Backup manifest must describe all user-data CSV files.")
    for name, data in imported.items():
        metadata = files[name]
        if not isinstance(metadata, dict) or metadata.get("sha256") != hashlib.sha256(data).hexdigest():
            raise ValueError(f"{name} does not match its backup checksum.")


def _error(name, line, message):
    raise ValueError(f"{name}, row {line}: {message}")


def _number(name, line, column, text, minimum, *, integer=False, positive=False):
    try:
        value = int(text) if integer else float(text)
        finite = math.isfinite(value)
    except (ValueError, OverflowError) as exc:
        raise ValueError(f"{name}, row {line}: {column} must be a valid {'integer' if integer else 'number'}.") from exc
    if not finite or value < minimum or (positive and value == 0):
        _error(name, line, f"{column} must be a finite {'positive' if positive else 'nonnegative'} value.")
    count_columns = (set(INTEGER_MINIMUMS) - {"timer_elapsed_seconds"}) | {"default_sets", "rep_max_target_reps", "set_spacing", "rounding"}
    if integer and column in count_columns and value > 9999:
        _error(name, line, f"{column} exceeds the supported count limit (9999).")


def _validate_settings(name, line, row, defaults):
    key, value = row["key"], row["value"].strip()
    if key == "unit" and value not in {"kg", "lb"}:
        _error(name, line, "unit must be kg or lb.")
    if key in defaults and defaults[key] in {"0", "1"} and key not in {"rounding", "set_spacing"}:
        if value not in {"0", "1"}:
            _error(name, line, f"{key} must be 0 or 1.")
    integer_keys = {
        "default_sets": 1, "default_rest_seconds": 0, "rep_max_target_reps": 1,
        "set_spacing": 0, "rounding": 0, "default_workout_pack_revision": 0,
    }
    if key in integer_keys:
        _number(name, line, key, value, integer_keys[key], integer=True)
    if key == "font_scale" or key.startswith("weight_increment_"):
        _number(name, line, key, value, 0, positive=True)
    if key == "mesocycle_intro_seen_exercises":
        try:
            seen = json.loads(value)
        except ValueError:
            _error(name, line, f"{key} must be a JSON object.")
        if not isinstance(seen, dict):
            _error(name, line, f"{key} must be a JSON object.")


def validate_csv_files(imported, schemas, defaults):
    parsed = {}
    for name, raw in imported.items():
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise ValueError(f"{name} is not a UTF-8 CSV file.") from exc
        try:
            reader = csv.DictReader(io.StringIO(text, newline=""), strict=True)
            header = reader.fieldnames
            if not header or len(set(header)) != len(header) or any(not field for field in header):
                raise ValueError(f"{name} has a missing or duplicate CSV header.")
            if not REQUIRED_COLUMNS[name].issubset(header):
                raise ValueError(f"{name} is missing required columns: {', '.join(sorted(REQUIRED_COLUMNS[name] - set(header)))}.")
            if set(header) - set(schemas[name]):
                raise ValueError(f"{name} contains unsupported columns.")
            rows = []
            for row in reader:
                line = reader.line_num
                if None in row or any(value is None for value in row.values()):
                    _error(name, line, "CSV row has the wrong number of fields.")
                for column in REQUIRED_VALUES[name]:
                    if not row.get(column, "").strip():
                        _error(name, line, f"{column} cannot be empty.")
                for column, raw_value in row.items():
                    value = raw_value.strip()
                    if not value:
                        continue  # Blank optional observations are not zero.
                    if name == "active_workout.csv" and row.get("completed", "0") != "1" and column in {"weight", "reps", "rir"}:
                        # These are editable drafts, not observations. Preserve
                        # arithmetic and unfinished input exactly as the UI does.
                        # IDs, indices and timer metadata are still validated.
                        continue
                    if column in INTEGER_MINIMUMS:
                        _number(name, line, column, value, INTEGER_MINIMUMS[column], integer=True)
                    elif column in NUMBER_MINIMUMS:
                        _number(name, line, column, value, NUMBER_MINIMUMS[column], positive=column.startswith("weight_increment_"))
                    elif column == "rest_seconds":
                        if ":" in value:
                            parts = value.split(":")
                            if len(parts) != 2 or not all(p.isdigit() for p in parts) or int(parts[1]) >= 60:
                                _error(name, line, "rest_seconds must be seconds or m:ss.")
                        else:
                            _number(name, line, column, value, 0)
                    elif column in BOOLEAN_FIELDS and value not in {"0", "1"}:
                        _error(name, line, f"{column} must be 0 or 1.")
                    elif column in {"weight_unit", "default_weight_unit", "reference_weight_unit"} and value not in {"kg", "lb"}:
                        _error(name, line, f"{column} must be kg or lb.")
                    elif column == "rest_timer_state":
                        try:
                            rest_timer_state.decode(value)
                        except ValueError as exc:
                            _error(name, line, str(exc))
                    elif column == "load_mode":
                        try:
                            load_modes.normalize(value)
                        except ValueError:
                            _error(name, line, "load_mode is not supported.")
                    elif column in set_context.OPTIONS and value not in set_context.OPTIONS[column]:
                        _error(name, line, f"{column} is not supported.")
                    elif column == "stop_reason" and value not in protocols.STOP_REASONS:
                        _error(name, line, "stop_reason is not supported.")
                    elif column == "segment_role" and value not in volume_accounting.ROLES:
                        _error(name, line, "segment_role is not supported.")
                    elif column == "prescription_kind" and value not in {"deload", "deload_manual"}:
                        _error(name, line, "prescription_kind is not supported.")
                    elif column in {"date", "start_date", "started_at", "performed_at"}:
                        try:
                            timestamp = datetime.fromisoformat(value)
                        except ValueError:
                            _error(name, line, f"{column} must be an ISO date or timestamp.")
                if name == "settings.csv":
                    _validate_settings(name, line, row, defaults)
                if name == "exercise_details.csv":
                    try:
                        progression.straight_settings(row.get("straight_rep_min"), row.get("straight_rep_max"), row.get("straight_progression"))
                    except ValueError as exc:
                        _error(name, line, str(exc))
                if name == "mesocycles.csv" or any(row.get(key, "").strip() for key in ("deload_load_percent", "deload_volume_percent")):
                    try:
                        deloads.settings(row)
                        if name == "mesocycles.csv" and row.get("deload_policy") == "recovery":
                            if error := deloads.effort_error(row):
                                raise ValueError(error)
                    except ValueError as exc:
                        _error(name, line, str(exc))
                rows.append(row)
            parsed[name] = rows
        except csv.Error as exc:
            raise ValueError(f"{name} is not valid CSV: {exc}") from exc

    unique_keys = {
        "workouts.csv": ("workout_id",), "settings.csv": ("key",),
        "workout_exercises.csv": ("workout_id", "order_index"),
        "workout_set_templates.csv": ("workout_id", "order_index", "set_number"),
        "mesocycles.csv": ("cycle_id",),
        "mesocycle_schedule.csv": ("cycle_id", "day_number"),
    }
    for name, keys in unique_keys.items():
        seen = set()
        for line, row in enumerate(parsed.get(name, []), 2):
            key = tuple(str(int(row[k])) if k in INTEGER_MINIMUMS else row[k] for k in keys)
            if key in seen:
                _error(name, line, "duplicate record ID/position.")
            seen.add(key)

    # Historical sessions and an active workout may refer to deleted templates.
    # Schedule slots may also retain a deleted workout ID in existing versions.
    # Validate live template relationships without discarding historical records.
    if "workouts.csv" in parsed:
        workout_ids = {row["workout_id"] for row in parsed["workouts.csv"]}
        for name in ("workout_exercises.csv", "workout_set_templates.csv"):
            for line, row in enumerate(parsed.get(name, []), 2):
                if row["workout_id"] not in workout_ids:
                    _error(name, line, "workout_id does not reference a saved workout.")
    if "workout_exercises.csv" in parsed:
        placements = {(row["workout_id"], int(row["order_index"])) for row in parsed["workout_exercises.csv"]}
        for line, row in enumerate(parsed.get("workout_set_templates.csv", []), 2):
            if (row["workout_id"], int(row["order_index"])) not in placements:
                _error("workout_set_templates.csv", line, "set does not reference a saved exercise placement.")

    active = parsed.get("active_workout.csv", [])
    if active:
        state = rest_timer_state.decode(active[0].get("rest_timer_state", ""))
        if state and not rest_timer_state.matches(state, {"session_id": active[0].get("session_id"), "rows": active}):
            _error("active_workout.csv", 2, "rest timer does not reference a completed entry in this session.")
        for line, row in enumerate(active[1:], 3):
            for column in ("session_id", "performed_at", "cycle_id", "cycle_microcycle", "cycle_phase", "cycle_target_rir", "workout_id", "workout_name", "started_at", "timer_started", "timer_elapsed_seconds", "rest_timer_state"):
                if row.get(column, "") != active[0].get(column, ""):
                    _error("active_workout.csv", line, "conflicting active-workout metadata.")
    return parsed
