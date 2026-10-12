"""Reopen authored master, check roof coverage, export reusable doorway prop."""
import bpy,bmesh,json,hashlib,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_finish.blend'))
deps=bpy.context.evaluated_depsgraph_get();vs=[];fs=[]
for o in bpy.data.objects:
    if o.type!='MESH' or o.get('semantic_group')!='50_Roof':continue
    e=o.evaluated_get(deps);m=e.to_mesh();offset=len(vs)
    vs.extend(o.matrix_world@v.co for v in m.vertices)
    fs.extend(tuple(offset+i for i in p.vertices) for p in m.polygons);e.to_mesh_clear()
bvh=BVHTree.FromPolygons(vs,fs);holes=[];count=0
for ix in range(127):
    for iy in range(55):
        x=.25+ix*.25;y=.25+iy*.25;count+=1
        if bvh.ray_cast(Vector((x,y,30)),Vector((0,0,-1)),25)[0] is None:holes.append([x,y])
posts=[o for o in bpy.data.objects if o.get('asset_id')=='guild_entrance_crescent_standard' and o.type=='MESH']
cloth=bpy.data.objects.get('Guild finish guild_banner_cloth')
checks={'roof_coverage_no_holes':not holes,'paired_entrance_standards':len(posts)==2,
        'no_scale_figures':not any(o.get('semantic_group','').startswith('60_') for o in bpy.data.objects),
        'cloth_wind_anchor_top':cloth is not None and cloth.get('rmmo_wind',{}).get('anchor')=='top',
        'cloth_nonmetal':cloth is not None and all(next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Metallic'].default_value==0 for m in cloth.data.materials)}
assert all(checks.values()),checks
# Export one origin-at-base standard, keeping its standalone resource independent.
o=posts[0];bpy.ops.object.select_all(action='DESELECT');o.select_set(True);o.parent=None;o.matrix_world=Matrix.Identity(4)
path=OUT/'guild_entrance_crescent_standard.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
o.data.calc_loop_triangles()
report={'checks':checks,'roof_samples':count,'roof_holes':holes,'standalone':str(path),'standalone_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'standalone_triangles':len(o.data.loop_triangles),'standalone_bytes':path.stat().st_size,'master_reopened':True,'master_sha256':hashlib.sha256((OUT/'axel_guild_finish.blend').read_bytes()).hexdigest(),'scope':'Geometry only; native/runtime and visual review recorded separately.'}
(OUT/'structure_review.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('STRUCTURE_REVIEW',json.dumps(report))
