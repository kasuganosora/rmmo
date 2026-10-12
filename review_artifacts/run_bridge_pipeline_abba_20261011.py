import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/review_artifacts')
CHECKPOINT = 'D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf'
rows = []
for label, enabled in [('warm', False), ('a1', False), ('b1', True), ('b2', True), ('a2', False)]:
    output = OUT / f'bridge_pipeline_{label}_20261011.json'
    log = output.with_suffix('.log')
    command = [sys.executable, str(ROOT / 'tools/run_godot_background.py'), '--timeout', '260', '--log', str(log), '--',
               'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(ROOT), '--script', 'res://tools/profile_game_entry.gd', '--',
               '--map=' + CHECKPOINT, '--output=' + str(output), '--spawn=321.2,0.9,160.3', '--monitor',
               '--bridge-texture-preparation' if enabled else '--without-bridge-texture-preparation']
    result = subprocess.run(command, cwd=ROOT, timeout=280)
    logs = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in logs or '\nERROR:' in logs:
        print(label, 'FAILED', logs[-5000:], flush=True)
        raise SystemExit(1)
    data = json.loads(output.read_text(encoding='utf-8'))
    events = data.get('monitor', {}).get('trace', {}).get('events', [])
    bridge = [event for event in events if event.get('label') == 'deferred.publication' and event.get('details', {}).get('group_id', '').startswith('bridge:')]
    profile = data.get('entry_deferred_profile', {})
    row = {key: data.get(key) for key in ['entry_ms', 'entry_core_ready_ms', 'failures', 'map_sha', 'formal_sha', 'screenshot_avatar_hidden', 'bridge_texture_preparation']}
    row.update(label=label, enabled=enabled, report=str(output), checks=sum(line.startswith('PASS ') for line in logs.splitlines()),
               bridge_publications=bridge,
               bridge_preparation={key: value for key, value in profile.items() if key.startswith('bridge_texture_')},
               pixel_preparation=profile.get('prefab_pixels', {}),
               frames=data.get('monitor', {}).get('phase_frame_percentiles_ms', {}),
               admission=profile.get('admission', {}),
               warnings=[line for line in logs.splitlines() if line.startswith('WARNING:')])
    rows.append(row)
    (OUT / 'bridge_pipeline_abba_20261011.json').write_text(json.dumps({'rows': rows, 'scope': 'Fresh process same checkpoint/spawn ABBA with excluded warm-up, no OS or asset cache clearing. Only targeted bridge CPU texture preparation differs. No formal map mutation or LOD migration in timed fixture.'}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in row.items() if k not in ['pixel_preparation', 'frames', 'admission']}, ensure_ascii=False), flush=True)
    if row['failures'] or not row['screenshot_avatar_hidden'] or row['map_sha'] != row['formal_sha']:
        raise SystemExit(1)
print('off_mean_ms', statistics.mean(row['entry_ms'] for row in rows if row['label'] in ['a1', 'a2']), flush=True)
print('on_mean_ms', statistics.mean(row['entry_ms'] for row in rows if row['enabled']), flush=True)
