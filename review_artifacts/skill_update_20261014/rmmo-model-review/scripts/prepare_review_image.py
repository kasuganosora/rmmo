"""Encode OpenAI review screenshots as quality-90 WebP; keep pixel QA local."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

VERSION = 2
DEFAULT_QUALITY = 90


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def receipt_path(path: Path) -> Path:
    return path.with_name(path.name + ".review-image.json")


def verified_receipt(path: Path) -> dict:
    try:
        record = json.loads(receipt_path(path).read_text(encoding="utf-8"))
        if (isinstance(record, dict) and record.get("version") == VERSION
                and record.get("path") == str(path)
                and record.get("sha256") == sha(path)):
            return record
    except (OSError, ValueError):
        pass
    return {}


def same_encoding(record: dict, lossless: bool, quality: int) -> bool:
    return (record.get("format") == "WEBP"
            and record.get("lossless") is lossless
            and record.get("quality") == quality
            and record.get("method") == 6)


def prepare(path: Path, lossless: bool = False, keep_source: bool = False,
            quality: int = DEFAULT_QUALITY) -> dict:
    if not 0 <= quality <= 100:
        raise ValueError("quality must be between 0 and 100")
    path = path.resolve(strict=True)
    source_sha, source_bytes = sha(path), path.stat().st_size
    with Image.open(path) as source:
        source.load()
        if getattr(source, "n_frames", 1) != 1:
            raise ValueError("Animated images require a separate review workflow")
        if source.mode not in ("RGB", "RGBA", "L", "LA", "P"):
            raise ValueError("Only 8-bit screenshots are supported; preserve HDR/high-bit sources")
        if path.suffix.lower() == ".webp" and source.format != "WEBP":
            raise ValueError(f"Not a WebP payload: {path}")
        source_format = source.format
        rgba = source.convert("RGBA" if "A" in source.getbands() or "transparency" in source.info else "RGB")
        metadata = {key: source.info[key] for key in ("icc_profile", "exif")
                    if source.info.get(key)}
        dimensions = list(source.size)

    # The input is closed before replacing/deleting it on Windows.
    existing = verified_receipt(path)
    if source_format == "WEBP" and same_encoding(existing, lossless, quality):
        return {**existing, "already_prepared": True}
    output = path.with_suffix(".webp")
    if output == path and keep_source:
        suffix = ".lossless.webp" if lossless else ".upload.webp"
        output = path.with_name(path.stem + suffix)
    if output.exists() and output != path:
        previous = verified_receipt(output)
        if (previous.get("source") != str(path)
                or previous.get("source_sha256") != source_sha):
            raise ValueError(f"Refusing to overwrite an unrelated output: {output}")
        if same_encoding(previous, lossless, quality):
            # Reuse is a no-op for the retained original, even if the caller
            # omits --keep-source on a later invocation.
            previous["source_retained"] = True
            receipt_tmp = receipt_path(output).with_name(receipt_path(output).name + ".tmp")
            if receipt_tmp.exists():
                raise ValueError("An unfinished receipt exists; inspect it before retrying")
            receipt_tmp.write_text(json.dumps(previous, ensure_ascii=False, indent=2) + "\n",
                                   encoding="utf-8")
            receipt_tmp.replace(receipt_path(output))
            return {**previous, "already_prepared": True}

    temporary = output.with_name(output.name + ".tmp")
    record_tmp = receipt_path(output).with_name(receipt_path(output).name + ".tmp")
    backup = output.with_name(output.name + ".review-backup")
    if temporary.exists() or record_tmp.exists() or backup.exists():
        raise ValueError("An unfinished conversion exists; inspect it before retrying")
    options = {"lossless": lossless, "quality": quality, "method": 6, "exact": True}
    options.update(metadata)
    rgba.save(temporary, format="WEBP", **options)
    with Image.open(temporary) as encoded:
        encoded.load()
        if encoded.format != "WEBP" or list(encoded.size) != dimensions:
            raise ValueError("WebP verification failed")
        for key, value in metadata.items():
            actual = encoded.info.get(key, b"")
            # WebP stores TIFF EXIF without the optional JPEG/PNG Exif header.
            if key == "exif":
                actual = actual.removeprefix(b"Exif\x00\x00")
                value = value.removeprefix(b"Exif\x00\x00")
            if actual != value:
                raise ValueError("Color profile/EXIF changed")
        if lossless and encoded.convert(rgba.mode).tobytes() != rgba.tobytes():
            raise ValueError("Lossless pixels changed")

    record = {"version": VERSION, "source": str(path),
              "source_sha256": source_sha, "source_bytes": source_bytes,
              "path": str(output), "sha256": sha(temporary),
              "bytes": temporary.stat().st_size, "dimensions": dimensions,
              "format": "WEBP", "quality": quality, "lossless": lossless,
              "method": 6, "source_retained": keep_source,
              "intended_use": "local_pixel_reference" if lossless else "openai_review"}
    record_tmp.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8")
    had_output = output.exists()
    if had_output:
        with backup.open("xb") as retained:
            retained.write(output.read_bytes())
    try:
        temporary.replace(output)
        record_tmp.replace(receipt_path(output))
    except OSError as error:
        # If receipt publication fails, preserve the original WebP as well.
        # Never roll back over an unrelated concurrent write.
        if output.exists() and sha(output) == record["sha256"]:
            if had_output:
                backup.replace(output)
            else:
                output.unlink()
        if backup.exists():
            error.add_note(f"Recoverable previous image retained at {backup}")
        raise
    if had_output:
        backup.unlink()
    if not keep_source and path != output:
        path.unlink()
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", type=Path, nargs="+")
    parser.add_argument("--lossless", action="store_true",
                        help="Local pixel-QA copy only; OpenAI uploads use default lossy quality 90")
    parser.add_argument("--keep-source", action="store_true",
                        help="Retain a source needed for local comparison or report references")
    parser.add_argument("--quality", type=int, default=DEFAULT_QUALITY,
                        help="WebP encoding quality, default 90; change only for an explicit request")
    args = parser.parse_args()
    if not 0 <= args.quality <= 100:
        parser.error("quality must be between 0 and 100")
    for path in args.images:
        print(json.dumps(prepare(path, args.lossless, args.keep_source, args.quality), ensure_ascii=False))


if __name__ == "__main__":
    main()
