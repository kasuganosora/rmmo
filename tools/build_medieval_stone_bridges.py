"""Original realistic bridge models, built in Blender; no third-party bridge meshes.

Blender -b --python tools/build_medieval_stone_bridges.py -- --output <content dir>
Coordinates: bridge length X, Blender up Z, deck Z=0. GLB uses Godot Y up.
Material images remain shared external pack resources; runtime binds the three PBR slots.
"""
import argparse
import hashlib
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
opts = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
out = Path(opts.output).resolve()
out.mkdir(parents=True, exist_ok=True)
materials_root = out.parents[1] / 'materials'
rng = random.Random(1974)
objects = []

def material(role, folder):
    spec = json.loads((materials_root / folder / 'material.json').read_text(encoding='utf-8'))['material']
    mat = bpy.data.materials.new('bridge_' + role)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None) or nodes.new('ShaderNodeOutputMaterial')
        links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    bsdf.inputs['Roughness'].default_value = spec.get('roughness', .88)
    texcoord = nodes.new('ShaderNodeTexCoord')
    for key, socket in [('texture_path','Base Color'), ('roughness_path','Roughness'), ('normal_path','Normal')]:
        if key not in spec: continue
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(materials_root / folder / spec[key]), check_existing=True)
        if key != 'texture_path': tex.image.colorspace_settings.name = 'Non-Color'
        links.new(texcoord.outputs['UV'],tex.inputs['Vector'])
        if key == 'normal_path':
            normal = nodes.new('ShaderNodeNormalMap')
            normal.inputs['Strength'].default_value = .8
            links.new(tex.outputs['Color'],normal.inputs['Color'])
            links.new(normal.outputs['Normal'],bsdf.inputs[socket])
        else: links.new(tex.outputs['Color'],bsdf.inputs[socket])
    return mat

def prism(name, section, y0, y1, role=1, bevel=.025, segments=2):
    # section in X/Z, closed outward quads along width Y
    verts = [(x,y0,z) for x,z in section]+[(x,y1,z) for x,z in section]
    n = len(section)
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces); mesh.update()
    ob = bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mats[role]); objects.append(ob)
    # Correct winding with Blender's mesh operation; deterministic and offline only.
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    if bevel:
        mod=ob.modifiers.new('Worn stone edge','BEVEL'); mod.width=bevel; mod.segments=segments; mod.affect='EDGES'
        mod.limit_method='ANGLE'; mod.angle_limit=.22
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=ob.modifiers.new('Stone weighted normals','WEIGHTED_NORMAL'); mod.keep_sharp=True; mod.weight=50
        for p in ob.data.polygons: p.use_smooth=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    uv = ob.data.uv_layers.new(name='UVMap')
    # Metre-based box projection, 2m source textures. Arch blocks have individual offsets.
    du,dv = rng.random()*3,rng.random()*3
    for p in ob.data.polygons:
        axis=max(range(3),key=lambda k:abs(p.normal[k]))
        for li in p.loop_indices:
            v=ob.data.vertices[ob.data.loops[li].vertex_index].co
            xy=(v.x,v.y) if axis==2 else ((v.x,v.z) if axis==1 else (v.y,v.z))
            uv.data[li].uv=(xy[0]/2+du,xy[1]/2+dv)
    attr=ob.data.color_attributes.new(name='StoneVariation',type='FLOAT_COLOR',domain='CORNER')
    value=rng.uniform(.88,1.0) if role else 1
    for c in attr.data: c.color=(value,value*.995,value*.98,1)
    ob.select_set(False)
    return ob

def box(name,x0,x1,y0,y1,z0,z1,role=1,bevel=.025,segments=2):
    return prism(name,[(x0,z0),(x1,z0),(x1,z1),(x0,z1)],y0,y1,role,bevel,segments)


mats=[material('deck','paving/outdoor_flagstone'),material('masonry','walls/castle_rubble'),material('trim','walls/stone_tiles_facade')]
def join_piece(name):
    global objects
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join()
    ob=bpy.context.object; ob.name=name
    old=list(ob.data.materials); mapping=[mats.index(m) for m in old]
    indices=[mapping[p.material_index] for p in ob.data.polygons]
    ob.data.materials.clear()
    for m in mats: ob.data.materials.append(m)
    for p,i in zip(ob.data.polygons,indices): p.material_index=i
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    objects=[]; ob.select_set(False)
    return ob

def make_kit(style):
    global objects
    objects=[]; rng.seed(873)
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    w=7.; opening=8.; rise=3.05 if style=='pointed' else 2.55; spring=-.65-rise
    def arch(t):
        if style=='pointed': return spring+rise*math.sqrt(max(0,1-(abs(t)*.6+.4)**2))/math.sqrt(.84)
        return spring+rise*math.sqrt(max(0,1-t*t))
    poly=[(-4+8*j/64,arch(j/32-1)) for j in range(65)]+[(4,-.25),(-4,-.25)]
    prism('Arch masonry',poly,-w/2,w/2,1,.016)
    for j in range(25):
        a=math.pi*(j+.017)/25; b=math.pi*(j+1-.017)/25
        def edge(t,r): return (-math.cos(t)*(4+r),arch(-math.cos(t))+r*math.sin(t))
        p=[edge(a,0),edge(b,0),edge(b,.43),edge(a,.43)]
        for side in (-1,1): prism('Radial cut stone',p,side*w/2-.105,side*w/2+.105,2,.024)
    join_piece('arch')
    box('Pier',-.65,.65,-w/2,w/2,-5,-.25,1,.045)
    # Cutwaters are horizontal triangular prisms, with sloped caps, manually UV mapped.
    for side in (-1,1):
        y=side*w/2; tip=side*(w/2+1.05)
        verts=[(-.65,y,-5),(.65,y,-5),(0,tip,-5),(-.65,y,-.3),(.65,y,-.3),(0,tip,-.85)]
        me=bpy.data.meshes.new('Cutwater'); me.from_pydata(verts,[],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]); me.update()
        ob=bpy.data.objects.new('Pier cutwater',me); bpy.context.collection.objects.link(ob); ob.data.materials.append(mats[1]); objects.append(ob)
        bpy.context.view_layer.objects.active=ob; ob.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
        mod=ob.modifiers.new('Worn pier edges','BEVEL'); mod.width=.045; mod.segments=2; bpy.ops.object.modifier_apply(modifier=mod.name)
        uv=ob.data.uv_layers.new()
        for p in ob.data.polygons:
            for li in p.loop_indices:
                v=ob.data.vertices[ob.data.loops[li].vertex_index].co; uv.data[li].uv=((v.x+v.y)/2,v.z/2)
        ob.select_set(False)
    join_piece('pier')
    box('Abutment',-.5,.5,-w/2,w/2,-5,-.25,1,.035); join_piece('abutment')
    # Deck segments keep exact coincident end planes; no bevel on walking joins.
    box('Continuous deck',-.5,.5,-w/2,w/2,-.25,0,0,0); join_piece('deck')
    rail=.98 if style=='rustic' else 1.08
    box('Rail mortar core',-.5,.5,-.20,.20,0,rail-.07,1,.008)
    for row in range(3):
        cuts=[-.5,-.04,.5] if row%2==0 else [-.5,-.30,.26,.5]
        for a,b in zip(cuts,cuts[1:]):
            box('Bevelled ashlar rail',a+.009,b-.009,-.23,.23,row*(rail-.07)/3+.012,(row+1)*(rail-.07)/3-.009,1,.019,1)
    prism('Coping',[(-.49,rail-.10),(.49,rail-.10),(.49,rail+.05),(.42,rail+.13),(-.42,rail+.13),(-.49,rail+.05)],-.30,.30,2,.02)
    join_piece('parapet')
    box('Bridgehead post',-.28,.28,-.27,.27,0,rail+.08,1,.035)
    box('Cap',-.32,.32,-.3,.3,rail+.08,rail+.23,2,.03); join_piece('post')
    bpy.ops.object.select_all(action='SELECT')
    native=out.parents[2]/'sources'/'authored'/'bridges'; native.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(native/('stone_'+style+'.blend')))
    placeholders=[]
    for source in mats:
        placeholder=bpy.data.materials.new(source.name+'_runtime'); placeholder.use_nodes=False
        placeholders.append(placeholder)
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH': continue
        for slot in ob.material_slots:
            slot.material=placeholders[mats.index(slot.material)]
    bpy.ops.export_scene.gltf(filepath=str(out/('stone_'+style+'.glb')),export_format='GLB',use_selection=True,export_materials='EXPORT',export_yup=True,export_normals=True,export_texcoords=True,export_vertex_color="ACTIVE",export_all_vertex_colors=True,export_extras=True)
    stats={}
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH': ob.data.calc_loop_triangles(); stats[ob.name]=len(ob.data.loop_triangles)
    print('BRIDGE_KIT_BUILT',style,stats,flush=True)

for style in ('segmental','pointed','rustic'): make_kit(style)

(out/'source.json').write_text(json.dumps({
    'format':'rmmo_bridge_modules', 'version':1,
    'authoring_tool':'Blender 4.5', 'generator':'tools/build_medieval_stone_bridges.py',
    'origin':'Original project geometry; style reference only, no vendor mesh or textures copied.',
    'reference':'https://www.fab.com/listings/802b970a-ea78-4b26-bfcc-ed74f2347b0e',
    'modules':['arch','pier','abutment','deck','parapet','post'],
    'materials':{'deck':'paving/outdoor_flagstone','masonry':'walls/castle_rubble','trim':'walls/stone_tiles_facade'},
    'assets':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob('stone_*.glb'))},
},indent=2),encoding='utf-8')
