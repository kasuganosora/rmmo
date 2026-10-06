"""Offline full-topology HW reference run with original motion/follow inputs.

Outputs are candidates for independent audit, never automatic visual acceptance.
Run with Linux Python and the explicitly built surface-follow reference module.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time
from probe_codim_reference import read_points


def write_vertices(path, points):
    path.write_text(''.join('v %.17g %.17g %.17g\n'%tuple(p) for p in points),encoding='utf-8')


def lerp(a,b,t):
    return [tuple(x+(y-x)*t for x,y in zip(p,q)) for p,q in zip(a,b)]


def read_follow(path):
    lines=path.read_text().splitlines()
    header=list(map(float,lines[0].split()))
    values=[list(map(float,line.split())) for line in lines[1:]]
    if len(values)!=int(header[0]) or any(len(v)!=4 or not all(math.isfinite(x) for x in v) for v in values):
        raise ValueError('Invalid follow packet')
    return header,values


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in ['checkout','module-dir','motion','scene','output']:
        parser.add_argument('--'+flag,required=True,type=Path)
    parser.add_argument('--frames-limit',type=int,default=130)
    parser.add_argument('--substeps',type=int,default=4)
    parser.add_argument('--contact-offset',type=float,default=.00008)
    args=parser.parse_args()
    if not 1<=args.frames_limit<=130 or not 1<=args.substeps<=1000 or not 0<args.contact_offset<.000162:
        parser.error('Invalid frame/substep/offset setting; offset must fit verified source gap')
    for name in ['checkout','module_dir','motion','scene','output']:
        setattr(args,name,getattr(args,name).resolve())
    if args.output.exists():
        raise ValueError('Choose a fresh output directory to preserve runs')
    args.output.mkdir(parents=True)
    manifest=json.loads((args.motion/'motion.json').read_text())
    scene_manifest=json.loads((args.scene/'scene_manifest.json').read_text())
    audit=json.loads((args.motion/'audit.json').read_text())
    if not audit['accepted'] or len(manifest['frames'])!=130:
        raise ValueError('Motion preservation audit has not passed')
    # Validate all packets before starting the native solver.
    for frame in manifest['frames']:
        for ext,key in [('.obj','body_sha256'),('.follow','follow_sha256')]:
            if hashlib.sha256((args.motion/(frame['stem']+ext)).read_bytes()).hexdigest()!=frame[key]:
                raise ValueError('Changed input packet '+frame['stem'])
    sys.path[:0]=[str(args.module_dir),str(args.checkout/'Python')]
    from JGSL import Vector3d,Vector4i,FEM,Set_Parameter
    import Drivers
    sys.argv=['rmmo_codim_garment'];os.chdir(args.output);Path('output').mkdir()
    sim=Drivers.FEMDiscreteShellBase('double',3)
    sim.dt=manifest['dt']/args.substeps;sim.withCollision=True;sim.mu=.2
    sim.MDBC_tmax=-1 # DBC is explicitly loaded below; disable implicit driver translations.
    zero,axis=Vector3d(0,0,0),Vector3d(1,0,0)
    sim.add_shell_3D(str(args.scene/'cloth_initial.obj'),zero,zero,axis,0)
    sim.add_shell_3D(str(args.scene/'colliders_initial.obj'),zero,zero,axis,0)
    cloth_count=scene_manifest['cloth_vertices']
    body_count=scene_manifest['body_vertices']
    total_count=cloth_count+body_count+scene_manifest['scene_vertices']
    sim.set_DBC_with_range(Vector3d(-1,-1,-1),Vector3d(2,2,2),zero,zero,axis,0,
                           Vector4i(cloth_count,0,total_count,-1))
    sim.initialize(1000,1e5,.3,.0005,0)
    sim.initialize_OIPC(.001,args.contact_offset)
    static_points=read_points(args.scene/'scene.obj')
    frames=manifest['frames'][:args.frames_limit]
    previous_body=read_points(args.motion/(frames[0]['stem']+'.obj'))
    header,previous_follow=read_follow(args.motion/(frames[0]['stem']+'.follow'))
    packet=args.output/'current.follow';dbc=args.output/'current_colliders.obj'
    Set_Parameter('RMMOSurfaceFollowFile',str(packet))
    sim.write(0)
    rows=[];start=time.monotonic()
    for index,frame in enumerate(frames):
        body=read_points(args.motion/(frame['stem']+'.obj'))
        next_header,follow=read_follow(args.motion/(frame['stem']+'.follow'))
        if header!=next_header or len(body)!=body_count or any(a[3]!=b[3] for a,b in zip(previous_follow,follow)):
            raise ValueError('Motion changed weights or topology')
        max_error=0.
        for step in range(args.substeps):
            amount=(step+1)/args.substeps
            body_now=lerp(previous_body,body,amount)
            targets=lerp(previous_follow,follow,amount)
            packet.write_text('%d %.17g %.17g\n'%tuple(header)+''.join('%.17g %.17g %.17g %.17g\n'%tuple(p) for p in targets),encoding='utf-8')
            write_vertices(dbc,body_now+static_points)
            FEM.Load_Dirichlet(str(dbc),cloth_count,zero,sim.DBC)
            sim.advance_one_time_step(sim.dt)
            number=index*args.substeps+step+1
            sim.write(number)
            output=read_points(Path(sim.output_folder)/('shell%d.obj'%number))
            if len(output)!=total_count or not all(math.isfinite(x) for p in output for x in p):
                raise ValueError('Invalid native output')
            error=max(math.dist(p,q) for p,q in zip(output[cloth_count:],body_now+static_points))
            max_error=max(max_error,error)
        rows.append(dict(frame=index,stem=frame['stem'],last_output=number,max_collider_error=max_error,
                         elapsed_seconds=time.monotonic()-start))
        (args.output/'progress.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
        print('RMMO_GARMENT_FRAME',json.dumps(rows[-1]),flush=True)
        previous_body,previous_follow=body,follow
    report=dict(scope='offline full topology output; independent geometry/visual audit required',
                complete_trajectory=len(rows)==130,accepted=False,frames=rows,dt=sim.dt,
                substeps=args.substeps,contact_offset=args.contact_offset,barrier_activation=.001,
                material=dict(density=1000,young_modulus=1e5,poisson=.3,thickness=.0005,friction=.2),
                cloth_vertices=cloth_count,body_vertices=body_count,scene_vertices=len(static_points))
    (args.output/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('RMMO_GARMENT_FINISHED',len(rows),'frames; not accepted without audit',flush=True)


if __name__=='__main__':
    main()
