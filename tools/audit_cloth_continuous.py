"""Independent IPC check of a linear segment between two recorded cloth states.

This is an offline diagnostic, not a cloth solver or a certificate for an entire
nonlinear animation. IPC requires an intersection-free start. Install the pinned
ipctk 1.6.0 wheel outside the project and pass its directory explicitly.
"""
import argparse
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path

import numpy as np

from art_paths import art_path


def collision_mesh(ipc, vertices, faces):
    edges = np.unique(np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]],
                                             faces[:, [2, 0]]]), axis=1), axis=0)
    return ipc.CollisionMesh(vertices, edges, faces)


def controls(ipc):
    """Confirm API meaning using crossing/non-crossing and a rotated control."""
    start = np.array([[-1, -1, 0], [1, -1, 0], [0, 1, 0],
                      [-1, -1, 1], [1, -1, 1], [0, 1, 1]], dtype=float)
    faces = np.array([[0, 1, 2], [3, 4, 5]])
    rows = []
    for rotated in [False, True]:
        basis = np.eye(3) if not rotated else np.linalg.qr(np.array([[1., 2, 3], [4, 3, 1], [2, -1, 4]]))[0]
        for crossing in [False, True]:
            end = start.copy()
            end[3:, 2] -= 2 if crossing else .25
            a, b = start @ basis, end @ basis
            mesh = collision_mesh(ipc, a, faces)
            free = bool(ipc.is_step_collision_free(mesh, a, b))
            step = float(ipc.compute_collision_free_stepsize(mesh, a, b))
            assert not ipc.has_intersections(mesh, a)
            assert free == (not crossing), (rotated, crossing, free)
            assert (0 < step < .5) if crossing else step == 1, step
            rows.append(dict(rotated=rotated, crossing=crossing, collision_free=free, safe_step=step))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--ipctk-path', required=True, type=Path)
    parser.add_argument('--start', required=True, help='Frame stem, or exact stage label with --stages')
    parser.add_argument('--end', required=True)
    parser.add_argument('--stages', help='Recorded stage frame stem, e.g. stand_043')
    parser.add_argument('--face-pair', nargs=2, type=int)
    args = parser.parse_args()
    if not args.ipctk_path.is_dir():
        parser.error('Missing external ipctk directory')
    sys.path.insert(0, str(args.ipctk_path.resolve()))
    import ipctk
    version = importlib.metadata.version('ipctk')
    if version != '1.6.0':
        raise ValueError('Expected pinned ipctk 1.6.0, found ' + version)
    control_results = controls(ipctk)
    meta = json.loads((args.directory / 'topology.json').read_text(encoding='utf-8'))
    source = json.loads(art_path('characters/source_models/garment_validation_set/' + meta['garment_id'] + '/clothing_data.json').read_text(encoding='utf-8'))
    faces = np.asarray([(f['vertices'][0], f['vertices'][i], f['vertices'][i + 1])
                        for f in source['faces'] for i in range(1, len(f['vertices']) - 1)])
    if args.face_pair:
        if min(args.face_pair) < 0 or max(args.face_pair) >= len(faces) or len(set(args.face_pair)) != 2:
            parser.error('Invalid source face pair')
        faces = faces[args.face_pair]
    # Welded solver topology, not duplicated display/UV seam vertices.
    faces = np.asarray(meta['control_to_particle'])[faces]
    used, compact = np.unique(faces, return_inverse=True)
    faces = compact.reshape(-1, 3)
    if args.stages:
        if not args.stages.isascii() or not args.stages.isidentifier():
            parser.error('Invalid stage frame stem')
        labels = json.loads((args.directory / (args.stages + '.stages.json')).read_text(encoding='utf-8'))
        data = np.fromfile(args.directory / (args.stages + '.stages.f32'), dtype='<f4').reshape(len(labels), -1, 4)
        samples = [data[labels.index(label)] for label in [args.start, args.end]]
    else:
        if any(not name.isascii() or not name.isidentifier() for name in [args.start, args.end]):
            parser.error('Invalid frame stem')
        samples = [np.fromfile(args.directory / (name + '.f32'), dtype='<f4').reshape(-1, 4) for name in [args.start, args.end]]
    a, b = [np.ascontiguousarray(sample[used, :3], dtype=np.float64) for sample in samples]
    if not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('Non-finite trace geometry')
    mesh = collision_mesh(ipctk, a, faces)
    initial_intersections = bool(ipctk.has_intersections(mesh, a))
    final_intersections = bool(ipctk.has_intersections(mesh, b))
    free = None if initial_intersections else bool(ipctk.is_step_collision_free(mesh, a, b))
    step = None if initial_intersections else float(ipctk.compute_collision_free_stepsize(mesh, a, b))
    report = dict(ipctk=version, controls=control_results, scope='selected_face_pair' if args.face_pair else 'whole_mesh',
                  face_pair=args.face_pair, start=args.start, end=args.end, stages=args.stages,
                  trajectory='linear interpolation of recorded states only',
                  start_sha256=hashlib.sha256(a.tobytes()).hexdigest(), end_sha256=hashlib.sha256(b.tobytes()).hexdigest(),
                  initial_intersections=initial_intersections, final_intersections=final_intersections,
                  collision_free=free, collision_free_stepsize=step)
    tag = hashlib.sha256(json.dumps([args.start, args.end, args.stages, args.face_pair]).encode()).hexdigest()[:12]
    target = args.directory / ('ipc_segment_' + tag + '.json')
    target.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)
    print('Report:', target)
    return 3 if initial_intersections else 0 if free and not final_intersections else 2


if __name__ == '__main__':
    sys.exit(main())
