"""Find the first observed self intersection; does not certify unsampled substeps."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from art_paths import art_path
from audit_cloth_self_intersections import intersections


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--first-only', action='store_true')
    parser.add_argument('--stages', help='Inspect solver stages for this frame stem, e.g. stand_032')
    parser.add_argument('--face-pair', nargs=2, type=int, help='Track only these two source face IDs (not a whole-mesh audit)')
    parser.add_argument('--changes-only', action='store_true', help='Print state transitions; retain every inspected state in JSON')
    args = parser.parse_args()
    metadata = json.loads((args.directory / 'topology.json').read_text(encoding='utf-8'))
    source = json.loads(art_path('characters/source_models/garment_validation_set/' + metadata['garment_id'] + '/clothing_data.json').read_text(encoding='utf-8'))
    faces = np.asarray([(f['vertices'][0], f['vertices'][j], f['vertices'][j+1])
                        for f in source['faces'] for j in range(1, len(f['vertices'])-1)])
    mapping = np.asarray(metadata['control_to_particle'], dtype=int)
    face_ids = np.arange(len(faces))
    if args.face_pair:
        if min(args.face_pair) < 0 or max(args.face_pair) >= len(faces) or len(set(args.face_pair)) != 2:
            raise ValueError('Invalid source face pair')
        face_ids = np.asarray(args.face_pair)
        faces = faces[face_ids]
    rows = []
    previous_state = None
    # Stand precedes sit; lexical sorting alone reverses the two actions.
    paths = sorted(args.directory.glob('stand_*.f32')) + sorted(args.directory.glob('sit_*.f32'))
    paths = [p for p in paths if not p.name.endswith('.stages.f32')]
    if args.stages:
        if not args.stages.isascii() or not args.stages.isidentifier():
            raise ValueError('Invalid frame stem')
        labels = json.loads((args.directory / (args.stages + '.stages.json')).read_text(encoding='utf-8'))
        stage_data = (args.directory / (args.stages + '.stages.f32')).read_bytes()
        arrays = np.frombuffer(stage_data, dtype='<f4').reshape(len(labels), -1, 4)
        samples = ((args.stages + '/' + label, array.tobytes()) for label, array in zip(labels, arrays))
    else:
        samples = ((path.stem, path.read_bytes()) for path in paths)
    for name, data in samples:
        values = np.frombuffer(data, dtype='<f4').reshape(-1, 4)
        crossings, coplanar, degenerate = intersections(values[mapping, :3], faces)
        row = dict(frame=name, crossings=len(crossings), coplanar=len(coplanar),
                   degenerate=len(degenerate), sha256=hashlib.sha256(data).hexdigest(),
                   scope='selected_face_pair' if args.face_pair else 'whole_mesh',
                   pairs=[dict(faces=face_ids[list(pair)].tolist(), segment_m=length) for pair, length in crossings.items()])
        rows.append(row)
        state = (len(crossings), len(coplanar), len(degenerate))
        if not args.changes_only or state != previous_state:
            print(json.dumps({k: v for k, v in row.items() if k != 'pairs'}), flush=True)
        previous_state = state
        if args.first_only and (crossings or coplanar or degenerate):
            break
    filename = args.stages + '_stages_audit.json' if args.stages else 'trace_audit.json'
    if args.face_pair: filename = 'pair_' + '_'.join(map(str, args.face_pair)) + '_' + filename
    (args.directory / filename).write_text(json.dumps(rows, indent=2), encoding='utf-8')
    return 0 if rows else 2


if __name__ == '__main__':
    raise SystemExit(main())
