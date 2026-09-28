"""Convert a completed reference substep to the existing geometry/visual audit format.

The body remains the requested motion input, not a solver-displaced substitute.
Partial samples keep their exact motion/frame identity and never become 'stand'.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from art_paths import review_path
from probe_codim_reference import read_points


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('obj',type=Path)
    parser.add_argument('--frame',required=True,type=int,help='Zero-based exported motion frame')
    parser.add_argument('--substep',required=True,type=int,help='One-based substep within the frame')
    parser.add_argument('--substeps',type=int,default=4)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    if not 0<=args.frame<130 or not 1<=args.substep<=args.substeps:
        parser.error('Invalid motion/substep index')
    expected_name='shell%d.obj'%(args.frame*args.substeps+args.substep)
    if args.obj.name != expected_name:
        parser.error('Expected '+expected_name+' for this motion sample; refusing to relabel another output')
    motion=review_path('character_3d/codim_hw_motion')
    frames=json.loads((motion/'motion.json').read_text())['frames']
    current,previous=frames[args.frame],frames[max(0,args.frame-1)]
    body=np.asarray(read_points(motion/(current['stem']+'.obj')))
    before=np.asarray(read_points(motion/(previous['stem']+'.obj')))
    body=before+(body-before)*(args.substep/args.substeps)
    native=np.asarray(read_points(args.obj))
    if native.shape!=(26528,3) or not np.isfinite(native).all():
        raise ValueError('Unexpected complete solver topology')
    original=json.loads(review_path('character_3d/candidate_body_release_hw_sit.json').read_text())
    boxes=[]
    for box in original['scene_boxes']:
        transform=np.asarray(box['local_from_cloth'])
        transform[3]-=np.array([0,-original['floor'],0]) @ transform[:3]
        boxes.append(dict(local_from_cloth=transform.tolist(),size=box['size']))
    capture=dict(garment_id='dress_ruffle_layers/item_01',garment=native[:4920].tolist(),body=body.tolist(),
                 floor=0,scene_boxes=boxes,coordinate_space='world',source_obj=str(args.obj.resolve()),
                 source_obj_sha256=hashlib.sha256(args.obj.read_bytes()).hexdigest(),motion=current,
                 substep=args.substep,substeps=args.substeps,
                 max_solver_body_error_m=float(np.linalg.norm(native[4920:4920+21556]-body,axis=1).max()),
                 scope='one completed substep only; no whole outfit acceptance')
    args.output.write_text(json.dumps(capture),encoding='utf-8')
    print(json.dumps({k:v for k,v in capture.items() if k not in ['garment','body','scene_boxes']}))


if __name__=='__main__':
    main()
