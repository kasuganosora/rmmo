"""Export independent v11 parts, inspect actual meshes, render changed landmarks."""
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

BASE=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild'
OUT=BASE/'whitebox_v12';ASSETS=BASE/'landmarks_v2';ASSETS.mkdir(exist_ok=True)


def fingerprint():
    result={}
    for o in bpy.data.objects:
        if o.type!='MESH' or o.get('semantic_group','').startswith(('70_','90_')):continue
        if o.get('semantic_group')=='44_Hanging_Landmark':
            node=o;new_skeleton=False
            while node:
                new_skeleton=new_skeleton or node.get('asset_id')=='guild_hanging_skeleton'
                node=node.parent
            old_skeleton=o.name.startswith(('Skeleton ','Curved rib envelope','Skull ','Open jaw '))
            if new_skeleton or old_skeleton:continue
        h=hashlib.sha256()
        for v in o.data.vertices:h.update((','.join('%.5f'%x for x in (o.matrix_world@v.co))).encode())
        # Blender sphere face iteration can change while positions/winding don't.
        faces=[]
        for p in o.data.polygons:
            face=list(p.vertices);start=face.index(min(face))
            faces.append(tuple(face[start:]+face[:start]))
        for face in sorted(faces):h.update(str(face).encode())
        result[o.name]=h.hexdigest()
    return result


bpy.ops.wm.open_mainfile(filepath=str(BASE/'whitebox_v10/axel_guild_whitebox.blend'))
old=fingerprint()
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_whitebox.blend'))
scene=bpy.context.scene
for c in bpy.data.collections:c.hide_viewport=False;c.hide_render=False
bpy.context.view_layer.update()
new=fingerprint();changes=[n for n in set(old)|set(new) if old.get(n)!=new.get(n)]
report={'unchanged_existing_geometry':not changes,'unexpected_changed_meshes':changes,'checks':{},'assets':[]}
checks=report['checks']
roots=[o for o in bpy.data.objects if str(o.get('asset_id','')).startswith(('guild_alarm_','guild_hanging_skeleton'))]
checks['independent_roots']=len(roots)==12
checks['old_envelopes_removed']=not any('envelope' in o.name.lower() and o.get('semantic_group')=='44_Hanging_Landmark' for o in bpy.data.objects)
checks['no_image_textures']=not any(n.type=='TEX_IMAGE' for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes)
horn=next(o for o in bpy.data.objects if o.get('open_bore',False))
mouth=Vector(horn['mouth_center']);axis=Vector(horn['mouth_axis'])
hit=horn.ray_cast(mouth+axis*.03,-axis,distance=.50)
checks['horn_mouth_no_solid_cap']=not hit[0]
# Inner wall should exist on each side a little upstream from the lip.
checks['horn_inner_wall_exists']=horn.ray_cast(mouth-axis*.18,Vector((0,1,0)),distance=1.0)[0]
skeleton=next(o for o in roots if o.get('asset_id')=='guild_hanging_skeleton')
bone=[o for o in skeleton.children_recursive if o.type=='MESH' and o.data.materials and o.data.materials[0].name=='WB pale stone clay']
verts=[o.matrix_world@v.co for o in bone for v in o.data.vertices]
low=min(v.z for v in verts);roof_clear=min(8.2+(7-abs(v.y-7))*5.8/7-v.z for v in verts)
checks['bones_above_upper_camera_zone']=low>8.3
checks['bones_clear_roof']=roof_clear>.15
checks['bones_inside_truss_bay']=min(v.x for v in verts)>13.2 and max(v.x for v in verts)<18.8
report['bone_bottom_z_m']=low;report['minimum_analytic_roof_gap_m']=roof_clear
deps=bpy.context.evaluated_depsgraph_get()
obstacles=[o for o in bpy.data.objects if o.type=='MESH' and o.get('semantic_group') in ['50_Roof','51_Trusses','33_Ceilings_L1']]
def tree(o):
    ev=o.evaluated_get(deps);me=ev.to_mesh()
    result=BVHTree.FromPolygons([o.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons])
    ev.to_mesh_clear();return result
obstacle_trees=[(o.name,tree(o)) for o in obstacles]
intersections=[]
for o in bone:
    t=tree(o)
    for name,other in obstacle_trees:
        if t.overlap(other):intersections.append([o.name,name])
checks['bones_no_roof_truss_ceiling_intersection']=not intersections
report['bone_structure_intersections']=intersections
exported=set()
for root in roots:
    asset=root['asset_id']
    if asset in exported:continue
    exported.add(asset)
    objects=[root]+list(root.children_recursive)
    oldparent=root.parent;loc=root.location.copy();rot=root.rotation_euler.copy()
    pivot=Vector((4.2,0,2.75)) if asset=='guild_alarm_horn' else Vector((0,0,4.62)) if asset=='guild_alarm_conical_roof' else Vector((0,0,0))
    direct=list(root.children)
    root.parent=None;root.location=(0,0,0);root.rotation_euler=(0,0,0)
    for o in direct:o.location-=pivot
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(asset+'.glb')),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
    asset_scene=bpy.data.scenes.new(asset)
    for o in objects:asset_scene.collection.objects.link(o)
    bpy.data.libraries.write(str(ASSETS/(asset+'.blend')),{asset_scene},fake_user=True,compress=True)
    bpy.data.scenes.remove(asset_scene)
    triangles=0
    for o in objects:
        if o.type=='MESH':o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
    report['assets'].append({'id':asset,'triangles':triangles,'origin_offset_in_assembly':list(pivot),'sha256':hashlib.sha256((ASSETS/(asset+'.glb')).read_bytes()).hexdigest()})
    for o in direct:o.location+=pivot
    root.parent=oldparent;root.location=loc;root.rotation_euler=rot
report['glb_sha256']=hashlib.sha256((OUT/'axel_guild_whitebox.glb').read_bytes()).hexdigest()
report['passed']=all(checks.values()) and not changes
(OUT/'landmark_geometry_review.json').write_text(json.dumps(report,indent=2),encoding='utf8')
(ASSETS/'manifest.json').write_text(json.dumps({'stage':'neutral whitebox','assets':report['assets'],'published':False,'sources':['U04','U18','U23'],'horn_instances':8,'counts_authored':True,'design_completion_authorized':True},indent=2),encoding='utf8')
print('LANDMARK_REVIEW',json.dumps(report),flush=True)
if not report['passed']:raise RuntimeError('Landmark review failed; see JSON')
if '--no-render' in sys.argv:sys.exit(0)
cam=scene.camera
scene.render.resolution_x=1500;scene.render.resolution_y=1100
scene.cycles.samples=24
def shot(name,eye,target,scale,groups,isolated=None):
    if '--parts-only' in sys.argv and name not in ['20_alarm_crown','21_horn_detail','22_skeleton_detail']:return
    if '--detail-only' in sys.argv and name not in ['22_skeleton_detail','23_hall_landmarks']:return
    if '--hall-only' in sys.argv and name!='23_hall_landmarks':return
    for col in bpy.data.collections:col.hide_render=col.name not in groups+['90_Studio']
    for o in bpy.data.objects:
        if o.type=='MESH':o.hide_render=o.get('semantic_group','') not in groups+['90_Studio']
        if o.type=='LIGHT' and o.data.type=='AREA':o.hide_render=o.location.y>0 and name!='23_hall_landmarks'
    if isolated:
        keep=set([isolated]+list(isolated.children_recursive))
        for o in bpy.data.objects:
            if o.get('semantic_group')==isolated.get('semantic_group'):o.hide_render=o not in keep
    cam.location=eye;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO' if scale else 'PERSP';cam.data.ortho_scale=scale or 45;cam.data.lens=14 if name=='23_hall_landmarks' else 23
    scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
    for o in bpy.data.objects:
        if o.get('semantic_group')=='70_Alarm_Tower_Context':o.hide_render=False
shot('20_alarm_crown',(36,23,25),(23,42,27.7),17,['70_Alarm_Tower_Context'])
shot('21_horn_detail',(34,40.8,21.5),(28.0,42,25.9),4.2,['70_Alarm_Tower_Context'],next(o for o in roots if o.name=='guild_alarm_horn'))
shot('22_skeleton_detail',(23,-3,12),(16,7,10.2),8.5,['44_Hanging_Landmark'],skeleton)
groups=[c.name for c in bpy.data.collections if not c.name.startswith(('70_','71_','80_','60_'))]
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA':o.hide_render=False
shot('23_hall_landmarks',(8.3,5.0,5.6),(16,7.2,6.7),0,groups)
shot('24_site_landmarks',(68,-53,61),(18,21,12),72,[c.name for c in bpy.data.collections if not c.name.startswith(('80_',))])
print('LANDMARK_PREVIEWS_DONE',flush=True)
