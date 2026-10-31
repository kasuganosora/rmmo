"""Reproduce native pending-task shutdown without loading the game or a GPU.

Run with --expect-low-timeout for an affected engine, and without it for a fix.
Each priority condition runs in three fresh processes. A queued-work marker is
never counted as successful shutdown: the engine must actually exit cleanly.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def run(engine: Path, output: Path, expect_low_timeout: bool) -> int:
    output.mkdir(parents=True, exist_ok=False)
    script = Path(__file__).with_name("test_worker_pool_pending_shutdown.gd")
    project = output / "project"
    project.mkdir()
    (project / script.name).write_bytes(script.read_bytes())
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Worker shutdown isolation"\n'
        '[threading]\nworker_pool/max_threads=12\nworker_pool/low_priority_thread_ratio=0.25\n',
        encoding="utf-8",
    )
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    report = {"engine": str(engine), "engine_sha256": sha(engine),
              "script_sha256": sha(script), "expect_low_timeout": expect_low_timeout, "runs": []}
    for high in (False, True):
        for iteration in range(1, 4):
            label = f'{"high" if high else "low"}_{iteration:02d}'
            private = output / label
            private.mkdir()
            env = os.environ.copy()
            for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP"):
                folder = private / key
                folder.mkdir()
                env[key] = str(folder)
            command = [str(engine), "--headless", "--path", str(project), "--script",
                       "res://" + script.name, "--"]
            if high:
                command.append("--high-priority")
            began = time.monotonic()
            try:
                result = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=8)
                code, data = result.returncode, result.stdout
            except subprocess.TimeoutExpired as error:
                # subprocess.run terminates and waits for only its owned process.
                code, data = 124, error.stdout or b""
            (private / "engine.log").write_bytes(data)
            expected = 124 if expect_low_timeout and not high else 0
            record = {"mode": "high" if high else "low", "exit": code,
                      "seconds": time.monotonic() - began, "command": command,
                      "enqueued": b"PENDING_SHUTDOWN_ENQUEUED 40" in data,
                      "errors": b"ERROR:" in data}
            record["passed"] = code == expected and record["enqueued"] and not record["errors"]
            report["runs"].append(record)
            (output / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print(json.dumps({k: v for k, v in record.items() if k != "command"}), flush=True)
    return 0 if all(row["passed"] for row in report["runs"]) else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-low-timeout", action="store_true")
    args = parser.parse_args()
    raise SystemExit(run(args.engine.resolve(strict=True), args.output.resolve(), args.expect_low_timeout))
