"""Reopen oak, exercise native parameters, save three reusable presets and render."""
import bpy,json,sys,time,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from build_blender_parametric_oak import OUT,setval

bpy.ops.wm.open_mainfile(filepath=str(OUT/'street_oak_parametric.blend'))
sc=bpy.context.scene;tree=bpy.data.objects['STREET OAK | editable parameters']
tests=[]
def snapshot(name):
    start=time.perf_counter();bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get()
    count=sum(1 for i in dg.object_instances if i.is_instance)
    bounds=list(tree.dimensions)
    assert all(0<x<40 for x in bounds),bounds
    tests.append({'test':name,'dimensions':bounds,'instances':count,'update_seconds':time.perf_counter()-start})
    print(tests[-1],flush=True)
    return count

full=snapshot('default')
assert full==505,full
# Every transformed twig base must follow the skeleton's spatial map. This
# catches accidental scaling around world origin, which detaches the canopy.
setval(tree,'Irregularity',0.)
bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
errors=[]
for instance in dg.object_instances:
    if not instance.is_instance:continue
    source=instance.object.original
    if not source.name.startswith('Branch_'):continue
    p=source.matrix_world.translation
    q=p.z/13.2272053;t=max(0.,min(1.,(q-.12)/(.48-.12)));smooth=t*t*(3-2*t)
    w=(2.1+(1.7-2.1)*smooth)*9/13.2272053
    expected=Vector((p.x*w+.2*q*q,p.y*w,q*9-.5*math.sin(q*math.pi)))
    errors.append((instance.matrix_world.translation-expected).length)
assert len(errors)==505,len(errors)
assert max(errors)<.0001,max(errors)
tests.append({'test':'twig_base_attachment','maximum_error_metres':max(errors)})
setval(tree,'Irregularity',.06)
setval(tree,'Height (m)',7);snapshot('height_7')
setval(tree,'Height (m)',9);setval(tree,'Crown spread',1.2);snapshot('narrow_crown')
setval(tree,'Crown spread',1.7);setval(tree,'Seed',81);setval(tree,'Twig retention',.90)
retained=snapshot('seed_81_retention_90_percent');assert 400<retained<505,retained
setval(tree,'Seed',17);setval(tree,'Twig retention',1.);setval(tree,'Wind (m)',.06)
sc.frame_set(1);snapshot('wind_frame_1');sc.frame_set(36);snapshot('wind_frame_36')
sc.frame_set(1);setval(tree,'Wind (m)',0.)
if '--check-only' in sys.argv:
    (OUT/'parameter_checks.json').write_text(json.dumps(tests,indent=2),encoding='utf-8')
    print('PARAMETER_CHECKS_PASSED',flush=True)
    raise SystemExit(0)

# Close leaf/twig check. Same light, camera and seed for both reduction states.
cam=sc.camera
oldloc=cam.location.copy();oldrot=cam.rotation_euler.copy();oldscale=cam.data.ortho_scale
cam.location=(6,-10,7);cam.rotation_euler=(Vector((1.8,-.2,6.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.5
for name,flag in [('master',False),('optimized',True)]:
    setval(tree,'Optimized',flag);sc.render.filepath=str(OUT/f'{name}_foliage.png');bpy.ops.render.render(write_still=True)
cam.location=oldloc;cam.rotation_euler=oldrot;cam.data.ortho_scale=oldscale

# An independent comparison scene reuses source modules and materials.
presets=bpy.data.scenes.new('PRESETS | street - courtyard - riverside')
presets.world=sc.world
presets.render.engine='CYCLES';presets.cycles.samples=40;presets.cycles.use_denoising=True;presets.cycles.device=sc.cycles.device
presets.render.resolution_x=1800;presets.render.resolution_y=900;presets.render.resolution_percentage=100
presets.view_settings.view_transform='AgX'
presets.view_settings.exposure=.5
for name in ['REVIEW | ground','REVIEW | fixed sun']:
    presets.collection.objects.link(bpy.data.objects[name])
definitions=[('01 Courtyard | compact',-9,7.2,1.55,2.0,-.4,-.15,11),('02 Street | broad shade',0,9.,1.7,2.1,-.5,.20,17),('03 Riverside | leaning',9,8.2,1.95,2.3,-.6,.5,63)]
for name,x,height,spread,thick,lift,lean,seed in definitions:
    o=tree.copy();o.name=name;presets.collection.objects.link(o);o.location.x=x
    for key,value in [('Height (m)',height),('Crown spread',spread),('Trunk width',thick),('Crown lift (m)',lift),('Lean (m)',lean),('Seed',seed)]:setval(o,key,value)
    o.asset_mark();o.asset_data.description='Editable realistic street oak. Native Geometry Nodes; shared Fab twig geometry.'
camera=bpy.data.objects.new('PRESETS | camera',cam.data.copy());presets.collection.objects.link(camera);camera.location=(12,-36,15);camera.rotation_euler=(Vector((0,0,4.1))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=29;presets.camera=camera
presets.render.filepath=str(OUT/'three_presets.png')
bpy.ops.render.render(write_still=True,scene=presets.name)

# Keep the single-tree editing scene active and the optimized state selected.
bpy.context.window.scene=sc
bpy.ops.object.select_all(action='DESELECT');tree.select_set(True);bpy.context.view_layer.objects.active=tree
setval(tree,'Optimized',True)
assert all(im.packed_file for im in bpy.data.images if im.source=='FILE'), 'Unpacked image dependency'
readme=bpy.data.texts.get('使用说明与验收记录') or bpy.data.texts.new('使用说明与验收记录')
readme.clear();readme.write((Path(__file__).parent.parent/'docs/parametric_street_oak_20261006.md').read_text(encoding='utf-8'))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'street_oak_parametric.blend'),compress=True)
(OUT/'parameter_verification.json').write_text(json.dumps({'passed':True,'checks':tests,'presets':[x[0] for x in definitions]},indent=2),encoding='utf-8')
print('PARAMETRIC_OAK_VERIFIED',flush=True)
