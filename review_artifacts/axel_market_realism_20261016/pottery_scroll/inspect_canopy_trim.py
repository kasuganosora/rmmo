import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
base=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v3')
report={}
for asset in ['pottery','scroll','potion','ore']:
    bpy.ops.wm.open_mainfile(filepath=str(base/asset/'authoring.blend'))
    cloth=[o for o in bpy.context.scene.objects if o.get('rmmo_export_group')=='CanopyCloth']
    verts=[];faces=[]
    for obj in cloth:
        off=len(verts);verts.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        faces.extend(tuple(off+i for i in face.vertices) for face in obj.data.polygons)
    tree=BVHTree.FromPolygons(verts,faces)
    rows=[]
    for obj in bpy.context.scene.objects:
        if obj.get('rmmo_export_group')!='CanopyTrim':continue
        pts=[obj.matrix_world@v.co for v in obj.data.vertices]
        distances=[];signed=[]
        for pt in pts:
            pos,normal,idx,d=tree.find_nearest(pt)
            distances.append(d);signed.append((pt-pos).dot(normal))
        rows.append({'name':obj.name,'vertices':len(pts),'faces':len(obj.data.polygons),'modifiers':[{k:getattr(m,k,None) for k in ['name','type','thickness','offset','width']} for m in obj.modifiers],
                     'min':[min(p[i] for p in pts) for i in range(3)],'max':[max(p[i] for p in pts) for i in range(3)],
                     'nearest_distance_min':min(distances),'nearest_distance_max':max(distances),
                     'vertices_below_0_5mm':sum(d<.0005 for d in distances),'signed_min':min(signed),'signed_max':max(signed),
                     'vertices_inside_cloth':sum(d<-.00005 for d in signed)})
    report[asset]=rows
out=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/canopy_trim_diagnosis.json')
out.write_text(json.dumps(report,indent=2))
print(json.dumps({k:{'trim_objects':len(v),'near_vertices':sum(r['vertices_below_0_5mm'] for r in v),'first':v[0]} for k,v in report.items()},indent=2),flush=True)
