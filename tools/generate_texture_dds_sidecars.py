"""Optional offline texture packaging for map assets.

Writes additive DDS sidecars next to PNG/JPEG/WebP sources. Runtime materials
prefer these block-compressed files and skip the decoded RGBA upload. Sources
are never modified; deleting the sidecars restores the uncompressed path.
"""
import argparse
import struct
from pathlib import Path

from PIL import Image, ImageOps


def is_normal(path: Path) -> bool:
    name = path.name.lower()
    return "normal" in name or "nrm" in name or "_n." in name or "_n_" in name


def has_alpha(image: Image.Image) -> bool:
    if image.mode not in ("RGBA", "LA"):
        return False
    alpha = image.getchannel("A")
    return alpha.getextrema()[0] < 255


def save_dds(image: Image.Image, target: Path, use_alpha: bool) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    try:
        image.save(tmp, format="DDS", pixel_format="DXT5" if use_alpha else "DXT1")
        # Pillow writes a pitch value 268 for compressed DDS; Godot's reader
        # expects the DXT linear-size block count and otherwise rejects the file.
        raw = bytearray(tmp.read_bytes())
        blocks = max(1, (image.width + 3) // 4) * max(1, (image.height + 3) // 4)
        struct.pack_into("<I", raw, 20, blocks * (16 if use_alpha else 8))
        tmp.write_bytes(raw)
        tmp.replace(target)
        return True
    except Exception:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass
        return False


def process(source: Path, overwrite: bool) -> tuple[int, int, int]:
    """Return (written, skipped, failed)."""
    try:
        with Image.open(source) as image:
            image.load()
            if image.width % 4 or image.height % 4:
                # DDS DXT blocks require a complete 4x4 block grid. Godot's DDS
                # reader rejects padded/odd headers, so leave the source path.
                for suffix in (".dxt1.dds", ".dxt5.dds", ".flip.dxt1.dds", ".flip.dxt5.dds"):
                    try:
                        source.with_name(source.name + suffix).unlink()
                    except FileNotFoundError:
                        pass
                return 0, 1, 0
            rgba = image.convert("RGBA")
            normal = is_normal(source)
            alpha = normal or has_alpha(rgba)
            written = skipped = failed = 0
            targets = [(source.with_name(source.name + (".dxt5.dds" if alpha else ".dxt1.dds")), rgba, alpha)]
            if normal:
                targets.append((source.with_name(source.name + ".flip.dxt5.dds"),
                                ImageOps.flip(rgba), True))
            for target, pixels, use_alpha in targets:
                if target.exists() and not overwrite:
                    skipped += 1
                    continue
                if save_dds(pixels, target, use_alpha):
                    written += 1
                else:
                    failed += 1
            return written, skipped, failed
    except Exception:
        return 0, 0, 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    sources = sorted(p for p in args.root.rglob("*")
                     if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp"))
    if args.limit:
        sources = sources[:args.limit]
    written = skipped = failed = 0
    for index, source in enumerate(sources, 1):
        w, s, f = process(source, args.overwrite)
        written += w
        skipped += s
        failed += f
        if index % 25 == 0 or index == len(sources):
            print(f"[{index}/{len(sources)}] written={written} skipped={skipped} failed={failed}", flush=True)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
