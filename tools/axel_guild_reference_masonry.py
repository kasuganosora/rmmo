"""Restore scanned limestone relief without altering the original scan or topology."""
from pathlib import Path
import bpy
from io_scene_gltf2.blender.com.material_helpers import create_settings_group

LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials/walls/stone_tiles_facade')

def apply():
    mat=bpy.data.materials['Guild PBR | exterior limestone']
    normal_nodes=[n for n in mat.node_tree.nodes if n.type=='NORMAL_MAP']
    assert len(normal_nodes)==1
    old=float(normal_nodes[0].inputs['Strength'].default_value)
    normal_nodes[0].inputs['Strength'].default_value=1.05
    p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    assert p.inputs['Metallic'].default_value==0
    # The underlying scanned roughness is already 0.79–0.91; increasing a
    # constant cannot repair a normal map that was attenuated to 45 percent.
    image=bpy.data.images.load(str(LIB/'ao.png'),check_existing=True)
    image.colorspace_settings.name='Non-Color';image.pack()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    group=bpy.data.node_groups.get('glTF Material Output') or create_settings_group('glTF Material Output')
    out=mat.node_tree.nodes.new('ShaderNodeGroup');out.node_tree=group
    mat.node_tree.links.new(tex.outputs['Color'],out.inputs['Occlusion'])
    mat['reference_revision']='20261013'
    mat['reference_material_design']='Original owned 2K scan, normal attenuation removed and scanned cavity occlusion connected; no new geometry displacement'
    changed=set();objects=[];reprojected=0;seen=set()
    for obj in bpy.data.objects:
        if obj.type!='MESH' or mat not in obj.data.materials[:]:continue
        # Original frontage mapping was only planar: narrow dormer return
        # faces collapsed to a stripe. Give each wall-facing plane actual metre
        # coordinates while keeping vertical masonry courses horizontal.
        if obj.data.as_pointer() not in seen:
            seen.add(obj.data.as_pointer())
            uv=obj.data.uv_layers.active or obj.data.uv_layers.new(name='LimestoneMetreUV')
            slots={i for i,m in enumerate(obj.data.materials) if m==mat}
            matrix=obj.matrix_world;normal_matrix=matrix.to_3x3().inverted().transposed()
            for face in obj.data.polygons:
                if face.material_index not in slots:continue
                normal=(normal_matrix@face.normal).normalized()
                for li in face.loop_indices:
                    co=matrix@obj.data.vertices[obj.data.loops[li].vertex_index].co
                    if abs(normal.z)>.85:u,v=co.x,co.y
                    elif abs(normal.x)>abs(normal.y):u,v=co.y,co.z
                    else:u,v=co.x,co.z
                    uv.data[li].uv=(u/2,v/2)
                reprojected+=1
        objects.append(obj.name);root=obj
        while root:
            if root.get('asset_id'):changed.add(root['asset_id'])
            root=root.parent
    return {'material':mat.name,'normal_before':old,'normal_after':1.05,
            'ao_source':str(LIB/'ao.png'),'unchanged':['2K albedo/normal/roughness scan','2 by 2 metre mapping','nonmetallic stone','wall geometry and collision'],
            'changed_asset_ids':sorted(changed),'affected_objects':objects,
            'metre_reprojected_faces':reprojected,
            'limitation':'Normal/AO are surface shading, not silhouette displacement; inspect raking-light close views before accepting.'}
