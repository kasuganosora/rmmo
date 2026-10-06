"""Derive adult male and fitted starter clothing from the supplied female mesh.

Blender background script. No downloaded models and no raster repainting. Geometry,
armature rest positions and all expression shapes receive the same deformation.
"""
import bpy,bmesh,math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
from mathutils.kdtree import KDTree
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

def refresh_normals(obj):
    # UV seams duplicate vertices. Smooth their normals together without
    # welding geometry, changing skin weights or destroying the UV layout.
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True);bpy.context.view_layer.objects.active=obj
    if obj.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for polygon in obj.data.polygons:polygon.use_smooth=True
    obj.data.update()
    sums={}
    keys=[tuple(round(c,5) for c in v.co) for v in obj.data.vertices]
    for v,key in zip(obj.data.vertices,keys):sums[key]=sums.get(key,Vector())+v.normal
    obj.data.normals_split_custom_set_from_vertices([sums[key].normalized() for key in keys])

def refine_joint_weights(obj,rig,refine_chest=True):
    # The source's auto-weights have abrupt islands at the knees and carry
    # shoulder motion into the lateral chest. Fit these local areas to the
    # existing joints; all other weights and the skeleton remain intact.
    def assign(vertex,weights):
        for group_index in [g.group for g in vertex.groups]:obj.vertex_groups[group_index].remove([vertex.index])
        for name,weight in weights.items():
            if weight>0.00001:obj.vertex_groups[name].add([vertex.index],weight,'REPLACE')
    for v in obj.data.vertices:
        p=obj.matrix_world@v.co
        side='Left' if p.x>0 else 'Right'
        lower='mixamorig:'+side+'Leg';upper='mixamorig:'+side+'UpLeg'
        knee=(rig.matrix_world@rig.data.bones[lower].head_local).z
        if abs(p.z-knee)<.26 and abs(p.x)<.30:
            t=smoothstep(knee-.14,knee+.14,p.z)
            blend=1-smoothstep(.16,.26,abs(p.z-knee))
            weights={obj.vertex_groups[g.group].name:g.weight*(1-blend) for g in v.groups}
            for name,w in [(upper,t),(lower,1-t)]:weights[name]=weights.get(name,0)+w*blend
            total=sum(weights.values())
            assign(v,{name:w/total for name,w in weights.items()})

        if refine_chest and 1.53<p.z<1.94 and abs(p.x)<.32:
            blend=(1-smoothstep(.24,.32,abs(p.x)))*(1-smoothstep(1.84,1.94,p.z))*smoothstep(1.53,1.60,p.z)
            if blend<=0:continue
            weights={obj.vertex_groups[g.group].name:g.weight*(1-blend) for g in v.groups}
            t=smoothstep(1.60,1.83,p.z)
            for name,w in [('mixamorig:Spine1',1-t),('mixamorig:Spine2',t)]:weights[name]=weights.get(name,0)+w*blend
            total=sum(weights.values())
            assign(v,{name:w/total for name,w in weights.items()})

def relax_male_chest(obj):
    # Flattening the old breast surface can fold its underside triangles.
    # Relax that patch in all axes with a pinned falloff into the rib cage.
    bm=bmesh.new();bm.from_mesh(obj.data)
    influence={}
    for v in bm.verts:
        p=obj.matrix_world@v.co
        weight=smoothstep(1.48,1.60,p.z)*(1-smoothstep(1.85,1.98,p.z))*(1-smoothstep(.24,.34,abs(p.x)))*(1-smoothstep(-.025,.035,p.y))
        if weight>0:influence[v]=weight
    for iteration in range(18):
        updates={}
        for v,weight in influence.items():
            neighbors=[e.other_vert(v).co for e in v.link_edges]
            if neighbors:updates[v]=v.co.lerp(sum(neighbors,Vector())/len(neighbors),.45*weight)
        for v,co in updates.items():v.co=co
    bm.to_mesh(obj.data);bm.free()

def relax_male_front_pelvis(obj):
    bm=bmesh.new();bm.from_mesh(obj.data)
    influence={}
    for v in bm.verts:
        p=obj.matrix_world@v.co
        weight=smoothstep(1.12,1.23,p.z)*(1-smoothstep(1.45,1.64,p.z))*(1-smoothstep(.12,.23,abs(p.x)))*(1-smoothstep(-.025,.015,p.y))
        if weight>0:influence[v]=weight
    for iteration in range(10):
        updates={}
        for v,weight in influence.items():
            neighbors=[e.other_vert(v).co for e in v.link_edges]
            if neighbors:updates[v]=v.co.lerp(sum(neighbors,Vector())/len(neighbors),.4*weight)
        for v,co in updates.items():v.co=co
    bm.to_mesh(obj.data);bm.free()
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
        if kind=='Body':
            # Keep a quiet, shallow front contour under shorts/trousers.
            # Derived garments inherit this shape rather than inflating it.
            crotch=smoothstep(1.08,1.19,z)*(1-smoothstep(1.35,1.58,z))*(1-smoothstep(.07,.20,abs(x)))
            y+=(max(y,-.075)-y)*crotch*.85
        if kind in ['Body','Clothing1']:
            # A continuous rib-cage surface, rather than flattening only the
            # middle of each breast (which leaves an under-bust shelf).
            front=smoothstep(.005,.065,-y)
            height=smoothstep(1.39,1.55,z)*(1-smoothstep(1.84,1.96,z))
            side=1-smoothstep(.24,.34,abs(x))
            depth=.103+.008*math.exp(-((z-1.72)/.20)**2)
            profile=-depth*math.sqrt(max(.08,1-(x/.30)**2))
            if kind=='Clothing1':profile-=.012
            y+=(profile-y)*front*height*side

    x*=width
    # Slightly longer legs/torso, leaving the facial height almost unchanged.
    z+=.065*smoothstep(.12,1.90,z)
    return Vector((x,y,z))

def refine_female_surface(obj):
    """Small anatomical transitions, shared by the body and fitted top.

    Preserve scale, topology, skeleton and the authored face. Lower-pole
    fullness and the hip/thigh transition should remain curved in side view.
    This is offline source sculpting; runtime clothing never uses these values.
    """
    inverse=obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        p=obj.matrix_world@vertex.co;x,y,z=p
        breast=math.exp(-((abs(x)-.095)/.105)**4)*smoothstep(.055,.115,-y)
        upper=math.exp(-((z-1.785)/.055)**2)
        lower=math.exp(-((z-1.665)/.062)**2)
        p.y+=breast*(.006*upper-.003*lower)
        p.z-=breast*.005*math.exp(-((z-1.715)/.095)**4)
        hip=math.exp(-((abs(x)-.095)/.105)**4-((z-1.26)/.13)**4)*smoothstep(.055,.11,y)
        p.y+=hip*.005
        vertex.co=inverse@p
    # Recompute across coincident UV seam vertices: the old custom normals
    # left polygon-sized bands under the bust and along the gluteal fold.
    refresh_normals(obj)

def refine_female_front_pelvis(obj):
    # Remove the inherited forward pouch before deriving either underwear or
    # trousers. Preserve the rear pelvis, thigh volume and skeleton positions.
    inverse=obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        p=obj.matrix_world@vertex.co
        weight=smoothstep(1.07,1.19,p.z)*(1-smoothstep(1.40,1.58,p.z))
        weight*=1-smoothstep(.14,.23,abs(p.x))
        weight*=1-smoothstep(-.025,.015,p.y)
        profile=-.067-.060*smoothstep(1.18,1.50,p.z)
        p.y+=max(0,profile-p.y)*weight
        vertex.co=inverse@p
    refresh_normals(obj)

def cut_base_curve(obj,height,keep_above):
    # Flatten the desired curved hem for an exact edge cut, then restore it.
    bm=bmesh.new();bm.from_mesh(obj.data);inverse=obj.matrix_world.inverted()
    for v in bm.verts:
        p=obj.matrix_world@v.co;p.z-=height(p.x,p.y);v.co=p
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,
        plane_co=Vector(),plane_no=Vector((0,0,1)),clear_inner=keep_above,clear_outer=not keep_above)
    for v in bm.verts:
        p=v.co.copy();p.z+=height(p.x,p.y);v.co=inverse@p
    bm.to_mesh(obj.data);bm.free()

def bra_top(x,y):
    front=1-smoothstep(-.015,.04,y)
    cup=1.735+.085*math.exp(-((abs(x)-.11)/.065)**4)
    return 1.70*(1-front)+cup*front

def underwear_material(gender):
    if gender=='male':return plain_material('White plain cotton',(.86,.845,.82))
    existing=bpy.data.materials.get('White lace with opaque lining')
    if existing:return existing
    import numpy as np
    size=512;yy,xx=np.mgrid[:size,:size].astype(float)
    x=(xx+.5)/size-.5;y=(yy+.5)/size-.5;r=np.sqrt(x*x+y*y);angle=np.arctan2(y,x)
    def line(distance,width):
        t=np.clip((distance-width)/.008,0,1);return 1-t*t*(3-2*t)
    thread=np.maximum(np.maximum(line(abs(r-(.255+.055*np.cos(angle*6))),.012),line(abs(r-.07),.010)),line(abs(abs(x)-abs(y)),.006)*.55)
    pixels=np.ones((size,size,4));pixels[:,:,:3]=np.array([.83,.82,.80])+thread[:,:,None]*np.array([.13,.135,.14])
    image=bpy.data.images.new('White lace embroidery',width=size,height=size);image.pixels.foreach_set(pixels.astype(np.float32).ravel())
    image.filepath_raw=str(art_path('characters/materials/underwear_lace.png'));Path(image.filepath_raw).parent.mkdir(parents=True,exist_ok=True);image.file_format='PNG';image.save();image.pack()
    mat=plain_material('White lace with opaque lining',(.83,.82,.80));nodes=mat.node_tree.nodes;links=mat.node_tree.links
    bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');bsdf.inputs['Roughness'].default_value=.8
    uv=nodes.new('ShaderNodeTexCoord');mapping=nodes.new('ShaderNodeMapping');mapping.inputs['Scale'].default_value=(40,40,1)
    tex=nodes.new('ShaderNodeTexImage');tex.image=image
    links.new(uv.outputs['UV'],mapping.inputs['Vector']);links.new(mapping.outputs['Vector'],tex.inputs['Vector']);links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    return mat

for gender in (['male'] if '--male-only' in sys.argv else ['female'] if '--female-only' in sys.argv else ['female','male']):
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
        for reshaped in [body,shirt]:relax_male_chest(reshaped)
        relax_male_front_pelvis(body)
        for reshaped in [body,shirt,bpy.data.objects.get('Stockings')]:
            if reshaped:refine_joint_weights(reshaped,rig)
        # Imported split normals describe the old feminine form. Recompute
        # only deformed body/garment normals; preserve the face's authored
        # normals and all 57 expression shapes.
        for reshaped in [body,shirt]:refresh_normals(reshaped)
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

    if gender=='female':
        for reshaped in [body,bpy.data.objects.get('Clothing1')]:
            if reshaped:refine_female_surface(reshaped)
        refine_female_front_pelvis(body)
        apply_material(body,plain_material('Female ivory skin',(.91,.77,.66)))
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        for reshaped in [body,bpy.data.objects.get('Stockings')]:
            if reshaped:refine_joint_weights(reshaped,rig,refine_chest=False)

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
    if gender=='male':refresh_normals(trousers)
    apply_material(trousers,plain_material('Traveller charcoal trousers',(.08,.105,.13)))

    # Tuck the lower shirt into the waistband and share the underlying waist
    # deformation there; a torso-only hem otherwise cuts through a seated belt.
    waist_top=1.48 if gender=='female' else 1.51
    shirt=bpy.data.objects['Clothing1']
    tree=KDTree(len(body.data.vertices))
    for v in body.data.vertices:tree.insert(body.matrix_world@v.co,v.index)
    tree.balance()
    for v in shirt.data.vertices:
        p=shirt.matrix_world@v.co
        blend=1-smoothstep(waist_top,waist_top+.08,p.z)
        if blend<=0:continue
        samples=tree.find_n(p,4);weights={};total=0
        surface=Vector()
        for point,index,distance in samples:
            w=1/max(distance,.002)**2;total+=w;surface+=point*w
            for group in body.data.vertices[index].groups:
                name=body.vertex_groups[group.group].name
                weights[name]=weights.get(name,0)+group.weight*w
        surface/=total
        target=Vector((surface.x*.995,surface.y*.995,p.z))
        v.co=shirt.matrix_world.inverted()@p.lerp(target,blend)
        merged={shirt.vertex_groups[g.group].name:g.weight*(1-blend) for g in v.groups}
        for name,w in weights.items():merged[name]=merged.get(name,0)+w/total*blend
        for index in [g.group for g in v.groups]:shirt.vertex_groups[index].remove([v.index])
        for name,w in merged.items():
            group=shirt.vertex_groups.get(name) or shirt.vertex_groups.new(name=name)
            if w>.00001:group.add([v.index],w,'REPLACE')

    # Fit the belt to the actual waistband, including its blended skin weights.
    # A rigid ellipse on Hips separates from the waist when the torso bends.
    belt=trousers.copy();belt.data=trousers.data.copy();belt.name='Belt'
    bpy.context.collection.objects.link(belt)
    waist_top=1.48 if gender=='female' else 1.51
    slice_height(belt,waist_top-.05,waist_top-.003)
    bm=bmesh.new();bm.from_mesh(belt.data);bm.normal_update()
    for v in bm.verts:v.co+=v.normal*.004
    # Split a narrow front buckle patch so it follows the same surface and
    # skinning, rather than floating as a separate rigid box.
    inverse=belt.matrix_world.inverted()
    for x in [-.026,.026]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
            dist=.000001,plane_co=inverse@Vector((x,0,0)),
            plane_no=belt.matrix_world.to_3x3().transposed()@Vector((1,0,0)))
    bm.to_mesh(belt.data);bm.free()
    apply_material(belt,plain_material('Fitted leather belt',(.07,.033,.016)))
    belt.data.materials.append(plain_material('Belt brass buckle',(.55,.36,.12)))
    for face in belt.data.polygons:
        p=belt.matrix_world@face.center
        if abs(p.x)<.026 and p.y<-.02:face.material_index=1
    refresh_normals(belt)

    # Minimal base underwear is a separate, always-on safety layer of the model.
    # It keeps the preview useful for inspecting anatomy without exposed details.
    layers=[('BaseBottom',1.16 if gender=='female' else 1.18,1.405 if gender=='female' else 1.435)]
    if gender=='female':layers.append(('BaseTop',1.615,1.84))
    for name,low,high in layers:
        base=body.copy();base.data=body.data.copy();base.name=name;bpy.context.collection.objects.link(base)
        slice_height(base,low,high)
        if name=='BaseBottom':
            # Briefs: curved leg openings, an intact crotch and full rear
            # coverage. The higher side opening removes the old shorts legs.
            def leg_opening(x,y):
                rear=smoothstep(-.015,.055,y)
                rise=(.20 if gender=='female' else .19)*(1-rear)+.15*rear
                return low+rise*smoothstep(0,.18,abs(x))
            cut_base_curve(base,leg_opening,True)
        else:cut_base_curve(base,bra_top,False)
        bm=bmesh.new();bm.from_mesh(base.data)
        if name=='BaseTop':
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if abs((base.matrix_world@f.calc_center_median()).x)>.225],context='FACES')
        for v in bm.verts:v.co+=v.normal*.0025
        bm.to_mesh(base.data);bm.free()
        if name=='BaseTop':
            # Cut fitted shoulder straps from the same weighted surface,
            # preserving body proportions and the shared armature modifier.
            for side in [-1,1]:
                strap=body.copy();strap.data=body.data.copy();bpy.context.collection.objects.link(strap)
                slice_height(strap,1.69,1.97)
                sb=bmesh.new();sb.from_mesh(strap.data)
                for limit,normal in [(side*.14-.009,Vector((-1,0,0))),(side*.14+.009,Vector((1,0,0)))]:
                    bmesh.ops.bisect_plane(sb,geom=list(sb.verts)+list(sb.edges)+list(sb.faces),dist=.000001,
                        plane_co=strap.matrix_world.inverted()@Vector((limit,0,0)),plane_no=normal,clear_outer=True)
                sb.to_mesh(strap.data);sb.free();cut_base_curve(strap,lambda x,y:bra_top(x,y)-.006,True)
                for vertex in strap.data.vertices:vertex.co+=vertex.normal*.004
                bpy.ops.object.select_all(action='DESELECT');base.select_set(True);strap.select_set(True);bpy.context.view_layer.objects.active=base;bpy.ops.object.join()
        apply_material(base,underwear_material(gender))
        refresh_normals(base)

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
