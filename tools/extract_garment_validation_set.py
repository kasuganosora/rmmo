"""Extract a varied local garment corpus with original maps, wrap records and provenance."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile
from art_paths import art_path
from inspect_vam_clothing import decode

PACKAGES = {
    'GaryHo.maid_cloth_v1.2.var': ('maid_classic', '女仆连衣裙：袖口、领口、裙摆'),
    'AmineKunai.Maid_Costume_Set.1.var': ('maid_separate', '分体女仆装：上衣、裙子、头饰、袜子'),
    'AmineKunai.Pleated_Skirt.1.var': ('skirt_pleated', '百褶裙：褶皱保持与腿部碰撞'),
    'AmineKunai.Short_Pencil_Skirt.1.var': ('skirt_pencil', '包臀裙：髋部、迈步与坐姿'),
    'maru01.dress_l01_V2.4.var': ('dress_long', '连衣裙双版本：多层裙摆、领口与蝴蝶结'),
    'JD.Elf_Dress_Set.1.var': ('dress_elf', '及地精灵裙：复杂轮廓、地面与多部位约束'),
    'maru01.dressM08.4.var': ('dress_layered', '连衣裙：自由布料与层间关系'),
    'maru01.HW_dress02.2.var': ('dress_ruffle_layers', '泡袖束腰裙：独立外裙、荷叶边与帽饰'),
}

root = art_path('characters/source_models/garment_validation_set')
root.mkdir(parents=True, exist_ok=True)
catalog = []
for package, (key, purpose) in PACKAGES.items():
    source = Path('D:/Games/vamzhb/AddonPackages') / package
    folder = root / key
    folder.mkdir(exist_ok=True)
    with zipfile.ZipFile(source) as archive:
        meta = json.loads(archive.read('meta.json'))
        entries = [name for name in archive.namelist() if name.endswith('.vab')]
        # This corpus tests outer garments; unrelated underwear is not needed.
        if key == 'dress_elf': entries = [n for n in entries if '/Elf Dress/' in n]
        if key == 'dress_layered': entries = [n for n in entries if '/dressM08/' in n]
        if key == 'dress_ruffle_layers':
            entries = [n for n in entries if any('/' + part + '/' in n for part in ['hw_dress02', 'hw_dress02_skirt', 'HW_hat2025'])]
        record = {'id': key, 'purpose': purpose, 'package': package,
                  'package_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                  'author': package.split('.')[0], 'license': meta.get('licenseType'), 'items': []}
        (folder / 'source_meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
        for number, entry in enumerate(entries):
            item = folder / f'item_{number:02d}'
            item.mkdir(exist_ok=True)
            parent = PurePosixPath(entry).parent
            # Copy only the garment's original directory; never unpack arbitrary archive paths.
            files = {}
            for name in archive.namelist():
                if PurePosixPath(name).parent != parent or name.endswith('/'): continue
                basename = PurePosixPath(name).name
                if ':' in basename or '\\' in basename or basename in ['.', '..']: raise ValueError(name)
                data = archive.read(name)
                (item / basename).write_bytes(data)
                files[basename] = {'member': name, 'sha256': hashlib.sha256(data).hexdigest()}
            decoded = decode(archive.read(entry))
            settings = json.loads((item / PurePosixPath(entry).with_suffix('.vaj').name).read_text(encoding='utf-8-sig'))
            texture_references = []
            for storable in settings.get('storables', []):
                for field, value in storable.items():
                    if (field.startswith('customTexture_') or field == 'simTexture') and value:
                        if not (item / value).is_file(): raise FileNotFoundError(f'{entry}: {field}: {value}')
                        texture_references.append(value)
            (item / 'clothing_data.json').write_text(json.dumps(decoded), encoding='utf-8')
            obj = item / 'garment_original.obj'
            with obj.open('w', encoding='utf-8') as f:
                for p in decoded['vertices']: f.write('v %g %g %g\n' % tuple(p))
                for p in decoded['uv']: f.write('vt %g %g\n' % tuple(p))
                for face, uvface in zip(decoded['faces'], decoded['uv_faces']):
                    f.write('g ' + decoded['materials'][face['material']] + '\n')
                    f.write('f ' + ' '.join(f'{v+1}/{uv+1}' for v, uv in zip(face['vertices'], uvface['vertices'])) + '\n')
            bindings = decoded['bindings']
            summary = {'folder': item.name, 'entry': entry, 'vertices': len(decoded['vertices']),
                       'polygons': len(decoded['faces']), 'uv_bindings': len(bindings),
                       'bindings_outside_clean_body': sum(max(b[1:4]) >= 21556 for b in bindings),
                       'max_body_index': max(max(b[1:4]) for b in bindings),
                       'verified_texture_references': sorted(set(texture_references)),
                       'unparsed_tail_bytes': decoded['unparsed_tail_bytes'], 'files': files}
            (item / 'manifest.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
            record['items'].append(summary)
        catalog.append(record)
        print('PASS', key, len(record['items']), 'garments', record['license'])
(root / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
print('EXTRACTED', len(catalog), 'sets;', sum(len(r['items']) for r in catalog), 'meshes; source archives untouched')
