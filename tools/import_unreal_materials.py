"""Install reviewed Unreal material exports into the external default pack.

The curation manifest explicitly maps parameters to PBR channels. Shader graphs
are not guessed or baked; native parameters and source .uassets are retained.
"""
import argparse
import json
from pathlib import Path
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image
import numpy as np
from import_fab_materials import digest, write_json


def inside(root, relative):
    target = (root / relative).resolve()
    if not target.is_relative_to(root.resolve()) or target == root.resolve():
        raise ValueError("Path escapes its root: " + str(relative))
    return target


def install(export, spec, pack):
    report = json.loads((export / "manifest.json").read_text(encoding="utf-8"))
    if report["errors"]:
        raise ValueError("Do not install an export with unresolved errors")
    materials = {m["asset"]: m for m in report["materials"]}
    textures = {t["asset"]: t for t in report["textures"]}
    source_folder = inside(pack / "sources/fab", spec["source_folder"])
    source_content = Path(report["source_content"])
    originals = inside(source_content, spec["package_folder"])
    selected = []
    for row in spec["materials"]:
        output = inside(pack / "assets/materials", row["folder"])
        if output.exists():
            raise ValueError("Material already exists; use a new reviewed folder: " + str(output))
        material = materials[row["unreal_material"]]
        maps = {}
        for field, parameter in row["channels"].items():
            if field not in ("texture_path", "normal_path", "roughness_path", "metallic_path", "ao_path"):
                raise ValueError("Unsupported runtime channel")
            texture = textures[material["parameters"]["texture"][parameter]]
            path = inside(export, texture["file"])
            if not path.is_file() or digest(path) != texture["sha256"]:
                raise ValueError("Missing or changed export: " + str(path))
            maps[field] = (path, texture)
        selected.append((row, material, output, maps))
    if not originals.is_dir() or source_folder.exists():
        raise ValueError("Source assets unavailable or provenance folder already exists")
    source_folder.mkdir(parents=True)
    archive = source_folder / "unreal_source.zip"
    with ZipFile(archive, "w", ZIP_DEFLATED) as z:
        for original in sorted(originals.rglob("*")):
            if original.is_file() and original.suffix.lower() in (".uasset", ".ubulk", ".uexp", ".uptnl"):
                if not original.resolve().is_relative_to(originals.resolve()):
                    raise ValueError("Linked source escapes Content")
                z.write(original, original.relative_to(source_content).as_posix())
    shutil.copy2(export / "manifest.json", source_folder / "export_manifest.json")
    write_json(source_folder / "curation.json", spec)
    catalog_path = pack / "sources/fab/catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8")) if catalog_path.exists() else {"materials": []}
    for row, material, output, maps in selected:
        output.mkdir(parents=True)
        definition = {"name": row["name"], "color": [1, 1, 1, 1], "metallic": 0,
                      "roughness": 1, "normal_format": row["normal_format"],
                      "normal_strength": row["normal_strength"], "tile_size": row["tile_size"]}
        channels = {}
        for field, (path, texture) in maps.items():
            im = Image.open(path).convert("RGB")
            im.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
            if field == "normal_path":
                n = np.asarray(im, dtype=np.float32) / 127.5 - 1
                n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
                im = Image.fromarray(np.clip((n + 1) * 127.5, 0, 255).astype(np.uint8))
            elif field not in ("texture_path", "normal_path"):
                im = im.getchannel(0)
            filename = field.removesuffix("_path") + ".png"
            im.save(output / filename)
            definition[field] = filename
            channels[field] = {"unreal_texture": texture["asset"], "export_sha256": texture["sha256"],
                               "runtime_sha256": digest(output / filename), "size": list(im.size)}
        source = {"type": "unreal_native_export", "listing_url": report["source_url"],
                  "license_url": "https://www.fab.com/eula", "owned_library_verified": spec["owned_verified"],
                  "unreal_material": material["asset"], "archive": archive.relative_to(pack).as_posix(),
                  "archive_sha256": digest(archive), "channels": channels,
                  "adaptation": row["adaptation"], "original_parameters": material["parameters"]}
        write_json(output / "material.json", {"category": row["category"], "material": definition,
                                               "source": source, "usage": row["usage"]})
        catalog["materials"].append({"material_id": "pack:default:" + row["folder"] + "/material",
                                     "folder": output.relative_to(pack).as_posix(), "name": row["name"],
                                     "category": row["category"], "usage": row["usage"], "source": source})
    write_json(catalog_path, catalog)
    print("Installed %d reviewed Unreal materials" % len(selected))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--export", type=Path, required=True)
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--pack", type=Path, required=True)
    args = p.parse_args()
    pack = args.pack.resolve()
    if pack.is_relative_to(Path(__file__).resolve().parents[1]):
        p.error("Use an external pack")
    if json.loads((pack / "metadata.json").read_text(encoding="utf-8-sig")).get("id") != "default":
        p.error("Expected the default resource pack")
    install(args.export.resolve(), json.loads(args.manifest.read_text(encoding="utf-8")), pack)


if __name__ == "__main__":
    main()
