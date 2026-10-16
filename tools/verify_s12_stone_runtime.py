"""Compare reopened S12 material pixels and fixed gallery conditions to source.

This is a technical check only. Visual acceptance is recorded separately.
"""
import argparse
import hashlib
import io
import json
import struct
from pathlib import Path

from PIL import Image


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(report_path, baseline_path):
    report = json.loads(report_path.read_text(encoding="utf-8"))
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    source = Path(report["identity"]["path"])
    raw = source.read_bytes()
    assert raw[:4] == b"glTF"
    json_size = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_size])
    binary = raw[28 + json_size:]
    checks = []

    def check(condition, label):
        checks.append({"passed": bool(condition), "label": label})

    check(digest(source) == report["identity"]["sha256"], "exact source SHA")
    check(report["passed"] and not report["failures"], "native roundtrip checks")
    check(report["render_environment"] == baseline["render_environment"], "fixed renderer/exposure/environment")
    base_views = {row["name"]: row for row in baseline["screenshots"]}
    for row in report["screenshots"]:
        base = base_views[row["name"]]
        keys = ("eye", "aim", "light_direction_to_source", "front_N_dot_L", "ambient", "sun", "sun_color")
        check(all(row[k] == base[k] for k in keys), "fixed camera and light " + row["name"])
        path = Path(row["path"])
        receipt = json.loads(path.with_name(path.name + ".review-image.json").read_text(encoding="utf-8"))
        check(digest(path) == row["sha256"] == receipt["sha256"], "image SHA " + row["name"])
        check(receipt["quality"] == 90 and receipt["lossless"] is False and receipt["method"] == 6
              and receipt["dimensions"] == [1100, 1100], "actual quality90 full size " + row["name"])
        check(path.read_bytes()[:4] == b"RIFF" and path.read_bytes()[8:12] == b"WEBP", "WebP payload " + row["name"])

    image_hashes = {}
    for index, img in enumerate(doc["images"]):
        view = doc["bufferViews"][img["bufferView"]]
        offset = view.get("byteOffset", 0)
        data = binary[offset:offset + view["byteLength"]]
        image_hashes[index] = hashlib.sha256(Image.open(io.BytesIO(data)).convert("RGBA").tobytes()).hexdigest()

    for row in report["actual_materials"]:
        if not row["stone_surface"]:
            continue
        node = next(n for n in doc["nodes"] if n["name"] == row["node"])
        prim = doc["meshes"][node["mesh"]]["primitives"][row["surface"]]
        material = doc["materials"][prim["material"]]
        pbr = material["pbrMetallicRoughness"]
        roles = {"albedo": pbr["baseColorTexture"], "normal": material["normalTexture"],
                 "roughness_map": pbr["metallicRoughnessTexture"], "ao_map": material["occlusionTexture"]}
        for role, texture in roles.items():
            idx = doc["textures"][texture["index"]]["source"]
            check(image_hashes[idx] == row[role]["rgba_base_sha256"], row["node"] + " actual pixels " + role)
        check(abs(row["normal_scale"] - .12) < 1e-6, row["node"] + " actual normal scale .12")
        check(row["roughness_channel"] == 1 and row["ao_channel"] == 0 and row["ao_enabled"], row["node"] + " ORM channels G/R")
        check(row["metallic"] == 0 and row["albedo_color"] == "Color(1, 1, 1, 1)", row["node"] + " nonmetal white color factor")

    result = {"source_path": source.as_posix(), "source_sha256": digest(source),
              "report_path": report_path.as_posix(), "report_sha256": digest(report_path),
              "baseline_path": baseline_path.as_posix(), "baseline_sha256": digest(baseline_path),
              "checks": checks, "passed": all(c["passed"] for c in checks),
              "scope": "Technical identity, actual runtime material pixels and same gallery conditions; not a visual verdict."}
    destination = report_path.with_name("runtime_material_proof.json")
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"path": destination.as_posix(), "sha256": digest(destination),
                      "passed": result["passed"], "checks": len(checks)}))
    return result["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("baseline", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if verify(args.report, args.baseline) else 1)
