"""Session totals count performed entries without changing volume categories."""
from test_data_integrity import TemporaryStorageTestCase
import storage


class SessionStatusTests(TemporaryStorageTestCase):
    def record(self, workout_id='A'):
        storage.append_session({'workout_id': workout_id, 'name': 'Status'}, [
            {'exercise_name': 'Leg Press', 'set_number': 1, 'weight': '50',
             'reps': '10', 'rir': '2', 'completed': True},
            {'exercise_name': 'Leg Press', 'set_number': 2, 'weight': '',
             'reps': '', 'rir': '', 'completed': False},
        ])

    def test_all_overviews_separate_completed_from_planned(self):
        self.record()
        for sessions in (storage.recent_sessions(), storage.all_sessions(), storage.workout_sessions('A')):
            self.assertEqual(1, len(sessions))
            self.assertEqual((1, 2, 1), tuple(sessions[0][key] for key in
                             ('completed_count', 'planned_count', 'set_count')))

    def test_limits_do_not_truncate_entries_and_workout_filters_are_scoped(self):
        self.record()
        self.record('B')
        for sessions in (storage.recent_sessions(1), storage.all_sessions(1), storage.workout_sessions('A', 1)):
            self.assertEqual(1, len(sessions))
            self.assertEqual(2, sessions[0]['planned_count'])
        self.assertEqual('A', storage.workout_sessions('A')[0]['workout_id'])
        self.assertEqual([], storage.all_sessions(0))
        self.assertEqual([], storage.workout_sessions('missing'))

    def test_correcting_completion_updates_all_overviews(self):
        self.record()
        session = storage.read_session(storage.all_sessions()[0]['session_id'])
        session['rows'][1].update(completed=True, weight='50', reps='8', rir='2')
        storage.save_session(session["session_id"], session["workout_name"], session["rows"])
        self.assertEqual(2, storage.recent_sessions()[0]['completed_count'])
