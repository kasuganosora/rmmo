"""Cooperating processes hold this lock while using or changing a fixture.

The lock does not detect external programs that ignore it. Callers must ensure
all fixture consumers use it and must not remove or replace the lock file.
"""
from contextlib import contextmanager
import os
from pathlib import Path
import time


@contextmanager
def fixture_lock(root, *, timeout=0.0):
    root = Path(root).resolve(strict=True)
    if not root.is_dir() or not (root / "fixture_manifest.json").is_file():
        raise ValueError("existing fixture root and manifest required")
    path = root / ".benchmark.lock"
    if path.is_symlink():
        raise ValueError("fixture lock must not be a symbolic link")
    handle = path.open("a+b")
    try:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\0")
            handle.flush()
        deadline = time.monotonic() + max(0.0, float(timeout))
        while True:
            try:
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("fixture is in use") from None
                time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == "nt":
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        handle.close()
