"""Extract the real guild record into a fresh external test map; never import GLB."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf'))
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    target = args.out.resolve()
    cache = Path('D:/code/rmmo_runtime/cache/world3d').resolve()
    if not target.is_relative_to(cache) or target == cache:
        parser.error('--out must be a fresh directory under rmmo_runtime/cache/world3d')
    if target.exists():
        parser.error('--out already exists; use a new directory')
    source_sha = digest(source)
    data = json.loads(source.read_text(encoding='utf-8'))
    world = data['nodes'][data['scenes'][data.get('scene', 0)]['nodes'][0]]
    extra = world['extras']
    records = [r for r in extra['rmmo_records'] if r.get('uuid') == 'obj_1033']
    proxies = [n for n in data['nodes'] if n.get('extras', {}).get('uuid') == 'obj_1033']
    if len(records) != 1 or len(proxies) != 1 or not proxies[0].get('extras', {}).get('rmmo_proxy'):
        raise RuntimeError('Expected one real obj_1033 guild record and proxy')
    record = copy.deepcopy(records[0])
    if record.get('rotation') != [0, 0, 0] or record.get('size') != [1, 1, 1]:
        raise RuntimeError('Fixture camera coordinates require the current unrotated, unit-scale guild')
    ref = record['rmmo_ref']
    ref_source = (source.parent / ref['uri']).resolve(strict=True)
    if not ref_source.is_relative_to(source.parent) or ref_source.stat().st_size != ref['length']:
        raise RuntimeError('Guild reference must be an unchanged adjacent resource')
    # Retain native model identity and collision annotations inside the original
    # reference bytes. The ordinary game loader resolves this reference itself.
    position = record['position']
    spawn = [position[0] + 16.0, position[1] + 1.15, position[2] - 4.6]
    retained = {k: copy.deepcopy(extra[k]) for k in ('rmmo_format', 'rmmo_version', 'rmmo_unit', 'rmmo_storage')}
    retained.update({
        'name': 'Guild night camera regression',
        'map_ref': 'test/guild_night_camera',
        'spawn': spawn,
        'rmmo_records': [record],
        'rmmo_resource_dependencies': {ref['uri']: ref['sha256']},
        'environment': {
            'preset': 'night', 'time_hours': 22.0, 'time_speed': 0.0,
            'celestial_cycle': False, 'sun_energy': 0.12,
            'ambient_color': [0.78, 0.82, 0.9], 'ambient_energy': 0.08,
            'sky_enabled': True, 'weather': 'clear', 'environment_audio': False,
            'wind_speed': 0.0, 'sun_shadows': True, 'ambient_occlusion': True,
            'outline_enabled': True, 'interior_cutaway': False,
            'indirect_screen_light': False, 'interior_reflection': False,
        },
    })
    data['nodes'] = [{'name': world['name'], 'extras': retained, 'children': [1]}, copy.deepcopy(proxies[0])]
    data['scenes'] = [{'nodes': [0]}]
    data['scene'] = 0
    # Original proxy accessors/materials and its embedded geometry buffer remain
    # valid; no external model is copied, rebuilt, or mutated.
    if any('uri' in b and not b['uri'].startswith('data:') for b in data.get('buffers', [])):
        raise RuntimeError('Expected embedded proxy buffers')
    target.mkdir(parents=True)
    ref_target = target / ref['uri']
    ref_target.parent.mkdir(parents=True)
    shutil.copyfile(ref_source, ref_target)
    map_path = target / 'map.gltf'
    map_path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    assert digest(source) == source_sha
    assert digest(ref_source) == digest(ref_target)
    manifest = {
        'source_map': str(source), 'source_map_sha256': source_sha,
        'map': str(map_path), 'map_sha256': digest(map_path),
        'source_record_uuid': 'obj_1033', 'source_position': position,
        'spawn': spawn, 'reference': str(ref_target), 'reference_sha256': digest(ref_target),
        'reference_bytes': ref_target.stat().st_size,
        'native_assets_shared_unchanged': True, 'formal_map_modified': False,
    }
    (target / 'fixture_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=True))


if __name__ == '__main__':
    main()
