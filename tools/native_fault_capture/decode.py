"""Decode captured Windows x64 PCs offline with the matching MinGW symbols.

This is first-chance evidence, not proof that a process terminated. Always keep
the raw capture, process exit and launcher identity alongside the decoded file.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import struct
import subprocess


def image_base(path):
    with Path(path).open("rb") as handle:
        handle.seek(0x3C)
        offset = struct.unpack("<I", handle.read(4))[0]
        handle.seek(offset)
        if handle.read(4) != b"PE\0\0":
            raise ValueError(f"Not a PE image: {path}")
        handle.seek(offset + 24)
        if struct.unpack("<H", handle.read(2))[0] != 0x20B:
            raise ValueError(f"Not a PE32+ image: {path}")
        handle.seek(offset + 24 + 24)
        return struct.unpack("<Q", handle.read(8))[0]


def decode(path, addr2line=None, gdb=None):
    modules, frames, fault = [], [], {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if parts[0] == "module":
            modules.append(dict(base=int(parts[1], 16), size=int(parts[2], 16), path=parts[3]))
        elif parts[0] == "fault":
            fault = dict(code=parts[1], **dict(p.split("=", 1) for p in parts[2:]))
        elif parts[0] == "frame":
            frames.append(dict(index=int(parts[1]), pc=int(parts[2], 16), sp=int(parts[3], 16)))
    groups = defaultdict(list)
    for frame in frames:
        # The fault PC is exact; subsequent PCs are return addresses.
        pc = frame["pc"] - (1 if frame["index"] > 0 and frame["pc"] else 0)
        module = next((m for m in modules if m["base"] <= pc < m["base"] + m["size"]), None)
        if module is None:
            frame["note"] = "No initial module owns this PC (including null or a later-loaded module)"
            continue
        binary = Path(module["path"])
        frame["module"] = str(binary)
        if not binary.is_file():
            frame["note"] = "Image unavailable; preserve raw PC"
            continue
        frame["preferred_pc"] = hex(image_base(binary) + pc - module["base"])
        symbols = binary.with_suffix(binary.suffix + ".debugsymbols")
        if not symbols.is_file():
            symbols = binary
        frame["symbol_file"] = str(symbols)
        groups[str(symbols)].append(frame)
    for symbols, group in groups.items():
        if gdb:
            # GDB loads this large Godot DWARF build much faster than this
            # machine's addr2line. No target is run or attached here.
            cmd = [str(gdb), "--batch", "--nx", "-iex", "set debuginfod enabled off",
                   "-iex", "set pagination off", "-ex", f'file "{Path(symbols).as_posix()}"']
            for frame in group:
                pc = frame["preferred_pc"]
                cmd += ["-ex", f"echo RMMO_PC={pc}\\n", "-ex", f"info symbol {pc}", "-ex", f"info line *{pc}"]
        else:
            cmd = [str(addr2line), "-a", "-f", "-C", "-i", "-e", symbols]
            cmd += [f["preferred_pc"] for f in group]
        result = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=120,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        result.check_returncode()
        by_pc, current = {}, None
        for line in result.stdout.splitlines():
            address = line.removeprefix("RMMO_PC=") if gdb else line
            if address.startswith("0x") and all(c in "0123456789abcdefABCDEF" for c in address[2:]):
                current = int(address, 16)
                by_pc[current] = []
            elif current is not None:
                by_pc[current].append(line)
        for frame in group:
            frame["symbols"] = by_pc.get(int(frame["preferred_pc"], 16), [])
    return dict(raw=str(Path(path).resolve()), fault=fault, frames=frames,
                evidence="First chance only. Check the owned process outcome; no exception is swallowed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    backend = parser.add_mutually_exclusive_group(required=True)
    backend.add_argument("--addr2line", type=Path)
    backend.add_argument("--gdb", type=Path, help="Offline symbol lookup only; does not run or attach a target")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(decode(args.raw, args.addr2line, args.gdb), handle, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
