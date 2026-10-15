"""Build an isolated S2 green post, preserving the accepted S1 source.

CPU only. v1 preserves legacy channels; v2 repairs painted-wood PBR and trunk UVs;
v3 fixes branch cylinder seams and tangent handedness. Every prior candidate stays
available. Strict static-glTF parsing fails closed before reachability compaction.
"""
from __future__ import annotations
import copy
import hashlib
import io
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT.parent / "rmmo_runtime"
SOURCE = RUNTIME / "packs/default/assets/c20c78874ba2a1693d2d474f43d0ea8bc47958fa08b610e3b703e5570883a6ad.glb"
GREEN = RUNTIME / "art_sources/bridge_reference_scene_20261006/festival_post_green.glb"
OUT = RUNTIME / "art_sources/s2_green_pennant_post_20261015"
AUDIT = ROOT / "review_artifacts/s2_green_pennant_post_20261015/build_audit.json"
EXPECTED_SOURCE = SOURCE.stem
EXPECTED_GREEN = "9bfb3d27579dc368b4a52679aec53c5def5c8bffabe71ec7dcedda3b5d0b4450"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_glb(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from("<III", raw)
    assert (magic, version, size) == (0x46546C67, 2, len(raw))
    jl, jt = struct.unpack_from("<II", raw, 12)
    assert jt == 0x4E4F534A
    bl, bt = struct.unpack_from("<II", raw, 20 + jl)
    assert bt == 0x004E4942 and 28 + jl + bl == len(raw)
    return json.loads(raw[20:20 + jl]), bytearray(raw[28 + jl:]), raw


def write_glb(path, doc, binary):
    d = copy.deepcopy(doc)
    d['buffers'] = [{'byteLength': len(binary)}]
    js = json.dumps(d, ensure_ascii=False, separators=(',', ':')).encode('utf8')
    js += b' ' * (-len(js) % 4)
    payload = bytes(binary) + b'\0' * (-len(binary) % 4)
    raw = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(payload))
    raw += struct.pack('<II', len(js), 0x4E4F534A) + js
    raw += struct.pack('<II', len(payload), 0x004E4942) + payload
    path.write_bytes(raw)
    return sha(raw)


def view_bytes(d, b, index):
    v = d['bufferViews'][index]
    start = v.get('byteOffset', 0)
    assert v['buffer'] == 0 and 0 <= start <= len(b) - v['byteLength']
    return bytes(b[start:start + v['byteLength']])


def accessor(d, b, index):
    a = d['accessors'][index]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    dtype = np.dtype({5123: '<u2', 5125: '<u4', 5126: '<f4'}[a['componentType']])
    v = d['bufferViews'][a['bufferView']]
    stride = v.get('byteStride', width * dtype.itemsize)
    raw = view_bytes(d, b, a['bufferView'])
    return np.ndarray((a['count'], width), dtype=dtype, buffer=raw,
                      offset=a.get('byteOffset', 0), strides=(stride, dtype.itemsize)).copy()


def primitive_geometry(d, b, ni):
    n = d['nodes'][ni]
    assert not any(k in n for k in ('matrix', 'scale', 'rotation', 'children'))
    primitives = d['meshes'][n['mesh']]['primitives']
    assert len(primitives) == 1
    p = primitives[0]
    data = {k: accessor(d, b, v) for k, v in p['attributes'].items()}
    data['indices'] = accessor(d, b, p['indices']).reshape(-1, 3)
    data['world'] = data['POSITION'].astype(float) + np.array(n.get('translation', [0, 0, 0]))
    return data


def append_view(d, b, blob, target=None):
    b.extend(b'\0' * (-len(b) % 4))
    v = {'buffer': 0, 'byteOffset': len(b), 'byteLength': len(blob)}
    if target is not None:
        v['target'] = target
    d['bufferViews'].append(v)
    b.extend(blob)
    return len(d['bufferViews']) - 1


def append_accessor(d, b, arr, kind):
    dtype, component, target = ('<u2', 5123, 34963) if kind == 'SCALAR' else ('<f4', 5126, 34962)
    arr = np.asarray(arr, dtype=dtype)
    if kind == 'SCALAR':
        arr = arr.reshape(-1, 1)
    v = append_view(d, b, arr.tobytes(), target)
    a = {'bufferView': v, 'componentType': component, 'count': len(arr), 'type': kind,
         'min': arr.min(axis=0).tolist(), 'max': arr.max(axis=0).tolist()}
    d['accessors'].append(a)
    return len(d['accessors']) - 1


def texture_refs(material):
    refs = []
    for key in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
        if key in material:
            refs.append(material[key])
    pbr = material.get('pbrMetallicRoughness', {})
    for key in ('baseColorTexture', 'metallicRoughnessTexture'):
        if key in pbr:
            refs.append(pbr[key])
    return refs


def strict_schema(d):
    """Unknown reference-bearing structures abort; never guess that names are roots."""
    def allowed(value, keys, where):
        extra = set(value) - set(keys.split())
        assert not extra, f'Unknown fields {where}: {sorted(extra)}; compaction stopped'
    allowed(d, 'asset accessors bufferViews buffers images materials meshes nodes samplers scene scenes textures extensionsUsed', 'root')
    assert not d.get('extensionsUsed'), 'Extensions require an explicit dependency adapter'
    assert len(d['buffers']) == 1
    allowed(d['asset'], 'generator version copyright', 'asset')
    allowed(d['buffers'][0], 'byteLength', 'buffer')
    for a in d['accessors']:
        allowed(a, 'bufferView byteOffset componentType count max min normalized type name', 'accessor')
    for v in d['bufferViews']:
        allowed(v, 'buffer byteOffset byteLength byteStride target name', 'bufferView')
    for n in d['nodes']:
        allowed(n, 'mesh name translation rotation scale matrix children', 'node')
    for scene in d['scenes']:
        allowed(scene, 'name nodes', 'scene')
    for m in d['meshes']:
        allowed(m, 'name primitives', 'mesh')
        for p in m['primitives']:
            allowed(p, 'attributes indices material mode', 'primitive')
            allowed(p['attributes'], 'POSITION NORMAL TANGENT TEXCOORD_0 TEXCOORD_1 COLOR_0', 'attributes')
            assert p.get('mode', 4) == 4
    for m in d['materials']:
        allowed(m, 'name doubleSided alphaMode alphaCutoff normalTexture occlusionTexture emissiveTexture emissiveFactor pbrMetallicRoughness', 'material')
        allowed(m.get('pbrMetallicRoughness', {}), 'baseColorFactor baseColorTexture metallicFactor roughnessFactor metallicRoughnessTexture', 'pbr')
        for t in texture_refs(m):
            allowed(t, 'index texCoord scale strength', 'textureInfo')
    for t in d['textures']:
        allowed(t, 'sampler source name', 'texture')
    for im in d['images']:
        allowed(im, 'bufferView mimeType name', 'image')
    for s in d['samplers']:
        allowed(s, 'magFilter minFilter wrapS wrapT name', 'sampler')


def reachable(d):
    strict_schema(d)
    sets = {key: set() for key in ('nodes', 'meshes', 'materials', 'accessors', 'textures', 'images', 'samplers', 'bufferViews')}
    todo = [n for scene in d['scenes'] for n in scene['nodes']]
    while todo:
        i = todo.pop()
        if i in sets['nodes']:
            continue
        sets['nodes'].add(i)
        n = d['nodes'][i]
        todo.extend(n.get('children', []))
        if 'mesh' in n:
            sets['meshes'].add(n['mesh'])
    for i in sets['meshes']:
        for p in d['meshes'][i]['primitives']:
            sets['materials'].add(p['material'])
            sets['accessors'].update(p['attributes'].values())
            sets['accessors'].add(p['indices'])
    for i in sets['materials']:
        sets['textures'].update(t['index'] for t in texture_refs(d['materials'][i]))
    for i in sets['textures']:
        t = d['textures'][i]
        sets['images'].add(t['source'])
        if 'sampler' in t:
            sets['samplers'].add(t['sampler'])
    sets['bufferViews'].update(d['images'][i]['bufferView'] for i in sets['images'])
    sets['bufferViews'].update(d['accessors'][i]['bufferView'] for i in sets['accessors'])
    for key, indices in sets.items():
        assert all(isinstance(i, int) and 0 <= i < len(d[key]) for i in indices), key
    return {k: sorted(v) for k, v in sets.items()}


def compact(d, b):
    reach = reachable(d)
    maps = {k: {old: new for new, old in enumerate(v)} for k, v in reach.items()}
    out = copy.deepcopy(d)
    for k, inds in reach.items():
        out[k] = [copy.deepcopy(d[k][i]) for i in inds]
    for scene in out['scenes']:
        scene['nodes'] = [maps['nodes'][i] for i in scene['nodes']]
    for n in out['nodes']:
        if 'mesh' in n:
            n['mesh'] = maps['meshes'][n['mesh']]
        if 'children' in n:
            n['children'] = [maps['nodes'][i] for i in n['children']]
    for m in out['meshes']:
        for p in m['primitives']:
            p['material'] = maps['materials'][p['material']]
            p['indices'] = maps['accessors'][p['indices']]
            p['attributes'] = {k: maps['accessors'][v] for k, v in p['attributes'].items()}
    for m in out['materials']:
        for t in texture_refs(m):
            t['index'] = maps['textures'][t['index']]
    for t in out['textures']:
        t['source'] = maps['images'][t['source']]
        if 'sampler' in t:
            t['sampler'] = maps['samplers'][t['sampler']]
    for im in out['images']:
        im['bufferView'] = maps['bufferViews'][im['bufferView']]
    for a in out['accessors']:
        a['bufferView'] = maps['bufferViews'][a['bufferView']]
    binary = bytearray()
    for new, old in enumerate(reach['bufferViews']):
        blob = view_bytes(d, b, old)
        binary.extend(b'\0' * (-len(binary) % 4))
        out['bufferViews'][new]['byteOffset'] = len(binary)
        binary.extend(blob)
    out['buffers'][0]['byteLength'] = len(binary)
    reachable(out)
    return out, binary, maps


def closest_triangles(points, triangles):
    """Closest barycentric projection, including edge clamps; CPU triangle data only."""
    a, b, c = (triangles[:, i] for i in range(3))
    ab, ac = b - a, c - a
    aa, cc, acdot = (np.einsum('ij,ij->i', x, y) for x, y in ((ab, ab), (ac, ac), (ab, ac)))
    det = aa * cc - acdot * acdot
    results = []
    for p in points:
        ap = p - a
        da, dc = np.einsum('ij,ij->i', ap, ab), np.einsum('ij,ij->i', ap, ac)
        u = (da * cc - dc * acdot) / np.maximum(det, 1e-20)
        v = (dc * aa - da * acdot) / np.maximum(det, 1e-20)
        bary = np.stack([1 - u - v, u, v], axis=1)
        projected = a + u[:, None] * ab + v[:, None] * ac
        dist = ((projected - p) ** 2).sum(1)
        dist[(u < 0) | (v < 0) | (u + v > 1) | (det < 1e-15)] = np.inf
        best = int(np.argmin(dist)); bestdist = float(dist[best]); bestbary = bary[best]
        for ia, ib in ((0, 1), (1, 2), (2, 0)):
            start, delta = triangles[:, ia], triangles[:, ib] - triangles[:, ia]
            t = np.clip(np.einsum('ij,ij->i', p - start, delta) / np.maximum((delta ** 2).sum(1), 1e-20), 0, 1)
            ds = ((start + t[:, None] * delta - p) ** 2).sum(1)
            k = int(np.argmin(ds))
            if ds[k] < bestdist:
                best, bestdist = k, float(ds[k])
                bestbary = np.zeros(3); bestbary[ia] = 1 - t[k]; bestbary[ib] = t[k]
        results.append((math.sqrt(max(0, bestdist)), best, bestbary))
    return results


def branch_mesh(center, angle, height, length, phase, trunk, trunk_uv, trunk_faces, cap_uv):
    radial = np.array([math.cos(angle), 0., math.sin(angle)])
    axis = radial + np.array([0., .22, 0.]); axis /= np.linalg.norm(axis)
    u = np.cross(np.array([0., 1., 0.]), axis); u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    origin = center + radial * .158 + np.array([0., height, 0.])
    count = 16
    pos = []
    for row, (t, radius) in enumerate(zip([0., .31, .70, 1.], [.076, .071, .052, .046])):
        for i in range(count):
            a = i * math.tau / count
            r = radius * (1 + .065 * math.sin(3 * a + phase) + .025 * math.cos(5 * a - phase))
            point = origin + axis * length * t + r * (u * math.cos(a) + v * math.sin(a))
            pos.append(point)
    faces = []
    for row in range(3):
        for i in range(count):
            j = (i + 1) % count; a = row * count + i; b = row * count + j
            faces.extend([(a, b, b + count), (a, b + count, a + count)])
    pos = np.array(pos)
    normals = np.zeros_like(pos)
    for f in faces:
        p = pos[list(f)]; n = np.cross(p[1] - p[0], p[2] - p[0])
        for i in f:
            normals[i] += n
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    # Project side UVs onto the same source trunk atlas, preserving its grain scale.
    project = pos.copy(); delta = project[:, [0, 2]] - center[[0, 2]]
    project[:, [0, 2]] = center[[0, 2]] + delta / np.linalg.norm(delta, axis=1)[:, None] * .235
    uv = []
    for _, face, bary in closest_triangles(project, trunk[trunk_faces]):
        uv.append(bary @ trunk_uv[trunk_faces[face]])
    uv = np.array(uv)
    # Closed planar ends: duplicate rim vertices only for hard cap normals.
    cap_center = cap_uv.mean(axis=0)
    cap_radius = float(np.min(np.linalg.norm(cap_uv - cap_center, axis=1))) * .72
    for row, direction in ((0, -1), (3, 1)):
        rim = pos[row * count:(row + 1) * count].copy()
        base = len(pos); ctr = rim.mean(axis=0)
        pos = np.vstack([pos, rim, ctr])
        normals = np.vstack([normals, np.tile(axis * direction, (count + 1, 1))])
        cap_coords = np.array([cap_center + cap_radius * np.array([math.cos(i * math.tau / count), math.sin(i * math.tau / count)]) for i in range(count)])
        uv = np.vstack([uv, cap_coords, cap_center])
        for i in range(count):
            j = (i + 1) % count
            faces.append((base + count, base + i, base + j) if direction > 0 else (base + count, base + j, base + i))
    return pos, normals, uv, np.array(faces, dtype=np.uint16), {'angle_degrees': math.degrees(angle), 'height_m': height, 'length_m': length, 'root_center': origin.tolist(), 'end_center': (origin + axis * length).tolist(), 'root_radius_m': .076, 'end_radius_m': .046}


def triangle_intersections(tri_a, tri_b):
    count = 0
    low, high = tri_b.min(1), tri_b.max(1)
    for ta in tri_a:
        keep = np.all(high >= ta.min(0) - 1e-8, axis=1) & np.all(low <= ta.max(0) + 1e-8, axis=1)
        candidates = tri_b[keep]
        if not len(candidates):
            continue
        for one, others in ((ta, candidates),):
            for k in range(3):
                if segment_hits(one[k], one[(k + 1) % 3], others):
                    count += 1; break
            else:
                for other in candidates:
                    if any(segment_hits(other[k], other[(k + 1) % 3], ta[None, :]) for k in range(3)):
                        count += 1; break
    return count


def segment_hits(start, end, triangles):
    direction = end - start
    e1, e2 = triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]
    h = np.cross(np.broadcast_to(direction, e2.shape), e2)
    a = np.einsum('ij,ij->i', e1, h)
    safe = np.abs(a) > 1e-12
    f = np.divide(1., a, out=np.zeros_like(a), where=safe)
    s = start - triangles[:, 0]
    u = f * np.einsum('ij,ij->i', s, h)
    q = np.cross(s, e1)
    v = f * (q @ direction)
    t = f * np.einsum('ij,ij->i', e2, q)
    return bool(np.any(safe & (u >= -1e-8) & (v >= -1e-8) & (u + v <= 1 + 1e-8) & (t >= -1e-8) & (t <= 1 + 1e-8)))


def image_audit(d, b):
    active = set(reachable(d)['images']); images = []
    for i, im in enumerate(d['images']):
        blob = view_bytes(d, b, im['bufferView'])
        p = Image.open(io.BytesIO(blob)); p.load()
        w, h = p.size; mip_bytes = 0
        while True:
            mip_bytes += w * h * 4
            if w == h == 1:
                break
            w, h = max(1, w // 2), max(1, h // 2)
        images.append({'index': i, 'name': im.get('name'), 'active': i in active, 'encoded_sha256': sha(blob),
                       'encoded_bytes': len(blob), 'dimensions': list(p.size), 'mode': p.mode,
                       'decoded_bytes': len(p.tobytes()), 'decoded_rgba_sha256': sha(p.convert('RGBA').tobytes()),
                       'rgba8_full_mips_budget_bytes': mip_bytes})
    return images


def semantic(d, b):
    rows = []
    for ni in reachable(d)['nodes']:
        n = d['nodes'][ni]
        if 'mesh' not in n:
            continue
        g = primitive_geometry(d, b, ni)
        p = d['meshes'][n['mesh']]['primitives'][0]
        m = copy.deepcopy(d['materials'][p['material']])
        for t in texture_refs(m):
            tex = d['textures'][t['index']]; im = d['images'][tex['source']]
            t['image_sha256'] = sha(view_bytes(d, b, im['bufferView']))
            t['sampler'] = copy.deepcopy(d['samplers'][tex['sampler']]) if 'sampler' in tex else None
            del t['index']
        rows.append({'node': copy.deepcopy({k: v for k, v in n.items() if k != 'mesh'}),
                     'geometry_sha256': {k: sha(v.tobytes()) for k, v in g.items()}, 'material': m})
    return rows


def model_audit(path, repeating_uv=False):
    d, b, raw = read_glb(path); reach = reachable(d)
    rows = []; worlds = []
    for ni in reach['nodes']:
        g = primitive_geometry(d, b, ni); worlds.append(g['world'])
        faces = g['world'][g['indices']]
        areas = np.linalg.norm(np.cross(faces[:, 1] - faces[:, 0], faces[:, 2] - faces[:, 0]), axis=1) * .5
        normal_lens = np.linalg.norm(g['NORMAL'], axis=1)
        assert all(np.isfinite(v).all() for v in g.values())
        assert areas.min() > 1e-10 and normal_lens.min() > .99 and normal_lens.max() < 1.01
        if not repeating_uv:
            assert g['TEXCOORD_0'].min() >= 0 and g['TEXCOORD_0'].max() <= 1
        rows.append({'name': d['nodes'][ni]['name'], 'triangles': len(faces), 'vertices': len(g['world']),
                     'min_triangle_area_m2': float(areas.min()), 'normal_length_range': [float(normal_lens.min()), float(normal_lens.max())],
                     'uv_min': g['TEXCOORD_0'].min(0).tolist(), 'uv_max': g['TEXCOORD_0'].max(0).tolist()})
    points = np.vstack(worlds); images = image_audit(d, b)
    active = [im for im in images if im['active']]
    assert abs(points[:, 1].min()) < 1e-6
    return {'path': str(path), 'sha256': sha(raw), 'bytes': len(raw), 'counts': {k: len(d[k]) for k in reach},
            'reachable': reach, 'parts': rows, 'triangles': sum(row['triangles'] for row in rows),
            'world_bounds_min': points.min(0).tolist(), 'world_bounds_max': points.max(0).tolist(),
            'world_size': (points.max(0) - points.min(0)).tolist(), 'images': images,
            'active_decoded_bytes': sum(im['decoded_bytes'] for im in active),
            'active_rgba8_full_mips_budget_bytes': sum(im['rgba8_full_mips_budget_bytes'] for im in active),
            'gpu_rss_vram_measured': False}


def main():
    protected = [SOURCE, GREEN, RUNTIME / 'packs/default/assets/library.json',
                 RUNTIME / 'packs/default/assets/prefabs/ae8388b77fc7239fd2dfafc9fd540cd596a14c1b9e759c9a7b85e6635ecc9c4a.json']
    guards = {str(p): sha(p.read_bytes()) for p in protected}
    assert guards[str(SOURCE)] == EXPECTED_SOURCE and guards[str(GREEN)] == EXPECTED_GREEN
    source, binary, _ = read_glb(SOURCE); green, gb, _ = read_glb(GREEN)
    strict_schema(source); strict_schema(green)
    doc = copy.deepcopy(source); buf = bytearray(binary)
    body_i = next(i for i, n in enumerate(doc['nodes']) if n['name'] == 'PostBody')
    silk_i = next(i for i, n in enumerate(doc['nodes']) if n['name'] == 'GoldSilk')
    body = primitive_geometry(doc, buf, body_i); silk = primitive_geometry(doc, buf, silk_i)
    body_mi = doc['meshes'][doc['nodes'][body_i]['mesh']]['primitives'][0]['material']
    green_body = next(n for n in green['nodes'] if n['name'] == 'PostBody')
    green_mat = green['materials'][green['meshes'][green_body['mesh']]['primitives'][0]['material']]
    green_tex = green['textures'][green_mat['pbrMetallicRoughness']['baseColorTexture']['index']]
    green_im = green['images'][green_tex['source']]
    green_blob = view_bytes(green, gb, green_im['bufferView'])
    vi = append_view(doc, buf, green_blob)
    doc['images'].append({'bufferView': vi, 'mimeType': green_im['mimeType'], 'name': 'S2_existing_green_wood_albedo'})
    tex = copy.deepcopy(doc['textures'][doc['materials'][body_mi]['pbrMetallicRoughness']['baseColorTexture']['index']])
    tex['source'] = len(doc['images']) - 1; doc['textures'].append(tex)
    doc['materials'][body_mi]['pbrMetallicRoughness']['baseColorTexture']['index'] = len(doc['textures']) - 1
    doc['materials'][body_mi]['name'] = 'S2 green timber; retained natural-post normal and ORM'
    base_points = np.unique(body['world'][np.abs(body['world'][:, 1]) < 1e-6], axis=0)
    center = base_points.mean(0); center[1] = 0
    cap_uv = body['TEXCOORD_0'][body['NORMAL'][:, 1] > .9]
    silk_tris = silk['world'][silk['indices']]
    branches = []
    for bi, (height, preferred, length) in enumerate([(1.93, 145., .205), (2.51, 25., .19)]):
        accepted = None
        for y_delta in [0., -.06, .06, -.12, .12]:
            for angle_delta in [0., -12., 12., -24., 24., -36., 36., -48., 48.]:
                result = branch_mesh(center, math.radians(preferred + angle_delta), height + y_delta, length, .7 + bi,
                                     body['world'], body['TEXCOORD_0'], body['indices'], cap_uv)
                pos, norm, uv, faces, info = result
                tri = pos[faces]
                sample = np.vstack([pos, tri.mean(1), (tri[:, 0] + tri[:, 1]) * .5, (tri[:, 1] + tri[:, 2]) * .5, (tri[:, 2] + tri[:, 0]) * .5])
                r = np.linalg.norm(sample[:, [0, 2]] - center[[0, 2]], axis=1)
                sample = sample[r > .225]
                clearance = min(x[0] for x in closest_triangles(sample, silk_tris))
                intersections = triangle_intersections(tri, silk_tris)
                if clearance > .012 and intersections == 0:
                    accepted = result
                    info.update({'sampled_silk_clearance_m': clearance, 'exact_segment_triangle_intersections_with_silk': intersections})
                    break
            if accepted:
                break
        assert accepted is not None, 'No branch placement clears existing ribbons'
        pos, norm, uv, faces, info = accepted
        # Prove geometric closure after welding cap normal seams.
        _, welded = np.unique(np.round(pos, 7), axis=0, return_inverse=True)
        edges = {}
        for f in welded[faces]:
            for ia, ib in zip(f, np.roll(f, -1)):
                key = tuple(sorted([int(ia), int(ib)])); edges[key] = edges.get(key, 0) + 1
        assert all(n == 2 for n in edges.values())
        tri = pos[faces]
        signed_volume = float(np.einsum('ij,ij->i', tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6)
        assert signed_volume > 0
        assert np.linalg.norm(pos[:16, [0, 2]] - center[[0, 2]], axis=1).max() < .20
        attrs = {'POSITION': append_accessor(doc, buf, pos, 'VEC3'),
                 'NORMAL': append_accessor(doc, buf, norm, 'VEC3'),
                 'TEXCOORD_0': append_accessor(doc, buf, uv, 'VEC2')}
        indices = append_accessor(doc, buf, faces, 'SCALAR')
        doc['meshes'].append({'name': f'S2_project_design_branch_stub_{bi + 1}',
                              'primitives': [{'attributes': attrs, 'indices': indices, 'material': body_mi, 'mode': 4}]})
        doc['nodes'].append({'name': f'BranchStub_{bi + 1}', 'mesh': len(doc['meshes']) - 1})
        doc['scenes'][doc.get('scene', 0)]['nodes'].append(len(doc['nodes']) - 1)
        info.update({'closed_welded_edge_incidence': True, 'outward_signed_volume_m3': signed_volume,
                     'root_embedded_inside_trunk': True, 'triangles': len(faces), 'vertices': len(pos),
                     'cut_end_uv_source': 'existing trunk top-cap atlas island', 'design_status': 'project supplemental design'})
        branches.append(info)
    doc['asset']['generator'] = 'RMMO build_s2_green_post.py; preserved authored post + supplemental branch stubs'
    doc['scenes'][doc.get('scene', 0)]['name'] = 'S2_Green_GoldSilk_Post'
    doc['buffers'][0]['byteLength'] = len(buf)
    # Only new isolated outputs are permitted.
    OUT.mkdir(parents=True, exist_ok=True); AUDIT.parent.mkdir(parents=True, exist_ok=True)
    master = OUT / 'master.glb'; runtime = OUT / 'runtime.glb'
    write_glb(master, doc, buf)
    clean, cleanbuf, remap = compact(doc, buf)
    write_glb(runtime, clean, cleanbuf)
    md, mb, _ = read_glb(master); rd, rb, _ = read_glb(runtime)
    assert semantic(md, mb) == semantic(rd, rb), 'Compaction changed geometry/material/pixels'
    before = semantic(source, binary); after = semantic(md, mb)
    for i in (body_i, silk_i):
        assert before[i]['geometry_sha256'] == after[i]['geometry_sha256']
        assert before[i]['node'] == after[i]['node']
    assert before[silk_i] == after[silk_i], 'GoldSilk must remain byte/parameter equivalent'
    body_before, body_after = copy.deepcopy(before[body_i]['material']), copy.deepcopy(after[body_i]['material'])
    for mat in (body_before, body_after):
        mat.pop('name', None); mat['pbrMetallicRoughness'].pop('baseColorTexture')
    assert body_before == body_after
    for p in protected:
        assert sha(p.read_bytes()) == guards[str(p)], f'Protected source changed: {p}'
    ma, ra = model_audit(master), model_audit(runtime)
    assert ra['triangles'] == 5212 + 256 and len(ra['images']) == 6 and ra['counts']['materials'] == 2
    report = {'schema_version': 1, 'label': '绿色金丝带彩柱', 'date': '2026-10-15',
              'source_path': str(SOURCE), 'source_sha256': guards[str(SOURCE)],
              'existing_green_path': str(GREEN), 'existing_green_sha256': guards[str(GREEN)],
              'green_albedo_encoded_sha256': sha(green_blob), 'recipe_path': str(Path(__file__).resolve()),
              'recipe_sha256': sha(Path(__file__).read_bytes()),
              'reference': str(ROOT / 'docs/references/town_required_shots_20261012/03_festival_residential_lane.webp'),
              'design': 'Retain user-required gold silk. Green wooden identity uses existing green albedo. Two small irregular upper branch stubs are supplemental design; not a claim of measured reference geometry.',
              'branch_stubs': branches, 'master': ma, 'runtime': ra,
              'compaction': {'complete_known_reachability': True, 'unknown_reference_policy': 'abort', 'remap': remap,
                             'semantic_geometry_material_and_encoded_image_identity': True,
                             'decoded_pixel_identity': [x['decoded_rgba_sha256'] for x in ma['images'] if x['active']] == [x['decoded_rgba_sha256'] for x in ra['images']],
                             'disk_bytes_saved': ma['bytes'] - ra['bytes'], 'not_a_vram_reduction_claim': True},
              'original_parts': {'PostBody_geometry_unchanged': True, 'GoldSilk_geometry_material_images_unchanged': True,
                                 'existing_node_translations_unchanged': True, 'PostBody_non_albedo_PBR_unchanged': True,
                                 'geometry_hashes_before': before, 'semantic_hashes_master': after, 'semantic_hashes_runtime': semantic(rd, rb)},
              'protected_files': [{'path': p, 'before_sha256': s, 'after_sha256': sha(Path(p).read_bytes()), 'unchanged': True} for p, s in guards.items()],
              'scope': {'maps_written': False, 'formal_library_written': False, 'gpu_run': False},
              'review_status': {'resources': 'CPU passed', 'visual': 'pending same-camera GPU review',
                                'runtime_pipeline': 'pending real import/save/reopen', 'formal_import': 'not performed'},
              'cost_note': 'Encoded/decoded bytes and conservative RGBA8+mips budgets are separate. No native size/RSS/VRAM measured.'}
    assert report['compaction']['decoded_pixel_identity']
    AUDIT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(json.dumps({'master': str(master), 'runtime': str(runtime), 'runtime_sha256': ra['sha256'],
                      'triangles': ra['triangles'], 'master_bytes': ma['bytes'], 'runtime_bytes': ra['bytes'],
                      'audit': str(AUDIT), 'branch_stubs': branches}, ensure_ascii=False))


def encode_png(array):
    stream = io.BytesIO()
    Image.fromarray(np.asarray(array, dtype=np.uint8)).save(stream, format='PNG', optimize=True)
    return stream.getvalue()


def tangents_for(g, uv):
    """glTF tangent frames from the actual repaired UVs, without changing normals."""
    pos, normals, faces = g['POSITION'].astype(float), g['NORMAL'].astype(float), g['indices']
    tangent, bitangent = np.zeros_like(pos), np.zeros_like(pos)
    degenerate_uv = 0
    for face in faces:
        p, q = pos[face], uv[face]
        e1, e2 = p[1] - p[0], p[2] - p[0]
        d1, d2 = q[1] - q[0], q[2] - q[0]
        det = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(det) < 1e-12:
            degenerate_uv += 1
            continue
        t = (e1 * d2[1] - e2 * d1[1]) / det
        bt = (e2 * d1[0] - e1 * d2[0]) / det
        weight = np.linalg.norm(np.cross(e1, e2))
        tangent[face] += t * weight; bitangent[face] += bt * weight
    out = np.zeros((len(pos), 4), dtype=np.float32)
    for i, normal in enumerate(normals):
        t = tangent[i] - normal * np.dot(normal, tangent[i])
        if np.linalg.norm(t) < 1e-8:
            seed = np.array([1., 0., 0.]) if abs(normal[0]) < .9 else np.array([0., 0., 1.])
            t = seed - normal * np.dot(seed, normal)
        t /= np.linalg.norm(t)
        out[i, :3] = t
        out[i, 3] = -1. if np.dot(np.cross(normal, t), bitangent[i]) < 0 else 1.
    assert np.isfinite(out).all()
    return out, degenerate_uv


def cylindrical_body_uv(g):
    pos, normals, faces = g['world'], g['NORMAL'], g['indices']
    center = np.unique(pos[np.abs(pos[:, 1]) < 1e-6], axis=0).mean(axis=0)
    delta = pos[:, [0, 2]] - center[[0, 2]]
    angles = np.arctan2(delta[:, 1], delta[:, 0])
    side_faces = faces[np.all(np.abs(normals[faces, 1]) < .9, axis=1)]
    # Locate an existing authored seam; never add/split vertices to repair the UVs.
    for degrees in range(360):
        u = np.mod(angles - math.radians(degrees), math.tau) / math.tau
        assigned = {}; conflict = False
        for face in side_faces:
            q = u[face].copy()
            if np.ptp(q) > .5:
                q[q < .5] += 1
            for vertex, value in zip(face, q):
                if int(vertex) in assigned and abs(assigned[int(vertex)] - value) > 1e-5:
                    conflict = True; break
                assigned[int(vertex)] = value
            if conflict:
                break
        if not conflict:
            break
    assert not conflict, 'No existing cylindrical seam; preserve geometry and stop'
    radius = float(np.linalg.norm(delta[np.abs(pos[:, 1]) < 1e-6], axis=1).mean())
    uv = np.zeros((len(pos), 2), dtype=float)
    uv[:, 0] = delta[:, 0] / .8 + .5
    uv[:, 1] = delta[:, 1] / .8 + .5
    for vertex, value in assigned.items():
        uv[vertex] = [value * math.tau * radius / .8, pos[vertex, 1] / 2.4]
    return uv, {'mode': 'existing seam cylindrical sides + planar cut caps', 'seam_degrees': degrees,
                'physical_repeat_m': [.8, 2.4], 'estimated_base_radius_m': radius,
                'indices_positions_normals_changed': False}


def stub_continuous_uv(g, info):
    # A short branch has no duplicated longitude seam. A continuous planar grain
    # projection avoids atlas islands and preserves the authored vertex/index set.
    origin = np.array(info['root_center']); end = np.array(info['end_center'])
    axis = end - origin; axis /= np.linalg.norm(axis)
    u = np.cross(np.array([0., 1., 0.]), axis); u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    rel = g['world'] - origin
    uv = np.column_stack([rel @ u / .8 + .41, rel @ axis / 2.4 + .37])
    caps = np.abs(g['NORMAL'] @ axis) > .995
    uv[caps] = np.column_stack([rel[caps] @ u / .8 + .65, rel[caps] @ v / .8 + .51])
    return uv, {'mode': 'continuous planar branch grain + planar cut caps; full valid tiling PBR',
                'physical_repeat_m': [.8, 2.4], 'indices_positions_normals_changed': False,
                'limitation': 'opposite narrow branch sides mirror the same continuous grain projection'}


def main_v2():
    v1 = OUT / 'v1'; dst = OUT / 'v2'; dst.mkdir(parents=True, exist_ok=True)
    assert (v1 / 'master.glb').exists() and (v1 / 'runtime.glb').exists(), 'Archive v1 first'
    timber = RUNTIME / 'packs/default/assets/materials/wood/solid_timber'
    sources = [timber / name for name in ['material.json', 'texture.png', 'normal.png', 'roughness.png']]
    protected = [SOURCE, GREEN, RUNTIME / 'packs/default/assets/library.json',
                 RUNTIME / 'packs/default/assets/prefabs/ae8388b77fc7239fd2dfafc9fd540cd596a14c1b9e759c9a7b85e6635ecc9c4a.json',
                 v1 / 'master.glb', v1 / 'runtime.glb', v1 / 'build_audit.json', *sources]
    guards = {str(p): sha(p.read_bytes()) for p in protected}
    assert guards[str(SOURCE)] == EXPECTED_SOURCE and guards[str(GREEN)] == EXPECTED_GREEN
    assert guards[str(v1 / 'master.glb')] == '29729b3e4c08fd69fc69dcb80499e8d2f8b95e3f63941812c66b03390f16b17e'
    doc, buf, _ = read_glb(v1 / 'master.glb'); strict_schema(doc)
    before = semantic(doc, buf)
    v1report = json.loads((v1 / 'build_audit.json').read_text(encoding='utf8'))
    body_i = next(i for i, n in enumerate(doc['nodes']) if n['name'] == 'PostBody')
    silk_i = next(i for i, n in enumerate(doc['nodes']) if n['name'] == 'GoldSilk')
    body_mi = doc['meshes'][doc['nodes'][body_i]['mesh']]['primitives'][0]['material']
    original_body_material = copy.deepcopy(doc['materials'][body_mi])
    old_im = doc['images'][doc['textures'][original_body_material['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    old_green = np.asarray(Image.open(io.BytesIO(view_bytes(doc, buf, old_im['bufferView']))).convert('RGB'))
    valid_old = old_green.max(axis=2) > 2
    # Technical stain recoloring from the owned real wood texture. No atlas-wide
    # black mean, no baked illumination, no invented grain, no AI raster changes.
    color = np.asarray(Image.open(timber / 'texture.png').convert('RGB'), dtype=np.float32) / 255.
    luminance = color @ np.array([.2126, .7152, .0722], dtype=np.float32)
    median = float(np.median(luminance))
    variation = np.power(np.maximum(luminance, .015) / median, 1.45)
    base = np.array([.14, .34, .17], dtype=np.float32)
    stained = np.clip(variation[:, :, None] * base, .012, .72)
    stained_pixels = np.rint(stained * 255).astype(np.uint8)
    rough_source = np.asarray(Image.open(timber / 'roughness.png').convert('L'), dtype=np.float32) / 255.
    rough = np.clip(.65 + .26 * np.clip((rough_source - .29) / .71, 0, 1), .65, .91)
    orm = np.empty((*rough.shape, 3), dtype=np.uint8)
    orm[:, :, 0] = 255; orm[:, :, 1] = np.rint(rough * 255).astype(np.uint8); orm[:, :, 2] = 0
    blobs = {'albedo': encode_png(stained_pixels), 'normal': (timber / 'normal.png').read_bytes(), 'orm': encode_png(orm)}
    texture_indices = {}
    map_evidence = []
    for key, blob in blobs.items():
        p = dst / f'green_timber_{key}.png'; p.write_bytes(blob)
        vi = append_view(doc, buf, blob)
        doc['images'].append({'bufferView': vi, 'mimeType': 'image/png', 'name': f'S2_v2_green_timber_{key}'})
        doc['textures'].append({'sampler': 0, 'source': len(doc['images']) - 1})
        texture_indices[key] = len(doc['textures']) - 1
        map_evidence.append({'channel': key, 'path': str(p), 'sha256': sha(blob), 'bytes': len(blob),
                             'normal_is_source_byte_identical': key == 'normal' and blob == (timber / 'normal.png').read_bytes()})
    doc['materials'][body_mi] = {
        'name': 'S2 v2 forest-green stained real timber; continuous metric grain',
        'doubleSided': True,
        'pbrMetallicRoughness': {'baseColorFactor': [1., 1., 1., 1.],
                               'baseColorTexture': {'index': texture_indices['albedo']},
                               'metallicFactor': 0., 'roughnessFactor': 1.,
                               'metallicRoughnessTexture': {'index': texture_indices['orm']}},
        'normalTexture': {'index': texture_indices['normal'], 'scale': .45}}
    uv_fixes = []
    for ni, node in enumerate(doc['nodes']):
        if node['name'] == 'GoldSilk':
            continue
        g = primitive_geometry(doc, buf, ni)
        if node['name'] == 'PostBody':
            uv, info = cylindrical_body_uv(g)
        else:
            bi = int(node['name'].split('_')[-1]) - 1
            uv, info = stub_continuous_uv(g, v1report['branch_stubs'][bi])
        tangent, bad_uv = tangents_for(g, uv)
        assert bad_uv == 0, f'Degenerate UV faces: {node["name"]}: {bad_uv}'
        p = doc['meshes'][node['mesh']]['primitives'][0]
        p['attributes']['TEXCOORD_0'] = append_accessor(doc, buf, uv, 'VEC2')
        p['attributes']['TANGENT'] = append_accessor(doc, buf, tangent, 'VEC4')
        uv_fixes.append({'node': node['name'], **info, 'finite_nondegenerate_uv_faces': True,
                         'explicit_uv_derived_tangents': True, 'normal_format': 'opengl',
                         'normal_strength': .45, 'uv_min': uv.min(0).tolist(), 'uv_max': uv.max(0).tolist()})
    doc['asset']['generator'] = 'RMMO build_s2_green_post.py v2; real timber PBR and repaired continuous UVs'
    doc['buffers'][0]['byteLength'] = len(buf)
    master, runtime = dst / 'master.glb', dst / 'runtime.glb'
    write_glb(master, doc, buf)
    clean, binary, remap = compact(doc, buf); write_glb(runtime, clean, binary)
    md, mb, _ = read_glb(master); rd, rb, _ = read_glb(runtime)
    after, final = semantic(md, mb), semantic(rd, rb)
    assert after == final
    assert before[silk_i] == after[silk_i], 'GoldSilk changed'
    preserved = []
    for old, new in zip(before, after):
        assert old['node'] == new['node']
        keys = ['POSITION', 'NORMAL', 'indices', 'world']
        assert all(old['geometry_sha256'][k] == new['geometry_sha256'][k] for k in keys)
        preserved.append({'name': old['node']['name'], 'unchanged_channels': keys,
                          'sha256': {k: old['geometry_sha256'][k] for k in keys}})
    ma, ra = model_audit(master, repeating_uv=True), model_audit(runtime, repeating_uv=True)
    assert ra['triangles'] == 5468 and ra['counts']['materials'] == 2 and len(ra['images']) == 6
    assert ma['world_size'] == v1report['master']['world_size']
    for p in protected:
        assert sha(p.read_bytes()) == guards[str(p)], f'Protected source changed: {p}'
    report = {
        'schema_version': 2, 'version': 'v2', 'label': '绿色金丝带彩柱', 'date': '2026-10-15',
        'source_path': str(SOURCE), 'source_sha256': EXPECTED_SOURCE,
        'v1_archive': {'path': str(v1), 'master_sha256': guards[str(v1 / 'master.glb')],
                       'runtime_sha256': guards[str(v1 / 'runtime.glb')], 'visual_status': 'failed: fluorescent clipped green and branch atlas seams'},
        'diagnosis': {'old_green_black_background_fraction': float((~valid_old).mean()),
                      'old_green_nonblack_pixels_green_channel_255_fraction': float((old_green[:, :, 1][valid_old] == 255).mean()),
                      'cause': 'v1 inherited atlas recoloring normalized against black background then clipped the green channel; branch vertex UV projection interpolated across disconnected atlas islands',
                      'seen_q90_images': ['runtime/near.webp', 'runtime/wood_ribbon_detail.webp', 'runtime/upper_join_detail.webp']},
        'recipe_path': str(Path(__file__).resolve()), 'recipe_sha256': sha(Path(__file__).read_bytes()),
        'wood_source': {'definition_path': str(timber / 'material.json'),
                        'definition': json.loads((timber / 'material.json').read_text(encoding='utf8')),
                        'sources': [{'path': str(p), 'sha256': guards[str(p)]} for p in sources],
                        'recolor': {'type': 'technical green stain over existing real grain', 'median_srgb_luminance': median,
                                    'base_srgb': base.tolist(), 'contrast_exponent': 1.45, 'clamp': [.012, .72]},
                        'roughness': {'source_map': 'solid_timber/roughness.png', 'range': [.65, .91],
                                      'formula': '.65 + .26 * clamp((source - .29) / .71, 0, 1)'},
                        'normal': {'source_bytes_identical': True, 'format': 'opengl', 'scale': .45},
                        'maps': map_evidence},
        'uv_fixes': uv_fixes, 'branch_stubs': v1report['branch_stubs'], 'preserved_geometry': preserved,
        'GoldSilk_semantic_geometry_material_images_unchanged': True,
        'master': ma, 'runtime': ra,
        'compaction': {'complete_known_reachability': True, 'unknown_reference_policy': 'abort', 'remap': remap,
                       'semantic_geometry_material_and_encoded_image_identity': True,
                       'decoded_pixel_identity': [x['decoded_rgba_sha256'] for x in ma['images'] if x['active']] == [x['decoded_rgba_sha256'] for x in ra['images']],
                       'disk_bytes_saved': ma['bytes'] - ra['bytes'], 'not_a_vram_reduction_claim': True},
        'protected_files': [{'path': p, 'before_sha256': s, 'after_sha256': sha(Path(p).read_bytes()), 'unchanged': True} for p, s in guards.items()],
        'scope': {'maps_written': False, 'formal_library_written': False, 'gpu_run': False},
        'review_status': {'resources': 'CPU passed', 'visual': 'v1 failed; v2 pending same-camera GPU review',
                          'runtime_pipeline': 'pending actual v2 import/save/reopen', 'formal_import': 'not performed'},
        'cost_note': 'Runtime images differ intentionally from v1. Master/runtime compaction preserves all active images. Encoded/decoded and mip budgets are separate; native/RSS/VRAM not measured.'}
    assert report['compaction']['decoded_pixel_identity']
    AUDIT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    (dst / 'build_audit.json').write_bytes(AUDIT.read_bytes())
    print(json.dumps({'version': 'v2', 'master': str(master), 'runtime': str(runtime),
                      'master_sha256': ma['sha256'], 'runtime_sha256': ra['sha256'],
                      'master_bytes': ma['bytes'], 'runtime_bytes': ra['bytes'],
                      'triangles': ra['triangles'], 'audit': str(AUDIT), 'diagnosis': report['diagnosis']}, ensure_ascii=False))


def tangent_handedness_audit(g):
    mixed_faces = []; mismatched_corners = []
    pos, uv, faces = g['POSITION'], g['TEXCOORD_0'], g['indices']
    for fi, f in enumerate(faces):
        t = g['TANGENT'][f]
        if not np.all(t[:, 3] == t[0, 3]):
            mixed_faces.append(fi)
        p, q = pos[f], uv[f]
        e1, e2 = p[1] - p[0], p[2] - p[0]
        d1, d2 = q[1] - q[0], q[2] - q[0]
        det = float(d1[0] * d2[1] - d1[1] * d2[0])
        assert abs(det) > 1e-12
        bt = (e2 * d1[0] - e1 * d2[0]) / det
        for ci, vi in enumerate(f):
            value = float(np.dot(np.cross(g['NORMAL'][vi], g['TANGENT'][vi, :3]), bt))
            expected = -1. if value < 0 else 1.
            if expected != g['TANGENT'][vi, 3]:
                mismatched_corners.append([fi, ci])
    return {'mixed_handedness_faces': mixed_faces, 'uv_gradient_mismatched_corners': mismatched_corners,
            'passed': not mixed_faces and not mismatched_corners}


def main_v3():
    previous, dst = OUT / 'v2', OUT / 'v3'
    dst.mkdir(parents=True, exist_ok=True)
    protected = [SOURCE, GREEN, RUNTIME / 'packs/default/assets/library.json',
                 RUNTIME / 'packs/default/assets/prefabs/ae8388b77fc7239fd2dfafc9fd540cd596a14c1b9e759c9a7b85e6635ecc9c4a.json',
                 previous / 'master.glb', previous / 'runtime.glb', previous / 'build_audit.json']
    guards = {str(p): sha(p.read_bytes()) for p in protected}
    assert guards[str(SOURCE)] == EXPECTED_SOURCE
    assert guards[str(previous / 'runtime.glb')] == '88ae433eb3c6969249131714dc5ab97c7cf23b20cfbd532706d848c39075a510'
    report_v2 = json.loads((previous / 'build_audit.json').read_text(encoding='utf8'))
    doc, buf, _ = read_glb(previous / 'master.glb')
    strict_schema(doc)
    before = semantic(doc, buf)
    branch_evidence = []
    original_branch_geometry = {}
    for ni, node in enumerate(doc['nodes']):
        if not node['name'].startswith('BranchStub_'):
            continue
        bi = int(node['name'].split('_')[-1]) - 1
        info = report_v2['branch_stubs'][bi]
        g = primitive_geometry(doc, buf, ni)
        original_branch_geometry[ni] = g
        assert len(g['POSITION']) == 98 and len(g['indices']) == 128
        origin = np.array(info['root_center']); axis = np.array(info['end_center']) - origin
        axis /= np.linalg.norm(axis)
        uv = g['TEXCOORD_0'].astype(float).copy()
        for row in range(4):
            for i in range(16):
                vi = row * 16 + i
                uv[vi] = [.41 + i / 16., .37 + float(np.dot(g['world'][vi] - origin, axis)) / 2.4]
        duplicated = [0, 16, 32, 48]
        pos = np.vstack([g['POSITION'], g['POSITION'][duplicated]])
        normal = np.vstack([g['NORMAL'], g['NORMAL'][duplicated]])
        uv = np.vstack([uv, uv[duplicated]])
        uv[98:, 0] += 1.
        faces = g['indices'].copy()
        for f in faces[:96]:
            if np.any(f % 16 == 15) and np.any(f % 16 == 0):
                for ci, vi in enumerate(f):
                    if vi % 16 == 0:
                        f[ci] = 98 + vi // 16
        assert all(np.any(faces == i) for i in range(98, 102))
        assert np.array_equal(pos[faces], g['POSITION'][g['indices']])
        assert np.array_equal(normal[faces], g['NORMAL'][g['indices']])
        fixed = {'POSITION': pos, 'NORMAL': normal, 'indices': faces}
        tangent, degenerate = tangents_for(fixed, uv)
        fixed.update({'TEXCOORD_0': uv, 'TANGENT': tangent})
        assert degenerate == 0
        tbn = tangent_handedness_audit(fixed)
        assert tbn['passed'], tbn
        p = doc['meshes'][node['mesh']]['primitives'][0]
        p['attributes']['POSITION'] = append_accessor(doc, buf, pos, 'VEC3')
        p['attributes']['NORMAL'] = append_accessor(doc, buf, normal, 'VEC3')
        p['attributes']['TEXCOORD_0'] = append_accessor(doc, buf, uv, 'VEC2')
        p['attributes']['TANGENT'] = append_accessor(doc, buf, tangent, 'VEC4')
        p['indices'] = append_accessor(doc, buf, faces, 'SCALAR')
        circumference = []
        for row in range(4):
            ring = g['world'][row * 16:(row + 1) * 16]
            circumference.append(float(np.linalg.norm(np.roll(ring, -1, axis=0) - ring, axis=1).sum()))
        branch_evidence.append({'node': node['name'], 'vertex_count_before': 98, 'vertex_count_after': 102,
                                'triangles_before': 128, 'triangles_after': 128,
                                'seam_vertices_duplicated': duplicated, 'seam_u_delta_exact': 1.,
                                'v_tile_m': 2.4, 'u_repeat': 'one whole texture repeat per ring',
                                'ring_u_effective_period_m': circumference,
                                'side_uv': 'cylindrical unfold with one duplicated seam vertex per ring',
                                'cut_end_uv_source': 'complete solid_timber texture with planar cut-cap UVs',
                                'triangle_corner_position_bytes_unchanged': True,
                                'triangle_corner_normal_bytes_unchanged': True,
                                'position_face_sha256': sha(pos[faces].tobytes()),
                                'normal_face_sha256': sha(normal[faces].tobytes()),
                                'tangent_handedness': tbn})
    doc['asset']['generator'] = 'RMMO build_s2_green_post.py v3; split branch UV seams with consistent tangent frames'
    doc['buffers'][0]['byteLength'] = len(buf)
    master, runtime = dst / 'master.glb', dst / 'runtime.glb'
    write_glb(master, doc, buf)
    clean, binary, remap = compact(doc, buf); write_glb(runtime, clean, binary)
    md, mb, _ = read_glb(master); rd, rb, _ = read_glb(runtime)
    after, final = semantic(md, mb), semantic(rd, rb)
    assert after == final
    for old, new in zip(before, after):
        if old['node']['name'] in ['PostBody', 'GoldSilk']:
            assert old == new
    for ni, old in original_branch_geometry.items():
        new = primitive_geometry(rd, rb, ni)
        assert np.array_equal(old['POSITION'][old['indices']], new['POSITION'][new['indices']])
        assert np.array_equal(old['NORMAL'][old['indices']], new['NORMAL'][new['indices']])
        assert tangent_handedness_audit(new)['passed']
    ma, ra = model_audit(master, repeating_uv=True), model_audit(runtime, repeating_uv=True)
    assert ma['world_size'] == report_v2['master']['world_size']
    assert ra['triangles'] == 5468 and ra['counts']['materials'] == 2 and len(ra['images']) == 6
    assert [(im['encoded_sha256'], im['decoded_rgba_sha256']) for im in ra['images']] == [(im['encoded_sha256'], im['decoded_rgba_sha256']) for im in report_v2['runtime']['images']]
    for p in protected:
        assert sha(p.read_bytes()) == guards[str(p)]
    branches = copy.deepcopy(report_v2['branch_stubs'])
    for row in branches:
        row['cut_end_uv_source'] = 'complete solid_timber texture with planar cut-cap UVs'
    report = {
        'schema_version': 3, 'version': 'v3', 'label': '绿色金丝带彩柱', 'date': '2026-10-15',
        'source_path': str(SOURCE), 'source_sha256': EXPECTED_SOURCE,
        'v1_archive': report_v2['v1_archive'],
        'v2_archive': {'path': str(previous), 'master_sha256': guards[str(previous / 'master.glb')],
                       'runtime_sha256': guards[str(previous / 'runtime.glb')],
                       'status': 'color/wood grain accepted visually; branch tangent handedness failed independent CPU audit'},
        'recipe_path': str(Path(__file__).resolve()), 'recipe_sha256': sha(Path(__file__).read_bytes()),
        'diagnosis': 'v2 planar side UVs folded over shared branch vertices, yielding mixed tangent handedness inside triangles. v3 splits four seam vertices per branch and uses cylindrical side UVs.',
        'wood_source': report_v2['wood_source'], 'branch_stubs': branches,
        'uv_fixes': branch_evidence,
        'PostBody_entire_geometry_material_images_unchanged_from_v2': True,
        'GoldSilk_entire_geometry_material_images_unchanged_from_v1_and_v2': True,
        'all_active_images_encoded_and_decoded_sha_unchanged_from_v2': True,
        'master': ma, 'runtime': ra,
        'compaction': {'complete_known_reachability': True, 'unknown_reference_policy': 'abort', 'remap': remap,
                       'semantic_geometry_material_and_encoded_image_identity': True,
                       'decoded_pixel_identity': True, 'disk_bytes_saved': ma['bytes'] - ra['bytes'],
                       'not_a_vram_reduction_claim': True},
        'protected_files': [{'path': p, 'before_sha256': s, 'after_sha256': sha(Path(p).read_bytes()), 'unchanged': True} for p, s in guards.items()],
        'scope': {'maps_written': False, 'formal_library_written': False, 'gpu_run': False},
        'review_status': {'resources': 'local CPU passed; independent CPU review pending',
                          'visual': 'pending v3 GPU review', 'runtime_pipeline': 'pending actual v3 import/save/reopen',
                          'formal_import': 'not performed'},
        'cost_note': 'Only branch UV seam vertices are duplicated, no new triangles. Six 2K image channels and decoded/mip budgets unchanged from v2. Native/RSS/VRAM not measured.'}
    AUDIT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    (dst / 'build_audit.json').write_bytes(AUDIT.read_bytes())
    print(json.dumps({'version': 'v3', 'master': str(master), 'runtime': str(runtime),
                      'master_sha256': ma['sha256'], 'runtime_sha256': ra['sha256'],
                      'master_bytes': ma['bytes'], 'runtime_bytes': ra['bytes'],
                      'audit': str(AUDIT), 'branch_evidence': branch_evidence}, ensure_ascii=False))


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', choices=['v1', 'v2', 'v3'], default='v3')
    args = parser.parse_args()
    {'v1': main, 'v2': main_v2, 'v3': main_v3}[args.version]()
