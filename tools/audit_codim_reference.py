"""Independent IPC audit of every serialized triangle-control solver step.

This audits the saved piecewise-linear trajectory, not hidden Newton iterates
or a real outfit. Keep the failed no-contact run as a negative control.
"""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

import numpy as np
from audit_cloth_continuous import collision_mesh, controls
from probe_codim_reference import read_points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--ipctk-path', required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.ipctk_path.resolve()))
    import ipctk as ipc
    if importlib.metadata.version('ipctk') != '1.6.0':
        raise ValueError('Expected ipctk 1.6.0')
    report_path = args.directory / 'result.json'
    result = json.loads(report_path.read_text(encoding='utf-8'))
    if result['case'] != 'body_layers':
        raise ValueError('This audit expects the three-triangle body/layers control')
    directory = args.directory / 'output' / 'rmmo_codim_body_layers'
    paths = [directory / ('shell%d.obj' % i) for i in range(len(result['frames']) + 1)]
    start = np.asarray(read_points(paths[0]), dtype=np.float64)
    faces = np.asarray([[0, 2, 1], [3, 5, 4], [6, 8, 7]])
    if start.shape != (9, 3):
        raise ValueError('Unexpected initial topology')
    mesh = collision_mesh(ipc, start, faces)
    previous = start
    initial_intersection = bool(ipc.has_intersections(mesh, start))
    failures = []
    digest = hashlib.sha256()
    digest.update(paths[0].read_bytes())
    max_body_error = 0.0
    for frame, path in enumerate(paths[1:], 1):
        current = np.asarray(read_points(path), dtype=np.float64)
        output_faces = np.asarray([[int(v.split('/')[0])-1 for v in line.split()[1:]]
                                   for line in path.read_text().splitlines() if line.startswith('f ')])
        if not np.array_equal(output_faces, faces):
            raise ValueError('Changed output topology at frame %d' % frame)
        if current.shape != start.shape or not np.isfinite(current).all():
            raise ValueError('Invalid output at frame %d' % frame)
        digest.update(path.read_bytes())
        end_intersection = bool(ipc.has_intersections(mesh, current))
        free = None if initial_intersection else bool(ipc.is_step_collision_free(mesh, previous, current))
        expected = start[6:].copy()
        expected[:, 1] += frame * result['dt']
        error = float(np.linalg.norm(current[6:] - expected, axis=1).max())
        max_body_error = max(max_body_error, error)
        if initial_intersection or end_intersection or not free or error > 1e-6:
            failures.append(dict(frame=frame, start_intersection=initial_intersection,
                                 end_intersection=end_intersection, collision_free=free,
                                 body_target_error=error))
        previous, initial_intersection = current, end_intersection
    report = dict(scope='all serialized linear control segments, not Newton iterates or garments',
                  controls=controls(ipc), frames=len(paths)-1, max_body_error=max_body_error,
                  output_precision='upstream OBJ %le: 7 significant decimal digits',
                  body_error_threshold_m=1e-6, failed_frames=failures,
                  source_result_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest(),
                  trajectory_sha256=digest.hexdigest(), accepted=not failures)
    (args.directory / 'independent_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'failed_frames'}))
    print('Failed frames:', len(failures))
    return 0 if report['accepted'] else 2


if __name__ == '__main__':
    sys.exit(main())
