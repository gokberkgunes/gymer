"""Workout time is monotonic in process and recovers persisted UTC intervals."""
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from unittest import mock
from test_data_integrity import TemporaryStorageTestCase
from test_rest_timer_recovery import TimerApp
import storage

NOW = datetime(2026, 10, 19, 12, tzinfo=timezone.utc)


@contextmanager
def clock(now=NOW, mono=100):
    with mock.patch('timers.datetime', wraps=datetime) as dates, mock.patch('timers.time.monotonic', return_value=mono):
        dates.now.return_value = now
        yield


class WorkoutClockTests(TemporaryStorageTestCase):
    def app(self, active=None):
        app = TimerApp(active or storage.build_active_workout(storage.read_workout('A')))
        app.workout_elapsed_text = None
        app.workout_timer_play_icon = None
        app.workout_timer_pause_icon = None
        return app

    def test_start_records_utc_and_runtime_ignores_wall_clock_jumps(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        self.assertEqual(timedelta(0), datetime.fromisoformat(app.active_workout['started_at']).utcoffset())
        for now in (NOW + timedelta(days=3), NOW - timedelta(days=3)):
            with clock(now, 130): self.assertEqual(30, app.workout_elapsed_seconds())

    def test_pause_is_frozen_resume_accumulates_and_completion_cannot_resume(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        with clock(mono=120): app.toggle_workout_clock()
        with clock(NOW + timedelta(hours=2), 500):
            app.start_workout_clock()
            self.assertTrue(app.workout_clock_is_paused())
            self.assertEqual(20, app.workout_elapsed_seconds())
            app.toggle_workout_clock()
        with clock(NOW - timedelta(hours=2), 510): self.assertEqual(30, app.workout_elapsed_seconds())

    def test_restart_recovers_once_then_uses_monotonic_time(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        recovered = self.app(storage.load_active_workout())
        with clock(NOW + timedelta(minutes=3), 500): self.assertEqual(180, recovered.workout_elapsed_seconds())
        with clock(NOW - timedelta(days=2), 515): self.assertEqual(195, recovered.workout_elapsed_seconds())

    def test_aware_offset_and_legacy_local_timestamps_recover(self):
        for stamp in ((NOW - timedelta(seconds=45)).astimezone(timezone(timedelta(hours=-5))).isoformat(),
                      (NOW - timedelta(seconds=45)).astimezone().replace(tzinfo=None).isoformat()):
            app = self.app()
            app.active_workout.update(started_at=stamp, timer_started=True, timer_elapsed_seconds=10)
            with clock(): self.assertEqual(55, app.workout_elapsed_seconds())
            self.assertEqual(stamp, app.active_workout['started_at'])

    def test_backward_recovery_and_invalid_timestamp_preserve_stored_elapsed(self):
        for stamp in ((NOW + timedelta(hours=1)).isoformat(), 'invalid'):
            app = self.app()
            app.active_workout.update(started_at=stamp, timer_started=True, timer_elapsed_seconds=20)
            with clock(): self.assertEqual(20, app.workout_elapsed_seconds())

    def test_reset_persists_and_next_start_has_fresh_anchor(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        with clock(mono=120): app.reset_workout_clock()
        self.assertFalse(storage.load_active_workout()['timer_started'])
        with clock(NOW + timedelta(days=1), 500): app.start_workout_clock()
        with clock(mono=510): self.assertEqual(10, app.workout_elapsed_seconds())

    def test_units_reload_preserves_runtime_anchor_and_backup_preserves_interval(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        _, app.active_workout = storage.change_weight_unit('lb')
        with clock(NOW + timedelta(days=2), 110): self.assertEqual(10, app.workout_elapsed_seconds())
        before = storage.load_active_workout()['started_at']
        archive = storage.export_data_zip_bytes()
        storage.clear_active_workout()
        storage.import_data_zip_bytes(archive)
        self.assertEqual(before, storage.load_active_workout()['started_at'])

    def test_paused_reload_counts_no_time_away(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        with clock(mono=125): app.toggle_workout_clock()
        recovered = self.app(storage.load_active_workout())
        with clock(NOW + timedelta(days=1), 10000):
            self.assertEqual(25, recovered.workout_elapsed_seconds())
            self.assertTrue(recovered.workout_clock_is_paused())

    def test_import_legacy_timestamp_and_reject_invalid_date_without_mutation(self):
        app = self.app()
        with clock(): app.start_workout_clock()
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        legacy = (NOW - timedelta(seconds=30)).astimezone().replace(tzinfo=None).isoformat()
        for row in rows: row['started_at'] = legacy
        storage.import_data_zip_bytes(self.rewrite_archive('active_workout.csv', self.csv_bytes(storage.ACTIVE_FIELDS, rows)))
        self.assertEqual(legacy, storage.load_active_workout()['started_at'])
        for row in rows: row['started_at'] = 'broken-date'
        before = self.snapshot()
        with self.assertRaises(ValueError):
            storage.import_data_zip_bytes(self.rewrite_archive('active_workout.csv', self.csv_bytes(storage.ACTIVE_FIELDS, rows)))
        self.assertEqual(before, self.snapshot())
