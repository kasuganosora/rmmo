"""Derive adult male and fitted starter clothing from the supplied female mesh.

Blender background script. No downloaded models and no raster repainting. Geometry,
armature rest positions and all expression shapes receive the same deformation.
"""
import bpy,bmesh,math
import sys
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from add_female_secondary_rig import add_secondary_rig
SOURCE=art_path('characters/imported/artoria/editable/character.blend')

def components(obj):
    adj=[[] for v in obj.data.vertices]
    for e in obj.data.edges:
        a,b=e.vertices;adj[a].append(b);adj[b].append(a)
    unseen=set(range(len(adj)));result=[]
    while unseen:
        todo=[unseen.pop()];part=set()
        while todo:
            v=todo.pop();part.add(v)
            for n in adj[v]:
                if n in unseen:unseen.remove(n);todo.append(n)
        result.append(part)
    return result

def delete_vertices(obj,indices):
    bm=bmesh.new();bm.from_mesh(obj.data);bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index in indices],context='VERTS')
    bm.to_mesh(obj.data);bm.free()

def plain_material(name,color):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    tree=mat.node_tree;tree.nodes.clear()
    out=tree.nodes.new('ShaderNodeOutputMaterial');bsdf=tree.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value=(*color,1);bsdf.inputs['Roughness'].default_value=.95
    tree.links.new(bsdf.outputs[0],out.inputs['Surface'])
    return mat

def apply_material(obj,mat):
    obj.data.materials.clear();obj.data.materials.append(mat)
    for p in obj.data.polygons:p.material_index=0

def slice_height(obj,low,high):
    bm=bmesh.new();bm.from_mesh(obj.data)
    inverse=obj.matrix_world.inverted()
    for height,normal in [(low,Vector((0,0,-1))),(high,Vector((0,0,1)))]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
            dist=.00001,plane_co=inverse@Vector((0,0,height)),plane_no=obj.matrix_world.to_3x3().transposed()@normal,clear_outer=True,clear_inner=False)
    bm.to_mesh(obj.data);bm.free()

def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)

def male_form(p,kind):
    x,y,z=p
    # Broader shoulders, straighter waist and narrower pelvis; retain limb lengths.
    shoulder=math.exp(-((z-1.80)/.29)**4)
    pelvis=math.exp(-((z-1.28)/.20)**4)
    width=1+.17*shoulder-.095*pelvis
    if z>1.96:
        jaw=math.exp(-((z-2.037)/.066)**2)
        width=1.035+.13*jaw
        y*=.99
        if y<.01:
            eyes=math.exp(-((abs(x)-.067)/.046)**4-((z-2.105)/.080)**4)
            z-=.16*(z-2.105)*eyes
    else:
        y*=1-.08*pelvis
        if kind in ['Body','Clothing1'] and abs(x)<.24 and y<-.075:
            chest=smoothstep(1.53,1.63,z)*(1-smoothstep(1.76,1.86,z))
            y+=(max(y,-.105)-y)*chest*.96
            if kind=='Clothing1':y-=.015*smoothstep(1.48,1.59,z)*(1-smoothstep(1.86,1.95,z))
    x*=width
    # Slightly longer legs/torso, leaving the facial height almost unchanged.
    z+=.065*smoothstep(.12,1.90,z)
    return Vector((x,y,z))

for gender in ['female','male']:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.scene.render.engine='BLENDER_EEVEE_NEXT'
    body=bpy.data.objects['Body']
    if gender=='male':
        # The bun and ribbons are independent islands; remove them, not the scalp.
        accessory=bpy.data.objects.get('HairAccessory')
        if accessory:bpy.data.objects.remove(accessory,do_unlink=True)
        hair=bpy.data.objects['Hair'];remove=set()
        for part in components(hair):
            pts=[hair.matrix_world@hair.data.vertices[i].co for i in part]
            if min(p.y for p in pts)>.145:remove.update(part)
        delete_vertices(hair,remove)
        bm=bmesh.new();bm.from_mesh(hair.data)
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if (hair.matrix_world@f.calc_center_median()).y>.115],context='FACES')
        bm.to_mesh(hair.data);bm.free()
        for v in hair.data.vertices:
            p=hair.matrix_world@v.co
            if p.z<2.13:
                p.z=2.13-(2.13-p.z)*.43
                v.co=hair.matrix_world.inverted()@p
        shirt=bpy.data.objects['Clothing1'];remove=set()
        for part in components(shirt):
            if len(part) not in [644,100]:remove.update(part)
        delete_vertices(shirt,remove)
        for obj in list(bpy.context.scene.objects):
            if obj.type!='MESH':continue
            inverse=obj.matrix_world.inverted()
            if obj.data.shape_keys:
                for shape in obj.data.shape_keys.key_blocks:
                    for v in shape.data:v.co=inverse@male_form(obj.matrix_world@v.co,obj.name)
            else:
                for v in obj.data.vertices:v.co=inverse@male_form(obj.matrix_world@v.co,obj.name)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        bpy.context.view_layer.objects.active=rig;rig.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        inverse=rig.matrix_world.inverted()
        for bone in rig.data.edit_bones:
            bone.head=inverse@male_form(rig.matrix_world@bone.head,'Rig')
            bone.tail=inverse@male_form(rig.matrix_world@bone.tail,'Rig')
        bpy.ops.object.mode_set(mode='OBJECT')
        apply_material(body,plain_material('Male ivory skin',(.88,.74,.64)))
        apply_material(shirt,plain_material('Traveller blue linen',(.095,.15,.19)))
        # Reuse the skull surface as a fitted hair shell behind the shortened locks.
        back=body.copy();back.data=bpy.data.meshes.new('Fitted short hair back');back.name='HairBack';bpy.context.collection.objects.link(back)
        verts=[];faces=[];segments=48;rings=16;inverse=body.matrix_world.inverted()
        for i in range(rings+1):
            theta=max(.0001,i/rings*2.05)
            for j in range(segments):
                phi=j/segments*math.tau
                verts.append(inverse@Vector((.157*math.sin(theta)*math.sin(phi),.14+.085*math.cos(theta),2.249+.17*math.sin(theta)*math.cos(phi))))
        for i in range(rings):
            for j in range(segments):
                a=i*segments+j;b=i*segments+(j+1)%segments
                faces.append((a,b,b+segments,a+segments))
        back.data.from_pydata(verts,[],faces);back.data.update()
        head_group=back.vertex_groups.new(name='mixamorig:Head')
        head_group.add(list(range(len(verts))),1,'REPLACE')
        apply_material(back,plain_material('Hair shell brown',(.10,.057,.029)))
        # Store the brown tint in the editable source too (not only in the game).
        hair_material=hair.data.materials[0].copy();hair.data.materials[0]=hair_material
        tree=hair_material.node_tree
        image=next(n.image for n in tree.nodes if n.type=='TEX_IMAGE')
        tree.nodes.clear();output=tree.nodes.new('ShaderNodeOutputMaterial')
        bsdf=tree.nodes.new('ShaderNodeBsdfPrincipled');bsdf.inputs['Roughness'].default_value=.9
        tex=tree.nodes.new('ShaderNodeTexImage');tex.image=image
        mix=tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
        mix.inputs[2].default_value=(.16,.105,.075,1)
        tree.links.new(tex.outputs['Color'],mix.inputs[1]);tree.links.new(mix.outputs[0],bsdf.inputs['Base Color']);tree.links.new(bsdf.outputs[0],output.inputs['Surface'])

    if gender=='female':apply_material(body,plain_material('Female ivory skin',(.91,.77,.66)))

    # Preserve the supplied skirt as a separate optional asset. The starter item
    # is called trousers in the item catalog, so it must actually display trousers.
    bpy.data.objects['Clothing2'].name='SkirtVariant'
    trousers=body.copy();trousers.data=body.data.copy();trousers.name='Clothing2'
    bpy.context.collection.objects.link(trousers)
    slice_height(trousers,.14,1.48 if gender=='female' else 1.51)
    bm=bmesh.new();bm.from_mesh(trousers.data)
    # Small cloth ease around thighs/calves; retain original skin weights.
    inverse=trousers.matrix_world.inverted()
    for v in bm.verts:
        p=trousers.matrix_world@v.co
        leg_center=.11 if p.x>=0 else -.11
        if p.z<1.13:p.x=leg_center+(p.x-leg_center)*1.12
        else:p.x*=1.045
        p.y=(p.y-.04)*1.09+.04
        v.co=inverse@p+v.normal*.004
    bm.to_mesh(trousers.data);bm.free()
    apply_material(trousers,plain_material('Traveller charcoal trousers',(.08,.105,.13)))

    # Minimal base underwear is a separate, always-on safety layer of the model.
    # It keeps the preview useful for inspecting anatomy without exposed details.
    layers=[('BaseBottom',1.13,1.45 if gender=='female' else 1.48)]
    if gender=='female':layers.append(('BaseTop',1.62,1.80))
    for name,low,high in layers:
        base=body.copy();base.data=body.data.copy();base.name=name;bpy.context.collection.objects.link(base)
        slice_height(base,low,high)
        bm=bmesh.new();bm.from_mesh(base.data)
        if name=='BaseTop':
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if abs((base.matrix_world@f.calc_center_median()).x)>.225],context='FACES')
        for v in bm.verts:v.co+=v.normal*.0025
        bm.to_mesh(base.data);bm.free()
        apply_material(base,plain_material('Base layer charcoal',(.13,.16,.18)))

    add_secondary_rig(gender)
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':
            for p in obj.data.polygons:p.use_smooth=True
    out=art_path(f'characters/imported/{gender}')
    (out/'editable').mkdir(parents=True,exist_ok=True);(out/'editable/.gdignore').touch()
    (out/'SOURCE.txt').write_text((SOURCE.parents[1]/'SOURCE.txt').read_text()+
        f'\nDerivative: {gender}; fitted trousers, separate base layer; male derived by body/face/rest-rig deformation and shortening hair.\n',encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'editable/character.blend'))
    bpy.ops.export_scene.gltf(filepath=str(out/'character.glb'),export_format='GLB',export_animations=False,export_yup=True)
    print('REFINED',gender,flush=True)
