"""Measure retained lossless AB images without replacing visual acceptance."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    source = json.loads(args.report.read_text(encoding="utf-8"))
    if source.get("failures") != 0 or source.get("phase") != "complete":
        raise ValueError("A completed, successful capture report is required")
    images = {row["local_lossless"]: row for row in source["screenshots"]}
    result = {
        "scope": "Lossless local pixel measurements, not automatic visual approval",
        "capture_report": str(args.report.resolve()),
        "capture_report_sha256": sha(args.report),
        "map_sha256": source["map_sha256"],
        "baseline": source["baseline"],
        "pairs": [],
        "visual_accepted": False,
    }
    for subject in source["subjects"]:
        for pair in subject["comparison"]:
            before, after = (Path(pair[k]) for k in ("baseline", "candidate"))
            for path in (before, after):
                record = images[str(path)] if str(path) in images else images[path.as_posix()]
                if sha(path) != record["local_lossless_sha256"]:
                    raise ValueError(f"Lossless source changed: {path}")
                if sha(Path(record["path"])) != record["sha256"]:
                    raise ValueError(f"Q90 review image changed: {record['path']}")
                if record.get("quality") != 90 or record.get("lossless") is not False:
                    raise ValueError("Review images must have actual lossy Q90 receipts")
            a = np.array(Image.open(before).convert("RGB"), dtype=np.int16)
            b = np.array(Image.open(after).convert("RGB"), dtype=np.int16)
            if a.shape != b.shape:
                raise ValueError("AB dimensions differ")
            diff = np.abs(a - b)
            maximum = diff.max(axis=2)
            ys, xs = np.nonzero(maximum)
            result["pairs"].append({
                "subject": subject["id"], "view": pair["view"],
                "width": a.shape[1], "height": a.shape[0],
                "before_sha256": sha(before), "after_sha256": sha(after),
                "exact_pixels": bool(np.array_equal(a, b)),
                "mean_absolute_channel_error_0_255": float(diff.mean()),
                "maximum_channel_error_0_255": int(diff.max()),
                "changed_pixels": int(np.count_nonzero(maximum)),
                "changed_pixel_fraction": float(np.count_nonzero(maximum) / maximum.size),
                "pixels_above_2_levels": int(np.count_nonzero(maximum > 2)),
                "pixels_above_8_levels": int(np.count_nonzero(maximum > 8)),
                "changed_bounds_xyxy_inclusive": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None,
            })
    if len(result["pairs"]) != 8:
        raise ValueError("Expected two representative subjects and four views each")
    output = args.report.with_name("pixel_comparison.json")
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"path": str(output), "sha256": sha(output), "pairs": len(result["pairs"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
