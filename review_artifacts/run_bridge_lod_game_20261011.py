import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path('D:/code/rmmo')
RUNTIME = Path('D:/code/rmmo_runtime')
SOURCE = RUNTIME / 'maps/medieval_river_town/map.gltf'
OUT = RUNTIME / 'review_artifacts'
published = json.loads((OUT / 'bridge_lod_update_20261011/published.json').read_text(encoding='utf-8'))
source_bytes = SOURCE.read_bytes()
source_sha = hashlib.sha256(source_bytes).hexdigest()
assert published['ok'] and source_sha == published['published_sha256']
data = json.loads(source_bytes)
folder = RUNTIME / 'cache/world3d' / ('bridge_lod_checkpoint_20261011_' + str(time.time_ns()))
folder.mkdir()
target = folder / SOURCE.name
target.write_bytes(source_bytes)
manifest = data['nodes'][0]['extras']['rmmo_resource_dependencies']
for uri in manifest:
    relative = Path(uri)
    assert not relative.is_absolute() and '..' not in relative.parts
    assert relative.parts[0] == 'map.gltf.resources'
    original = SOURCE.parent / relative
    destination = folder / relative
    destination.parent.mkdir(exist_ok=True)
    shutil.copy2(original, destination)
assert all(item.get('uri', '').startswith('data:') for kind in ('buffers', 'images') for item in data.get(kind, []))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_sha
(OUT / 'bridge_lod_game_checkpoint_20261011.json').write_text(json.dumps({'map': str(target), 'sha256': source_sha, 'resources': len(manifest), 'purpose': 'Temporary runtime acceptance copy, not a map backup'}, indent=2), encoding='utf-8')
for label, arguments in [('cold_route', ['--town-route']), ('warm', []), ('transfer', None)]:
    script = 'res://tools/profile_town_transfer.gd' if arguments is None else 'res://tools/profile_game_entry.gd'
    output = OUT / ('bridge_lod_game_' + label + '_20261011.json')
    log = output.with_suffix('.log')
    command = [sys.executable, str(ROOT / 'tools/run_godot_background.py'), '--timeout', '560', '--log', str(log), '--',
               'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(ROOT), '--script', script, '--',
               '--map=' + str(target), '--output=' + str(output)]
    if arguments is not None:
        command += ['--spawn=321.2,0.9,160.3', '--monitor'] + arguments
    result = subprocess.run(command, cwd=ROOT, timeout=580)
    logs = log.read_text(encoding='utf-8', errors='replace')
    report = json.loads(output.read_text(encoding='utf-8')) if output.exists() else {}
    print(json.dumps({'label': label, 'exit': result.returncode, 'entry_ms': report.get('entry_ms'), 'transfer_ms': report.get('transfer_ms'),
                      'failures': report.get('failures'), 'checks': sum(line.startswith('PASS ') for line in logs.splitlines()),
                      'route_ok': report.get('town_route', {}).get('ok'), 'avatar_hidden': report.get('screenshot_avatar_hidden'),
                      'report': str(output), 'warnings': [line for line in logs.splitlines() if line.startswith(('WARNING:', 'Unicode parsing'))]}, ensure_ascii=False), flush=True)
    if result.returncode or 'SCRIPT ERROR:' in logs or '\nERROR:' in logs or report.get('failures') != 0:
        print(logs[-4000:], flush=True)
        raise SystemExit(1)
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_sha
    assert hashlib.sha256(target.read_bytes()).hexdigest() == source_sha
