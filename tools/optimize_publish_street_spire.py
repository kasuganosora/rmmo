"""Blender: retain approved master, bake clay normal, batch by tower section."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
BASE=Path('D:/code/rmmo_runtime/art_sources/street_red_spire/square_3window_shaft_2000_roof_750_finial_240')
OUT=BASE/'game';OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'street_spire_optimized.blend'))
sc=bpy.context.scene
assets=[o for o in sc.objects if o.get('asset_role')=='street_red_spire']
clays=[m for m in bpy.data.materials if m.name.startswith('Fired red clay')]
# Bake original procedural normal on a tile-sized sample. Share one normal texture.
bpy.ops.mesh.primitive_plane_add(size=1,location=(0,0,-20));sample=bpy.context.object
sample.data.materials.append(clays[0]);bpy.context.view_layer.objects.active=sample
normal=bpy.data.images.new('Baked fired clay tangent normal',width=1024,height=1024,alpha=False);normal.colorspace_settings.name='Non-Color'
target=clays[0].node_tree.nodes.new('ShaderNodeTexImage');target.image=normal;clays[0].node_tree.nodes.active=target
sc.render.engine='CYCLES';sc.cycles.samples=16
bpy.ops.object.bake(type='NORMAL',normal_space='TANGENT',margin=8)
normal.filepath_raw=str(OUT/'clay_normal.png');normal.file_format='PNG';normal.save();normal.pack()
bpy.data.objects.remove(sample,do_unlink=True)
for m in clays:
    nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    for link in list(nt.links):
        if link.to_socket==bs.inputs['Normal']:nt.links.remove(link)
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=normal
    n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.12
    nt.links.new(tex.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs['Normal'])
    # A local 0..1 UV per tile gives the packed texture the same repetition basis.
for o in assets:
    if o.name.startswith('Overlapping red tile'):
        uv=o.data.uv_layers.active
        for axis in [0,1]:
            values=[x.uv[axis] for x in uv.data];lo=min(values);span=max(values)-lo
            if span>1e-6:
                for x in uv.data:x.uv[axis]=(x.uv[axis]-lo)/span
    for mod in o.modifiers:
        if mod.type=='BEVEL':mod.segments=1
def count(obs):
    deps=bpy.context.evaluated_depsgraph_get();total=0
    for o in obs:
        ev=o.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles();total+=len(me.loop_triangles);ev.to_mesh_clear()
    return total
def render(name,close=False):
    cam=sc.camera;cam.location=(10,-18,25) if close else (30,-48,26)
    target=Vector((0,0,21.7 if close else 13.75));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10 if close else 32
    sc.cycles.samples=24;sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
render('game_overview');render('game_close',True)
# Keep approved split walls; combine only accessories belonging to the same height section.
groups={name:[] for name in ['shaft_0','shaft_1','shaft_2','shaft_3','roof','door']}
for o in assets:
    if o.name.startswith('Shaft section'):key='shaft_'+o.name.split()[-1]
    elif o.name.startswith(('Separate closed door','Door vertical','Door iron')):key='door'
    elif o.name.startswith(('Overlapping red tile','Four-sided pyramid','Square eave','Metal finial')):key='roof'
    else:
        z=sum((o.matrix_world@Vector(c)).z for c in o.bound_box)/8
        key='shaft_'+str(min(3,max(0,int(z/5))))
    groups[key].append(o)
deps=bpy.context.evaluated_depsgraph_get()
data=[bpy.data.meshes.new_from_object(o.evaluated_get(deps)) for o in assets]
for o,me in zip(assets,data):o.modifiers.clear();o.data=me
joined=[]
for key,obs in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name='StreetSpire_'+key;o['rmmo_collision']='block';joined.append(o)
tri=count(joined)
render('batched_overview')
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'street_spire_game.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for o in joined:o.select_set(True)
file=OUT/'street_spire.glb';bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
old=json.loads((BASE/'manifest.json').read_text())
report=dict(status='game candidate',assets=[dict(id='street_spire',game_triangles=tri,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),recipe=dict(height=29.85),mesh_count=len(joined))],dimensions=old['dimensions'],approved_triangles=old['optimized_triangles'],game_triangles=tri,limitations=['Closed exterior landmark; no playable interior, stairs, or door interaction'])
(OUT/'manifest.json').write_text(json.dumps(report,indent=2));print('SPIRE_GAME',json.dumps(report),flush=True)
