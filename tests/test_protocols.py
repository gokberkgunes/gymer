"""Advanced-method eligibility and protocol-record persistence."""

import copy
from test_data_integrity import TemporaryStorageTestCase
import progression as p
import protocols
import storage


class ProtocolTests(TemporaryStorageTestCase):
    def rows(self, method="Myo-Reps", reps=13):
        roles = {"AMRAP": ["AMRAP"] * 3, "Cluster": ["Cluster Set"] * 3,
                 "Myo-Reps": ["Activation", "Myo-set", "Myo-set"]}.get(method, ["Activation", method, method])
        return [dict(exercise_name="Bench Press", set_number=index + 1, training_method=method,
                     set_type=role, weight=str(100 if method != "Drop Set" else [100, 75, 50][index]),
                     reps=str(reps if index == 0 or method in {"AMRAP", "Myo-Rep Match", "Cluster"} else 3),
                     rir="2" if index == 0 or method == "AMRAP" else "", completed=True,
                     planned_work_count="3", setup="Machine A, bilateral", stop_reason="target_rir" if index == 0 or method == "AMRAP" else "",
                     rest_seconds="20", actual_rest_seconds="20") for index, role in enumerate(roles)]

    def rec(self, rows, method="Myo-Reps", **kwargs):
        return p.method_progression_recommendation(rows, method=method, target_rir=2, weight_increment=5, **kwargs)

    def assert_hold(self, rows, method="Myo-Reps", contains=None, **kwargs):
        rec = self.rec(rows, method, **kwargs)
        self.assertEqual(("hold", 100), (rec["action"], rec["weight"]))
        self.assertFalse(rec["apply_weight"])
        if contains: self.assertIn(contains, rec["reason"])
        return rec

    def test_complete_comparable_protocols_qualify_without_mutating_observations(self):
        for method in ["AMRAP", "Myo-Reps", "Rest-Pause", "Drop Set", "Myo-Rep Match", "Cluster"]:
            with self.subTest(method=method):
                rows = self.rows(method)
                before = copy.deepcopy(rows)
                rec = self.rec(rows, method, planned_rows=rows, expected_set_count=3)
                self.assertEqual("increase", rec["action"])
                self.assertTrue(rec["apply_weight"])
                self.assertGreater(rec["weight"], 100)
                self.assertLessEqual(rec["weight"], 110)
                self.assertEqual(before, rows)
                if method == "Cluster": self.assertIsNone(rec["estimated_1rm"])

    def test_activation_only_missing_removed_or_invalid_segments_never_pass(self):
        for method in sorted(p.METHODS_WITH_ACTIVATION):
            for change in ["activation_only", "removed", "missed", "invalid", "role", "legacy"]:
                rows = self.rows(method)
                if change == "activation_only":
                    rows = rows[:1]
                    rows[0]["planned_work_count"] = "1"
                elif change == "removed": rows.pop()
                elif change == "missed": rows[-1]["completed"] = False
                elif change == "invalid": rows[-1]["reps"] = ""
                elif change == "role": rows[-1]["set_type"] = "Normal"
                elif change == "legacy":
                    for row in rows: row["planned_work_count"] = ""
                with self.subTest(method=method, change=change):
                    self.assert_hold(rows, method)

    def test_changed_plan_count_roles_setup_and_rest_hold(self):
        rows = self.rows()
        self.assert_hold(rows, expected_set_count=4, contains="count changed")
        for key, value in [("setup", "Machine B"), ("setup", ""), ("set_type", "Normal"), ("rest_seconds", "30")]:
            plan = copy.deepcopy(rows)
            plan[-2][key] = value
            with self.subTest(key=key, value=value):
                self.assert_hold(rows, planned_rows=plan)

    def test_unknown_or_changed_actual_rest_does_not_become_planned_rest(self):
        for actual in ["", "0", "25", "-1"]:
            rows = self.rows()
            rows[0]["actual_rest_seconds"] = actual
            self.assert_hold(rows, contains="rest")
        rows = self.rows()
        rows[-1]["actual_rest_seconds"] = ""  # No next fragment to compare.
        self.assertEqual("increase", self.rec(rows)["action"])

    def test_known_stop_never_infers_failure_or_unknown_effort(self):
        for reason in ["", "safety_limit", "other"]:
            rows = self.rows()
            rows[0]["stop_reason"] = reason
            self.assert_hold(rows, contains="stop reason")
        for rir in ["", "0", "-1"]:
            rows = self.rows()
            rows[0].update(stop_reason="technical_failure", rir=rir)
            self.assert_hold(rows, contains="RIR")
        rows = self.rows()
        rows[0].update(stop_reason="technical_failure", rir="2")
        self.assertEqual("increase", self.rec(rows)["action"])
        rows[0]["stop_reason"] = "muscular_failure"
        self.assert_hold(rows, contains="conflicts")

    def test_zero_actual_rest_is_a_known_observation(self):
        rows = self.rows()
        for row in rows: row.update(rest_seconds="0", actual_rest_seconds="0")
        self.assertEqual("increase", self.rec(rows)["action"])

    def test_anchor_load_sizing_uses_the_prescribed_effort_target(self):
        rows = self.rows(reps=6)
        rec = self.rec(rows)
        self.assertEqual("decrease", rec["action"])
        self.assertEqual(95, rec["weight"])
        self.assertEqual(2, rec["target_rir"])

    def test_same_load_and_descending_drop_checks(self):
        for method in ["AMRAP", "Myo-Reps", "Rest-Pause", "Myo-Rep Match", "Cluster"]:
            rows = self.rows(method)
            rows[-1]["weight"] = "90"
            self.assert_hold(rows, method, contains="same-load")
        rows = self.rows("Drop Set")
        rows[-1]["weight"] = "80"
        self.assert_hold(rows, "Drop Set", contains="strictly decrease")

    def test_continuation_rep_criteria(self):
        for method in ["Myo-Reps", "Rest-Pause", "Drop Set", "Myo-Rep Match"]:
            rows = self.rows(method)
            rows[-1]["reps"] = "1" if method != "Myo-Rep Match" else "12"
            self.assert_hold(rows, method)

    def test_every_amrap_anchor_and_cluster_fragment_counts(self):
        rows = self.rows("AMRAP")
        rows[-1]["reps"] = "5"
        self.assertEqual("hold", self.rec(rows, "AMRAP")["action"])
        rows[-1]["reps"] = "13"
        rows[-1]["stop_reason"] = "safety_limit"
        self.assert_hold(rows, "AMRAP", contains="stop reason")
        rows = self.rows("Cluster", reps=6)
        rows[-1]["reps"] = "3"
        self.assertEqual("hold", self.rec(rows, "Cluster")["action"])
        rows[-1]["reps"] = "1"
        self.assertEqual("decrease", self.rec(rows, "Cluster")["action"])

    def test_mechanical_variants_remain_manual_even_with_complete_metadata(self):
        rows = self.rows("Mechanical Drop Set")
        for row, setup in zip(rows, ["Incline", "Flat", "Decline"]): row["setup"] = setup
        self.assert_hold(rows, "Mechanical Drop Set", contains="leverage")

    def test_new_workout_snapshot_and_metadata_survive_every_storage_path(self):
        wid = storage.create_workout("Protocol")
        storage.save_workout(wid, "Protocol", [{"exercise_name": "Bench Press", "training_method": "Myo-Reps", "sets": [
            dict(set_type="Normal", rest_seconds=20) for _ in range(3)]}])
        active = storage.build_active_workout(storage.read_workout(wid))
        self.assertEqual({"3"}, {row["planned_work_count"] for row in active["rows"]})
        for target, source in zip(active["rows"], self.rows()): target.update(source)
        storage.save_active_workout(active)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        loaded = storage.load_active_workout()
        for row in loaded["rows"]:
            self.assertEqual("20", str(row["actual_rest_seconds"]))
            self.assertEqual("Machine A, bilateral", row["setup"])
        storage.finish_active_workout(loaded)
        session = storage.read_session(active["session_id"])
        storage.save_session(session["session_id"], "Corrected name", session["rows"])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        latest = storage.latest_completed_method_session("Bench Press", "Myo-Reps", workout_id=wid)
        self.assertEqual("increase", self.rec(latest)["action"])
        self.assertEqual("20", latest[0]["rest_seconds"])
        self.assertIn("Chosen RIR", protocols.summary(latest[0]))

    def test_legacy_fields_remain_unknown_and_invalid_import_does_not_mutate(self):
        rows = self.rows()
        storage.append_session(storage.read_workout("A"), rows, session_id="fixture")
        fields = [key for key in storage.SET_FIELDS if key not in protocols.FIELDS and key != "rest_seconds"]
        saved = storage._read_csv(storage.SETS_FILE)
        storage._write_csv(storage.SETS_FILE, fields, [{key: row[key] for key in fields} for row in saved])
        latest = storage.latest_completed_method_session("Bench Press", "Myo-Reps")
        self.assertTrue(all(row["planned_work_count"] == "" and row["actual_rest_seconds"] == "" for row in latest))
        self.assert_hold(latest, contains="unknown")
        for key, value in [("planned_work_count", "0"), ("planned_work_count", "2.5"), ("actual_rest_seconds", "-1"), ("actual_rest_seconds", "nan"), ("stop_reason", "guessed")]:
            before = self.snapshot()
            saved = storage._read_csv(storage.SETS_FILE)
            saved[0][key] = value
            raw = self.csv_bytes(storage.SET_FIELDS, saved)
            with self.assertRaises(ValueError):
                storage.import_data_zip_bytes(self.rewrite_archive("sets.csv", raw))
            self.assertEqual(before, self.snapshot())

    def test_changed_logging_context_blocks_advanced_method_automation(self):
        for method in ('AMRAP','Myo-Reps','Rest-Pause','Drop Set','Myo-Rep Match','Cluster'):
            rows=self.rows(method)
            plan=copy.deepcopy(rows)
            for row in plan: row['side']='left'
            result=self.rec(rows,method,planned_rows=plan)
            with self.subTest(method=method):
                self.assertFalse(result['apply_weight'])
                self.assertEqual('hold',result['action'])
                self.assertIn('conventions',result['reason'])
