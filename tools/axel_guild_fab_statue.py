"""User-approved Fab Knight Statue, neutral whitebox adaptation; no textures."""
from pathlib import Path
import bpy
from mathutils import Vector

ASSET_DIR=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild/fab_knight_statue_v1'
SOURCE=ASSET_DIR/'source/Knight Statue.blend'
URL='https://www.fab.com/listings/f68207c8-d10d-4658-ac46-536c18645ac8'

def build_knight_statue(collection,material,height=3.15):
    with bpy.data.libraries.load(str(SOURCE),link=False) as (src,dst):
        assert all(n in src.objects for n in ['Knight_Statue_Sword','Sword'])
        dst.objects=['Knight_Statue_Sword','Sword']
    parts=list(dst.objects)
    for obj in parts:collection.objects.link(obj)
    bpy.context.view_layer.update()
    coords=[obj.matrix_world@v.co for obj in parts for v in obj.data.vertices]
    lo=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    factor=height/(hi.z-lo.z)
    center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    root=bpy.data.objects.new('Guild_Fab_Knight_Statue',None);collection.objects.link(root)
    root['asset_id']='guild_fab_knight_statue';root['independent_prop']=True
    root['whitebox_only']=True;root['fab_listing_url']=URL
    root['asset_source']='../fab_knight_statue_v1/guild_knight_statue_whitebox.glb'
    root['author']='Infinity3DGame';root['user_approved']='2026-10-08'
    root['height_m']=height;root['front_axis']='-Y'
    for obj,label in zip(parts,['Body','Sword']):
        world=obj.matrix_world.copy()
        for vertex in obj.data.vertices:vertex.co=(world@vertex.co-center)*factor
        obj.matrix_world.identity();obj.parent=root
        obj.name='Fab_Knight_Statue_'+label
        obj.data.materials.clear();obj.data.materials.append(material)
        obj['replaceable_group']='statue_body' if label=='Body' else 'statue_sword'
        obj['whitebox_only']=True;obj['collision_review']=True
        obj.data.calc_loop_triangles()
    return root,parts,{'source_bounds':[list(lo),list(hi)],'uniform_scale':factor,
                       'height_m':height,'dimensions_m':list((hi-lo)*factor),'triangles':sum(len(o.data.loop_triangles) for o in parts)}

if __name__=='__main__':
    import hashlib,json
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mat=bpy.data.materials.new('WB knight neutral clay');mat.diffuse_color=(.55,.57,.55,1);mat.use_nodes=True
    bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bsdf.inputs['Base Color'].default_value=(.55,.57,.55,1);bsdf.inputs['Roughness'].default_value=.83
    root,parts,info=build_knight_statue(bpy.context.scene.collection,mat)
    for obj in parts:obj.data.calc_loop_triangles()
    info['triangles']=sum(len(o.data.loop_triangles) for o in parts)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root]+parts:obj.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET_DIR/'guild_knight_statue_whitebox.blend'))
    bpy.ops.export_scene.gltf(filepath=str(ASSET_DIR/'guild_knight_statue_whitebox.glb'),export_format='GLB',use_selection=True,export_extras=True)
    info.update({'listing_url':URL,'author':'Infinity3DGame','license':'Fab Standard License (listing UI)',
                 'owned_library_verified':'2026-10-08','user_approval':'2026-10-08 可以使用',
                 'archive_sha256':hashlib.sha256((ASSET_DIR/'source/knight_statue_blender.zip').read_bytes()).hexdigest(),
                 'changes':['Sword variant selected','Uniform scale and recentered origin','Neutral clay material; no textures'],
                 'optimization':'Retain all 3274 triangles; already economical; no decimation or silhouette loss.',
                 'deviations':['User-approved stylized full helmet/shoulder armor differs from exposed-head animation statue.'],
                 'runtime_catalog_published':False})
    (ASSET_DIR/'provenance.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
