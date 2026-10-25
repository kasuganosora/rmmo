"""Stage a bounded DDS migration; publish only after reviewing the staged SHA set.

Never traverses the pack. The input is the explicitly reviewed map source/sibling
plan. Source images and map bytes are immutable. Backups and GPU candidates stay
outside the Godot project and outside the pack being migrated.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image
from generate_texture_dds_sidecars import flip_normal_green, save_dds


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def within(path, root):
    path = Path(path).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Path outside the selected pack: {path}")
    return path


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def stage(plan_path, output, pack, map_path):
    pack = pack.resolve(strict=True)
    map_path = within(map_path, pack)
    output = output.resolve()
    project = Path(__file__).resolve().parents[1]
    if output.is_relative_to(pack) or output.is_relative_to(project):
        raise ValueError("Stage and backups must be external to pack and Godot project")
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    if sha(map_path) != plan["map_sha256"]:
        raise ValueError("Map changed after dependency inventory")
    output.mkdir(parents=True, exist_ok=False)
    candidate = output / "candidate"
    backup = output / "backup"
    review = output / "gpu_review"
    reference = output / "references"
    for folder in (candidate, backup, review, reference):
        folder.mkdir()
    neutral = reference / "neutral.png"
    Image.new("RGB", (16, 16), (180, 180, 180)).save(neutral)
    manifest = {"schema": 1, "pack": str(pack), "map": str(map_path),
                "map_sha256": plan["map_sha256"], "sources": [], "originals": [],
                "changes": [], "retire": [], "generator_sha256": sha(Path(__file__).with_name("generate_texture_dds_sidecars.py"))}
    samples = []
    seen = set()
    for number, item in enumerate(plan["sources"]):
        source = within(item["source"], pack)
        if source in seen:
            raise ValueError(f"Duplicate source in migration plan: {source}")
        seen.add(source)
        normal = "normal_path" in item["fields"]
        if normal and item["fields"] != ["normal_path"]:
            raise ValueError("Mixed-role source requires a separate migration plan; retain its color DDS")
        manifest["sources"].append({"path": str(source), "sha256": sha(source), "fields": item["fields"]})
        selected = Path(item["selected"]).resolve()
        selected_stage = None
        selected_backup = None
        targets = set()
        with Image.open(source) as original:
            original.load()
            rgba = original.convert("RGBA")
            if rgba.width % 4 or rgba.height % 4:
                raise ValueError(f"Existing compressed source has unsupported dimensions: {source}")
            for sibling in item["existing"]:
                old = within(sibling["path"], pack)
                if not old.name.startswith(source.name + ".") or old.parent != source.parent:
                    raise ValueError("Inventory sibling is not adjacent to its source")
                retained = backup / old.relative_to(pack)
                retained.parent.mkdir(parents=True, exist_ok=True)
                digest = sha(old)
                shutil.copy2(old, retained)
                if sha(retained) != digest:
                    raise OSError("Backup bytes differ")
                manifest["originals"].append({"path": str(old), "backup": str(retained), "sha256": digest, "bytes": old.stat().st_size})
                flip = ".flip." in old.name
                if flip and not normal:
                    raise ValueError("A color-only source unexpectedly owns a flipped normal alias")
                target = source.with_name(source.name + (".flip.bc5.dds" if flip else ".bc5.dds")) if normal else old
                staged = candidate / target.relative_to(pack)
                if target not in targets:
                    targets.add(target)
                    if target != old and target.exists():
                        raise ValueError(f"Uninventoried target already exists: {target}")
                    if not save_dds(flip_normal_green(rgba) if flip else rgba, staged,
                                    target.name.endswith(".dxt5.dds"), normal=normal):
                        raise OSError(f"DDS encode failed: {target}")
                    manifest["changes"].append({"path": str(target), "staged": str(staged), "sha256": sha(staged), "bytes": staged.stat().st_size})
                if target != old:
                    manifest["retire"].append(str(old))
                if old == selected:
                    selected_stage, selected_backup = staged, retained
            if normal:
                if selected_stage is None:
                    raise ValueError("Selected normal variant was absent from the sibling plan")
                reference_normal = source
                if ".flip." in selected.name:
                    reference_normal = reference / f"normal_{number:02d}_opengl.png"
                    flip_normal_green(rgba).save(reference_normal)
                samples.append({"name": f"n{number:02d}_{source.parent.name}", "source_sha256": sha(source),
                                "variant_sha256": {"source": sha(reference_normal), "legacy": sha(selected_backup), "candidate": sha(selected_stage)},
                                "source": {"albedo": str(neutral), "normal": str(reference_normal)},
                                "legacy": {"albedo": str(neutral), "normal": str(selected_backup)},
                                "candidate": {"albedo": str(neutral), "normal": str(selected_stage)}})
        print(f"[{number + 1}/{len(plan['sources'])}] staged {source.name}", flush=True)
    if sha(map_path) != manifest["map_sha256"]:
        raise ValueError("Map changed during staging; nothing published")
    manifest["selected_review"] = str(output / "normal_review.json")
    write_json(output / "manifest.json", manifest)
    write_json(output / "normal_review.json", {"output": str(review), "samples": samples})
    print(json.dumps({"sources": len(manifest["sources"]), "backups": len(manifest["originals"]),
                      "changes": len(manifest["changes"]), "retire": len(manifest["retire"]),
                      "normal_reviews": len(samples), "staged_bytes": sum(row["bytes"] for row in manifest["changes"])}))


def atomic_copy(source, target):
    temporary = target.with_name(target.name + ".migration.tmp")
    created = False
    try:
        with temporary.open("xb") as stream:
            created = True
            stream.write(source.read_bytes())
        temporary.replace(target)
    finally:
        if created:
            temporary.unlink(missing_ok=True)


def publish(manifest_path):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pack = Path(manifest["pack"]).resolve(strict=True)
    originals = {row["path"]: row for row in manifest["originals"]}
    # This is a one-off migration ownership check, never a runtime package audit.
    for row in manifest["sources"] + manifest["originals"]:
        path = within(row["path"], pack)
        if sha(path) != row["sha256"]:
            raise ValueError(f"Source/sidecar changed after staging: {path}")
    if sha(Path(manifest["map"])) != manifest["map_sha256"]:
        raise ValueError("Map changed after staging")
    for row in manifest["originals"]:
        if sha(Path(row["backup"])) != row["sha256"]:
            raise ValueError("Invalid backup")
    for row in manifest["changes"]:
        target = within(row["path"], pack)
        if target.exists() and row["path"] not in originals:
            raise ValueError("A new target appeared after staging")
        if sha(Path(row["staged"])) != row["sha256"]:
            raise ValueError("Staged candidate changed after review")
    for path in manifest["retire"]:
        within(path, pack)
        if path not in originals:
            raise ValueError("Retirement lacks an exact backup")
    touched = []
    retired = []
    installed = []
    try:
        for row in manifest["changes"]:
            atomic_copy(Path(row["staged"]), Path(row["path"]))
            touched.append(row)
        for path in manifest["retire"]:
            Path(path).unlink()
            retired.append(path)
        for row in touched:
            target = Path(row["path"])
            actual = {"path": str(target), "sha256": sha(target), "bytes": target.stat().st_size}
            if actual["sha256"] != row["sha256"] or actual["bytes"] != row["bytes"]:
                raise OSError(f"Installed DDS differs from the reviewed candidate: {target}")
            installed.append(actual)
    except Exception:
        # Restore only files this operation changed, from the byte/SHA backup.
        for path in retired:
            atomic_copy(Path(originals[path]["backup"]), Path(path))
        for row in reversed(touched):
            path = Path(row["path"])
            if sha(path) != row["sha256"]:
                raise RuntimeError(f"Concurrent sidecar change; inspect backup before rollback: {path}")
            if row["path"] in originals:
                atomic_copy(Path(originals[row["path"]]["backup"]), path)
            else:
                path.unlink()
        raise
    result = {"manifest_sha256": sha(manifest_path), "files": len(touched), "retired": len(retired),
              "installed": installed, "installed_matches_candidates": True,
              "dds_bytes": sum(row["bytes"] for row in installed), "map_unchanged": sha(Path(manifest["map"])) == manifest["map_sha256"],
              "sources_unchanged": all(sha(Path(row["path"])) == row["sha256"] for row in manifest["sources"])}
    write_json(manifest_path.with_name("published.json"), result)
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    staging = sub.add_parser("stage")
    for name in ("plan", "output", "pack", "map"):
        staging.add_argument("--" + name, type=Path, required=True)
    publishing = sub.add_parser("publish")
    publishing.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "stage":
        stage(args.plan, args.output, args.pack, args.map)
    else:
        publish(args.manifest)


if __name__ == "__main__":
    main()
