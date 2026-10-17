"""Preserve the editable deformation master; bind a render master to final GLB."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector

root=Path('D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017/v2')
p=root/'s10_mature_redfruit_courtyard.glb'
ap=p.with_name(p.stem+'_authoring.json');a=json.loads(ap.read_text(encoding='utf-8'))
assert hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256']
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(p))
cloud=[];stem=[]
for o in bpy.data.objects:
    if o.type!='MESH':continue
    points=[o.matrix_world@v.co for v in o.data.vertices]
    if 'LOD0' in o.name:cloud+=points
    if 'Trunk' in o.name:stem+=[v for v in points if 1.25<=v.z<=1.35]
def box(points):
    lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
    return lo,hi
lo,hi=box(cloud);sl,sh=box(stem)
# Blender Z-up -> GLTF/Godot Y-up; these describe the actual source mesh.
center=[(lo[0]+hi[0])/2,(lo[2]+hi[2])/2,-(lo[1]+hi[1])/2]
a['deformation_master']={'path':a['master'],'sha256':a['master_sha256'],'note':'Preserved original editable build. Final GLB restores the baseline bark baseColorFactor after export.'}
m=p.with_name(p.stem+'_render_master.blend');assert not m.exists()
bpy.ops.wm.save_as_mainfile(filepath=str(m),compress=True)
a.update(master=m.as_posix(),master_sha256=hashlib.sha256(m.read_bytes()).hexdigest())
a['anchors'].update(crown_center=center,stem_at_1_3m=[(sl[0]+sh[0])/2,1.3,-(sl[1]+sh[1])/2])
a['measured_shape']={'crown_width_depth_m':[hi[0]-lo[0],hi[1]-lo[1]],'lowest_canopy_m':lo[2],'stem_width_depth_at_1_3m':[sh[0]-sl[0],sh[1]-sl[1]],'method':'Actual final GLB imported in Blender, world-space canopy LOD0 and trunk vertex band z=1.25..1.35m; not a forestry DBH claim.'}
ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
hp=root/'s10_court_shutter_house_authoring.json';h=json.loads(hp.read_text(encoding='utf-8'))
h['anchors']['independent_existing_lamp_root']=[1.37,2.25,-5.6914444]
h['independent_lamp']={'source':'D:/code/rmmo_runtime/packs/default/assets/5beaac048f0176d57c6ca06e0d136f87c64d0b46ec93c378f2a637aceeafef45.glb','yaw_degrees':180,'placement':'root local offset, not wall anchor; existing source remains separate and unchanged'}
hp.write_text(json.dumps(h,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('S10_MASTER',a['anchors'],a['measured_shape'],flush=True)
