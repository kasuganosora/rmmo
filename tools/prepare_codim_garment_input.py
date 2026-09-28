"""Export unchanged HW/body rest meshes and audit the reference solver's start.

This is an input feasibility gate, not a garment simulation or acceptance.
Body/body pairs are excluded because the body is prescribed; cloth/body and
cloth/cloth pairs remain enabled. No intersections are repaired or hidden here.
"""
import argparse
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import sys

import numpy as np
from art_paths import art_path
from audit_cloth_continuous import collision_mesh, controls


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def triangles(polygons):
    return np.asarray([(face[0], face[i], face[i+1])
                       for face in polygons for i in range(1, len(face)-1)], dtype=np.int64)


def write_obj(path, points, faces):
    with path.open('w', encoding='utf-8', newline='\n') as output:
        for p in points:
            output.write('v %.17g %.17g %.17g\n' % tuple(p))
        for f in faces:
            output.write('f %d %d %d\n' % tuple(f+1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--ipctk-path', required=True, type=Path)
    parser.add_argument('--minimum-offset', type=float, default=.0005)
    args = parser.parse_args()
    if not math.isfinite(args.minimum_offset) or args.minimum_offset <= 0:
        parser.error('--minimum-offset must be finite and positive')
    sys.path.insert(0, str(args.ipctk_path.resolve()))
    import ipctk as ipc
    if importlib.metadata.version('ipctk') != '1.6.0':
        raise ValueError('Expected pinned ipctk 1.6.0')
    control_results = controls(ipc)
    body_path = art_path('characters/base/female_base_v2/female_display_topology.json')
    folder = art_path('characters/equipment/surface_bound/dress_ruffle_layers/item_01')
    binding_path = folder / 'binding.json'
    binding = json.loads(binding_path.read_text(encoding='utf-8'))
    source_path = art_path(binding['source_relative']) / 'clothing_data.json'
    if binding['body_sha256'] != sha(body_path) or binding['source_sha256'] != sha(source_path):
        raise ValueError('Binding source hash mismatch')
    body = json.loads(body_path.read_text(encoding='utf-8'))
    source = json.loads(source_path.read_text(encoding='utf-8'))
    cloth_points = np.asarray(source['vertices'], dtype=float)
    body_points = np.asarray(body['points'], dtype=float)
    cloth_faces = triangles([f['vertices'] for f in source['faces']])
    body_faces = triangles(body['base_faces'])
    # Match the existing candidate's exclusion of zero-area body collider faces.
    t = body_points[body_faces]
    valid = np.sum(np.cross(t[:, 1]-t[:, 0], t[:, 2]-t[:, 0])**2, axis=1) > 1e-16
    excluded_body_faces = np.flatnonzero(~valid).tolist()
    body_faces = body_faces[valid]
    weights_path = folder / 'cloth_rest.bin'
    weights = np.fromfile(weights_path, dtype='<f4').reshape(-1, 4)[:, 3]
    if len(weights) != len(cloth_points) or not np.isfinite(weights).all():
        raise ValueError('Invalid source follow weights')
    vertices = np.concatenate([cloth_points, body_points])
    if not np.isfinite(vertices).all():
        raise ValueError('Nonfinite source geometry')
    faces = np.concatenate([cloth_faces, body_faces + len(cloth_points)])
    mesh = collision_mesh(ipc, vertices, faces)
    if any(mesh.to_full_vertex_id(i) != i for i in range(mesh.num_vertices)):
        raise ValueError('Collision mesh reordered vertices; obstacle filter needs remapping')
    mesh.can_collide = ipc.make_static_obstacle_filter(len(cloth_points))
    combined_intersections = bool(ipc.has_intersections(mesh, vertices))
    cloth_mesh = collision_mesh(ipc, cloth_points, cloth_faces)
    cloth_intersections = bool(ipc.has_intersections(cloth_mesh, cloth_points))
    collisions = ipc.NormalCollisions()
    collisions.build(mesh, vertices, max(.003, args.minimum_offset * 2))
    # ipctk 1.6.0 returns squared distance despite the method's short name.
    # Verified separately with two parallel triangles 0.002 m apart -> 4e-6.
    distance_squared = float(collisions.compute_minimum_distance(mesh, vertices))
    minimum_gap = math.sqrt(distance_squared) if math.isfinite(distance_squared) else None
    nearest = None
    for kind in ['vv', 'ev', 'ee', 'fv']:
        for stencil in getattr(collisions, kind + '_collisions'):
            d2 = float(stencil.compute_distance(vertices, mesh.edges, mesh.faces))
            if nearest is None or d2 < nearest['distance_squared']:
                ids = [int(i) for i in stencil.vertex_ids(mesh.edges, mesh.faces) if i >= 0]
                nearest = dict(kind=kind, distance_squared=d2,
                               vertices=[dict(mesh='cloth' if i < len(cloth_points) else 'body',
                                              index=i if i < len(cloth_points) else i-len(cloth_points))
                                         for i in ids])
    args.output.mkdir(parents=True, exist_ok=True)
    write_obj(args.output / 'cloth_rest.obj', cloth_points, cloth_faces)
    write_obj(args.output / 'body_rest.obj', body_points, body_faces)
    np.save(args.output / 'source_follow_weights.npy', weights)
    cloth_weights = 1.0 - weights
    report = dict(scope='rest input feasibility only; no simulation', garment_id='dress_ruffle_layers/item_01',
                  controls=control_results, vertices=dict(cloth=len(cloth_points), body=len(body_points)),
                  triangles=dict(cloth=len(cloth_faces), body=len(body_faces)),
                  excluded_degenerate_body_face_indices=excluded_body_faces,
                  cloth_self_intersections=cloth_intersections,
                  cloth_or_body_intersections=combined_intersections,
                  minimum_gap_m=minimum_gap, required_offset_m=args.minimum_offset,
                  nearest_feature=nearest,
                  collision_filter='exclude prescribed body/body only',
                  source_follow_weights=dict(min=float(weights.min()), max=float(weights.max())),
                  candidate_weight_classification=dict(
                      formula='cloth_weight = 1 - source_follow_weight; original candidate thresholds',
                      hard_anchors=int(np.sum(cloth_weights < .01)),
                      blend=int(np.sum((cloth_weights >= .01) & (cloth_weights <= .99))),
                      free=int(np.sum(cloth_weights > .99))),
                  source_sha256={str(p): sha(p) for p in [body_path, source_path, binding_path, weights_path]},
                  accepted=not (cloth_intersections or combined_intersections)
                           and (minimum_gap is None or minimum_gap > args.minimum_offset))
    (args.output / 'input_manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)
    return 0 if report['accepted'] else 2


if __name__ == '__main__':
    sys.exit(main())
