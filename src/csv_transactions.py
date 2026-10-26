"""Serialized CSV operations with a durable undo journal for grouped changes.

The app keeps its existing CSV format. A journal is fsynced before the first
write of a transaction; it is removed only after all replacements are durable.
An interrupted transaction is rolled back before any subsequent storage access.
"""

import base64
import json
import os
import tempfile
import threading
from contextlib import contextmanager
from pathlib import Path


_LOCK = threading.RLock()
_LOCAL = threading.local()
JOURNAL_NAME = ".gymer-transaction.json"


def sync_directory(directory):
    if os.name == "posix":
        fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as f:
            temporary = Path(f.name)
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


@contextmanager
def _process_lock(directory):
    with open(directory / ".gymer.lock", "a+b") as lock:
        if os.name == "posix":
            import fcntl
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        else:
            import msvcrt
            if lock.seek(0, os.SEEK_END) == 0:
                lock.write(b"\0")
                lock.flush()
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)


def _recover(directory, paths):
    journal = directory / JOURNAL_NAME
    if not journal.exists():
        return
    try:
        payload = json.loads(journal.read_bytes())
        if payload.get("version") != 1 or set(payload["files"]) != {p.name for p in paths}:
            raise ValueError("unexpected journal schema")
        # Decode the entire journal before changing any file.
        previous = {
            name: None if raw is None else base64.b64decode(raw, validate=True)
            for name, raw in payload["files"].items()
        }
    except (ValueError, KeyError, TypeError, AttributeError) as exc:
        raise RuntimeError("Cannot recover saved data: the transaction journal is invalid. Keep the data directory for recovery.") from exc
    for path in paths:
        raw = previous[path.name]
        if raw is None:
            path.unlink(missing_ok=True)
        else:
            atomic_write(path, raw)
    sync_directory(directory)
    journal.unlink()
    sync_directory(directory)


@contextmanager
def access(directory, paths):
    """Keep a complete operation isolated from other threads/processes."""
    directory = Path(directory)
    with _LOCK:
        current = getattr(_LOCAL, "directory", None)
        if current is not None:
            if current != directory:
                raise RuntimeError("Cannot nest operations on different data directories.")
            yield
            return
        directory.mkdir(parents=True, exist_ok=True)
        with _process_lock(directory):
            _recover(directory, paths)
            _LOCAL.directory = directory
            try:
                yield
            finally:
                _LOCAL.directory = None


def before_write(directory, paths):
    """Lazily journal only transactions that actually modify stored data."""
    state = getattr(_LOCAL, "transaction", None)
    if state is None or state["previous"] is not None:
        return
    previous = {
        path.name: base64.b64encode(path.read_bytes()).decode("ascii") if path.exists() else None
        for path in paths
    }
    payload = json.dumps({"version": 1, "files": previous}).encode("utf-8")
    atomic_write(Path(directory) / JOURNAL_NAME, payload)
    state["previous"] = payload


@contextmanager
def transaction(directory, paths):
    with access(directory, paths):
        existing = getattr(_LOCAL, "transaction", None)
        if existing is not None:
            try:
                yield
            except BaseException:
                existing["failed"] = True
                raise
            return
        state = {"previous": None, "failed": False}
        _LOCAL.transaction = state
        journal = Path(directory) / JOURNAL_NAME
        try:
            yield
            if state["failed"]:
                raise RuntimeError("A nested storage operation failed; the transaction was cancelled.")
            if state["previous"] is not None:
                sync_directory(directory)
                journal.unlink()
                sync_directory(directory)
        except BaseException:
            if state["previous"] is not None:
                # If final directory sync failed after unlinking, reinstate the
                # journal before rollback. Keep it if rollback itself fails.
                if not journal.exists():
                    atomic_write(journal, state["previous"])
                _recover(Path(directory), paths)
            raise
        finally:
            _LOCAL.transaction = None
