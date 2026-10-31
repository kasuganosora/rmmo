"""Compare Windows compiler TLS implementations on identical work.

Keeps all six fresh-process samples (A B B A A B), compiler identities, assembly,
and raw output. This is a component experiment, never a map FPS estimate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

from godot_process_monitor import workload_snapshot


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(baseline, candidate, output, iterations):
    repo = Path(__file__).resolve().parents[1]
    output = Path(output).resolve()
    if output == repo or repo in output.parents or "review_artifacts" not in output.parts:
        raise ValueError("Use a new external review_artifacts directory")
    output.mkdir(parents=True, exist_ok=False)
    fixture = repo / "tools/fixtures"
    sources = [fixture / name for name in (
        "thread_local_identity_harness.cpp", "thread_local_identity_values.cpp")]
    identities = {str(p): sha(p) for p in sources + [fixture / "thread_local_identity_values.h"]}
    report = dict(component_only=True, source_sha256=identities, builds={}, samples=[])

    def save():
        (output / "result.json").write_text(json.dumps(report, indent=2), encoding="utf8")

    def command(args, env, log):
        other = workload_snapshot()
        if other:
            raise RuntimeError(f"Another Godot/compiler workload is active: {other}")
        result = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=180, creationflags=subprocess.CREATE_NO_WINDOW)
        (output / log).write_bytes(result.stdout)
        if result.returncode:
            raise RuntimeError(f"Command failed: {log}, code {result.returncode}")
        return result.stdout

    for label, cc in (("A", baseline), ("B", candidate)):
        cc = Path(cc).resolve()
        env = os.environ.copy()
        env["PATH"] = str(cc.parent) + os.pathsep + env["PATH"]
        executable = output / f"tls_{label}.exe"
        flags = ["-std=c++17", "-O3", "-g", "-pthread", "-static", "-static-libgcc", "-static-libstdc++"]
        args = [str(cc), *flags, *map(str, sources), "-o", str(executable)]
        version = command([str(cc), "--version"], env, f"compiler_{label}.log").decode("utf8", "replace")
        command(args, env, f"build_{label}.log")
        command([str(cc), *flags, "-S", str(sources[0]), "-o", str(output / f"harness_{label}.s")],
                env, f"assembly_{label}.log")
        command([str(cc.parent / "nm.exe"), "-C", str(executable)], env, f"symbols_{label}.txt")
        report["builds"][label] = dict(command=args, compiler_sha256=sha(cc), version=version,
                                      executable=str(executable), exe_sha256=sha(executable))
        save()

    for index, label in enumerate("ABBAAB", 1):
        env = os.environ.copy()
        cc = Path(baseline if label == "A" else candidate).resolve()
        env["PATH"] = str(cc.parent) + os.pathsep + env["PATH"]
        data = command([report["builds"][label]["executable"], str(iterations)], env,
                       f"sample_{index:02}_{label}.jsonl")
        rows = [json.loads(line) for line in data.decode("utf8").splitlines() if line.strip()]
        assert [r["threads"] for r in rows] == [1, 4, 12]
        assert all(r["identity_passed"] and r["calls_per_thread"] == iterations for r in rows)
        if report["samples"]:
            assert [(r["threads"], r["checksum"]) for r in rows] == [
                (r["threads"], r["checksum"]) for r in report["samples"][0]["rows"]]
        report["samples"].append(dict(index=index, label=label, exit=0, rows=rows))
        save()
        print("SAMPLE", index, label, [(r["threads"], r["wall_ms"]) for r in rows], flush=True)
    report["comparison"] = {}
    for count in (1, 4, 12):
        groups = {label: [r["wall_ms"] for s in report["samples"] if s["label"] == label
                          for r in s["rows"] if r["threads"] == count] for label in ("A", "B")}
        report["comparison"][str(count)] = dict(samples_ms=groups,
                                                median_ms={k: statistics.median(v) for k, v in groups.items()})
    assert all(sha(p) == digest for p, digest in identities.items())
    report["source_unchanged"] = True
    save()
    print(json.dumps(report["comparison"], indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-cxx", type=Path, required=True)
    parser.add_argument("--candidate-cxx", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=10000000)
    args = parser.parse_args()
    if not 0 < args.iterations <= 100000000:
        parser.error("iterations must be between 1 and 100000000")
    run(args.baseline_cxx, args.candidate_cxx, args.output, args.iterations)
