"""Editor and cycle plans share scoped work categories without mutating templates."""
import copy
from test_data_integrity import TemporaryStorageTestCase
import storage


class PlannedWorkoutVolumeTests(TemporaryStorageTestCase):
    def exercise(self, name, method='Straight', count=3):
        storage.save_exercise_details(name, ['Chest'], ['Triceps'], '', '')
        return {'exercise_name': name, 'training_method': method,
                'sets': storage.reconcile_method_sets(method, [
                    {'set_type': 'Normal', 'weight': '50', 'reps': '10', 'rest_seconds': 30}
                    for _ in range(count)])}

    def test_editor_distinguishes_conventional_work_and_myo_segments(self):
        exercises = [self.exercise('Conventional', count=6), self.exercise('Myo', 'Myo-Reps', 5)]
        before = copy.deepcopy(exercises)
        report = storage.workout_volume_report(exercises)
        self.assertEqual((6, 1, 1, 4), tuple(report['totals'][key] for key in
                         ('conventional_sets', 'protocol_groups', 'activations', 'continuations')))
        self.assertEqual(6, report['direct']['Chest']['conventional_sets'])
        self.assertEqual(1, report['indirect']['Triceps']['protocol_groups'])
        self.assertEqual(before, exercises)
        self.assertEqual(0, report['legacy_metadata_rows'])

    def test_duplicate_cluster_placements_remain_separate_and_warmups_are_excluded(self):
        exercise = self.exercise('Cluster', 'Cluster', 3)
        exercise['sets'].insert(0, {'set_type': 'Warm-up', 'weight': '20', 'reps': '10'})
        report = storage.workout_volume_report([exercise, copy.deepcopy(exercise)])
        self.assertEqual((0, 2, 6), tuple(report['totals'][key] for key in
                         ('conventional_sets', 'protocol_groups', 'cluster_fragments')))
        self.assertEqual(2, report['totals']['complete_protocol_groups'])

    def test_cleared_tags_and_placeholder_rows_do_not_invent_exposure(self):
        exercise = self.exercise('Cleared tags')
        storage.save_exercise_details('Cleared tags', [], [], '', '')
        report = storage.workout_volume_report([exercise, {'exercise_name': '', 'sets': [{'set_type':'Normal'}]}])
        self.assertEqual(3, report['totals']['conventional_sets'])
        self.assertEqual({}, report['direct'])
        self.assertEqual({}, report['indirect'])

    def test_repeating_cycle_and_single_workout_reports_agree(self):
        exercises = [self.exercise('Straight'), self.exercise('Myo', 'Myo-Reps', 5)]
        wid = storage.create_workout('Report agreement')
        storage.save_workout(wid, 'Report agreement', exercises)
        stored = storage.read_workout(wid)['exercises']
        cycle_id = storage.save_mesocycle({'setup_complete':'1', 'microcycle_days':'10'})
        storage.save_mesocycle_day_schedule(cycle_id, {1:wid, 5:wid})
        single = storage.workout_volume_report(stored, report_groups=True)
        cycle = storage.mesocycle_volume_report(storage.get_mesocycle(cycle_id))
        for metric, value in single['totals'].items():
            self.assertEqual(2 * value, cycle['totals'][metric], metric)
            self.assertAlmostEqual(2 * value * 0.7, cycle['weekly_totals'][metric])
