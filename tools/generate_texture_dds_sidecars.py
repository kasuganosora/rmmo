"""Optional offline texture packaging for map assets.

Writes additive DDS sidecars next to PNG/JPEG/WebP sources. Runtime materials
prefer these block-compressed files and skip the decoded RGBA upload. Sources
are never modified; deleting the sidecars restores the uncompressed path.
"""
import argparse
import io
import struct
from pathlib import Path

from PIL import Image


def is_normal(path: Path) -> bool:
    name = path.name.lower()
    return "normal" in name or "nrm" in name or "_n." in name or "_n_" in name


def has_alpha(image: Image.Image) -> bool:
    if image.mode not in ("RGBA", "LA"):
        return False
    alpha = image.getchannel("A")
    return alpha.getextrema()[0] < 255


def save_dds(image: Image.Image, target: Path, use_alpha: bool, *, normal: bool = False) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    try:
        # Pillow encodes only one DDS level. Assemble a complete mip chain so
        # the compressed path keeps the runtime's mipmapped filtering contract.
        levels = []
        pixels = image.convert("RGB") if normal else image
        while True:
            encoded = io.BytesIO()
            pixels.save(encoded, format="DDS", pixel_format="BC5" if normal else ("DXT5" if use_alpha else "DXT1"))
            levels.append(encoded.getvalue())
            if pixels.size == (1, 1):
                break
            pixels = pixels.resize((max(1, pixels.width // 2), max(1, pixels.height // 2)),
                                   Image.Resampling.BOX)
        # Pillow writes a pitch value 268 for compressed DDS; Godot's reader
        # expects the DXT linear-size block count and otherwise rejects the file.
        raw = bytearray(levels[0][:128])
        if normal:
            # Pillow emits DX10 BC5_TYPELESS with a 20-byte extension. Godot
            # supports ATI2 (BC5 UNORM); retain only the common header and RG
            # block payload, never include the DX10 extension as pixel bytes.
            raw[84:88] = b"ATI2"
        blocks = max(1, (image.width + 3) // 4) * max(1, (image.height + 3) // 4)
        struct.pack_into("<I", raw, 20, blocks * (16 if use_alpha or normal else 8))
        struct.pack_into("<I", raw, 28, len(levels))
        if len(levels) > 1:
            struct.pack_into("<I", raw, 8, struct.unpack_from("<I", raw, 8)[0] | 0x20000)
            struct.pack_into("<I", raw, 108, struct.unpack_from("<I", raw, 108)[0] | 0x400008)
        for level in levels:
            raw.extend(level[148 if normal else 128:])
        tmp.write_bytes(raw)
        tmp.replace(target)
        return True
    except Exception:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass
        return False


def flip_normal_green(image: Image.Image) -> Image.Image:
    """DirectX -> OpenGL changes the tangent-space Y component, not UV rows."""
    red, green, blue, alpha = image.convert("RGBA").split()
    return Image.merge("RGBA", (red, green.point(lambda value: 255 - value), blue, alpha))


def process(source: Path, overwrite: bool, *, normal: bool | None = None) -> tuple[int, int, int]:
    """Return (written, skipped, failed)."""
    try:
        normal = is_normal(source) if normal is None else normal
        # One immutable image can serve both albedo and normal roles. Only
        # replace siblings owned by this role; non-flipped DXT files may still
        # be live color bindings even when a BC5 normal is rebuilt.
        owned_suffixes = ((".bc5.dds", ".flip.bc5.dds", ".flip.dxt1.dds", ".flip.dxt5.dds")
                          if normal else (".dxt1.dds", ".dxt5.dds"))
        with Image.open(source) as image:
            image.load()
            if image.width % 4 or image.height % 4:
                # DDS DXT blocks require a complete 4x4 block grid. Godot's DDS
                # reader rejects padded/odd headers, so leave the source path.
                for suffix in owned_suffixes if overwrite else ():
                    try:
                        source.with_name(source.name + suffix).unlink()
                    except FileNotFoundError:
                        pass
                return 0, 1, 0
            rgba = image.convert("RGBA")
            # Map-aware packaging can pass the declared material role. Content
            # SHA filenames do not preserve a "normal" suffix.
            alpha = has_alpha(rgba)
            written = skipped = failed = 0
            targets = [(source.with_name(source.name + (".bc5.dds" if normal else (".dxt5.dds" if alpha else ".dxt1.dds"))), rgba, alpha)]
            if normal:
                targets.append((source.with_name(source.name + ".flip.bc5.dds"),
                                flip_normal_green(rgba), True))
            for target, pixels, use_alpha in targets:
                if target.exists() and not overwrite:
                    skipped += 1
                    continue
                if save_dds(pixels, target, use_alpha, normal=normal):
                    written += 1
                else:
                    failed += 1
            # A successful explicit rebuild owns these generated siblings.
            # Otherwise an obsolete DXT5 wins runtime lookup over the new DXT1.
            # Do not remove obsolete siblings if a requested encode failed.
            # Each target itself is atomically replaced only after encoding.
            if overwrite and failed == 0:
                current = {target for target, _, _ in targets}
                for suffix in owned_suffixes:
                    obsolete = source.with_name(source.name + suffix)
                    if obsolete not in current:
                        obsolete.unlink(missing_ok=True)
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
