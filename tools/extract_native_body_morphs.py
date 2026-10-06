"""Inventory source morphs and stage a bounded initial set, without changing the body.

Use the existing UnityPy environment. Formula-driven entries remain source data,
not enabled sliders, until joint/dependency evaluation has been implemented.
"""
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

import UnityPy
from art_paths import art_path

source = Path('D:/Games/vamzhb/VaM_Data/StreamingAssets/f_mb')
body_path = art_path('characters/source_models/vam_base_reference/female/original_data.json')
body = json.loads(body_path.read_text(encoding='utf-8'))['geometry_component']
topology = json.loads(art_path('characters/base/female_base_v2/female_display_topology.json').read_text())
assert body['geometryId'] == 'GenesisFemale-1'
points = [[v[a] for a in 'xyz'] for v in body['_baseVertices']]
assert points == topology['points'], 'Current control topology differs from approved original coordinates/order'
output = art_path('characters/morphs/female_base_v2/source_native_01')
output.mkdir(parents=True, exist_ok=True)
selected = {'PBMBreastsSize': 'bust_size', 'PBMHipSize': 'hip_size',
            'PBMWaistWidth': 'waist_width', 'PHMNoseWidth': 'nose_width', 'FBMHeight': 'height'}
records = []
payloads = {}
for obj in UnityPy.load(str(source)).objects:
    if obj.type.name != 'MonoBehaviour':
        continue
    for index, morph in enumerate(obj.read_typetree().get('_morphs', [])):
        deltas = morph['deltas']
        bad = [d['vertex'] for d in deltas if not 0 <= d['vertex'] < len(points)]
        finite = all(math.isfinite(d['delta'][a]) for d in deltas for a in 'xyz')
        duplicate = len(deltas) != len({d['vertex'] for d in deltas})
        # Repeated indices can legitimately accumulate; flag them, do not
        # mistake a source additive list for a corrupt one-value-per-index map.
        valid = not bad and finite and len(deltas) == morph['numDeltas']
        record = {k: morph[k] for k in ['morphName', 'displayName', 'overrideName', 'region', 'isPoseControl', 'min', 'max', 'numDeltas']}
        record.update(component_id=str(obj.path_id), index=index, formula_count=len(morph['formulas']),
                      formula_types=dict(Counter(f['targetType'] for f in morph['formulas'])),
                      structurally_valid=valid, out_of_range=len(bad), duplicate_indices=duplicate)
        records.append(record)
        if morph['morphName'] in selected:
            key = selected[morph['morphName']]
            assert valid and not duplicate and key not in payloads, 'Initial source entry needs additive-index handling or disambiguation'
            payload = {'id': key, 'source': record, 'default': morph['startValue'],
                       'deltas': deltas, 'formulas': morph['formulas'],
                       'coordinate_convention': 'Original source XYZ; identical to approved control positions',
                       'status': 'staged, not runtime/UI accepted'}
            encoded = json.dumps(payload).encode('utf-8')
            (output / f'{key}.json').write_bytes(encoded)
            payloads[key] = {'file': f'{key}.json', 'sha256': hashlib.sha256(encoded).hexdigest()}
assert len(payloads) == len(selected)
report = {'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'body_source_sha256': hashlib.sha256(body_path.read_bytes()).hexdigest(),
          'vertex_count': len(points), 'entries': records, 'initial_payloads': payloads,
          'status': 'Source inventory only; structural range checks do not prove visual/joint/garment compatibility'}
(output / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('Inventoried', len(records), 'source morphs;', sum(r['structurally_valid'] for r in records),
      'structurally valid;', len(payloads), 'initial payloads staged, no UI changes')
