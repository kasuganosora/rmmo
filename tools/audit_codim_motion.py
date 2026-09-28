"""Verify exported reference motion against the existing candidate snapshots."""
import hashlib
import json
import numpy as np
from art_paths import art_path, review_path
from probe_codim_reference import read_points


def main():
    directory = review_path('character_3d/codim_hw_motion')
    manifest = json.loads((directory/'motion.json').read_text(encoding='utf-8'))
    weights = np.fromfile(art_path('characters/equipment/surface_bound/dress_ruffle_layers/item_01/cloth_rest.bin'), dtype='<f4').reshape(-1, 4)[:, 3]
    expected = 1-weights.astype(float)
    if len(manifest['frames']) != 130:
        raise ValueError('Incomplete stand/sit trajectory')
    max_weight_error = 0.
    for frame in manifest['frames']:
        for extension, key in [('.obj', 'body_sha256'), ('.follow', 'follow_sha256')]:
            path = directory/(frame['stem']+extension)
            if hashlib.sha256(path.read_bytes()).hexdigest() != frame[key]:
                raise ValueError('Changed export: '+str(path))
        points = np.asarray(read_points(directory/(frame['stem']+'.obj')))
        targets = np.loadtxt(directory/(frame['stem']+'.follow'), skiprows=1)
        if points.shape != (21556, 3) or targets.shape != (4920, 4) or not np.isfinite(points).all() or not np.isfinite(targets).all():
            raise ValueError('Invalid frame: '+frame['stem'])
        max_weight_error = max(max_weight_error, float(np.abs(targets[:, 3]-expected).max()))
    comparisons = []
    for label, stem, z in [('stand', 'stand_064', .45), ('sit_15', 'sit_015', .3),
                           ('sit_30', 'sit_030', .15), ('sit_45', 'sit_045', 0), ('sit', 'sit_064', 0)]:
        path = review_path('character_3d/candidate_body_release_hw_'+label+'.json')
        original = json.loads(path.read_text(encoding='utf-8'))
        body = np.asarray(original['body'])+np.array([0, -original['floor'], z])
        exported = np.asarray(read_points(directory/(stem+'.obj')))
        error = float(np.linalg.norm(body-exported, axis=1).max())
        comparisons.append(dict(pose=label, maximum_body_error_m=error,
                                reference_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    report = dict(scope='motion input preservation; no cloth solve', frames=130,
                  maximum_weight_error=max_weight_error, comparisons=comparisons,
                  accepted=max_weight_error < 1e-8 and all(r['maximum_body_error_m'] < 1e-5 for r in comparisons))
    (directory/'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['accepted'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
