"""Install curated, already-downloaded Fab PBR maps into an external resource pack.

No network, executables, archive extraction or engine packages are required.
Archives stay in sources/fab/<category>/<slug>; runtime maps in assets/materials.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
from zipfile import ZipFile

from PIL import Image, ImageDraw, ImageFont
import numpy as np


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def install(spec, downloads, pack):
    category, slug = spec["folder"], spec["slug"]
    for value in [category, slug]:
        if not value or any(part in value for part in ["..", "/", "\\", ":"]):
            raise ValueError("Unsafe category or slug")
    archive = downloads / spec["archive"]
    if archive.parent.resolve() != downloads.resolve():
        raise ValueError("Archive must be directly inside downloads")
    output = pack / "assets/materials" / category / slug
    originals = pack / "sources/fab" / category / slug
    for path in [output, originals]:
        if not path.resolve().is_relative_to(pack.resolve()):
            raise ValueError("Output escapes pack")
        path.mkdir(parents=True, exist_ok=True)
    maps, members = {}, {}
    with ZipFile(archive) as z:
        for field, member in spec["maps"].items():
            if isinstance(member, list):
                member, channel = member
            else:
                channel = None
            if member not in z.namelist() or z.getinfo(member).file_size > 268435456:
                raise ValueError("Missing/oversized texture: " + member)
            image = Image.open(io.BytesIO(z.read(member)))
            if image.width > 8192 or image.height > 8192:
                raise ValueError("Oversized image")
            image.load()
            if channel is not None:
                image = image.convert("RGB").getchannel(channel)
            elif field in ["roughness_path", "metallic_path", "ao_path", "height_path"]:
                image = image.convert("RGB").getchannel(0)
            else:
                image = image.convert("RGB")
            image.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
            if field == "normal_path":
                # Renormalize filtered tangent normals; orientation stays in metadata.
                normals = np.asarray(image, dtype=np.float32) / 127.5 - 1.0
                length = np.linalg.norm(normals, axis=2, keepdims=True)
                normals /= np.maximum(length, 1e-6)
                image = Image.fromarray(np.clip((normals + 1.0) * 127.5, 0, 255).astype(np.uint8))
            filename = field.removesuffix("_path") + (".jpg" if field == "texture_path" else ".png")
            image.save(output / filename, **({"quality": 95, "subsampling": 0} if filename.endswith(".jpg") else {}))
            maps[field] = filename
            members[field] = {"member": member, "channel": channel, "runtime_sha256": digest(output / filename), "size": list(image.size)}
    destination = originals / archive.name
    sha = digest(archive)
    if destination.exists() and digest(destination) != sha:
        raise ValueError("Existing source archive differs; refusing overwrite")
    if not destination.exists():
        shutil.copy2(archive, destination)
    source = {"listing_url": "https://www.fab.com/listings/" + spec["listing_id"], "seller": spec["seller"],
              "title": spec["title"], "license_url": "https://www.fab.com/eula", "owned_library_verified": spec.get("owned_verified", "2026-10-02"),
              "archive": destination.relative_to(pack).as_posix(), "archive_sha256": sha,
              "ai_generated_on_listing": spec.get("ai_generated", False), "maps": members}
    value = {"category": spec["category"], "source": source, "usage": spec["usage"], "material": {
        "name": spec["name"], "color": [1, 1, 1, 1], "roughness": 1.0,
        "normal_format": spec.get("normal_format", "opengl"), "normal_strength": spec.get("normal_strength", 1.0),
        "tile_size": spec.get("tile_size", [2, 2]), **maps}}
    write_json(output / "material.json", value)
    write_json(originals / "source.json", source)
    return {"material_id": "pack:default:" + (output / "material").relative_to(pack / "assets/materials").as_posix(),
            "folder": output.relative_to(pack).as_posix(), "category": spec["category"], "name": spec["name"], "source": source,
            "usage": spec["usage"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--downloads", required=True, type=Path)
    parser.add_argument("--pack", required=True, type=Path)
    args = parser.parse_args()
    pack = args.pack.resolve()
    project = Path(__file__).resolve().parents[1]
    if pack.is_relative_to(project) or not (pack / "metadata.json").is_file():
        raise ValueError("Use an existing external resource pack")
    metadata = json.loads((pack / "metadata.json").read_text(encoding="utf-8-sig"))
    if metadata.get("id") != "default":
        raise ValueError("Curated install requires the default pack")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    rows = [install(spec, args.downloads, pack) for spec in manifest["materials"]]
    catalog_path = pack / "sources/fab/catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8")) if catalog_path.exists() else {}
    merged = {row["material_id"]: row for row in catalog.get("materials", [])}
    merged.update({row["material_id"]: row for row in rows})
    write_json(catalog_path, {"materials": list(merged.values()), "gaps": manifest.get("gaps", catalog.get("gaps", []))})
    # Actual downloaded base colors, not marketplace screenshots.
    columns, width, height = 3, 400, 440
    sheet = Image.new("RGB", (columns * width, ((len(rows) + columns - 1) // columns) * height), "#22262d")
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    font = ImageFont.truetype(str(font_path), 19) if font_path.exists() else ImageFont.load_default()
    for index, row in enumerate(rows):
        x, y = index % columns * width, index // columns * height
        folder = pack / row["folder"]
        image = Image.open(folder / "texture.jpg")
        image = image.resize((380, 380), Image.Resampling.LANCZOS)
        sheet.paste(image, (x + 10, y + 50))
        draw.text((x + 10, y + 8), row["category"] + " · " + row["name"], fill="white", font=font)
    sheet.save(pack / "sources/fab/material_contact_sheet.jpg", quality=92)
    print(json.dumps({"installed": len(rows), "pack": str(pack), "categories": sorted({r["category"] for r in rows})}, ensure_ascii=False))


if __name__ == "__main__":
    main()
