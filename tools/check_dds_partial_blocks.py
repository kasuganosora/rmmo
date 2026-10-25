"""Reproduce DDS edge-block mip sizes without changing authored assets.

Use --gpu for a private-desktop Vulkan upload/readback of every compressed mip.
The output must be a new directory outside the Godot project.
"""
import argparse
import json
import struct
import subprocess
from pathlib import Path

from PIL import Image

from generate_texture_dds_sidecars import save_dds
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if output.is_relative_to(root):
        parser.error('Fixtures must be outside the Godot project')
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for width, height in [(4, 4), (12, 20), (1, 1), (5, 5), (6, 6), (7, 7), (7, 11), (1254, 1254)]:
        for role in ['bc1', 'bc3', 'bc5']:
            path = output / f'{width}x{height}_{role}.dds'
            pixels = Image.new('RGBA', (width, height), (64, 191, 128, 220))
            assert save_dds(pixels, path, role == 'bc3', normal=role == 'bc5')
            data = path.read_bytes()
            levels = struct.unpack_from('<I', data, 28)[0]
            sizes = []
            w, h = width, height
            for _ in range(levels):
                sizes.append(max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * (8 if role == 'bc1' else 16))
                w, h = max(1, w // 2), max(1, h // 2)
            assert len(data) == 128 + sum(sizes)
            rows.append(dict(path=str(path), width=width, height=height, mipmaps=levels - 1, bytes=sum(sizes)))
    manifest = output / 'manifest.json'
    manifest.write_text(json.dumps(dict(images=rows, gpu=args.gpu), indent=2), encoding='utf-8')
    command = [str(args.engine.resolve()), '--path', str(root), '--script', 'res://tools/test_dds_partial_blocks.gd']
    command += ['--rendering-driver', 'vulkan'] if args.gpu else ['--headless']
    command += ['--', str(manifest), str(output / 'result.json')]
    if args.gpu:
        result = run_background(command, cwd=root, timeout=120)
        code = result.returncode
        (output / 'engine.log').write_bytes(result.stdout)
    else:
        with (output / 'engine.log').open('wb') as log:
            code = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                                  creationflags=subprocess.CREATE_NO_WINDOW, timeout=120).returncode
    print(json.dumps(dict(exit_code=code, result=str(output / 'result.json'))), flush=True)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
