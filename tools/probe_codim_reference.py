"""Headless C-IPC reference controls, run with Linux Python and the built JGSL.

This does not switch the Godot backend or certify a real garment. Each case runs
in its own process because the upstream driver owns Kokkos initialization.
"""
import argparse
import json
import math
import os
from pathlib import Path
import sys
import time


def write_triangle(path, size, height):
    points = [(-size, height, -size), (size, height, -size), (0, height, size)]
    path.write_text(''.join('v %.12g %.12g %.12g\n' % p for p in points) + 'f 1 3 2\n', encoding='utf-8')


def read_points(path):
    return [tuple(map(float, line.split()[1:4])) for line in path.read_text().splitlines() if line.startswith('v ')]


def plane_height(triangle, x, z):
    a, b, c = triangle
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    if abs(n[1]) < 1e-12:
        raise ValueError('Probe face became vertical or degenerate')
    return a[1] - (n[0]*(x-a[0]) + n[2]*(z-a[2])) / n[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--module-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=['freefall', 'body_layers', 'follow', 'follow_contact'], required=True)
    parser.add_argument('--without-contact', action='store_true')
    parser.add_argument('--newton-tolerance', type=float, default=1e-3)
    parser.add_argument('--dt', type=float, default=.01)
    parser.add_argument('--follow-weight', type=float, default=.5)
    parser.add_argument('--follow-max-travel', type=float, default=0)
    parser.add_argument('--without-follow', action='store_true')
    args = parser.parse_args()
    checkout, module_dir, output = args.checkout.resolve(), args.module_dir.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sys.path[:0] = [str(module_dir), str(checkout / 'Python')]
    from JGSL import Vector3d, Vector4i, Set_Parameter
    import Drivers
    # The upstream driver derives log directories from argv. Do not let our
    # absolute CLI paths become nested output directory names.
    sys.argv = ['rmmo_codim_' + args.case]
    os.chdir(output)
    Path('output').mkdir(exist_ok=True)
    sim = Drivers.FEMDiscreteShellBase('double', 3)
    if not math.isfinite(args.dt) or not 0 < args.dt <= .01:
        parser.error('--dt must be finite and in (0, .01]')
    steps = round(.2 / args.dt)
    if not math.isclose(steps * args.dt, .2, abs_tol=1e-12):
        parser.error('--dt must divide the 0.2 second trajectory')
    sim.dt = args.dt
    if not math.isfinite(args.newton_tolerance) or args.newton_tolerance <= 0:
        parser.error('--newton-tolerance must be finite and positive')
    sim.PNTol = args.newton_tolerance
    sim.gravity = Vector3d(0, -9.81 if args.case == 'freefall' else 0, 0)
    sim.withCollision = not args.without_contact
    sim.mu = 0
    zero, axis = Vector3d(0, 0, 0), Vector3d(1, 0, 0)
    geometry = [(1., 1.)]
    if args.case == 'body_layers':
        geometry = [(1., 1.), (1., 1.002), (.02, .9)]
    elif args.case == 'follow_contact':
        geometry = [(1., 1.), (2., 1.25)]
    for index, (size, height) in enumerate(geometry):
        path = output / ('input_%d.obj' % index)
        write_triangle(path, size, height)
        sim.add_shell_3D(str(path), zero, zero, axis, 0)
    if args.case == 'body_layers':
        sim.set_DBC_with_range(Vector3d(-1, -1, -1), Vector3d(2, 2, 2),
                               Vector3d(0, 1, 0), zero, axis, 0, Vector4i(6, 0, 9, -1))
    elif args.case == 'follow_contact':
        sim.set_DBC_with_range(Vector3d(-1, -1, -1), Vector3d(2, 2, 2),
                               zero, zero, axis, 0, Vector4i(3, 0, 6, -1))
    sim.initialize(1000, 1e5, .3, .0005, 0)
    sim.initialize_OIPC(.001, .0005)
    sim.write(0)
    initial = read_points(Path(sim.output_folder) / 'shell0.obj')
    if args.case.startswith('follow'):
        steps = 1
        if not args.without_follow:
            packet = output / 'follow.txt'
            packet.write_text('3 .01 %.17g\n' % args.follow_max_travel +
                              ''.join('%.17g 2 %.17g %.17g\n' % (p[0], p[2], args.follow_weight) for p in initial[:3]),
                              encoding='utf-8')
            Set_Parameter('RMMOSurfaceFollowFile', str(packet))
    rows = []
    started = time.monotonic()
    for frame in range(1, steps + 1):
        sim.advance_one_time_step(sim.dt)
        sim.write(frame)
        points = read_points(Path(sim.output_folder) / ('shell%d.obj' % frame))
        if len(points) != len(initial) or not all(math.isfinite(x) for p in points for x in p):
            raise ValueError('Reference output is missing or non-finite')
        row = dict(frame=frame, cloth_min_y=min(p[1] for p in points[:3]))
        if args.case == 'follow_contact':
            row['body_target_error'] = max(math.dist(p, q) for p, q in zip(points[3:], initial[3:]))
            row['body_gap'] = min(plane_height(points[3:], p[0], p[2])-p[1] for p in points[:3])
        if args.case == 'body_layers':
            row['body_target_error'] = max(math.dist(p, (q[0], q[1] + frame * sim.dt, q[2]))
                                           for p, q in zip(points[6:9], initial[6:9]))
            row['body_gap'] = min(plane_height(points[layer*3:layer*3+3], p[0], p[2])-p[1]
                                  for layer in range(2) for p in points[6:9])
            row['layer_gap'] = min(plane_height(points[3:6], p[0], p[2])-plane_height(points[:3], p[0], p[2]) for p in points[6:9])
        rows.append(row)
    if args.case == 'freefall':
        accepted = rows[-1]['cloth_min_y'] < .95
    elif args.case == 'body_layers':
        accepted = all(r['body_target_error'] < 1e-6 and r['body_gap'] >= .00045 and r['layer_gap'] >= .00045 for r in rows)
    elif args.case == 'follow_contact':
        accepted = rows[-1]['body_gap'] >= .00045 and rows[-1]['body_target_error'] < 1e-6 and rows[-1]['cloth_min_y'] > 1.01
    else:
        predicted_y = 1.
        limit = args.follow_weight * args.follow_max_travel
        if not args.without_follow:
            if limit > 1e-7 and args.follow_max_travel > 0 and limit < 1:
                predicted_y = 2-limit
            if args.follow_weight < .999:
                predicted_y = 2+(predicted_y-2)*args.follow_weight**(sim.dt/.01)
        accepted = abs(rows[-1]['cloth_min_y']-predicted_y) < 1e-6
    report = dict(case=args.case, contact=sim.withCollision, scope='small reference control only',
                  minimum_contact_offset=.0005, barrier_activation=.001, dt=sim.dt,
                  newton_tolerance=sim.PNTol,
                  elapsed_seconds=time.monotonic()-started, accepted=accepted, frames=rows)
    if args.case.startswith('follow'):
        report.update(follow_enabled=not args.without_follow, cloth_weight=args.follow_weight,
                      max_travel=args.follow_max_travel)
        if args.case == 'follow':
            report['expected_y'] = predicted_y
    (output / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('RMMO_REFERENCE_RESULT', json.dumps({k:v for k,v in report.items() if k != 'frames'}), flush=True)
    return 0 if accepted else 2


if __name__ == '__main__':
    sys.exit(main())
