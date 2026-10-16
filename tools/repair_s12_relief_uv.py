"""UV-only v3 repair of S12's 23 worked-stone leaves. CPU, isolated outputs.

The v2 material, every triangle corner POSITION/NORMAL, triangle order, secondary
UV, semantic node data and the accepted v2 arch stay unchanged. Default inspects
in memory; --build writes only v3 relief and its audit.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import numpy as np

import repair_s12_stone_materials as base

V2 = base.OUT / 'v2/s12_gable_relief.glb'
V2_SHA = '42578d536dda46383e1e736d14a7f263c6c7295932d5c620fd6e1d22b0e2bab6'
ARCH = base.OUT / 'v2/s12_projecting_arch.glb'
ARCH_SHA = '2ac0241ac0a665aaf2c61e7778111ca1ea9f9508351bebc3b6f630fa1234221d'
ORIGINAL = base.LIBRARY / (base.SOURCES['s12_gable_relief'] + '.glb')
OUT = base.OUT / 'v3/s12_gable_relief.glb'
AUDIT = base.REPORT / 'v3/build_audit.json'


def original_leaf_runs(original):
    _, _, _, _, _, det = base.face_data(original['POSITION'], original['TEXCOORD_0'], original['indices'])
    bad = abs(det) < 1e-12
    runs, start = [], None
    for i, active in enumerate(np.r_[bad, False]):
        if active and start is None:
            start = i
        elif not active and start is not None:
            runs.append((start, i)); start = None
    assert len(runs) == 23 and all(b - a == 360 for a, b in runs)
    return runs


def leaf_uvs(data, original):
    P, I = data['POSITION'], data['indices']
    pc = P[I].astype(np.float64)
    old_uv = data['TEXCOORD_0'][I]
    uv = old_uv.astype(np.float64).copy()
    labels = np.full(len(I), -1, dtype=np.int32)
    _, first, weld = np.unique(np.round(P, 6), axis=0, return_index=True, return_inverse=True)
    W = P[first].astype(np.float64)
    a, b = pc[:, 1] - pc[:, 0], pc[:, 2] - pc[:, 0]
    area2 = np.linalg.norm(np.cross(a, b), axis=1)
    valid_geo = area2 > 2e-12
    records = []
    for leaf_id, (start, end) in enumerate(original_leaf_runs(original)):
        faces = np.arange(start, end)
        labels[faces] = leaf_id
        tri = pc[faces]
        front = faces[tri[:, :, 2].min(1) > .035001]
        back = faces[tri[:, :, 2].max(1) < .035001]
        side = np.setdiff1d(faces, np.r_[front, back])
        assert (len(front), len(back), len(side)) == (144, 144, 72)
        assert int((~valid_geo[faces]).sum()) == 48
        # One world-metric chart across the entire curved front. The shallow
        # relief depth creates modest projected foreshortening, explicitly
        # measured below; no per-face rotation or per-triangle colour islands.
        uv[faces] = pc[faces, :, :2] / 2
        uv[faces, :, 1] = 1 - uv[faces, :, 1]
        edge_counts = {}
        for f in front[valid_geo[front]]:
            ids = weld[I[f]]
            for aa, bb in zip(ids, np.roll(ids, -1)):
                key = tuple(sorted((int(aa), int(bb))))
                edge_counts[key] = edge_counts.get(key, 0) + 1
        outline_edges = [e for e, count in edge_counts.items() if count == 1]
        adjacency = {}
        for aa, bb in outline_edges:
            adjacency.setdefault(aa, []).append(bb)
            adjacency.setdefault(bb, []).append(aa)
        assert len(outline_edges) == 24 and all(len(v) == 2 for v in adjacency.values())
        loop = [min(adjacency)]
        previous = None
        while True:
            nxt = next(v for v in adjacency[loop[-1]] if v != previous)
            previous = loop[-1]
            if nxt == loop[0]:
                break
            assert nxt not in loop
            loop.append(nxt)
        xy = W[loop, :2]
        signed_area = np.sum(xy[:, 0] * np.roll(xy[:, 1], -1) - xy[:, 1] * np.roll(xy[:, 0], -1))
        if signed_area < 0:
            loop.reverse(); xy = W[loop, :2]
        edge = np.roll(xy, -1, axis=0) - xy
        edge /= np.linalg.norm(edge, axis=1)[:, None]
        outward = np.stack([edge[:, 1], -edge[:, 0]], axis=1)
        outward += np.roll(outward, 1, axis=0)
        outward /= np.linalg.norm(outward, axis=1)[:, None]
        outline_lookup = {tuple(np.round(W[w, :2], 6)): k for k, w in enumerate(loop)}
        # Unfold a continuous side band away from the original front outline.
        # Front-edge UV stays EXACTLY the front chart. Rear-edge seam lies at
        # z=.035, inside the masonry slab, leaving all visible front/side edges
        # continuous. The back itself retains a separate planar metric chart.
        for f in side:
            for c, point in enumerate(pc[f]):
                if point[2] > .035001:
                    continue
                k = outline_lookup[tuple(np.round(point[:2], 6))]
                thickness = W[loop[k], 2] - point[2]
                extended = point[:2] + outward[k] * thickness
                uv[f, c] = [extended[0] / 2, 1 - extended[1] / 2]
        new = uv[faces]
        du, dv = new[:, 1] - new[:, 0], new[:, 2] - new[:, 0]
        det = du[:, 0] * dv[:, 1] - du[:, 1] * dv[:, 0]
        assert np.all(abs(det[valid_geo[faces]]) > 1e-12)
        assert np.all(det[np.isin(faces, front) & valid_geo[faces]] < 0)
        assert np.all(det[np.isin(faces, side) & valid_geo[faces]] < 0)
        assert np.all(det[np.isin(faces, back) & valid_geo[faces]] > 0)
        # Compare actual UV at every shared edge. Hard/smooth normals do not
        # excuse a colour discontinuity; only the explicit buried rear loop may
        # differ. Existing zero-area faces are retained but excluded from this
        # manifold surface check.
        shared = {}
        for f in faces[valid_geo[faces]]:
            ids = weld[I[f]]
            for c in range(3):
                ca, cb = c, (c + 1) % 3
                key = tuple(sorted((int(ids[ca]), int(ids[cb]))))
                shared.setdefault(key, []).append((int(f), ca, cb))
        seams = []
        continuous = 0
        for key, entries in shared.items():
            assert len(entries) == 2, (leaf_id, key, entries)
            pair_uvs = []
            for f, ca, cb in entries:
                pair_uvs.append(np.array([uv[f, ca if weld[I[f, ca]] == wid else cb] for wid in key]))
            if not np.allclose(pair_uvs[0], pair_uvs[1], rtol=0, atol=2e-7):
                assert np.max(abs(W[list(key), 2] - .035)) < 2e-6, 'Unexpected visible UV seam'
                seams.append({'welded_edge': list(key), 'positions': W[list(key)].tolist(),
                              'triangles': [e[0] for e in entries], 'uv_pairs': [u.tolist() for u in pair_uvs]})
            else:
                continuous += 1
        assert len(seams) == 24
        records.append({'leaf': leaf_id, 'triangle_start': int(start), 'triangle_end_exclusive': int(end),
                        'front_triangle_ids': front.tolist(), 'side_triangle_ids': side.tolist(), 'back_triangle_ids': back.tolist(),
                        'source_zero_area_triangles_retained': int((~valid_geo[faces]).sum()),
                        'outline_positions': W[loop].tolist(), 'continuous_shared_edges': continuous,
                        'buried_rear_seam_edges': seams, 'unexpected_front_side_or_back_interior_uv_seams': 0,
                        'method': 'front/back XY planar 2m projection; continuous front-outline side band unfolded by actual depth, with all chart cuts on buried back z=.035',
                        'bounds': [pc[faces].min((0, 1)).tolist(), pc[faces].max((0, 1)).tolist()]})
    assert np.array_equal(uv[labels < 0].astype('<f4'), old_uv[labels < 0])
    return uv.astype('<f4'), labels, records


def rebuild_leaf_frames(data, uv, labels, isolated_corners=None, iteration=0):
    isolated_corners = set() if isolated_corners is None else isolated_corners
    P, N, I = data['POSITION'], data['NORMAL'], data['indices']
    pts = P[I].astype(np.float64)
    a, b = pts[:, 1] - pts[:, 0], pts[:, 2] - pts[:, 0]
    u, v = uv[:, 1].astype(float) - uv[:, 0], uv[:, 2].astype(float) - uv[:, 0]
    det = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
    valid = np.linalg.norm(np.cross(a, b), axis=1) > 2e-12
    touched = labels >= 0
    good = touched & valid
    assert np.all(abs(det[good]) > 1e-12)
    ft, fb = np.zeros_like(a), np.zeros_like(a)
    ft[good] = (a[good] * v[good, 1:2] - b[good] * u[good, 1:2]) / det[good, None]
    fb[good] = (b[good] * u[good, 0:1] - a[good] * v[good, 0:1]) / det[good, None]
    sign = np.where(np.einsum('fci,fi->fc', np.cross(N[I], ft[:, None]), fb) < 0, -1., 1.)
    assert not np.any(np.ptp(sign[good], axis=1) != 0)
    remap, frame_map, frame_sums = {}, {}, []
    owners, uv_values, frame_ids, old_tangents, out_indices = [], [], [], [], []
    for f, face in enumerate(I):
        row = []
        for c, old in enumerate(face):
            if good[f]:
                key = (int(labels[f]), P[old].tobytes(), N[old].tobytes(), uv[f, c].tobytes(),
                       (int(f), c) if (int(f), c) in isolated_corners else None, float(sign[f, c]))
                if key not in frame_map:
                    frame_map[key] = len(frame_sums); frame_sums.append(np.zeros(3))
                frame = frame_map[key]
                aa, bb = pts[f, (c + 1) % 3] - pts[f, c], pts[f, (c + 2) % 3] - pts[f, c]
                angle = np.arctan2(np.linalg.norm(np.cross(aa, bb)), np.dot(aa, bb))
                frame_sums[frame] += ft[f] * angle
            else:
                frame = -1
            # Retain secondary UV even though it no longer drives the material.
            # It must not split tangent averaging at old per-face UV1 islands.
            out_key = (int(old), uv[f, c].tobytes(), frame)
            if out_key not in remap:
                remap[out_key] = len(owners)
                owners.append(old); uv_values.append(uv[f, c]); frame_ids.append(frame)
                old_tangents.append(data['TANGENT'][old])
            row.append(remap[out_key])
        out_indices.append(row)
    owners = np.asarray(owners, dtype=np.int64)
    result = {k: v[owners].copy() for k, v in data.items() if k != 'indices'}
    result['indices'] = np.asarray(out_indices, dtype=np.uint32)
    result['TEXCOORD_0'] = np.asarray(uv_values, dtype='<f4')
    tangent = np.asarray(old_tangents, dtype='<f4')
    sums = np.asarray(frame_sums)
    frame_w = np.array([key[-1] for key in frame_map])
    for i, frame in enumerate(frame_ids):
        if frame < 0:
            continue  # Unchanged faces and old degenerate faces keep old T.
        normal = result['NORMAL'][i].astype(np.float64)
        normal /= np.linalg.norm(normal)
        t = sums[frame] - normal * np.dot(sums[frame], normal)
        assert np.linalg.norm(t) > 1e-12
        tangent[i] = np.r_[t / np.linalg.norm(t), frame_w[frame]]
    result['TANGENT'] = tangent
    J = result['indices']
    for k in ('POSITION', 'NORMAL', 'TEXCOORD_1'):
        assert np.array_equal(result[k][J], data[k][I]), k
    for k in data.keys() - {'indices'}:
        assert np.array_equal(result[k][J][~touched], data[k][I][~touched]), k
    # Extreme pre-existing pipe turns can make a shared averaged tangent cross
    # a UV-gradient half-plane even though every individual frame is valid.
    # Split only such tangent corners (UV and N remain continuous/unchanged),
    # retaining the actual per-face UV derivative, never forcing the w sign.
    face_ids = np.where(good)[0]
    tc = result['TANGENT'][J[good]]
    expected = np.where(np.einsum('fci,fi->fc', np.cross(result['NORMAL'][J[good]], tc[:, :, :3]), fb[good]) < 0, -1., 1.)
    bad = np.argwhere(expected != tc[:, :, 3])
    if len(bad):
        additions = {(int(face_ids[f]), int(c)) for f, c in bad}
        assert additions - isolated_corners and iteration < 8, 'A per-corner derivative failed TBN; do not force handedness'
        return rebuild_leaf_frames(data, uv, labels, isolated_corners | additions, iteration + 1)
    audit = base.tangent_audit(result)
    audit['isolated_tangent_corners_at_extreme_source_turns'] = [list(x) for x in sorted(isolated_corners)]
    audit['tangent_averaging_refinement_iterations'] = iteration
    return result, audit


def tube_uvs(data, uv, labels):
    """Recover actual 8-vertex rings and quad connections from the GLB.

    No assumptions about exported vertex numbering or Blender frames: each
    segment's 16 triangles identify its two rings; original quad boundary edges
    identify longitudinal correspondence, excluding triangulation diagonals.
    """
    P, I = data['POSITION'], data['indices']
    _, first, weld = np.unique(np.round(P, 6), axis=0, return_index=True, return_inverse=True)
    W = P[first].astype(np.float64)
    parent = np.arange(len(W))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for tri in weld[I]:
        root = find(tri[0])
        for v in tri[1:]:
            parent[find(v)] = root
    roots = np.array([find(v) for v in weld[I[:, 0]]])
    records = []
    for root in sorted(np.unique(roots), key=lambda r: np.where(roots == r)[0][0]):
        faces = np.where(roots == root)[0]
        if np.any(labels[faces] >= 0):
            continue
        assert np.array_equal(faces, np.arange(faces[0], faces[-1] + 1))
        assert len(faces) in (112, 272, 1152, 2384)
        segments = faces.reshape(-1, 16)
        segment_points = [set(weld[I[g]].ravel()) for g in segments]
        assert all(len(g) == 16 for g in segment_points)
        middle = [segment_points[i] & segment_points[i + 1] for i in range(len(segments) - 1)]
        rings = [segment_points[0] - middle[0]] + middle + [segment_points[-1] - middle[-1]]
        assert all(len(r) == 8 for r in rings)
        centres = np.array([W[list(r)].mean(0) for r in rings])
        maps = []
        ring0_edges = set()
        for seg, group in enumerate(segments):
            mapping = {}
            for pair in group.reshape(-1, 2):
                counts = {}
                for f in pair:
                    ids = weld[I[f]]
                    for c in range(3):
                        key = tuple(sorted((int(ids[c]), int(ids[(c + 1) % 3]))))
                        counts[key] = counts.get(key, 0) + 1
                assert len(counts) == 5 and sorted(counts.values()) == [1, 1, 1, 1, 2]
                for (aa, bb), count in counts.items():
                    if count != 1:
                        continue
                    if aa in rings[seg] and bb in rings[seg + 1]:
                        assert aa not in mapping or mapping[aa] == bb
                        mapping[aa] = bb
                    if bb in rings[seg] and aa in rings[seg + 1]:
                        assert bb not in mapping or mapping[bb] == aa
                        mapping[bb] = aa
                    if seg == 0 and aa in rings[0] and bb in rings[0]:
                        ring0_edges.add((aa, bb))
            assert len(mapping) == 8 and set(mapping.values()) == rings[seg + 1]
            maps.append(mapping)
        adjacency = {}
        for aa, bb in ring0_edges:
            adjacency.setdefault(aa, []).append(bb); adjacency.setdefault(bb, []).append(aa)
        assert len(adjacency) == 8 and all(len(v) == 2 for v in adjacency.values())
        rear = min(rings[0], key=lambda wid: (W[wid, 2], W[wid, 0], W[wid, 1]))
        neighbours = adjacency[rear]
        direction = centres[1] - centres[0]
        next_vertex = max(neighbours, key=lambda wid: np.dot(np.cross(W[rear] - centres[0], W[wid] - centres[0]), direction))
        ring_order = [rear, next_vertex]
        while len(ring_order) < 8:
            ring_order.append(next(x for x in adjacency[ring_order[-1]] if x != ring_order[-2]))
        assert len(set(ring_order)) == 8 and rear in adjacency[ring_order[-1]]
        ordered = [ring_order]
        for mapping in maps:
            ordered.append([mapping[x] for x in ordered[-1]])
        radii = np.array([np.linalg.norm(W[order] - centre, axis=1).mean() for order, centre in zip(ordered, centres)])
        ring_deviation = [float(np.ptp(np.linalg.norm(W[order] - centre, axis=1))) for order, centre in zip(ordered, centres)]
        assert max(ring_deviation) < 2e-6
        path_arc = np.r_[0., np.cumsum(np.linalg.norm(np.diff(centres, axis=0), axis=1))]
        closed = np.linalg.norm(centres[0] - centres[-1]) < 1e-6
        repeat_count = max(1, round(float(path_arc[-1] / 2))) if closed else None
        path_period = float(path_arc[-1] / repeat_count) if closed else 2.
        # U is real circumference arc/2m, V is real centreline arc/2m. Tiny
        # 7–22mm radii must NOT squeeze an entire 2m texture around each ring.
        # Closed border paths use the closest integer repeat to avoid a visible
        # phase jump at the closure; their actual metre period is reported.
        uv_offset = [centres[0, 0] / 2, 1 - centres[0, 1] / path_period]
        ring_js = [{wid: j for j, wid in enumerate(order)} for order in ordered]
        for seg, group in enumerate(segments):
            for f in group:
                coords = []
                for wid in weld[I[f]]:
                    ring = seg if wid in rings[seg] else seg + 1
                    coords.append((ring, ring_js[ring][int(wid)]))
                js = [x[1] for x in coords]
                wrap = max(js) - min(js) > 4
                for c, (ring, j) in enumerate(coords):
                    if wrap and j == 0:
                        j = 8
                    uv[f, c] = [uv_offset[0] + j * np.pi / 4 * radii[ring] / 2,
                                uv_offset[1] - path_arc[ring] / path_period]
        labels[faces] = 23 + len(records)
        seam_pairs = {tuple(sorted((ordered[k][0], ordered[k + 1][0]))) for k in range(len(segments))}
        edges = {}
        for f in faces:
            ids = weld[I[f]]
            for c in range(3):
                key = tuple(sorted((int(ids[c]), int(ids[(c + 1) % 3]))))
                edges.setdefault(key, []).append((int(f), c, (c + 1) % 3))
        seams, continuous, boundaries = [], 0, 0
        for key, entries in edges.items():
            if len(entries) == 1:
                boundaries += 1; continue  # Open ends of the original pipe.
            assert len(entries) == 2
            vals = []
            for f, aa, bb in entries:
                vals.append(np.array([uv[f, aa if weld[I[f, aa]] == wid else bb] for wid in key]))
            diff = vals[1] - vals[0]
            if np.max(abs(diff)) > 3e-7:
                assert key in seam_pairs, ('Unexpected visible tube UV jump', len(records), key, diff)
                seams.append({'welded_edge': list(key), 'positions': W[list(key)].tolist(),
                              'triangles': [e[0] for e in entries], 'uv_pairs': [x.tolist() for x in vals],
                              'occlusion_status': 'Rear-facing seam; exact slab/leaf or self-occlusion is an independent CPU/GPU check, not inferred from -Z alone.'})
            else:
                continuous += 1
        assert len(seams) == len(segments)
        radial = np.array([W[order[0]] - centre for order, centre in zip(ordered, centres)])
        rear_z_ratio = -radial[:, 2] / np.linalg.norm(radial, axis=1)
        assert rear_z_ratio.min() > .80, 'Seam ceased to point toward -Z rear'
        records.append({'tube': len(records), 'kind': {112: 'closed perimeter bead', 272: 'leaf central rib', 1152: 'scroll volute', 2384: 'ascending vine'}[len(faces)],
                        'triangle_ids': faces.tolist(), 'ring_centres': centres.tolist(), 'ring_welded_vertex_order': ordered,
                        'ring_radii_m': radii.tolist(), 'ring_max_radius_deviation_m': max(ring_deviation),
                        'path_arc_lengths_m': path_arc.tolist(), 'closed_path': bool(closed), 'closed_path_repeat_count': repeat_count,
                        'path_m_per_texture_repeat': path_period, 'path_texels_per_m': 2048 / path_period,
                        'circumference_m_per_texture_repeat': 2., 'circumference_texels_per_m': 1024.,
                        'actual_ring_circumferences_m': (2 * np.pi * radii).tolist(),
                        'uv_offset': uv_offset, 'rear_seam_edges': seams,
                        'rear_radial_negative_z_cosine_min': float(rear_z_ratio.min()),
                        'continuous_shared_edges': continuous, 'original_open_end_boundary_edges': boundaries,
                        'unexpected_nonrear_uv_discontinuities': 0,
                        'seam_exception': 'Noninteger circumference phase difference kept only on rear seam to preserve real stone scale. Actual occlusion must be checked; not all rear seams are necessarily embedded.'})
    assert len(records) == 36 and np.all(labels >= 0)
    return uv, labels, records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    guards = [V2, ARCH, ORIGINAL, base.LIBRARY / 'library.json', base.REPORT / 'v2/build_audit.json',
              Path(base.__file__)]
    before_sha = {str(p): base.file_sha(p) for p in guards}
    assert before_sha[str(V2)] == V2_SHA and before_sha[str(ARCH)] == ARCH_SHA
    assert before_sha[str(ORIGINAL)] == base.SOURCES['s12_gable_relief']
    doc, binary, old_raw = base.read_glb(V2)
    original_doc, original_binary, _ = base.read_glb(ORIGINAL)
    old_doc, old_binary = copy.deepcopy(doc), bytearray(binary)
    baseline_geo = base.geometry_record(doc, binary)
    p = doc['meshes'][1]['primitives'][0]
    data = base.prim_data(doc, binary, p)
    original = base.prim_data(original_doc, original_binary, original_doc['meshes'][1]['primitives'][0])
    for k in ('POSITION',):
        assert np.array_equal(data[k][data['indices']], original[k][original['indices']])
    uv, labels, leaves = leaf_uvs(data, original)
    uv, labels, tubes = tube_uvs(data, uv, labels)
    result, tangent_audit = rebuild_leaf_frames(data, uv, labels)
    for key, value in result.items():
        if key == 'indices':
            p['indices'] = base.append_accessor(doc, binary, value, 'SCALAR')
        else:
            p['attributes'][key] = base.append_accessor(doc, binary, value, f'VEC{value.shape[1]}')
    doc, binary = base.compact(doc, binary)
    assert doc['nodes'] == old_doc['nodes']
    assert doc['materials'] == old_doc['materials']
    assert base.geometry_record(doc, binary) == baseline_geo
    assert base.image_audit(doc, binary) == base.image_audit(old_doc, old_binary)
    for k in ('POSITION', 'NORMAL', 'TANGENT', 'TEXCOORD_0', 'indices'):
        new_base = base.prim_data(doc, binary, doc['meshes'][0]['primitives'][0])
        old_base = base.prim_data(old_doc, old_binary, old_doc['meshes'][0]['primitives'][0])
        assert np.array_equal(new_base[k], old_base[k]), 'Back slab primitive changed'
    raw = base.encode_glb(doc, binary)
    report = {'schema_version': 1, 'date': '2026-10-15', 'recipe': 's12_relief_v3_continuous_leaf_uv',
              'builder': str(Path(__file__).resolve()), 'builder_sha256': base.file_sha(__file__),
              'helper': str(Path(base.__file__).resolve()), 'helper_sha256': base.file_sha(base.__file__),
              'source_path': str(V2), 'source_sha256': V2_SHA, 'source_bytes': len(old_raw),
              'candidate_path': str(OUT), 'candidate_sha256': base.sha(raw), 'candidate_bytes': len(raw),
              'formal_origin_path': str(ORIGINAL), 'formal_origin_sha256': base.SOURCES['s12_gable_relief'],
              'frozen_accepted_arch_path': str(ARCH), 'frozen_accepted_arch_sha256': ARCH_SHA,
              'geometry': baseline_geo, 'per_corner_positions_normals_and_triangle_order_identical_to_v2': True,
              'secondary_uv_per_corner_identical_to_v2': True, 'back_slab_primitive_all_original_arrays_identical_to_v2': True,
              'nodes_transforms_extras_collision_semantics_identical': True, 'materials_identical_to_v2': True,
              'encoded_and_decoded_images_identical_to_v2': True, 'images': base.image_audit(doc, binary),
              'leaves': leaves, 'leaf_count': len(leaves), 'leaf_triangle_count': int((labels < 23).sum()),
              'tubes': tubes, 'tube_count': len(tubes), 'tube_triangle_count': int((labels >= 23).sum()),
              'geometry_degenerate_faces_preserved': int((~(np.linalg.norm(np.cross(data['POSITION'][data['indices'][:, 1]]-data['POSITION'][data['indices'][:, 0]], data['POSITION'][data['indices'][:, 2]]-data['POSITION'][data['indices'][:, 0]]), axis=1)>2e-12)).sum()),
              'before_uv_metrics': base.uv_metrics(data), 'after_uv_metrics': base.uv_metrics(result),
              'tangent_audit': tangent_audit,
              'continuous_shared_edges': sum(x['continuous_shared_edges'] for x in leaves),
              'buried_rear_seam_edges': sum(len(x['buried_rear_seam_edges']) for x in leaves),
              'unexpected_leaf_front_side_interior_uv_seams': 0,
              'tube_continuous_shared_edges': sum(x['continuous_shared_edges'] for x in tubes),
              'tube_explicit_rear_seam_edges': sum(len(x['rear_seam_edges']) for x in tubes),
              'unexpected_tube_nonrear_uv_discontinuities': 0,
              'protected_files': before_sha, 'protected_files_unchanged': all(base.file_sha(p) == h for p, h in before_sha.items()),
              'resource_status': 'CPU builder checks passed; independent audit pending', 'visual_status': 'pending same-camera GPU review',
              'runtime_pipeline_status': 'pending native import/save/reopen', 'formal_integration_status': 'not published',
              'scope': 'Leaf, vine, scroll, rib and perimeter bead UV0/TANGENT plus necessary vertex/index repack only. Current v2 PBR unchanged. No geometric loss claim; UV appearance is an intentional fix, not an encoded-lossless optimisation.',
              'cost_note': 'Same three embedded images as v2. Geometry count unchanged; native/RSS/VRAM not measured.'}
    assert report['protected_files_unchanged']
    encoded_report = json.dumps(report, ensure_ascii=False, indent=2,
                                default=lambda x: x.item() if isinstance(x, np.generic) else str(x))
    if args.build:
        assert not OUT.exists() or base.file_sha(OUT) == base.sha(raw)
        OUT.parent.mkdir(parents=True, exist_ok=True)
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        if not OUT.exists():
            OUT.write_bytes(raw)
        assert all(base.file_sha(p) == h for p, h in before_sha.items())
        AUDIT.write_text(encoded_report, encoding='utf8')
    print(json.dumps({k: report[k] for k in ('candidate_path', 'candidate_sha256', 'candidate_bytes', 'leaf_count',
                                            'continuous_shared_edges', 'buried_rear_seam_edges', 'tangent_audit')}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
