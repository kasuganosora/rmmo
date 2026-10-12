import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/review_artifacts')
rows = []
for label, workers in [('warm', 1), ('a1', 1), ('b1', 2), ('b2', 2), ('a2', 1)]:
    output = OUT / f'house_warm_{label}_20261011.json'
    log = output.with_suffix('.log')
    command = [sys.executable, str(ROOT / 'tools/run_godot_background.py'), '--timeout', '300', '--log', str(log), '--',
               'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(ROOT), '--script', 'res://tools/test_house_town_editor_incremental.gd', '--',
               '--output=' + str(output), '--prefab-warm-workers=' + str(workers)]
    result = subprocess.run(command, cwd=ROOT, timeout=320)
    logs = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in logs or '\nERROR:' in logs:
        print(label, 'FAILED', logs[-5000:], flush=True)
        raise SystemExit(1)
    data = json.loads(output.read_text(encoding='utf-8'))
    timings = data.get('load_result', {}).get('timings', {})
    row = {key: data.get(key) for key in ['load_ms', 'failures', 'full_rebuilds', 'baseline_full_rebuilds', 'final_house_count', 'final_record_count', 'prefab_warm_workers']}
    row.update(label=label, workers=workers, report=str(output), checks=logs.count('PASS:'),
               validation=timings.get('validation', {}), validate_ms=timings.get('validate_ms'),
               build=timings.get('build', {}), preparation=timings.get('preparation', {}),
               warnings=[line for line in logs.splitlines() if line.startswith('WARNING:')])
    rows.append(row)
    (OUT / 'house_warm_abba_20261011.json').write_text(json.dumps({'rows': rows, 'scope': 'Fresh process same immutable full town ABBA, excluded warm-up, no OS or asset cache clearing. Only bounded prefab warm worker limit differs; all real HTTP acceptance operations are after load timing.'}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in row.items() if key not in ['validation', 'build', 'preparation']} | {'prefab_warm': row['validation'].get('prefab_warm', {})}, ensure_ascii=False), flush=True)
    if row['failures'] or row['full_rebuilds'] != row['baseline_full_rebuilds']:
        raise SystemExit(1)
print('serial_mean_ms', statistics.mean(row['load_ms'] for row in rows if row['label'] in ['a1', 'a2']), flush=True)
print('parallel_mean_ms', statistics.mean(row['load_ms'] for row in rows if row['workers'] == 2), flush=True)
