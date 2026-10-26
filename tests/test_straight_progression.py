"""Exercise-specific double progression, including incomplete session history."""

from test_data_integrity import TemporaryStorageTestCase
import progression as p
import storage


class StraightPolicyTests(TemporaryStorageTestCase):
    def rows(self, reps=(8, 8, 8), rir=2):
        return [dict(exercise_name="Leg Press", weight="100", reps=str(rep), rir=rir,
                     completed=True, set_type="Normal", set_number=index + 1,
                     training_method="Straight") for index, rep in enumerate(reps)]

    def recommend(self, rows=None, **kwargs):
        return p.progression_recommendation(self.rows() if rows is None else rows,
                                            **dict(target_rir=2, weight_increment=5, **kwargs))

    def record(self, sid, rows, date, workout="A"):
        storage.append_session(storage.read_workout(workout), rows, session_id=sid, performed_at=date)

    def test_rep_goals_advance_each_set_without_inventing_actuals(self):
        rows = self.rows((8, 10, 11))
        before = [dict(row) for row in rows]
        rec = self.recommend(rows)
        self.assertEqual(("hold", 100, [9, 11, 12]), (rec["action"], rec["weight"], rec["set_rep_targets"]))
        self.assertEqual(rows, before)
        self.assertIn("every planned set", rec["reason"])

    def test_upper_limit_is_inclusive_and_resets_goals_after_one_increment(self):
        for reps in [(12, 12, 12), (30, 30, 30)]:
            rec = self.recommend(self.rows(reps))
            self.assertEqual(("increase", 105, [8, 8, 8]), (rec["action"], rec["weight"], rec["set_rep_targets"]))

    def test_weak_final_set_is_not_hidden_by_the_median(self):
        rec = self.recommend(self.rows((13, 13, 5)))
        self.assertEqual(("decrease", 95), (rec["action"], rec["weight"]))
        self.assertEqual([8, 8, 8], rec["set_rep_targets"])

    def test_missed_or_invalid_working_set_blocks_progression(self):
        for observation in [dict(completed=False), dict(completed="0"), dict(completed=0), dict(reps=""), dict(reps="0")]:
            rows = self.rows((12, 12, 12))
            rows[-1].update(observation)
            with self.subTest(observation=observation):
                rec = self.recommend(rows)
                self.assertEqual(("hold", 100), (rec["action"], rec["weight"]))
                self.assertIn("missed", rec["reason"])

    def test_unknown_effort_and_unknown_target_do_not_qualify(self):
        for rir in [None, "", -1]:
            rec = self.recommend(self.rows((12, 12, 12), rir=rir))
            self.assertEqual("hold", rec["action"])
        rec = p.progression_recommendation(self.rows((12, 12, 12)), target_rir=None)
        self.assertEqual("hold", rec["action"])
        self.assertIsNone(rec["target_rir"])

    def test_effort_above_target_reduces_rep_goals_before_increasing_load(self):
        rec = self.recommend(self.rows((12, 12, 12), rir=0))
        self.assertEqual(("hold", 100, [10, 10, 10]), (rec["action"], rec["weight"], rec["set_rep_targets"]))
        rec = self.recommend(self.rows((8, 8, 8), rir=0))
        self.assertEqual("decrease", rec["action"])

    def test_changing_effort_target_changes_the_next_goal(self):
        rows = self.rows((12, 12, 12), rir=1)
        easier = p.progression_recommendation(rows, target_rir=3, weight_increment=5)
        harder = p.progression_recommendation(rows, target_rir=1, weight_increment=5)
        self.assertEqual(("hold", [10, 10, 10]), (easier["action"], easier["set_rep_targets"]))
        self.assertEqual(("increase", [8, 8, 8]), (harder["action"], harder["set_rep_targets"]))

    def test_custom_range_and_midpoint_calibration(self):
        for low, high in [(5, 8), (15, 20), (6, 6)]:
            rec = self.recommend(self.rows((high, high, high)), rep_min=low, rep_max=high)
            self.assertEqual((low, high), rec["rep_range"])
            self.assertEqual([low] * 3, rec["set_rep_targets"])
            cal = p.method_calibration_recommendation(100, 10, 2, method="Straight", target_rir=2, rep_min=low, rep_max=high)
            self.assertEqual((low + high) // 2, cal["target_reps"])

    def test_changed_plan_count_and_mixed_loads_require_manual_baseline(self):
        rec = self.recommend(self.rows((12, 12, 12)), expected_set_count=4)
        self.assertEqual("hold", rec["action"])
        self.assertEqual("", p.recommendation_weight_for_set(rec, "Normal"))
        rows = self.rows((12, 12, 12))
        rows[-1]["weight"] = "90"
        rec = self.recommend(rows)
        self.assertEqual("hold", rec["action"])
        self.assertIn("loads differ", rec["reason"])
        self.assertEqual("", p.recommendation_weight_for_set(rec, "Normal"))

    def test_manual_mode_and_warmup_exclusion(self):
        self.assertIsNone(self.recommend(self.rows((12, 12, 12)), policy="manual"))
        rows = [dict(weight="40", reps="5", rir="", set_type="Warm-up", completed=False)] + self.rows((12, 12, 12))
        self.assertEqual("increase", self.recommend(rows)["action"])

    def test_coarse_increment_keeps_upper_goals_when_increase_is_unavailable(self):
        rows = self.rows((12, 12, 12))
        for row in rows: row["weight"] = "12"
        rec = self.recommend(rows)
        self.assertEqual(("hold", [12, 12, 12]), (rec["action"], rec["set_rep_targets"]))

    def test_history_keeps_missed_rows_and_does_not_fall_back_after_all_missed(self):
        self.record("old", self.rows((12, 12, 12)), "2026-01-01T10:00:00")
        rows = self.rows((12, 12, 12))
        rows[-1].update(completed=False, reps="")
        self.record("partial", rows, "2026-01-02T10:00:00")
        latest = storage.latest_completed_straight_session("Leg Press", workout_id="A")
        self.assertEqual(3, len(latest))
        self.assertFalse(latest[-1]["completed"])
        self.assertEqual("hold", self.recommend(latest)["action"])
        for row in rows: row.update(completed=False, reps="")
        # The workout was performed, but every Leg Press set was missed.
        other_exercise = {**self.rows((8,))[0], "exercise_name": "Calf Raise"}
        self.record("missed", rows + [other_exercise], "2026-01-03T10:00:00")
        latest = storage.latest_completed_straight_session("Leg Press", workout_id="A")
        self.assertEqual({"missed"}, {row["session_id"] for row in latest})
        self.assertIsNone(self.recommend(latest))

    def test_history_matches_workout_and_method_and_retains_chronology(self):
        self.record("straight", self.rows((8, 8, 8)), "2026-01-01T10:00:00")
        other = storage.create_workout("Other")
        self.record("other-plan", self.rows((12, 12, 12)), "2026-01-03T10:00:00", workout=other)
        rows = self.rows((15,))
        rows[0].update(training_method="AMRAP", set_type="AMRAP")
        self.record("amrap", rows, "2026-01-04T10:00:00")
        self.record("backdated", self.rows((12, 12, 12)), "2025-12-31T10:00:00")
        latest = storage.latest_completed_straight_session("Leg Press", workout_id="A")
        self.assertEqual({"straight"}, {row["session_id"] for row in latest})

    def test_policy_settings_persist_through_unrelated_save_backup_and_rename(self):
        storage.save_exercise_details("Leg Press", ["Quads"], [], "", "", straight_rep_min="5", straight_rep_max="8", straight_progression="manual")
        storage.save_exercise_details("Leg Press", ["Quads"], [], "", "new note")
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        storage.rename_exercise("Leg Press", "Leg Press custom")
        details = storage.read_exercise_details("Leg Press custom")
        self.assertEqual(("5", "8", "manual"), tuple(details[key] for key in ("straight_rep_min", "straight_rep_max", "straight_progression")))

    def test_legacy_details_use_defaults_without_altering_history(self):
        fields = [key for key in storage.EXERCISE_DETAIL_FIELDS if not key.startswith("straight_")]
        rows = storage._read_csv(storage.EXERCISE_DETAILS_FILE)
        storage._write_csv(storage.EXERCISE_DETAILS_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        storage.ensure_data()
        details = storage.read_exercise_details("Leg Press")
        self.assertEqual(("8", "12", "double_progression"), tuple(details[key] for key in ("straight_rep_min", "straight_rep_max", "straight_progression")))

    def test_invalid_policy_or_range_is_rejected_before_save_or_import(self):
        for low, high, policy in [(0, 12, "manual"), (12, 8, "manual"), (5, 10000, "manual"), (5.5, 8, "manual"), (5, 8, "bad")]:
            before = self.snapshot()
            with self.subTest(low=low, high=high, policy=policy):
                with self.assertRaises(ValueError):
                    storage.save_exercise_details("Leg Press", ["Quads"], [], "", "", straight_rep_min=low, straight_rep_max=high, straight_progression=policy)
                self.assertEqual(before, self.snapshot())
                rows = storage._read_csv(storage.EXERCISE_DETAILS_FILE)
                rows[0].update(straight_rep_min=str(low), straight_rep_max=str(high), straight_progression=policy)
                raw = self.csv_bytes(storage.EXERCISE_DETAIL_FIELDS, rows)
                with self.assertRaises(ValueError):
                    storage.import_data_zip_bytes(self.rewrite_archive("exercise_details.csv", raw))
                self.assertEqual(before, self.snapshot())
