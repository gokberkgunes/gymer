"""Exception, concurrency and real process-termination tests for CSV commits."""

import os
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from unittest import mock

from test_data_integrity import TemporaryStorageTestCase
import storage
import csv_transactions


TEST_TIME = datetime.now().replace(microsecond=0)


class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
        return cls.fromisoformat(TEST_TIME.isoformat())


CHILD = r'''
import os, sys
from pathlib import Path
import storage, csv_transactions
from datetime import datetime
class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
        return cls.fromisoformat(os.environ['GYMER_TEST_TIME'])
storage.datetime = FrozenDateTime
mode, stage, point = sys.argv[1], int(sys.argv[2]), sys.argv[3]
active = None if mode == 'migrate' else storage.load_active_workout()
original_write = csv_transactions.atomic_write
original_delete = storage._delete_file
count = 0
def after_mutation():
    global count
    count += 1
    if point == 'mutation' and count == stage:
        os._exit(75)
def write(path, data):
    original_write(path, data)
    if Path(path).name == csv_transactions.JOURNAL_NAME and point == 'prepared':
        os._exit(75)
    elif Path(path).name != csv_transactions.JOURNAL_NAME:
        after_mutation()
def delete(path):
    original_delete(path)
    after_mutation()
csv_transactions.atomic_write = write
storage._delete_file = delete
unlink = Path.unlink
def journal_unlink(path, *args, **kwargs):
    if path.name == csv_transactions.JOURNAL_NAME and point == 'before_commit':
        os._exit(75)
    result = unlink(path, *args, **kwargs)
    if path.name == csv_transactions.JOURNAL_NAME and point == 'after_commit':
        os._exit(75)
    return result
Path.unlink = journal_unlink
def save_template():
    storage.save_workout('A', 'Changed', [{'exercise_name':'Leg Press','sets':[
        {'weight':'60','reps':'8','rest_seconds':120,'set_type':'Normal'}]}])
if mode == 'unit': storage.change_weight_unit('lb')
elif mode == 'save': save_template()
elif mode == 'rename': storage.rename_exercise('Leg Press','Audit Leg Press')
elif mode == 'delete': storage.delete_workout('A')
elif mode == 'import': storage.import_data_zip_bytes((storage.DATA_DIR/'restore.zip').read_bytes())
elif mode == 'finish': storage.finish_active_workout(active, save_template=save_template)
elif mode == 'migrate': storage.ensure_data()
else: raise AssertionError(mode)
raise AssertionError('The failure injection did not run')
'''


class TransactionTests(TemporaryStorageTestCase):
    def prepare_active(self):
        cycle = storage.save_mesocycle({"setup_complete": "1"})
        storage.save_mesocycle_day_schedule(cycle, {1: "A"})
        active = storage.build_active_workout(storage.read_workout("A"))
        active["rows"][0].update(weight="50", reps="10", rir="2", completed=True, calibration_done=True)
        storage.save_active_workout(active)
        return active

    def save_template(self):
        storage.save_workout("A", "Changed", [{"exercise_name": "Leg Press", "sets": [
            {"weight": "60", "reps": "8", "rest_seconds": 120, "set_type": "Normal"}]}])

    def operations(self):
        active = self.prepare_active()
        self.add_session()
        (self.directory / "restore.zip").write_bytes(storage.export_data_zip_bytes())
        settings = storage.read_settings()
        storage.save_settings({**settings, "accent_color": "green"})
        return {
            "unit": lambda: storage.change_weight_unit("lb"),
            "save": self.save_template,
            "rename": lambda: storage.rename_exercise("Leg Press", "Audit Leg Press"),
            "delete": lambda: storage.delete_workout("A"),
            "import": lambda: storage.import_data_zip_bytes((self.directory / "restore.zip").read_bytes()),
            "finish": lambda: storage.finish_active_workout(active, save_template=self.save_template),
        }

    def probe(self, operation):
        """Measure actual mutation count and capture expected state, then undo."""
        class UndoProbe(Exception): pass
        count = 0
        original_write = csv_transactions.atomic_write
        original_delete = storage._delete_file
        def write(path, data):
            nonlocal count
            original_write(path, data)
            if Path(path).name != csv_transactions.JOURNAL_NAME:
                count += 1
        def delete(path):
            nonlocal count
            original_delete(path)
            count += 1
        try:
            with storage.storage_transaction():
                with mock.patch.object(csv_transactions, "atomic_write", side_effect=write), mock.patch.object(storage, "_delete_file", side_effect=delete), mock.patch.object(storage, "datetime", FrozenDateTime):
                    operation()
                expected, mutations = self.snapshot(), count
                raise UndoProbe()
        except UndoProbe:
            pass
        return expected, mutations

    def test_failure_after_each_mutation_rolls_back_every_related_file(self):
        for name, operation in self.operations().items():
            expected, mutations = self.probe(operation)
            before = self.snapshot()
            self.assertNotEqual(before, expected)
            for stage in range(1, mutations + 1):
                with self.subTest(operation=name, stage=stage):
                    count = 0
                    original_write = csv_transactions.atomic_write
                    original_delete = storage._delete_file
                    def after_mutation():
                        nonlocal count
                        count += 1
                        if count == stage:
                            raise OSError("injected disk failure")
                    def write(path, data):
                        original_write(path, data)
                        if Path(path).name != csv_transactions.JOURNAL_NAME:
                            after_mutation()
                    def delete(path):
                        original_delete(path)
                        after_mutation()
                    with mock.patch.object(csv_transactions, "atomic_write", side_effect=write), mock.patch.object(storage, "_delete_file", side_effect=delete):
                        with self.assertRaisesRegex(OSError, "injected disk failure"):
                            operation()
                    self.assertEqual(before, self.snapshot())
                    self.assertFalse((self.directory / csv_transactions.JOURNAL_NAME).exists())

    def test_process_death_at_each_mutation_and_commit_point_recovers(self):
        for name, operation in self.operations().items():
            expected, mutations = self.probe(operation)
            before = self.snapshot()
            points = [(0, "prepared")] + [(stage, "mutation") for stage in range(1, mutations + 1)] + [(0, "before_commit"), (0, "after_commit")]
            for stage, point in points:
                with self.subTest(operation=name, stage=stage, point=point):
                    environment = {**os.environ, "FLET_APP_STORAGE_DATA": str(self.directory),
                                   "GYMER_TEST_TIME": TEST_TIME.isoformat(),
                                   "PYTHONPATH": str(Path(storage.__file__).parent)}
                    result = subprocess.run([sys.executable, "-c", CHILD, name, str(stage), point],
                                            env=environment, capture_output=True, text=True, timeout=15)
                    self.assertEqual(75, result.returncode, result.stdout + result.stderr)
                    # The first access is deliberately a simple read, not only
                    # ensure_data(), proving recovery precedes other requests.
                    storage.read_settings()
                    self.assertEqual(expected if point == "after_commit" else before, self.snapshot())
                    self.assertFalse((self.directory / csv_transactions.JOURNAL_NAME).exists())
                    if point == "after_commit":
                        with storage.storage_transaction():
                            for path in storage.BACKUP_DATA_FILES:
                                storage._atomic_write_bytes(path, before[path.name])

    def test_finish_is_idempotent_and_does_not_change_a_new_active_workout(self):
        active = self.prepare_active()
        self.assertEqual(1, storage.finish_active_workout(active, save_template=self.save_template))
        saved = self.snapshot()
        with mock.patch.object(self, "save_template", side_effect=AssertionError("template callback repeated")):
            self.assertEqual(1, storage.finish_active_workout(active, save_template=self.save_template))
        self.assertEqual(saved, self.snapshot())
        self.assertIsNone(storage.load_active_workout())
        self.assertEqual(1, len(storage.all_sessions()))
        next_active = storage.build_active_workout(storage.read_workout("B"))
        storage.save_active_workout(next_active)
        self.assertEqual(1, storage.finish_active_workout(active))
        storage.save_active_workout(active)  # delayed autosave of the old UI
        self.assertEqual(next_active["session_id"], storage.load_active_workout()["session_id"])

    def test_concurrent_finish_saves_exactly_one_session(self):
        active = self.prepare_active()
        with ThreadPoolExecutor(max_workers=4) as pool:
            counts = list(pool.map(lambda _: storage.finish_active_workout(active), range(8)))
        self.assertEqual([1] * 8, counts)
        self.assertEqual(1, len(storage.all_sessions()))
        self.assertIsNone(storage.load_active_workout())

    def test_stale_unsaved_finish_cannot_complete_a_different_active_workout(self):
        stale = self.prepare_active()
        current = storage.build_active_workout(storage.read_workout("B"))
        storage.save_active_workout(current)
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "no longer"):
            storage.finish_active_workout(stale)
        self.assertEqual(before, self.snapshot())

    def test_legacy_active_session_id_is_upgraded_once_and_survives_backup(self):
        active = self.prepare_active()
        legacy_fields = [field for field in storage.ACTIVE_FIELDS if field != "session_id"]
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        storage._write_csv(storage.ACTIVE_WORKOUT_FILE, legacy_fields, [
            {key: row[key] for key in legacy_fields} for row in rows])
        upgraded = storage.load_active_workout()
        self.assertTrue(upgraded["session_id"])
        self.assertEqual(upgraded["session_id"], storage.load_active_workout()["session_id"])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual(upgraded["session_id"], storage.load_active_workout()["session_id"])
        self.assertEqual(1, storage.finish_active_workout(upgraded))
        self.assertEqual(upgraded["session_id"], storage.all_sessions()[0]["session_id"])

    def test_caught_nested_error_still_cancels_the_outer_transaction(self):
        before = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, "nested"):
            with storage.storage_transaction():
                storage.save_settings({**storage.read_settings(), "unit": "lb"})
                try:
                    with storage.storage_transaction():
                        raise ValueError("nested failure")
                except ValueError:
                    pass
        self.assertEqual(before, self.snapshot())

    def test_failed_reload_does_not_commit_a_unit_change(self):
        self.prepare_active()
        before = self.snapshot()
        with mock.patch.object(storage, "load_active_workout", side_effect=OSError("cannot reload")):
            with self.assertRaisesRegex(OSError, "cannot reload"):
                storage.change_weight_unit("lb")
        self.assertEqual(before, self.snapshot())

    def test_concurrent_processes_finish_once(self):
        import json
        active = self.prepare_active()
        payload = self.directory / "finish-input.json"
        payload.write_text(json.dumps(active))
        program = "import json,storage; a=json.loads((storage.DATA_DIR/'finish-input.json').read_text()); print(storage.finish_active_workout(a))"
        environment = {**os.environ, "FLET_APP_STORAGE_DATA": str(self.directory),
                       "PYTHONPATH": str(Path(storage.__file__).parent)}
        children = [subprocess.Popen([sys.executable, "-c", program], env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(4)]
        try:
            for child in children:
                output, error = child.communicate(timeout=15)
                self.assertEqual(0, child.returncode, error)
                self.assertEqual("1", output.strip())
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.communicate()
        self.assertEqual(1, len(storage.all_sessions()))
        self.assertIsNone(storage.load_active_workout())

    def test_startup_migration_recovers_after_process_death(self):
        self.prepare_active()
        fields = [field for field in storage.ACTIVE_FIELDS if field != "session_id"]
        rows = storage._read_csv(storage.ACTIVE_WORKOUT_FILE)
        storage._write_csv(storage.ACTIVE_WORKOUT_FILE, fields, [{key: row[key] for key in fields} for row in rows])
        before = self.snapshot()
        for stage in (1, 2):  # new header, then persistent session ID
            environment = {**os.environ, "FLET_APP_STORAGE_DATA": str(self.directory),
                           "GYMER_TEST_TIME": TEST_TIME.isoformat(),
                           "PYTHONPATH": str(Path(storage.__file__).parent)}
            result = subprocess.run([sys.executable, "-c", CHILD, "migrate", str(stage), "mutation"],
                                    env=environment, capture_output=True, text=True, timeout=15)
            self.assertEqual(75, result.returncode, result.stderr)
            storage.read_settings()
            self.assertEqual(before, self.snapshot())
        self.assertTrue(storage.load_active_workout()["session_id"])

    def test_failed_rollback_retains_journal_for_next_access(self):
        before = self.snapshot()
        original_write = csv_transactions.atomic_write
        failed = False
        def write(path, data):
            nonlocal failed
            if Path(path) == storage.WORKOUTS_FILE:
                if not failed:
                    original_write(path, data)
                    failed = True
                raise OSError("disk unavailable")
            original_write(path, data)
        with mock.patch.object(csv_transactions, "atomic_write", side_effect=write):
            with self.assertRaises(OSError):
                self.save_template()
        self.assertTrue((self.directory / csv_transactions.JOURNAL_NAME).exists())
        storage.read_workouts()
        self.assertEqual(before, self.snapshot())
        self.assertFalse((self.directory / csv_transactions.JOURNAL_NAME).exists())

    def test_reader_waits_for_grouped_save(self):
        written, release, reader_started = threading.Event(), threading.Event(), threading.Event()
        original_write = storage._atomic_write_bytes
        def write(path, data):
            original_write(path, data)
            if path == storage.WORKOUTS_FILE:
                written.set()
                if not release.wait(5):
                    raise RuntimeError("test timed out")
        def read():
            reader_started.set()
            return storage.read_workout("A")
        with ThreadPoolExecutor(max_workers=2) as pool, mock.patch.object(storage, "_atomic_write_bytes", side_effect=write):
            writer = pool.submit(self.save_template)
            try:
                self.assertTrue(written.wait(5))
                reader = pool.submit(read)
                self.assertTrue(reader_started.wait(5))
                self.assertFalse(reader.done())
            finally:
                release.set()
            writer.result(timeout=5)
            workout = reader.result(timeout=5)
        self.assertEqual("Changed", workout["name"])
        self.assertEqual(1, len(workout["exercises"]))

    def test_invalid_journal_stops_access_without_altering_data(self):
        before = self.snapshot()
        journal = self.directory / csv_transactions.JOURNAL_NAME
        journal.write_text('{"version":1,"files":{"../escape":null}}')
        with self.assertRaisesRegex(RuntimeError, "journal is invalid"):
            storage.read_workouts()
        self.assertEqual(before, self.snapshot())
        self.assertTrue(journal.exists())
