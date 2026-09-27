"""Independent NumPy audit of captured cloth against the actual posed body triangles.

Finite vertices are not sufficient for acceptance. Sample vertices and face interiors,
record penetration and stretch, and return nonzero while the geometric gate fails.
"""
import json
import sys
import numpy as np
from scipy.spatial import cKDTree
from art_paths import art_path, review_path
try:
    import igl  # Optional C++ implementation of the same exact winding sum.
except ImportError:
    igl = None


def winding_inside(points, triangles):
    """Classify against the whole oriented surface, not one nearby face plane.

    A face-normal dot product mislabels exterior points near finger edges.
    Solid-angle winding tolerates small openings in the imported body surface;
    this remains a sampled mesh audit, not proof of collision-free animation.
    """
    result = np.zeros(len(points), dtype=bool)
    if igl is not None and len(points):
        vertices = np.ascontiguousarray(triangles.reshape(-1, 3), dtype=np.float64)
        faces = np.arange(len(vertices), dtype=np.int64).reshape(-1, 3)
        return np.abs(igl.winding_number(vertices, faces, np.asarray(points, dtype=np.float64))) > .5
    for start in range(0, len(points), 8):
        relative = triangles[None] - points[start:start+8, None, None]
        a, b, c = relative[:, :, 0], relative[:, :, 1], relative[:, :, 2]
        la, lb, lc = (np.linalg.norm(v, axis=-1) for v in (a, b, c))
        numerator = np.einsum('...i,...i->...', a, np.cross(b, c))
        denominator = (la*lb*lc + np.einsum('...i,...i->...', a, b)*lc
                       + np.einsum('...i,...i->...', b, c)*la
                       + np.einsum('...i,...i->...', c, a)*lb)
        winding = np.sum(2*np.arctan2(numerator, denominator), axis=1)/(4*np.pi)
        result[start:start+8] = np.abs(winding) > .5
    return result


def closest_on_triangles(p, triangles):
    a, b, c = (triangles[:, :, i] for i in range(3))
    ab, ac = b-a, c-a
    n = np.cross(ab, ac)
    nn = np.maximum(np.sum(n*n, axis=-1), 1e-20)
    plane = p-n*(np.sum((p-a)*n, axis=-1)/nn)[..., None]
    u = np.sum(np.cross(plane-a, ac)*n, axis=-1)/nn
    v = np.sum(np.cross(ab, plane-a)*n, axis=-1)/nn
    inside = (u >= 0) & (v >= 0) & (u+v <= 1)
    choices = [plane]
    for start, end in ((a, b), (b, c), (c, a)):
        edge = end-start
        t = np.clip(np.sum((p-start)*edge, axis=-1)/np.maximum(np.sum(edge*edge, axis=-1), 1e-20), 0, 1)
        choices.append(start+edge*t[..., None])
    choices = np.stack(choices, axis=2)
    distances = np.sum((choices-p[:, :, None])**2, axis=-1)
    distances[:, :, 0] = np.where(inside, distances[:, :, 0], np.inf)
    selected = np.argmin(distances, axis=2)
    q = np.take_along_axis(choices, selected[..., None, None], axis=2)[:, :, 0]
    d = np.sum((q-p)**2, axis=-1)
    candidate = np.argmin(d, axis=1)
    row = np.arange(len(p))
    normal = -n[row, candidate]/np.sqrt(nn[row, candidate, None])
    return np.sum((p[:, 0]-q[row, candidate])*normal, axis=-1), np.sqrt(d[row, candidate])


def hand_intersections(vertices, body_faces, triangles, hand_vertices):
    """Actual hand-edge/cloth-triangle crossings catch holes missed by samples."""
    edges = set()
    for face in body_faces:
        for a, b in zip(face, np.roll(face, -1)):
            if a in hand_vertices and b in hand_vertices: edges.add(tuple(sorted((a, b))))
    edges = np.asarray(sorted(edges))
    centers = triangles.mean(axis=1)
    radius = np.linalg.norm(triangles-centers[:, None], axis=-1).max()
    tree = cKDTree(centers)
    crossed = 0
    for a, b in vertices[edges]:
        ids = tree.query_ball_point((a+b)/2, radius+np.linalg.norm(b-a)/2)
        if not ids: continue
        tri = triangles[ids]
        e1, e2, direction = tri[:, 1]-tri[:, 0], tri[:, 2]-tri[:, 0], b-a
        h = np.cross(direction, e2)
        determinant = np.sum(e1*h, axis=-1)
        valid = np.abs(determinant)>1e-12
        inverse = np.divide(1, determinant, out=np.zeros_like(determinant), where=valid)
        s = a-tri[:, 0]
        u = np.sum(s*h, axis=-1)*inverse
        q = np.cross(s, e1)
        v = np.sum(direction*q, axis=-1)*inverse
        t = np.sum(e2*q, axis=-1)*inverse
        hits = valid & (u>=0) & (v>=0) & (u+v<=1) & (t>.001) & (t<.999)
        if hits.any(): crossed += 1
    return crossed


def main():
    body = json.loads(art_path('characters/base/female_base_v2/female_display_topology.json').read_text())
    body_faces = np.asarray([(p[0], p[j], p[j+1]) for p in body['base_faces'] for j in range(1, len(p)-1)])
    rig = json.loads(art_path('characters/base/female_base_v2/female_axis_rig.json').read_text())
    hands = set()
    for node in rig['nodes']:
        if node['name'][1:].startswith(('Hand', 'Thumb', 'Index', 'Mid', 'Ring', 'Pinky', 'Carpal')):
            hands.update(node['full'])
            hands.update(w['vertex'] for w in node['weights'] if max(w['xweight'], w['yweight'], w['zweight'])>.01)
    complex_mode = '--complex' in sys.argv
    prefix = 'cloth_hw_' if complex_mode else 'cloth_'
    candidate_mode = '--candidate' in sys.argv
    if candidate_mode:
        # A body-contact pass alone used to label a self-intersecting skirt
        # accepted. Keep the independent open-surface gate in the default audit.
        from audit_cloth_self_intersections import intersections
    if candidate_mode: prefix = 'candidate_self_hw_' if '--self-contact' in sys.argv else 'candidate_hw_'
    results = []
    names = ['stand', 'step', 'sit'] if complex_mode else ['stand', 'elbow', 'reach', 'step', 'sit', 'lie']
    if candidate_mode: names = ['stand', 'sit_15', 'sit_30', 'sit_45', 'sit']
    if '--stand-only' in sys.argv: names = ['stand']
    for name in names:
        capture = json.loads(review_path('character_3d/'+prefix+name+'.json').read_text())
        garment = json.loads(art_path('characters/source_models/garment_validation_set/'+capture['garment_id']+'/clothing_data.json').read_text())
        garment_faces = np.asarray([(f['vertices'][0], f['vertices'][j], f['vertices'][j+1]) for f in garment['faces'] for j in range(1, len(f['vertices'])-1)])
        vertices, points = np.asarray(capture['body']), np.asarray(capture['garment'])
        triangles = vertices[body_faces]
        tree = cKDTree(triangles.mean(axis=1))
        samples = np.concatenate([points, points[garment_faces].mean(axis=1)])
        distances, depths = [], []
        for start in range(0, len(samples), 512):
            sample = samples[start:start+512]
            ids = tree.query(sample, k=48)[1]
            signed, distance = closest_on_triangles(sample[:, None], triangles[ids])
            depths.extend(signed); distances.extend(distance)
        depths, distances = np.asarray(depths), np.asarray(distances)
        normal_candidates = (depths < -.003) & (distances < .08)
        candidates = np.flatnonzero((distances > .003) & (distances < .08))
        inside = np.zeros(len(samples), dtype=bool)
        inside[candidates] = winding_inside(samples[candidates], triangles)
        result = dict(pose=name, samples=len(samples), penetrations_over_3mm=int(inside.sum()),
                      deepest_sample_m=float(distances[inside].max()) if inside.any() else 0,
                      legacy_normal_candidates=int(normal_candidates.sum()),
                      volume_method='solid_angle_winding',
                      below_floor=int(np.sum(samples[:, 1] < capture['floor']-.003)))
        result['hand_edge_crossings'] = hand_intersections(vertices, body_faces, points[garment_faces], hands)
        scene_inside = np.zeros(len(samples), dtype=bool)
        body_scene_inside = np.zeros(len(vertices), dtype=bool)
        for box in capture.get('scene_boxes', []):
            transform = np.asarray(box['local_from_cloth'])
            local = samples @ transform[:3] + transform[3]
            scene_inside |= np.all(np.asarray(box['size'])/2 - np.abs(local) > .003, axis=1)
            body_local = vertices @ transform[:3] + transform[3]
            body_scene_inside |= np.all(np.asarray(box['size'])/2 - np.abs(body_local) > .003, axis=1)
        result['scene_penetrations_over_3mm'] = int(scene_inside.sum())
        result['body_scene_penetrations_over_3mm'] = int(body_scene_inside.sum())
        binding = json.loads(art_path('characters/equipment/surface_bound/'+capture['garment_id']+'/binding.json').read_text())
        edges = np.asarray([e for e in binding['edges'] if e[2] >= .0005])
        ratio = np.linalg.norm(points[edges[:, 0].astype(int)]-points[edges[:, 1].astype(int)], axis=1)/edges[:, 2]
        result['maximum_edge_ratio'] = float(ratio.max())
        result['edges_stretched_over_50_percent'] = int(np.sum(ratio > 1.5))
        if candidate_mode:
            crossing, coplanar, degenerate = intersections(points, garment_faces)
            result['self_crossing_pairs'] = len(crossing)
            result['self_coplanar_pairs'] = len(coplanar)
            result['degenerate_cloth_faces'] = len(degenerate)
        result['accepted'] = (result['penetrations_over_3mm'] == 0 and result['below_floor'] == 0
                              and result['scene_penetrations_over_3mm'] == 0
                              and result['body_scene_penetrations_over_3mm'] == 0
                              and result['hand_edge_crossings'] == 0 and result['edges_stretched_over_50_percent'] == 0)
        if candidate_mode:
            result['accepted'] = result['accepted'] and not (
                result['self_crossing_pairs'] or result['self_coplanar_pairs'] or result['degenerate_cloth_faces'])
        results.append(result)
        print(json.dumps(result), flush=True)
    review_path('character_3d/'+prefix+'contact_audit.json').write_text(json.dumps(results, indent=2))
    return 0 if all(r['accepted'] for r in results) else 2


if __name__ == '__main__': sys.exit(main())
