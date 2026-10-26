"""Rest recovery uses temporary storage and controllable wall/monotonic clocks."""
import json
from types import SimpleNamespace
from unittest import mock
from test_data_integrity import TemporaryStorageTestCase
from timers import TimerMixin
import storage
import rest_timer_state as state


class TimerApp(TimerMixin):
    def __init__(self, active):
        self.active_workout = active
        self.set_controls = []
        self.page = SimpleNamespace(update=mock.Mock(), run_task=mock.Mock())
        self.timer_generation = 0
        self.timer_started_at = None
        self.timer_inline_item = None
        self.timer_popup = SimpleNamespace()
        self.timer_name_text = SimpleNamespace()
        self.timer_value_text = SimpleNamespace()
        self.dismiss_timer(persist=False)

    def default_timer_display_mode(self): return 'elapsed'
    def floating_timer_enabled(self): return True
    def nearset_timer_enabled(self): return True
    def accent_color(self): return '#ff0000'
    def foreground_color(self): return '#ffffff'


class RestTimerRecoveryTests(TemporaryStorageTestCase):
    def active(self):
        active = storage.build_active_workout(storage.read_workout('A'))
        active['rows'][0].update(completed=True, weight='50', reps='10', rir='2')
        storage.save_active_workout(active)
        return active

    def start(self, duration=60):
        app = TimerApp(self.active())
        with mock.patch('timers.time.time', return_value=1000), mock.patch('timers.time.monotonic', return_value=100):
            app.start_rest_timer(app.active_workout['rows'][0]['exercise_name'], duration,
                                 inline_item=app.active_workout['rows'][0])
        return app

    def recover(self, wall=1025):
        app = TimerApp(storage.load_active_workout())
        with mock.patch('timers.time.time', return_value=wall), mock.patch('timers.time.monotonic', return_value=500):
            app.restore_rest_timer()
        return app

    def test_restart_accounts_for_time_away_and_preserves_overdue(self):
        self.start()
        for wall, expected in [(1025, '00:25 / 1:00'), (1090, '01:30 / 1:00')]:
            recovered = self.recover(wall)
            self.assertEqual(expected, recovered.timer_value_text.value)
            self.assertIsNotNone(recovered.timer_started_at)
            self.assertEqual(1, recovered.page.run_task.call_count)

    def test_monotonic_runtime_ignores_wall_clock_changes_and_backward_recovery_clamps(self):
        app = self.start()
        with mock.patch('timers.time.time', return_value=9999999), mock.patch('timers.time.monotonic', return_value=110):
            app.refresh_timer_display()
        self.assertEqual('00:10 / 1:00', app.timer_value_text.value)
        self.assertEqual('00:00 / 1:00', self.recover(900).timer_value_text.value)

    def test_dismissal_clears_disk_and_does_not_reappear(self):
        app = self.start()
        app.dismiss_timer()
        self.assertEqual('', storage.load_active_workout()['rest_timer_state'])
        self.assertIsNone(self.recover().timer_started_at)

    def test_display_mode_and_duration_edits_survive_recovery(self):
        app = self.start()
        app.timer_total_seconds = 90
        with mock.patch('timers.time.monotonic', return_value=110):
            app.handle_floating_timer_hold()
        self.assertEqual('1:05', self.recover().timer_value_text.value)

    def test_backup_units_and_rename_preserve_timer(self):
        self.start()
        raw = storage.load_active_workout()['rest_timer_state']
        storage.change_weight_unit('lb')
        self.assertEqual(raw, storage.load_active_workout()['rest_timer_state'])
        archive = storage.export_data_zip_bytes()
        storage.clear_active_workout()
        storage.import_data_zip_bytes(archive)
        active = storage.load_active_workout()
        self.assertEqual(raw, active['rest_timer_state'])
        old = active['rows'][0]['exercise_name']
        self.assertTrue(storage.rename_exercise(old, 'Renamed timer exercise'))
        self.assertEqual('Renamed timer exercise', self.recover().timer_exercise_name)

    def test_legacy_missing_and_stale_source_do_not_create_countdown(self):
        app = TimerApp(self.active())
        app.restore_rest_timer()
        self.assertIsNone(app.timer_started_at)
        self.start()
        active = storage.load_active_workout()
        active['rows'][0]['completed'] = False
        app = TimerApp(active)
        app.restore_rest_timer()
        self.assertIsNone(app.timer_started_at)

    def test_corrupt_snapshot_rejects_import_without_modifying_data(self):
        self.start()
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        for bad in ('[]', '{', '{"version":1}', json.dumps({**state.decode(rows[0]['rest_timer_state']), 'started_epoch': float('nan')})):
            altered = [dict(row, rest_timer_state=bad) for row in rows]
            archive = self.rewrite_archive('active_workout.csv', self.csv_bytes(storage.ACTIVE_FIELDS, altered))
            before = self.snapshot()
            with self.assertRaises(ValueError): storage.import_data_zip_bytes(archive)
            self.assertEqual(before, self.snapshot())

    def test_wrong_session_or_source_and_inconsistent_rows_reject_import(self):
        self.start()
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        for key, value in [('session_id', 'different-session'), ('set_number', 999), ('total_seconds', -1)]:
            changed = state.decode(rows[0]['rest_timer_state'])
            changed[key] = value
            altered = [dict(row, rest_timer_state=json.dumps(changed)) for row in rows]
            before = self.snapshot()
            with self.assertRaises(ValueError):
                storage.import_data_zip_bytes(self.rewrite_archive('active_workout.csv', self.csv_bytes(storage.ACTIVE_FIELDS, altered)))
            self.assertEqual(before, self.snapshot())
        rows[-1]['rest_timer_state'] = ''
        with self.assertRaises(ValueError):
            storage.import_data_zip_bytes(self.rewrite_archive('active_workout.csv', self.csv_bytes(storage.ACTIVE_FIELDS, rows)))

    def test_import_replaces_previous_runtime_without_overwriting_restored_snapshot(self):
        app = self.start()
        archive = storage.export_data_zip_bytes()
        with mock.patch('timers.time.time', return_value=1010), mock.patch('timers.time.monotonic', return_value=110):
            app.start_rest_timer(app.timer_exercise_name, 120, inline_item=app.active_workout['rows'][0])
        generation = app.timer_generation
        storage.import_data_zip_bytes(archive)
        before = self.snapshot()
        app.active_workout = storage.load_active_workout()
        with mock.patch('timers.time.time', return_value=1020), mock.patch('timers.time.monotonic', return_value=500):
            app.restore_rest_timer()
        self.assertEqual(60, app.timer_total_seconds)
        self.assertEqual('00:20 / 1:00', app.timer_value_text.value)
        self.assertGreater(app.timer_generation, generation)
        self.assertEqual(before, self.snapshot())

    def test_missing_active_session_clears_previous_popup_without_resurrection(self):
        app = self.start()
        generation = app.timer_generation
        storage.clear_active_workout()
        app.active_workout = storage.load_active_workout()
        before = self.snapshot()
        app.restore_rest_timer()
        self.assertIsNone(app.timer_started_at)
        self.assertFalse(app.timer_popup.visible)
        self.assertGreater(app.timer_generation, generation)
        self.assertEqual(before, self.snapshot())
