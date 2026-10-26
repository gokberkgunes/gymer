"""Regression checks for audit repair batch 1. All data lives in temp dirs."""

import csv
import io
import json
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import storage
import numeric_input
from settings_ui import SettingsMixin


class TemporaryStorageTestCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gymer-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        paths = {name: self.directory / value.name for name, value in vars(storage).items()
                 if name.endswith("_FILE") and isinstance(value, Path)}
        paths["DATA_DIR"] = self.directory
        paths["BACKUP_DATA_FILES"] = [self.directory / p.name for p in storage.BACKUP_DATA_FILES]
        patcher = mock.patch.multiple(storage, **paths)
        patcher.start()
        self.addCleanup(patcher.stop)
        storage.ensure_data()

    def snapshot(self):
        return {p.name: p.read_bytes() for p in storage.BACKUP_DATA_FILES if p.exists()}

    def rewrite_archive(self, name=None, content=None, omit=(), manifest=False):
        """Produce a legacy archive unless testing checksum verification."""
        source = zipfile.ZipFile(io.BytesIO(storage.export_data_zip_bytes()))
        buffer = io.BytesIO()
        with source, zipfile.ZipFile(buffer, "w") as target:
            for member in source.namelist():
                if member in omit or (member == "manifest.json" and not manifest):
                    continue
                target.writestr(member, content if member == name else source.read(member))
        return buffer.getvalue()

    def csv_bytes(self, fields, rows):
        buffer = io.StringIO(newline="")
        writer = csv.DictWriter(buffer, fields)
        writer.writeheader()
        writer.writerows(rows)
        return buffer.getvalue().encode()

    def add_session(self):
        storage.append_session({"workout_id": "A", "name": "Legs"}, [{
            "exercise_name": "Leg Press", "set_number": 1, "weight": "50",
            "reps": "10", "rir": "2", "completed": True,
        }])


class DataIntegrityTests(TemporaryStorageTestCase):
    def test_failed_row_serialization_retains_original_csv(self):
        before = storage.WORKOUTS_FILE.read_bytes()
        def interrupted():
            yield {"workout_id": "new", "name": "partial"}
            raise OSError("interrupted")
        with self.assertRaises(OSError):
            storage._write_csv(storage.WORKOUTS_FILE, storage.WORKOUT_FIELDS, interrupted())
        self.assertEqual(before, storage.WORKOUTS_FILE.read_bytes())

    def test_failed_write_or_replace_retains_original_and_cleans_temp(self):
        for operation in ("fsync", "replace"):
            with self.subTest(operation=operation):
                before = self.snapshot()
                with mock.patch.object(storage.os, operation, side_effect=OSError("disk failure")):
                    with self.assertRaises(OSError):
                        storage._write_csv(storage.WORKOUTS_FILE, storage.WORKOUT_FIELDS, [])
                self.assertEqual(before, self.snapshot())
                self.assertEqual([], list(self.directory.glob(".*.csv.*")))

    def test_new_backup_preserves_all_user_files_and_distinct_set_templates(self):
        wid = storage.create_workout("Custom")
        storage.save_workout(wid, "Custom", [{"exercise_name": "Bench Press", "sets": [
            {"weight": "20", "reps": "10", "rest_seconds": 60, "set_type": "Warm-up"},
            {"weight": "75", "reps": "8", "rest_seconds": 210, "set_type": "Top Set"},
            {"weight": "60", "reps": "12", "rest_seconds": 120, "set_type": "Back-off"},
        ]}])
        before = self.snapshot()
        archive = storage.export_data_zip_bytes()
        with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
            manifest = json.loads(zipped.read("manifest.json"))
            self.assertEqual(1, manifest["version"])
            self.assertIn("workout_set_templates.csv", manifest["files"])
        storage.save_workout(wid, "Changed", [])
        storage.import_data_zip_bytes(archive)
        self.assertEqual(before, self.snapshot())

    def test_all_training_methods_keep_their_program_on_restore(self):
        for method in storage.TRAINING_METHODS:
            wid = storage.create_workout(method)
            storage.save_workout(wid, method, [{"exercise_name": "Bench Press", "training_method": method,
                "sets": [{"set_type": "Normal", "weight": str(50-i*5), "reps": str(10-i), "rest_seconds": 180-i*75} for i in range(3)]}])
        before = self.snapshot()
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual(before, self.snapshot())

    def test_legacy_backup_without_templates_regenerates_defaults(self):
        archive = self.rewrite_archive(omit={"workout_set_templates.csv"})
        storage.import_data_zip_bytes(archive)
        workout = storage.read_workout("A")
        self.assertEqual(4, len(workout["exercises"]))
        self.assertEqual(3, len(workout["exercises"][0]["sets"]))

    def test_legacy_optional_columns_and_utf8_bom_are_migrated(self):
        content = b'\xef\xbb\xbfworkout_id,order_index,exercise_name\r\nA,1,Leg Press\r\n'
        archive = self.rewrite_archive("workout_exercises.csv", content, omit={"workout_set_templates.csv"})
        storage.import_data_zip_bytes(archive)
        self.assertEqual("Leg Press", storage.read_workout("A")["exercises"][0]["exercise_name"])

    def test_bad_set_values_are_rejected_before_mutation(self):
        self.add_session()
        for key, value in (("set_number", "not-an-integer"), ("set_number", "1.5"),
                           ("date", "yesterday"), ("weight", "nan"), ("weight", "inf"),
                           ("reps", "0"), ("completed", "true"), ("weight_unit", "stone")):
            with self.subTest(key=key, value=value):
                rows = storage._read_csv(storage.SETS_FILE)
                rows[0][key] = value
                archive = self.rewrite_archive("sets.csv", self.csv_bytes(storage.SET_FIELDS, rows))
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "sets.csv, row 2"):
                    storage.import_data_zip_bytes(archive)
                self.assertEqual(before, self.snapshot())

    def test_bad_settings_are_rejected_before_mutation(self):
        for key, value in (("default_sets", "1.5"), ("default_rest_seconds", "nan"),
                           ("default_sets", "999999999999999999999999999"),
                           ("font_scale", "inf"), ("weight_increment_barbell_kg", "0"),
                           ("unit", "stone"), ("mesocycle_intro_seen_exercises", "[]")):
            with self.subTest(key=key):
                content = self.csv_bytes(storage.SETTING_FIELDS, [{"key": key, "value": value}])
                archive = self.rewrite_archive("settings.csv", content)
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "settings.csv, row 2"):
                    storage.import_data_zip_bytes(archive)
                self.assertEqual(before, self.snapshot())

    def test_blank_unfinished_set_observations_are_allowed(self):
        self.add_session()
        rows = storage._read_csv(storage.SETS_FILE)
        rows.append(dict(rows[0], set_number="2", weight="", reps="", rir="", completed="0"))
        archive = self.rewrite_archive("sets.csv", self.csv_bytes(storage.SET_FIELDS, rows))
        storage.import_data_zip_bytes(archive)
        self.assertEqual("", storage._read_csv(storage.SETS_FILE)[1]["reps"])

    def test_active_arithmetic_and_unfinished_input_survive_backup(self):
        active = storage.build_active_workout(storage.read_workout("A"))
        active["rows"][0].update(weight="45+45", reps="5+", rir="0")
        storage.save_active_workout(active)
        before = self.snapshot()
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual(before, self.snapshot())
        storage.convert_all_weights("kg", "lb")
        self.assertAlmostEqual(90 * storage.KG_TO_LB, float(storage.load_active_workout()["rows"][0]["weight"]), places=2)

    def test_arithmetic_parser_preserves_supported_operations_and_rejects_code(self):
        for text, expected in (("45+45", 90), ("(50-5)*2/3", 30), ("-2+5", 3)):
            with self.subTest(text=text):
                self.assertEqual(expected, numeric_input.evaluate_numeric_expression(text))
        for text in ("1/0", "True", "2**100", "__import__('os')", "nan", "1e999", "5+"):
            with self.subTest(text=text):
                self.assertIsNone(numeric_input.evaluate_numeric_expression(text))

    def test_bad_headers_rows_and_duplicate_ids_are_rejected(self):
        for content in (b"garbage\nx\n", b"workout_id,name,name\nA,a,a\n",
                        b"workout_id,name\nA,a,extra\n", b"workout_id,name\nA\n",
                        b"workout_id,name\nA,a\nA,b\n"):
            with self.subTest(content=content):
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "workouts.csv"):
                    storage.import_data_zip_bytes(self.rewrite_archive("workouts.csv", content))
                self.assertEqual(before, self.snapshot())

    def test_orphan_live_placement_is_rejected(self):
        archive = self.rewrite_archive("workout_exercises.csv", b"workout_id,order_index,exercise_name\nmissing,1,Bench Press\n")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "workout_id does not reference"):
            storage.import_data_zip_bytes(archive)
        self.assertEqual(before, self.snapshot())

    def test_history_of_deleted_workout_remains_valid(self):
        self.add_session()
        storage.delete_workout("A")
        before = self.snapshot()
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual(before, self.snapshot())
        self.assertEqual(1, len(storage.all_sessions()))

    def test_checksum_and_missing_manifest_members_are_rejected(self):
        for archive in (self.rewrite_archive("workouts.csv", b"workout_id,name\n", manifest=True),
                        self.rewrite_archive(omit={"workout_set_templates.csv"}, manifest=True)):
            before = self.snapshot()
            with self.assertRaises(ValueError):
                storage.import_data_zip_bytes(archive)
            self.assertEqual(before, self.snapshot())

    def test_duplicate_unknown_and_nested_archive_members_are_rejected(self):
        for name in ("workouts.csv", "unknown.csv", "../workouts.csv", "folder\\workouts.csv"):
            buffer = io.BytesIO(self.rewrite_archive())
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(buffer, "a") as zipped:
                    zipped.writestr(name, "workout_id,name\n")
            before = self.snapshot()
            with self.assertRaises(ValueError):
                storage.import_data_zip_bytes(buffer.getvalue())
            self.assertEqual(before, self.snapshot())

    def test_archive_limits_are_checked_before_mutation(self):
        archive = storage.export_data_zip_bytes()
        before = self.snapshot()
        with mock.patch.object(storage.backup_validation, "MAX_FILE_BYTES", 10):
            with self.assertRaisesRegex(ValueError, "oversized"):
                storage.import_data_zip_bytes(archive)
        self.assertEqual(before, self.snapshot())

    def test_migration_failure_restores_previous_files(self):
        archive = storage.export_data_zip_bytes()
        storage.save_settings({**storage.read_settings(), "unit": "lb"})
        before = self.snapshot()
        with mock.patch.object(storage, "ensure_data", side_effect=RuntimeError("migration failed")):
            with self.assertRaisesRegex(RuntimeError, "migration failed"):
                storage.import_data_zip_bytes(archive)
        self.assertEqual(before, self.snapshot())

    def test_unit_changes_discard_old_controls_and_preserve_active_loads(self):
        class App(SettingsMixin):
            def capture_active_controls(self):
                self.capture_count += 1
                self.active_workout["rows"][0]["weight"] = self.set_controls[0].value
                self.active_workout["rows"][0]["weight_unit"] = self.settings["unit"]
                storage.save_active_workout(self.active_workout)

        app = App()
        app.capture_count = 0
        app.settings = storage.read_settings()
        app.active_workout = storage.build_active_workout(storage.read_workout("A"))
        app.active_workout["rows"][0].update(weight="50", previous_weight="45", completed=True)
        storage.save_active_workout(app.active_workout)
        app.set_controls = [SimpleNamespace(value="50")]
        for name in ("numeric_field_kinds", "numeric_warning_fields", "focus_previous_fields",
                     "android_backspace_last_values", "active_numeric_context"):
            setattr(app, name, {1: "stale"})
        app.numeric_warning_acknowledged = {"stale"}
        app.focused_text_field = app.set_controls[0]
        app.timer_inline_item = {"stale": True}
        for unit in ("lb", "kg", "lb", "kg"):
            app.change_weight_unit(unit)
            app.settings["unit"] = unit
            storage.save_settings(app.settings)
            self.assertEqual([], app.set_controls)
        self.assertEqual(1, app.capture_count)
        self.assertEqual("50", app.active_workout["rows"][0]["weight"])
        self.assertEqual("45", app.active_workout["rows"][0]["previous_weight"])
        self.assertTrue(app.active_workout["rows"][0]["completed"])
        self.assertIsNone(app.focused_text_field)
        self.assertIsNone(app.timer_inline_item)
        self.assertFalse(app.active_numeric_context)


if __name__ == "__main__":
    unittest.main()
