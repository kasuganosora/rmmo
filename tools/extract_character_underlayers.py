"""Package the local white lace base layer without editing its source archive.

Meshes, UVs and maps remain authored data. White colors and the opaque cup
lining are explicit runtime material variants, separate from original VAJ files.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

from art_paths import art_path
from inspect_vam_clothing import decode


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")


def main():
    package = Path("D:/Games/vamzhb/AddonPackages/maru01.UnderwearM1.2.var")
    output = art_path("characters/source_models/garment_validation_set/underlayer_lace")
    output.mkdir(parents=True, exist_ok=True)
    record = {"id": "underlayer_lace", "author": "maru01", "package": package.name,
              "package_sha256": hashlib.sha256(package.read_bytes()).hexdigest(), "items": []}
    with zipfile.ZipFile(package) as archive:
        meta = json.loads(archive.read("meta.json"))
        if meta.get("licenseType") != "CC BY":
            raise ValueError("Unexpected source license; review changed package")
        record["license"] = meta["licenseType"]
        save(output / "source_meta.json", meta)
        for number, name in enumerate(("bram06", "panty024")):
            entry = f"Custom/Clothing/Female/maru01/{name}/{name}.vab"
            item = output / f"item_{number:02d}"
            item.mkdir(exist_ok=True)
            parent = PurePosixPath(entry).parent
            files = {}
            for member in archive.namelist():
                if member.endswith("/") or PurePosixPath(member).parent != parent:
                    continue
                basename = PurePosixPath(member).name
                if ":" in basename or "\\" in basename or basename in (".", ".."):
                    raise ValueError(member)
                data = archive.read(member)
                (item / basename).write_bytes(data)
                files[basename] = {"member": member, "sha256": hashlib.sha256(data).hexdigest()}
            decoded = decode(archive.read(entry))
            save(item / "clothing_data.json", decoded)
            overrides = {}
            for material in decoded["materials"]:
                overrides[material] = {"Diffuse Color": {"h": 0, "s": .018, "v": .95}}
            # A sewn opaque lining behind the cup lace; the scalloped trim keeps
            # its authored cutout. No body faces or source garment faces removed.
            if number == 0:
                overrides["cup"]["lined_lace"] = True
            save(item / "material_overrides.json", overrides)
            manifest = {"entry": entry, "folder": item.name, "files": files,
                        "vertices": len(decoded["vertices"]), "faces": len(decoded["faces"]),
                        "variant": "white lace; opaque cup lining; source topology unchanged",
                        "slot": "UnderwearTop" if number == 0 else "UnderwearBottom",
                        "simulation": "source simEnabled=false; fitted surface attachment",
                        "cloth_enabled": False}
            save(item / "manifest.json", manifest)
            record["items"].append(manifest)
            print("PACKAGED", item.name, manifest["vertices"], "vertices")
    save(output / "manifest.json", record)
    (output / "ATTRIBUTION.txt").write_text(
        "UnderwearM1 by maru01. Local source package maru01.UnderwearM1.2.var.\n"
        "Package license: CC BY. https://creativecommons.org/licenses/by/4.0/\n"
        "RMMO adaptation: format conversion, female_base_v2 surface binding, white material "
        "variant and opaque cup lining. Original meshes, UVs and source maps retained.\n",
        encoding="utf-8", newline="\n")
    # The first source bottom is a thong and is retained only as a rejected
    # diagnostic asset. Package a full brief for the requested default instead.
    package = Path("D:/Games/vamzhb/AddonPackages/Poli5.Lingerie.9.var")
    output = art_path("characters/source_models/garment_validation_set/underlayer_briefs")
    item = output / "item_00"
    item.mkdir(parents=True, exist_ok=True)
    entry = "Custom/Clothing/Female/Poli5/Pantie0/Pantie0.vab"
    with zipfile.ZipFile(package) as archive:
        meta = json.loads(archive.read("meta.json"))
        if meta.get("licenseType") != "CC BY":
            raise ValueError("Unexpected brief source license")
        save(output / "source_meta.json", meta)
        files = {}
        for member in archive.namelist():
            if member.endswith("/") or PurePosixPath(member).parent != PurePosixPath(entry).parent:
                continue
            basename = PurePosixPath(member).name
            if ":" in basename or "\\" in basename or basename in (".", ".."):
                raise ValueError(member)
            data = archive.read(member)
            (item / basename).write_bytes(data)
            files[basename] = {"member": member, "sha256": hashlib.sha256(data).hexdigest()}
        data = decode(archive.read(entry))
        save(item / "clothing_data.json", data)
        # The original black albedo cannot be tinted white by multiplication.
        # Keep all source maps, using the neutral thread/lining colors of this
        # explicit variant; lace coverage retains its original UV and pattern.
        save(item / "material_overrides.json", {name: {
            "Diffuse Color": {"h": 0, "s": .018, "v": .95},
            "customTexture_MainTex": "", "lined_lace": True,
        } for name in data["materials"]})
        record = {"entry": entry, "package": package.name,
                  "package_sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
                  "author": "Poli5", "license": "CC BY", "files": files,
                  "vertices": len(data["vertices"]), "faces": len(data["faces"]),
                  "slot": "UnderwearBottom", "cloth_enabled": False,
                  "variant": "white lace over opaque lining; source topology unchanged"}
        save(item / "manifest.json", record)
        (output / "ATTRIBUTION.txt").write_text(
            "Lingerie / Pantie0 by Poli5. Local source: Poli5.Lingerie.9.var.\n"
            "Package license: CC BY. https://creativecommons.org/licenses/by/4.0/\n"
            "RMMO adaptation: format conversion, female_base_v2 binding, white lined lace variant.\n"
            "Original mesh, UV and source maps retained.\n", encoding="utf-8", newline="\n")
        print("PACKAGED full brief", len(data["vertices"]), "vertices")


if __name__ == "__main__":
    main()
