"""Extract original material/texture references matching the approved base UVs.

Run in the existing UnityPy environment. No geometry or texture repainting.
"""
import hashlib
import json
from pathlib import Path

import UnityPy
from art_paths import art_path

root = Path('D:/Games/vamzhb/VaM_Data/StreamingAssets')
output = art_path('characters/materials/face_native_01')
output.mkdir(parents=True, exist_ok=True)
body = json.loads(art_path('characters/source_models/vam_base_reference/female/original_data.json').read_text())['geometry_component']
selected = {'Eyelashes', 'Cornea', 'EyeReflection', 'Tear', 'Gums', 'Tongue', 'Teeth', 'InnerMouth'}
environments = {name: UnityPy.load(str(root / name)) for name in ['f_c_mat', 'p_eye_mat']}
shader_env = UnityPy.load(str(root / 'z_sha'))
shaders = {o.path_id: o for o in shader_env.objects if o.type.name == 'Shader'}
materials = {o.path_id: o for o in environments['f_c_mat'].objects if o.type.name == 'Material'}
textures = {}
for name, env in environments.items():
    for obj in env.objects:
        if obj.type.name == 'Texture2D':
            textures[(name, obj.path_id)] = obj
report = {'id': 'face_native_01', 'source_kind': 'local original base material references; no new license grant',
          'sources': {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in environments}, 'materials': {}}
report['sources']['z_sha'] = hashlib.sha256((root / 'z_sha').read_bytes()).hexdigest()
for name, reference in zip(body['_materialNames'], body['materials']):
    if name not in selected:
        continue
    material = materials[reference['m_PathID']].read_typetree()
    entry = {'source_name': material['m_Name'], 'properties': material['m_SavedProperties'], 'textures': {}}
    shader_ref = material['m_Shader']
    assert shader_ref['m_FileID'] == 1, 'Resolve unexpected shader dependency before packaging'
    shader = shaders[shader_ref['m_PathID']].read()
    entry['shader'] = {'bundle': 'z_sha', 'path_id': str(shader_ref['m_PathID']), 'name': shader.m_ParsedForm.m_Name}
    for semantic, value in material['m_SavedProperties']['m_TexEnvs']:
        ref = value['m_Texture']
        if not ref['m_PathID']:
            continue
        assert ref['m_FileID'] in (0, 3), 'Unexpected dependency; resolve before extraction'
        bundle = 'f_c_mat' if ref['m_FileID'] == 0 else 'p_eye_mat'
        obj = textures[(bundle, ref['m_PathID'])]
        texture = obj.read()
        filename = f'{name}_{semantic}.png'
        texture.image.save(output / filename)
        entry['textures'][semantic] = {'file': filename, 'name': texture.m_Name,
            'path_id': str(obj.path_id), 'bundle': bundle, 'sha256': hashlib.sha256((output / filename).read_bytes()).hexdigest()}
    report['materials'][name] = entry
assert set(report['materials']) == selected
def exact_ids(value):
    # Godot JSON numbers are doubles; Unity object IDs require all 64 bits.
    if isinstance(value, dict):
        return {key: str(item) if key == 'm_PathID' else exact_ids(item) for key, item in value.items()}
    if isinstance(value, list):
        return [exact_ids(item) for item in value]
    if isinstance(value, tuple):
        return [exact_ids(item) for item in value]
    return value

(output / 'manifest.json').write_text(json.dumps(exact_ids(report), indent=2), encoding='utf-8')
print('PASS packaged', len(selected), 'original facial material records:', output)
