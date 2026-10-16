"""Read-only CPU audit of the nine layout vegetation models and two existing alternatives.

No mesh generation, native compilation, catalog publication or map mutation.
Output goes to a new audit directory, never to previous acceptance evidence.
"""
import collections
import hashlib
import importlib.util
import io
import json
import sys
from pathlib import Path
from PIL import Image

ROOT = Path('D:/code/rmmo')
RUNTIME = Path('D:/code/rmmo_runtime')
OUT = RUNTIME / 'review_artifacts/axel_vegetation_resource_audit_20261017'
ASSETS = RUNTIME / 'packs/default/assets'
MAP = RUNTIME / 'packs/default/maps/axel_town/map.gltf'
INDEX = RUNTIME / 'review_artifacts/axel_town_layout_20261016/vegetation_reused_model_evidence.json'
HISTORY = ROOT / 'review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json'
RECEIPT = RUNTIME / 'review_artifacts/joint_model_validation_20261011/publish_preferred_v2_receipt.json'
spec = importlib.util.spec_from_file_location('audit_graph', ROOT / 'review_artifacts/town_asset_size_audit_20261011/architecture_lossless.py')
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)
Glb = graph.ref.Glb
sha = graph.ref.digest


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def identity(path):
    return {'path': path.as_posix(), 'sha256': sha(path), 'bytes': path.stat().st_size}


def json_sha(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def mip_budget(width, height):
    result = 0
    while True:
        result += width * height * 4
        if width == height == 1:
            return result
        width, height = max(1, width // 2), max(1, height // 2)


def slots(value, prefix=''):
    if isinstance(value, dict):
        for key, item in value.items():
            name = prefix + '/' + key
            if key.endswith('Texture') and isinstance(item, dict) and 'index' in item:
                yield name, item['index']
            else:
                yield from slots(item, name)
    elif isinstance(value, list):
        for i, item in enumerate(value):
            yield from slots(item, prefix + '/' + str(i))


def native_snapshot(path, expected):
    directory = RUNTIME / 'cache/world3d/compiled_assets_v1'
    key = hashlib.sha256(path.as_posix().encode()).hexdigest()
    manifest = directory / (key + '.json')
    result = {'scope': 'Existing disk cache snapshot only; no current-generator or runtime acceptance', 'manifest_path': manifest.as_posix()}
    if not manifest.exists():
        result['present'] = False
        return result
    index = read(manifest)
    result.update(present=True, manifest=identity(manifest), descriptor=index)
    payload = directory / (index['payload_sha'] + '.scn')
    result['payload_present'] = payload.exists()
    if payload.exists():
        result['payload'] = identity(payload)
        result['identity_valid'] = index['source_sha'] == expected and sha(payload) == index['payload_sha'] and payload.stat().st_size == index['bytes']
    footprint = directory / 'footprints_v1' / (key + '.json')
    if footprint.exists():
        envelope = read(footprint)
        body = envelope['body']
        result['footprint'] = identity(footprint)
        result['footprint_body_sha_valid'] = hashlib.sha256(body.encode()).hexdigest() == envelope['sha256']
        result['footprint_snapshot'] = json.loads(body)
    result['manifest_unchanged_during_read'] = result['manifest']['sha256'] == sha(manifest)
    return result


def audit(path):
    before = identity(path)
    source = Glb(path)
    try:
        j = source.j
        graph.guard_graph(j)
        use = graph.usage(j)  # All declared meshes, including every authored LOD.
        roles = collections.defaultdict(set)
        for material in use['materials']:
            for role, texture in slots(j['materials'][material]):
                roles[j['textures'][texture]['source']].add(role)
        stats = graph.stats(source)
        active = []
        for item in stats['images']:
            if not item['referenced']:
                continue
            raw = source.blob(j['images'][item['index']]['bufferView'])
            with Image.open(io.BytesIO(raw)) as image:
                image.load()
                item = dict(item, roles=sorted(roles[item['index']]), decoded_mode=image.mode,
                            decoded_pillow_pixel_bytes=len(image.tobytes()),
                            rgba8_mip_budget_bytes=mip_budget(*image.size))
                if any(role.endswith('/baseColorTexture') for role in item['roles']):
                    rgba = image.convert('RGBA')
                    item['rgba_pixel_sha256'] = hashlib.sha256(rgba.tobytes()).hexdigest()
                    item['alpha_range'] = list(rgba.getchannel('A').getextrema())
                    item['alpha_sha256'] = hashlib.sha256(rgba.getchannel('A').tobytes()).hexdigest()
            active.append(item)
        per_mesh = [sum(j['accessors'][p.get('indices', p['attributes']['POSITION'])]['count'] // 3 for p in mesh['primitives']) for mesh in j['meshes']]
        nodes = []
        for i, node in enumerate(j['nodes']):
            if 'mesh' in node:
                nodes.append({'index': i, 'name': node.get('name'), 'mesh': node['mesh'], 'triangles': per_mesh[node['mesh']], 'extras': node.get('extras', {})})
        static_samples = {}
        for distance in [0, 10, 30, 60, 110, 190]:
            count = 0
            for node in nodes:
                r = node['extras'].get('rmmo_visibility_range', {})
                if distance >= r.get('begin', 0) and (not r.get('end', 0) or distance < r['end']):
                    count += node['triangles']
            static_samples[str(distance)] = count
        active_unique = {x['sha256']: x for x in active}
        result = dict(before, stats=stats, active_images=active, mesh_nodes=nodes,
                      active_rgba8_mip_budget_bytes=sum(x['rgba8_mip_budget_bytes'] for x in active_unique.values()),
                      active_encoded_unique_bytes=sum(x['bytes'] for x in active_unique.values()),
                      source_authored_distance_triangle_counts=static_samples,
                      triangle_sample_limit='All declared mesh nodes; authored ranges only. Ignores bounds/scale, index LOD, occlusion and culling. Not measured draw counts.',
                      material_alpha_modes=[j['materials'][i].get('alphaMode', 'OPAQUE') for i in sorted(use['materials'])],
                      nodes_fingerprint=json_sha(j['nodes']),
                      cpu_resource_status='passed_read_only_inventory',
                      visual_status='not_retested', runtime_status='not_retested',
                      source_unchanged=sha(path) == before['sha256'])
        result['native_cache_snapshot'] = native_snapshot(path, before['sha256'])
        return result
    finally:
        source.close()


def catalogue_models(entry, chain=()):
    """Resolve only explicit asset_path/prefab_path fields, not arbitrary text."""
    found = set()
    if isinstance(entry, dict):
        for key, value in entry.items():
            if key in ('asset_path', 'prefab_path') and isinstance(value, str):
                path = Path(value)
                if not path.is_absolute():
                    path = ASSETS / path
                path = path.resolve()
                if not path.is_relative_to(ASSETS.resolve()):
                    continue
                if path.suffix == '.glb':
                    found.add(path.as_posix())
                elif path.suffix == '.json' and path.exists() and path not in chain:
                    found |= catalogue_models(read(path), chain + (path,))
            else:
                found |= catalogue_models(value, chain)
    elif isinstance(entry, list):
        for child in entry:
            found |= catalogue_models(child, chain)
    return found


def main():
    target = OUT / 'audit01.json'
    if target.exists():
        raise SystemExit('Use a new versioned output; do not overwrite audit evidence')
    snapshot = read(OUT / 'map_cpu01.json')
    map_before = sha(MAP)
    assert map_before == snapshot['map_sha256'], 'Map changed since CPU definition snapshot'
    catalog_path = ASSETS / 'library.json'
    catalog_before = identity(catalog_path)
    catalog = read(catalog_path)
    source_index = read(INDEX)
    history = read(HISTORY)
    publication = read(RECEIPT)
    sources = []
    for item in source_index['assets']:
        for model in item['models']:
            path = Path(model['path'])
            assert sha(path) == model['sha256']
            sources.append((item['label'], path))
    history_selected = [item for item in history['preferred'] if item['label'] in ('oak_9ba5457e', 'foliage_boxwood_pbr2k_albedo4k')]
    alternatives = []
    for preferred in history_selected:
        receipt = next(i for i in publication['imports'] if i['label'] == preferred['label'])
        path = Path(receipt['target'])
        assert sha(path) == preferred['candidate_sha256'] == receipt['expected_source_sha256']
        alternatives.append((preferred, receipt, path))
    models = []
    for label, path in sources + [(x[0]['label'], x[2]) for x in alternatives]:
        print('Auditing ' + label, flush=True)
        model = audit(path)
        model['label'] = label
        model['catalog_entries'] = [{'index': i, 'label': entry.get('label'), 'entry': entry} for i, entry in enumerate(catalog) if path.as_posix() in catalogue_models(entry)]
        models.append(model)
    records = read(MAP)['nodes'][0]['extras']['rmmo_records']
    definitions = snapshot['definitions']
    for model in models:
        matching = [record['uuid'] for record in records if definitions[record['rmmo_ref']['sha256']].get('asset_path', '').replace('\\', '/') == model['path']]
        model['formal_map_direct_record_count'] = len(matching)
        model['formal_map_direct_record_uuids'] = matching
    reuse = []
    for preferred, receipt, path in alternatives:
        old = next(m for m in models if m['sha256'] == preferred['original_sha256'])
        new = next(m for m in models if m['sha256'] == preferred['candidate_sha256'])
        a, b = Glb(Path(old['path'])), Glb(path)
        try:
            graph.guard_graph(a.j); graph.guard_graph(b.j)
            ag, bg = graph.graph(a), graph.graph(b)
            full_equal = ag == bg
            ageom, bgeom = graph.ref.semantic(a)['meshes'], graph.ref.semantic(b)['meshes']
            for meshes in (ageom, bgeom):
                for mesh in meshes:
                    for primitive in mesh['primitives']:
                        primitive.pop('material', None)
            base_a = [x['rgba_pixel_sha256'] for x in old['active_images'] if 'rgba_pixel_sha256' in x]
            base_b = [x['rgba_pixel_sha256'] for x in new['active_images'] if 'rgba_pixel_sha256' in x]
            reuse.append({'label': preferred['label'], 'original': old['path'], 'original_sha256': old['sha256'],
                          'existing_formal_alternative': new['path'], 'alternative_sha256': new['sha256'],
                          'kind': preferred['kind'], 'source_saved_bytes': old['bytes'] - new['bytes'],
                          'active_rgba8_mip_budget_saved_bytes': old['active_rgba8_mip_budget_bytes'] - new['active_rgba8_mip_budget_bytes'],
                          'full_resolved_graph_exact': full_equal, 'all_mesh_geometry_exact': ageom == bgeom,
                          'nodes_transforms_extras_exact': a.j['nodes'] == b.j['nodes'],
                          'basecolor_rgba_pixels_exact': base_a == base_b,
                          'prior_publication': {'receipt': identity(RECEIPT), 'historical_import_ok': receipt['import_ok']},
                          'prior_visual_review': identity(ROOT / 'review_artifacts/town_asset_size_audit_20261011/selected_visual_review.json'),
                          'current_scene_visual_runtime_status': 'pending; historical evidence does not establish this layout/current pipeline acceptance',
                          'map_direct_old_count': old['formal_map_direct_record_count'], 'map_direct_alternative_count': new['formal_map_direct_record_count']})
        finally:
            a.close(); b.close()
    map_after = sha(MAP)
    assert map_after == map_before and sha(catalog_path) == catalog_before['sha256'], 'Concurrent publication invalidates current snapshot'
    result = {'scope': 'Nine reused vegetation sources and two existing published alternatives; CPU audit only',
              'date': '2026-10-17', 'models': models, 'existing_alternative_reuse': reuse,
              'map_snapshot': {'path': MAP.as_posix(), 'sha256': map_before, 'unchanged': True,
                               'definition_snapshot': identity(OUT / 'map_cpu01.json'), 'records': len(records)},
              'catalog_snapshot': catalog_before, 'catalog_unchanged': True,
              'source_evidence': identity(INDEX), 'historical_handoff': identity(HISTORY),
              'formal_asset_or_map_changes': False, 'new_gpu_runs': 0,
              'limits': ['No actual RSS, VRAM, FPS or load-time measurement.',
                         'Active RGBA8+mips is a dimension-based budget with identical encoded images deduplicated, not measured Godot texture allocation.',
                         'Native files and footprint envelopes are existing on-disk snapshots, not proof of current-generator validity.',
                         'Reference counts cover explicit saved asset records; they are not simultaneous visible instances or draw calls.',
                         'No source, master, catalog, prefab, native payload or formal map is modified.']}
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'output': target.as_posix(), 'models': len(models), 'reuse': reuse}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
