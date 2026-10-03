"""Audit the reference's visible water outline; --write updates the authored trace.

Bridge/wall occlusions are explicit exclusions, not mistaken for a narrow river.
This is image analysis of this one reference, not a general map reconstruction AI.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.interpolate import PchipInterpolator
from scipy.signal import savgol_filter


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain"))
    args = parser.parse_args()
    source = Path(__file__).with_name("medieval_town_layout.json")
    spec = json.loads(source.read_text(encoding="utf-8"))
    previous = spec.get("river_previous_trace", {k: spec[k] for k in ("river_left", "river_right")})
    image = Image.open(spec["reference"]).convert("RGB")
    if image.size != (1000, 1000):
        raise ValueError("This trace requires the original 1000 x 1000 reference")
    colors = np.asarray(image).astype(int)
    rows = np.arange(1000)
    old = {}
    for side in ("left", "right"):
        points = np.array(previous["river_" + side])
        old[side] = PchipInterpolator(points[:, 1], points[:, 0])(rows)
    mask = ((colors[:, :, 2] - colors[:, :, 0] > 20)
            & (colors[:, :, 1] - colors[:, :, 0] > 8)
            & (colors[:, :, 2] - colors[:, :, 1] > -5))
    x = rows[None, :]
    mask &= (x > old["left"][:, None] - 70) & (x < old["right"][:, None] + 70)
    labels, _ = ndimage.label(mask)
    mask = (np.bincount(labels.ravel())[labels] > 350) & (labels != 0)
    valid = np.ones(1000, dtype=bool)
    for start, end in [(66, 84), (229, 264), (375, 402), (582, 612), (699, 735), (901, 918), (945, 960)]:
        valid[start:end + 1] = False
    result, report = {}, {}
    for side in ("left", "right"):
        edge = 0 if side == "left" else -1
        raw = np.array([float(np.flatnonzero(row)[edge]) if row.sum() > 7 else np.nan for row in mask])
        ok = valid & np.isfinite(raw)
        smooth = savgol_filter(PchipInterpolator(rows[ok], raw[ok])(rows), 25, 3)
        y = np.append(np.arange(0, 1000, 16), 999)
        values = np.interp(y, rows, smooth)
        points = [[round(float(values[0] - (values[1] - values[0]) / 16 * 20), 3), -20]]
        points += [[round(float(value), 3), int(z)] for value, z in zip(values, y)]
        points += [[round(float(values[-1] + (smooth[-1] - smooth[-9]) / 8 * 21), 3), 1020]]
        result["river_" + side] = points
        fitted = PchipInterpolator([p[1] for p in points], [p[0] for p in points])(rows)
        error = abs(fitted[ok] - raw[ok]) * 1.4
        report[side] = {"old_mean_error_m": float(np.mean(abs(old[side][ok] - raw[ok])) * 1.4),
                        "old_max_error_m": float(np.max(abs(old[side][ok] - raw[ok])) * 1.4),
                        "new_mean_error_m": float(error.mean()), "new_p95_error_m": float(np.quantile(error, .95)),
                        "new_max_error_m": float(error.max())}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "shore_trace_result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if args.write:
        spec["river_previous_trace"] = previous
        spec.update(result)
        source.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
