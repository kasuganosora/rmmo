"""Dedicated S1 five-step doorstep: reviewed S12 masonry recipe, exact new dimensions, no overall scaling."""
import bpy, bmesh, json, hashlib, math, sys, shutil, argparse
from pathlib import Path
from mathutils import Vector

BASE=Path('D:/code/rmmo_runtime/art_sources/s1_five_step_doorstep_20261017')
parser=argparse.ArgumentParser();parser.add_argument('--version',default='v1')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=BASE/args.version;OUT.mkdir(parents=True,exist_ok=True)
SOURCE=Path('D:/code/rmmo_runtime/packs/default/assets/6159447af9b9583a35eb72b9674e02b2ad70ef043683ae85685d82aa3ff99ff5.glb')
NAME='s1_doorstep_stairs_5'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(SOURCE)==SOURCE.stem
assert not (OUT/(NAME+'.glb')).exists()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system='METRIC'
# Same real individual masonry block recipe as approved S12; five new tiers.
parts=[]
for i in range(5):
    low=i*.4+(0 if i==0 else .002);high=(i+1)*.4-.002 if i<4 else 2.4
    h=(i+1)*.16
    for col in range(4):
        left=-1.1+col*.55+(0 if col==0 else .002);right=-1.1+(col+1)*.55-(0 if col==3 else .002)
        bpy.ops.mesh.primitive_cube_add(size=1,location=((left+right)/2,(low+high)/2,h/2))
        ob=bpy.context.object;ob.name='Masonry_step_%d_block_%d'%(i+1,col+1);ob.dimensions=(right-left,high-low,h)
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        mod=ob.modifiers.new('Worked stone arris 7 mm','BEVEL');mod.width=.007;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=ob.modifiers.new('Weighted stone normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
        parts.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();stone=bpy.context.object
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
stone['repair_note']='New 5-tier stone geometry, 0.16m rise, 0.40m tread and 0.80m top platform; no global scale.'

# A closed stepped polyhedron, 4 mm below each original tread. It is visible in
# the mortar joints and has the same rendered/physical geometry. No ramp, box
# collider or invisible walk-only surface is introduced.
profile=[(.012,0),(2.388,0),(2.388,.796),(1.612,.796),(1.612,.636),(1.212,.636),(1.212,.476),(.812,.476),(.812,.316),(.412,.316),(.412,.156),(.012,.156)]
n=len(profile);v=[(x,y,z) for x in [-1.086,1.086] for y,z in profile]
f=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
me=bpy.data.meshes.new('Continuous five-tier lime mortar bed');me.from_pydata(v,[],f);me.update()
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
row={'id':NAME,'path':path.as_posix(),'sha256':sha(path),'bytes':path.stat().st_size,'master':master.as_posix(),'master_sha256':sha(master),'baseline':{'path':SOURCE.as_posix(),'sha256':sha(SOURCE)},'inputs':inputs,'bounds':{'min':[min(p[k] for p in coords) for k in range(3)],'max':[max(p[k] for p in coords) for k in range(3)]},'anchors':{'origin':'bottom-front foundation [0,0,0]','front':'+Z low side','back':'-Z high side','step_heights':[.16,.32,.48,.64,.80],'mortar_heights':[.156,.316,.476,.636,.796],'width':2.2,'tread':.4,'upper_landing':.8,'length':2.4,'top_platform_center':[0,.8,-2.0],'top_back_edge':[0,.8,-2.4],'mortar_recess_m':.004},'notes':'20 newly sized bevelled stones using the approved S12 recipe; five 0.16m rises, four 0.40m treads and 0.80m top platform. One real continuous stepped mortar bed closes through seams; visible shallow pointing, shared render/collision, no invisible ramp. Existing worked stone base color and owned OpenGL scan normal/roughness reused.'}
(OUT/(NAME+'_authoring.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
shutil.copyfile(__file__,OUT/'build_snapshot.py')
print('S1_FIVE_STEP_COMPLETE',row['sha256'],row['bounds'])
