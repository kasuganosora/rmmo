"""Offline open-surface audit using libigl's triangle intersection predicate.

Reports source and deformed topology separately: source intersections are not
silently waived. Shared-vertex pairs are excluded, so this is a diagnostic, not
a complete self-collision certificate (nor a continuous collision test).
"""
import argparse
import hashlib
import json
from pathlib import Path

import igl
import numpy as np
from scipy.spatial import cKDTree

from art_paths import art_path, review_path


def intersections(vertices, faces):
    vertices = np.asarray(vertices, dtype=np.float64)
    faces = np.asarray(faces, dtype=np.int64)
    if not np.isfinite(vertices).all():
        raise ValueError('Non-finite cloth positions')
    triangles = vertices[faces]
    centers = triangles.mean(axis=1)
    radii = np.linalg.norm(triangles-centers[:, None], axis=2).max(axis=1)
    lower, upper = triangles.min(axis=1), triangles.max(axis=1)
    tree = cKDTree(centers)
    maximum_radius = radii.max()
    scale = max(float(np.ptp(vertices, axis=0).max()), 1e-12)
    epsilon = scale*1e-9
    areas = np.linalg.norm(np.cross(triangles[:, 1]-triangles[:, 0],
                                    triangles[:, 2]-triangles[:, 0]), axis=1)
    degenerate = areas <= scale*scale*1e-14
    crossings, coplanar = {}, []
    for i, center in enumerate(centers):
        if degenerate[i]:
            continue
        candidates = np.asarray(tree.query_ball_point(center, radii[i]+maximum_radius+epsilon))
        candidates = candidates[candidates > i]
        if not len(candidates):
            continue
        candidates = candidates[np.all(lower[candidates] <= upper[i]+epsilon, axis=1)
                                & np.all(upper[candidates] >= lower[i]-epsilon, axis=1)]
        for j in candidates:
            if degenerate[j] or np.isin(faces[i], faces[j]).any():
                continue
            hit, planar, start, end = igl.tri_tri_intersection_test_3d(
                *[p.reshape(1, 3) for p in triangles[i]],
                *[p.reshape(1, 3) for p in triangles[j]])
            if not hit:
                continue
            if planar:
                coplanar.append((int(i), int(j)))
            else:
                length = float(np.linalg.norm(end-start))
                if length > epsilon:
                    crossings[(int(i), int(j))] = length
    return crossings, coplanar, np.flatnonzero(degenerate).tolist()


def compare(vertices, faces, source):
    crossing, planar, degenerate = intersections(vertices, faces)
    old, _, _ = source
    return {
        'crossing_pairs': len(crossing),
        'new_crossing_pairs': len(crossing.keys()-old.keys()),
        'source_pair_still_crossing': len(crossing.keys() & old.keys()),
        'source_pair_resolved': len(old.keys()-crossing.keys()),
        'coplanar_pairs': len(planar),
        'degenerate_faces': degenerate,
        'maximum_crossing_segment_m': max(crossing.values(), default=0),
        'pairs': [{'faces': list(pair), 'segment_m': length, 'present_in_source': pair in old}
                  for pair, length in sorted(crossing.items())],
        'coplanar_face_pairs': planar,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=review_path('character_3d'))
    args = parser.parse_args()
    reports = {}
    source_cache = {}
    for pose in ['stand', 'sit_15', 'sit_30', 'sit_45', 'sit']:
        path = args.directory / ('candidate_hw_'+pose+'.json')
        capture = json.loads(path.read_text(encoding='utf-8'))
        garment_id = capture['garment_id']
        if garment_id not in source_cache:
            garment = json.loads(art_path('characters/source_models/garment_validation_set/'
                                         +garment_id+'/clothing_data.json').read_text(encoding='utf-8'))
            faces = np.asarray([(f['vertices'][0], f['vertices'][j], f['vertices'][j+1])
                                for f in garment['faces'] for j in range(1, len(f['vertices'])-1)])
            source = intersections(garment['vertices'], faces)
            source_cache[garment_id] = faces, source
            reports['source'] = compare(garment['vertices'], faces, source)
        faces, source = source_cache[garment_id]
        reports[pose] = compare(capture['garment'], faces, source)
        reports[pose]['capture_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        print(pose, {k: v for k, v in reports[pose].items() if k not in ('pairs', 'coplanar_face_pairs')}, flush=True)
    output = args.directory / 'candidate_hw_self_intersections.json'
    output.write_text(json.dumps(reports, indent=2), encoding='utf-8')
    # Existing source crossings also require inspection; don't waive them.
    return int(any(r['crossing_pairs'] or r['coplanar_pairs'] or r['degenerate_faces'] for r in reports.values()))


if __name__ == '__main__':
    raise SystemExit(main())
