"""Remove regenerable review images from two fixed RMMO review runs.

The script never removes directories, production thumbnails, source textures,
reports, or model files.  It defaults to a dry run and requires --apply.
"""

from __future__ import annotations

import argparse
from pathlib import Path


REVIEW_ROOT = Path(r"D:/code/rmmo/review_artifacts").resolve()
GUILD_ROOT = (REVIEW_ROOT / "guild_reference_recheck_20261013").resolve()
HOUSE_ROOT = (REVIEW_ROOT / "house_surface_relief_20261014").resolve()
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
KEEP = {
    (HOUSE_ROOT / "gallery/diagnostic/baseline/roofs/terracotta_plain/roof_facing_raking_close.webp").resolve(),
    (HOUSE_ROOT / "gallery/diagnostic/strong/roofs/terracotta_plain/roof_facing_raking_close.webp").resolve(),
    (HOUSE_ROOT / "gallery/diagnostic/wall_v2/baseline/walls/earthen_plaster/facade_facing_raking_close.webp").resolve(),
    (HOUSE_ROOT / "gallery/diagnostic/wall_v2/wall_v2/walls/earthen_plaster/facade_facing_raking_close.webp").resolve(),
    (HOUSE_ROOT / "gallery/candidate/wall_v2/walls/earthen_plaster/house_near.webp").resolve(),
}


def inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def collect() -> list[Path]:
    for root in (GUILD_ROOT, HOUSE_ROOT):
        if not root.is_dir() or not inside(root, REVIEW_ROOT):
            raise RuntimeError(f"Unsafe or missing review root: {root}")
    files = []
    for root in (GUILD_ROOT, HOUSE_ROOT):
        for path in root.rglob("*"):
            resolved = path.resolve()
            if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES and resolved not in KEEP:
                if not inside(resolved, root) or not inside(resolved, REVIEW_ROOT):
                    raise RuntimeError(f"Target escaped review root: {resolved}")
                files.append(resolved)
    return sorted(set(files))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    files = collect()
    size = sum(path.stat().st_size for path in files)
    if args.apply:
        for path in files:
            path.unlink()
    kept = sum(path.is_file() for path in KEEP)
    print(f"mode={'apply' if args.apply else 'dry-run'} files={len(files)} bytes={size} mib={size / 1048576:.2f} kept={kept}")


if __name__ == "__main__":
    main()
