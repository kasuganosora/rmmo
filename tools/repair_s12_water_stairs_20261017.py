"""Blender: preserve four original stone tiers; close through-joints with a real stepped mortar bed."""
import bpy, bmesh, json, hashlib, math, sys, shutil, argparse
from pathlib import Path
from mathutils import Vector

BASE=Path('D:/code/rmmo_runtime/art_sources/s12_water_stairs_repair_20261017')
parser=argparse.ArgumentParser();parser.add_argument('--version',default='v2')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=BASE/args.version;OUT.mkdir(parents=True,exist_ok=True)
SOURCE=Path('D:/code/rmmo_runtime/packs/default/assets/0711766e3b6adb7a4f3916888e5497e6732faea878bb7eb19ea1be1ebac5e543.glb')
NAME='s12_landing_steps_4'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(SOURCE)==SOURCE.stem
assert not (OUT/(NAME+'.glb')).exists()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system='METRIC'
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
stone=next(o for o in bpy.context.scene.objects if o.type=='MESH')
stone.name=NAME+'_original_stones';before=[tuple(stone.matrix_world@v.co) for v in stone.data.vertices]
inputs={str(SOURCE):sha(SOURCE)}
color=Path('D:/code/rmmo_runtime/art_sources/s12_stone_materials_20261015/v2/materials/worked_limestone_albedo.png')
scan=Path('D:/code/rmmo_runtime/packs/default/assets/materials/terrain/beach_cliff')
mat=bpy.data.materials.new('S12 weathered worked limestone | existing reviewed maps');mat.use_nodes=True
bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1
for socket,path in [('Base Color',color),('Normal',scan/'normal.png'),('Roughness',scan/'roughness.png')]:
    inputs[str(path)]=sha(path);im=bpy.data.images.load(str(path),check_existing=False)
    im.colorspace_settings.name='sRGB' if socket=='Base Color' else 'Non-Color';im.pack()
    node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im
    if socket=='Normal':
        normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.24
        mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    else:mat.node_tree.links.new(node.outputs['Color'],bs.inputs[socket])
stone.data.materials.clear();stone.data.materials.append(mat)
for p in stone.data.polygons:p.material_index=0
stone['rmmo_collision']='walk'
stone['repair_note']='Original stone vertex positions and four nominal heights preserved; material/UV replaced.'

# A closed stepped polyhedron, 4 mm below each original tread. It is visible in
# the mortar joints and has the same rendered/physical geometry. No ramp, box
# collider or invisible walk-only surface is introduced.
profile=[(.012,0),(2.028,0),(2.028,.636),(1.212,.636),(1.212,.476),(.812,.476),(.812,.316),(.412,.316),(.412,.156),(.012,.156)]
n=len(profile);v=[(x,y,z) for x in [-1.086,1.086] for y,z in profile]
f=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
me=bpy.data.meshes.new('Continuous four-tier lime mortar bed');me.from_pydata(v,[],f);me.update()
bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
core=bpy.data.objects.new(NAME+'_continuous_mortar_bed',me);bpy.context.collection.objects.link(core)
core['rmmo_collision']='walk';core['asset_id']=NAME;core['design_provenance']='Project supplementary repair: continuous stepped bed with 4 mm recessed visible pointing; no hidden collider.'
mortar=bpy.data.materials.new('Recessed lime mortar');mortar.use_nodes=True
mb=next(n for n in mortar.node_tree.nodes if n.type=='BSDF_PRINCIPLED');mb.inputs['Base Color'].default_value=(.30,.28,.24,1);mb.inputs['Metallic'].default_value=0;mb.inputs['Roughness'].default_value=1
me.materials.append(mortar)
for o in [stone,core]:
    # Face-local orthonormal metre UVs keep even narrow bevel triangles valid.
    uv=o.data.uv_layers.active or o.data.uv_layers.new(name='WorkedStoneUV');uv.name='WorkedStoneUV'
    for p in o.data.polygons:
        normal=p.normal.normalized();axis=Vector((0,0,1)) if abs(normal.z)<.8 else Vector((0,1,0))
        u=normal.cross(axis).normalized();w=normal.cross(u).normalized()
        for li in p.loop_indices:
            pos=o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co
            uv.data[li].uv=(pos.dot(u)/2,pos.dot(w)/2)
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new('Explicit surface triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
assert before==[tuple(stone.matrix_world@v.co) for v in stone.data.vertices]
master=OUT/(NAME+'_master.blend');bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
path=OUT/(NAME+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_extras=True,export_yup=True,export_tangents=True,export_normals=True,export_animations=False,export_lights=False,export_cameras=False)
coords=[o.matrix_world@v.co for o in [stone,core] for v in o.data.vertices]
coords=[(p.x,p.z,-p.y) for p in coords]
row={'id':NAME,'path':path.as_posix(),'sha256':sha(path),'bytes':path.stat().st_size,'master':master.as_posix(),'master_sha256':sha(master),'baseline':{'path':SOURCE.as_posix(),'sha256':sha(SOURCE)},'inputs':inputs,'bounds':{'min':[min(p[k] for p in coords) for k in range(3)],'max':[max(p[k] for p in coords) for k in range(3)]},'anchors':{'origin':'unchanged bottom-front foundation','front':'+Z water','back':'-Z land','step_heights':[.16,.32,.48,.64],'mortar_heights':[.156,.316,.476,.636],'mortar_recess_m':.004},'notes':'Original 16 bevelled stone blocks unchanged in geometry. One real continuous stepped mortar bed closes through seams; visible shallow pointing, shared render/collision, no invisible ramp. Existing worked stone base color and owned OpenGL scan normal/roughness reused.'}
(OUT/(NAME+'_authoring.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
shutil.copyfile(__file__,OUT/'build_snapshot.py')
print('S12_STAIRS_REPAIR',row['sha256'],row['bounds'])
