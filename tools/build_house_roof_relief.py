"""Bake bounded technical roof normal candidates from the existing tile layout.

This changes normal data only. It does not paint an albedo, modify a source pack,
run a renderer, or publish a map. Existing colour and roughness bytes are copied.
The masks follow the actual four staggered courses, not an ideal square grid.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, gaussian_filter1d
from scipy.signal import find_peaks


REPO = Path(__file__).resolve().parents[1]
PACK = Path("D:/code/rmmo_runtime/packs/default/assets/materials/roofs")
OUTPUT = Path("D:/code/rmmo_runtime/art_sources/house_surface_relief_20261014/roof")
EVIDENCE = REPO / "review_artifacts/house_surface_relief_20261014/roof"
TILE_METRES = (1.0, 0.72)
PROFILES = {
    "balanced": dict(camber_m=.0045, course_lift_m=.008, lip_m=.0016,
                     lip_width_m=.0032, round_radius_m=.0011,
                     original_detail_weight=.52, original_low_weight=.22,
                     slope_limit_degrees=60.0),
    "strong": dict(camber_m=.0065, course_lift_m=.011, lip_m=.0022,
                   lip_width_m=.004, round_radius_m=.0014,
                   original_detail_weight=.52, original_low_weight=.20,
                   slope_limit_degrees=62.0),
}


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255


def save_rgb(path: Path, values: np.ndarray) -> None:
    Image.fromarray(np.rint(np.clip(values, 0, 1) * 255).astype(np.uint8)).save(path)


def periodic_valleys(profile: np.ndarray, count: int = 4) -> np.ndarray:
    """Select valleys on the circular image domain, including the x=0 seam."""
    n = len(profile)
    peaks, properties = find_peaks(-np.tile(profile, 3), distance=int(n * .18),
                                  prominence=.025)
    ranked = sorted(((float(properties["prominences"][i]), int(p - n))
                     for i, p in enumerate(peaks) if n <= p < 2 * n), reverse=True)
    if len(ranked) < count:
        raise ValueError(f"Only {len(ranked)} detectable valleys; inspect source")
    result = np.sort([p for _, p in ranked[:count]])
    gaps = np.diff(np.r_[result, result[0] + n])
    if not np.all((gaps > n * .18) & (gaps < n * .33)):
        raise ValueError(f"Unexpected course/tile boundaries: {result}, {gaps}")
    return result


def layout(albedo: np.ndarray, original: np.ndarray) -> dict:
    n, width, _ = albedo.shape
    assert n == width == 1254, "Do not silently resize the authored source"
    luminance = albedo @ np.array([.2126, .7152, .0722], np.float32)
    smooth = gaussian_filter(luminance, (1.1, 1.1), mode="wrap")
    row_centres = periodic_valleys(gaussian_filter1d(smooth.mean(1), 1.2, mode="wrap"))
    xx, yy = np.meshgrid(np.arange(n), np.arange(n))
    offsets = np.arange(-18, 19)
    row_curves = []
    for centre in row_centres:
        ys = (centre + offsets) % n
        # The negative green lip identifies the lower tile edge; the dark gap
        # and bounded position prior avoid jumping onto a crossing vertical seam.
        score = smooth[ys, :] + .04 * (original[ys, :, 1] + 1) / 2
        score += .018 * (offsets[:, None] / 8.0) ** 2
        trace = centre + offsets[np.argmin(score, axis=0)]
        row_curves.append(gaussian_filter1d(trace.astype(np.float32), 3.0, mode="wrap"))
    row_curves = np.array(row_curves)
    u = np.zeros((n, n), np.float32)
    v = np.zeros_like(u)
    course_size = np.zeros_like(u)
    tile_size = np.zeros_like(u)
    assignment = np.full((n, n), -1, np.int16)
    vertical_curves = []
    vertical_centres = []
    for row in range(4):
        end = row_curves[row].astype(np.float64) % n
        start = row_curves[(row - 1) % 4].astype(np.float64) % n
        span = (end - start) % n
        position = (yy - start[None, :]) % n
        mask = np.where(end[None, :] > start[None, :],
                        (yy >= start[None, :]) & (yy < end[None, :]),
                        (yy >= start[None, :]) | (yy < end[None, :]))
        phase = position / span[None, :]
        # Use only the central visible body to estimate vertical seams.
        middle = mask & (phase > .18) & (phase < .78)
        profile = (smooth * middle).sum(0) / np.maximum(1, middle.sum(0))
        centres = periodic_valleys(gaussian_filter1d(profile, 1.0, mode="wrap"))
        vertical_centres.append(centres)
        curves = []
        for centre in centres:
            xs = (centre + offsets) % n
            score = smooth[:, xs] + .018 * (offsets[None, :] / 8.0) ** 2
            trace = centre + offsets[np.argmin(score, axis=1)]
            curves.append(gaussian_filter1d(trace.astype(np.float32), 3.0, mode="wrap"))
        curves = np.array(curves)
        vertical_curves.append(curves)
        for tile in range(4):
            left = curves[tile].astype(np.float64) % n
            right = curves[(tile + 1) % 4].astype(np.float64) % n
            span_x = (right - left) % n
            position_x = (xx - left[:, None]) % n
            horizontal_mask = np.where(right[:, None] > left[:, None],
                (xx >= left[:, None]) & (xx < right[:, None]),
                (xx >= left[:, None]) | (xx < right[:, None]))
            selected = mask & horizontal_mask
            assert np.all(assignment[selected] == -1), "Overlapping UV partition"
            assignment[selected] = row * 4 + tile
            u[selected] = (position_x / span_x[:, None])[selected]
            v[selected] = phase[selected]
            course_size[selected] = np.broadcast_to(span[None, :], (n, n))[selected]
            tile_size[selected] = np.broadcast_to(span_x[:, None], (n, n))[selected]
    assert np.all(assignment >= 0), "Unassigned pixels in tracked layout"
    return dict(u=u, v=v, course_size=course_size, tile_size=tile_size,
                assignment=assignment, row_centres=row_centres, row_curves=row_curves,
                vertical_centres=np.array(vertical_centres),
                vertical_curves=np.array(vertical_curves))


def original_slopes(raw_normal: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Renormalise the approximate authored vectors, preserve prior 0.65 strength.

    The prior material's amplitude is baked into data. Candidate shader scale is
    1.0. +Y is OpenGL; array row-down height gradient has positive green.
    """
    lengths = np.linalg.norm(raw_normal, axis=2)
    unit = raw_normal / np.maximum(lengths[..., None], 1e-6)
    xy = unit[..., :2] * .65
    z = np.sqrt(np.maximum(1e-6, 1 - (xy * xy).sum(2)))
    slope = np.stack((-xy[..., 0] / z, xy[..., 1] / z), axis=2)
    return slope, lengths


def candidate(fields: dict, source_slope: np.ndarray, config: dict) -> tuple[np.ndarray, dict]:
    n = fields["u"].shape[0]
    u, v = fields["u"], fields["v"]
    # Per-tile camber and a gentle downslope rise, then a shallow rolled lip.
    # Physical millimetres are deliberately small; the source boundary detail
    # remains present rather than being replaced by a perfect geometric grid.
    end_distance = (1 - v) * fields["course_size"] * TILE_METRES[1] / n
    camber = config["camber_m"] * np.sin(np.pi * u) ** 2
    rise = config["course_lift_m"] * (v - .10 * np.sin(2 * np.pi * v) / (2 * np.pi))
    lip = config["lip_m"] * np.exp(-.5 * ((end_distance - config["lip_width_m"] * 1.5)
                                         / config["lip_width_m"]) ** 2)
    height = camber + rise + lip
    pixel_x, pixel_y = TILE_METRES[0] / n, TILE_METRES[1] / n
    radius = config["round_radius_m"]
    height = gaussian_filter(height, (radius / pixel_y, radius / pixel_x), mode="wrap")
    sx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / (2 * pixel_x)
    sy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / (2 * pixel_y)
    macro = np.stack((sx, sy), 2)
    filtered = gaussian_filter(source_slope, (.60, .60, 0), mode="wrap")
    low = gaussian_filter(filtered, (14, 14, 0), mode="wrap")
    slopes = macro + (filtered - low) * config["original_detail_weight"]
    slopes += low * config["original_low_weight"]
    lengths = np.linalg.norm(slopes, axis=2)
    bound = np.tan(np.deg2rad(config["slope_limit_degrees"]))
    limited = lengths > bound
    slopes /= np.maximum(1, lengths / bound)[..., None]
    normal = np.stack((-slopes[..., 0], slopes[..., 1], np.ones_like(sx)), 2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    # Course and side masks report body response independently of narrow seams.
    body = (u > .08) & (u < .92) & (v > .08) & (v < .9)
    degrees = np.degrees(np.arccos(np.clip(normal[..., 2], -1, 1)))
    return normal * .5 + .5, dict(
        angle_degrees_p10_p50_p90_p95_p99=np.percentile(degrees, [10, 50, 90, 95, 99]).tolist(),
        body_angle_degrees_p10_p50_p90_p99=np.percentile(degrees[body], [10, 50, 90, 99]).tolist(),
        angle_limited_pixel_fraction=float(limited.mean()),
        height_profile_metres_min_max=[float(height.min()), float(height.max())],
        finite=bool(np.isfinite(normal).all()),
        float_unit_normal_length_error_max=float(np.abs(np.linalg.norm(normal, axis=2) - 1).max()),
        horizontal_wrap_rgb_delta_mean=float(np.abs(normal[:, 0] - normal[:, -1]).mean()),
        vertical_wrap_rgb_delta_mean=float(np.abs(normal[0] - normal[-1]).mean()),
    )


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    sources = {}
    for family in ("terracotta_plain", "terracotta_warm"):
        folder = PACK / family
        descriptor = json.loads((folder / "material.json").read_text(encoding="utf-8"))
        assert descriptor["material"]["tile_size"] == list(TILE_METRES)
        assert descriptor["material"]["normal_format"] == "opengl"
        entries = {name: dict(path=(folder / name).as_posix(), sha256=sha(folder / name),
                             bytes=(folder / name).stat().st_size)
                   for name in ("material.json", "albedo.png", "normal.png", "roughness.png")}
        sources[family] = dict(original_descriptor=descriptor,
                               original_material=descriptor["material"], files=entries)
        backup = OUTPUT / "sources" / family
        backup.mkdir(parents=True, exist_ok=True)
        for filename in entries:
            target = backup / filename
            if target.exists():
                assert sha(target) == entries[filename]["sha256"], "Rollback collision"
            else:
                shutil.copyfile(folder / filename, target)
    for name in ("normal.png", "roughness.png"):
        assert sources["terracotta_plain"]["files"][name]["sha256"] == sources["terracotta_warm"]["files"][name]["sha256"]
    original_albedo = rgb(PACK / "terracotta_plain/albedo.png")
    raw_normal = rgb(PACK / "terracotta_plain/normal.png") * 2 - 1
    fields = layout(original_albedo, raw_normal)
    slope, source_lengths = original_slopes(raw_normal)
    # Reproducible numeric boundary evidence; no derived mask is a final material.
    np.savez_compressed(EVIDENCE / "tracked_boundaries.npz", row_curves=fields["row_curves"],
                        vertical_curves=fields["vertical_curves"], assignment=fields["assignment"])
    diagnostic = Image.fromarray(np.rint(original_albedo * 255).astype(np.uint8))
    draw = ImageDraw.Draw(diagnostic)
    n = diagnostic.width
    for curve in fields["row_curves"]:
        draw.line([(x, float(curve[x]) % n) for x in range(n)], fill=(0, 255, 190), width=2)
    for row, curves in enumerate(fields["vertical_curves"]):
        for curve in curves:
            for y in range(n):
                x = int(round(curve[y])) % n
                if fields["assignment"][y, x] // 4 == row:
                    draw.point((x, y), fill=(255, 240, 20))
    diagnostic.save(EVIDENCE / "tracked_boundaries.webp", lossless=True, method=6)
    items = []
    variants = []
    for variant, config in PROFILES.items():
        folder = OUTPUT / variant
        folder.mkdir(parents=True, exist_ok=True)
        normal, stats = candidate(fields, slope, config)
        normal_path = folder / "normal.png"
        save_rgb(normal_path, normal)
        # Uploaded diagnostic is WebP; shader data remains a lossless RGB PNG.
        Image.open(normal_path).save(EVIDENCE / f"normal_{variant}.webp", lossless=True, method=6)
        stats["normal_image_sha256"] = sha(normal_path)
        stats["normal_image_bytes"] = normal_path.stat().st_size
        quantised = rgb(normal_path) * 2 - 1
        stats["png_quantised_unit_length_error_max"] = float(np.abs(np.linalg.norm(quantised, axis=2) - 1).max())
        stats["decoded_rgb_bytes"] = n * n * 3
        stats["rgba8_full_mips_budget_bytes"] = sum(max(1, n >> i) ** 2 * 4 for i in range(n.bit_length()))
        variants.append(dict(id=variant, normal_path=normal_path.as_posix(),
                             normal_sha256=sha(normal_path), profile=config, stats=stats))
        for family in sources:
            target = folder / family
            target.mkdir(parents=True, exist_ok=True)
            for filename in ("albedo.png", "roughness.png"):
                shutil.copyfile(PACK / family / filename, target / filename)
                assert sha(target / filename) == sources[family]["files"][filename]["sha256"]
            descriptor = json.loads(json.dumps(sources[family]["original_descriptor"]))
            mat = descriptor["material"]
            mat["normal_path"] = "../normal.png"
            mat["normal_strength"] = 1.0
            descriptor["source"] = dict(type="project_normal_relief_candidate", date="2026-10-14",
                base_material_id=f"pack:default:roofs/{family}/material", variant=variant,
                source_files=sources[family]["files"],
                source_note=sources[family]["original_descriptor"]["source"],
                normal_only=True, visual_status="pending fixed-camera native GPU review")
            descriptor["review_variant"] = variant
            (target / "material.json").write_text(json.dumps(descriptor, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            items.append(dict(id=f"{family}_{variant}", family=family, variant=variant,
                material_path=(target / "material.json").as_posix(), material=mat,
                normal_path=normal_path.as_posix(), normal_sha256=sha(normal_path),
                unchanged_channels_byte_identical={name:sha(target / name) == sources[family]["files"][name]["sha256"]
                                                  for name in ("albedo.png", "roughness.png")},
                actual_channel_paths={"texture_path":(target / "albedo.png").as_posix(),
                                      "normal_path":normal_path.as_posix(),
                                      "roughness_path":(target / "roughness.png").as_posix()},
                allowed_material_changes=["normal_path", "normal_strength"],
                metadata_changes=["source", "review_variant"],
                review_status={"technical_normal_data":"passed CPU finite/unit/partition checks",
                               "original_albedo_roughness":"passed byte identity",
                               "visual":"pending real native fixed-camera comparison",
                               "runtime_pipeline":"pending real import and save/reopen",
                               "formal_integration":"not published"}))
    for family, src in sources.items():
        for filename, entry in src["files"].items():
            assert sha(PACK / family / filename) == entry["sha256"], "Source pack was modified"
    manifest = dict(schema=1, date="2026-10-14", status="CPU candidate ready; GPU/native validation pending",
        output_root=OUTPUT.as_posix(), evidence_root=EVIDENCE.as_posix(),
        script_path=Path(__file__).as_posix(), script_sha256=sha(Path(__file__)),
        size=[n,n], tile_metres=list(TILE_METRES), sources=sources,
        inferred_layout=dict(course_count=4, tiles_per_course=4, staggered=True,
            row_valleys_pixels=fields["row_centres"].tolist(),
            row_curve_ranges_pixels=[[float(x.min()),float(x.max())] for x in fields["row_curves"]],
            vertical_valleys_pixels=fields["vertical_centres"].tolist(),
            all_pixels_assigned_once=True,
            method="Circular luminance valleys, original negative-green lip evidence, bounded per-column/per-row seam tracking. Actual boundary spacing is retained; no ideal 4x4 grid warp."),
        original_normal_length_p5_p50_p95=np.percentile(source_lengths,[5,50,95]).tolist(),
        method=["Original approximate OpenGL normal vectors normalised; prior material 0.65 amplitude folded into source slopes.",
                "Observed tile UV coordinates drive small metre-valued transverse camber, downslope rise, and rounded lower lip.",
                "Periodic central derivatives divide by physical texel spacing (1/1254 m and 0.72/1254 m).",
                "Sub-texel authored noise is filtered; retained original detail preserves irregular chips/seams; slopes are bounded before unit-vector encoding.",
                "Both palette variants share candidate normals; colour, roughness, dimensions, sampler semantics and all model geometry are unchanged."],
        candidates=items, profiles=variants,
        unchanged_source_files_verified=True, formal_pack_modified=False, maps_modified=False,
        intentional_lossy_normal_change=True,
        limitations=["Shading only: no displacement, silhouettes, contact-shadow geometry or added mesh faces.",
                     "Boundary inference and millimetre profiles are project-authored design, not measured roof scanning.",
                     "CPU data validity is not visual acceptance. Native channel checks and fixed-light near/mid/far/oblique renders remain pending.",
                     "Original baked albedo contact darkening is retained, and no new dark seams or AO are painted."])
    for target in (OUTPUT / "manifest.json", EVIDENCE / "manifest.json"):
        target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest":(OUTPUT / "manifest.json").as_posix(),
                      "courses":manifest["inferred_layout"],
                      "profiles":[{"id":x["id"],"stats":x["stats"]} for x in variants]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
