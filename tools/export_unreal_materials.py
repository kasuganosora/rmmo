"""Export locally owned Unreal Content using a temporary, isolated UE project.

Requires an installed Unreal Editor; never loads the source project's scripts,
plugins or maps and never saves changes to its Content. Output must be new.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from run_godot_background import run_background


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--engine", type=Path, required=True, help="UE installation root")
    p.add_argument("--content", type=Path, required=True, help="Source project's Content directory")
    p.add_argument("--output", type=Path, required=True, help="New external export directory")
    p.add_argument("--asset-root", default="/Game", help="Export folder in the Unreal asset namespace")
    p.add_argument("--asset", action="append", default=[], help="Optional exact asset paths; repeatable")
    p.add_argument("--source-url", default="", help="Owned source listing, retained for provenance")
    p.add_argument("--timeout", type=int, default=900)
    args = p.parse_args()
    source, output = args.content.resolve(), args.output.resolve()
    exe = args.engine.resolve() / "Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
    if not exe.is_file() or not source.is_dir():
        p.error("UnrealEditor-Cmd.exe or source Content directory does not exist")
    repo = Path(__file__).resolve().parents[1]
    if output.exists() or output.is_relative_to(repo) or output.is_relative_to(source) or source.is_relative_to(output):
        p.error("Output must be a NEW external directory, disjoint from source Content")
    if not (args.asset_root == "/Game" or args.asset_root.startswith("/Game/")) or ".." in args.asset_root:
        p.error("Asset root must be /Game or a folder under /Game")
    for asset in args.asset:
        if not asset.startswith(args.asset_root.rstrip("/") + "/") or ".." in asset:
            p.error("Selected assets must be inside asset root")
    # Validate all source paths before creating the destination. No linked escapes.
    files = sorted(f for f in source.rglob("*") if f.is_file() and f.suffix.lower() in {".uasset", ".ubulk", ".uexp", ".uptnl"})
    if not files or any(not f.resolve().is_relative_to(source) for f in files):
        p.error("No Unreal assets found, or a source asset escapes Content")
    stage = output / "staging"
    copied = []
    for src in files:
        relative = src.relative_to(source)
        dst = stage / "Content" / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        with src.open("rb") as stream:
            sha = hashlib.file_digest(stream, "sha256").hexdigest()
        copied.append({"path": relative.as_posix(), "sha256": sha, "bytes": src.stat().st_size})
    project = stage / "MaterialExport.uproject"
    write_json(project, {"FileVersion": 3, "Plugins": [
        {"Name": "PythonScriptPlugin", "Enabled": True},
        {"Name": "EditorScriptingUtilities", "Enabled": True}]})
    config = {"output": output.as_posix(), "asset_root": args.asset_root,
              "assets": args.asset, "source_content": source.as_posix(),
              "source_url": args.source_url, "source_files": copied}
    write_json(stage / "export_request.json", config)
    backend = stage / "export_backend.py"
    shutil.copy2(Path(__file__).with_name("unreal_material_export_backend.py"), backend)
    # NullRHI commandlet, also isolated on a private desktop. It cannot steal focus.
    command = [str(exe), str(project), "-run=pythonscript", "-script=" + str(backend),
               "-unattended", "-nop4", "-nosplash", "-NullRHI", "-nosound",
               "-NoAssetRegistryCache", "-stdout", "-FullStdOutLogOutput", "-UTF8Output"]
    try:
        result = run_background(command, cwd=stage, timeout=args.timeout)
        (output / "export.log").write_bytes(result.stdout)
    except subprocess.TimeoutExpired as error:
        (output / "export.log").write_bytes((error.stdout or b"") + b"\nEXPORT TIMEOUT\n")
        return 124
    manifest = output / "manifest.json"
    if result.returncode or not manifest.is_file():
        print("Unreal export failed; inspect " + str(output / "export.log"))
        return 1
    data = json.loads(manifest.read_text(encoding="utf-8"))
    print(json.dumps({"manifest": str(manifest), "textures": len(data["textures"]),
                      "materials": len(data["materials"]), "errors": data["errors"]}, ensure_ascii=False))
    return 1 if data["errors"] or not data["textures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
