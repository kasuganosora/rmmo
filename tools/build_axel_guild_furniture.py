"""Build independent realistic-material guild props; no editor/user-map writes."""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from axel_guild_furniture import ASSETS, build_furniture, bake_game_meshes
from axel_guild_lantern_finish import apply_lantern_finish
P=argparse.ArgumentParser();P.add_argument('--no-render',action='store_true')
P.add_argument('--renders',default='all')
P.add_argument('--set',choices=['furniture','furnishings','textiles_sanitary','guestroom'],default='furniture')
ARGS=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if ARGS.set=='furnishings':
    from axel_guild_furnishings import ASSETS, build_furnishing as build_furniture
if ARGS.set=='textiles_sanitary':
    from axel_guild_textiles_sanitary import ASSETS, build_fitting as build_furniture
if ARGS.set=='guestroom':
    from axel_guild_guestroom import ASSETS, build_guestroom as build_furniture, rig_cabinet
OUT=HERE.parents[1]/('rmmo_runtime/art_sources/axel_guild/'+ARGS.set+'_v1')
OUT.mkdir(parents=True,exist_ok=True);(OUT/'textures').mkdir(exist_ok=True)
for folder in ['game','master','preview','comparison']:(OUT/folder).mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
SC=bpy.context.scene;SC.unit_settings.system='METRIC';SC.unit_settings.scale_length=1

def mat(name,color,rough=.65,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    return m

M={
    'wood':mat('Guild owned natural joinery timber',(.36,.29,.16)),
    'wood_dark':mat('Guild recessed timber',(.22,.16,.085)),
    'steel':mat('Guild worn pewter iron',(.29,.33,.32),.38,1),
    'metal':mat('Guild patinated lantern metal',(.28,.34,.29),.40,.85),
    'inset':mat('Guild dark recessed metal',(.19,.235,.20),.49,.85),
    'glass':mat('Guild lantern frosted glass',(.72,.82,.74),.32),
    'paper':mat('Guild blank parchment',(.70,.62,.44),.9),
    'linen':mat('Guild linen',(.57,.53,.43),.9),
    'cloth':mat('Guild green woven blanket',(.15,.21,.14),.9),
    'soil':mat('Guild dry potting soil',(.075,.058,.037),.98),
}
if ARGS.set!='furniture':
    M.update({
      'redwood':mat('Guild dark red brown coated timber',(.075,.025,.014),.63),
      'brass':mat('Guild aged brass',(.48,.34,.13),.34,1),
      'dark':mat('Guild violet black hard support',(.043,.026,.036),.34),
      'dark_inset':mat('Guild recessed dark support',(.075,.049,.058),.47),
      'blueglass':mat('Guild blue inset crystal',(.012,.40,.49),.22),
      'crystal':mat('Guild registration crystal',(.015,.43,.65),.115),
      'bottle':mat('Guild olive bottle glass',(.08,.14,.074),.16),
      'pewter':mat('Guild pewter tankard',(.64,.67,.63),.32,.95),
      'ceramic':mat('Guild ivory glazed stoneware',(.67,.63,.49),.26),
      'cork':mat('Guild bottle cork',(.27,.16,.073),.95),
      'terracotta':mat('Guild muted red planter inlay',(.25,.066,.035),.54),
      'purple':mat('Guild muted plum seat leather',(.105,.049,.083),.58),
      'stone':mat('Guild registration masonry',(.23,.25,.18),.86),
      'pale_stone':mat('Guild pale counter brackets',(.49,.47,.32),.8),
      'counter_stone':mat('Guild dark polished counter',(.045,.071,.062),.30),
      'papers':mat('Guild replaceable quest papers',(.7,.61,.44),.94),
      'notice':mat('Guild notice print',(.7,.61,.44),.94),
      'label':mat('Guild bottle label',(.7,.61,.44),.94),
      'rug':mat('Guild woven entrance runner',(.10,.19,.16),.94),
      'inscription':mat('Guild authored decorative glyph band',(.3,.2,.1),.70),
    })
    for key,trans in [('crystal',.42),('blueglass',.25),('bottle',.7)]:
        p=next(n for n in M[key].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Transmission Weight'].default_value=trans;p.inputs['IOR'].default_value=1.46
    p=next(n for n in M['crystal'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Emission Color'].default_value=(.015,.48,.72,1);p.inputs['Emission Strength'].default_value=.12
    pattern_files=[('papers','quest_paper_atlas.png'),('notice','notice_pattern.png'),('label','notice_pattern.png'),
                         ('rug','runner_pattern.png'),('inscription','ornament_strip.png')]
    if ARGS.set=='textiles_sanitary':
        M.update({'tapestry':mat('Guild woven wool tapestry',(.12,.15,.10),.96),'banner':mat('Guild embroidered oxblood banner',(.25,.035,.025),.96),'rope':mat('Guild spun flax rope',(.34,.27,.13),.96),'soap':mat('Guild natural soap',(.55,.48,.32),.8)})
        pattern_files=[('tapestry','tapestry_pattern.png'),('banner','banner_pattern.png')]
    if ARGS.set=='guestroom':
        pattern_files=[]
        M.update({'upholstery':mat('Guild oxblood woven upholstery',(.23,.025,.019),.83),'welt':mat('Guild red seam piping',(.13,.015,.009),.85),'wax':mat('Guild ivory candle wax',(.78,.72,.57),.48),'wick':mat('Guild charred linen wick',(.012,.009,.007),.99),'iron':mat('Guild forged dark iron',(.045,.040,.034),.55,.80)})
        next(n for n in M['linen'].node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.82,.79,.70,1)
    for key,filename in pattern_files:
        nt=M[key].node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'textures'/filename));tex.image.pack()
        nt.links.new(tex.outputs['Color'],p.inputs['Base Color'])

def image(name,rgb,srgb=False):
    h,w=rgb.shape[:2];rgba=np.ones((h,w,4),dtype=np.float32)
    rgba[:,:,:3]=rgb if rgb.ndim==3 else rgb[:,:,None]
    im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    im.colorspace_settings.name='sRGB' if srgb else 'Non-Color'
    im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(OUT/'textures'/(name+'.png'))
    im.file_format='PNG';im.save();im.pack();return im

def mapped(m,base,rough,normal):
    nt=m.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    for im,slot in [(base,'Base Color'),(rough,'Roughness')]:
        n=nt.nodes.new('ShaderNodeTexImage');n.image=im;nt.links.new(n.outputs['Color'],p.inputs[slot])
    n=nt.nodes.new('ShaderNodeTexImage');n.image=normal
    nm=nt.nodes.new('ShaderNodeNormalMap');nt.links.new(n.outputs['Color'],nm.inputs['Color'])
    nm.inputs['Strength'].default_value=.35
    nt.links.new(nm.outputs['Normal'],p.inputs['Normal'])

# Reuse the already-owned Fab wood set, curated for furniture in this project.
# Preserve colour, OpenGL normal and roughness; pack all maps into each GLB.
wood_source=HERE.parents[1]/'rmmo_runtime/packs/default/assets/materials/wood/natural_joinery'
wood_images=[]
for filename,srgb in [('texture.png',True),('roughness.png',False),('normal.png',False)]:
    dest=OUT/'textures'/('owned_joinery_'+filename);shutil.copyfile(wood_source/filename,dest)
    im=bpy.data.images.load(str(dest));im.colorspace_settings.name='sRGB' if srgb else 'Non-Color'
    im.pack();wood_images.append(im)
if ARGS.set=='guestroom':
    timber=wood_images[0];pixels=np.empty(len(timber.pixels),dtype=np.float32);timber.pixels.foreach_get(pixels)
    rgba=pixels.reshape(-1,4);rgba[:,:3]*=np.array([.50,.36,.24]);timber.pixels.foreach_set(pixels);timber.save();timber.pack()
mapped(M['wood'],*wood_images)
if ARGS.set=='guestroom':mapped(M['wood_dark'],*wood_images)
if ARGS.set!='furniture':
    # Coated board keeps timber pore normal without replacing its deep red pigment.
    nt=M['redwood'].node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=wood_images[2]
    nm=nt.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.18
    nt.links.new(tex.outputs['Color'],nm.inputs['Color']);nt.links.new(nm.outputs['Normal'],p.inputs['Normal'])
    stone_source=wood_source.parents[1]/'walls/stone_tiles_facade'
    stone_images=[]
    for filename,srgb in [('texture.jpg',True),('roughness.png',False),('normal.png',False)]:
        dest=OUT/'textures'/('owned_stone_'+filename);shutil.copyfile(stone_source/filename,dest)
        im=bpy.data.images.load(str(dest));im.colorspace_settings.name='sRGB' if srgb else 'Non-Color';im.pack();stone_images.append(im)
    mapped(M['stone'],*stone_images)
    shutil.copyfile(stone_source/'material.json',OUT/'stone_material_provenance.json')
shutil.copyfile(wood_source/'material.json',OUT/'wood_material_provenance.json')
n=1024;y,x=np.mgrid[0:n,0:n]/n
if ARGS.set!='furniture':
    # Portable baked microtexture; no Blender-only procedural shader is exported.
    rng=np.random.default_rng(91)
    grain=rng.random((n,n))
    for key in ['brass','dark','pewter','purple','ceramic','counter_stone']:
        nt=M[key].node_tree;p=next(k for k in nt.nodes if k.type=='BSDF_PRINCIPLED')
        rough=p.inputs['Roughness'].default_value
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image(key+'_roughness',np.clip(rough+(grain-.5)*.06,0,1))
        nt.links.new(tex.outputs['Color'],p.inputs['Roughness'])
    glow=np.zeros((n,n,3));glow[:]=(.015,.48,.72)
    stars=grain>.997
    glow[stars]=(.34,.82,1.0)
    nt=M['crystal'].node_tree;p=next(k for k in nt.nodes if k.type=='BSDF_PRINCIPLED')
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image('crystal_luminous_grain',glow)
    nt.links.new(tex.outputs['Color'],p.inputs['Emission Color'])
for key in (['linen','cloth','tapestry','banner'] if ARGS.set=='textiles_sanitary' else ['linen','cloth','upholstery'] if ARGS.set=='guestroom' else ['linen','cloth']):
    weave=.008*(np.sin(x*2*np.pi*190)+np.sin(y*2*np.pi*190))
    gy,gx=np.gradient(weave);norm=np.stack([-gx,-gy,np.ones_like(gx)],axis=2)
    norm/=np.linalg.norm(norm,axis=2,keepdims=True)
    nt=M[key].node_tree;p=next(k for k in nt.nodes if k.type=='BSDF_PRINCIPLED')
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image(key+'_normal',norm*.5+.5)
    nm=nt.nodes.new('ShaderNodeNormalMap');nt.links.new(tex.outputs['Color'],nm.inputs['Color']);nt.links.new(nm.outputs['Normal'],p.inputs['Normal'])

def stats(parts):
    deps=bpy.context.evaluated_depsgraph_get();points=[];tris=bad=missing=0
    for obj in parts:
        ev=obj.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles();tris+=len(me.loop_triangles)
        bm=bmesh.new();bm.from_mesh(me);bad+=sum(not e.is_manifold for e in bm.edges);bm.free()
        missing+=int(not me.uv_layers);points.extend([tuple(ev.matrix_world@v.co) for v in me.vertices]);ev.to_mesh_clear()
    coords=np.asarray(points);lo=coords.min(axis=0);hi=coords.max(axis=0)
    return {'triangles':tris,'meshes':len(parts),'non_manifold_edges':bad,'missing_uv':missing,
            'bounds_xyz_m':[lo.tolist(),hi.tolist()],'dimensions_xyz_m':(hi-lo).tolist()}

from axel_guild_magic_lantern import magic_materials, add_preview_light
if ARGS.set=='furniture':M['glass'],M['magic_stone']=magic_materials()
assets={};records={}
for kind,(label,refs) in ASSETS.items():
    assets[kind]={};records[kind]={'asset_id':'guild_'+kind,'label':label,'references':refs,'stats':{}}
    for quality in ['master','game']:
        col=bpy.data.collections.new(kind+'_'+quality);SC.collection.children.link(col)
        root,parts=build_furniture(kind,col,M,quality,'guild_'+kind+'_'+quality)
        if kind=='hall_lantern':apply_lantern_finish(parts)
        if quality=='game':parts=bake_game_meshes(root,parts)
        if ARGS.set=='guestroom':rig_cabinet(root,parts)
        bpy.context.view_layer.update();s=stats(parts)
        assert s['non_manifold_edges']==0 and s['missing_uv']==0,(kind,quality,s)
        assert abs(s['bounds_xyz_m'][0][2])<.002,(kind,s)
        records[kind]['stats'][quality]=s
        bpy.ops.object.select_all(action='DESELECT')
        for o in [root]+parts:o.select_set(True)
        path=OUT/quality/('guild_'+kind+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True,export_attributes=True,export_animation_mode='NLA_TRACKS',export_frame_range=False)
        records[kind][quality+'_glb_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        assets[kind][quality]=(col,root,parts)

# Identical studio, camera and exposure for master/game comparison.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.008));bpy.context.object.name='Review_floor'
bpy.context.object.data.materials.append(mat('Review neutral floor',(.25,.265,.25),.95))
SC.world.use_nodes=True
bg=next(n for n in SC.world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs[0].default_value=(.65,.70,.78,1);bg.inputs[1].default_value=.35
lights=[]
for name,loc,power,size in [('Key',(-3,-4,6),750,4),('Fill',(3,-2,3),300,3),('Rim',(0,3,5),650,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name
    o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((0,0,1.2))-o.location).to_track_quat('-Z','Y').to_euler();lights.append(o)
bpy.ops.object.camera_add();cam=bpy.context.object;SC.camera=cam
SC.render.engine='CYCLES';SC.cycles.samples=32;SC.cycles.use_denoising=True;SC.cycles.seed=41
SC.render.resolution_x=720;SC.render.resolution_y=720;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG';SC.view_settings.view_transform='AgX';SC.view_settings.exposure=0

def show(kind,quality):
    for k,qualities in assets.items():
        for q,(c,root,parts) in qualities.items():c.hide_render=(k,q)!=(kind,quality);c.hide_viewport=c.hide_render
    s=records[kind]['stats'][quality];dim=s['dimensions_xyz_m'];height=dim[2]
    target=Vector((0,0,height*.50));cam.location=target+Vector((4,-7,3.6))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=max(dim)*1.32
    if kind.startswith('quest_board') or kind in ['round_notice_board','sloped_notice_stand']:
        cam.location=target+Vector((2,-8,1.9));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    SC.cycles.samples=64 if kind=='registration_crystal' else 32

show(next(iter(ASSETS)),'game')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guild_furniture.blend'),compress=True)
for source in [Path(__file__),HERE/'axel_guild_furniture.py',HERE/'axel_guild_lantern_finish.py',HERE/'axel_guild_magic_lantern.py']+([HERE/'axel_guild_furnishings.py'] if ARGS.set!='furniture' else [])+([HERE/'axel_guild_textiles_sanitary.py'] if ARGS.set=='textiles_sanitary' else []):shutil.copyfile(source,OUT/source.name)
if ARGS.set=='guestroom':shutil.copyfile(HERE/'axel_guild_guestroom.py',OUT/'axel_guild_guestroom.py')
report={'stage':'independent_furniture_offline_review','asset_count':len(ASSETS),'assets':records,
        'front_axis_blender':'-Y','front_axis_gltf':'+Z','units':'metres','origin':'floor centre',
        'material_maps':'embedded portable PBR; owned Fab natural joinery wood, authored cloth weave',
        'wood_source':str(wood_source),'wood_provenance':'wood_material_provenance.json',
        'dimensions_are_proposals':True,'runtime_catalog_published':False,'user_map_modified':False,
        'limitations':['Upper floor furniture and hidden construction are authored proposals.',
                       'Generic GLB does not supply sitting, cupboard doors, light switching or cross-instance batching.',
                       'Light socket and emissive pane remain separate; game day/night connection pending publication.',
                       'Notice paper is blank and replaceable; bottles and planter vegetation are separate contents.',
                       'Statue, suspended skeleton and sanitary fixtures are separate tasks.']}
if ARGS.set=='furnishings':
    report['stage']='additional_furnishings_and_landmarks_offline_review'
    report['limitations']=['Metric dimensions, hidden supports and authored glyph patterns are proposals.',
      'Task/register gameplay, light activation, wind, native editor publication and batching are not connected.',
      'Cups, bottles, planters and shelf contents remain separate; plants and food not welded into furniture.',
      'Statue, suspended skeleton, architectural joinery and sanitary fixtures are not part of this furnishing batch.']
if ARGS.set=='textiles_sanitary':
    report['stage']='textiles_and_authored_sanitary_offline_review'
    report['limitations']=['U04/U07 establish textile shapes; motifs and hidden supports are authored.','All sanitary fittings are authored to the approved L1 plan, not verified anime props.','Water, drainage, waste, cloth motion, native editor and runtime interactions are not connected.','WindWeight is retained on the master mesh; custom _WIND_WEIGHT attribute carries wind amplitude without tinting base color.']
if ARGS.set=='guestroom':
    report['stage']='U15_U22_guestroom_independent_models'
    report['limitations']=['Visible furniture follows U15/U22; dimensions and hidden construction proposed.','Candles are unlit meshes with sockets; flame and runtime light not connected.','Cabinet Open/Close clips exported per door; input-driven interaction and moving runtime collision pending editor publication.','Sitting, sleeping and editor publication not connected.']
(OUT/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if not ARGS.no_render:
    selected=set(ASSETS) if ARGS.renders=='all' else set(ARGS.renders.split(','))
    for kind in ASSETS:
        if kind not in selected:continue
        SC.frame_set(1)
        show(kind,'game');SC.render.filepath=str(OUT/'preview'/(kind+'.png'));bpy.ops.render.render(write_still=True)
        # Review every reduction, not just a chosen representative asset.
        show(kind,'master');SC.render.filepath=str(OUT/'comparison'/(kind+'_master.png'));bpy.ops.render.render(write_still=True)
    if ARGS.set=='guestroom':
        for kind in ['guest_nightstand','guest_low_cabinet']:
            if kind in selected:
                show(kind,'game');SC.frame_set(31);cam.data.ortho_scale*=1.4;SC.render.filepath=str(OUT/'preview'/(kind+'_open.png'));bpy.ops.render.render(write_still=True)
        SC.frame_set(1)
    if 'hall_lantern' in selected:
        show('hall_lantern','game');bg.inputs[1].default_value=.035
        for o in lights:o.data.energy*=.04
        preview_light=add_preview_light(assets['hall_lantern']['game'][1],SC.collection)
        SC.render.filepath=str(OUT/'preview'/'hall_lantern_night.png');bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(preview_light,do_unlink=True)
    if 'registration_crystal' in selected:
        show('registration_crystal','game')
        p=next(n for n in M['crystal'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Emission Strength'].default_value=1.0
        SC.render.filepath=str(OUT/'preview'/'registration_crystal_active.png');bpy.ops.render.render(write_still=True)
        p.inputs['Emission Strength'].default_value=.12
    if ARGS.set=='textiles_sanitary' and 'washstand' in selected:
        show('washstand','game')
        for kind,positions in [('wash_basin',[(-.43,-.035,.84),(.43,-.035,.84)]),('brass_faucet',[(-.43,.275,.84),(.43,.275,.84)]),('wash_ewer',[(0,0,.84)]),('soap_dish',[(-.68,-.10,.84)])]:
            col,root,parts=assets[kind]['game'];col.hide_render=False;col.hide_viewport=False
            root.location=positions[0]
            for loc in positions[1:]:
                duplicate=root.copy();col.objects.link(duplicate);duplicate.location=loc
                for part in parts:
                    obj=part.copy();obj.data=part.data;col.objects.link(obj);obj.parent=duplicate
        target=Vector((0,0,.60));cam.location=target+Vector((3,-6,4));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.4
        SC.render.filepath=str(OUT/'preview'/'washstation_assembled.png');bpy.ops.render.render(write_still=True)
print('GUILD_FURNITURE_COMPLETE',json.dumps({k:v['stats']['game']['triangles'] for k,v in records.items()}),flush=True)

