"""Rebuild and replay the integration patch against the actual pinned Git paths."""
import argparse
import difflib
from pathlib import Path
import subprocess
import tempfile

UPSTREAM = 'bd917afd15a8389370c7e12ec9c074555834cf68'
FILES = ['src/gpu_cloth_solver.gd', *['shaders/compute/' + name + '.glsl' for name in (
    'cloth_collide_triangles', 'cloth_predict', 'cloth_update', 'cloth_reverse_contacts',
    'cloth_gather_contacts', 'cloth_snapshot', 'cloth_collide_self_swept')]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    head = subprocess.check_output(['git', '-C', str(args.upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if head != UPSTREAM:
        raise ValueError('Upstream checkout does not match pinned commit')
    tracked = set(subprocess.check_output(['git', '-C', str(args.upstream), 'ls-tree', '-r', '--name-only', 'HEAD'], text=True).splitlines())
    prefix = 'addons/godot_gpu_cloth/'
    # Upstream is a whole Godot project. Stripping this prefix falsely turns
    # modified upstream files into new files and makes an empty-tree replay pass.
    assert prefix + 'src/gpu_cloth_solver.gd' in tracked
    chunks, sources = [], {}
    for path in FILES:
        relative = prefix + path
        old = None
        if relative in tracked:
            old = subprocess.check_output(['git', '-C', str(args.upstream), 'show', 'HEAD:' + relative]).decode('utf-8')
        sources[relative] = old
        new = (project / relative).read_text(encoding='utf-8')
        chunks.append(f'diff --git a/{relative} b/{relative}\n')
        if old is None:
            chunks.append('new file mode 100644\n')
        chunks.extend(difflib.unified_diff((old or '').splitlines(keepends=True), new.splitlines(keepends=True),
                      fromfile='a/' + relative if old is not None else '/dev/null', tofile='b/' + relative))
    assert sum(old is not None for old in sources.values()) >= 4
    patch = project / 'tools/patches/gpu_cloth_candidate_integration.patch'
    patch.write_text(''.join(chunks), encoding='utf-8', newline='\n')
    with tempfile.TemporaryDirectory(prefix='rmmo-upstream-replay-') as temporary:
        for relative, old in sources.items():
            if old is not None:
                target = Path(temporary) / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(old, encoding='utf-8', newline='\n')
        subprocess.run(['git', 'apply', '--unsafe-paths', str(patch)], cwd=temporary, check=True)
        for relative in sources:
            assert (Path(temporary) / relative).read_text(encoding='utf-8') == (project / relative).read_text(encoding='utf-8'), relative
    print('PASS pinned upstream replay:', sum(old is not None for old in sources.values()),
          'modified originals and', sum(old is None for old in sources.values()), 'new files')


if __name__ == '__main__':
    main()
