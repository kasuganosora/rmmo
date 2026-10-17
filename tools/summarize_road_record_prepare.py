"""Summarize every OFF pair, retaining slower samples and A/A controls."""
from pathlib import Path
import json
import statistics
import hashlib

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/road_record_prepare_completed_20261017")
checks = []


def check(ok, label):
    checks.append({"ok": bool(ok), "label": label})

def compare(samples, field, prefix=""):
    paired = [s for s in samples if s["label"].startswith(prefix + "AB_")]
    check(len(paired) == 24 and all(not s["profile_enabled"] for s in paired), prefix + field + " has exactly 12 OFF pairs")
    values = {v: [s[field] for s in paired if s["version"] == v] for v in ("baseline", "current")}
    aa = [s[field] for s in samples if s["label"].startswith(prefix + "AA_")]
    check(len(aa) == 8 and all(len(v) == 12 for v in values.values()), prefix + field + " complete A/A and A/B sample counts")
    a, b = (statistics.median(values[v]) for v in ("baseline", "current"))
    pairs = {}
    for s in paired:
        label = s["label"].removesuffix("_baseline").removesuffix("_current")
        pairs.setdefault(label, {})[s["version"]] = s[field]
    check(len(pairs) == 12 and all(set(p) == {"baseline", "current"} for p in pairs.values()), prefix + field + " every pair has both versions")
    aa_delta = statistics.median(abs(aa[i]-aa[i+1]) for i in range(0, len(aa), 2))
    tolerance = max(a * .1, aa_delta)
    check(b - a <= tolerance, prefix + field + " within predefined regression tolerance")
    return {"baseline_ms": a, "current_ms": b, "change_pct": (b/a - 1)*100,
            "aa_abs_delta_median_ms": aa_delta, "regression_tolerance_ms": tolerance,
            "slower_pairs": sum(p["current"] > p["baseline"] for p in pairs.values()),
            "pairs": len(pairs), "paired_change_ms": [p["current"]-p["baseline"] for p in pairs.values()],
            "raw_aa_ms": aa, "raw_baseline_ms": values["baseline"], "raw_current_ms": values["current"]}

result = {}
for name in ("cpu", "ui"):
    data = json.loads((ROOT/f"{name}.json").read_text(encoding="utf-8"))
    assert data["failures"] == 0, name
    check(bool(data["checks"]) and all(c["ok"] for c in data["checks"]), name + " all functional checks passed")
    if name == "cpu":
        result[name] = {mode: compare(data["samples"], "prepare_ms", mode+"_") for mode in ("dual", "single", "plain", "far", "existing")}
    else:
        result[name] = {field: compare(data["samples"], field) for field in ("preview_callback_ms", "apply_callback_ms", "apply_to_ready_ms")}
    result[name+"_diagnostic"] = [s for s in data["samples"] if s["profile_enabled"]]
    result[name+"_checks"] = len(data["checks"])
dual = result["cpu"]["dual"]
check(dual["baseline_ms"]-dual["current_ms"] > dual["aa_abs_delta_median_ms"], "primary dual PBR preparation saving exceeds observed median A/A variation")
result["checks"] = checks
result["failures"] = sum(not c["ok"] for c in checks)
result["inputs"] = {name: hashlib.sha256((ROOT/f"{name}.json").read_bytes()).hexdigest() for name in ("cpu", "ui")}
(ROOT/"comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({k: ({m: {f: n for f, n in row.items() if not f.startswith("raw_")} for m, row in v.items()} if isinstance(v, dict) else v)
                  for k, v in result.items() if k in ("cpu", "ui", "cpu_checks", "ui_checks", "failures")}, ensure_ascii=False, indent=2))
raise SystemExit(1 if result["failures"] else 0)
