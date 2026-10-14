"""Bake isolated earthen-plaster relief candidates from an owned plaster scan.

This is a deterministic technical-channel bake, not a color-image repaint.
The existing 2 m albedo is copied byte-for-byte. The 1 m scan repeats twice
across that footprint. Large scan undulations, source color and source AO are
not carried into this composite material. Formal packs/maps are read-only.

Requires the project's existing Pillow, NumPy and SciPy Python environment.
GPU appearance and editor save/reopen acceptance are deliberately left pending.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
from zipfile import ZipFile

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


RUNTIME = Path("D:/code/rmmo_runtime")
DEFAULT_OUTPUT = RUNTIME / "art_sources/house_surface_relief_20261014/wall"
DEFAULT_EVIDENCE = RUNTIME / "review_artifacts/house_surface_relief_20261014/wall"
SOURCE_PREFIX = "Construction_Plaster_pjBkT0_4K_"
EXPECTED_ARCHIVE_SHA = "71be02babcc8b85bd9a924e7e6fd3df6327cdcdc13ef6bb6e63d4395065430cd"
EXPECTED_ALBEDO_SHA = "222fb2f40f8858add08b5eb1922c7e8de19220d8d91febb50316ad52448eb31b"
SOURCE_METRES = 1.0
MATERIAL_METRES = 2.0
REPETITIONS = 2
SIZE = 2048
VARIANTS = {"balanced": 1.0, "strong": 1.45}


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def periodic_component(a: np.ndarray) -> np.ndarray:
    """Remove only the smooth boundary discontinuity (periodic-plus-smooth).

    Unlike mirrored tiling, this retains the scan's stroke orientation. The
    following wrap-mode band filters remove the remaining broad height field.
    """
    h, w = a.shape
    boundary = np.zeros_like(a)
    boundary[0] = a[-1] - a[0]
    boundary[-1] = a[0] - a[-1]
    boundary[:, 0] += a[:, -1] - a[:, 0]
    boundary[:, -1] += a[:, 0] - a[:, -1]
    denominator = (2 * np.cos(2 * np.pi * np.arange(h) / h)[:, None]
                   + 2 * np.cos(2 * np.pi * np.arange(w) / w)[None, :] - 4)
    denominator[0, 0] = 1
    smooth_spectrum = np.fft.fft2(boundary) / denominator
    smooth_spectrum[0, 0] = 0
    return a - np.fft.ifft2(smooth_spectrum).real


def band(a: np.ndarray, low_sigma_m: float, high_sigma_m: float) -> np.ndarray:
    px_per_m = a.shape[0] / SOURCE_METRES
    return (gaussian_filter(a, low_sigma_m * px_per_m, mode="wrap")
            - gaussian_filter(a, high_sigma_m * px_per_m, mode="wrap"))


def bounded_band(a: np.ndarray, amplitude_m: float) -> tuple[np.ndarray, float]:
    reference = float(np.percentile(np.abs(a), 95))
    if reference <= 0:
        raise ValueError("Scan contains no usable relief in the requested band")
    return amplitude_m * np.tanh(a / reference), reference


def gradients(height: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    pixel_m = SOURCE_METRES / height.shape[0]
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2 * pixel_m)
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2 * pixel_m)
    return dx, dy


def opengl_normal(height: np.ndarray) -> np.ndarray:
    dx, dy = gradients(height)
    # Image rows run downwards; OpenGL tangent +Y runs upwards.
    normal = np.stack((-dx, dy, np.ones_like(height)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return np.round(np.clip((normal + 1) * 127.5, 0, 255)).astype(np.uint8)


def quantiles(a: np.ndarray) -> dict:
    return {str(p): float(v) for p, v in zip([0, 1, 50, 95, 99, 100],
                                           np.percentile(a, [0, 1, 50, 95, 99, 100]))}


def seams(a: np.ndarray) -> dict:
    result = {}
    for axis, name in [(0, "top_bottom"), (1, "left_right")]:
        inside = np.abs(np.diff(a.astype(np.float64), axis=axis))
        edge = np.abs(np.take(a, 0, axis=axis).astype(np.float64)
                      - np.take(a, -1, axis=axis).astype(np.float64))
        result[name] = {
            "edge_mean": float(edge.mean()),
            "interior_mean": float(inside.mean()),
            "edge_mean_to_interior_mean": float(edge.mean() / max(inside.mean(), 1e-12)),
            "edge_p95": float(np.percentile(edge, 95)),
            "interior_p95": float(np.percentile(inside, 95)),
            "edge_p95_to_interior_p95": float(np.percentile(edge, 95)
                                               / max(np.percentile(inside, 95), 1e-12)),
            "edge_max": float(edge.max()),
        }
    return result


def mip_pixels(width: int, height: int) -> int:
    total = 0
    while True:
        total += width * height
        if width == height == 1:
            return total
        width, height = max(width // 2, 1), max(height // 2, 1)


def image_record(path: Path, role: str, runtime: bool) -> dict:
    with Image.open(path) as image:
        w, h = image.size
        bands = len(image.getbands())
        byte_channels = 2 if image.mode in ("I;16", "I;16L", "I;16B") else bands
        return {
            "path": str(path.resolve()), "sha256": sha(path), "disk_bytes": path.stat().st_size,
            "dimensions": [w, h], "mode": image.mode, "role": role,
            "runtime_channel": runtime, "decoded_bytes": w * h * byte_channels,
            "gpu_rgba8_with_mips_budget_bytes": mip_pixels(w, h) * 4 if runtime else None,
            "budget_note": "Conservative RGBA8 upload estimate; not measured RSS/VRAM or compressed GPU allocation.",
        }


def validate_output_root(path: Path, allowed: Path) -> None:
    if not path.resolve().is_relative_to(allowed.resolve()):
        raise ValueError(f"Output must remain inside the isolated candidate root: {allowed}")


def build(args: argparse.Namespace) -> dict:
    pack = args.pack_root.resolve()
    output, evidence = args.output_root.resolve(), args.evidence_root.resolve()
    validate_output_root(output, DEFAULT_OUTPUT)
    validate_output_root(evidence, DEFAULT_EVIDENCE)
    profile = args.profile
    if profile == "v2":
        output, evidence = output / "v2", evidence / "v2"
    legacy_paths = sorted(p for folder in [DEFAULT_OUTPUT / "balanced", DEFAULT_OUTPUT / "strong"]
                          if folder.exists() for p in folder.rglob("*") if p.is_file()) if profile == "v2" else []
    if profile == "v2":
        legacy_paths += sorted(p for p in DEFAULT_OUTPUT.glob("*") if p.is_file())
    legacy_guard_before = {str(p): sha(p) for p in legacy_paths}
    original_dir = pack / "assets/materials/walls/earthen_plaster"
    scan_dir = pack / "assets/materials/walls/troweled_plaster"
    source_dir = pack / "sources/fab/walls/troweled_plaster"
    original_path = original_dir / "material.json"
    scan_path = scan_dir / "material.json"
    source_path = source_dir / "source.json"
    original, scan, source = read_json(original_path), read_json(scan_path), read_json(source_path)
    albedo_path = original_dir / original["material"]["texture_path"]
    archive_path = pack / source["archive"]
    guarded_paths = [original_path, albedo_path, scan_path, source_path, archive_path]
    guarded_paths += [scan_dir / scan["material"][field] for field in
                      ["texture_path", "normal_path", "roughness_path", "ao_path"]]
    guard_before = {str(p): sha(p) for p in guarded_paths}
    checks = []

    def check(name: str, passed: bool, detail=None) -> None:
        checks.append({"name": name, "pass": bool(passed), "detail": detail})
        if not passed:
            raise ValueError(f"Validation failed: {name}: {detail}")

    check("owned_source_provenance_record", bool(source.get("owned_library_verified")
          and source.get("listing_url") and source.get("license_url")))
    check("archive_sha_matches_owned_source", guard_before[str(archive_path)]
          == source["archive_sha256"] == EXPECTED_ARCHIVE_SHA)
    check("original_albedo_sha_matches_frozen_baseline", sha(albedo_path) == EXPECTED_ALBEDO_SHA)
    check("original_2m_scale_unchanged", original["material"]["tile_size"] == [2, 2])
    check("runtime_scan_maps_match_manifest", all(
        sha(scan_dir / scan["material"][field]) == source["maps"][field]["runtime_sha256"]
        for field in ["texture_path", "normal_path", "roughness_path", "ao_path"]))

    source_images, member_records = {}, {}
    with ZipFile(archive_path) as archive:
        metadata_bytes = archive.read("pjBkT0.json")
        scan_metadata = json.loads(metadata_bytes)
        for role in ["Bump", "Displacement", "Normal", "Roughness"]:
            member = SOURCE_PREFIX + role + ".jpg"
            encoded = archive.read(member)
            image = Image.open(io.BytesIO(encoded))
            image.load()
            member_records[role] = {"member": member, "sha256": hashlib.sha256(encoded).hexdigest(),
                                    "disk_bytes": len(encoded), "original_dimensions": list(image.size),
                                    "color_space": "linear technical data; no gamma transform"}
            mode = "RGB" if role == "Normal" else "L"
            image = image.convert(mode).resize((SIZE // REPETITIONS, SIZE // REPETITIONS), Image.Resampling.LANCZOS)
            source_images[role] = np.asarray(image, dtype=np.float64) / 255
    physical_size = scan_metadata.get("physicalSize")
    check("scan_physical_size_1m", physical_size == "1x1", physical_size)
    source_normal = source_images["Normal"] * 2 - 1
    pair_correlations = {}
    for role in ["Bump", "Displacement"]:
        dx, dy = gradients(source_images[role])
        pair_correlations[role] = {
            "height_dx_vs_normal_x": float(np.corrcoef(dx.ravel(), source_normal[:, :, 0].ravel())[0, 1]),
            "height_dy_image_down_vs_normal_y": float(np.corrcoef(dy.ravel(), source_normal[:, :, 1].ravel())[0, 1]),
        }
        check(role.lower() + "_paired_opengl_orientation",
              pair_correlations[role]["height_dx_vs_normal_x"] < -.7
              and pair_correlations[role]["height_dy_image_down_vs_normal_y"] > .7,
              pair_correlations[role])

    raw_height = source_images["Displacement"]
    periodic_height = periodic_component(raw_height)
    # Only measured scan detail is used. Two bounded bands keep fine grain and
    # soft trowel response without copying the damaged scan's broad height field.
    micro, micro_reference = bounded_band(band(periodic_height, .00065, .004), .00016)
    middle, middle_reference = bounded_band(band(periodic_height, .004, .025), .00028)
    base_height = micro + middle
    base_height -= base_height.mean()
    soft_middle, soft_middle_reference = bounded_band(band(periodic_height, .025, .09), .001)
    soft_middle -= soft_middle.mean()
    rough_field = periodic_component(source_images["Roughness"])
    rough_detail = band(rough_field, .00065, .012)
    rough_reference = float(np.percentile(np.abs(rough_detail), 95))
    roughness = .98 + .017 * np.tanh(rough_detail / rough_reference)
    roughness += .98 - roughness.mean()
    roughness = np.round(np.clip(roughness, .955, .998) * 255).astype(np.uint8)
    roughness_tiled = np.tile(roughness, (REPETITIONS, REPETITIONS))

    output.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    write_json(output / "original_material.json", original)
    write_json(output / "scan_source.json", source)
    write_json(output / "scan_metadata.json", scan_metadata)
    candidates = {}
    variants = {"v2": 1.45} if profile == "v2" else VARIANTS
    for name, factor in variants.items():
        folder = output if profile == "v2" else output / name
        folder.mkdir(parents=True, exist_ok=True)
        height = base_height * factor
        if profile == "v2":
            # Keep v1 strong's grain exactly the same. Only add a smoothed,
            # bounded 25--90 mm scan band; no additional high-frequency gain.
            height = height + soft_middle
        normal = opengl_normal(height)
        normal_tiled = np.tile(normal, (REPETITIONS, REPETITIONS, 1))
        Image.fromarray(normal_tiled).save(folder / "normal.png")
        Image.fromarray(roughness_tiled).save(folder / "roughness.png")
        # Height is an auditable master, not a runtime parallax/displacement slot.
        height_range_m = .00175 if profile == "v2" else .00075
        encoded_height = np.round(np.clip((height / height_range_m + 1) * 32767.5, 0, 65535)).astype(np.uint16)
        Image.fromarray(np.tile(encoded_height, (REPETITIONS, REPETITIONS))).save(folder / "height_detail_16.png")
        shutil.copy2(albedo_path, folder / "texture.png")
        material = {
            "category": original["category"],
            "usage": "隔离验收候选：保留原浅米黄抹墙色图和2m尺度；复用扫描的低幅砂粒与柔和抹痕。",
            "source": {
                "type": "composite_technical_channels", "original_albedo_sha256": EXPECTED_ALBEDO_SHA,
                "albedo_source": original["source"], "technical_source": source,
                "variant": name, "profile": profile, "height_amplitude_factor": factor,
                "not_pixel_matched_pbr": True,
                "note": "原生成色图与另一扫描的细节通道复合；不是逐像素原生扫描PBR。扫描颜色、AO、大尺度起伏不复用。",
            },
            "material": {
                "name": original["material"]["name"] + " · " + name,
                "color": original["material"]["color"], "roughness": 1.0,
                "tile_size": [2, 2], "normal_format": "opengl", "normal_strength": 1.0,
                "texture_path": "texture.png", "normal_path": "normal.png", "roughness_path": "roughness.png",
            },
        }
        write_json(folder / "material.json", material)
        decoded_normal = normal.astype(np.float64) / 127.5 - 1
        lengths = np.linalg.norm(decoded_normal, axis=-1)
        dx, dy = gradients(height)
        seam_stats = {"normal_rgb8": seams(normal), "height_m": seams(height), "roughness_r8": seams(roughness)}
        check(name + "_albedo_byte_identical", sha(folder / "texture.png") == EXPECTED_ALBEDO_SHA)
        check(name + "_technical_2x_repeat_exact", all(
            np.array_equal(a[:1024, :1024], a[y:y + 1024, x:x + 1024])
            for a in [normal_tiled, roughness_tiled]
            for y, x in [(0, 1024), (1024, 0), (1024, 1024)]))
        check(name + "_unit_normal_quantization", float(np.max(np.abs(lengths - 1))) < .008,
              {"max_unit_length_error": float(np.max(np.abs(lengths - 1)))})
        check(name + "_height_bounded", float(np.max(np.abs(height))) < height_range_m)
        check(name + "_all_technical_channels_no_boundary_outlier", all(
            s["edge_mean_to_interior_mean"] < 1.5 and s["edge_p95_to_interior_p95"] < 1.5
            for channel in seam_stats.values() for s in channel.values()), seam_stats)
        check(name + "_roughness_dry_matte", int(roughness.min()) >= 243 and int(roughness.max()) <= 255
              and abs(float(roughness.mean() / 255) - .98) < .003)
        saved_normal = np.asarray(Image.open(folder / "normal.png"))
        saved_roughness = np.asarray(Image.open(folder / "roughness.png"))
        saved_height = np.asarray(Image.open(folder / "height_detail_16.png"))
        check(name + "_saved_technical_pixels_exact", np.array_equal(saved_normal, normal_tiled)
              and np.array_equal(saved_roughness, roughness_tiled)
              and np.array_equal(saved_height, np.tile(encoded_height, (REPETITIONS, REPETITIONS))))
        records = [image_record(folder / p, role, runtime) for p, role, runtime in [
            ("texture.png", "unchanged sRGB albedo", True),
            ("normal.png", "linear OpenGL tangent normal", True),
            ("roughness.png", "linear dry-plaster roughness, red channel", True),
            ("height_detail_16.png", "linear derived height master, not connected at runtime", False)]]
        candidates[name] = {
            "material_path": str(folder / "material.json"), "material_sha256": sha(folder / "material.json"),
            "amplitude_factor": factor, "height_m_quantiles": quantiles(height),
            "slope_quantiles": quantiles(np.sqrt(dx * dx + dy * dy)),
            "normal_length_quantiles": quantiles(lengths), "roughness_quantiles": quantiles(roughness / 255),
            "roughness_mean": float(roughness.mean() / 255), "seams": seam_stats,
            "height_master_decode": {"zero_uint16": 32767.5, "metres_per_unit": height_range_m / 32767.5,
                                     "signed_range_m": [-height_range_m, height_range_m]},
            "files": records, "runtime_decoded_bytes": sum(r["decoded_bytes"] for r in records if r["runtime_channel"]),
            "runtime_rgba8_with_mips_budget_bytes": sum(r["gpu_rgba8_with_mips_budget_bytes"] for r in records if r["runtime_channel"]),
        }
    guard_after = {str(p): sha(p) for p in guarded_paths}
    check("formal_input_guard_unchanged", guard_before == guard_after)
    legacy_guard_after = {str(p): sha(p) for p in legacy_paths}
    if profile == "v2":
        check("v1_candidate_files_unchanged", legacy_guard_before == legacy_guard_after)
        check("v2_keeps_v1_strong_roughness", sha(output / "roughness.png")
              == sha(DEFAULT_OUTPUT / "strong/roughness.png"))
        check("v2_soft_middle_band_bounded", float(np.max(np.abs(soft_middle))) < .0012)
        archived_tool = output / "provenance/build_house_wall_relief_v1.py"
        check("v1_generator_archived_at_original_sha", archived_tool.exists()
              and sha(archived_tool) == read_json(DEFAULT_OUTPUT / "manifest.json")["generator"]["sha256"])
    unique_runtime = {r["sha256"]: r for v in candidates.values()
                      for r in v["files"] if r["runtime_channel"]}
    manifest = {
        "schema_version": 1, "task": "house_surface_relief_20261014/earthen_plaster", "profile": profile,
        "generator": {"path": str(Path(__file__).resolve()), "sha256": sha(Path(__file__))},
        "status": {"resource_audit": "PASS", "visual_quality": "PENDING same-camera GPU comparison",
                   "runtime_pipeline": "PENDING candidate import/save/reopen", "formal_pack_map_integration": "NOT PERFORMED"},
        "original_material": {"path": str(original_path), "sha256": sha(original_path), "data": original},
        "source_provenance": {"source_json": str(source_path), "source_json_sha256": sha(source_path),
                              "archive_path": str(archive_path), "archive_sha256": sha(archive_path),
                              "owned_record": source, "verification_scope": "Existing owned-library record and archive/map hashes verified locally; no new acquisition."},
        "source_scan_metadata": {"member": "pjBkT0.json", "sha256": hashlib.sha256(metadata_bytes).hexdigest(),
                                 "physical_size": physical_size, "metadata_path": str(output / "scan_metadata.json")},
        "source_members": member_records, "paired_height_normal_correlations": pair_correlations,
        "parameters": {
            "output_pixels": [SIZE, SIZE], "source_physical_metres": [1, 1], "material_tile_metres": [2, 2],
            "source_repetitions": [2, 2], "source_resampled_pixels": [1024, 1024], "pixels_per_metre": 1024,
            "boundary_processing": "periodic-plus-smooth; wrap-mode Gaussian filtering and central derivatives",
            "fine_band_sigma_m": [.00065, .004], "soft_trowel_band_sigma_m": [.004, .025],
            "fine_height_soft_bound_m": .00016, "soft_trowel_height_soft_bound_m": .00028,
            "fine_band_p95_reference": micro_reference, "soft_trowel_band_p95_reference": middle_reference,
            "height_interpretation": "Authored relief bounds in metres; raw scan displacement is not assumed to encode metres directly.",
            "roughness_sigma_m": [.00065, .012], "roughness_mean_target": .98,
            "roughness_variation_soft_bound": .017, "roughness_hard_range": [.955, .998],
            "no_random_noise": True, "no_source_color_or_ao": True, "normal_strength_in_material": 1.0,
        },
        "limitations": [
            "Composite generated albedo plus independently scanned fine relief; not a pixel-matched native PBR scan.",
            "Broad cracks, deep grooves and low-frequency scan displacement are suppressed; minor low-amplitude stroke shapes remain.",
            "Seam metrics are technical evidence only. Visual seams, repetition and realism still require GPU inspection.",
            "No source color, AO, metallic or runtime height/displacement channel added. No random noise introduced.",
            "The other seven wall families and all formal packs/maps are unchanged.",
        ],
        "candidates": candidates,
        "cost_summary": {
            "unique_runtime_textures_across_both_candidates": len(unique_runtime),
            "unique_runtime_decoded_bytes": sum(r["decoded_bytes"] for r in unique_runtime.values()),
            "unique_runtime_rgba8_with_mips_budget_bytes": sum(r["gpu_rgba8_with_mips_budget_bytes"] for r in unique_runtime.values()),
            "per_candidate_added_decoded_bytes_over_albedo_only": 2048 * 2048 * 4,
            "per_candidate_added_rgba8_with_mips_budget_bytes": mip_pixels(2048, 2048) * 8,
            "note": "Both candidates share byte-identical albedo and roughness; unique cost assumes content deduplication. These are decoded bytes and conservative budgets, not measured allocations.",
        },
        "checks": checks, "pass_count": sum(c["pass"] for c in checks),
        "formal_input_guard_before": guard_before, "formal_input_guard_after": guard_after,
    }
    if profile == "v2":
        sx, sy = gradients(soft_middle)
        manifest["parameters"]["v2_additional_soft_middle"] = {
            "sigma_m": [.025, .09], "height_soft_bound_m": .001,
            "p95_source_reference": soft_middle_reference,
            "height_m_quantiles": quantiles(soft_middle),
            "slope_quantiles": quantiles(np.sqrt(sx * sx + sy * sy)),
            "fine_detail_factor_unchanged_from_v1_strong": 1.45,
            "note": "Only this added smoothed band has about +/- 1 mm relief. The combined surface includes existing fine relief and is reported separately; no deep scan grooves or color shadows are copied.",
        }
        manifest["parameters"]["v2_low_frequency_slope_comparison"] = {}
        for sigma_m in [.01, .05]:
            row = {}
            for name, field in [("v1_strong", base_height * 1.45),
                                ("v2", base_height * 1.45 + soft_middle),
                                ("added_only", soft_middle)]:
                dx, dy = gradients(field)
                sigma_px = sigma_m * field.shape[0] / SOURCE_METRES
                dx = gaussian_filter(dx, sigma_px, mode="wrap")
                dy = gaussian_filter(dy, sigma_px, mode="wrap")
                row[name + "_rms"] = float(np.sqrt(np.mean(dx * dx + dy * dy)))
            manifest["parameters"]["v2_low_frequency_slope_comparison"][str(sigma_m) + "m_sigma"] = row
        manifest["legacy_v1_candidates_guard_before"] = legacy_guard_before
        manifest["legacy_v1_candidates_guard_after"] = legacy_guard_after
        archived_tool = output / "provenance/build_house_wall_relief_v1.py"
        if archived_tool.exists():
            manifest["archived_v1_generator"] = {"path": str(archived_tool), "sha256": sha(archived_tool)}
        manifest["cost_summary"]["note"] = "One v2 candidate only, no extra runtime channels or resolution over v1 strong. All figures are decoded bytes and conservative budgets, not measured allocations."
        manifest["cost_summary"].pop("unique_runtime_textures_across_both_candidates")
        manifest["cost_summary"]["unique_runtime_textures"] = len(unique_runtime)
    write_json(output / "manifest.json", manifest)
    write_json(evidence / "cpu_review.json", manifest)
    print(json.dumps({"pass_count": manifest["pass_count"], "manifest": str(output / "manifest.json"),
                      "cpu_review": str(evidence / "cpu_review.json"), "candidate_paths": {
                          k: v["material_path"] for k, v in candidates.items()}}, ensure_ascii=False, indent=2))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-root", type=Path, default=RUNTIME / "packs/default")
    parser.add_argument("--profile", choices=["v1", "v2"], default="v1",
                        help="v1 retains balanced/strong; v2 writes one new wall/v2 candidate without replacing v1")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
