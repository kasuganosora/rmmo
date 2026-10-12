"""Build, export and render the independent statue-side panel in Blender 4.5."""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from axel_guild_decorative_panel import build_panel, ASSET_ID, RING_CENTRES, WIDTH, HEIGHT

P = argparse.ArgumentParser()
P.add_argument('--no-render', action='store_true')
ARGS = P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT = HERE.parents[1] / 'rmmo_runtime/art_sources/axel_guild/decorative_panel_v1'
OUT.mkdir(parents=True, exist_ok=True)
(OUT/'textures').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
SC = bpy.context.scene
SC.unit_settings.system = 'METRIC'; SC.unit_settings.scale_length = 1


def texture(name, pixels, srgb):
    h,w,_ = pixels.shape
    image = bpy.data.images.new(name,width=w,height=h,alpha=True)
    image.colorspace_settings.name = 'sRGB' if srgb else 'Non-Color'
    image.pixels.foreach_set(pixels.astype(np.float32).ravel())
    image.filepath_raw = str(OUT/'textures'/(name+'.png'))
    image.file_format = 'PNG'; image.save(); image.pack()
    return image


def material(name, color, roughness, metal=0):
    m = bpy.data.materials.new(name); m.use_nodes=True
    m.diffuse_color = (*color,1)
    nodes = m.node_tree.nodes; links = m.node_tree.links
    bs = next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metal
    bs.inputs['Roughness'].default_value=roughness
    return m


mats = {
    'board': material('Muted olive painted timber',(.47,.48,.29),.72),
    'rose': material('Satin rose copper metal ring',(.64,.37,.39),.27,1.0),
    'trim': material('Pale worn metal edging',(.50,.50,.39),.43,.72),
    'gold': material('Muted brass relief',(.49,.39,.12),.42,.78),
}
# Small, packed, portable PBR maps. No Blender-only procedural nodes in GLB.
rng = np.random.default_rng(7403)
n = 512
yy,xx = np.mgrid[0:n,0:n]
grain = (np.sin(xx*.41 + .5*np.sin(yy*.012)) + .4*np.sin(xx*1.39+yy*.002))*.5
fine = rng.normal(0,1,(n,n))
variation = grain*.019+fine*.003
rgba = np.ones((n,n,4)); rgba[:,:,:3]=np.array([.47,.48,.29])[None,None,:]*(1+variation[:,:,None])
base = texture('panel_coated_wood_basecolor',np.clip(rgba,0,1),True)
rgba[:,:,:3]=np.clip(.72+grain[:,:,None]*.025+fine[:,:,None]*.009,0,1)
rough = texture('panel_coated_wood_roughness',rgba,False)
height = grain*.018+fine*.002
dy,dx = np.gradient(height)
normal = np.stack([-dx,-dy,np.ones_like(dx)],axis=2)
normal /= np.linalg.norm(normal,axis=2,keepdims=True)
rgba[:,:,:3]=normal*.5+.5
normal_image=texture('panel_coated_wood_normal',rgba,False)
nodes=mats['board'].node_tree.nodes; links=mats['board'].node_tree.links
bs=next(node for node in nodes if node.type=='BSDF_PRINCIPLED')
for im,target in [(base,'Base Color'),(rough,'Roughness')]:
    node=nodes.new('ShaderNodeTexImage');node.image=im;links.new(node.outputs['Color'],bs.inputs[target])
node=nodes.new('ShaderNodeTexImage');node.image=normal_image
nm=nodes.new('ShaderNodeNormalMap');links.new(node.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bs.inputs['Normal'])

# User clarified that the rings should read as metal. Keep their rose/copper
# tint, but use a conductor response and faint concentric finishing marks.
# Metal species is an interpretation, not a claim about the animation canon.
nmetal=1024
my,mx=np.mgrid[0:nmetal,0:nmetal]
px=(mx/(nmetal-1)-.5)*WIDTH
pz=my/(nmetal-1)*HEIGHT
cz=np.asarray(RING_CENTRES)[np.argmin(np.abs(pz[:,:,None]-np.asarray(RING_CENTRES)),axis=2)]
radius=np.hypot(px,pz-cz)
angle=np.arctan2(pz-cz,px)
finishing=np.sin(radius*950+.15*np.sin(angle*7))*.65+np.sin(radius*1670)*.35
metal_rng=np.random.default_rng(7703)
micro=metal_rng.normal(0,1,(nmetal,nmetal))
rgba=np.ones((nmetal,nmetal,4))
rough_values=np.clip(.27+finishing*.017+micro*.007,.22,.32)
rgba[:,:,:3]=rough_values[:,:,None]
ring_rough=texture('rose_metal_roughness',rgba,False)
gy,gx=np.gradient(finishing*.004+micro*.0002)
normals=np.stack([-gx,-gy,np.ones_like(gx)],axis=2)
normals/=np.linalg.norm(normals,axis=2,keepdims=True)
rgba[:,:,:3]=normals*.5+.5
ring_normal=texture('rose_metal_normal',rgba,False)
nodes=mats['rose'].node_tree.nodes;links=mats['rose'].node_tree.links
bs=next(node for node in nodes if node.type=='BSDF_PRINCIPLED')
node=nodes.new('ShaderNodeTexImage');node.image=ring_rough;links.new(node.outputs['Color'],bs.inputs['Roughness'])
node=nodes.new('ShaderNodeTexImage');node.image=ring_normal
nm=nodes.new('ShaderNodeNormalMap');links.new(node.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bs.inputs['Normal'])

collections={}; assets={}
for quality in ['master','game']:
    c=bpy.data.collections.new(quality.title()+' independent panel');SC.collection.children.link(c)
    collections[quality]=c;assets[quality]=build_panel(c,mats,ASSET_ID+'_'+quality,quality)
    assets[quality][0]['material_revision']=2
    assets[quality][0]['ring_finish']='satin_rose_copper_metal'


def evaluated_audit(parts):
    deps=bpy.context.evaluated_depsgraph_get();tris=0;bad=0;uv_missing=0;vcount=0
    bounds=[]
    for obj in parts:
        ev=obj.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles()
        tris+=len(me.loop_triangles);vcount+=len(me.vertices)
        bm=bmesh_for(me)
        bad+=sum(1 for edge in bm.edges if not edge.is_manifold)
        bm.free()
        uv_missing+=int(not me.uv_layers)
        bounds.extend([tuple(ev.matrix_world@v.co) for v in me.vertices]);ev.to_mesh_clear()
    a=np.array(bounds)
    return {'triangles':tris,'vertices':vcount,'non_manifold_edges':bad,'meshes_missing_uv':uv_missing,
            'bounds_xyz_m':[a.min(axis=0).tolist(),a.max(axis=0).tolist()],
            'dimensions_xyz_m':(a.max(axis=0)-a.min(axis=0)).tolist(),
            'objects':len(parts),'materials':len(mats)}


def bmesh_for(mesh):
    import bmesh
    bm=bmesh.new();bm.from_mesh(mesh);return bm


stats={quality:evaluated_audit(parts) for quality,(root,parts) in assets.items()}
assert all(s['non_manifold_edges']==0 and s['meshes_missing_uv']==0 for s in stats.values()),stats
for quality,(root,parts) in assets.items():
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root]+parts:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(ASSET_ID+'_'+quality+'.glb')),
        export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
    for obj in [root]+parts:obj.select_set(False)

# One reproducible camera and light rig for direct source/game comparisons.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005))
floor=bpy.context.object;floor.name='Review floor';floor.data.materials.append(material('Studio',(.27,.29,.28),.9))
SC.world.use_nodes=True
bg=next(n for n in SC.world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs[0].default_value=(.65,.7,.8,1);bg.inputs[1].default_value=.3
for name,loc,power,size in [('Key',(-3,-4,6),550,4),('Fill',(3,-1,4),220,3),('Rim',(1,3,5),450,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((0,0,1.7))-o.location).to_track_quat('-Z','Y').to_euler()
# A tall photographic softbox gives the planar metal an environment feature
# to reflect. Both master and game use exactly the same review lighting.
bpy.ops.object.light_add(type='AREA',location=(-1.7,-4,1.8))
softbox=bpy.context.object;softbox.name='Metal review strip reflection'
softbox.data.shape='RECTANGLE';softbox.data.size=1.4;softbox.data.size_y=4.8;softbox.data.energy=150
softbox.rotation_euler=(Vector((0,0,1.65))-softbox.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();camera=bpy.context.object;SC.camera=camera
SC.render.engine='CYCLES';SC.cycles.samples=96;SC.cycles.use_denoising=True
SC.cycles.seed=7;SC.view_settings.view_transform='AgX';SC.view_settings.exposure=0
SC.render.resolution_x=900;SC.render.resolution_y=1300;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG'
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
    for dev in prefs.devices:dev.use=dev.type=='OPTIX'
    if any(dev.use for dev in prefs.devices):SC.cycles.device='GPU'
except Exception:pass


def set_view(quality,eye):
    for key,c in collections.items():c.hide_render=key!=quality;c.hide_viewport=key!=quality
    camera.location=eye;camera.rotation_euler=(Vector((0,0,1.65))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=3.85


set_view('game',(3,-9,3.6))
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=(0,0,1.65)
            area.spaces.active.region_3d.view_distance=5
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guild_decorative_panel.blend'),compress=True)
for source in [Path(__file__),HERE/'axel_guild_decorative_panel.py']:
    shutil.copyfile(source,OUT/source.name)
report={'asset_id':ASSET_ID,'stage':'independent_model_offline_review','dimensions_proposed':True,
        'material_revision':2,'ring_material':{'metallic':1.0,'roughness_range':[.22,.32],
                                             'finish':'satin rose copper with subtle finishing marks',
                                             'metal_species_confirmed':False},
        'references':['U03 dining','U05 statue frontal','user confirmation 2026-10-07'],
        'body_thickness_m':.06,'border_thickness_m':.10,'width_m':1.08,'height_m':3.3,
        'front_axis_blender':'-Y','front_axis_gltf':'+Z','origin':'floor contact, horizontal centre',
        'independent_replaceable':True,'structural_wall':False,'stats':stats,
        'deviations':['Metric dimensions and material interpretation are not officially measured.',
                      'Rear battens and small floor anchors are authored support proposals; source back is obscured.'],
        'runtime_catalog_published':False,'user_map_modified':False,
        'exports':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb')}}
(OUT/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if not ARGS.no_render:
    for quality,view,eye in [('game','front',(0,-9,1.65)),('master','front',(0,-9,1.65)),
                             ('game','three_quarter',(3,-9,3.6)),('master','three_quarter',(3,-9,3.6)),
                             ('game','back',(3,9,3.1))]:
        set_view(quality,eye);SC.render.filepath=str(OUT/(quality+'_'+view+'.png'))
        bpy.ops.render.render(write_still=True)
    set_view('game',(.6,-2.4,3.25))
    camera.rotation_euler=(Vector((0,0,2.76))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=1.12
    SC.render.resolution_x=1100;SC.render.resolution_y=1000
    SC.render.filepath=str(OUT/'metal_ring_detail.png');bpy.ops.render.render(write_still=True)
set_view('game',(3,-9,3.6))
print('DECORATIVE_PANEL_DONE',json.dumps(stats),flush=True)
