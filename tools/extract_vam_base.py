"""Read original VaM body data; never modify the installation or game assets.

Requires UnityPy 1.25.3. Blender conversion is a separate explicit step.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import UnityPy


def extract(source: Path, output: Path, gender: str):
    env = UnityPy.load(str(source))
    components = {
        obj.path_id: obj.read_typetree()
        for obj in env.objects if obj.type.name == 'MonoBehaviour'
    }
    candidates = [(key, data) for key, data in components.items()
                  if data.get('geometryId') in ('GenesisFemale-1', 'Genesis2Male')]
    assert len(candidates) == 1, 'Expected one original ungrafted base body'
    key, body = candidates[0]
    skins = [d for d in components.values()
             if d.get('dazMesh', {}).get('m_PathID') == key and 'nodes' in d]
    assert len(skins) == 1
    vertices, faces = body['_baseVertices'], body['_basePolyList']
    uv_faces, uvs = body['_UVPolyList'], body['_OrigUV']
    assert len(vertices) == body['_numBaseVertices']
    assert len(faces) == body['_numBasePolygons'] == len(uv_faces)
    assert len(uvs) == body['_numUVVertices']
    for p, uvp in zip(faces, uv_faces):
        assert len(p['vertices']) == len(uvp['vertices']) >= 3
        assert all(0 <= i < len(vertices) for i in p['vertices'])
        assert all(0 <= i < len(uvs) for i in uvp['vertices'])
        assert 0 <= p['materialNum'] < len(body['_materialNames'])
        # UV seam duplicates must map to the same original surface point.
        for vi, ui in zip(p['vertices'], uvp['vertices']):
            assert max(abs(vertices[vi][a] - body['_UVVertices'][ui][a]) for a in 'xyz') < 1e-6
    assert all(math.isfinite(v[a]) for v in vertices for a in 'xyz')
    output.mkdir(parents=True, exist_ok=True)
    raw = {'gender': gender, 'source': str(source),
           'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
           'geometry_component': body, 'skin_component': skins[0]}
    (output / 'original_data.json').write_text(json.dumps(raw), encoding='utf-8')
    # Existing garments can target the merged topology rather than the clean
    # base. Preserve that reference separately; never silently reuse indices.
    merged = [data for data in components.values()
              if '_baseVertices' in data and ':' in data.get('geometryId', '')]
    for data in merged:
        (output / 'merged_binding_reference.json').write_text(json.dumps(data), encoding='utf-8')
    # OBJ uses original Unity coordinates here; Blender conversion explicitly
    # maps Y-up to Z-up. Separate position/UV indices retain source topology.
    with (output / 'base_original.obj').open('w', encoding='utf-8') as f:
        f.write('# Original base, Unity Y-up coordinates; UV seams preserved\n')
        for v in vertices: f.write('v %.9g %.9g %.9g\n' % (v['x'], v['y'], v['z']))
        for uv in uvs: f.write('vt %.9g %.9g\n' % (uv['x'], uv['y']))
        previous = None
        for p, uvp in zip(faces, uv_faces):
            material = body['_materialNames'][p['materialNum']]
            if material != previous:
                f.write('g ' + material + '\n'); previous = material
            f.write('f ' + ' '.join(f'{i+1}/{u+1}' for i, u in zip(p['vertices'], uvp['vertices'])) + '\n')
    stats = {'geometry': body['geometryId'], 'base_vertices': len(vertices),
             'polygons': len(faces), 'quads': sum(len(p['vertices']) == 4 for p in faces),
             'uv_vertices': len(uvs), 'materials': body['_materialNames'],
             'weight_nodes': skins[0]['_numBones'],
             'bounds': {a: [min(v[a] for v in vertices), max(v[a] for v in vertices)] for a in 'xyz'},
             'rig_status': 'Original axis-specific weights saved; no reconstructed armature yet',
             'source_sha256': raw['sha256']}
    (output / 'validation.json').write_text(json.dumps(stats, indent=2), encoding='utf-8')
    print(gender, stats['base_vertices'], 'vertices', stats['quads'], 'quads; UV correspondence PASS', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vam-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / '.gdignore').touch()
    for gender, bundle in [('female', 'f_c'), ('male', 'm_c')]:
        extract(args.vam_root / 'VaM_Data/StreamingAssets' / bundle, args.output / gender, gender)
