"""CPU-only, non-destructive S12 worked-limestone material repair.

Default is inspect-only. --build creates isolated v2 candidates and a build audit;
it never writes a catalogue, map, or original model. Geometry and node semantics
are preserved. Existing valid UV1 is recovered only where active UV0 collapsed.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT.parent / 'rmmo_runtime'
LIBRARY = RUNTIME / 'packs/default/assets'
OUT = RUNTIME / 'art_sources/s12_stone_materials_20261015'
REPORT = ROOT / 'review_artifacts/s12_stone_materials_20261015'
STONE = LIBRARY / 'materials/terrain/beach_cliff'
SOURCES = {
    's12_projecting_arch': '11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be',
    's12_gable_relief': 'd0ca66d5b04913d4bc9ffd56fcc01bb2f4761332dc28fcd98337ad21026dd240',
}
MAP_SHAS = {
    'texture.jpg': 'e0b356c07cab84325e110c4cfbc0ca83e19af82fa303e60e1d408d0de4db1e2b',
    'normal.png': '56ac6933b7e17a0dd9270d45eef4690e396c51d946c047d9e4a02305355e2717',
    'roughness.png': 'be383ae6f5139321d49ba2f7228d3b5b16c98bb9ee48c6fe8689c908443216b7',
    'ao.png': 'de197004cc6abf2e40544081a5772a558892a881b7f1739dc5e99ff7db625e7c',
}


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def file_sha(path):
    return sha(Path(path).read_bytes())


def read_glb(path):
    raw = Path(path).read_bytes()
    assert struct.unpack_from('<III', raw) == (0x46546C67, 2, len(raw))
    size, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    bs, bk = struct.unpack_from('<II', raw, 20 + size)
    assert bk == 0x004E4942 and 28 + size + bs == len(raw)
    return json.loads(raw[20:20 + size]), bytearray(raw[28 + size:]), raw


def encode_glb(doc, binary):
    d = copy.deepcopy(doc)
    d['buffers'] = [{'byteLength': len(binary)}]
    js = json.dumps(d, ensure_ascii=False, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    binary = bytes(binary) + b'\0' * (-len(binary) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(binary))
            + struct.pack('<II', len(js), 0x4E4F534A) + js
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def view(doc, binary, index):
    v = doc['bufferViews'][index]
    assert v['buffer'] == 0
    start = v.get('byteOffset', 0)
    assert 0 <= start <= len(binary) - v['byteLength']
    return bytes(binary[start:start + v['byteLength']])


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    dtype = np.dtype({5121: 'u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}[a['componentType']])
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    v = doc['bufferViews'][a['bufferView']]
    return np.ndarray((a['count'], width), dtype=dtype, buffer=view(doc, binary, a['bufferView']),
                      offset=a.get('byteOffset', 0),
                      strides=(v.get('byteStride', dtype.itemsize * width), dtype.itemsize)).copy()


def append_view(doc, binary, blob, target=None):
    binary.extend(b'\0' * (-len(binary) % 4))
    row = {'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(blob)}
    if target is not None:
        row['target'] = target
    doc['bufferViews'].append(row)
    binary.extend(blob)
    return len(doc['bufferViews']) - 1


def append_accessor(doc, binary, arr, kind):
    if kind == 'SCALAR':
        component, dtype = (5123, '<u2') if np.max(arr) <= 65535 else (5125, '<u4')
        target = 34963
        arr = np.asarray(arr, dtype=dtype).reshape(-1, 1)
    else:
        component, target = 5126, 34962
        arr = np.asarray(arr, dtype='<f4')
    vi = append_view(doc, binary, arr.tobytes(), target)
    doc['accessors'].append({'bufferView': vi, 'componentType': component, 'count': len(arr), 'type': kind,
                             'min': arr.min(axis=0).tolist(), 'max': arr.max(axis=0).tolist()})
    return len(doc['accessors']) - 1


def material_textures(material):
    result = [material[k] for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture') if k in material]
    pbr = material.get('pbrMetallicRoughness', {})
    result += [pbr[k] for k in ('baseColorTexture', 'metallicRoughnessTexture') if k in pbr]
    return result


def strict_schema(doc):
    """Known static glTF plus the actual S12 semantic extras. Unknown refs abort."""
    def fields(value, allowed, label):
        extra = set(value) - set(allowed.split())
        assert not extra, f'Unknown {label} fields {sorted(extra)}; no compaction or output'
    fields(doc, 'asset scene scenes nodes materials meshes textures images accessors bufferViews samplers buffers', 'root')
    fields(doc['asset'], 'generator version copyright', 'asset')
    assert len(doc['buffers']) == 1
    fields(doc['buffers'][0], 'byteLength', 'buffer')
    for x in doc['scenes']:
        fields(x, 'name nodes', 'scene')
    for n in doc['nodes']:
        fields(n, 'mesh name translation rotation scale matrix children extras', 'node')
        fields(n.get('extras', {}), 'rmmo_collision design_provenance asset_id reference_revision', 'node extras')
        assert not any(k in n for k in ('translation', 'rotation', 'scale', 'matrix', 'children')), 'Expected baked S12 transforms'
    for m in doc['meshes']:
        fields(m, 'name primitives', 'mesh')
        for p in m['primitives']:
            fields(p, 'attributes indices material mode', 'primitive')
            fields(p['attributes'], 'POSITION NORMAL TANGENT TEXCOORD_0 TEXCOORD_1', 'attributes')
            assert p.get('mode', 4) == 4
    for a in doc['accessors']:
        fields(a, 'bufferView byteOffset componentType count max min normalized type name', 'accessor')
    for b in doc['bufferViews']:
        fields(b, 'buffer byteOffset byteLength byteStride target name', 'bufferView')
    for m in doc['materials']:
        fields(m, 'name doubleSided alphaMode alphaCutoff normalTexture occlusionTexture emissiveTexture emissiveFactor pbrMetallicRoughness extras', 'material')
        fields(m.get('extras', {}), 'provenance base_provenance repair_recipe', 'material extras')
        assert all(isinstance(v, str) for v in m.get('extras', {}).values())
        fields(m.get('pbrMetallicRoughness', {}), 'baseColorFactor baseColorTexture metallicFactor roughnessFactor metallicRoughnessTexture', 'PBR')
        for t in material_textures(m):
            fields(t, 'index texCoord scale strength', 'texture info')
    for x in doc['textures']:
        fields(x, 'sampler source name', 'texture')
    for x in doc['images']:
        fields(x, 'bufferView mimeType name', 'image')
    for x in doc['samplers']:
        fields(x, 'magFilter minFilter wrapS wrapT name', 'sampler')


def reachable(doc):
    strict_schema(doc)
    sets = {k: set() for k in ('nodes', 'meshes', 'materials', 'accessors', 'textures', 'images', 'samplers', 'bufferViews')}
    sets['nodes'].update(n for s in doc['scenes'] for n in s['nodes'])
    sets['meshes'].update(doc['nodes'][n]['mesh'] for n in sets['nodes'])
    for i in sets['meshes']:
        for p in doc['meshes'][i]['primitives']:
            sets['materials'].add(p['material'])
            sets['accessors'].update(p['attributes'].values())
            sets['accessors'].add(p['indices'])
    for i in sets['materials']:
        sets['textures'].update(t['index'] for t in material_textures(doc['materials'][i]))
    for i in sets['textures']:
        t = doc['textures'][i]
        sets['images'].add(t['source'])
        if 'sampler' in t:
            sets['samplers'].add(t['sampler'])
    sets['bufferViews'].update(doc['images'][i]['bufferView'] for i in sets['images'])
    sets['bufferViews'].update(doc['accessors'][i]['bufferView'] for i in sets['accessors'])
    for key, values in sets.items():
        assert all(isinstance(i, int) and 0 <= i < len(doc[key]) for i in values)
    return {key: sorted(values) for key, values in sets.items()}


def compact(doc, binary):
    reach = reachable(doc)
    maps = {k: {old: new for new, old in enumerate(v)} for k, v in reach.items()}
    out = copy.deepcopy(doc)
    for k, ids in reach.items():
        out[k] = [copy.deepcopy(doc[k][i]) for i in ids]
    for s in out['scenes']:
        s['nodes'] = [maps['nodes'][i] for i in s['nodes']]
    for n in out['nodes']:
        n['mesh'] = maps['meshes'][n['mesh']]
    for m in out['meshes']:
        for p in m['primitives']:
            p['material'] = maps['materials'][p['material']]
            p['indices'] = maps['accessors'][p['indices']]
            p['attributes'] = {k: maps['accessors'][v] for k, v in p['attributes'].items()}
    for m in out['materials']:
        for t in material_textures(m):
            t['index'] = maps['textures'][t['index']]
    for t in out['textures']:
        t['source'] = maps['images'][t['source']]
        if 'sampler' in t:
            t['sampler'] = maps['samplers'][t['sampler']]
    for i in out['images']:
        i['bufferView'] = maps['bufferViews'][i['bufferView']]
    for a in out['accessors']:
        a['bufferView'] = maps['bufferViews'][a['bufferView']]
    result = bytearray()
    for i, old in enumerate(reach['bufferViews']):
        result.extend(b'\0' * (-len(result) % 4))
        out['bufferViews'][i]['byteOffset'] = len(result)
        result.extend(view(doc, binary, old))
    out['buffers'] = [{'byteLength': len(result)}]
    reachable(out)
    return out, result


def prim_data(doc, binary, p):
    data = {k: accessor(doc, binary, i) for k, i in p['attributes'].items()}
    data['indices'] = accessor(doc, binary, p['indices']).reshape(-1, 3)
    return data


def face_data(position, uv, indices):
    xyz = position[indices].astype(np.float64)
    tex = uv[indices].astype(np.float64)
    a, b = xyz[:, 1] - xyz[:, 0], xyz[:, 2] - xyz[:, 0]
    u, v = tex[:, 1] - tex[:, 0], tex[:, 2] - tex[:, 0]
    area2 = np.linalg.norm(np.cross(a, b), axis=1)
    det = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
    return a, b, u, v, area2, det


def uv_metrics(data):
    a, b, u, v, area2, det = face_data(data['POSITION'], data['TEXCOORD_0'], data['indices'])
    valid = area2 > 2e-12
    alen = np.linalg.norm(a, axis=1)
    e1 = a / np.maximum(alen[:, None], 1e-30)
    bx = (b * e1).sum(1)
    by = np.linalg.norm(b - e1 * bx[:, None], axis=1)
    gradients = np.stack([u / np.maximum(alen[:, None], 1e-30),
                         (v - u * bx[:, None] / np.maximum(alen[:, None], 1e-30)) / np.maximum(by[:, None], 1e-30)], axis=1)
    sv = np.linalg.svd(gradients[valid], compute_uv=False)
    return {'vertices': len(data['POSITION']), 'triangles': len(data['indices']),
            'geometric_degenerate_triangles': int((~valid).sum()),
            'uv_degenerate_all_triangles': int((abs(det) < 1e-12).sum()),
            'uv_degenerate_nondegenerate_geometry': int(((abs(det) < 1e-12) & valid).sum()),
            'uv_repeat_per_m_singular_values_p1_p50_p99': np.percentile(sv, [1, 50, 99], axis=0).tolist()}


def cylindrical_columns(data, corner_uv):
    """Recognise the 18 actual independent lathe components, never reshape them.

    Side U is one complete texture repeat per ring; V is meridian arc / 2m.
    The single side seam is at -Z. Caps retain their planar source UVs.
    """
    P, I = data['POSITION'], data['indices']
    points, inverse = np.unique(np.round(P, 6), axis=0, return_inverse=True)
    parent = np.arange(len(points))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for face in inverse[I]:
        a = find(face[0])
        for x in face[1:]:
            b = find(x)
            if a != b:
                parent[b] = a
    roots = np.array([find(x) for x in inverse[I[:, 0]]])
    mask = np.zeros(len(I), dtype=bool)
    records = []
    for root in np.unique(roots):
        faces = np.where(roots == root)[0]
        ids = np.unique(I[faces])
        pos = P[ids].astype(np.float64)
        lo, hi = pos.min(0), pos.max(0)
        cx, cz = float((lo[0] + hi[0]) / 2), float((lo[2] + hi[2]) / 2)
        if abs(abs(cx) - 1.48) > 1e-4 or abs(cz - 1.25) > 1e-4:
            continue
        rad = np.linalg.norm(pos[:, [0, 2]] - [cx, cz], axis=1)
        heights = np.round(pos[:, 1], 6)
        levels = np.unique(heights)
        if len(levels) not in (2, 6) or max(np.ptp(rad[heights == h]) for h in levels) > 2e-6:
            continue  # Plinth/abacus boxes are not cylindrical.
        radius = np.array([rad[heights == h].mean() for h in levels])
        assert all(len(np.unique(np.round(pos[heights == h], 6), axis=0)) == 48 for h in levels)
        assert len(faces) == (len(levels) - 1) * 96 + 92
        meridian = np.r_[0., np.cumsum(np.hypot(np.diff(levels), np.diff(radius)))]
        tri = P[I[faces]].astype(np.float64)
        cap = np.ptp(tri[:, :, 1], axis=1) < 1e-6
        side_faces = faces[~cap]
        side = tri[~cap]
        theta = np.arctan2(side[:, :, 0] - cx, side[:, :, 2] - cz) + np.pi
        # The source is an exact 48-segment lathe. Snap floating point atan2
        # jitter to that measured ring so both corners of shared edges match.
        theta = np.round(theta / (np.pi / 24)) * (np.pi / 24)
        theta = np.mod(theta, 2 * np.pi)
        spans = np.ptp(theta, axis=1) > np.pi
        theta[spans] = np.where(theta[spans] < np.pi, theta[spans] + 2 * np.pi, theta[spans])
        ring_index = np.searchsorted(levels, np.round(side[:, :, 1], 6))
        new_uv = np.stack([theta / (2 * np.pi),
                           1 - (levels[0] + meridian[ring_index]) / 2], axis=-1)
        corner_uv[side_faces] = new_uv
        mask[side_faces] = True

        # Audit UV continuity, including the explicit rear 0/1 chart seam.
        # One whole repeat ensures its endpoints sample the same texture phase.
        locations = {}
        edges = {}
        for f in side_faces:
            for c, old in enumerate(I[f]):
                locations.setdefault(int(inverse[old]), []).append((int(f), c, corner_uv[f, c].copy()))
            for c in range(3):
                ca, cb = c, (c + 1) % 3
                edge = tuple(sorted((int(inverse[I[f, ca]]), int(inverse[I[f, cb]]))))
                edges.setdefault(edge, []).append((int(f), ca, cb))
        discontinuities = []
        for weld, values in locations.items():
            unique = np.unique(np.round([v[2] for v in values], 6), axis=0)
            if len(unique) > 1:
                pp = points[weld]
                assert abs(pp[0] - cx) < 2e-6 and pp[2] < cz, 'Side UV seam escaped the rear'
                assert np.ptp(unique[:, 1]) < 2e-6
                assert abs(np.ptp(unique[:, 0]) - 1.) < 2e-6
                discontinuities.append({'welded_vertex': weld, 'position': pp.tolist(), 'uv_values': unique.tolist()})
        seam_edges = []
        for edge, entries in edges.items():
            if len(entries) != 2:
                continue  # End ring boundary between side and planar cap.
            first, second = entries
            mismatch = False
            for wid in edge:
                def uv_at(entry):
                    f, ca, cb = entry
                    c = ca if inverse[I[f, ca]] == wid else cb
                    return corner_uv[f, c]
                mismatch |= not np.allclose(uv_at(first), uv_at(second), rtol=0, atol=2e-6)
            if mismatch:
                assert all(abs(points[w][0] - cx) < 2e-6 and points[w][2] < cz for w in edge)
                seam_edges.append({'welded_edge': list(edge), 'positions': points[list(edge)].tolist(),
                                   'triangles': [first[0], second[0]]})
        assert len(seam_edges) == len(levels) - 1
        records.append({'component': len(records), 'welded_root': int(root), 'center_xz_m': [cx, cz],
                        'triangle_ids': faces.tolist(), 'side_triangle_ids': side_faces.tolist(),
                        'cap_triangle_ids': faces[cap].tolist(), 'ring_heights_m': levels.tolist(),
                        'ring_radii_m': radius.tolist(), 'meridian_arc_lengths_m': meridian.tolist(),
                        'ring_circumferences_m': (radius * 2 * np.pi).tolist(),
                        'side_u_m_per_texture_repeat_by_ring': (radius * 2 * np.pi).tolist(),
                        'side_u_texture_repeats_per_ring': 1., 'side_u_2048px_texels_per_m_range': [float(2048/(radius.max()*2*np.pi)), float(2048/(radius.min()*2*np.pi))],
                        'side_v_m_per_texture_repeat': 2.,
                        'seam_direction': '-Z, rear', 'seam_edges': seam_edges,
                        'seam_vertices': discontinuities, 'nonrear_side_uv_discontinuities': 0,
                        'texture_phase_continuity_at_rear_seam': 'U differs by exactly 1.0, V identical: periodic REPEAT sampler addresses the same phase. Source scan edge quality remains a GPU visual check.'})
    assert len(records) == 18 and int(mask.sum()) == 3264, (len(records), int(mask.sum()))
    return corner_uv, mask, records


def build_uv_tangents(data, allow_source_normal_repair=False, repair_columns=False):
    """Recover valid secondary charts, retain other layout, split only UV/TBN seams."""
    P, N, U, I = (data[k] for k in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'indices'))
    a, b, u, v, area, det = face_data(P, U, I)
    valid_geo = area > 2e-12
    corner_normals = N[I].copy()
    face_normal = np.cross(a, b) / np.maximum(area[:, None], 1e-30)
    hemisphere_dot = np.einsum('fci,fi->fc', corner_normals, face_normal)
    mixed_normal = valid_geo & (np.min(hemisphere_dot, axis=1) < 0) & (np.max(hemisphere_dot, axis=1) > 0)
    normal_evidence = []
    normal_changed = np.zeros(I.shape, dtype=bool)
    if mixed_normal.any():
        assert allow_source_normal_repair, 'Source shading normals cross face hemispheres'
        assert np.where(mixed_normal)[0].tolist() == [2618, 2637, 5036, 5037, 5053, 5055, 7450, 7469, 9868, 9869, 9885, 9887, 12282, 12301, 14700, 14701, 14717, 14719, 17114, 17133, 19532, 19533, 19549, 19551, 21946, 21965, 24364, 24365, 24381, 24383]
        # Minimal angular rotation into the positive hemisphere. Keep the
        # existing tangential direction and all already-positive corner normals.
        # A 0.10 normal cosine floor avoids a numerically grazing TBN. Corners
        # split from neighbouring faces, whose original normals remain exact.
        for fi in np.where(mixed_normal)[0]:
            evidence = {'triangle': int(fi), 'area_m2': float(area[fi] * .5),
                        'positions': P[I[fi]].tolist(), 'source_normals': N[I[fi]].tolist(),
                        'face_normal': face_normal[fi].tolist(), 'source_normal_face_dots': hemisphere_dot[fi].tolist(),
                        'changes': []}
            for c in np.where(hemisphere_dot[fi] < 0)[0]:
                old = N[I[fi, c]].astype(np.float64)
                old /= np.linalg.norm(old)
                f = face_normal[fi]
                tangent = old - f * np.dot(old, f)
                tangent /= np.linalg.norm(tangent)
                new = tangent * np.sqrt(1. - .1 ** 2) + f * .1
                corner_normals[fi, c] = new.astype('<f4')
                normal_changed[fi, c] = True
                evidence['changes'].append({'corner': int(c), 'source_vertex': int(I[fi, c]),
                                            'new_normal': corner_normals[fi, c].tolist(),
                                            'rotation_degrees': float(np.degrees(np.arccos(np.clip(np.dot(old, new), -1, 1)))),
                                            'new_normal_face_dot': float(np.dot(new, f))})
            normal_evidence.append(evidence)
    recover = valid_geo & (abs(det) < 1e-12)
    per_corner_uv = U[I].astype(np.float64)
    if recover.any():
        assert 'TEXCOORD_1' in data, 'Missing valid source UV fallback'
        alt = data['TEXCOORD_1'][I].astype(np.float64)
        au, av = alt[:, 1] - alt[:, 0], alt[:, 2] - alt[:, 0]
        ad = au[:, 0] * av[:, 1] - au[:, 1] * av[:, 0]
        assert np.all(abs(ad[recover]) > 1e-12)
        per_corner_uv[recover] = alt[recover]
    # Original charts measured in metres; the scan is 2 metres per full repeat.
    per_corner_uv *= .5
    column_mask = np.zeros(len(I), dtype=bool)
    column_records = []
    if repair_columns:
        per_corner_uv, column_mask, column_records = cylindrical_columns(data, per_corner_uv)
    u = per_corner_uv[:, 1] - per_corner_uv[:, 0]
    v = per_corner_uv[:, 2] - per_corner_uv[:, 0]
    det = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
    good = valid_geo & (abs(det) > 1e-12)
    assert np.all(good[valid_geo])
    ft = np.zeros_like(a)
    fb = np.zeros_like(a)
    ft[good] = (a[good] * v[good, 1:2] - b[good] * u[good, 1:2]) / det[good, None]
    fb[good] = (b[good] * u[good, 0:1] - a[good] * v[good, 0:1]) / det[good, None]
    sign = np.where(np.einsum('fci,fi->fc', np.cross(corner_normals, ft[:, None, :]), fb) < 0, -1., 1.)
    sign[~good] = 1.
    # Existing degenerate faces carry no reliable UV gradient; keep them and
    # isolate their tangent fallback so they cannot pollute renderable neighbours.
    remap, owners, uvs, new_normals, handed, tris = {}, [], [], [], [], []
    for face_index, face in enumerate(I):
        row = []
        for corner, old in enumerate(face):
            uv = per_corner_uv[face_index, corner].astype('<f4')
            normal = corner_normals[face_index, corner]
            w = float(sign[face_index, corner])
            # A continuous lathe chart must also share its tangent accumulation
            # across the original narrow-strip UV vertex splits.
            identity = ('lathe', P[old].tobytes(), normal.tobytes()) if column_mask[face_index] else ('source', int(old))
            key = (identity, uv.tobytes(), normal.tobytes(), w, bool(good[face_index]))
            if key not in remap:
                remap[key] = len(owners)
                owners.append(old); uvs.append(uv); new_normals.append(normal); handed.append(w)
            row.append(remap[key])
        tris.append(row)
    owners = np.asarray(owners, dtype=np.int64)
    J = np.asarray(tris, dtype=np.uint32)
    result = {k: value[owners].copy() for k, value in data.items() if k != 'indices'}
    result['TEXCOORD_0'] = np.asarray(uvs, dtype='<f4')
    result['NORMAL'] = np.asarray(new_normals, dtype='<f4')
    result['indices'] = J
    # Angle weighted accumulation reduces bias at tiny bevel triangles.
    accum = np.zeros((len(owners), 3), dtype=np.float64)
    pts = P[I].astype(np.float64)
    for c in range(3):
        aa, bb = pts[:, (c + 1) % 3] - pts[:, c], pts[:, (c + 2) % 3] - pts[:, c]
        weight = np.arctan2(np.linalg.norm(np.cross(aa, bb), axis=1), (aa * bb).sum(1))
        weight[~good] = 0
        np.add.at(accum, J[:, c], ft * weight[:, None])
    nn = result['NORMAL'].astype(np.float64)
    nn /= np.maximum(np.linalg.norm(nn, axis=1)[:, None], 1e-30)
    t = accum - nn * (nn * accum).sum(1)[:, None]
    fallback = np.linalg.norm(t, axis=1) < 1e-12
    axis = np.zeros_like(nn)
    axis[np.arange(len(nn)), np.argmin(abs(nn), axis=1)] = 1
    t[fallback] = np.cross(axis[fallback], nn[fallback])
    t /= np.maximum(np.linalg.norm(t, axis=1)[:, None], 1e-30)
    result['TANGENT'] = np.column_stack([t, handed]).astype('<f4')
    assert np.array_equal(result['POSITION'][J], data['POSITION'][I])
    assert np.array_equal(result['NORMAL'][J][~normal_changed], data['NORMAL'][I][~normal_changed])
    assert np.array_equal(result['NORMAL'][J], corner_normals)
    if 'TEXCOORD_1' in data:
        assert np.array_equal(result['TEXCOORD_1'][J], data['TEXCOORD_1'][I])
    return result, {'recovered_uv1_triangles': int(recover.sum()),
                    'original_vertices': len(P), 'candidate_vertices': len(owners),
                    'vertex_count_delta': len(owners) - len(P),
                    'degenerate_geometry_preserved': int((~valid_geo).sum()),
                    'tangent_fallback_vertices': int(fallback.sum()),
                    'source_normal_anomaly_triangles': int(mixed_normal.sum()),
                    'normal_changed_corners': int(normal_changed.sum()),
                    'normal_repair_method': 'Only existing negative-hemisphere corners on the 30 listed mixed-normal faces: minimum angular rotation to cosine +0.10, retaining original tangent direction. All other corners byte-identical.',
                    'normal_max_rotation_degrees': max((c['rotation_degrees'] for e in normal_evidence for c in e['changes']), default=0),
                    'source_normal_anomaly_evidence': normal_evidence,
                    'cylindrical_columns': column_records}


def tangent_audit(data):
    P, N, U, I, T = (data[k] for k in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'indices', 'TANGENT'))
    a, b, u, v, area, det = face_data(P, U, I)
    good = (area > 2e-12) & (abs(det) > 1e-12)
    tb = (b[good] * u[good, 0:1] - a[good] * v[good, 0:1]) / det[good, None]
    tc = T[I[good]]
    predicted = np.where(np.einsum('fci,fi->fc', np.cross(N[I[good]], tc[:, :, :3]), tb) < 0, -1., 1.)
    mismatched = int((predicted != tc[:, :, 3]).sum())
    mixed = int((np.ptp(tc[:, :, 3], axis=1) != 0).sum())
    norms = np.linalg.norm(T[:, :3], axis=1)
    orth = abs((T[:, :3] * N).sum(1))
    assert np.isfinite(T).all() and np.max(abs(norms - 1)) < 2e-5
    assert orth.max() < 2e-5
    # Non-manifold or opposing source normals are not silently rewritten here.
    assert mismatched == 0 and mixed == 0, (mismatched, mixed)
    return {'valid_triangles_tested': int(good.sum()), 'handedness_mismatched_corners': mismatched,
            'mixed_handedness_triangles': mixed, 'max_tangent_normal_dot': float(orth.max()),
            'max_tangent_length_error': float(abs(norms - 1).max())}


def image_audit(doc, binary):
    rows = []
    for i, im in enumerate(doc['images']):
        blob = view(doc, binary, im['bufferView'])
        pic = Image.open(io.BytesIO(blob)); pic.load()
        pixels = np.asarray(pic)
        w, h = pic.size
        mip_bytes = 0
        while True:
            mip_bytes += w * h * 4
            if w == 1 and h == 1:
                break
            w, h = max(1, w // 2), max(1, h // 2)
        rows.append({'index': i, 'name': im.get('name'), 'encoded_sha256': sha(blob), 'encoded_bytes': len(blob),
                     'mode': pic.mode, 'dimensions': list(pic.size), 'decoded_sha256': sha(pixels.tobytes()),
                     'decoded_bytes': pixels.nbytes, 'rgba8_full_mips_budget_bytes': mip_bytes,
                     'rgb_std': np.std(np.asarray(pic.convert('RGB')), axis=(0, 1)).tolist()})
    return rows


def geometry_record(doc, binary):
    records = []
    for ni, n in enumerate(doc['nodes']):
        for pi, p in enumerate(doc['meshes'][n['mesh']]['primitives']):
            d = prim_data(doc, binary, p); i = d['indices']
            records.append({'node': ni, 'name': n['name'], 'primitive': pi, 'material': p['material'],
                            'triangle_count': len(i),
                            'per_corner_sha256': {key: sha(d[key][i].tobytes()) for key in ('POSITION', 'NORMAL')},
                            'bounds': [d['POSITION'].min(0).tolist(), d['POSITION'].max(0).tolist()],
                            'node_semantics': copy.deepcopy(n)})
    return records


def scan_source():
    source = json.loads((STONE / 'material.json').read_text(encoding='utf8'))
    assert source['material']['normal_format'] == 'opengl'
    for filename, expected in MAP_SHAS.items():
        assert file_sha(STONE / filename) == expected, filename
    return source


def make_images(version):
    source_rgb = (STONE / 'texture.jpg').read_bytes()
    rgb = source_rgb
    normal = (STONE / 'normal.png').read_bytes()
    r = np.asarray(Image.open(STONE / 'roughness.png').convert('L'))
    ao = np.asarray(Image.open(STONE / 'ao.png').convert('L'))
    assert r.shape == ao.shape == (2048, 2048)
    source_ao = ao.copy()
    formula = 'v1 source image bytes and AO pixels retained'
    mean = None
    if version == 'v2':
        pixels = np.asarray(Image.open(io.BytesIO(source_rgb)).convert('RGB')).astype(np.float64)
        mean = pixels.mean(axis=(0, 1), keepdims=True)
        derived = np.clip(np.rint(mean + .55 * (pixels - mean)), 0, 255).astype(np.uint8)
        buf = io.BytesIO(); Image.fromarray(derived).save(buf, format='PNG', optimize=True)
        rgb = buf.getvalue()
        ao = np.clip(np.rint(255. - .35 * (255. - ao.astype(np.float64))), 0, 255).astype(np.uint8)
        formula = 'albedo uint8 sRGB pixels: round(channel_mean + 0.55*(source-channel_mean)); AO linear data: round(255 - 0.35*(255-source_AO)); no added noise, no hue or lighting tint, no blur. This is intentional design adaptation, not lossless encoding.'
    orm = np.stack([ao, r, np.zeros_like(r)], axis=-1)
    buf = io.BytesIO(); Image.fromarray(orm).save(buf, format='PNG', optimize=True)
    return [normal, rgb, buf.getvalue()], {
        'albedo_encoded_identical_to_source': sha(rgb) == MAP_SHAS['texture.jpg'],
        'normal_encoded_identical_to_source': sha(normal) == MAP_SHAS['normal.png'],
        'normal_format': 'opengl', 'normal_y_flip': False,
        'orm_r_ao_decoded_sha256': sha(ao.tobytes()),
        'source_ao_decoded_sha256': sha(source_ao.tobytes()),
        'orm_g_roughness_decoded_sha256': sha(r.tobytes()),
        'orm_b_metallic': 0, 'source_roughness_decoded_pixels_preserved': True,
        'source_ao_decoded_pixels_preserved': version == 'v1', 'derivation_formula': formula,
        'source_srgb_channel_means': mean.flatten().tolist() if mean is not None else None,
        'ao_strength_baked_in_data': .35 if version == 'v2' else 1., 'gltf_occlusion_strength': 1.,
    }


def build_one(asset_id, blobs, version):
    path = LIBRARY / (SOURCES[asset_id] + '.glb')
    doc, binary, original = read_glb(path)
    assert sha(original) == SOURCES[asset_id]
    strict_schema(doc)
    baseline_doc, baseline_binary = copy.deepcopy(doc), bytearray(binary)
    original_geometry = geometry_record(doc, binary)
    stone = doc['materials'][0]
    assert stone['pbrMetallicRoughness'].get('baseColorFactor', [1, 1, 1, 1]) == [1, 1, 1, 1]
    assert len(doc['images']) == 3 and len(doc['textures']) == 3
    for i, (blob, name, mime) in enumerate(zip(blobs,
            ['S12 Beach Cliff OpenGL normal', 'S12 Beach Cliff worked limestone albedo '+version, 'S12 Beach Cliff packed AO roughness metallic '+version],
            ['image/png', 'image/png' if version == 'v2' else 'image/jpeg', 'image/png'])):
        doc['images'][i] = {'bufferView': append_view(doc, binary, blob), 'mimeType': mime, 'name': name}
    stone['name'] = 'S12 worked limestone | Beach Cliff scan '+version+' 20261015'
    old_provenance = stone.get('extras', {}).get('provenance', '')
    stone['extras'] = {'base_provenance': old_provenance,
                      'provenance': ('Owned Quixel Megascans Beach Cliff scan; worked-stone color contrast 0.55 around source channel means; AO contrast baked at 0.35. Original OpenGL normal and roughness pixels. Intentional material adaptation; no new noise or mortar.' if version == 'v2' else 'Owned Quixel Megascans Beach Cliff scan; original albedo/OpenGL normal; exact AO and roughness pixels packed ORM.'),
                      'repair_recipe': ('S12 20261015 '+version+'; non-column and meridian period 2m; columns one circumference repeat with rear seam; white baseColorFactor; metallic zero; valid UV1 recovered where UV0 collapsed; explicit TANGENT; 40 authorized source-normal corner corrections on relief.' if version == 'v2' else 'S12 20261015 v1; 2m period; normal scale 0.40; white baseColorFactor; metallic zero; valid secondary UV recovered only where active UV collapsed; explicit seam-safe TANGENT.')}
    stone['normalTexture'] = {'index': 0, 'texCoord': 0, 'scale': .12 if version == 'v2' else .40}
    stone['occlusionTexture'] = {'index': 2, 'texCoord': 0, 'strength': 1.0}
    stone['pbrMetallicRoughness'] = {'baseColorFactor': [1., 1., 1., 1.], 'baseColorTexture': {'index': 1, 'texCoord': 0},
                                   'metallicFactor': 0., 'roughnessFactor': 1.,
                                   'metallicRoughnessTexture': {'index': 2, 'texCoord': 0}}
    changes = []
    for mi, mesh in enumerate(doc['meshes']):
        for pi, p in enumerate(mesh['primitives']):
            if p['material'] != 0:
                continue
            before = prim_data(doc, binary, p)
            after, details = build_uv_tangents(before, allow_source_normal_repair=asset_id == 's12_gable_relief' and mi == 1 and pi == 0,
                                               repair_columns=version == 'v2' and asset_id == 's12_projecting_arch' and mi == 0 and pi == 0)
            audit = tangent_audit(after)
            for key, value in after.items():
                if key == 'indices':
                    p['indices'] = append_accessor(doc, binary, value, 'SCALAR')
                else:
                    p['attributes'][key] = append_accessor(doc, binary, value, f'VEC{value.shape[1]}')
            changes.append({'mesh': mi, 'primitive': pi, 'before': uv_metrics(before), 'after': uv_metrics(after),
                            'uv_repair': details, 'tangent_audit': audit})
    doc, binary = compact(doc, binary)
    assert doc['nodes'] == baseline_doc['nodes'], 'Node identities/transforms/extras changed'
    final_geometry = geometry_record(doc, binary)
    for old, new in zip(original_geometry, final_geometry):
        a, b = copy.deepcopy(old), copy.deepcopy(new)
        a['per_corner_sha256'].pop('NORMAL'); b['per_corner_sha256'].pop('NORMAL')
        assert a == b, 'Geometry or topology order changed'
    if len(doc['materials']) > 1:
        assert doc['materials'][1] == baseline_doc['materials'][1], 'Iron material changed'
        for mi, mesh in enumerate(doc['meshes']):
            for pi, p in enumerate(mesh['primitives']):
                if p['material'] == 0:
                    continue
                old = prim_data(baseline_doc, baseline_binary, baseline_doc['meshes'][mi]['primitives'][pi])
                new = prim_data(doc, binary, p)
                assert old.keys() == new.keys() and all(np.array_equal(old[k], new[k]) for k in old)
    reach = reachable(doc)
    assert all(len(reach[k]) == len(doc[k]) for k in reach)
    raw = encode_glb(doc, binary)
    return raw, {'id': asset_id, 'source_path': str(path), 'source_sha256': sha(original), 'source_bytes': len(original),
                 'original_source_material': baseline_doc['materials'][0], 'candidate_material': doc['materials'][0],
                 'source_images': image_audit(baseline_doc, baseline_binary), 'candidate_images': image_audit(doc, binary),
                 'source_geometry': original_geometry, 'candidate_geometry': geometry_record(doc, binary),
                 'per_corner_position_and_triangle_order_identical': True,
                 'per_corner_normal_identical': all(r['uv_repair']['normal_changed_corners'] == 0 for r in changes),
                 'normals_identical_outside_explicit_corner_allowlist': True,
                 'node_names_transforms_extras_collision_groups_identical': True,
                 'iron_material_geometry_all_original_attributes_identical': True if len(doc['materials']) > 1 else 'not applicable',
                 'secondary_uv_per_triangle_corner_preserved': True, 'primitive_repairs': changes,
                 'complete_known_dependency_graph': reach, 'all_stored_resources_reachable': True,
                 'candidate_sha256': sha(raw), 'candidate_bytes': len(raw),
                 'resource_status': 'CPU checks passed; independent audit pending',
                 'visual_status': 'pending actual fixed-camera GPU review',
                 'runtime_pipeline_status': 'pending native import/save/reopen',
                 'formal_library_and_map_integration_status': 'not published'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='write only isolated v2 candidates and audit')
    parser.add_argument('--version', choices=['v2'], default='v2', help='v1 remains reproducible with its archived builder')
    parser.add_argument('--asset', choices=list(SOURCES), action='append', help='limit candidate preparation to this asset')
    args = parser.parse_args()
    source = scan_source()
    guards = [LIBRARY / (v + '.glb') for v in SOURCES.values()]
    guards += [LIBRARY / 'library.json', STONE / 'material.json'] + [STONE / n for n in MAP_SHAS]
    guards += [OUT / 'v1' / (asset_id + '.glb') for asset_id in SOURCES]
    guards += [REPORT / 'v1/build_audit.json', OUT / 'v1/repair_s12_stone_materials.py']
    protected = {str(p): file_sha(p) for p in guards}
    if not args.build:
        result = {}
        for asset_id, expected in SOURCES.items():
            d, b, raw = read_glb(LIBRARY / (expected + '.glb'))
            assert sha(raw) == expected
            reachable(d)
            result[asset_id] = {'sha256': expected, 'geometry': geometry_record(d, b), 'images': image_audit(d, b),
                                'uv': [uv_metrics(prim_data(d, b, p)) for m in d['meshes'] for p in m['primitives']]}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    version = args.version
    blobs, packing = make_images(version)
    selected = args.asset or list(SOURCES)
    products = [build_one(asset_id, blobs, version) for asset_id in selected]
    assert all(file_sha(p) == h for p, h in protected.items()), 'Protected source changed during build'
    paths = [OUT / version / (row['id'] + '.glb') for _, row in products]
    derived = {OUT / version / 'materials/worked_limestone_albedo.png': blobs[1],
               OUT / version / 'materials/worked_limestone_orm.png': blobs[2]}
    # Never overwrite a prior distinct candidate; this is also safe for a
    # deterministic rerun whose existing artifacts are already byte-identical.
    for path, (blob, _) in zip(paths, products):
        assert not path.exists() or file_sha(path) == sha(blob), f'Existing different candidate: {path}'
    for path, blob in derived.items():
        assert not path.exists() or file_sha(path) == sha(blob), f'Existing different derived map: {path}'
    (OUT / version / 'materials').mkdir(parents=True, exist_ok=True)
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / version).mkdir(parents=True, exist_ok=True)
    for path, blob in derived.items():
        if not path.exists():
            path.write_bytes(blob)
    for path, (blob, row) in zip(paths, products):
        if not path.exists():
            path.write_bytes(blob)
        row['candidate_path'] = str(path)
        d, b, raw = read_glb(path)
        assert sha(raw) == row['candidate_sha256'] and geometry_record(d, b) == row['candidate_geometry']
        v1path = OUT / 'v1' / (row['id'] + '.glb')
        vd, vb, vr = read_glb(v1path)
        assert geometry_record(d, b) == geometry_record(vd, vb), 'v2 geometry or normals changed versus v1'
        row['v1_path'] = str(v1path)
        row['v1_sha256'] = sha(vr)
        row['v1_per_corner_position_normal_and_triangle_order_identical'] = True
        if row['id'] == 's12_gable_relief':
            for mi, mesh in enumerate(d['meshes']):
                for pi, p in enumerate(mesh['primitives']):
                    a, c = prim_data(d, b, p), prim_data(vd, vb, vd['meshes'][mi]['primitives'][pi])
                    assert a.keys() == c.keys() and all(np.array_equal(a[k], c[k]) for k in a)
            row['relief_all_geometry_uv_tangent_and_normal_arrays_identical_to_v1'] = True
    assert all(file_sha(p) == h for p, h in protected.items())
    report = {'schema_version': 2, 'date': '2026-10-15', 'recipe': 's12_beach_cliff_worked_stone_'+version,
              'builder_path': str(Path(__file__).resolve()), 'builder_sha256': file_sha(__file__),
              'selection': {'scan': 'Beach Cliff', 'non_column_tile_size_m': [2., 2.], 'normal_format': 'opengl', 'normal_scale': .12,
                            'column_u': 'one complete repeat per actual circumference; see per-ring metre density; closed rear seam',
                            'column_v_meridian_m_per_repeat': 2., 'albedo_contrast_about_each_srgb_channel_mean': .55,
                            'ao_contrast_baked_in_data': .35, 'gltf_ao_strength': 1.,
                            'base_color_factor': [1, 1, 1, 1], 'metallic': 0, 'roughness_factor': 1},
              'source_material_path': str(STONE / 'material.json'), 'source_material_sha256': file_sha(STONE / 'material.json'),
              'source_material_definition': source,
              'source_maps': {name: {'path': str(STONE / name), 'sha256': h} for name, h in MAP_SHAS.items()},
              'derived_maps': [{'path': str(p), 'sha256': sha(blob), 'encoded_bytes': len(blob), 'use': 'exact pixels/bytes embedded in both runtime GLBs; these files are source copies, do not add them again to runtime image budget'} for p, blob in derived.items()],
              'channel_packing': packing, 'models': [r for _, r in products],
              'protected_files': protected, 'protected_files_unchanged': True,
              'write_scope': [str(p) for p in paths] + [str(p) for p in derived] + [str(REPORT / 'build_audit.json'), str(REPORT / version / 'build_audit.json')],
              'original_maps_and_other_assets': 'not written; guard covers listed source files/catalog only, not a claim of full-tree SHA traversal',
              'geometry_degenerates': 'Existing 1,104 degenerate triangles in relief ornament preserved in original order; not repaired in this material-only change.',
              'cost_note': 'Image decoded bytes and exact RGBA8+mip budgets are separate from source file size; native/RSS/VRAM not measured. Shared image SHAs may be deduplicated for batch estimates; instances do not multiply shared GPU textures.',
              'lod_decision': 'No decimation in material repair; original geometry and collision groups retained. Existing native/LOD must be regenerated and reviewed with the new source SHA.',
              'visual_risk': 'v1 rejected for stripwise cylinder UV and oversized cliff relief. v2 has continuous integer-wrap cylindrical side UV, reduced source color contrast, normal scale .12, baked AO .35. Still pending actual same-camera review of cut-stone identity, cap joins, both sides and grazing light; no claim of visual acceptance from UV checks.'}
    encoded_report = json.dumps(report, ensure_ascii=False, indent=2)
    (REPORT / 'build_audit.json').write_text(encoded_report, encoding='utf8')
    (REPORT / version / 'build_audit.json').write_text(encoded_report, encoding='utf8')
    print(json.dumps({'status': 'CPU candidate built; GPU/native/independent review pending',
                      'models': [{k: row[k] for k in ('id', 'candidate_path', 'candidate_sha256', 'candidate_bytes')} for _, row in products],
                      'report': str(REPORT / 'build_audit.json')}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
