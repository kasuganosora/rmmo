"""Optional offline texture packaging for map assets.

Writes additive DDS sidecars next to PNG/JPEG/WebP sources. Runtime materials
prefer these block-compressed files and skip the decoded RGBA upload. Sources
are never modified; deleting the sidecars restores the uncompressed path.
Partial edge blocks retain their original dimensions and require an engine and
rendering backend that support them; the project's patched DDS loader does.
"""
import argparse
import hashlib
import io
import json
import struct
from pathlib import Path
import tempfile

from PIL import Image


def is_normal(path: Path) -> bool:
    name = path.name.lower()
    return "normal" in name or "nrm" in name or "_n." in name or "_n_" in name


def has_alpha(image: Image.Image) -> bool:
    if image.mode not in ("RGBA", "LA"):
        return False
    alpha = image.getchannel("A")
    return alpha.getextrema()[0] < 255


def encode_dds(image: Image.Image, use_alpha: bool, *, normal: bool = False) -> bytearray:
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
    return raw


def identity_path(target: Path) -> Path:
    return target.with_name(target.name + ".source.json")


def _stage_bytes(target: Path, data: bytes) -> Path:
    # Each producer owns its temporary file, including concurrent rebuilds.
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=target.name + ".", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        temporary.write_bytes(data)
        return temporary
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def save_dds(image: Image.Image, target: Path, use_alpha: bool, *, normal: bool = False,
             source_identity: dict | None = None, flip: bool = False) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = metadata_tmp = None
    try:
        encoded = encode_dds(image, use_alpha, normal=normal)
        tmp = _stage_bytes(target, encoded)
        if source_identity is not None:
            metadata = {"version": 1, "encoder_version": 1,
                        "source_sha256": source_identity["sha256"], "source_bytes": source_identity["bytes"],
                        "dds_sha256": hashlib.sha256(encoded).hexdigest(), "dds_bytes": len(encoded),
                        "normal": normal, "flip": flip}
            metadata_tmp = _stage_bytes(identity_path(target), (json.dumps(metadata, sort_keys=True) + "\n").encode("utf-8"))
        tmp.replace(target)
        # Two files cannot be replaced atomically together. A reader must match
        # BOTH source SHA and DDS SHA; interruption here leaves a safe miss, not
        # permission to label old/mixed DDS bytes with the new source identity.
        if metadata_tmp is not None:
            metadata_tmp.replace(identity_path(target))
        return True
    except Exception:
        return False
    finally:
        for temporary in (tmp, metadata_tmp):
            if temporary is not None:
                temporary.unlink(missing_ok=True)


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
        # The identity describes the same snapshot that is actually decoded,
        # even if the editable source pathname is replaced during encoding.
        source_bytes = source.read_bytes()
        source_identity = {"sha256": hashlib.sha256(source_bytes).hexdigest(), "bytes": len(source_bytes)}
        with Image.open(io.BytesIO(source_bytes)) as image:
            image.load()
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
                if save_dds(pixels, target, use_alpha, normal=normal,
                            source_identity=source_identity, flip=target.name.endswith(".flip.bc5.dds")):
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
                        identity_path(obsolete).unlink(missing_ok=True)
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
