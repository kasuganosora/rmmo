"""Strict A/B evidence comparison for the isolated CPU road preparation benchmark.

Run only after both serial benchmark processes have finished. No Godot invocation,
map access, or fixture generation is performed here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from datetime import datetime, timezone
from pathlib import Path


WORKTREE = Path(__file__).resolve().parents[1]
EVIDENCE = WORKTREE / "review_artifacts" / "road_prepare_20261016"
CASES = (
    "junction_kerbs",
    "terrain64_local",
    "terrain64_far_complex",
    "waterway_bound_bridge",
    "frozen_stone_bridge_approaches",
)
LABELS = (
    "first_prepare", "warm_on_1", "warm_on_2", "warm_off_1", "warm_off_2", "warm_off_3",
)
FIXED_SCRIPTS = (
    "res://tools/benchmark_road_prepare.gd",
    "res://tools/road_prepare_fixture.gd",
    "res://project.godot",
    "res://review_artifacts/road_prepare_20261016/reference.gd.txt",
)
ALLOWED_PRODUCTION = {
    "res://scripts/world_editor/road_tools.gd",
    "res://scripts/world3d/terrain_projection.gd",
    "res://scripts/world3d/road_terrain_fit.gd",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def constrained_path(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_relative_to(EVIDENCE.resolve()):
        raise ValueError(f"Evidence path must remain inside this worktree: {path}")
    return path


def source_changes(before: dict, after: dict) -> tuple[list[dict], list[dict]]:
    production, other = [], []
    for path in sorted(before.keys() | after.keys()):
        if before.get(path) != after.get(path):
            target = production if path.startswith("res://scripts/") else other
            target.append({"path": path, "before_sha256": before.get(path), "after_sha256": after.get(path)})
    return production, other


def sample_statistics(samples: list[dict]) -> dict:
    result = {}
    for key, wanted in (("first", LABELS[:1]), ("warm_on", LABELS[1:3]), ("warm_off", LABELS[3:])):
        group = [sample for sample in samples if sample["label"] in wanted]
        stages = sorted({stage for sample in group for stage in sample.get("profile", {}).get("stages_ms", {})})
        result[key] = {
            "n": len(group),
            "raw_wall_ms": [sample["wall_ms"] for sample in group],
            "median_wall_ms": statistics.median(sample["wall_ms"] for sample in group) if group else None,
            "stages_median_ms": {
                stage: statistics.median(sample["profile"]["stages_ms"][stage] for sample in group)
                for stage in stages
                if all(stage in sample.get("profile", {}).get("stages_ms", {}) for sample in group)
            },
            "raw_profiles": [sample.get("profile", {}) for sample in group],
        }
    return result


def compare(before_path: Path, after_path: Path) -> dict:
    before = json.loads(before_path.read_text(encoding="utf-8-sig"))
    after = json.loads(after_path.read_text(encoding="utf-8-sig"))
    checks: list[dict] = []

    def check(condition: bool, label: str, details=None) -> None:
        checks.append({"ok": bool(condition), "label": label, "details": details})

    check(before_path != after_path, "A and B are distinct reports")
    for label, report in (("A", before), ("B", after)):
        check(report.get("failures") == 0, f"{label} benchmark has zero failures")
        check(bool(report.get("checks")) and all(item.get("ok") is True for item in report.get("checks", [])), f"{label} every recorded check passed")
        check(report.get("quick") is False, f"{label} is a full six-sample benchmark")
        check(report.get("display") == "headless", f"{label} uses the same CPU-only headless scope")
        check([item.get("name") for item in report.get("fixtures", [])] == list(CASES), f"{label} has exactly the five ordered fixtures")
        check(len(report.get("samples", [])) == 30, f"{label} has exactly thirty samples")
    for field in ("engine_executable_sha256", "engine", "display", "reference_sha256"):
        check(bool(before.get(field)) and before.get(field) == after.get(field), f"A/B {field} match")
    for field in FIXED_SCRIPTS:
        digest = before.get("script_sha256", {}).get(field)
        check(bool(digest) and digest == after.get("script_sha256", {}).get(field), f"A/B frozen benchmark dependency {field}")
    production, other = source_changes(before.get("script_sha256", {}), after.get("script_sha256", {}))
    check(all(item["path"] in ALLOWED_PRODUCTION for item in production), "Production source changes stay inside the independently frozen comparison chain", production)
    # The report verifies the bytes that were actually executed. Current copies
    # are additionally checked to detect later changes to recorded dependencies.
    engine_path = Path(after.get("engine_executable", ""))
    check(engine_path.is_file() and sha256(engine_path) == after.get("engine_executable_sha256"), "Recorded engine executable still has its measured SHA")

    comparisons = []
    for name in CASES:
        a_matches = [entry for entry in before.get("fixtures", []) if entry.get("name") == name]
        b_matches = [entry for entry in after.get("fixtures", []) if entry.get("name") == name]
        if len(a_matches) != 1 or len(b_matches) != 1:
            check(False, name + " unique fixture metadata exists")
            continue
        a, b = a_matches[0], b_matches[0]
        for field in ("records", "road_nodes", "road_edges", "terrain_cells", "input_bytes", "input_sha256", "fixture_sha256", "args", "dependencies"):
            check(field in a and field in b and a[field] == b[field], name + " identical " + field)
        files = {}
        for suffix, metadata_field in (("input", "fixture_sha256"), ("result", "full_result_sha256"), ("reference_result", "reference_result_sha256")):
            paths = (before_path.parent / f"{name}_{suffix}.bin", after_path.parent / f"{name}_{suffix}.bin")
            exists = all(path.is_file() for path in paths)
            check(exists, name + f" {suffix} binary evidence exists")
            if not exists:
                continue
            digests = [sha256(path) for path in paths]
            check(digests[0] == digests[1], name + f" complete {suffix} bytes have matching SHA256")
            check(digests[0] == a.get(metadata_field) and digests[1] == b.get(metadata_field), name + f" {suffix} files match both recorded hashes")
            files[suffix] = {"before": str(paths[0]), "after": str(paths[1]), "before_sha256": digests[0], "after_sha256": digests[1], "bytes_before": paths[0].stat().st_size, "bytes_after": paths[1].stat().st_size}
        for dependency, digest in b.get("dependencies", {}).items():
            dependency_path = Path(dependency)
            check(dependency_path.is_file() and sha256(dependency_path) == digest, name + " measured external dependency remains exact: " + dependency)
        groups = []
        for label, report, metadata in (("A", before, a), ("B", after, b)):
            samples = [item for item in report.get("samples", []) if item.get("fixture") == name]
            check([item.get("label") for item in samples] == list(LABELS), name + f" {label} exact first/ON2/OFF3 order")
            for index, sample in enumerate(samples):
                identity = name + f" {label}/{sample.get('label')}"
                check(sample.get("ok") is True, identity + " succeeded")
                check(sample.get("full_result_sha256") == metadata.get("full_result_sha256") == a.get("full_result_sha256"), identity + " entire return SHA matches A/B binary result")
                check(sample.get("input_sha256") == metadata.get("input_sha256"), identity + " input identity matches")
                check(sample.get("profiling_on") is (index < 3), identity + " expected probe state")
                wall = sample.get("wall_ms")
                check(isinstance(wall, (int, float)) and math.isfinite(wall) and wall >= 0, identity + " finite nonnegative external wall")
                profile = sample.get("profile", {})
                if index >= 3:
                    check(profile == {}, identity + " OFF profile is empty")
                else:
                    check(profile.get("ok") is True and bool(profile.get("stages_ms")), identity + " ON profile covers a successful prepare")
                    stage_sum = sum(profile.get("stages_ms", {}).values())
                    check(math.isclose(stage_sum, sample.get("stage_sum_ms", -1), rel_tol=1e-9, abs_tol=1e-6), identity + " stage sum recomputes")
            groups.append(sample_statistics(samples))
        changes = {}
        for group in ("first", "warm_on", "warm_off"):
            av, bv = groups[0][group]["median_wall_ms"], groups[1][group]["median_wall_ms"]
            changes[group] = {"before_ms": av, "after_ms": bv, "change_ms": bv - av if av is not None and bv is not None else None,
                              "improvement_percent": (1 - bv / av) * 100 if av and bv is not None else None}
        comparisons.append({"name": name, "binary_evidence": files, "before": groups[0], "after": groups[1], "wall_change": changes})
    return {
        "version": 1, "created_utc": datetime.now(timezone.utc).isoformat(),
        "before_report": str(before_path), "after_report": str(after_path),
        "before_report_sha256": sha256(before_path), "after_report_sha256": sha256(after_path),
        "comparison_script_sha256": sha256(Path(__file__)),
        "failures": sum(not item["ok"] for item in checks), "checks": checks,
        "production_source_changes": production, "nonproduction_source_changes": other, "fixtures": comparisons,
        "method": {
            "identity": "Full input and return binary SHA plus every one of six recorded sample hashes. IDs, tokens, manifests, errors and numeric types are retained.",
            "timing": "First is separate; warm ON has two samples and warm OFF three. Raw samples, wall medians and separate ON stage medians retained. No percentile, significance or isolated instrumentation-overhead claim.",
            "reference_limit": "The benchmark reference road_tools shares current helper preloads. Its equality alone cannot prove old Projection equivalence. Cross-process A/B binaries and test_road_prepare_differential's independently frozen full chain must both pass.",
            "scope": "CPU preparation only. These numbers do not measure GPU, actual editor publication, HTTP response latency, memory or character traversal.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", default=str(EVIDENCE / "before" / "result.json"))
    parser.add_argument("--after", default=str(EVIDENCE / "after" / "result.json"))
    parser.add_argument("--output", default=str(EVIDENCE / "comparison.json"))
    args = parser.parse_args()
    before, after, output = map(constrained_path, (args.before, args.after, args.output))
    if output in (before, after):
        raise ValueError("Comparison output cannot overwrite input reports")
    report = compare(before, after)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("fixture                                  warm OFF A -> B (ms)    change       warm ON A -> B (ms)")
    for item in report["fixtures"]:
        off, on = item["wall_change"]["warm_off"], item["wall_change"]["warm_on"]
        if off["before_ms"] is None or off["after_ms"] is None or on["before_ms"] is None or on["after_ms"] is None:
            print(f"{item['name']:<40} INCOMPLETE")
            continue
        print(f"{item['name']:<40} {off['before_ms']:9.3f} -> {off['after_ms']:9.3f}  {off['improvement_percent']:8.2f}%   {on['before_ms']:9.3f} -> {on['after_ms']:9.3f}")
    print(f"checks={len(report['checks'])} failures={report['failures']} report={output}")
    for item in report["checks"]:
        if not item["ok"]:
            print("FAIL", item["label"], item["details"])
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
