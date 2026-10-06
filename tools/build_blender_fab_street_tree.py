"""Offline Fab tree adaptation and identical-light optimization review."""
import bpy, json, math, hashlib
from pathlib import Path
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/bridge_street_kit/fab_tree_review')
SRC=OUT.parent/'sources/trees60'
OUT.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def image_mat(name,filename,leaf=False):
    m=bpy.data.materials.new(name);m.use_nodes=True
    nt=m.node_tree;p=nt.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.8
    t=nt.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(SRC/filename));t.image.pack()
    nt.links.new(t.outputs['Color'],p.inputs['Base Color'])
    if leaf:
        nt.links.new(t.outputs['Alpha'],p.inputs['Alpha']);p.inputs['Subsurface Weight'].default_value=.06
    else:
        n=nt.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(SRC/'T_Trees60_Trunk_normal.png'));n.image.colorspace_settings.name='Non-Color';n.image.pack()
        normal=nt.nodes.new('ShaderNodeNormalMap');nt.links.new(n.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs['Normal'],p.inputs['Normal'])
    return m
bark=image_mat('Fab Trees60 photographed bark','T_Trees60_Trunk.png')
leaves=image_mat('Fab Trees60 photographed foliage','T_Trees60_Leaf.png',True)
bpy.ops.import_scene.fbx(filepath=str(SRC/'SM_Trees60_1.fbx'))
source=next(o for o in bpy.context.selected_objects if o.type=='MESH')
bpy.context.view_layer.objects.active=source;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
for i,m in enumerate(source.data.materials):source.data.materials[i]=leaves if 'Leaf' in m.name else bark
minz=min(v.co.z for v in source.data.vertices)
for v in source.data.vertices:v.co.z-=minz
source.location=(0,0,0);source.name='Fab_original_tree_1'
adapt=source.copy();adapt.data=source.data.copy();bpy.context.collection.objects.link(adapt);adapt.name='Street_broad_crown_master'
# A compact street tree: 8m height, crown width retained, gentle lean.
height=max(v.co.z for v in adapt.data.vertices);scale=8/height
for v in adapt.data.vertices:
    v.co*=scale
    z=v.co.z;f=1+.10*min(1,max(0,(z-2)/3))
    v.co.x=v.co.x*f+.12*(z/8)**2;v.co.y*=f
adapt['design']='8m street broadleaf; photographed source; slight crown spread and lean'
opt=adapt.copy();opt.data=adapt.data.copy();bpy.context.collection.objects.link(opt);opt.name='Street_tree_optimized'
bpy.ops.object.select_all(action='DESELECT');opt.select_set(True);bpy.context.view_layer.objects.active=opt
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='MATERIAL');bpy.ops.object.mode_set(mode='OBJECT')
optimized=list(bpy.context.selected_objects)
for o in optimized:
    o.name='Street_tree_'+('foliage_preserved' if o.data.materials[0]==leaves else 'trunk_optimized')
    if o.data.materials[0]==bark:
        bpy.context.view_layer.objects.active=o
        mod=o.modifiers.new('Conservative trunk-only reduction','DECIMATE');mod.ratio=.8;mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
def tris(objects):
    return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
stats={'original_triangles':tris([source]),'adapted_triangles':tris([adapt]),'optimized_triangles':tris(optimized),'foliage_policy':'All original leaf geometry, UVs and alpha texture preserved','integration':False,'visual_review':'pending'}
for name,objects in [('original',[source]),('adapted',[adapt]),('optimized',optimized)]:
    for o in objects:o['review_version']=name
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes['Background'];bg.inputs[0].default_value=(.65,.75,.9,1);bg.inputs[1].default_value=.35
bpy.ops.mesh.primitive_plane_add(size=200);ground=bpy.context.object;ground.name='REVIEW_GROUND';gm=bpy.data.materials.new('Review neutral ground');gm.diffuse_color=(.24,.26,.22,1);ground.data.materials.append(gm)
bpy.ops.object.light_add(type='SUN',location=(-8,-5,14));sun=bpy.context.object;sun.rotation_euler=(math.radians(25),math.radians(-28),math.radians(-25));sun.data.energy=2.4;sun.data.angle=.08
bpy.ops.object.camera_add(location=(17,-23,14));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=14;scene.camera=cam;scene.view_settings.view_transform='AgX'
alltrees=[source,adapt]+optimized
def show(objects):
    for o in alltrees:o.hide_render=o not in objects;o.hide_set(o not in objects)
for name,objects in [('original',[source]),('adapted',[adapt]),('optimized',optimized)]:
    show(objects);scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
show(optimized)
bpy.ops.object.select_all(action='DESELECT')
for o in optimized:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'street_tree_optimized.glb'),use_selection=True,export_format='GLB')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'street_tree_review.blend'))
stats['source']={'title':'Desktop Trees Pack 60 (PC/Console)','author':'Tree Master','url':'https://www.fab.com/listings/43b47da3-b552-4b6f-9deb-d638c26d3021','license':'CC BY 4.0','license_url':'https://creativecommons.org/licenses/by/4.0/','archive_sha256':hashlib.sha256((SRC/'trees_60_fbx.zip').read_bytes()).hexdigest(),'modifications':'Tree 1 resized to 8m; crown spread/lean adjusted; PBR rebuilt; trunk decimated 20%, leaf mesh preserved.'}
(OUT/'review.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
print('FAB_TREE_REVIEW_COMPLETE',stats)
