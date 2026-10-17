"""Summarize every OFF pair, retaining slower samples and A/A controls."""
from pathlib import Path
import json
import statistics

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/material_targeted_20261017")

def compare(samples, field, prefix=""):
    paired = [s for s in samples if s["label"].startswith(prefix + "AB_")]
    values = {v: [s[field] for s in paired if s["version"] == v] for v in ("baseline", "current")}
    aa = [s[field] for s in samples if s["label"].startswith(prefix + "AA_")]
    a, b = (statistics.median(values[v]) for v in ("baseline", "current"))
    pairs = {}
    for s in paired:
        label = s["label"].removesuffix("_baseline").removesuffix("_current")
        pairs.setdefault(label, {})[s["version"]] = s[field]
    return {"baseline_ms": a, "current_ms": b, "change_pct": (b/a - 1)*100,
            "aa_abs_delta_median_ms": statistics.median(abs(aa[i]-aa[i+1]) for i in range(0, len(aa), 2)),
            "slower_pairs": sum(p["current"] > p["baseline"] for p in pairs.values()),
            "pairs": len(pairs), "raw_baseline_ms": values["baseline"], "raw_current_ms": values["current"]}

result = {}
for name in ("cpu", "ui"):
    data = json.loads((ROOT/f"{name}.json").read_text(encoding="utf-8"))
    assert data["failures"] == 0, name
    if name == "cpu":
        result[name] = {mode: compare(data["samples"], "prepare_ms", mode+"_") for mode in ("dual", "single", "plain")}
    else:
        result[name] = {field: compare(data["samples"], field) for field in ("preview_callback_ms", "apply_callback_ms", "apply_to_ready_ms")}
    result[name+"_diagnostic"] = [s for s in data["samples"] if s["profile_enabled"]]
    result[name+"_checks"] = len(data["checks"])
(ROOT/"comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({k: ({m: {f: n for f, n in row.items() if not f.startswith("raw_")} for m, row in v.items()} if isinstance(v, dict) else v)
                  for k, v in result.items() if not k.endswith("_diagnostic")}, ensure_ascii=False, indent=2))
