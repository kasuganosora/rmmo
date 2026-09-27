"""Extract only garments from the supplied Maid FBX; bind to the shared adult rigs."""
import bpy,math,bmesh
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector,Quaternion
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[1]
SOURCE=art_path('characters/source_models/maid')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(SOURCE/'Maid.fbx'))
source=bpy.data.objects['Body'];rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
# Subdivision preserves every source panel and UV boundary while allowing the
# adapted surface to follow curved skin without triangle interiors clipping.
bm=bmesh.new();bm.from_mesh(source.data)
bmesh.ops.subdivide_edges(bm,edges=[e for e in bm.edges if any(f.material_index==2 for f in e.link_faces)],cuts=2,use_grid_fill=True)
bm.to_mesh(source.data);bm.free()
rests={b.name:(rig.matrix_world@b.matrix_local).copy() for b in rig.data.bones}
semantic_children={'Hips':'Spine','Spine':'Spine1','Spine1':'Spine2','Spine2':'Neck','Neck':'Head'}
for side in ['Left','Right']:
    for parent,child in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('UpLeg','Leg'),('Leg','Foot'),('Foot','ToeBase')]:
        semantic_children[side+parent]=side+child
records=[]
for material,name,texture in [(2,'MaidDress','Clothes_Tex.png'),(3,'MaidShoes','Shoes_Tex.png')]:
    polygons=[p for p in source.data.polygons if p.material_index==material]
    ids=sorted({i for p in polygons for i in p.vertices});mapping={old:new for new,old in enumerate(ids)}
    points=[(source.matrix_world@source.data.vertices[i].co).copy() for i in ids]
    weights=[{source.vertex_groups[g.group].name:g.weight for g in source.data.vertices[i].groups} for i in ids]
    faces=[[mapping[i] for i in p.vertices] for p in polygons]
    uvs=[[tuple(source.data.uv_layers.active.data[i].uv) for i in p.loop_indices] for p in polygons]
    records.append((name,texture,points,weights,faces,uvs))

for gender in (['male'] if '--male-only' in sys.argv else ['female'] if '--female-only' in sys.argv else ['female','male']):
    bpy.ops.wm.open_mainfile(filepath=str(art_path(f'characters/imported/{gender}/editable/character.blend')))
    target=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    target_rests={b.name:(target.matrix_world@b.matrix_local).copy() for b in target.data.bones}
    body=bpy.data.objects['Body'];objects=[]
    foot_tree=KDTree(len(body.data.vertices))
    for vertex in body.data.vertices:foot_tree.insert(body.matrix_world@vertex.co,vertex.index)
    foot_tree.balance()
    body_surface=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[list(p.vertices) for p in body.data.polygons])
    torso_faces=[]
    for face in body.data.polygons:
        limb=max(sum(g.weight for g in body.data.vertices[i].groups if body.vertex_groups[g.group].name.endswith(('Arm','ForeArm','Hand'))) for i in face.vertices)
        if limb<.25:torso_faces.append(list(face.vertices))
    torso_surface=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],torso_faces)
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
                if name=='MaidDress':
                    # FBX and target bone rolls differ by ~180 degrees on
                    # the thighs. Roll is a coordinate convention, not an
                    # anatomical twist to bake into the skirt. Align the
                    # actual joint segments while preserving cloth volume.
                    child='mixamorig:'+semantic_children.get(k.removeprefix('mixamorig:'),'')
                    rotation=Quaternion()
                    if child in rests and child in target_rests:
                        source_axis=rests[child].translation-src.translation
                        target_axis=target_rests[child].translation-dst.translation
                        if source_axis.length>.00001 and target_axis.length>.00001:
                            rotation=source_axis.rotation_difference(target_axis)
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
            if name=='MaidDress':
                hips=target_rests['mixamorig:Hips'].translation
                source_hip=rests['mixamorig:Hips'].translation
                leg_length=(target_rests['mixamorig:LeftLeg'].translation-target_rests['mixamorig:LeftUpLeg'].translation).length
                source_leg=(rests['mixamorig:LeftLeg'].translation-rests['mixamorig:LeftUpLeg'].translation).length
                # Keep the source skirt/apron silhouette and length relative
                # to the wearer's thighs; no nearest-leg surface projection.
                if p.z<source_hip.z:
                    lower=hips+(p-source_hip)*(leg_length/source_leg)
                    t=max(0,min(1,(source_hip.z-p.z)/.08))
                    position=position.lerp(lower,t*t*(3-2*t))
                # Fit existing panels to the body without replacing their cut.
                # A torso-centred radial cage preserves the panel's height
                # and angular order; sleeves use local surface clearance.
                neck=target_rests['mixamorig:Neck'].translation
                arm_weight=sum(w for k,w in valid.items() if k.endswith(('Arm','ForeArm','Shoulder')))
                if hips.z<position.z<neck.z:
                    nearest,normal,_,_=body_surface.find_nearest(position)
                    if arm_weight<.4:
                        t=max(0,min(1,(position.z-hips.z)/(neck.z-hips.z)))
                        center=hips.lerp(neck,t);center.z=position.z
                        radial=position-center;radial.z=0
                        if radial.length>.0001:
                            direction=radial.normalized()
                            hit=torso_surface.ray_cast(center+direction, -direction,1.0)[0]
                            if hit is not None and radial.length<(hit-center).length+.025:
                                position=center+direction*((hit-center).length+.025)
                                nearest=hit
                    elif nearest is not None and (position-nearest).dot(normal)<.028:
                        position=nearest+normal*.028
                    # Torso rays intentionally exclude arms; at the axilla a
                    # ray may miss. Still enforce clearance against the full
                    # body instead of leaving low-arm-weight sleeve corners
                    # embedded in the shoulder.
                    nearest,normal,_,_=body_surface.find_nearest(position)
                    if nearest is not None and (position-nearest).dot(normal)<.028:
                        position=nearest+normal*.028
                    # Use the local body's secondary/shoulder blending under
                    # fitted torso and sleeve panels, instead of mixing rigs.
                    if nearest is not None:
                        transferred={};total=0
                        for _,index,distance in foot_tree.find_n(nearest,4):
                            influence=1/max(distance,.002)**2;total+=influence
                            for g in body.data.vertices[index].groups:
                                k=body.vertex_groups[g.group].name;transferred[k]=transferred.get(k,0)+g.weight*influence
                        blend=1.0
                        valid={k:v*(1-blend) for k,v in valid.items()}
                        for k,w in transferred.items():valid[k]=valid.get(k,0)+w/total*blend
                # Original sleeve, neckline, apron and bow topology/UVs are
                # retained. Only skin weights below the hips gain leg motion.
                t=max(0,min(1,(hips.z-position.z)/(leg_length*.65)))
                radial=Vector((position.x-hips.x,position.y-hips.y,0))
                front=max(0,-radial.normalized().y) if radial.length>0 else 0
                amount=t*t*(3-2*t)*(.12+.76*front)
                left=target_rests['mixamorig:LeftUpLeg'].translation
                right=target_rests['mixamorig:RightUpLeg'].translation
                split=max(0,min(1,(position.x-right.x)/(left.x-right.x)))
                split=split*split*(3-2*split)
                valid={k:v*(1-amount) for k,v in valid.items()}
                for key,w in [('mixamorig:LeftUpLeg',split),('mixamorig:RightUpLeg',1-split)]:valid[key]=valid.get(key,0)+amount*w
            fitted.append(body.matrix_world.inverted()@position)
            skin.append(valid)
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(fitted,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
        if name=='MaidDress':
            obj['garment_kind']='skirt'
            obj['source_triangle_count']=sum(len(face)-2 for face in faces)
        obj.parent=target;obj.matrix_world=body.matrix_world.copy()
        for bone in target.data.bones:obj.vertex_groups.new(name=bone.name)
        for i,groups in enumerate(skin):
            total=sum(groups.values())
            for bone,w in groups.items():
                if w>.00001:obj.vertex_groups[bone].add([i],w/total,'REPLACE')
        uv=mesh.uv_layers.new(name='UVMap')
        colors=mesh.color_attributes.new(name='Cloth shading',type='FLOAT_COLOR',domain='CORNER')
        uv=mesh.uv_layers['UVMap']
        for polygon,coords in zip(mesh.polygons,uvs):
            polygon.use_smooth=True
            for index,coord in zip(polygon.loop_indices,coords):
                uv.data[index].uv=coord
                point=body.matrix_world@mesh.vertices[mesh.loops[index].vertex_index].co
                mobility=max(0,min(1,(hips.z-point.z)/(leg_length*.65))) if name=='MaidDress' else 0
                # White fabric is often painted on the same physical panel:
                # colour cannot be used as a separate collision-layer mask.
                front=max(0,min(1,(hips.y-point.y)/max(abs(point.x),.08))) if name=='MaidDress' else 0
                colors.data[index].color=(1,0,front,mobility*mobility*(3-2*mobility))
        # The fitting pass must not replace/drop original panels or UVs.
        assert len(mesh.polygons)==len(faces)
        for polygon,coords in zip(mesh.polygons,uvs):
            for index,coord in zip(polygon.loop_indices,coords):
                assert (mesh.uv_layers['UVMap'].data[index].uv-Vector(coord)).length<1e-6
        modifier=obj.modifiers.new('Shared character skeleton','ARMATURE');modifier.object=target
        mat=bpy.data.materials.new(name+' original texture');mat.use_nodes=True
        nodes=mat.node_tree.nodes;nodes.clear()
        output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission')
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(SOURCE/'Textures'/texture));tex.image.pack()
        mat.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color']);mat.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
        if gender=='male' and name=='MaidDress':
            # The lace/ribbon atlas contains transparent cutouts. Preserve
            # them in the editable material and exported glTF as well.
            bsdf=nodes.new('ShaderNodeBsdfPrincipled')
            bsdf.inputs['Roughness'].default_value=1
            mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
            mat.node_tree.links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
            mat.node_tree.links.new(bsdf.outputs[0],output.inputs['Surface'])
            mat.surface_render_method='DITHERED'
        mesh.materials.append(mat);objects.append(obj)
    # Fitted stockings cover the ankle too, avoiding overlap with the old boot-specific overlay.
    socks=body.copy();socks.data=body.data.copy();socks.name='MaidStockings';bpy.context.collection.objects.link(socks)
    bm=bmesh.new();bm.from_mesh(socks.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        dist=.00001,plane_co=socks.matrix_world.inverted()@Vector((0,0,.92)),
        plane_no=socks.matrix_world.to_3x3().transposed()@Vector((0,0,1)),clear_outer=True)
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
    hair=bpy.data.objects['Hair']
    hair_surface=BVHTree.FromPolygons([hair.matrix_world@v.co for v in hair.data.vertices],[list(p.vertices) for p in hair.data.polygons])
    crown=2.115 if gender=='female' else 2.185
    head=target_rests['mixamorig:Head'].translation
    skull=[body.matrix_world@v.co for v in body.data.vertices if (body.matrix_world@v.co).z>head.z+.07]
    band_center_y=(min(p.y for p in skull)+max(p.y for p in skull))*.5
    contour=[]
    for i in range(65):
        angle=-1.20+2.40*i/64;direction=Vector((math.sin(angle),0,math.cos(angle)))
        samples=[]
        for y in [band_center_y-.035,band_center_y,band_center_y+.035]:
            center=Vector((0,y,crown));hit,_,_,_=hair_surface.ray_cast(center+direction*.5,-direction,.5)
            samples.append((hit-center).length if hit is not None else 1/math.sqrt((math.sin(angle)/.163)**2+(math.cos(angle)/.225)**2))
        contour.append(sorted(samples)[1])
    contour=[sum(contour[max(0,i-3):min(65,i+4)])/len(contour[max(0,i-3):min(65,i+4)])+.009 for i in range(65)]
    for frill in [False,True]:
        start=len(verts);steps=64
        for i in range(steps+1):
            angle=-1.20+2.40*i/steps
            for edge in range(2):
                y=band_center_y-.0325+(.065*edge if not frill else -.008+math.sin(i/steps*math.tau*12)*.006*edge)
                center=Vector((0,y,crown))
                radius=contour[i]+(edge*.030 if frill else 0)
                if frill and edge:radius+=.003*math.sin(i/steps*math.tau*12)
                x=radius*math.sin(angle);z=center.z+radius*math.cos(angle)
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
        bsdf.inputs['Emission Color'].default_value=color;bsdf.inputs['Emission Strength'].default_value=.35
        mat.use_backface_culling=False;mesh.materials.append(mat)
    for polygon,index in zip(mesh.polygons,material_ids):polygon.material_index=index;polygon.use_smooth=True
    objects.append(headpiece)
    bpy.ops.object.select_all(action='DESELECT');target.select_set(True)
    for obj in objects:obj.select_set(True)
    out=art_path(f'characters/equipment/maid/{gender}');out.mkdir(parents=True,exist_ok=True)
    (out/'editable').mkdir(exist_ok=True);(out/'editable/.gdignore').touch()
    # Editable outfit file contains the reference body as well, runtime GLB exports selected garments only.
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'editable/maid.blend'))
    bpy.ops.export_scene.gltf(filepath=str(out/'outfit.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True,export_vertex_color='ACTIVE',export_extras=True)
    (out/'License.txt').write_bytes((SOURCE/'License.txt').read_bytes())
    (out/'SOURCE.txt').write_text('Garments extracted from user-supplied Maid.zip (bundled CC0 license).\nAdapted to the shared '+gender+' rig; no source body, face or hair in outfit.glb.\n',encoding='utf-8')
    print('MAID_EXPORTED',gender,flush=True)
