"""Prepare SHA-pinned realism review plans; GPU work is explicit and serial.

This round intentionally changes goods/cloth appearance. Numeric image differences
are diagnostic, never an acceptance threshold. No formal library/map writes here.
"""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import io
import json
import re
import struct
import subprocess
import time

from PIL import Image
from run_godot_background import run_background

ROOT = Path('D:/code/rmmo')
RUNTIME = Path('D:/code/rmmo_runtime')
ART = RUNTIME / 'art_sources/axel_market_realism_20261016'
REVIEW = RUNTIME / 'review_artifacts/axel_market_realism_20261016'
BASE = RUNTIME / 'review_artifacts/axel_market_optimization_20261016'
PUBLICATION = BASE / 'publication/publish03/publication.json'
LIBRARY = RUNTIME / 'packs/default/assets/library.json'
ENGINE = Path('D:/tools/godot/Godot_v4.7.2-stable_win64.exe')
SCRIPT = 'res://tools/review_axel_market_realism_20261016.gd'
IDS = ['pottery', 'scroll', 'potion', 'ore']


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def put(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def active_gpu():
    command = "Get-CimInstance Win32_Process | Where-Object {($_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless') -or $_.Name -like '*blender*'} | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
    result = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', command], capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else []


def resolved(value):
    path = Path(value)
    return path if path.is_absolute() else LIBRARY.parent / path


def confined(path, parent):
    return Path(path).resolve().is_relative_to(parent.resolve())


def uv_sampling_proof(doc, binary, primitive):
    """Exact corner-position/UV pairing, independent of reindexing/winding."""
    def accessor(index):
        row = doc['accessors'][index]
        if 'sparse' in row or row.get('normalized'):
            raise ValueError('UV review requires an explicit adapter for sparse/normalized accessors')
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[row['type']]
        fmt, size = {5121: ('B', 1), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}[row['componentType']]
        view = doc['bufferViews'][row['bufferView']]
        offset = view.get('byteOffset', 0) + row.get('byteOffset', 0)
        stride = view.get('byteStride', width * size)
        return [struct.unpack_from('<' + fmt * width, binary, offset + i * stride) for i in range(row['count'])]
    attrs = primitive['attributes']
    if 'TEXCOORD_0' not in attrs:
        raise ValueError('Textured primitive has no consumable TEXCOORD_0')
    positions, uvs = accessor(attrs['POSITION']), accessor(attrs['TEXCOORD_0'])
    if len(positions) != len(uvs):
        raise ValueError('Position/UV vertex count mismatch')
    indices = [v[0] for v in accessor(primitive['indices'])] if 'indices' in primitive else list(range(len(positions)))
    paired = [struct.pack('<5f', *(0.0 if value == 0 else value for value in (*positions[i], *uvs[i]))).hex() for i in indices]
    paired.sort()
    triangles = sorted(','.join(map(str, sorted(indices[i:i + 3]))) for i in range(0, len(indices), 3))
    return {'corners': len(indices), 'vertices': len(positions), 'position_uv_corner_sha256': hashlib.sha256('\n'.join(paired).encode('ascii')).hexdigest(), 'triangle_vertex_sets_sha256': hashlib.sha256('\n'.join(triangles).encode('ascii')).hexdigest(), 'position_f32_base64': base64.b64encode(b''.join(struct.pack('<3f', *v) for v in positions)).decode('ascii'), 'uv0_f32_base64': base64.b64encode(b''.join(struct.pack('<2f', *v) for v in uvs)).decode('ascii'), 'position_range': [max(v[k] for v in positions) - min(v[k] for v in positions) for k in range(3)], 'uv_range': [max(v[k] for v in uvs) - min(v[k] for v in uvs) for k in range(2)], 'encoding': 'Source float32 vertex pairing and orientation-independent triangle vertex sets; raw corner hash retained diagnostically. Actual renderer may quantize position/UV; bounded per-vertex error is verified separately.'}


def glb_expectations(path):
    """CPU source pixels and all active PBR channels, without re-encoding assets."""
    data = Path(path).read_bytes()
    magic, version, total = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or total != len(data):
        raise ValueError(f'Invalid GLB header: {path}')
    offset = 12
    doc = None
    binary = b''
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        chunk = data[offset + 8:offset + 8 + size]
        if len(chunk) != size:
            raise ValueError('Truncated GLB chunk')
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    if doc is None or any('uri' in b for b in doc.get('buffers', [])):
        raise ValueError('Closed embedded GLB required')
    image_rows = []
    for index, image in enumerate(doc.get('images', [])):
        if 'bufferView' not in image:
            raise ValueError('External/data-URI image needs an explicit adapter; no silent omission')
        view = doc['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        raw = binary[start:start + view['byteLength']]
        with Image.open(io.BytesIO(raw)) as im:
            im.load()
            rgba = im.convert('RGBA')
            width, height = im.size
            mip_pixels = 0
            w, h = width, height
            while True:
                mip_pixels += w * h
                if w == h == 1:
                    break
                w, h = max(1, w // 2), max(1, h // 2)
            image_rows.append({'index': index, 'name': image.get('name', ''), 'mime_type': image.get('mimeType', ''), 'encoded_sha256': hashlib.sha256(raw).hexdigest(), 'encoded_bytes': len(raw), 'width': width, 'height': height, 'rgba8_sha256': hashlib.sha256(rgba.tobytes()).hexdigest(), 'rgba8_bytes': width * height * 4, 'rgba8_mip_budget_bytes': mip_pixels * 4})
    pending = list(doc['scenes'][doc.get('scene', 0)]['nodes'])
    reachable = set()
    while pending:
        index = pending.pop()
        if index in reachable:
            continue
        reachable.add(index)
        pending.extend(doc['nodes'][index].get('children', []))
    active = set()
    optics_by_material = {}
    surfaces = 0
    triangles = 0
    for index in reachable:
        node = doc['nodes'][index]
        if 'mesh' not in node:
            continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            if primitive.get('mode', 4) != 4:
                raise ValueError('Non-triangle primitive needs explicit audit')
            surfaces += 1
            accessor = primitive.get('indices', primitive['attributes']['POSITION'])
            triangles += doc['accessors'][accessor]['count'] // 3
            if 'material' in primitive:
                active.add(primitive['material'])
                material_name = doc['materials'][primitive['material']].get('name', '')
                optical = node.get('extras', {}).get('rmmo_tinted_glass', {}).get('materials', {}).get(material_name)
                if optical is not None:
                    optics_by_material.setdefault(primitive['material'], []).append(optical)
    materials = []
    active_images = set()
    for index in sorted(active):
        material = doc['materials'][index]
        pbr = material.get('pbrMetallicRoughness', {})
        channels = {}
        for role, texture in [('albedo', pbr.get('baseColorTexture')), ('normal', material.get('normalTexture')), ('roughness', pbr.get('metallicRoughnessTexture')), ('metallic', pbr.get('metallicRoughnessTexture')), ('ao', material.get('occlusionTexture')), ('emission', material.get('emissiveTexture'))]:
            if texture is None:
                continue
            source_index = doc['textures'][texture['index']].get('source')
            if source_index is None:
                raise ValueError('Extended texture source needs explicit active-binding adapter')
            active_images.add(source_index)
            channels[role] = {key: image_rows[source_index][key] for key in ['index', 'width', 'height', 'rgba8_sha256']}
            channels[role]['texcoord'] = texture.get('texCoord', 0)
            channels[role]['texture_transform'] = texture.get('extensions', {}).get('KHR_texture_transform')
            if channels[role]['texcoord'] != 0 or channels[role]['texture_transform'] is not None:
                raise ValueError(f'{path.name}: {material.get("name")} {role} requires an unproven UV mapping. This fixed market export contract requires TEXCOORD_0 and no KHR_texture_transform; remap actual atlas coordinates before review.')
        primitive_uv = []
        if channels:
            for node_index in sorted(reachable):
                node = doc['nodes'][node_index]
                if 'mesh' not in node:
                    continue
                for primitive in doc['meshes'][node['mesh']]['primitives']:
                    if primitive.get('material') == index:
                        primitive_uv.append(uv_sampling_proof(doc, binary, primitive))
        materials.append({'index': index, 'name': material.get('name', ''), 'normal_scale': material.get('normalTexture', {}).get('scale', 1), 'normal_enabled': 'normalTexture' in material, 'roughness_factor': pbr.get('roughnessFactor', 1), 'metallic_factor': pbr.get('metallicFactor', 1), 'base_color_factor': pbr.get('baseColorFactor', [1, 1, 1, 1]), 'alpha_mode': material.get('alphaMode', 'OPAQUE'), 'double_sided': material.get('doubleSided', False), 'channels': channels, 'extensions': material.get('extensions', {}), 'explicit_optics_surface_recipes': optics_by_material.get(index, []), 'primitive_uv_sampling': primitive_uv})
    names = [m['name'] for m in materials]
    if any(not name for name in names) or len(names) != len(set(names)):
        raise ValueError('Active materials require distinct names for exact runtime channel attribution')
    unique = {image_rows[i]['rgba8_sha256']: image_rows[i] for i in active_images}
    return {'source_sha256': hashlib.sha256(data).hexdigest(), 'source_bytes': len(data), 'materials': materials, 'images': image_rows, 'active_image_indices': sorted(active_images), 'active_surface_instances': surfaces, 'visible_lod0_triangle_instances': triangles, 'active_unique_rgba8_bytes': sum(x['rgba8_bytes'] for x in unique.values()), 'active_unique_rgba8_mip_budget_bytes': sum(x['rgba8_mip_budget_bytes'] for x in unique.values()), 'cost_limit': 'Decoded/mip budgets only; neither measured RSS nor VRAM. Native cost comes from actual isolated engine run.'}


def prepare(candidate_list, plan_version="v1"):
    if not re.fullmatch(r"v[1-9][0-9]*", plan_version):
        raise ValueError("Plan version must be v1, v2, ...")
    if not confined(candidate_list, ART):
        raise ValueError('Candidate manifest must remain in this task art root')
    candidates = read(candidate_list)
    current_masters = candidates.get('source_masters', []) if isinstance(candidates, dict) else []
    preview_recipe = candidates.get('preview_recipe') if isinstance(candidates, dict) else None
    if preview_recipe:
        expected_helper = ROOT / 'scripts/world_editor/asset_preview_environment.gd'
        if Path(preview_recipe['path']).resolve() != expected_helper.resolve() or sha(expected_helper) != preview_recipe['sha256']:
            raise ValueError('Preview reflection helper identity mismatch')
    if isinstance(candidates, dict):
        if 'candidates' in candidates and 'assets' in candidates:
            raise ValueError('Ambiguous candidate rows: provide candidates or assets, not both')
        candidates = candidates.get('candidates', candidates.get('assets'))
        if not isinstance(candidates, list):
            raise ValueError('Candidate manifest needs candidates or assets array')
    by_id = {row['asset']: row for row in candidates}
    if len(candidates) != 4 or set(by_id) != set(IDS):
        raise ValueError('Exactly four unique candidates required')
    publication = read(PUBLICATION)
    if not publication.get('ok') or not publication.get('catalog_committed'):
        raise ValueError('Baseline publication must have completed')
    baseline = {row['asset']: row for row in publication['mapping']}
    library = read(LIBRARY)
    rows = []
    for asset in IDS:
        item = by_id[asset]
        old = baseline[asset]
        candidate = Path(item['candidate'])
        if not confined(candidate, ART) or candidate.suffix.lower() != '.glb':
            raise ValueError('Candidate outside this task root or not GLB')
        if sha(candidate) != item['candidate_sha256'] or sha(old['new_glb']) != old['candidate_sha256']:
            raise ValueError('Candidate/baseline SHA mismatch')
        if sha(old['new_asset_id']) != old['prefab_sha256']:
            raise ValueError('Baseline prefab SHA mismatch')
        hits = [(i, e) for i, e in enumerate(library) if resolved(e.get('prefab_path', '')) == Path(old['new_asset_id'])]
        if len(hits) != 1:
            raise ValueError('Baseline prefab must still occupy one current formal slot')
        slot, entry = hits[0]
        payload = read(old['new_asset_id'])
        if len(payload.get('records', [])) != 1 or resolved(payload['records'][0]['asset_path']) != Path(old['new_glb']):
            raise ValueError('One exact baseline record required')
        replacement = copy.deepcopy(payload)
        replacement['records'][0]['asset_path'] = item['candidate_sha256'] + '.glb'
        row = {'asset': asset, 'label': entry['label'], 'source': old['new_glb'], 'source_sha256': old['candidate_sha256'], 'source_bytes': Path(old['new_glb']).stat().st_size, 'candidate': candidate.as_posix(), 'candidate_sha256': item['candidate_sha256'], 'candidate_bytes': candidate.stat().st_size, 'existing_prefab': {'catalog_index': slot, 'entry': entry, 'prefab_path': old['new_asset_id'], 'prefab_sha256': old['prefab_sha256'], 'prefab': payload, 'old_asset_id': old['new_asset_id']}, 'candidate_payload_template': replacement, 'prospective_formal_glb': (LIBRARY.parent / (item['candidate_sha256'] + '.glb')).as_posix(), 'expected_materials': {case: glb_expectations(path) for case, path in [('baseline', old['new_glb']), ('candidate', candidate)]}, 'allowed_changes': 'User-directed goods geometry, cloth drape/PBR, and Structure wood UV/PBR refinement. Structure position/topology is preserved per builder source audit; its UV/material bytes are intentionally changed. Goods may gain material groups (including PaperSheet) and primitives. Appearance differences and source-cost increases are allowed, not automatic acceptance. Prefab UUID/transform/bounds/origin and structural use remain fixed.'}
        rows.append(row)
    baseline_review = read(BASE / 'publication/publish03/publication.json')
    masters = copy.deepcopy(baseline_review.get('source_masters', []))
    for master in masters:
        if sha(master['file']) != master['sha256']:
            raise ValueError('Historical source master SHA mismatch')
        master['role'] = 'historical baseline mother asset retained for rollback'
    for entry in current_masters:
        path = Path(entry.get('path', entry.get('file', '')))
        historical = next((master for master in masters if Path(master['file']).resolve() == path.resolve()), None)
        if historical is not None:
            if entry['sha256'] != historical['sha256'] or sha(path) != historical['sha256']:
                raise ValueError('Repeated historical source master SHA mismatch')
            continue
        if not path.is_file() or not (confined(path, ART) or confined(path, ROOT)):
            raise ValueError('Current source master/evidence must be a concrete task-art or repo file')
        if sha(path) != entry['sha256']:
            raise ValueError('Current source master/evidence SHA mismatch')
        masters.append({'file': path.as_posix(), 'sha256': entry['sha256'], 'bytes': path.stat().st_size, 'preserved_in_place': True, 'role': entry.get('role', 'current realism master or reproducibility evidence')})
    common = {'version': 1, 'scope': 'Intentional realism refinement, not lossless optimization; no map writes', 'baseline_publication': {'path': PUBLICATION.as_posix(), 'sha256': sha(PUBLICATION)}, 'candidates_manifest': {'path': Path(candidate_list).as_posix(), 'sha256': sha(candidate_list)}, 'catalog_before': {'path': LIBRARY.as_posix(), 'sha256': sha(LIBRARY)}, 'source_masters': masters, 'preview_recipe': preview_recipe, 'rows': rows}
    review = dict(common, status='PREPARED_NOT_RUN', render={'width': 1400, 'height': 1000, 'views': ['near', 'medium', 'far', 'back', 'cloth_detail', 'goods_detail', 'structure_detail', 'cloth_raking', 'goods_raking', 'glass_bright', 'glass_dark', 'liquid_surface'], 'glass_views': 'potion only; explicit neutral background card behind goods plus elevated liquid-surface view', 'comparison': 'Identical cameras/lights; difference metrics are diagnostic only; human review required', 'actual_binding': 'Reopened prepared scene get_active_material -> Texture2D.get_image RGBA8 SHA versus GLB source channel pixels, normal_enabled/scale/tangents. Explicit rmmo_tinted_glass replacement is separately checked as multiply transmission plus additive dielectric reflection; deliberately cleared albedo/emission textures are not missing-texture failures.', 'upload': 'Original dimensions, lossy WebP quality 90 with SHA receipt'})
    for filename, value in [('review_plan.json', review), ('publication_plan.json', dict(common, status='PREPARED_NOT_PUBLISHED'))]:
        path = ART / plan_version / filename
        if path.exists() and read(path) != value:
            raise ValueError(f'Existing frozen plan differs: {path}; preserve it and use a new task version/root')
        if not path.exists():
            put(path, value)
    return review


def run(args, plan):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', args.take):
        raise ValueError('Take must be an identifier')
    folder = REVIEW / args.take
    if folder.exists():
        raise ValueError('Use a new take; previous evidence is immutable')
    if active_gpu():
        raise RuntimeError('GPU queue not released')
    selected = IDS if args.assets is None else args.assets.split(',')
    if not selected or len(selected) != len(set(selected)) or any(value not in IDS for value in selected):
        raise ValueError('Explicit comma-separated unique market asset IDs required')
    folder.mkdir(parents=True)
    status = {'state': 'starting', 'jobs': [], 'selected_assets': selected, 'plan_sha256': sha(ART / args.plan_version / 'review_plan.json'), 'formal_writes': False}
    try:
        for row in plan['rows']:
            asset = row['asset']
            if asset not in selected:
                continue
            for case in ['baseline', 'candidate', 'compare']:
                if case != 'compare' and active_gpu():
                    raise RuntimeError('Another graphics process appeared; stop serial queue')
                command = [str(ENGINE), *(['--headless'] if case == 'compare' else []), '--path', str(ROOT), '--script', SCRIPT, '--', f'--asset={asset}', f'--case={case}', f'--take={args.take}', f'--plan-version={args.plan_version}']
                status.update(state='running', asset=asset, case=case)
                put(folder / 'status.json', status)
                began = time.time()
                result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=args.timeout) if case == 'compare' else run_background(command, cwd=ROOT, timeout=args.timeout)
                destination = folder / asset
                destination.mkdir(exist_ok=True)
                log = (result.stdout or b'') + (getattr(result, 'stderr', None) or b'')
                (destination / (case + '.log')).write_bytes(log)
                clean = not re.search(rb'(?m)^(?:SCRIPT ERROR|ERROR):', log)
                report_path = destination / (case + '.json')
                report = read(report_path) if report_path.exists() else {}
                status['jobs'].append({'asset': asset, 'case': case, 'returncode': result.returncode, 'engine_error_free': clean, 'elapsed_seconds': time.time() - began})
                put(folder / 'status.json', status)
                if result.returncode or not clean or not report.get('passed'):
                    raise RuntimeError(f'{asset}/{case} failed; local evidence retained')
            spec = importlib.util.spec_from_file_location('review_image', 'C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            receipts = [module.prepare(png, lossless=False, keep_source=False, quality=90) for png in sorted((folder / asset).glob('*/*.png'))]
            put(folder / asset / 'image_upload_receipts.json', receipts)
            lookup = {Path(v['source']).as_posix(): v for v in receipts}
            for case in ['baseline', 'candidate']:
                path = folder / asset / (case + '.json')
                report = read(path)
                for shot in report['screenshots']:
                    receipt = lookup[Path(shot['path']).as_posix()]
                    shot['local_png_sha256'] = shot['file_sha256']
                    shot.update(path=receipt['path'], file_sha256=receipt['sha256'], upload_encoding={'quality': 90, 'lossless': False, 'dimensions': receipt['dimensions']})
                report['visual_inspection'] = 'PENDING actual viewing against intended realism changes'
                put(path, report)
        status['state'] = 'completed_awaiting_visual_inspection'
    except Exception as error:
        status.update(state='failed', error=str(error))
        raise
    finally:
        put(folder / 'status.json', status)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', type=Path)
    parser.add_argument('--plan-version', default='v1')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--assets', help='Explicit subset for incremental GPU review, e.g. scroll,ore; omitted reviews all four')
    parser.add_argument('--take', default='gpu_realism01')
    parser.add_argument('--timeout', type=int, default=1200)
    parser.add_argument('--gpu-status', action='store_true')
    args = parser.parse_args()
    if args.gpu_status:
        print(json.dumps({'graphics_processes': active_gpu(), 'gpu_started': False}))
        return
    if not re.fullmatch(r'v[1-9][0-9]*', args.plan_version):
        raise ValueError('Plan version must be v1, v2, ...')
    plan = read(ART / args.plan_version / 'review_plan.json') if args.run else prepare(args.candidates or ART / args.plan_version / 'candidates.json', args.plan_version)
    if args.run:
        run(args, plan)
    print(json.dumps({'plan': str(ART / args.plan_version / 'review_plan.json'), 'publication_plan': str(ART / args.plan_version / 'publication_plan.json'), 'pairs': len(plan['rows']), 'gpu_started': args.run, 'visual_accepted': False, 'formal_writes': False}))


if __name__ == '__main__':
    main()
