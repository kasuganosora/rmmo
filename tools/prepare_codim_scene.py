"""Prepare unchanged world-space rest input and original chair/floor colliders."""
import hashlib
import json
import numpy as np
from art_paths import review_path
from prepare_codim_garment_input import write_obj
from probe_codim_reference import read_points


def faces(path):
    return np.asarray([[int(x)-1 for x in line.split()[1:]] for line in path.read_text().splitlines() if line.startswith('f ')])


def main():
    root = review_path('character_3d')
    motion = root/'codim_hw_motion'
    target = root/'codim_hw_scene'
    target.mkdir(exist_ok=True)
    original = json.loads((root/'candidate_body_release_hw_sit.json').read_text())
    scene_points, scene_faces = [], []
    box_faces = [[0,2,3],[0,3,1],[4,5,7],[4,7,6],[0,1,5],[0,5,4],
                 [2,6,7],[2,7,3],[0,4,6],[0,6,2],[1,3,7],[1,7,5]]
    for box in original['scene_boxes']:
        transform = np.asarray(box['local_from_cloth'])
        basis, origin = transform[:3].T, transform[3]
        corners = np.asarray([[x,y,z] for x in [-.5,.5] for y in [-.5,.5] for z in [-.5,.5]]) * box['size']
        points = (corners-origin) @ np.linalg.inv(basis).T + [0,-original['floor'],0]
        base = len(scene_points)
        scene_points.extend(points.tolist())
        scene_faces.extend([[i+base for i in f] for f in box_faces])
    base = len(scene_points)
    scene_points.extend([[-3,0,-3],[3,0,-3],[3,0,3],[-3,0,3]])
    scene_faces.extend([[base,base+2,base+1],[base,base+3,base+2]])
    scene_points, scene_faces = np.asarray(scene_points), np.asarray(scene_faces)
    body = np.asarray(read_points(motion/'stand_000.obj'))
    cloth = np.loadtxt(motion/'stand_000.follow', skiprows=1)[:,:3]
    rest = root/'codim_hw_input'
    body_rest = np.asarray(read_points(rest/'body_rest.obj'))
    source_cloth = np.asarray(read_points(rest/'cloth_rest.obj'))
    offset = np.median(body-body_rest, axis=0)
    body_error = float(np.linalg.norm(body-body_rest-offset,axis=1).max())
    cloth_error = float(np.linalg.norm(cloth-source_cloth-offset,axis=1).max())
    if max(body_error,cloth_error)>1e-5:
        raise ValueError('Initial shape differs from original rest input')
    write_obj(target/'cloth_initial.obj',cloth,faces(rest/'cloth_rest.obj'))
    write_obj(target/'colliders_initial.obj',np.concatenate([body,scene_points]),
              np.concatenate([faces(rest/'body_rest.obj'),scene_faces+len(body)]))
    write_obj(target/'scene.obj',scene_points,scene_faces)
    report=dict(scope='unchanged initial input and original scene; no solve',body_vertices=len(body),
                cloth_vertices=len(cloth),scene_vertices=len(scene_points),scene_triangles=len(scene_faces),
                initial_offset=offset.tolist(),max_initial_body_error=body_error,max_initial_cloth_error=cloth_error,
                snapshot_sha256=hashlib.sha256((root/'candidate_body_release_hw_sit.json').read_bytes()).hexdigest(),
                scene_source='same six chair boxes and 6x6 floor; no geometry clearance changes')
    (target/'scene_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
