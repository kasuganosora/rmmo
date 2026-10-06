"""Reopen pine, exercise native parameters, save three reusable presets and render."""
import bpy,json,sys,time,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from build_blender_parametric_pine import OUT,setval

bpy.ops.wm.open_mainfile(filepath=str(OUT/'baltic_pine_parametric.blend'))
sc=bpy.context.scene;tree=bpy.data.objects['BALTIC PINE | editable parameters']
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
assert full==583,full
# Every transformed twig base must follow the skeleton's spatial map. This
# catches accidental scaling around world origin, which detaches the canopy.
setval(tree,'Irregularity',0.)
bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
errors=[]
short_socket=next((s for s in tree.modifiers[0].node_group.interface.items_tree if s.name=='Bare trunk shortening (m)' and s.in_out=='INPUT'),None)
shortening=tree.modifiers[0].get(short_socket.identifier,short_socket.default_value) if short_socket else 0.
for instance in dg.object_instances:
    if not instance.is_instance:continue
    source=instance.object.original
    if not source.name.startswith('Branch_'):continue
    p=source.matrix_world.translation
    q=p.z/18.72559928894043;t=max(0.,min(1.,(q-.12)/(.48-.12)));smooth=t*t*(3-2*t)
    w=(1.45+(1.25-1.45)*smooth)*10/18.72559928894043
    lower=max(0.,min(1.,q/.25));lower=lower*lower*(3-2*lower)
    expected=Vector((p.x*w+.12*q*q,p.y*w,q*10-shortening*lower))
    errors.append((instance.matrix_world.translation-expected).length)
assert len(errors)==583,len(errors)
assert max(errors)<.0001,max(errors)
tests.append({'test':'twig_base_attachment','maximum_error_metres':max(errors)})
setval(tree,'Irregularity',.06)
setval(tree,'Height (m)',7);snapshot('height_7')
setval(tree,'Height (m)',10);setval(tree,'Crown spread',1.2);snapshot('narrow_crown')
setval(tree,'Crown spread',1.25);setval(tree,'Seed',81);setval(tree,'Twig retention',.90)
retained=snapshot('seed_81_retention_90_percent');assert 400<retained<583,retained
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
cam.location=(6,-10,8);cam.rotation_euler=(Vector((.6,-.2,8.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.5
for name,flag in [('master',False),('optimized',True)]:
    setval(tree,'Optimized',flag);sc.render.filepath=str(OUT/f'{name}_foliage.png');bpy.ops.render.render(write_still=True)
cam.location=oldloc;cam.rotation_euler=oldrot;cam.data.ortho_scale=oldscale

# An independent comparison scene reuses source modules and materials.
presets=bpy.data.scenes.new('PRESETS | compact - mature - windswept')
presets.world=sc.world
presets.render.engine='CYCLES';presets.cycles.samples=40;presets.cycles.use_denoising=True;presets.cycles.device=sc.cycles.device
presets.render.resolution_x=1800;presets.render.resolution_y=900;presets.render.resolution_percentage=100
presets.view_settings.view_transform='AgX'
presets.view_settings.exposure=.5
for name in ['REVIEW | ground','REVIEW | fixed sun']:
    presets.collection.objects.link(bpy.data.objects[name])
definitions=[('01 Pine | compact',-6,7.5,1.05,1.35,0.,-.12,11),('02 Pine | mature',0,10.,1.25,1.45,0.,.12,17),('03 Pine | windswept',6,9.,1.5,1.6,-.3,.5,63)]
for name,x,height,spread,thick,lift,lean,seed in definitions:
    o=tree.copy();o.name=name;presets.collection.objects.link(o);o.location.x=x
    for key,value in [('Height (m)',height),('Crown spread',spread),('Trunk width',thick),('Crown lift (m)',lift),('Lean (m)',lean),('Seed',seed)]:setval(o,key,value)
    o.asset_mark();o.asset_data.description='Editable realistic Baltic pine. Native Geometry Nodes; shared Fab twig geometry.'
camera=bpy.data.objects.new('PRESETS | camera',cam.data.copy());presets.collection.objects.link(camera);camera.location=(12,-36,15);camera.rotation_euler=(Vector((0,0,5.))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=23;presets.camera=camera
presets.render.filepath=str(OUT/'three_presets.png')
bpy.ops.render.render(write_still=True,scene=presets.name)

# Keep the single-tree editing scene active and the optimized state selected.
bpy.context.window.scene=sc
bpy.ops.object.select_all(action='DESELECT');tree.select_set(True);bpy.context.view_layer.objects.active=tree
setval(tree,'Optimized',True)
assert all(im.packed_file for im in bpy.data.images if im.source=='FILE'), 'Unpacked image dependency'
readme=bpy.data.texts.get('使用说明与验收记录') or bpy.data.texts.new('使用说明与验收记录')
readme.clear();readme.write((Path(__file__).parent.parent/'docs/parametric_baltic_pine_20261006.md').read_text(encoding='utf-8'))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baltic_pine_parametric.blend'),compress=True)
(OUT/'parameter_verification.json').write_text(json.dumps({'passed':True,'checks':tests,'presets':[x[0] for x in definitions]},indent=2),encoding='utf-8')
print('PARAMETRIC_PINE_VERIFIED',flush=True)
