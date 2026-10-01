"""Run geometry probes on the real GPU; expected failures must fail geometrically.

Import edited GLSL with Godot --editor --import --quit before running this suite.
The real garment capture/audit is a separate, mandatory acceptance gate.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from art_paths import review_path
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    cases = [
        ('body_unilateral', 'body_unilateral', [], None),
        ('oblique_contact', 'oblique_contact', [], None),
        ('body_layers_aligned', 'body_layers', ['--aligned', '--body-tangents'], None),
        ('body_layers_offset', 'body_layers', ['--body-tangents'], None),
        ('body_layers_rotated', 'body_layers', ['--aligned', '--rotated', '--body-tangents'], None),
        ('body_layers_negative', 'body_layers', ['--aligned'], 'Body and cloth-layer constraints conflict'),
        ('close_gap', 'self_contact', ['--mass-balance'], None),
        ('point_sweep', 'self_contact', ['--mass-balance', '--sweep'], None),
        ('moving_pin', 'self_contact', ['--mass-balance', '--moving-anchor', '--flip-winding'], None),
        ('fixed_point', 'self_contact', ['--mass-balance', '--reverse-self', '--contact-iterations'], None),
        ('fixed_point_negative', 'self_contact', ['--reverse-self', '--contact-iterations'], 'Full topology self contact did not separate'),
        ('edge_sweep', 'self_contact', ['--mass-balance', '--edge-only', '--sweep', '--contact-iterations', '--contact-structure'], None),
        ('edge_negative', 'self_contact', ['--edge-only', '--sweep', '--without-edges'], 'Full topology self contact did not separate'),
        ('corner', 'self_corner', ['--mass-balance', '--contact-structure'], None),
        ('corner_reordered', 'self_corner', ['--mass-balance', '--contact-structure', '--reverse-faces'], None),
        ('body_reverse', 'reverse_contact', ['--mass-balance', '--self-contact'], None),
        ('body_reverse_downward', 'reverse_contact', ['--mass-balance', '--self-contact', '--downward', '--flip-winding'], None),
    ]
    folder = review_path('character_3d/contact_suite')
    folder.mkdir(parents=True, exist_ok=True)
    results = []
    for name, script, flags, negative in cases:
        command = [args.godot, '--path', str(root), '--script', f'res://tools/test_gpu_cloth_{script}.gd', '--', *flags]
        try:
            run = run_background(command, cwd=root, timeout=120)
            output = run.stdout.decode('utf-8', errors='replace')
            ok = (run.returncode != 0 and negative in output) if negative else (run.returncode == 0 and 'PASS ' in output and 'ERROR:' not in output)
            ok = ok and 'Parse Error' not in output and 'Stale shader' not in output
            code = run.returncode
        except subprocess.TimeoutExpired:
            output, ok, code = 'TIMEOUT after 120 seconds', False, None
        (folder / f'{name}.log').write_text(output, encoding='utf-8')
        results.append(dict(name=name, passed=bool(ok), returncode=code, expected_failure=bool(negative)))
        print(json.dumps(results[-1]), flush=True)
    (folder / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
