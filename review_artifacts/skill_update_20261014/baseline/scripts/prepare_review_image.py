"""Prepare a WebP payload before sending a model-review image to OpenAI."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(path: Path, lossless: bool, keep_source: bool, quality: int) -> dict:
    path = path.resolve(strict=True)
    source_sha, source_bytes = sha(path), path.stat().st_size
    if path.suffix.lower() == ".webp":
        with Image.open(path) as current:
            current.load()
            if current.format != "WEBP":
                raise ValueError(f"Not a WebP payload: {path}")
        return {"path": str(path), "sha256": source_sha, "bytes": source_bytes,
                "already_webp": True}
    output = path.with_suffix(".webp")
    temporary = output.with_name(output.name + ".tmp")
    with Image.open(path) as source:
        source.load()
        if getattr(source, "n_frames", 1) != 1:
            raise ValueError("Animated images require a separate review workflow")
        rgba = source.convert("RGBA" if "A" in source.getbands() or "transparency" in source.info else "RGB")
        options = {"lossless": lossless, "quality": quality, "method": 6, "exact": True}
        for key in ("icc_profile", "exif"):
            if source.info.get(key):
                options[key] = source.info[key]
        rgba.save(temporary, format="WEBP", **options)
        with Image.open(temporary) as encoded:
            encoded.load()
            if encoded.format != "WEBP" or encoded.size != source.size:
                raise ValueError("WebP verification failed")
            if lossless and encoded.convert(rgba.mode).tobytes() != rgba.tobytes():
                raise ValueError("Lossless pixels changed")
        dimensions = list(source.size)
    temporary.replace(output)
    record = {"source": str(path), "source_sha256": source_sha,
              "source_bytes": source_bytes, "path": str(output),
              "sha256": sha(output), "bytes": output.stat().st_size,
              "dimensions": dimensions, "lossless": lossless,
              "source_retained": keep_source}
    if not keep_source:
        path.unlink()
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", type=Path, nargs="+")
    parser.add_argument("--lossless", action="store_true", help="Preserve pixels for exact QA")
    parser.add_argument("--keep-source", action="store_true", help="Retain an original still referenced by an active report")
    parser.add_argument("--quality", type=int, default=92)
    args = parser.parse_args()
    if not 0 <= args.quality <= 100:
        parser.error("quality must be between 0 and 100")
    for path in args.images:
        print(json.dumps(prepare(path, args.lossless, args.keep_source, args.quality), ensure_ascii=False))


if __name__ == "__main__":
    main()
