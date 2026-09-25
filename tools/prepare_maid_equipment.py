"""Extract only garments from the supplied Maid FBX; bind to the shared adult rigs."""
import bpy,math,bmesh
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[1]
SOURCE=art_path('characters/source_models/maid')
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'inspected.blend'))
source=bpy.data.objects['Body'];rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
rests={b.name:(rig.matrix_world@b.matrix_local).copy() for b in rig.data.bones}
records=[]
for material,name,texture in [(2,'MaidDress','Clothes_Tex.png'),(3,'MaidShoes','Shoes_Tex.png')]:
    polygons=[p for p in source.data.polygons if p.material_index==material]
    ids=sorted({i for p in polygons for i in p.vertices});mapping={old:new for new,old in enumerate(ids)}
    points=[(source.matrix_world@source.data.vertices[i].co).copy() for i in ids]
    weights=[{source.vertex_groups[g.group].name:g.weight for g in source.data.vertices[i].groups} for i in ids]
    faces=[[mapping[i] for i in p.vertices] for p in polygons]
    uvs=[[tuple(source.data.uv_layers.active.data[i].uv) for i in p.loop_indices] for p in polygons]
    records.append((name,texture,points,weights,faces,uvs))

for gender in ['female','male']:
    bpy.ops.wm.open_mainfile(filepath=str(art_path(f'characters/imported/{gender}/editable/character.blend')))
    target=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    target_rests={b.name:(target.matrix_world@b.matrix_local).copy() for b in target.data.bones}
    body=bpy.data.objects['Body'];objects=[]
    foot_tree=KDTree(len(body.data.vertices))
    for vertex in body.data.vertices:foot_tree.insert(body.matrix_world@vertex.co,vertex.index)
    foot_tree.balance()
    for name,texture,points,weights,faces,uvs in records:
        fitted=[];skin=[]
        for p,groups in zip(points,weights):
            valid={k:v for k,v in groups.items() if k in target_rests and v>0}
            if not valid:valid={'mixamorig:Hips':1}
            total=sum(valid.values());valid={k:v/total for k,v in valid.items()}
            position=Vector((0,0,0))
            for k,w in valid.items():
                src=rests[k];dst=target_rests[k]
                rotation=dst.to_quaternion()@src.to_quaternion().inverted()
                position+=(dst.translation+rotation@((p-src.translation)*1.29))*w
            if name=='MaidShoes':
                # FBX bone rolls differ: align anatomical feet in world space,
                # never rotate footwear with the source bone's arbitrary axes.
                side='Left' if p.x>0 else 'Right'
                src=rests['mixamorig:'+side+'Foot'].translation
                dst=target_rests['mixamorig:'+side+'Foot'].translation
                position=dst+Vector(((p.x-src.x)*1.38,(p.y-src.y)*1.42,(p.z-src.z)*1.42))
                # Share the fitted foot's skinning, including toe/ankle blending.
                valid={};total=0
                for _,index,distance in foot_tree.find_n(position,4):
                    influence=1/max(distance,.002)**2;total+=influence
                    for group in body.data.vertices[index].groups:
                        key=body.vertex_groups[group.group].name
                        valid[key]=valid.get(key,0)+group.weight*influence
                valid={key:weight/total for key,weight in valid.items()}
            # Gentle ease: cloth stays outside the fitted body at the chest/waist.
            if name=='MaidDress':
                position.x*=1.035
                position.y*=1.08
                if gender=='male' and abs(position.x)<.25 and position.y<-.12:
                    t=max(0,min(1,(position.z-1.59)/.13));lo=t*t*(3-2*t)
                    t=max(0,min(1,(position.z-1.88)/.12));hi=1-t*t*(3-2*t)
                    position.y+=(-.12-position.y)*lo*hi*.94
            fitted.append(body.matrix_world.inverted()@position)
            if gender=='female' and name=='MaidDress':
                x,y,z=position;t=max(0,min(1,(-y-.03)/.08));front=t*t*(3-2*t)
                amount=.92*math.exp(-((abs(x)-.085)/.115)**4-((z-1.70)/.15)**4)*front
                split=max(0,min(1,(x+.025)/.05));split=split*split*(3-2*split)
                valid={k:v*(1-amount) for k,v in valid.items()}
                valid['SecondaryBreastLeft']=amount*split;valid['SecondaryBreastRight']=amount*(1-split)
            skin.append(valid)
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(fitted,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
        obj.parent=target;obj.matrix_world=body.matrix_world.copy()
        for bone in target.data.bones:obj.vertex_groups.new(name=bone.name)
        for i,groups in enumerate(skin):
            for bone,w in groups.items():
                if w>.00001:obj.vertex_groups[bone].add([i],w,'REPLACE')
        uv=mesh.uv_layers.new(name='UVMap')
        for polygon,coords in zip(mesh.polygons,uvs):
            polygon.use_smooth=True
            for index,coord in zip(polygon.loop_indices,coords):uv.data[index].uv=coord
        modifier=obj.modifiers.new('Shared character skeleton','ARMATURE');modifier.object=target
        mat=bpy.data.materials.new(name+' original texture');mat.use_nodes=True
        nodes=mat.node_tree.nodes;nodes.clear()
        output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission')
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(SOURCE/'Textures'/texture));tex.image.pack()
        mat.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color']);mat.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
        mesh.materials.append(mat);objects.append(obj)
    # Fitted stockings cover the ankle too, avoiding overlap with the old boot-specific overlay.
    socks=body.copy();socks.data=body.data.copy();socks.name='MaidStockings';bpy.context.collection.objects.link(socks)
    bm=bmesh.new();bm.from_mesh(socks.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if (socks.matrix_world@f.calc_center_median()).z>.92],context='FACES')
    for vertex in bm.verts:
        vertex.co+=vertex.normal*.003
        p=socks.matrix_world@vertex.co
        if p.z<.14:
            # Keep the invisible sock sole/toes inside the leather shell.
            t=max(0,min(1,(.14-p.z)/.06));t=t*t*(3-2*t)
            center=target_rests['mixamorig:'+('Left' if p.x>0 else 'Right')+'Foot'].translation
            p.x=center.x+(p.x-center.x)*(1-.08*t)
            p.y=center.y+(p.y-center.y)*(1-.09*t)
            p.z+=max(0,.018-p.z)*t
            vertex.co=socks.matrix_world.inverted()@p
    bm.to_mesh(socks.data);bm.free()
    mat=bpy.data.materials.new('Maid opaque fitted stockings');mat.diffuse_color=(.035,.028,.033,1)
    socks.data.materials.clear();socks.data.materials.append(mat)
    for polygon in socks.data.polygons:polygon.material_index=0;polygon.use_smooth=True
    objects.append(socks)
    # Original head ornament, attached only to the shared Head bone. Kept
    # separate from hair and dress so other accessories can reuse this slot.
    verts=[];faces=[];material_ids=[]
    for frill in [False,True]:
        start=len(verts);steps=64
        for i in range(steps+1):
            angle=-1.20+2.40*i/steps
            for edge in range(2):
                radius=.018+(edge*.042 if frill else 0)
                ripple=.006*math.sin(i/steps*math.tau*12) if frill and edge else 0
                x=(.18+radius+ripple)*math.sin(angle)
                z=(2.115 if gender=="female" else 2.185)+(.245+radius+ripple)*math.cos(angle)
                y=-.055+(.065*edge if not frill else -.008+math.sin(i/steps*math.tau*12)*.006*edge)
                verts.append(body.matrix_world.inverted()@Vector((x,y,z)))
        for i in range(steps):
            a=start+i*2;faces.append((a,a+1,a+3,a+2));material_ids.append(1 if frill else 0)
    mesh=bpy.data.meshes.new('MaidHeadpiece');mesh.from_pydata(verts,[],faces);mesh.update()
    headpiece=bpy.data.objects.new('MaidHeadpiece',mesh);bpy.context.collection.objects.link(headpiece)
    headpiece.parent=target;headpiece.matrix_world=body.matrix_world.copy()
    group=headpiece.vertex_groups.new(name='mixamorig:Head');group.add(list(range(len(verts))),1,'REPLACE')
    armature=headpiece.modifiers.new('Shared head attachment','ARMATURE');armature.object=target
    for name,color in [('Black headband',(.018,.020,.026,1)),('White lace',(.92,.92,.91,1))]:
        mat=bpy.data.materials.new(name);mat.diffuse_color=color;mat.use_nodes=True
        bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bsdf.inputs['Base Color'].default_value=color;bsdf.inputs['Roughness'].default_value=.9
        mat.use_backface_culling=False;mesh.materials.append(mat)
    for polygon,index in zip(mesh.polygons,material_ids):polygon.material_index=index;polygon.use_smooth=True
    objects.append(headpiece)
    bpy.ops.object.select_all(action='DESELECT');target.select_set(True)
    for obj in objects:obj.select_set(True)
    out=art_path(f'characters/equipment/maid/{gender}');out.mkdir(parents=True,exist_ok=True)
    (out/'editable').mkdir(exist_ok=True);(out/'editable/.gdignore').touch()
    # Editable outfit file contains the reference body as well, runtime GLB exports selected garments only.
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'editable/maid.blend'))
    bpy.ops.export_scene.gltf(filepath=str(out/'outfit.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
    (out/'License.txt').write_bytes((SOURCE/'License.txt').read_bytes())
    (out/'SOURCE.txt').write_text('Garments extracted from user-supplied Maid.zip (bundled CC0 license).\nAdapted to the shared '+gender+' rig; no source body, face or hair in outfit.glb.\n',encoding='utf-8')
    print('MAID_EXPORTED',gender,flush=True)
