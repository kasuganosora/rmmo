"""Keep a renamed Windows engine's separate debug symbols discoverable by GDB.

The PE .gnu_debuglink still names the original build suffix. Create a hard link
with that exact basename; do not rewrite the executable or copy large symbols.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import struct


def pe_debuglink(executable: Path) -> tuple[str, int]:
    with executable.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("Expected a Windows PE executable")
        stream.seek(0x3C)
        pe_offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(pe_offset)
        if stream.read(4) != b"PE\0\0":
            raise ValueError("Invalid PE signature")
        _, count, _, symbols, symbol_count, optional_size, _ = struct.unpack("<HHIIIHH", stream.read(20))
        sections = pe_offset + 24 + optional_size
        for index in range(count):
            stream.seek(sections + index * 40)
            header = stream.read(40)
            name = header[:8].rstrip(b"\0")
            if name.startswith(b"/"):
                # COFF long section names live after the 18-byte symbol rows.
                stream.seek(symbols + symbol_count * 18 + int(name[1:]))
                name = stream.read(256).split(b"\0", 1)[0]
            if name != b".gnu_debuglink":
                continue
            size, offset = struct.unpack_from("<II", header, 16)
            stream.seek(offset)
            payload = stream.read(min(size, 4096))
            end = payload.index(b"\0")
            filename = payload[:end].decode("utf-8")
            if not filename or filename in (".", "..") or any(c in filename for c in "/\\:"):
                raise ValueError("Debug link must be a local basename")
            checksum = struct.unpack_from("<I", payload, (end + 4) & ~3)[0]
            return filename, checksum
    raise ValueError("Executable has no .gnu_debuglink section")


def ensure_debuglink(executable: Path, symbols: Path) -> dict:
    executable, symbols = executable.resolve(strict=True), symbols.resolve(strict=True)
    name, checksum = pe_debuglink(executable)
    alias = executable.parent / name
    created = False
    if alias.exists():
        if not os.path.samefile(alias, symbols):
            raise FileExistsError(f"Refusing to replace a different symbol file: {alias}")
    else:
        os.link(symbols, alias)
        created = True
    return {"engine": str(executable), "symbols": str(symbols), "debuglink": str(alias),
            "created": created, "same_file": os.path.samefile(alias, symbols),
            "debuglink_crc32": f"{checksum:08x}", "symbol_bytes": symbols.stat().st_size,
            "engine_modified": False, "note": "Alias identity verified; CRC is the executable's expected value, not a fresh symbol checksum."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = ensure_debuglink(args.engine, args.symbols or Path(str(args.engine) + ".debugsymbols"))
    text = json.dumps(report, indent=2)
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
