"""Install pinned MIT Godot cloud noise into the external content pack (never res://)."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("content_root", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    target = args.content_root.resolve()
    if target == project or project in target.parents:
        parser.error("content_root must be outside the project")
    manifest = json.loads(Path(__file__).with_name("cloud_assets.json").read_text())
    dest = target / "assets/weather/clouds"
    base = f"https://raw.githubusercontent.com/godotengine/godot-demo-projects/{manifest['revision']}/3d/sky_shaders/"
    payloads = {}
    for name, expected in manifest["files"].items():
        current = dest / name
        data = current.read_bytes() if current.is_file() else b""
        if hashlib.sha256(data).hexdigest() != expected:
            data = urllib.request.urlopen(base + name, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Checksum mismatch: {name}")
        payloads[name] = data
    dest.mkdir(parents=True, exist_ok=True)
    for name, data in payloads.items():
        (dest / name).write_bytes(data)
    (dest / "LICENSE-Godot.txt").write_bytes((project / "docs/licenses/Godot-clouds-MIT.txt").read_bytes())
    (dest / "source.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Verified cloud textures: {dest}")


if __name__ == "__main__":
    main()
