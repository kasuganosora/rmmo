"""Package the approved skin under project names, retaining provenance and hashes."""
import hashlib
import json
import shutil
from art_paths import art_path

reference = art_path('characters/source_models/vam_base_reference')
source = reference / 'skin_candidates/aimi_pale'
target = art_path('characters/materials/skin_porcelain_01')
target.mkdir(parents=True, exist_ok=True)
catalog = json.loads((source.parent / 'manifest.json').read_text(encoding='utf-8'))
entry = next(item for item in catalog if item['key'] == 'aimi_pale')
manifest = {'id': 'skin_porcelain_01', 'display_name': '瓷白肤色 01',
            'author': 'RenVR', 'source_package': entry['package'], 'license': entry['license'],
            'uv_layout': 'Genesis 2 Base Female', 'files': {},
            'changes': 'Renamed only; original texture pixels retained. Runtime PBR conversion documented in project.'}
for region in ['Face', 'Torso', 'Limbs']:
    for suffix, semantic in [('D', 'albedo'), ('N', 'normal'), ('G', 'gloss'), ('S', 'specular')]:
        old = f'{region}_{suffix}.jpg'
        new = f'{region.lower()}_{semantic}.jpg'
        shutil.copy2(source / old, target / new)
        manifest['files'][new] = {'source_member': entry['maps'][old],
                                  'sha256': hashlib.sha256((target / new).read_bytes()).hexdigest()}
(target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
body = art_path('characters/base/female_base_v2')
body.mkdir(parents=True, exist_ok=True)
shutil.copy2(reference / 'female/base_original.glb', body / 'female_base_v2.glb')
(body / 'manifest.json').write_text(json.dumps({
    'id': 'female_base_v2', 'source': 'VaM f_c / GenesisFemale-1',
    'source_record': 'characters/source_models/vam_base_reference/female/original_data.json',
    'sha256': hashlib.sha256((body / 'female_base_v2.glb').read_bytes()).hexdigest(),
    'status': 'Static material validation; no runtime skeleton or clothing binding yet',
    'skin': 'skin_porcelain_01'}, indent=2), encoding='utf-8')
print('Packaged female_base_v2 and skin_porcelain_01; 12 original 4K maps with provenance.')
