"""Stage missing DDS for explicitly declared map roles; never writes to the pack.

Input is the read-only output of audit_map_dds_sidecars.gd. Results stay in a
new external directory. This command does not publish or modify any map asset.
Failures preserve the incomplete output; inspect it and use a new output path.
COMPLETE marks this tool's successful write, not the authenticity of a stage;
consumers must independently check paths, links, snapshots and candidate hashes.
"""
import argparse
import ctypes
from contextlib import contextmanager
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import sys

from PIL import Image
import PIL

# Compile the exact source bytes whose digest is recorded in the manifest.
# An already-imported module can otherwise keep old functions while the file
# is replaced and a later provenance hash accidentally describes new code.
GENERATOR_PATH = Path(__file__).with_name("generate_texture_dds_sidecars.py")
GENERATOR_SOURCE = GENERATOR_PATH.read_bytes()
GENERATOR_SHA = hashlib.sha256(GENERATOR_SOURCE).hexdigest()
_generator = {"__name__": "rmmo_map_dds_generator", "__file__": str(GENERATOR_PATH)}
exec(compile(GENERATOR_SOURCE, str(GENERATOR_PATH), "exec"), _generator)
flip_normal_green = _generator["flip_normal_green"]
has_alpha = _generator["has_alpha"]
encode_dds = _generator["encode_dds"]

MAX_SOURCE_BYTES = 128 * 1024 * 1024
MAX_DIMENSION = 4096
MAX_VARIANTS = 200000
COLOR_FIELDS = {"texture_path", "roughness_path", "metallic_path", "ao_path", "height_path"}


def _digest(value):
    return hashlib.sha256(value).hexdigest()


def _link(path):
    # Godot Paths.allowed rejects links along the path, including junctions.
    return path.is_symlink() or bool(getattr(path, "is_junction", lambda: False)())


def _reject_links(path):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        if _link(part):
            raise ValueError(f"Linked path is not allowed: {part}")


def _within(value, root, *, must_exist=True):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Path must be absolute and confined: {path}")
    _reject_links(path)
    result = path.resolve(strict=must_exist)
    if not result.is_relative_to(root):
        raise ValueError(f"Path outside selected pack: {path}")
    return result


def _windows_handle_path(handle):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    get_path = kernel.GetFinalPathNameByHandleW
    get_path.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32]
    get_path.restype = ctypes.c_uint32
    size = get_path(handle, None, 0, 0)
    if not size:
        raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_unicode_buffer(size + 1)
    written = get_path(handle, buffer, len(buffer), 0)
    if not written or written >= len(buffer):
        raise ctypes.WinError(ctypes.get_last_error())
    name = buffer.value
    if name.startswith("\\\\?\\UNC\\"):
        name = "\\\\" + name[8:]
    elif name.startswith("\\\\?\\"):
        name = name[4:]
    return Path(name).resolve(strict=False)


def _opened_path(stream, path):
    if os.name == "nt":
        import msvcrt
        return _windows_handle_path(msvcrt.get_osfhandle(stream.fileno()))
    # Linux exposes the opened descriptor rather than the mutable path name.
    descriptor = Path("/proc/self/fd") / str(stream.fileno())
    if descriptor.exists():
        return descriptor.resolve(strict=True)
    raise OSError(f"Cannot verify opened file path on this platform: {path}")


@contextmanager
def _hold_output_parents(parent):
    # A path check alone cannot prevent an ancestor being replaced by a
    # junction before mkdtemp. Hold every ancestor without DELETE sharing for
    # the whole stage. Opening reparse points themselves lets us reject them.
    # Fail closed elsewhere until equivalent descriptor-relative creation is
    # implemented for that platform.
    if os.name != "nt":
        raise OSError("Safe DDS staging currently requires Windows directory handles")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create = kernel.CreateFileW
    create.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                       ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    create.restype = ctypes.c_void_p
    attributes = kernel.GetFileAttributesW
    attributes.argtypes = [ctypes.c_wchar_p]
    attributes.restype = ctypes.c_uint32
    close = kernel.CloseHandle
    close.argtypes = [ctypes.c_void_p]
    close.restype = ctypes.c_int
    handles = []
    try:
        for part in reversed((parent, *parent.parents)):
            handle = create(str(part), 0x80, 0x1 | 0x2, None, 3, 0x02000000 | 0x00200000, None)
            if handle == ctypes.c_void_p(-1).value:
                raise ctypes.WinError(ctypes.get_last_error())
            handles.append(handle)
            flags = attributes(str(part))
            if flags == 0xFFFFFFFF:
                raise ctypes.WinError(ctypes.get_last_error())
            if flags & 0x400:
                raise ValueError(f"Linked output parent is not allowed: {part}")
            if _windows_handle_path(handle) != part:
                raise ValueError(f"Output parent changed while being opened: {part}")
        yield
    finally:
        for handle in reversed(handles):
            close(handle)


def _read(path, root):
    with path.open("rb") as stream:
        # Recheck the *opened handle*, not merely its earlier pathname. A
        # concurrently replaced junction cannot redirect a read outside root.
        actual = _opened_path(stream, path)
        if not actual.is_relative_to(root):
            raise ValueError(f"Opened file escaped selected pack: {path}")
        size = os.fstat(stream.fileno()).st_size
        if size > MAX_SOURCE_BYTES:
            raise ValueError(f"Source exceeds the byte limit: {path}")
        data = stream.read(MAX_SOURCE_BYTES + 1)
        if len(data) != size:
            raise ValueError(f"Source changed while being read: {path}")
        return data


def _map_sha(path, root):
    with path.open("rb") as stream:
        if not _opened_path(stream, path).is_relative_to(root):
            raise ValueError(f"Opened map escaped selected pack: {path}")
        before = os.fstat(stream.fileno()).st_size
        digest = hashlib.sha256()
        while block := stream.read(1024 * 1024):
            digest.update(block)
        if stream.tell() != before or os.fstat(stream.fileno()).st_size != before:
            raise ValueError("Map changed while being read")
        return digest.hexdigest()


def _sidecar_suffixes(normal, flip):
    if flip:
        return (".flip.bc5.dds", ".flip.dxt5.dds", ".flip.dxt1.dds")
    return ((".bc5.dds", ".dxt5.dds", ".dxt1.dds") if normal
            else (".dxt5.dds", ".dxt1.dds"))


def _existing_header(path, root, normal):
    # Mirror compressed_texture_source.gd's bounded CPU plan, including the
    # complete mip requirement. This is a header classification, not proof of
    # source freshness or of a visually correct encoding.
    with path.open("rb") as stream:
        if not _opened_path(stream, path).is_relative_to(root):
            raise ValueError(f"Opened sidecar escaped selected pack: {path}")
        length = os.fstat(stream.fileno()).st_size
        header = stream.read(min(length, 148))
    return _header_usable(header, length, normal), (length, _digest(header))


def _header_usable(header, length, normal):
    if length < 128 or length > MAX_SOURCE_BYTES or len(header) < 128:
        return False
    u32 = lambda offset: struct.unpack_from("<I", header, offset)[0]
    if header[:4] != b"DDS " or u32(4) != 124 or u32(76) != 32:
        return False
    width, height = u32(16), u32(12)
    if not 1 <= width <= MAX_DIMENSION or not 1 <= height <= MAX_DIMENSION:
        return False
    if u32(24) > 1 or u32(112) != 0 or not (u32(80) & 4):
        return False
    fourcc = header[84:88]
    header_bytes, block = 128, 16
    if fourcc == b"DXT1":
        block = 8
    elif fourcc == b"DXT5":
        pass
    elif fourcc in (b"ATI2", b"BC5U"):
        if not normal:
            return False
    elif fourcc == b"DX10":
        if len(header) < 148 or u32(132) != 3 or u32(140) != 1 or (u32(136) & 4):
            return False
        header_bytes = 148
        dxgi = u32(128)
        if dxgi in (71, 72):
            block = 8
        elif dxgi in (77, 78):
            pass
        elif dxgi == 83:
            if not normal:
                return False
        else:
            return False
    else:
        return False
    count, expected, w, h = 1, 0, width, height
    while True:
        expected += max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * block
        if w == 1 and h == 1:
            break
        w, h = max(1, w // 2), max(1, h // 2)
        count += 1
    return max(1, u32(28)) == count and length == header_bytes + expected


def _encode(image, role, flip, destination, alpha):
    pixels = flip_normal_green(image) if flip else image
    normal = role == "normal"
    return encode_dds(pixels, alpha if not normal else False, normal=normal)


def _validate_blob(data, image, role, alpha):
    # Verify the artifact the stage will hand to an eventual publisher, without
    # decoding pixels or introducing any load-time package authentication.
    if len(data) < 128 or data[:4] != b"DDS ":
        raise ValueError("Generated DDS has no valid header")
    height, width = struct.unpack_from("<II", data, 12)
    count = struct.unpack_from("<I", data, 28)[0]
    fourcc = data[84:88]
    expected_fourcc = b"ATI2" if role == "normal" else (b"DXT5" if alpha else b"DXT1")
    if (width, height) != image.size or fourcc != expected_fourcc or count != max(width, height).bit_length():
        raise ValueError("Generated DDS dimensions, format or mip count differ")
    block = 8 if fourcc == b"DXT1" else 16
    sizes = []
    for _ in range(count):
        sizes.append(max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * block)
        width, height = max(1, width // 2), max(1, height // 2)
    if len(data) != 128 + sum(sizes) or struct.unpack_from("<I", data, 20)[0] != sizes[0]:
        raise ValueError("Generated DDS has an incomplete mip payload")


def _write_exclusive(path, expected_parent, data):
    # CREATE_NEW never follows or overwrites a pre-existing symlink/hardlink.
    # The parent directory handle is held without DELETE sharing by the caller.
    with path.open("xb") as stream:
        actual = _opened_path(stream, path)
        if actual.parent != expected_parent or actual.name != path.name:
            raise ValueError(f"Created output escaped its locked stage: {path}")
        stream.write(data)


def stage(audit_path, pack_root, output):
    if _digest(GENERATOR_PATH.read_bytes()) != GENERATOR_SHA:
        raise ValueError("Generator changed after this process loaded it")
    stage_sha = _digest(Path(__file__).read_bytes())
    pack_input = Path(pack_root).absolute()
    _reject_links(pack_input)
    root = pack_input.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Selected pack root is not a directory")
    out_input = Path(output).absolute()
    _reject_links(out_input)
    out = out_input.resolve(strict=False)
    project = Path(__file__).resolve().parents[1]
    if out.is_relative_to(root) or out.is_relative_to(project):
        raise ValueError("Stage output must be outside both pack and project")
    if out.exists():
        raise FileExistsError(out)
    parent = out.parent.resolve(strict=True)
    _reject_links(parent)
    raw_audit = Path(audit_path).read_bytes()
    audit = json.loads(raw_audit)
    if audit.get("errors") != [] or audit.get("map_unchanged") is not True:
        raise ValueError("Audit is incomplete or reported errors")
    variants = audit.get("texture_variants")
    if not isinstance(variants, list) or len(variants) > MAX_VARIANTS:
        raise ValueError("Invalid or oversized texture variant inventory")
    map_file = _within(audit.get("map", ""), root)
    if not map_file.is_file() or _map_sha(map_file, root) != audit.get("map_sha256"):
        raise ValueError("Map changed since the dependency inventory")

    requests = {}
    for row in variants:
        if not isinstance(row, dict):
            raise ValueError("Invalid variant row")
        normal, flip, fields = row.get("normal_role"), row.get("flip_normal_green"), row.get("fields")
        if type(normal) is not bool or type(flip) is not bool or (flip and not normal):
            raise ValueError("Invalid declared texture role or flip")
        if not isinstance(fields, list) or not fields or not all(isinstance(x, str) for x in fields):
            raise ValueError("Missing declared material fields")
        if (normal and set(fields) != {"normal_path"}) or (not normal and not set(fields).issubset(COLOR_FIELDS)):
            raise ValueError("Material fields disagree with the declared role")
        source = _within(row.get("source", ""), root)
        if not source.is_file() or source.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
            raise ValueError(f"Unsupported source: {source}")
        key = (source, normal, flip)
        requests[key] = key

    with _hold_output_parents(parent):
        # The handle check protects this decision for all following writes.
        if parent.resolve(strict=True) != parent:
            raise ValueError("Output parent changed before staging")
        return _stage_locked(root, out, parent, requests, map_file, audit, raw_audit, stage_sha)


def _stage_locked(root, out, parent, requests, map_file, audit, raw_audit, stage_sha):
    # The requested, non-existing directory is the stage. Its zero-byte
    # COMPLETE marker is created only after the full manifest has been written.
    out.mkdir()
    # Preserve incomplete output on errors: pathnames can be replaced after
    # creation, so deleting by name could remove someone else's file.
    with _hold_output_parents(out):
        blob_dir = out / "blobs"
        blob_dir.mkdir()
        with _hold_output_parents(blob_dir):
            created = []
            return _stage_into(root, out, blob_dir, requests, map_file, audit, raw_audit, stage_sha, created)


def _stage_into(root, out, blob_dir, requests, map_file, audit, raw_audit, stage_sha, created):
        source_snapshots = {}
        targets, skipped, observed, selected_headers = [], [], {}, {}
        missing = []
        for source, normal, flip in requests.values():
            existing = []
            for suffix in _sidecar_suffixes(normal, flip):
                sibling = Path(str(source) + suffix)
                _within(sibling, root, must_exist=False)
                if sibling.exists():
                    if not sibling.is_file():
                        raise ValueError(f"Sidecar is not a file: {sibling}")
                    existing.append(sibling.relative_to(root).as_posix())
            observed[(source, normal, flip)] = tuple(existing)
            role = "normal" if normal else "color"
            source_rel = source.relative_to(root).as_posix()
            if existing:
                selected = root / existing[0]
                selected_usable, signature = _existing_header(selected, root, normal)
                selected_headers[(source, normal, flip)] = signature
                skipped.append({"source": source_rel, "role": role, "flip": flip,
                                "existing": existing, "selected": existing[0],
                                "selection_status": "header_usable" if selected_usable else "selected_unusable",
                                "freshness_verified": False})
            else:
                missing.append((source, role, flip))

        # Only missing targets require decoding. Hash one source at a time and
        # group byte-identical sources; the encoder holds at most one RGBA image
        # at a time rather than retaining every decoded picture in the map.
        by_digest = {}
        for source, role, flip in missing:
            if source not in source_snapshots:
                source_snapshots[source] = _digest(_read(source, root))
            by_digest.setdefault(source_snapshots[source], []).append((source, role, flip))

        blobs = {}
        for digest, group in by_digest.items():
            data = _read(group[0][0], root)
            if _digest(data) != digest:
                raise ValueError(f"Source changed before encoding: {group[0][0]}")
            with Image.open(io.BytesIO(data)) as opened:
                if opened.width < 1 or opened.height < 1 or opened.width > MAX_DIMENSION or opened.height > MAX_DIMENSION:
                    raise ValueError(f"Unsupported source dimensions: {group[0][0]}")
                opened.load()
                image = opened.convert("RGBA")
            del data
            # Alpha belongs to a unique decoded source, not to every target.
            alpha = has_alpha(image) if any(role == "color" for _, role, _ in group) else False
            for source, role, flip in group:
                key = (digest, role, flip)
                if key not in blobs:
                    blob_rel = Path("blobs") / (digest + "-" + role + ("-flip" if flip else "") + ".dds")
                    blob_file = out / blob_rel
                    encoded = _encode(image, role, flip, blob_file, alpha)
                    _validate_blob(encoded, image, role, alpha)
                    _write_exclusive(blob_file, blob_dir, encoded)
                    created.append(blob_file)
                    blobs[key] = {"path": blob_rel.as_posix(), "sha256": _digest(encoded), "bytes": len(encoded),
                                  "width": image.width, "height": image.height, "source_sha256": digest,
                                  "role": role, "flip": flip}
                suffix = (".flip.bc5.dds" if flip else ".bc5.dds") if role == "normal" else (".dxt5.dds" if alpha else ".dxt1.dds")
                target = Path(str(source) + suffix)
                _within(target, root, must_exist=False)
                targets.append({"source": source.relative_to(root).as_posix(), "source_sha256": digest,
                                "target": target.relative_to(root).as_posix(), "role": role, "flip": flip,
                                "blob": blobs[key]["path"], "blob_sha256": blobs[key]["sha256"]})
            image.close()

        # A staged image is valid only for the exact source snapshot that was
        # encoded. Detect changes once more, and do not alter any package file.
        if _map_sha(map_file, root) != audit["map_sha256"]:
            raise ValueError("Map changed during staging")
        if _digest(GENERATOR_PATH.read_bytes()) != GENERATOR_SHA or _digest(Path(__file__).read_bytes()) != stage_sha:
            raise ValueError("Staging or generator source changed during encoding")
        for source, digest in source_snapshots.items():
            _within(source, root)
            if _digest(_read(source, root)) != digest:
                raise ValueError(f"Source changed during staging: {source}")
        for (source, normal, flip), original in observed.items():
            current = []
            for suffix in _sidecar_suffixes(normal, flip):
                sibling = Path(str(source) + suffix)
                _within(sibling, root, must_exist=False)
                if sibling.exists():
                    current.append(sibling.relative_to(root).as_posix())
            if tuple(current) != original:
                raise ValueError(f"Sidecar set changed during staging: {source}")
            if original:
                _, signature = _existing_header(root / original[0], root, normal)
                if signature != selected_headers[(source, normal, flip)]:
                    raise ValueError(f"Selected sidecar header changed during staging: {source}")
        manifest = {"schema": 1, "pack_root": str(root), "map": str(map_file), "map_sha256": audit["map_sha256"],
                    "audit_sha256": _digest(raw_audit), "generator_sha256": GENERATOR_SHA,
                    "stage_file_sha256_at_start_and_end": stage_sha, "pillow_version": PIL.__version__,
                    "scope": audit.get("scope", "map-declared paint variants only"),
                    "sources": [{"path": p.relative_to(root).as_posix(), "sha256": digest} for p, digest in source_snapshots.items()],
                    "targets": targets, "skipped": skipped, "blobs": list(blobs.values()),
                    "contract": "Stage only; no package file or map source was written. Runtime package checks are unchanged. Consumers require COMPLETE and must recheck artifact identities before any later publication."}
        # An unexpected file could be a preplaced hardlink/symlink. Never use
        # or remove it; leave the stage incomplete for explicit inspection.
        if {p.name for p in blob_dir.iterdir()} != {p.name for p in created}:
            raise ValueError("Unexpected staged blob entry")
        for blob in blobs.values():
            data = _read(out / blob["path"], blob_dir)
            if len(data) != blob["bytes"] or _digest(data) != blob["sha256"]:
                raise ValueError(f"Staged blob changed during encoding: {blob['path']}")
        payload = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        manifest_path = out / "manifest.json"
        _write_exclusive(manifest_path, out, payload)
        created.append(manifest_path)
        if {p.name for p in out.iterdir()} != {"blobs", "manifest.json"}:
            raise ValueError("Unexpected staged root entry")
        marker = out / "COMPLETE"
        _write_exclusive(marker, out, b"")
        created.append(marker)
        return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--pack-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = stage(args.audit, args.pack_root, args.output)
    except Exception:
        print(f"If created, incomplete stage is preserved at {args.output.absolute()}; inspect links and use a new output path.", file=sys.stderr)
        raise
    print(json.dumps({"targets": len(result["targets"]), "blobs": len(result["blobs"]),
                      "skipped": len(result["skipped"]), "output": str(args.output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
