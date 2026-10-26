"""Build the opt-in Windows x64 capture DLL outside the Godot project."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--engine-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New external directory")
    args = parser.parse_args()
    source = Path(__file__).with_name("capture.cpp").resolve()
    output = args.output.resolve()
    if output.is_relative_to(source.parents[2]):
        raise ValueError("Generated native files belong outside the Godot project")
    output.mkdir(parents=True, exist_ok=False)
    header = args.engine_source.resolve() / "core/extension/gdextension_interface.gen.h"
    library = output / "capture.dll"
    command = [str(args.compiler.resolve()), "-shared", "-O1", "-g", "-fno-omit-frame-pointer",
               "-static-libgcc", "-static-libstdc++", "-I" + str(header.parent),
               str(source), "-o", str(library), "-lpsapi"]
    manifest = dict(command=command, source_sha256=digest(source), header_sha256=digest(header))
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (output / "build.log").write_bytes(result.stdout)
    manifest["exit_code"] = result.returncode
    if not result.returncode:
        manifest["library_sha256"] = digest(library)
        (output / "capture.gdextension").write_text(
            '[configuration]\nentry_symbol = "rmmo_capture_init"\n'
            'compatibility_minimum = "4.7"\nreloadable = false\n\n'
            f'[libraries]\nwindows.x86_64 = "{library.as_posix()}"\n', encoding="utf-8")
    (output / "build.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    result.check_returncode()


if __name__ == "__main__":
    main()
