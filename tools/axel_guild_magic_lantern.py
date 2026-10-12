"""Four glass sheets enclosing a floating warm-white diamond-shaped crystal."""
import bpy
import bmesh
WARM_WHITE=(1.0,.86,.69)

def magic_materials():
    glass=bpy.data.materials.get('Guild clear lantern glass sheets')
    if glass is None:
        glass=bpy.data.materials.new('Guild clear lantern glass sheets');glass.use_nodes=True
        p=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Base Color'].default_value=(.92,.97,1,1)
        p.inputs['Roughness'].default_value=.12;p.inputs['Alpha'].default_value=.14;p.inputs['IOR'].default_value=1.45
        glass.diffuse_color=(.92,.97,1,.14);glass.surface_render_method='DITHERED'
    stone=bpy.data.materials.get('Guild warm white floating magic stone')
    if stone is None:
        stone=bpy.data.materials.new('Guild warm white floating magic stone');stone.use_nodes=True
        p=next(n for n in stone.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Base Color'].default_value=(.72,.65,.48,1);p.inputs['Roughness'].default_value=.24
        p.inputs['Emission Color'].default_value=(*WARM_WHITE,1);p.inputs['Emission Strength'].default_value=3.0
    return glass,stone

def build_magic_core(root,collection,glass,stone):
    parts=[]
    def mesh(label,vertices,faces,material):
        data=bpy.data.meshes.new(root.name+'_'+label);data.from_pydata(vertices,[],faces);data.update()
        bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
        obj=bpy.data.objects.new(data.name,data);collection.objects.link(obj);obj.parent=root
        data.materials.append(material);uv=data.uv_layers.new(name='FurnitureUV')
        for p in data.polygons:
            for li in p.loop_indices:
                v=data.vertices[data.loops[li].vertex_index].co;uv.data[li].uv=(v.x+v.y,v.z)
        obj['prop_part']=label;obj['collision_review']=False;obj['independent_prop']=True
        obj['structural_wall']=False;obj['replaceable_group']=label;parts.append(obj)
        return obj
    # Closed 4mm sheets, leaving air in the lantern rather than solid glass.
    for side in range(4):
        vs=[]
        for thickness in [0,.004]:
            for z,w in [(2.60,.136),(3.045,.222)]:
                for x in [-w+.008,w-.008]:
                    a,b=x,-w+thickness
                    for _ in range(side):a,b=-b,a
                    vs.append((a,b,z))
        obj=mesh('Glass_sheet_'+str(side+1),vs,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],glass)
        obj['glass_thickness_m']=.004
    center=2.825
    obj=mesh('Floating_magic_stone',[(0,0,center+.15),(.068,0,center),(0,.068,center),(-.068,0,center),(0,-.068,center),(0,0,center-.15)],
             [(0,1,2),(0,2,3),(0,3,4),(0,4,1),(5,2,1),(5,3,2),(5,4,3),(5,1,4)],stone)
    obj['emissive_part']=True;obj['floating']=True
    root['light_socket_blender']=[0,0,center];root['proposed_light_color_linear']=list(WARM_WHITE)
    root['light_source']='floating_diamond_magic_stone';root['glass_panels']=4;root['light_runtime_connected']=False
    return parts

def add_preview_light(root,collection):
    data=bpy.data.lights.new(root.name+'_Magic_light','POINT')
    data.energy=8;data.color=WARM_WHITE;data.shadow_soft_size=.045
    obj=bpy.data.objects.new(data.name,data);collection.objects.link(obj);obj.parent=root
    obj.location=(0,0,2.825);obj['preview_light']=True
    return obj
