"""Read recorded entry-gate snapshots; do not launch the engine or touch maps."""
import json
from collections import Counter
from pathlib import Path

REPORT = Path('D:/code/rmmo_runtime/review_artifacts/deferred_final_20261010')
rows = []
for path in sorted(REPORT.glob('*.json')):
    if path.name.endswith('.hardware.json'):
        continue
    data = json.loads(path.read_text(encoding='utf-8'))
    if 'world_profile' not in data:
        continue
    trace = data.get('monitor', {}).get('trace', {})
    gates = sorted((e for e in trace.get('events', []) if e['label'] == 'entry.geometry_gate'), key=lambda e: e['start_us'])
    if not gates:
        continue
    core = data['world_profile']['entry_core_resources_ready_us']
    safe = data['world_profile']['entry_safety_ready_us']
    ready = next((e for e in gates if e['details']['dependencies_ready']), None)
    segments = Counter()
    # Attribute an interval to the preceding observed state, not to pure CPU work.
    for previous, current in zip(gates, gates[1:]):
        d = previous['details']
        state = ('dependency' if not d['dependencies_ready'] else
                 'stream_scope' if not d['scope_ready'] else
                 'near_collision' if not d['nearby_collision_ready'] else 'ready')
        segments[state] += (current['start_us'] - previous['start_us']) / 1000
    tail = [e for e in gates if ready and e['start_us'] > ready['start_us']]
    rows.append({
        'name': path.stem, 'entry_ms': data['entry_ms'], 'safety_ms': (safe-core)/1000,
        'dependencies_observed_ready_after_core_ms': (ready['start_us']-core)/1000 if ready else None,
        'dependencies_observed_ready_to_safety_ms': (safe-ready['start_us'])/1000 if ready else None,
        'gate_count': len(gates), 'tail_gate_count': len(tail), 'trace_dropped': trace.get('dropped'),
        'observed_state_interval_ms': dict(segments),
        'tail_gate_direct_time_ms': {key: sum(e['details'][key] for e in tail)/1000
                                     for key in ('dependency_gate_us', 'sync_us', 'ready_gate_us')},
        'last_gate': gates[-1]['details'],
        'flags': {k: data.get(k) for k in ('deferred_native_preparation', 'deferred_native_budget', 'deferred_ready_worker_yield', 'prepared_collision_faces', 'collision_face_prefetch')},
        'failures': data['failures'], 'formal_sha': data['formal_sha'], 'map_sha': data['map_sha'],
    })
output = Path(__file__).with_name('final_gates.json')
output.write_text(json.dumps({'notes': ['Gate intervals include frame pacing, rendering and other callbacks; they are not CPU idle time.',
                                      'Dependency completion is first observed at a gate, not the exact worker completion timestamp.'],
                              'runs': rows}, indent=2), encoding='utf-8')
for row in rows:
    print(row['name'], round(row['entry_ms'], 3), round(row['safety_ms'], 3),
          row['tail_gate_count'], row['last_gate'].get('face_prefetch', {}))
