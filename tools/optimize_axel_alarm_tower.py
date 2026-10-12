"""Build a derived game asset; keep the full editable v3 source untouched."""
import bpy, sys, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

BASE=Path('D:/code/rmmo/review_artifacts')
SOURCE=BASE/'alarm_tower_materials_v3_20261011/guild_and_alarm_tower_materials.blend'
OUT=BASE/'alarm_tower_game_20261011';OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
for col in bpy.data.collections:col.hide_viewport=False
bpy.context.view_layer.update()
source=[o for o in bpy.data.objects if o.get('semantic_group')=='70_Alarm_Tower_Context']
meshes=[o for o in source if o.type=='MESH']
def tris(mesh):return sum(len(p.vertices)-2 for p in mesh.polygons)
def digest(obj):
    return hashlib.sha256(repr(([tuple(v.co) for v in obj.data.vertices],
        [tuple(p.vertices) for p in obj.data.polygons])).encode()).hexdigest()
before={o.name:digest(o) for o in meshes}
scene=bpy.data.scenes.new('Alarm tower | game LODs');bpy.context.window.scene=scene
root=bpy.data.objects.new('guild_alarm_tower_game',None);scene.collection.objects.link(root)
root['asset_id']='guild_alarm_tower';root['source_master']=str(SOURCE)
root['project_supplementary_design']=True
root['lod_distances_m']=[0.,40.,110.]
root['interior_traversal_complete']=False
roots=[o for o in source if o.type=='EMPTY' and o.get('asset_id')]
shaft=next(o for o in meshes if o.name=='Alarm tower context shaft')
groups=[('shaft',Matrix.Translation((23,42,0)),[shaft])]
for r in roots:groups.append((r.name,r.matrix_world.copy(),[o for o in r.children_recursive if o.type=='MESH']))
reduced={};joined={};instances=[];stats=[]
for level,ratio in enumerate([.65,.28,.12]):
    level_tri=0;level_surfaces=0;level_nodes=0
    for name,pose,parts in groups:
        part_root=next((o for o in root.children if o.get('source_part')==name),None)
        if part_root is None:
            part_root=bpy.data.objects.new('Part | '+name,None);scene.collection.objects.link(part_root)
            part_root.parent=root;part_root.matrix_local=Matrix.Translation((-23,-42,0))@pose
            part_root['source_part']=name;part_root['independent_prop']=True
        key=(level,tuple((o.data.as_pointer(),tuple(round(x,4) for row in pose.inverted()@o.matrix_world for x in row)) for o in parts))
        if key not in joined:
            copies=[]
            for original in parts:
                reduction_key=(level,original.data.as_pointer())
                if reduction_key not in reduced:
                    data=original.data.copy()
                    tmp=bpy.data.objects.new('Reduction work',data);scene.collection.objects.link(tmp)
                    bpy.context.view_layer.update()
                    n=original.name.lower()
                    # Thin brass tubes dominate; retain masonry openings and roof exactly.
                    metal=original.get('material_role') in ['aged golden brass','brass edges','brass horn interior','dark brass fixings']
                    if metal and tris(data)>150:
                        bpy.ops.object.select_all(action='DESELECT');tmp.select_set(True);bpy.context.view_layer.objects.active=tmp
                        mod=tmp.modifiers.new('Conservative brass LOD', 'DECIMATE');mod.ratio=ratio
                        mod.use_collapse_triangulate=True
                        bpy.ops.object.modifier_apply(modifier=mod.name)
                    reduced[reduction_key]=tmp.data
                    bpy.data.objects.remove(tmp,do_unlink=True)
                # Blender join mutates its active mesh: never lend it cached data.
                obj=bpy.data.objects.new('Derived | '+original.name,reduced[reduction_key].copy())
                scene.collection.objects.link(obj);obj.matrix_world=pose.inverted()@original.matrix_world
                copies.append(obj)
            bpy.context.view_layer.update()
            bpy.ops.object.select_all(action='DESELECT')
            for obj in copies:obj.select_set(True)
            bpy.context.view_layer.objects.active=copies[0]
            # Join only within one semantic component. Source remains fully editable.
            if len(copies)>1:bpy.ops.object.join()
            joined_obj=bpy.context.object
            joined_obj.data=joined_obj.data.copy()
            bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            joined[key]=joined_obj.data
            bpy.data.objects.remove(joined_obj,do_unlink=True)
        mesh=joined[key]
        obj=bpy.data.objects.new(name+' | LOD'+str(level),mesh);scene.collection.objects.link(obj)
        obj.parent=part_root;obj.matrix_basis=Matrix.Identity(4)
        obj['lod_level']=level;obj['source_part']=name
        # All LODs use the same tower-centred bound to switch in one frame.
        center=pose.inverted()@Vector((23,42,16.685))
        bounds=[center.x-6.2,center.z-16.685,-center.y-6.2,12.4,33.37,12.4]
        obj['rmmo_visibility_range']={'begin':[0.,40.,110.][level],'end':[40.,110.,0.][level],'bounds':bounds}
        # One persistent physical representation, independent of rendered LOD.
        obj['rmmo_collision']='block' if level==0 and name in ['shaft','guild_alarm_crown','guild_alarm_conical_roof'] else 'none'
        if name=='shaft':obj['shooting_slit_count']=16
        instances.append(obj);level_tri+=tris(mesh);level_surfaces+=len(mesh.materials);level_nodes+=1
    stats.append({'level':level,'triangles':level_tri,'surfaces':level_surfaces,'mesh_nodes':level_nodes,'begin_m':[0,40,110][level],'end_m':[40,110,0][level]})
    assert level_tri <= sum(tris(o.data) for o in meshes), ('unexpected duplicated geometry',level_tri)
assert before=={o.name:digest(o) for o in meshes}
bpy.context.view_layer.update()
# Four brass materials use byte-identical grain normal maps. Share that image
# without resampling, changing material colours or lowering texture resolution.
image_cache={};image_aliases=[]
for material in {m for obj in instances for m in obj.data.materials}:
    if not material or not material.use_nodes:continue
    for node in material.node_tree.nodes:
        if node.type!='TEX_IMAGE' or not node.image or not node.image.packed_file:continue
        image=node.image
        key=(hashlib.sha256(image.packed_file.data).hexdigest(),image.colorspace_settings.name)
        if key in image_cache and image_cache[key]!=image:
            image_aliases.append({'from':image.name,'to':image_cache[key].name})
            node.image=image_cache[key]
        else:image_cache[key]=image
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'guild_alarm_tower_game.glb'),export_format='GLB',use_selection=True,
    export_extras=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False)
for obj in instances:obj.hide_render=obj['lod_level']!=0;obj.hide_set(obj['lod_level']!=0)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guild_alarm_tower_game.blend'),compress=True)
report={'source':str(SOURCE),'source_unchanged':True,'master_triangles':sum(tris(o.data) for o in meshes),
 'master_mesh_nodes':len(meshes),'master_surfaces':sum(len(o.data.materials) for o in meshes),
 'lods':stats,'game_mesh_data_count':len({o.data.as_pointer() for o in instances}),
 'identical_image_aliases':image_aliases,
 'notes':['Editable source parts untouched; batching only in derived game asset, per independent part.',
          'All masonry and 16 shooting slits retained exactly at every LOD; only brass decimated.',
          'Original 2K masonry/roof and 1K brass PBR images retained pending measured quality comparison.',
          'Distances provisional until render/transition review. No editor publication or user map change.']}
(OUT/'optimization_build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('ALARM_GAME_BUILT',json.dumps(report),flush=True)
