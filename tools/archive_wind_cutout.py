"""Verify and archive accepted wind/cutout evidence. Art stays outside res://."""
import hashlib
import json
import re
import shutil
from pathlib import Path
from PIL import Image, ImageChops

EXTERNAL = Path("D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018")
DEST = Path("review_artifacts/wind_cutout_20261018")
REPORTS = ["wind_gpu", "production_retention", "vegetation_performance", "cutout_guarded_http", "http"]
LOGS = ["wind_visual_final", "production_current_native", "vegetation_rollout_gate", "cutout_ui_final", "wind_http_final", "wind_authoring_final", "wind_covered_variants", "wind_refresh_slices", "wind_lod_optimization", "wind_material_preparer", "vegetation_scatter", "ground_batch_lifetime"]

def sha(path):
    return hashlib.file_digest(Path(path).open("rb"), "sha256").hexdigest()

def identity(path):
    path = Path(path)
    return {"path": path.as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)}

def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def put(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

def compare(a, b):
    with Image.open(a) as left, Image.open(b) as right:
        assert left.size == right.size and left.mode == right.mode
        delta = ImageChops.difference(left, right)
        raw = delta.tobytes()
        channels = len(left.getbands())
        pixels = 0 if left.tobytes() == right.tobytes() else sum(any(raw[i:i + channels]) for i in range(0, len(raw), channels))
        total = left.width * left.height
        maxima = [row[1] for row in delta.getextrema()]
        return {"source": identity(a), "candidate": identity(b), "exact_pixels": pixels == 0, "changed_pixels": pixels, "total_pixels": total, "max_channel_delta": max(maxima), "mean_channel_delta": sum(delta.tobytes()) / (total * len(left.getbands()))}

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / ".gitattributes").write_text("*.json -text whitespace=cr-at-eol\n*.log -text -diff whitespace=cr-at-eol\n", encoding="utf-8", newline="\n")
    evidence = {"scope": "isolated fixtures and retained accepted plant candidates; no formal map/catalogue edits", "reports": [], "logs": [], "media": [], "pairs": [], "source_lf_sha256": {}, "visual_review": []}
    reports = {}
    for name in REPORTS:
        path = EXTERNAL / (name + ".json")
        data = read(path)
        assert data["failures"] == 0, name
        if "checks" in data:
            assert all(row["ok"] for row in data["checks"]), name
        reports[name] = data
        shutil.copyfile(path, DEST / path.name)
        evidence["reports"].append(identity(path))
    for name in LOGS:
        path = EXTERNAL / (name + ".log")
        log = path.read_text(encoding="utf-8", errors="replace")
        assert not re.search(r"^(?:FAIL(?::| )|SCRIPT ERROR:|ERROR:)", log, re.M), name
        assert "PASS" in log or re.search(r"(?:failures=|FAILURES )0", log), name
        shutil.copyfile(path, DEST / path.name)
        evidence["logs"].append(identity(path))
    for name in REPORTS[:-1]:
        directory = Path(reports[name]["media"])
        for png in sorted(directory.glob("*.png")):
            webp = png.with_suffix(".webp")
            record = read(str(webp) + ".review-image.json")
            assert record["quality"] == 90 and record["lossless"] is False and record["format"] == "WEBP"
            assert sha(webp) == record["sha256"] and sha(png) == record["source_sha256"]
            assert Image.open(webp).size == Image.open(png).size == tuple(record["dimensions"])
            evidence["media"].append(record)
        suffix = {"wind_gpu": ("_reference", "_background"), "production_retention": ("_source", "_guarded"), "cutout_guarded_http": ("_baseline", "_candidate")}.get(name)
        if suffix:
            for a in sorted(directory.glob("*" + suffix[0] + ".png")):
                b = a.with_name(a.stem.removesuffix(suffix[0]) + suffix[1] + ".png")
                evidence["pairs"].append(compare(a, b))
        elif name == "vegetation_performance":
            evidence["pairs"].append(compare(directory / "A1.png", directory / "B1.png"))
    for row in evidence["pairs"]:
        if row["exact_pixels"]:
            continue
        assert Path(row["source"]["path"]) == Path(reports["vegetation_performance"]["media"]) / "A1.png"
        # Dense overlapping cards can change a few raster/depth tie samples.
        # This is a bounded image result, explicitly not a lossless claim.
        assert row["changed_pixels"] <= 4 and row["max_channel_delta"] <= 48 and row["mean_channel_delta"] < .0001
        row["quality_result"] = "passed_bounded_raster_difference; manually reviewed at original size"
    # Real native costs from a current production import + closed save/reopen.
    for model in reports["production_retention"]["models"]:
        assert model["native_reopened"] and model["costs"]["native_uncompressed_bytes"] > 0
        assert sha(model["source_path"]) == model["source_sha256"]
        assert sha(model["native_path"]) == model["native_sha256"]
    # The analytical leaf is a contract fixture, never a deliverable art model.
    asset = reports["cutout_guarded_http"]["asset"]
    path = asset["import"]["asset_path"]
    key = hashlib.sha256(path.replace("\\", "/").encode()).hexdigest()
    cache = Path("D:/code/rmmo_runtime/cache/world3d/compiled_assets_v1")
    manifest = read(cache / (key + ".json"))
    payload = cache / (manifest["payload_sha"] + ".scn")
    assert sha(path) == manifest["source_sha"] == asset["source_sha256"]
    assert sha(payload) == manifest["payload_sha"]
    footprint = read(cache / "footprints_v1" / (key + ".json"))
    assert hashlib.sha256(footprint["body"].encode()).hexdigest() == footprint["sha256"]
    evidence["contract_resource"] = {"source": identity(path), "master_export": identity(asset["source"] + ".godot_export.glb"), "native": identity(payload), "manifest": manifest, "footprint": json.loads(footprint["body"]), "cost_label": "resource/mip/admission budgets, not measured RSS or VRAM"}
    for folder in ["scripts", "tools"]:
        for path in sorted(Path(folder).rglob("*")):
            if path.suffix not in [".gd", ".gdshader", ".py"]:
                continue
            digest = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            evidence["source_lf_sha256"][path.as_posix()] = digest
    measurements = reports["vegetation_performance"]["measurements"]
    controls = [r for r in measurements if r["label"].startswith("A")]
    candidates = [r for r in measurements if r["label"].startswith("B")]
    evidence["performance"] = {"control_cpu_render_medians_ms": [r["cpu_total_render_ms"]["p50"] for r in controls], "candidate_cpu_render_medians_ms": [r["cpu_total_render_ms"]["p50"] for r in candidates], "control_gpu_medians_ms": [r["gpu_ms"]["p50"] for r in controls], "candidate_gpu_medians_ms": [r["gpu_ms"]["p50"] for r in candidates], "frame_cap": 120, "whole_game_fps_claim": False}
    evidence["visual_review"] = read(EXTERNAL / "visual_review.json")
    put(DEST / "evidence.json", evidence)
    print("Verified", len(evidence["pairs"]), "image pairs (" + str(sum(r["exact_pixels"] for r in evidence["pairs"])) + " exact),", len(LOGS), "accepted logs,", len(evidence["source_lf_sha256"]), "source identities")

if __name__ == "__main__":
    main()
