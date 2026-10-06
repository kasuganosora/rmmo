"""Correctness gates for cloth optimizations; performance is a separate gate.

Run after Godot --editor --import --quit, with no concurrent GPU benchmarks.
Artifacts stay outside the repository, via the existing art_paths configuration.
"""
import argparse
import json
from pathlib import Path
import subprocess

from art_paths import review_path
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--stage', default='', help='Optional artifact subfolder; preserves earlier batch evidence')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    folder = review_path('character_3d/runtime_performance_06')
    if args.stage:
        if not args.stage.replace('_', '').replace('-', '').isalnum():
            parser.error('stage must be a simple alphanumeric label')
        folder = folder / args.stage
    folder.mkdir(parents=True, exist_ok=True)
    cases = [
        ('gpu_display', 'test_axis_gpu_display', []),
        ('packed_body', 'test_axis_packed_readback', []),
        ('body_identity', 'test_body_identity_shapes', []),
        ('packet_layout', 'test_cloth_packet_layout', []),
        ('indexed_packet', 'test_cloth_indexed_packet', []),
        ('shared_points', 'test_cloth_shared_points', []),
        ('resident_packet', 'test_cloth_resident_packet', []),
        ('batched_structure', 'test_cloth_batched_solve', []),
        ('gpu_contact_parity', 'test_cloth_body_broadphase', []),
        ('gpu_contact_parity_cooperative', 'test_cloth_body_broadphase', ['--cooperative-candidates']),
        ('runtime_lifecycle', 'test_runtime_cloth_lifecycle', []),
        ('runtime_twohand', 'test_runtime_cloth_lifecycle', ['--twohand']),
        ('runtime_resident', 'test_runtime_cloth_lifecycle', ['--resident-packet']),
        ('runtime_shared', 'test_runtime_cloth_lifecycle', ['--resident-packet', '--gpu-display', '--shared-body-points']),
        ('runtime_shared_twohand', 'test_runtime_cloth_lifecycle', ['--resident-packet', '--gpu-display', '--shared-body-points', '--twohand']),
        ('runtime_display', 'test_runtime_cloth_lifecycle', ['--resident-packet', '--gpu-display']),
        ('runtime_display_twohand', 'test_runtime_cloth_lifecycle', ['--resident-packet', '--gpu-display', '--twohand']),
        ('runtime_resident_twohand', 'test_runtime_cloth_lifecycle', ['--resident-packet', '--twohand']),
    ]
    results = []
    for name, script, flags in cases:
        command = [args.godot, '--path', str(root), '--script',
                   f'res://tools/{script}.gd', '--', *flags]
        try:
            run = run_background(command, cwd=root, timeout=360)
            output = run.stdout.decode('utf-8', errors='replace')
            code = run.returncode
            passed = code == 0 and 'PASS ' in output and 'ERROR:' not in output and 'was leaked' not in output and 'were leaked' not in output
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b'').decode('utf-8', errors='replace')
            output += '\nTIMEOUT after 360 seconds'
            code, passed = None, False
        (folder / f'{name}.log').write_text(output, encoding='utf-8')
        results.append(dict(name=name, passed=passed, returncode=code))
        print(json.dumps(results[-1]), flush=True)
    (folder / 'regressions.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(result['passed'] for result in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
