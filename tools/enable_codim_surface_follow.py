"""Enable the explicit offline predictor adapter in an already prepared C-IPC checkout.

Preserves the original source and fails on unknown edits. This changes input
prediction, not contact constraints. It is not a Godot integration or acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from prepare_codim_reference import PIN


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    if subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip() != PIN:
        raise ValueError('Wrong upstream revision')
    relative = 'Library/FEM/Shell/IMPLICIT_EULER.h'
    original = subprocess.check_output(['git', '-C', str(root), 'show', PIN+':'+relative]).decode()
    patched = original.replace('#include <deque>', '#include <deque>\n#include <FEM/Shell/RMMO_SURFACE_FOLLOW.h>', 1)
    marker = '        std::cout << "Xn and Xtilde prepared" << std::endl;'
    if original.count(marker) != 1:
        raise ValueError('Unexpected predictor layout')
    patched = patched.replace(marker, '        RMMO_Apply_Surface_Follow<T, dim>(Xtilde, h);\n'+marker)
    target = root / relative
    if target.read_text(encoding='utf-8') not in (original, patched):
        raise ValueError('Unknown timestep changes; refusing overwrite')
    header = Path(__file__).parent / 'reference/codim_surface_follow.h'
    destination = target.parent / 'RMMO_SURFACE_FOLLOW.h'
    if destination.exists() and destination.read_bytes() != header.read_bytes():
        raise ValueError('Unknown existing adapter; inspect before updating')
    if target.read_text(encoding='utf-8') != patched:
        target.write_text(patched, encoding='utf-8', newline='\n')
    if not destination.exists():
        destination.write_bytes(header.read_bytes())
    manifest = dict(scope='offline surface-follow predictor adapter; no runtime acceptance',
                    upstream=PIN, contact_algorithm_modified=False, prediction_modified=True,
                    disabled_parameter='RMMOSurfaceFollowFile empty or absent',
                    files={relative: hashlib.sha256(target.read_bytes()).hexdigest(),
                           str(destination.relative_to(root)).replace('\\','/'): hashlib.sha256(destination.read_bytes()).hexdigest()})
    (root/'RMMO_SURFACE_FOLLOW.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest))


if __name__ == '__main__':
    main()
