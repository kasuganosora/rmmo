"""Stage original face morphs on the accepted female control topology.
Uses the existing vam_extract_env; no source mesh edits or identity changes.
"""
import hashlib
import json
import math
from pathlib import Path
import UnityPy
from art_paths import art_path

source = Path('D:/Games/vamzhb/VaM_Data/StreamingAssets/f_mb')
inventory = json.loads(art_path('characters/morphs/female_base_v2/source_native_01/manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256(source.read_bytes()).hexdigest() == inventory['source_sha256']
names = [
    'PHMEyesClosedL', 'PHMEyesClosedR', 'PHMEyesSquintL', 'PHMEyesSquintR',
    'PHMBrowUpL', 'PHMBrowUpR', 'PHMBrowDownL', 'PHMBrowDownR',
    'PHMBrowInnerUpL', 'PHMBrowInnerUpR', 'PHMBrowSqueeze',
    'PHMMouthSmileSimpleL', 'PHMMouthSmileSimpleR', 'PHMMouthFrown',
    'PHMLipsPucker', 'PHMLipsPart', 'PHMMouthOpen',
    'PHMEyeLidsTopUpL', 'PHMEyeLidsTopUpR', 'PHMEyeLidsBottomDownL', 'PHMEyeLidsBottomDownR',
    'PHMCheekEyeFlexL', 'PHMCheekEyeFlexR', 'PHMBrowOuterDownL', 'PHMBrowOuterDownR', 'PHMBrowInnerDownL', 'PHMBrowInnerDownR',
    'VSMAA', 'VSMIY', 'VSMUW', 'VSMEH', 'VSMOW',
]
result = {}
for obj in UnityPy.load(str(source)).objects:
    if obj.type.name != 'MonoBehaviour':
        continue
    for morph in obj.read_typetree().get('_morphs', []):
        name = morph['morphName']
        if name not in names:
            continue
        assert name not in result
        deltas = {}
        for entry in morph['deltas']:
            index = int(entry['vertex'])
            assert 0 <= index < 21556
            value = [float(entry['delta'][axis]) for axis in 'xyz']
            assert all(math.isfinite(x) for x in value)
            previous = deltas.setdefault(index, [0.0, 0.0, 0.0])
            for axis in range(3):
                previous[axis] += value[axis]
        result[name] = {
            'display_name': morph['displayName'], 'min': morph['min'], 'max': morph['max'],
            'deltas': [[i, *v] for i, v in sorted(deltas.items())],
            'formulas': morph['formulas'],
            'runtime_eligible': not morph['formulas'],
        }
assert set(result) == set(names)
output = art_path('characters/expressions/female_base_v2/native_face_01.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({
    'vertex_count': 21556, 'source_sha256': inventory['source_sha256'],
    'coordinate_convention': 'Original source XYZ; additive before native axis deformation',
    'morphs': result, 'status': 'source staging only, not visual acceptance',
}, ensure_ascii=False), encoding='utf-8')
print(f'Staged {len(result)} original face morphs at {output}; formula-dependent entries require explicit joint handling')
