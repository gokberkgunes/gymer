"""Batch 3: truthful observations, dated context and explicit load meaning."""

from contextlib import contextmanager
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest import mock

from test_data_integrity import TemporaryStorageTestCase
import storage
import progression
import load_modes
from workouts import WorkoutMixin
from ui_core import UICoreMixin


@contextmanager
def at(timestamp):
    class Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls.fromisoformat(timestamp)
    with mock.patch.object(storage, "datetime", Clock):
        yield


class Form(WorkoutMixin, UICoreMixin):
    EMPTY_BACKSPACE_SENTINEL = "\u200b"

    def __init__(self):
        self.settings = {"track_rir": "1"}
        self.numeric_field_kinds = {}
        self.numeric_warning_fields = {}
        self.android_backspace_last_values = {}
        self.set_controls = []
        self.page = SimpleNamespace(update=lambda: None)

    def mark_field_invalid(self, field): field.invalid = True
    def clear_field_invalid(self, field): field.invalid = False
    def update_active_numeric_warning(self, item, key): pass

    def item(self, *, mode="external", weight="50", rir="", number=1):
        class Field:
            def __init__(self, value): self.value = value
        item = {"exercise_name": "Test", "set_number": number, "training_method": "Straight",
                "set_type": "Normal", "load_mode": mode, "target_rir": "3", "completed": False,
                "weight": Field(weight), "reps": Field("10"),
                "rir": Field(rir), "previous_rir": "3",
                "rir_ghost": Field("3"), "weight_ghost": Field(""),
                "reps_ghost": Field(""), "previous_weight": "", "previous_reps": ""}
        self.set_controls.append(item)
        return item


class TrainingRecordTests(TemporaryStorageTestCase):
    def cycle(self, start="2026-01-01", **config):
        return storage.save_mesocycle({"start_date": start, "setup_complete": "1", **config})

    def record(self, timestamp, weight, *, rir="2", mode="external"):
        sid = f"test-{timestamp}-{weight}"
        storage.append_session({"workout_id": "A", "name": "Legs"}, [{
            "exercise_name": "Leg Press", "set_number": 1, "weight": weight, "reps": "13",
            "rir": rir, "target_rir": "3", "load_mode": mode, "completed": True,
        }], session_id=sid, performed_at=timestamp)
        return sid

    def test_legacy_rir_is_retained_as_unverified_without_changing_reps(self):
        sid = self.record("2026-01-03T10:00:00", "50", rir="3")
        fields = [key for key in storage.SET_FIELDS if key not in {"target_rir", "legacy_rir", "load_mode"}]
        rows = storage._read_csv(storage.SETS_FILE)
        storage._write_csv(storage.SETS_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        storage.ensure_data()
        row = storage.read_session(sid)["rows"][0]
        self.assertEqual("3", row["legacy_rir"])
        self.assertEqual("", row["rir"])
        self.assertEqual("13", row["reps"])
        self.assertEqual("external", row["load_mode"])
        storage.ensure_data()
        self.assertEqual(row, storage.read_session(sid)["rows"][0])
        suggestion = progression.progression_recommendation(storage.latest_completed_straight_session("Leg Press"), target_rir=2)
        self.assertEqual("hold", suggestion["action"])
        self.assertIsNone(suggestion["estimated_1rm"])

    def test_legacy_active_rir_is_not_promoted_to_actual(self):
        active = storage.build_active_workout(storage.read_workout("A"))
        active["rows"][0].update(weight="50", reps="10", rir="3", completed=True)
        storage.save_active_workout(active)
        fields = [key for key in storage.ACTIVE_FIELDS if key not in {"legacy_rir", "target_rir", "load_mode"}]
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        storage._write_csv(storage.ACTIVE_WORKOUT_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        loaded = storage.load_active_workout()
        self.assertEqual("", loaded["rows"][0]["rir"])
        self.assertEqual("3", loaded["rows"][0]["legacy_rir"])
        self.assertEqual(active["session_id"], loaded["session_id"])

    def test_actual_zero_and_target_remain_distinct_through_backup_and_edit(self):
        sid = self.record("2026-01-03T10:00:00", "50", rir=0)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        session = storage.read_session(sid)
        row = session["rows"][0]
        self.assertEqual("0", row["rir"])
        self.assertEqual("3", row["target_rir"])
        storage.save_session(sid, "Edited", session["rows"])
        self.assertEqual("0", storage.read_session(sid)["rows"][0]["rir"])
        self.assertIsNotNone(progression.estimated_one_rm(50, 13, 0))

    def test_unknown_effort_does_not_become_failure_or_a_load_increase(self):
        self.assertIsNone(progression.estimated_one_rm(50, 13))
        self.assertIsNone(progression.calibration_recommendation(50, 13, "", target_rir=2))
        for method, role in (("Straight", "Normal"), ("AMRAP", "AMRAP"), ("Myo-Reps", "Activation")):
            with self.subTest(method=method):
                rec = progression.method_progression_recommendation([
                    {"weight": "50", "reps": "13", "rir": "", "target_rir": "3", "set_type": role}], method=method, target_rir=2)
                self.assertEqual("hold", rec["action"])
                self.assertIsNone(rec["estimated_1rm"])

    def test_actual_rir_is_optional_and_never_uses_the_ghost_or_prior_set(self):
        form = Form()
        first = form.item(rir="0")
        first["completed"] = True
        second = form.item(number=2)
        second["weight"].value = second["reps"].value = ""
        form.copy_previous_completed_set_values_if_empty(second)
        self.assertEqual("", second["rir"].value)
        self.assertIsNone(form.active_field_fallback(second, "rir"))
        self.assertTrue(form.validate_completion_items([second]))
        self.assertEqual("", second["rir"].value)
        form.propagate_completed_values_to_following_sets(first)
        self.assertEqual("", second["rir"].value)
        second["rir"].value = "0"
        self.assertTrue(form.validate_completion_items([second]))
        second["rir"].value = "nan"
        self.assertFalse(form.validate_completion_items([second]))

    def test_workout_keeps_start_date_and_cycle_after_midnight_and_cycle_change(self):
        with at("2026-01-07T23:59:00"):
            first_cycle = self.cycle()
            active = storage.build_active_workout(storage.read_workout("A"))
            active["rows"][0].update(weight="50", reps="8", rir="2", completed=True, calibration_done=True)
            storage.save_active_workout(active)
        with at("2026-01-08T00:10:00"):
            second_cycle = self.cycle("2026-01-08", start_rir="5")
            loaded = storage.load_active_workout()
            self.assertEqual("3", loaded["cycle_target_rir"])
            self.assertEqual(first_cycle, loaded["cycle_id"])
            storage.finish_active_workout(loaded)
            session = storage.read_session(active["session_id"])
            self.assertEqual("2026-01-07T23:59:00", session["date"])
            self.assertEqual(first_cycle, session["cycle_id"])
            self.assertEqual("1", session["cycle_microcycle"])
            seen = storage._mesocycle_intro_seen_map()
            self.assertIn(first_cycle, seen)
            self.assertNotIn(second_cycle, seen)

    def test_upcoming_and_expired_cycles_do_not_prescribe_or_capture_new_sessions(self):
        for timestamp in ("2025-12-31T10:00:00", "2026-02-10T10:00:00"):
            with self.subTest(timestamp=timestamp), at(timestamp):
                self.cycle()
                self.assertIsNone(storage.active_cycle_locks()["suggested_rir"])
                active = storage.build_active_workout(storage.read_workout("A"))
                self.assertEqual("", active["cycle_id"])
                active["rows"][0].update(weight="50", reps="8", rir="2", completed=True)
                storage.save_active_workout(active)
                storage.finish_active_workout(active)
                self.assertEqual("", storage.read_session(active["session_id"])["cycle_id"])

    def test_workout_started_without_cycle_does_not_join_a_new_cycle_at_finish(self):
        with at("2026-01-02T10:00:00"):
            active = storage.build_active_workout(storage.read_workout("A"))
            active["rows"][0].update(weight="50", reps="8", completed=True)
            storage.save_active_workout(active)
            self.cycle()
            storage.finish_active_workout(active)
            self.assertEqual("", storage.read_session(active["session_id"])["cycle_id"])

    def test_historical_date_correction_reconciles_cycle_and_retains_time(self):
        first = self.cycle()
        sid = self.record("2026-01-08T10:20:30", "50")
        second = self.cycle("2026-02-01")
        with at("2026-03-01T10:00:00"):
            rows = storage.read_session(sid)["rows"]
            storage.save_session(sid, "Corrected", rows, session_date="2026-02-10")
            corrected = storage.read_session(sid)
            self.assertEqual("2026-02-10T10:20:30", corrected["date"])
            self.assertEqual(second, corrected["cycle_id"])
            self.assertEqual("2", corrected["cycle_microcycle"])
            storage.save_session(sid, "Outside", rows, session_date="2025-12-01")
            self.assertEqual("", storage.read_session(sid)["cycle_id"])
        self.assertNotEqual(first, second)

    def test_future_date_correction_is_rejected_without_mutation(self):
        sid = self.record("2026-01-02T10:00:00", "50")
        before = self.snapshot()
        future = (datetime.now().date() + timedelta(days=1)).isoformat()
        with self.assertRaisesRegex(ValueError, "future"):
            storage.save_session(sid, "Future", storage.read_session(sid)["rows"], session_date=future)
        self.assertEqual(before, self.snapshot())

    def test_all_history_queries_agree_after_backdating(self):
        later = self.record("2026-01-03T10:00:00", "80")
        earlier = self.record("2026-01-01T10:00:00", "70")
        def assert_latest(expected_id, expected_weight):
            for sessions in (storage.all_sessions(), storage.recent_sessions(), storage.workout_sessions("A"), storage.exercise_sessions("Leg Press")):
                self.assertEqual(expected_id, sessions[0]["session_id"])
            for row in (storage.latest_completed_straight_set("Leg Press"), storage.latest_completed_exercise_set("Leg Press"),
                        storage.latest_completed_straight_session("Leg Press")[0], storage.latest_completed_method_session("Leg Press", "Straight")[0]):
                self.assertEqual(expected_id, row["session_id"])
                self.assertEqual(expected_weight, row["weight"])
            self.assertEqual(expected_weight, storage.latest_set_values("A", "Leg Press")[1]["weight"])
            self.assertEqual(expected_weight, storage.latest_exercise_values("Leg Press")[1]["weight"])
        assert_latest(later, "80")
        storage.save_session(later, "Backdated", storage.read_session(later)["rows"], session_date="2025-12-31")
        assert_latest(earlier, "70")

    def test_equal_timestamp_order_is_stable_and_aware_timestamps_are_comparable(self):
        self.record("2026-01-01T23:30:00+00:00", "80")
        self.record("2026-01-02T01:00:00+02:00", "70")
        self.assertEqual("80", storage.latest_completed_straight_set("Leg Press")["weight"])
        self.record("2026-01-01T23:30:00+00:00", "85")
        self.assertEqual("85", storage.latest_completed_straight_set("Leg Press")["weight"])

    def test_bodyweight_added_and_assisted_loads_accept_zero_but_external_does_not(self):
        for mode, weight, expected in (("bodyweight", "0", True), ("bodyweight", "10", True),
                                       ("assisted", "20", True), ("assisted", "0", True),
                                       ("assisted", "-10", False), ("external", "0", False)):
            with self.subTest(mode=mode, weight=weight):
                form = Form()
                self.assertEqual(expected, form.validate_completion_items([form.item(mode=mode, weight=weight)]))

    def test_load_mode_is_a_session_snapshot_and_excluded_from_rm_algorithms(self):
        wid = storage.create_workout("Pull ups")
        storage.save_workout(wid, "Pull ups", [{"exercise_name": "Pull-Up", "sets": [{"weight": "0", "reps": "8"}]}])
        active = storage.build_active_workout(storage.read_workout(wid))
        self.assertEqual("bodyweight", active["rows"][0]["load_mode"])
        active["rows"][0].update(weight=0, reps="8", rir=0, completed=True)
        storage.save_active_workout(active)
        details = storage.read_exercise_details("Pull-Up")
        storage.save_exercise_details("Pull-Up", ["Back"], ["Biceps"], details["description"], "", load_mode="assisted")
        self.assertEqual("bodyweight", storage.load_active_workout()["rows"][0]["load_mode"])
        storage.finish_active_workout(active)
        logged = storage.read_session(active["session_id"])["rows"][0]
        self.assertEqual("0", logged["weight"])
        self.assertEqual("bodyweight", logged["load_mode"])
        following = storage.build_active_workout(storage.read_workout(wid))
        self.assertEqual("assisted", following["rows"][0]["load_mode"])
        self.assertEqual("", following["rows"][0]["previous_weight"])
        form = Form()
        form.active_workout = following
        self.assertEqual("", form.active_rows_for_added_exercise("Pull-Up")[0]["previous_weight"])
        for mode in ("bodyweight", "assisted"):
            rows = [{"weight": "20", "reps": "15", "rir": "0", "load_mode": mode, "set_type": "Normal"}]
            self.assertIsNone(progression.progression_recommendation(rows, target_rir=2))
            self.assertIsNone(progression.method_progression_recommendation(rows, target_rir=2))
        self.assertIn("less assistance is harder", load_modes.guidance("assisted"))

    def test_new_effort_context_and_load_fields_survive_backup(self):
        with at("2026-01-02T10:00:00"):
            self.cycle()
            active = storage.build_active_workout(storage.read_workout("A"))
            active["rows"][0].update(weight="50", reps="8", rir="0")
            storage.save_active_workout(active)
            before = self.snapshot()
            storage.import_data_zip_bytes(storage.export_data_zip_bytes())
            self.assertEqual(before, self.snapshot())
            loaded = storage.load_active_workout()
            self.assertEqual("0", loaded["rows"][0]["rir"])
            self.assertEqual("3", loaded["rows"][0]["target_rir"])
            self.assertEqual("2026-01-02T10:00:00", loaded["performed_at"])

    def test_load_mode_change_rolls_back_defaults_and_metadata_together(self):
        storage.save_workout("A", "Legs", [{"exercise_name": "Leg Press", "sets": [{"weight": "50", "reps": "8"}]}])
        before = self.snapshot()
        original = storage._atomic_write_bytes
        def fail(path, data):
            original(path, data)
            if path == storage.WORKOUT_SET_TEMPLATES_FILE:
                raise OSError("cannot commit defaults")
        with mock.patch.object(storage, "_atomic_write_bytes", side_effect=fail):
            with self.assertRaises(OSError):
                storage.save_exercise_details("Leg Press", ["Quads"], [], "", "", load_mode="assisted")
        self.assertEqual(before, self.snapshot())
