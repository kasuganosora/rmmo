"""Compare built-in backends in isolated external projects, leaving game settings intact."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from art_paths import review_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    root = review_path('character_3d/builtin_cloth_probe')
    controls_valid = True
    for backend, key in [('Jolt Physics', 'jolt'), ('GodotPhysics3D', 'godot')]:
        project = root / key
        project.mkdir(parents=True, exist_ok=True)
        config = ('config_version=5\n[application]\nconfig/name="RMMO isolated cloth probe"\n'
                  '[physics]\n3d/physics_engine="' + backend + '"\n'
                  '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (project / 'project.godot').write_text(config, encoding='utf-8')
        shutil.copy2(Path(__file__).with_suffix('.gd'), project / 'probe.gd')
        # Remove neither user files nor old evidence; each backend owns one report.
        run = subprocess.run([args.godot, '--headless', '--path', str(project), '--script', 'res://probe.gd'],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        output = run.stdout.decode('utf-8', errors='replace')
        (root / f'{key}.log').write_text(output, encoding='utf-8')
        valid = run.returncode == 0 and 'ERROR:' not in output
        controls_valid = controls_valid and valid
        if valid:
            report = json.loads((project / 'probe_result.json').read_text(encoding='utf-8'))
            print(json.dumps({'backend': backend, 'controls_valid': True,
                              'capabilities': {r['mode']: r['supported_in_probe'] for r in report['cases']}}), flush=True)
        else:
            print(json.dumps({'backend': backend, 'controls_valid': False, 'returncode': run.returncode}), flush=True)
    # Zero means observations have valid controls, not that self/peer cloth passed.
    return 0 if controls_valid else 2


if __name__ == '__main__':
    sys.exit(main())
