"""Safely extract owned castle FBX/material sources, without installing Unity scripts.

Streams Unity's GUID tar layout; can inspect an incomplete browser download.
No archive paths are used as output paths. Textures are opt-in by filename.
"""
import argparse
import json
import shutil
import tarfile
import tempfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('package', type=Path)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--textures', nargs='*', default=[])
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
entries, current, asset, pathname = [], None, None, None

def finish():
    if not pathname:
        return
    name = Path(pathname).name
    entries.append({'guid': current, 'path': pathname})
    if asset and (name.lower().endswith(('.fbx', '.mat')) or name in a.textures):
        target = a.output / name
        shutil.copyfile(asset, target)

complete = False
with tempfile.TemporaryDirectory(prefix='rmmo_castle_') as td:
    tmp = Path(td) / 'asset'
    try:
        with tarfile.open(a.package, 'r|gz') as archive:
            for member in archive:
                pieces = member.name.strip('/').split('/')
                if len(pieces) != 2 or not member.isfile():
                    continue
                guid, key = pieces
                if guid != current:
                    finish()
                    current, asset, pathname = guid, None, None
                if key == 'pathname':
                    pathname = archive.extractfile(member).read(8192).decode('utf-8').strip()
                elif key == 'asset':
                    with tmp.open('wb') as output:
                        shutil.copyfileobj(archive.extractfile(member), output, 1024 * 1024)
                    asset = tmp
            finish()
            complete = True
    except (EOFError, tarfile.ReadError):
        pass
(a.output / 'package_index.json').write_text(json.dumps({'complete': complete, 'entries': entries}, indent=2), encoding='utf-8')
print(json.dumps({'complete': complete, 'entries': len(entries), 'fbx': len(list(a.output.glob('*.fbx'))) + len(list(a.output.glob('*.FBX')))}))
