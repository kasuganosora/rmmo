"""Diagnostic only: one owned Godot process on the private desktop.

Runs the existing entry/hardware, read-only main-thread CPU and WCT probes.
No production changes, suspension, injection, privilege changes, or other-process
wait traversal. Results are not a new speed benchmark (sampling has overhead).
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
without_wct = '--without-wct' in sys.argv
sparse_wct = '--sparse-wct' in sys.argv
TAG = 'wait_no_wct' if without_wct else ('wait_sparse_wct' if sparse_wct else 'wait_valid')
if '--mesh-parts' in sys.argv:
    if not without_wct:raise SystemExit('--mesh-parts requires --without-wct')
    TAG = 'mesh_parts'
OUT = ROOT / 'review_artifacts/loading_decoupling_20261010' / TAG
REPORT = Path('D:/code/rmmo_runtime/review_artifacts/loading_decoupling_20261010') / (TAG+'.json')
LABEL = 'loading_decoupling_20261010_' + TAG
OUT.mkdir(parents=True, exist_ok=True)
REPORT.parent.mkdir(parents=True, exist_ok=True)
children = []
handles = []
try:
    probes = [
        ('main_cpu', 'tools/profile_godot_thread.py', []),
        ('main_wct', 'review_artifacts/game_idle_hitch_audit_20261007/profile_wait_chain.py',
         ['--critical-sections', '--interval-ms', '250' if sparse_wct else '25']),
    ]
    if without_wct:
        probes = probes[:1]
    for name, script, extra in probes:
        handle = (OUT / (name + '.log')).open('wb')
        handles.append(handle)
        command = [sys.executable, script, '--label', LABEL, '--timeout', '180',
                   '--out', str(OUT / (name + '.json')), *extra]
        child = subprocess.Popen(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        children.append((name, child))
    command = [sys.executable, 'tools/profile_load_hardware.py', '--timeout', '120',
               '--log', str(OUT / 'wait_entry.log'), '--hardware', str(OUT / 'wait_entry.hardware.json'),
               '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(ROOT),
               '--script', 'res://tools/profile_game_entry.gd', '--', '--label=' + LABEL,
               '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
               '--spawn=321.2,0.9,160.3', '--monitor', '--output=' + str(REPORT)]
    result = subprocess.run(command, cwd=ROOT, timeout=140)
    statuses = {'entry_exit': result.returncode, 'command': command, 'probes': {}}
    for name, child in children:
        try:
            statuses['probes'][name] = child.wait(timeout=8)
        except subprocess.TimeoutExpired:
            child.terminate()
            child.wait(timeout=5)
            statuses['probes'][name] = 'sampler_did_not_exit_after_owned_target'
    (OUT / 'wait_run.json').write_text(json.dumps(statuses, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(statuses, indent=2))
finally:
    for _, child in children:
        if child.poll() is None:
            child.terminate()
            child.wait(timeout=5)
    for handle in handles:
        handle.close()
