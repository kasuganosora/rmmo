"""Read-only final guild GLB costs/identity audit; writes isolated per-asset reports.

CPU measurements here are source bytes and decoded image bytes, never VRAM/RSS.
Native/visual/HTTP claims remain bound to their own exact-SHA production reports.
"""
import argparse
import collections
import datetime
import hashlib
import io
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
DEFAULT_OUT = REPO / 'review_artifacts/guild_reference_recheck_20261013/resource_audit'
COMPONENTS = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def parse(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw), 'invalid GLB header'
    offset, chunks = 12, {}
    while offset < length:
        size, kind = struct.unpack_from('<II', raw, offset)
        assert offset + 8 + size <= length, 'invalid chunk length'
        chunks[kind] = raw[offset + 8:offset + 8 + size]
        offset += size + 8
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b''), sha(raw), len(raw)


def values(doc, binary, index):
    a = doc['accessors'][index]
    assert 'sparse' not in a, 'sparse accessor requires separate audit'
    v = doc['bufferViews'][a['bufferView']]
    dtype, width = np.dtype(COMPONENTS[a['componentType']]), WIDTHS[a['type']]
    stride = v.get('byteStride', width * dtype.itemsize)
    local = a.get('byteOffset', 0)
    assert stride >= width * dtype.itemsize, 'short accessor stride'
    assert local + max(0, a['count'] - 1) * stride + (width * dtype.itemsize if a['count'] else 0) <= v['byteLength'], 'accessor exceeds bufferView'
    return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
                      offset=v.get('byteOffset', 0) + local, strides=(stride, dtype.itemsize))


def nested(value, key):
    if isinstance(value, dict):
        if key in value:
            yield value[key]
        for child in value.values():
            yield from nested(child, key)
    elif isinstance(value, list):
        for child in value:
            yield from nested(child, key)


def image_info(doc, binary, index, decoded_cache):
    item = doc['images'][index]
    view = doc['bufferViews'][item['bufferView']]
    encoded = binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]
    digest = sha(encoded)
    if digest not in decoded_cache:
        with Image.open(io.BytesIO(encoded)) as pic:
            rgba = pic.convert('RGBA')
            width, height = rgba.size
            decoded_cache[digest] = dict(encoded_sha256=digest, encoded_bytes=len(encoded),
                rgba_pixel_sha256=sha(rgba.tobytes()), width=width, height=height,
                decoded_rgba_bytes=width * height * 4,
                estimated_rgba8_full_mips_bytes=sum(max(1, width >> i) * max(1, height >> i) * 4
                                                   for i in range(int(math.log2(max(width, height))) + 1)))
    return dict(index=index, name=item.get('name'), **decoded_cache[digest])


def bone_revision(doc, binary, source):
    result = {}
    for index, image in enumerate(doc.get('images', [])):
        if image.get('name') not in ('bone_color_v2', 'bone_rough_v2'):
            continue
        name = image['name']
        v = doc['bufferViews'][image['bufferView']]
        embedded = binary[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
        source_map = source / 'materials' / (name + '.png')
        with Image.open(io.BytesIO(embedded)) as got, Image.open(source_map) as expected:
            # Blender packs roughness into glTF metallic/roughness G; original is gray.
            actual_pixels = got.convert('RGB') if name == 'bone_color_v2' else got.convert('RGB').getchannel('G')
            expected_pixels = expected.convert('RGB') if name == 'bone_color_v2' else expected.convert('RGB').getchannel('R')
            result[name] = dict(source=str(source_map), source_encoded_sha256=file_sha(source_map),
                embedded_encoded_sha256=sha(embedded), pixel_sha256=sha(actual_pixels.tobytes()),
                source_pixel_sha256=sha(expected_pixels.tobytes()), pixels_match=actual_pixels.size == expected_pixels.size and actual_pixels.tobytes() == expected_pixels.tobytes(),
                comparison='RGB' if name == 'bone_color_v2' else 'glTF G roughness vs source R')
    return result


def audit(row, source, out, decoded_cache):
    path = Path(row['path'])
    doc, binary, digest, size = parse(path)
    failures, notes = [], []
    if digest != row['sha256']:
        failures.append('Actual source SHA differs from final manifest')
    if list(nested(doc, 'uri')):
        failures.append('External or URI resource needs explicit dependency audit')
    for view in doc.get('bufferViews', []):
        if view.get('buffer', 0) != 0 or view.get('byteOffset', 0) + view['byteLength'] > len(binary):
            failures.append('bufferView outside embedded buffer')
    arrays = {}
    for i, a in enumerate(doc.get('accessors', [])):
        try:
            arrays[i] = values(doc, binary, i)
            if arrays[i].dtype.kind == 'f' and not np.isfinite(arrays[i]).all():
                failures.append(f'Nonfinite accessor {i}')
        except Exception as error:
            failures.append(f'Accessor {i}: {error}')
    mesh_rows = []
    for mi, mesh in enumerate(doc.get('meshes', [])):
        triangles, vertices = 0, 0
        for pi, primitive in enumerate(mesh.get('primitives', [])):
            attrs = primitive.get('attributes', {})
            if 'POSITION' not in attrs:
                failures.append(f'Mesh {mi} primitive {pi}: missing POSITION')
                continue
            count = doc['accessors'][attrs['POSITION']]['count']
            vertices += count
            indices = arrays.get(primitive.get('indices'))
            index_count = len(indices) if indices is not None else count
            mode = primitive.get('mode', 4)
            if mode == 4:
                triangles += index_count // 3
                if index_count % 3:
                    failures.append(f'Mesh {mi} primitive {pi}: incomplete triangle')
            elif mode in (5, 6):
                triangles += max(0, index_count - 2)
            else:
                notes.append(f'Mesh {mi} primitive {pi}: nontriangle primitive mode {mode}')
            if indices is not None and indices.size and (indices.min() < 0 or indices.max() >= count):
                failures.append(f'Mesh {mi} primitive {pi}: index outside vertex array')
            for key, accessor in attrs.items():
                if doc['accessors'][accessor]['count'] != count:
                    failures.append(f'Mesh {mi} primitive {pi}: attribute {key} length mismatch')
        mesh_rows.append(dict(index=mi, name=mesh.get('name'), triangles=triangles, vertices=vertices, surfaces=len(mesh.get('primitives', []))))
    extras = collections.Counter()
    collision, lod_triangles, lod_nodes = collections.Counter(), collections.Counter(), collections.Counter()
    semantics, instances, surfaces = [], 0, 0
    for node in doc.get('nodes', []):
        e = node.get('extras', {})
        extras.update(e.keys())
        if 'mesh' not in node:
            continue
        mesh = mesh_rows[node['mesh']]
        instances += mesh['triangles']
        surfaces += mesh['surfaces']
        collision[str(e.get('rmmo_collision', 'legacy_adapter/default'))] += 1
        level = str(e.get('lod_level', 'unlevelled'))
        lod_triangles[level] += mesh['triangles']
        lod_nodes[level] += 1
        semantics.append(dict(name=node.get('name'), mesh=node['mesh'], triangles=mesh['triangles'],
            collision=e.get('rmmo_collision'), collision_review=e.get('collision_review'),
            group=e.get('semantic_group'), lod_level=e.get('lod_level'), visibility_range=e.get('rmmo_visibility_range'),
            auto_lod=e.get('rmmo_auto_lod'), hinge=e.get('rmmo_hinge'), door_pose=e.get('door_pose')))
    images = [image_info(doc, binary, i, decoded_cache) for i in range(len(doc.get('images', [])))]
    unique = {i['encoded_sha256']: i for i in images}
    bone = bone_revision(doc, binary, source)
    if row['id'] in ('axel_guild_repaired', 'guild_hanging_skeleton'):
        if len(bone) != 2 or not all(x['pixels_match'] for x in bone.values()):
            failures.append('Latest bone v2 color/roughness pixels are missing or mismatched')
    if row['id'] == 'guild_alarm_tower' and dict(lod_nodes) != {'0': 12, '1': 12, '2': 12}:
        failures.append('Tower does not contain exactly 12 meshes per LOD and no unlevelled duplicates')
    previous = source.parent / 'repair_v2' / ('library/' + path.name if path.parent.name == 'library' else path.name)
    prior_sha = file_sha(previous) if previous.exists() else None
    baseline = dict(path=str(previous), sha256=prior_sha, same_source=digest == prior_sha)
    if baseline['same_source']:
        optimization = 'Unchanged accepted source. Reuse prior visual/LOD decision; current shared production import/native contract still needs binding.'
    elif lod_nodes.get('0'):
        optimization = 'Authored explicit LOD levels retained. Verify same-camera transition silhouette and common range bounds in GPU review; total stored triangles are not simultaneous visible triangles.'
    elif extras.get('rmmo_auto_lod'):
        optimization = 'Source requests existing automatic LOD. Derived native per-surface LOD counts and visual acceptance belong to the production review report.'
    else:
        optimization = 'No forced decimation. Review cost and silhouette at intended viewing distance; a new LOD is warranted only if measured scale/cost justifies it.'
    report = dict(id=row['id'], source_path=str(path), source_sha256=digest, source_bytes=size,
        source_manifest_sha256=row['sha256'], source_manifest_match=digest == row['sha256'],
        source_master=row.get('source_master'), baseline=baseline,
        mesh_resources=len(mesh_rows), mesh_nodes=sum(lod_nodes.values()), unique_mesh_triangles=sum(m['triangles'] for m in mesh_rows),
        instanced_all_lod_triangles=instances, authored_surface_instances_all_lod=surfaces,
        material_count=len(doc.get('materials', [])), texture_entries=len(doc.get('textures', [])), image_entries=len(images),
        unique_encoded_images=len(unique), unique_encoded_image_bytes=sum(i['encoded_bytes'] for i in unique.values()),
        unique_decoded_rgba_bytes=sum(i['decoded_rgba_bytes'] for i in unique.values()),
        estimated_rgba8_full_mips_bytes=sum(i['estimated_rgba8_full_mips_bytes'] for i in unique.values()),
        measured_rss_bytes=None, measured_vram_bytes=None, actual_draw_calls=None,
        budget_note='RGBA8 full-mip and decoded values are conservative image budgets, not measured RSS/VRAM. They do not include native mesh/collision admission; equal images across files do not prove runtime resource sharing.',
        extension_declarations=doc.get('extensionsUsed', []), required_extensions=doc.get('extensionsRequired', []),
        extras_counts=dict(extras), collision_modes=dict(collision), explicit_lod_mesh_nodes=dict(lod_nodes), explicit_lod_triangles=dict(lod_triangles),
        bone_v2_pixel_confirmation=bone, meshes=mesh_rows, mesh_semantics=semantics, images=images,
        optimization_assessment=optimization, static_errors=failures, notes=notes,
        stages={'source_resource_audit': 'passed' if not failures else 'failed', 'visual': 'pending current-SHA GPU/human review',
                'production_native_and_HTTP': 'pending exact-SHA final import report; no inherited native cost mixed into source result',
                'formal_map_integration': 'pending; isolated review is not map publication'},
        source_stable_during_audit=file_sha(path) == digest)
    if not report['source_stable_during_audit']:
        failures.append('Source changed during audit')
        report['stages']['source_resource_audit'] = 'failed'
    (out / (row['id'] + '.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', type=Path, default=DEFAULT_SOURCE)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    # Only isolated report roots may be written.
    resolved = args.out.resolve()
    allowed = [REPO / 'review_artifacts', Path('D:/code/rmmo_runtime/review_artifacts')]
    assert any(resolved.is_relative_to(p.resolve()) for p in allowed), 'output must stay in review_artifacts'
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.source_dir / 'repair_manifest.json').read_text('utf8'))
    rows = [dict(id='axel_guild_repaired', path=str(args.source_dir / 'axel_guild_repaired.glb'),
                 sha256=manifest['final_sha256'], source_master=manifest['source_master']),
            dict(id='guild_alarm_tower', **manifest['tower'])]
    rows += [dict(id=r['asset_id'], **r) for r in manifest['library']]
    decoded_cache, reports = {}, []
    for row in rows:
        r = audit(row, args.source_dir, args.out, decoded_cache)
        reports.append(r)
        print(r['id'], r['source_sha256'][:12], 'errors=' + str(len(r['static_errors'])), flush=True)
    aggregate = dict(timestamp=datetime.datetime.now().astimezone().isoformat(),
        source_manifest=str(args.source_dir / 'repair_manifest.json'), source_manifest_sha256=file_sha(args.source_dir / 'repair_manifest.json'),
        asset_count=len(reports), unchanged_vs_v2=sum(r['baseline']['same_source'] for r in reports),
        source_bytes_sum=sum(r['source_bytes'] for r in reports), unique_cross_file_encoded_images=len(decoded_cache),
        unique_cross_file_decoded_rgba_bytes=sum(i['decoded_rgba_bytes'] for i in decoded_cache.values()),
        unique_cross_file_rgba8_full_mips_budget=sum(i['estimated_rgba8_full_mips_bytes'] for i in decoded_cache.values()),
        cross_file_sharing_note='Byte/pixel identity is a lower bound on unique content; no runtime sharing or actual memory saving claimed.',
        static_passed=all(not r['static_errors'] for r in reports),
        items=[dict(id=r['id'], sha256=r['source_sha256'], report=str(args.out / (r['id'] + '.json')), static_errors=r['static_errors'],
                    source_bytes=r['source_bytes'], triangles=r['instanced_all_lod_triangles'], rgba8_mips_budget=r['estimated_rgba8_full_mips_bytes']) for r in reports],
        generator_source_sha256={str(p.relative_to(REPO)):file_sha(p) for p in [REPO/'scripts/world3d/compiled_asset_cache.gd',REPO/'scripts/world3d/gltf_map_io.gd',REPO/'scripts/world3d/tinted_glass.gd']},
        formal_library_modified=False, production_map_modified=False)
    (args.out / 'index.json').write_text(json.dumps(aggregate, ensure_ascii=False, indent=2), encoding='utf8')
    print('GUILD_SOURCE_AUDIT', json.dumps({k:aggregate[k] for k in ['asset_count','unchanged_vs_v2','static_passed','source_bytes_sum','unique_cross_file_decoded_rgba_bytes']}))
    raise SystemExit(0 if aggregate['static_passed'] else 1)


if __name__ == '__main__':
    main()
