"""Publish the five reviewed structural candidates through the existing UI importer.

Does not place or save any real map. Requires explicit --publish; never rewrites
an existing receipt. GPU subprocesses run serially on a private desktop.
"""
import argparse
import json
import subprocess
from pathlib import Path
from run_godot_background import run_background
from finalize_s12_residential_review_20261017 import OUT, ROOT, read, sha, identity, write

p = argparse.ArgumentParser()
p.add_argument('--publish', action='store_true', required=True)
p.add_argument('--resume-failed', action='store_true', help='Resume only existing incomplete imports through their immutable receipts')
a = p.parse_args()
repo = Path('D:/code/rmmo')
handoff = read(OUT / 'handoff.json')
folder = OUT / 'publication'
folder.mkdir(exist_ok=True)
guards = {str(path): sha(path) for path in [ROOT / 'packs/default/maps/axel_town/map.gltf', ROOT / 'maps/medieval_river_town/map.gltf'] if path.exists()}
receipts = []
for row in handoff['items']:
    proof = row['acceptance']
    source = row['source']
    assert sha(proof['path']) == proof['sha256'] and sha(source['path']) == source['sha256']
    out = folder / (row['id'] + '.json')
    resume = None
    if out.exists():
        receipt = read(out)
        assert receipt['source_sha256'] == source['sha256']
        if receipt['ok'] and receipt['completed']:
            receipts.append(identity(out))
            continue
        assert a.resume_failed, 'Inspect failure then explicitly resume; never overwrite it'
        resume = out
        out = folder / (row['id'] + '_resumed.json')
        if out.exists():
            resumed = read(out)
            assert resumed['ok'] and resumed['completed'] and resumed['source_sha256'] == source['sha256']
            assert resumed['review_sha256'] == proof['sha256']
            receipts.append(identity(out))
            continue
    active = subprocess.check_output(['powershell', '-NoProfile', '-Command', "Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"], text=True).strip()
    if active:
        raise RuntimeError('Other GPU process active: ' + active)
    cmd = ['D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(repo), '--script',
           'res://tools/import_s12_residential_library.gd', '--', '--publish', '--source=' + source['path'],
           '--sha256=' + source['sha256'], '--review=' + proof['path'], '--review-sha256=' + proof['sha256'],
           '--out=' + out.as_posix(), '--id=' + row['id'], '--label=' + row['label'], '--category=' + row['category']]
    if resume:
        cmd.append('--resume-receipt=' + resume.as_posix())
    print('Publishing', row['id'], flush=True)
    run = run_background(cmd, cwd=repo, timeout=360)
    out.with_suffix('.log').write_bytes(run.stdout)
    if run.returncode:
        raise RuntimeError(f'Publication failed: {row["id"]}; see {out}')
    assert read(out)['ok']
    receipts.append(identity(out))
    for path, expected in guards.items():
        assert sha(path) == expected, 'Protected map changed during publication: ' + path
items = [read(row['path'])['items'][0] for row in receipts]
catalog = ROOT / 'packs/default/assets/library.json'
write(folder / 'receipt.json', {'ok': True, 'completed': True, 'items': items, 'receipts': receipts,
                               'catalog_path': catalog.as_posix(), 'catalog_sha_after': sha(catalog),
                               'formal_map_modified': False, 'protected_maps': guards,
                               'stage': 'structure_and_layout_candidate; near-field material work remains separate'})
print('S12_PUBLICATION_COMPLETE', flush=True)
