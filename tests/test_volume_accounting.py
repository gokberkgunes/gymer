"""Work categories, group identity, exposure snapshots and comparable periods."""

import copy
from unittest import mock
from test_data_integrity import TemporaryStorageTestCase
import storage
import progression
import volume_accounting as va
import volume_landmarks as landmarks


class VolumeAccountingTests(TemporaryStorageTestCase):
    def workout(self, method="Myo-Reps", count=5, name="Counted exercise"):
        storage.save_exercise_details(name, ["Chest"], ["Triceps"], "", "")
        wid = storage.create_workout("Accounting")
        storage.save_workout(wid, "Accounting", [{"exercise_name": name, "training_method": method,
            "sets": [dict(set_type="Normal", weight="50", reps="10", rest_seconds=20) for _ in range(count)]}])
        active = storage.build_active_workout(storage.read_workout(wid))
        for row in active["rows"]:
            row.update(completed=True, weight="50", reps="13" if row["set_type"] in {"Normal", "Activation", "AMRAP"} else "3",
                       rir="2", setup="Same setup", stop_reason="target_rir", actual_rest_seconds="20")
        return wid, active

    def test_five_conventional_sets_are_distinct_from_activation_plus_four_segments(self):
        _, straight = self.workout("Straight")
        _, myo = self.workout()
        first = storage.volume_report(straight["rows"])
        second = storage.volume_report(myo["rows"])
        self.assertEqual((5, 0), (first["totals"]["conventional_sets"], first["totals"]["protocol_groups"]))
        self.assertEqual((0, 1, 1, 4), tuple(second["totals"][key] for key in ("conventional_sets", "protocol_groups", "activations", "continuations")))
        self.assertEqual(1, second["totals"]["complete_protocol_groups"])
        self.assertEqual({}, storage.completed_primary_muscle_set_counts(myo["rows"]))

    def test_cluster_fragments_are_one_protocol_not_independent_sets(self):
        _, active = self.workout("Cluster", count=4)
        report = storage.volume_report(active["rows"])
        self.assertEqual((0, 1, 4), tuple(report["totals"][key] for key in ("conventional_sets", "protocol_groups", "cluster_fragments")))

    def test_repeated_cluster_placements_receive_different_group_ids(self):
        wid, _ = self.workout("Cluster", count=3)
        workout = storage.read_workout(wid)
        exercise = workout["exercises"][0]
        storage.save_workout(wid, "Repeated clusters", [exercise, copy.deepcopy(exercise)])
        active = storage.build_active_workout(storage.read_workout(wid))
        self.assertEqual(2, len({row["group_id"] for row in active["rows"]}))
        for row in active["rows"]: row["completed"] = True
        self.assertEqual(2, storage.volume_report(active["rows"])["totals"]["protocol_groups"])

    def test_group_ids_are_stable_and_deleted_members_do_not_shrink_the_snapshot(self):
        _, active = self.workout()
        rows = active["rows"]
        identity = rows[0]["group_id"]
        self.assertEqual({identity}, {row["group_id"] for row in rows})
        self.assertEqual({"5"}, {row["group_planned_count"] for row in rows})
        va.assign_groups(rows)
        rows.pop(0)
        va.assign_groups(rows)
        report = storage.volume_report(rows)
        self.assertEqual({identity}, {row["group_id"] for row in rows})
        self.assertEqual({"5"}, {row["group_planned_count"] for row in rows})
        self.assertEqual((0, 1), (report["totals"]["complete_protocol_groups"], report["totals"]["partial_protocol_groups"]))

    def test_warmups_missed_rows_orphans_and_inconsistent_roles_do_not_inflate_sets(self):
        _, active = self.workout()
        rows = active["rows"]
        rows[0]["completed"] = False
        rows.append(dict(rows[0], set_type="Warm-up", segment_role="warmup", completed=True))
        report = storage.volume_report(rows)
        self.assertEqual((4, 0, 4, 1), tuple(report["totals"][key] for key in ("working_segments", "activations", "continuations", "partial_protocol_groups")))
        rows[0].update(completed=True, segment_role="conventional")
        report = storage.volume_report(rows)
        self.assertEqual(0, report["totals"]["conventional_sets"])
        self.assertEqual(1, report["totals"]["unclassified"])

    def test_legacy_grouping_and_tags_remain_explicitly_inferred_without_mutation(self):
        _, active = self.workout()
        rows = [{key: value for key, value in row.items() if key not in va.FIELDS and key != "planned_work_count"} for row in active["rows"]]
        before = copy.deepcopy(rows)
        report = storage.volume_report(rows)
        self.assertEqual(before, rows)
        self.assertEqual(5, report["inferred_group_rows"])
        self.assertEqual(5, report["legacy_metadata_rows"])
        self.assertEqual((1, 0), (report["totals"]["protocol_groups"], report["totals"]["complete_protocol_groups"]))

    def test_direct_and_indirect_exposure_are_separate_without_fractional_credit(self):
        _, active = self.workout("Straight", count=3)
        report = storage.volume_report(active["rows"])
        self.assertEqual(3, report["direct"]["Chest"]["conventional_sets"])
        self.assertNotIn("Triceps", report["direct"])
        self.assertEqual(3, report["indirect"]["Triceps"]["conventional_sets"])
        for row in active["rows"]: row["secondary_muscles_snapshot"] = "Chest|Triceps"
        report = storage.volume_report(active["rows"])
        self.assertNotIn("Chest", report["indirect"])

    def test_new_muscle_snapshots_survive_later_tag_changes_and_intentional_empties(self):
        _, active = self.workout("Straight", count=2)
        storage.save_exercise_details("Counted exercise", ["Back"], [], "", "")
        report = storage.volume_report(active["rows"])
        self.assertEqual({"Chest"}, set(report["direct"]))
        self.assertEqual({"Triceps"}, set(report["indirect"]))
        for row in active["rows"]:
            row.update(primary_muscles_snapshot="", secondary_muscles_snapshot="")
        report = storage.volume_report(active["rows"])
        self.assertEqual({}, report["direct"])
        self.assertEqual({}, report["indirect"])

    def test_cleared_builtin_muscle_tags_stay_empty_across_reload_backup_and_new_sessions(self):
        storage.save_exercise_details("Bench Press", [], [], "", "")
        storage.ensure_data()
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        details = storage.read_exercise_details("Bench Press")
        self.assertEqual("", details["primary_muscles"])
        self.assertEqual("", details["secondary_muscles"])
        active = storage.build_active_workout(storage.read_workout("A"))
        bench = [row for row in active["rows"] if row["exercise_name"] == "Bench Press"]
        self.assertTrue(all(row["primary_muscles_snapshot"] == "" for row in bench))

    def test_legacy_absent_tag_columns_receive_defaults_once(self):
        rows = storage._read_csv(storage.EXERCISE_DETAILS_FILE)
        fields = [key for key in storage.EXERCISE_DETAIL_FIELDS if key not in {"primary_muscles", "secondary_muscles"}]
        storage._write_csv(storage.EXERCISE_DETAILS_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        storage.ensure_data()
        self.assertEqual("Chest", storage.read_exercise_details("Bench Press")["primary_muscles"])
        storage.save_exercise_details("Bench Press", [], [], "", "")
        self.assertEqual("", storage.read_exercise_details("Bench Press")["primary_muscles"])

    def test_five_seven_and_ten_day_schedules_use_matching_units_and_repeat_occurrences(self):
        wid, _ = self.workout("Straight", count=6)
        for days, weekly in [(5, 16.8), (7, 12), (10, 8.4)]:
            cycle = storage.save_mesocycle({"microcycle_days": str(days), "setup_complete": "1"})
            storage.save_mesocycle_day_schedule(cycle, {1: wid, 3: wid}, microcycle_days=days)
            report = storage.mesocycle_volume_report(storage.get_mesocycle(cycle))
            self.assertEqual(12, report["direct"]["Chest"]["conventional_sets"])
            self.assertEqual(weekly, report["weekly_direct"]["Chest"]["conventional_sets"])
            self.assertEqual(weekly, report["weekly_indirect"]["Triceps"]["conventional_sets"])
            self.assertEqual(weekly, storage.mesocycle_weekly_primary_set_counts(storage.get_mesocycle(cycle))["Chest"])

    def test_repeated_protocol_occurrences_do_not_merge_across_days_or_sessions(self):
        wid, active = self.workout()
        cycle = storage.save_mesocycle({"microcycle_days": "10", "setup_complete": "1"})
        storage.save_mesocycle_day_schedule(cycle, {1: wid, 3: wid}, microcycle_days=10)
        report = storage.mesocycle_volume_report(storage.get_mesocycle(cycle))
        self.assertEqual((2, 8), (report["totals"]["protocol_groups"], report["totals"]["continuations"]))
        self.assertAlmostEqual(1.4, report["weekly_totals"]["protocol_groups"])
        # Even a reused imported group ID is scoped by the actual session.
        rows = [{**row, "session_id": sid} for sid in ("first", "second") for row in active["rows"]]
        self.assertEqual(2, storage.volume_report(rows)["totals"]["protocol_groups"])

    def test_landmark_labels_preserve_ranges_without_a_representative_point(self):
        self.assertEqual((4, 6), landmarks.mev_target("Chest"))
        self.assertEqual("4–6", landmarks.mev_label("Chest"))
        self.assertEqual("0–8", landmarks.mev_label("Forearms"))
        self.assertEqual("—", landmarks.mev_label("Unknown"))

    def test_group_and_snapshot_fields_survive_active_history_unit_backup_and_edit_paths(self):
        _, active = self.workout()
        storage.save_active_workout(active)
        identity = {row["group_id"] for row in active["rows"]}
        storage.change_weight_unit("lb")
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        loaded = storage.load_active_workout()
        self.assertEqual(identity, {row["group_id"] for row in loaded["rows"]})
        storage.finish_active_workout(loaded)
        session = storage.read_session(active["session_id"])
        storage.save_session(session["session_id"], session["workout_name"], session["rows"])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        report = storage.volume_report(storage.read_session(session["session_id"])["rows"])
        self.assertEqual((1, 4), (report["totals"]["complete_protocol_groups"], report["totals"]["continuations"]))
        self.assertEqual(0, report["legacy_metadata_rows"])

    def test_invalid_metadata_imports_are_rejected_without_mutation(self):
        _, active = self.workout()
        storage.save_active_workout(active)
        for key, value in [("segment_role", "full set equivalent"), ("group_planned_count", "0"), ("group_planned_count", "1.5"), ("muscle_metadata_recorded", "yes")]:
            before = self.snapshot()
            rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
            rows[0][key] = value
            with self.assertRaises(ValueError):
                storage.import_data_zip_bytes(self.rewrite_archive("active_workout.csv", self.csv_bytes(storage.ACTIVE_FIELDS, rows)))
            self.assertEqual(before, self.snapshot())

    def test_multiple_groups_stay_separate_and_do_not_enable_single_group_progression(self):
        _, active = self.workout()
        rows = active["rows"]
        second = copy.deepcopy(rows)
        for row in second: row["group_id"] = "second-protocol"
        combined = rows + second
        self.assertEqual(2, storage.volume_report(combined)["totals"]["protocol_groups"])
        rec = progression.method_progression_recommendation(combined, method="Myo-Reps", target_rir=2)
        self.assertEqual("hold", rec["action"])
        self.assertIn("multiple protocol groups", rec["reason"])

    def test_relabeling_protocol_fragments_does_not_create_ordinary_progression_evidence(self):
        _, active = self.workout()
        for row in active["rows"]: row.update(set_type="Normal", training_method="Straight", reps="13", rir="2")
        rec = progression.progression_recommendation(active["rows"], target_rir=2)
        self.assertEqual("hold", rec["action"])
        self.assertFalse(rec["apply_weight"])
        self.assertIn("protocol fragments", rec["reason"])

    def test_failed_finish_preserves_group_ids_and_snapshots_for_retry(self):
        _, active = self.workout()
        storage.save_active_workout(active)
        before = self.snapshot()
        with mock.patch.object(storage, "clear_active_workout", side_effect=OSError("simulated interruption")):
            with self.assertRaises(OSError): storage.finish_active_workout(active)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(5, storage.finish_active_workout(active))
        self.assertEqual(5, storage.finish_active_workout(active))
