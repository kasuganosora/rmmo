import bpy,json,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
base=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v3')
report={}
for asset in ['pottery','scroll','potion','ore']:
    bpy.ops.wm.open_mainfile(filepath=str(base/asset/'runtime_baked.blend'))
    trim=bpy.data.objects['CanopyTrim'];cloth=bpy.data.objects['CanopyCloth']
    verts=[cloth.matrix_world@v.co for v in cloth.data.vertices];faces=[tuple(f.vertices) for f in cloth.data.polygons]
    tree=BVHTree.FromPolygons(verts,faces)
    parents=list(range(len(trim.data.vertices)))
    def root(i):
        while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
        return i
    for edge in trim.data.edges:
        a,b=[root(i) for i in edge.vertices];parents[b]=a
    groups={}
    for i in range(len(parents)):groups.setdefault(root(i),[]).append(i)
    rows=[]
    for indices in groups.values():
        pts=[trim.matrix_world@trim.data.vertices[i].co for i in indices];ar=np.asarray([p[:] for p in pts]);span=np.ptp(ar,axis=0);mean=ar.mean(axis=0)
        axis=1 if span[0]>span[1] else 0;normal=Vector((0,0,0));normal[axis]=1 if mean[axis]>0 else -1
        ids=set(indices);polys=[f for f in trim.data.polygons if f.vertices[0] in ids]
        samples=pts+[trim.matrix_world@f.center for f in polys]
        distances=[]
        for p in samples:
            pos,_,_,_=tree.ray_cast(p+normal*.05,-normal,.1)
            if pos is not None:distances.append((p-pos).dot(normal))
        rows.append({'axis':axis,'side':normal[axis],'min_gap':min(distances) if distances else None,'max_gap':max(distances) if distances else None,'below_0':sum(d<0 for d in distances),'below_1mm':sum(d<.001 for d in distances),'samples':len(distances),'inward_normal_faces':sum(f.normal.dot(normal)<0 for f in polys),'faces':len(polys)})
    runtime=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.name in ['CanopyTrim','CanopyCloth','Structure','GoodsOpaque','PaperSheet'] or o.get('rmmo_export_group','').startswith(('Glass','Liquid','Crystal')))]
    allpts=np.asarray([(o.matrix_world@v.co)[:] for o in runtime for v in o.data.vertices])
    report[asset]={'components':rows,'bounds_min':allpts.min(axis=0).tolist(),'bounds_max':allpts.max(axis=0).tolist()}
Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/trim_runtime_probe.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:{'bounds_min':v['bounds_min'],'bounds_max':v['bounds_max'],'components':len(v['components']),'min_gap':min(r['min_gap'] for r in v['components'] if r['min_gap'] is not None),'below_zero':sum(r['below_0'] for r in v['components']),'inward_faces':sum(r['inward_normal_faces'] for r in v['components']),'faces':sum(r['faces'] for r in v['components'])} for k,v in report.items()},indent=2),flush=True)
