"""Fixed-reference recovery plans and temporary deload persistence."""

import copy
from unittest import mock
from test_data_integrity import TemporaryStorageTestCase
from test_training_records import at
import deloads
import progression
import storage


class DeloadTests(TemporaryStorageTestCase):
    def seed(self, method="Straight", count=4, *, warmup=False, load_mode="external"):
        self.cycle = storage.save_mesocycle({"start_date": "2026-01-01", "length_value": "4",
                                           "deload_microcycles": "2", "setup_complete": "1"})
        self.wid = storage.create_workout("Recovery fixture")
        storage.save_exercise_details("Bench Press", ["Chest"], [], "", "", load_mode=load_mode, weight_increment_kg="5", logging_context={"setup":"Same setup"})
        sets = [dict(weight="100", reps="10", rest_seconds=30, set_type="Normal") for _ in range(count)]
        if warmup: sets.insert(0, dict(weight="40", reps="5", rest_seconds=30, set_type="Warm-up"))
        storage.save_workout(self.wid, "Recovery fixture", [{"exercise_name": "Bench Press", "training_method": method, "sets": sets}])
        with at("2026-01-08T10:00:00"):
            active = storage.build_active_workout(storage.read_workout(self.wid))
            for row in active["rows"]:
                row.update(weight="40" if row["set_type"] == "Warm-up" else "100", reps="3" if method == "Cluster" else "10",
                           rir="2", completed=True, setup="Same setup", stop_reason="target_rir", actual_rest_seconds="30")
            storage.save_active_workout(active)
            storage.finish_active_workout(active)
        self.source = active["session_id"]
        return active

    def start(self, timestamp="2026-01-15T10:00:00"):
        with at(timestamp):
            active = storage.build_active_workout(storage.read_workout(self.wid))
            storage.save_active_workout(active)
        self.assertEqual("Deload", active["cycle_phase"])
        return active

    def finish(self, active):
        for row in active["rows"]:
            row.update(weight=row.get("prescribed_weight") or "60", reps=row.get("target_reps") or "5", rir="4", completed=True)
        storage.save_active_workout(active)
        storage.finish_active_workout(active)

    def test_repeated_deloads_use_the_same_build_reference_without_compounding(self):
        self.seed()
        for day in [15, 16, 22, 25]:
            active = self.start(f"2026-01-{day}T10:00:00")
            self.assertEqual(2, len(active["rows"]))
            self.assertEqual({"90"}, {row["prescribed_weight"] for row in active["rows"]})
            self.assertEqual({self.source}, {row["reference_session_id"] for row in active["rows"]})
            self.assertTrue(all(row["weight"] == row["reps"] == row["rir"] == "" for row in active["rows"]))
            self.assertEqual({"4"}, {row["target_rir"] for row in active["rows"]})
            self.finish(active)

    def test_all_methods_receive_conventional_recovery_work_without_intensifiers(self):
        for method in storage.TRAINING_METHODS:
            with self.subTest(method=method):
                self.seed(method, count=4, warmup=True)
                active = self.start()
                warmups = [row for row in active["rows"] if row["set_type"] == "Warm-up"]
                working = [row for row in active["rows"] if row["set_type"] != "Warm-up"]
                self.assertEqual(1, len(warmups))
                self.assertEqual(2 if method in {"Straight", "AMRAP"} else 1, len(working))
                self.assertTrue(all(row["training_method"] == "Straight" and row["set_type"] == "Normal" for row in working))
                self.assertEqual({method}, {row["source_method"] for row in working})
                if method in {"Cluster", "Mechanical Drop Set"}:
                    self.assertEqual({""}, {row.get("prescribed_weight", "") for row in working})
                if method == "Cluster": self.assertEqual("3", working[0]["target_reps"])

    def test_volume_and_load_settings_are_explicit_and_discrete(self):
        self.seed(count=5)
        storage.update_mesocycle(self.cycle, {"deload_load_percent": "85", "deload_volume_percent": "60", "deload_rir": "5"})
        active = self.start()
        self.assertEqual(3, len(active["rows"]))
        self.assertEqual({"85"}, {row["prescribed_weight"] for row in active["rows"]})
        self.assertEqual({"5"}, {row["target_rir"] for row in active["rows"]})
        self.assertEqual(1, deloads.recovery_count("Straight", 1, 1))
        self.assertEqual(1, deloads.recovery_count("Straight", 3, 50))
        self.assertEqual(1, deloads.recovery_count("Myo-Reps", 10, 100))

    def test_rounding_never_increases_the_reference_and_cannot_return_zero(self):
        for load, step in [(100, 5), (12, 5), (110.23, 10), (5, 10)]:
            for percent in [1, 50, 90, 100]:
                text = deloads.recovery_weight(load, percent=percent, unit="kg", step=step)
                if text:
                    value = float(text)
                    self.assertGreater(value, 0)
                    self.assertLessEqual(value, load * percent / 100 + 1e-8)
                    self.assertAlmostEqual(round((value - load) / step), (value - load) / step)

    def test_no_reference_does_not_use_template_or_previous_recovery_load(self):
        self.seed()
        storage.delete_session(self.source)
        active = self.start()
        self.assertTrue(all(not row.get("prescribed_weight") for row in active["rows"]))
        self.finish(active)
        again = self.start("2026-01-16T10:00:00")
        self.assertTrue(all(not row.get("prescribed_weight") for row in again["rows"]))

    def test_recovery_loads_and_structure_do_not_update_workout_or_calibration(self):
        self.seed("Myo-Reps")
        files = {path: path.read_bytes() for path in [storage.WORKOUTS_FILE, storage.WORKOUT_EXERCISES_FILE, storage.WORKOUT_SET_TEMPLATES_FILE]}
        settings = storage.SETTINGS_FILE.read_bytes()
        active = self.start()
        for row in active["rows"]: row.update(weight="70", reps="5", rir="4", completed=True, calibration_done=True)
        storage.save_active_workout(active)
        with mock.patch.object(storage, "mark_mesocycle_intro_seen") as marker:
            callback = mock.Mock()
            storage.finish_active_workout(active, save_template=callback)
            callback.assert_not_called()
            marker.assert_not_called()
        self.assertEqual(settings, storage.SETTINGS_FILE.read_bytes())
        for path, content in files.items(): self.assertEqual(content, path.read_bytes())

    def test_recovery_history_remains_visible_but_not_a_progression_or_default_baseline(self):
        self.seed()
        active = self.start()
        self.finish(active)
        self.assertEqual(2, len(storage.all_sessions()))
        latest = storage.latest_completed_straight_session("Bench Press", workout_id=self.wid)
        self.assertEqual({self.source}, {row["session_id"] for row in latest})
        self.assertEqual(self.source, storage.latest_completed_straight_set("Bench Press")["session_id"])
        self.assertEqual("100", storage.latest_set_values(self.wid, "Bench Press")[1]["weight"])

    def test_snapshot_survives_settings_edit_reload_backup_and_unit_change(self):
        self.seed()
        active = self.start()
        expected = copy.deepcopy(active["rows"])
        storage.update_mesocycle(self.cycle, {"deload_load_percent": "50", "deload_volume_percent": "25", "deload_rir": "6"})
        self.assertEqual(expected, storage.load_active_workout()["rows"])
        settings, loaded = storage.change_weight_unit("lb")
        self.assertAlmostEqual(198.42, float(loaded["rows"][0]["prescribed_weight"]), places=2)
        self.assertEqual("100", loaded["rows"][0]["reference_weight"])
        self.assertEqual("kg", loaded["rows"][0]["reference_weight_unit"])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual(loaded["rows"], storage.load_active_workout()["rows"])
        self.assertEqual("4", loaded["cycle_target_rir"])

    def test_source_must_match_cycle_workout_method_and_pre_deload_date(self):
        self.seed()
        source_rows = storage.read_session(self.source)["rows"]
        other = storage.create_workout("Other")
        storage.append_session(storage.read_workout(other), source_rows, session_id="other-workout", performed_at="2026-01-14T10:00:00")
        altered = [{**row, "training_method": "AMRAP", "set_type": "AMRAP"} for row in source_rows]
        storage.append_session(storage.read_workout(self.wid), altered, session_id="other-method", performed_at="2026-01-14T11:00:00")
        storage.append_session(storage.read_workout(self.wid), source_rows, session_id="before-cycle", performed_at="2025-12-31T10:00:00")
        active = self.start()
        self.assertEqual({self.source}, {row["reference_session_id"] for row in active["rows"]})

    def test_backdating_recovery_does_not_make_it_a_build_reference(self):
        self.seed()
        active = self.start()
        self.finish(active)
        session = storage.read_session(active["session_id"])
        storage.save_session(session["session_id"], session["workout_name"], session["rows"], session_date="2026-01-14")
        again = self.start("2026-01-16T10:00:00")
        self.assertEqual({self.source}, {row["reference_session_id"] for row in again["rows"]})

    def test_manual_policy_and_non_external_or_manual_exercise_loads_stay_manual(self):
        for mode in ["bodyweight", "assisted"]:
            self.seed(load_mode=mode)
            self.assertTrue(all(not row.get("prescribed_weight") for row in self.start()["rows"]))
        self.seed()
        storage.save_exercise_details("Bench Press", ["Chest"], [], "", "", straight_progression="manual")
        self.assertTrue(all(not row.get("prescribed_weight") for row in self.start()["rows"]))
        storage.update_mesocycle(self.cycle, {"deload_policy": "manual"})
        active = self.start()
        self.assertEqual(4, len(active["rows"]))
        self.assertEqual({"deload_manual"}, {row["prescription_kind"] for row in active["rows"]})

    def test_invalid_config_and_import_are_rejected_without_mutation(self):
        self.seed()
        for changes in [{"deload_load_percent": "0"}, {"deload_volume_percent": "101"}, {"deload_load_percent": "nan"},
                        {"deload_policy": "unknown"}, {"deload_rir": "1"}, {"deload_rir": "4.2", "end_rir": "3.8"}]:
            before = self.snapshot()
            with self.assertRaises(ValueError): storage.update_mesocycle(self.cycle, changes)
            self.assertEqual(before, self.snapshot())
            rows = storage._read_csv(storage.MESOCYCLES_FILE)
            rows[0].update(changes)
            raw = self.csv_bytes(storage.MESOCYCLE_FIELDS, rows)
            with self.assertRaises(ValueError): storage.import_data_zip_bytes(self.rewrite_archive("mesocycles.csv", raw))
            self.assertEqual(before, self.snapshot())

    def test_legacy_interrupted_workout_is_not_rewritten_and_stateless_discounts_are_disabled(self):
        self.seed()
        active = self.start()
        fields = [key for key in storage.ACTIVE_FIELDS if key not in deloads.FIELDS]
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        storage._write_csv(storage.ACTIVE_WORKOUT_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        loaded = storage.load_active_workout()
        self.assertEqual(len(active["rows"]), len(loaded["rows"]))
        self.assertTrue(all(row["prescription_kind"] == "" for row in loaded["rows"]))
        for method in storage.TRAINING_METHODS:
            self.assertIsNone(progression.method_progression_recommendation(loaded["rows"], method=method, phase="Deload"))

    def test_legacy_invalid_effort_preserves_cycle_data_but_does_not_prescribe_failure(self):
        self.seed()
        fields = [key for key in storage.MESOCYCLE_FIELDS if key not in {"deload_policy", "deload_load_percent", "deload_volume_percent"}]
        rows = storage._read_csv(storage.MESOCYCLES_FILE)
        rows[0]["deload_rir"] = "0"
        storage._write_csv(storage.MESOCYCLES_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        active = self.start()
        self.assertEqual("0.0", storage.get_mesocycle(self.cycle)["deload_rir"])
        self.assertEqual("", active["cycle_target_rir"])
        self.assertEqual({""}, {row["target_rir"] for row in active["rows"]})
        self.assertEqual({"deload_manual"}, {row["prescription_kind"] for row in active["rows"]})

    def test_each_recovery_set_uses_its_own_reference_load(self):
        self.seed()
        source = storage.read_session(self.source)
        for row, load in zip(source["rows"], ["100", "95", "90", "85"]): row["weight"] = load
        storage.save_session(self.source, source["workout_name"], source["rows"])
        active = self.start()
        self.assertEqual(["90", "85"], [row["prescribed_weight"] for row in active["rows"]])
        self.assertEqual(["100", "95"], [row["reference_weight"] for row in active["rows"]])

    def test_recovery_finish_failure_rolls_back_and_retry_saves_once(self):
        self.seed()
        active = self.start()
        for row in active["rows"]: row.update(weight="90", reps="8", rir="4", completed=True)
        storage.save_active_workout(active)
        before = self.snapshot()
        with mock.patch.object(storage, "clear_active_workout", side_effect=OSError("interrupted recovery Finish")):
            with self.assertRaises(OSError): storage.finish_active_workout(active)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(2, storage.finish_active_workout(active))
        self.assertEqual(2, storage.finish_active_workout(active))
        self.assertEqual(2, len(storage.all_sessions()))

    def test_changed_setup_or_side_does_not_become_a_recovery_reference(self):
        self.seed()
        for context in ({"setup":"Other machine"},{"setup":"Same setup","side":"left"}):
            storage.save_exercise_details("Bench Press",["Chest"],[],"","",logging_context=context)
            active=self.start()
            self.assertTrue(all(not row.get("reference_session_id") and not row.get("prescribed_weight") for row in active["rows"]))
        self.assertEqual({"Same setup"},{row["setup"] for row in storage.read_session(self.source)["rows"]})
