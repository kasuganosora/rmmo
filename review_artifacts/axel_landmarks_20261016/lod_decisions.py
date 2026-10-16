"""AABB screen projection and measured isolated gallery counters; not an FPS/RSS claim."""
import json,math,itertools
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parent
records=[]
for asset,version in [('church','v7'),('guardhouse','v6'),('watermill','v10')]:
    path=ROOT/asset/version/'gpu/report.json';r=json.loads(path.read_text(encoding='utf-8'))
    p=np.array(r['bounds']['position']);sz=np.array(r['bounds']['size'])
    points=np.array([p+sz*np.array(c) for c in itertools.product([0,1],repeat=3)])
    views=[]
    for s in r['screenshots']:
        if s['name'] not in ['near','medium','far']:continue
        eye=np.array(s['eye']);forward=np.array(s['aim'])-eye;forward/=np.linalg.norm(forward)
        right=np.cross(forward,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,forward)
        rel=points-eye;depth=rel@forward;tan=math.tan(math.radians(s['fov']/2))
        x=(rel@right)/depth/tan/(1440/1080);y=(rel@up)/depth/tan
        dims=[round((x.max()-x.min())*720,1),round((y.max()-y.min())*540,1)]
        views.append({'name':s['name'],'eye':s['eye'],'aim':s['aim'],'vertical_fov':s['fov'],'aabb_projection_pixels':dims,'draw_calls_with_ground':s['draw_calls_with_ground'],'triangles_with_ground':s['triangles_with_ground']})
    records.append({'asset':asset,'version':version,'source_sha':r['identity']['sha256'],'report':str(path),'screenshots':views,
                    'decision':'No new destructive decimation or standalone simplification LOD in this delivery. Low-frequency single landmark; preserve real openings, walkable interior/floors, fixtures and stable silhouette. Existing production batching/visibility semantics retained.',
                    'reason':'Measured full-geometry near/mid/far counters and actual image inspection are recorded. Surface/transparent passes and shared PBR memory remain separate costs; triangle reduction alone would not resolve them.',
                    'boundary':'This is not a frame-rate pass. Reassess shell-only far LOD after formal-map profiling identifies geometric bottleneck, or if repeated across many instances. Never merge away floors/roofs/moving doors.',
                    'projection_method':'Conservative projected bounds of eight actual native AABB corners at recorded camera; includes empty corners, not exact silhouette pixel segmentation.'})
out=ROOT/'lod_decisions.json';out.write_text(json.dumps({'assets':records,'scope':'Unbatched isolated candidate galleries, ground and optical extra passes included; no actual process RSS/VRAM or formal-map performance inferred.'},ensure_ascii=False,indent=2),encoding='utf-8')
for r in records:print(r['asset'],[(s['name'],s['aabb_projection_pixels'],s['draw_calls_with_ground'],s['triangles_with_ground']) for s in r['screenshots']])
