"""Compare completed white geometry runs without dumping large membership arrays."""
import argparse
import collections
import json
import math
from pathlib import Path


def frame_stats(values):
    ordered = sorted(values)
    if not ordered:
        return {}
    total = sum(ordered)
    return {"frames": len(ordered), "observed_ms": total,
            "average_fps": len(ordered) * 1000 / total if total else 0,
            "mean_ms": total / len(ordered),
            **{label: ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]
               for label, fraction in [("p50_ms", .5), ("p95_ms", .95), ("p99_ms", .99), ("max_ms", 1)]},
            **{"over_%s_ms" % threshold: sum(x > threshold for x in ordered)
               for threshold in [16.667, 33.333, 50, 100]}}


def summarize(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    phases = collections.defaultdict(list)
    for row in data["frames"]:
        phases[row["phase"]].append(row["ms"])
    profiles = [row["deferred"]["profile"] for row in data.get("queues", []) if "deferred" in row]
    last = profiles[-1] if profiles else {}
    traversal = data.get("traversal", {})
    trace = data.get("monitor", {}).get("trace", {})
    spans = {}
    for row in trace.get("stats", []):
        if row["label"] in ["stream.publish", "stream.append", "stream.retire", "stream.retire_schema", "mesh.renderer_array_capture"] or "retirement" in row["label"]:
            spans.setdefault(row["label"], []).append(row)
    return {"source": str(path), "scope": data.get("scope"), "controls": data["controls"],
            "failures": data["failures"], "entry_ms": data["entry_ms"],
            "map_unchanged": data["map_sha"] == data.get("map_sha_after"),
            "code_unchanged": data["sources"] == data.get("sources_after"),
            "white": data.get("white_render_audit"), "retirement": data.get("retirement"),
            "phases": {key: frame_stats(value) for key, value in phases.items()},
            "demand_profile_last_observation": {key: value for key, value in last.items()
                                               if key.startswith(("demand_refresh", "max_demand_refresh", "typed_full_scan"))},
            "settling": [{"phase": row["phase"], "extra_ms": row["extra_ms"], "settled": row["settled"]}
                         for row in data.get("demand_settling", [])],
            "crossings": len(traversal.get("crossings", [])),
            "removed": len(traversal.get("removed_specs", [])),
            "reloaded": len(traversal.get("reloaded_specs", [])),
            "published_events": len(traversal.get("publications", [])),
            "published_specs": sum(row["count"] for row in traversal.get("publications", [])),
            "asset_profile": traversal.get("after", {}).get("asset"),
            "native_profile": traversal.get("after", {}).get("native"),
            "native_coverage": {key: value for key, value in data.get("native_ownership_coverage", {}).items()
                                if key != "units_before_departure"},
            "trace_dropped": trace.get("dropped"), "selected_trace_spans": spans}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = {"note": "Unprofiled distribution-engine runs with the same passive monitor. Nearest-rank percentiles include every recorded phase frame; focus movement has no gameplay avatar. Inclusive spans are not summed as exclusive CPU time.",
              "runs": [summarize(path) for path in args.reports]}
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("WHITE_SCAN_SUMMARY", args.output)
