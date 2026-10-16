"""Index raw evidence and report medians without hiding noisy/failed runs."""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RUN = Path("D:/code/rmmo_runtime/review_artifacts/road_projection_20261017")
ARCHIVE = ROOT / "review_artifacts/road_projection_20261017"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    result = {"base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "scope": "Single-call terrain projection reuse; no authored formats, mesh generator, publication or MCP schema changes.",
              "raw_root": RUN.as_posix(), "runs": {}, "sources": {}, "artifacts": {},
              "excluded_observations": {
                  "ui.json": "Initial harness passed material fields to the numeric form; update_values rejected it, so UI ran without terrain following. Two comparison failures retained. Excluded from optimization timing; corrected ui_final.json asserts every actual form value.",
                  "paired/result.json": "Initial implementation before the 4096-entry kerb cache cap. Diagnostic history only; exact measured implementation and harness copies retained.",
                  "paired_final/result.json": "First capped-source run. Large noise including unaffected control movement; retained and followed by a larger fixed 40-pair confirmation, not replaced."}}
    for name in ["profile.json", "counts.json", "counts_final.json", "differential_final.json", "ui_final.json", "district.json", "residential.json"]:
        if (RUN / name).exists():
            data = read(RUN / name)
            result["runs"][name] = {"checks": len(data.get("checks", [])), "failures": data.get("failures"), "case_count": data.get("case_count")}
    for name in ["paired/result.json", "paired_final/result.json", "confirmation/result.json"]:
        if (RUN / name).exists():
            data = read(RUN / name)
            result["runs"][name] = {"checks": len(data["checks"]), "failures": data["failures"],
                                    "fixtures": {f["name"]: f["statistics"] for f in data["fixtures"]}}
    if (RUN / "phase.json").exists():
        data = read(RUN / "phase.json"); stats = {}
        for case in data["fixtures"]:
            pairs = case["pairs"]
            stats[case["name"]] = {"median_ms": {v: statistics.median(p[v] for p in pairs) for v in ["baseline", "current"]},
                                   "paired_delta_median_ms": statistics.median(p["current"] - p["baseline"] for p in pairs),
                                   "aa_absolute_delta_median_ms": statistics.median(abs(p[1] - p[0]) for p in case["aa"]),
                                   "current_slower_pairs": sum(p["current"] > p["baseline"] for p in pairs), "pairs": len(pairs)}
        result["runs"]["phase.json"] = {"checks": len(data["checks"]), "failures": data["failures"], "fixtures": stats}
    if (RUN / "ui_final.json").exists():
        data = read(RUN / "ui_final.json"); ui = {"median_ms": {}, "aa_absolute_delta_median_ms": {}}
        for key in ["preview_callback_ms", "apply_callback_ms", "apply_to_ready_ms"]:
            ui["median_ms"][key] = {v: statistics.median(s[key] for s in data["samples"] if s["label"].startswith("AB_") and s["version"] == v) for v in ["baseline", "current"]}
            differences = []
            for i in range(3):
                pair = [s[key] for s in data["samples"] if s["label"].startswith(f"AA_{i}_")]
                differences.append(abs(pair[1] - pair[0]))
            ui["aa_absolute_delta_median_ms"][key] = statistics.median(differences)
        result["runs"]["ui_final.json"]["statistics"] = ui
    for directory in ["scripts/world3d", "scripts/world_editor"]:
        for path in sorted((ROOT / directory).rglob("*.gd")):
            result["sources"][path.relative_to(ROOT).as_posix()] = sha(path)
    for pattern in ["*road_projection*.gd", "*road_projection*.py"]:
        for path in sorted((ROOT / "tools").glob(pattern)):
            result["sources"][path.relative_to(ROOT).as_posix()] = sha(path)
    result["source_lf_sha256"] = {path: hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in result["sources"]}
    for path in sorted(RUN.rglob("*")):
        if path.is_file(): result["artifacts"][path.relative_to(RUN).as_posix()] = {"sha256": sha(path), "bytes": path.stat().st_size}
    result["frozen_baseline"] = read(ARCHIVE / "reference.json")
    for filename, expected in result["frozen_baseline"]["files"].items():
        assert sha(ARCHIVE / filename) == expected, filename
    result["archive_files"] = {path.name: sha(path) for path in sorted(ARCHIVE.iterdir()) if path.is_file() and path.name != "evidence.json" and not path.name.endswith(".uid")}
    result["retained_measured_sources"] = []
    for saved, report, source in [
        ("initial_projection_measured.gd.txt", "paired/result.json", "res://scripts/world3d/terrain_projection.gd"),
        ("paired/test_harness_measured.gd.txt", "paired/result.json", "res://tools/test_road_projection_reuse.gd"),
        ("paired_final/benchmark_measured.gd.txt", "paired_final/result.json", "res://tools/benchmark_road_projection.gd"),
        ("initial_ui_harness.gd.txt", "ui.json", "res://tools/benchmark_road_projection_ui.gd"),
        ("counts_harness_measured.gd.txt", "counts.json", "res://tools/profile_road_projection_counts.gd"),
    ]:
        expected = read(RUN / report)["script_sha256"][source]
        assert sha(RUN / saved) == expected, saved
        result["retained_measured_sources"].append({"saved": saved, "report": report, "source": source, "sha256": expected})
    (ARCHIVE / "evidence.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("Indexed", len(result["artifacts"]), "raw files and", len(result["sources"]), "source files")


if __name__ == "__main__":
    main()
