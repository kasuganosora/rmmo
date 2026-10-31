extends SceneTree
## Repeated building parts: live eligibility must be rechecked next tick, while
## identical meshes and cohort keys need only one evaluation inside one tick.
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
class Batches extends Node:
	var groups:Dictionary={}
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	if "--legacy-tick" in OS.get_cmdline_user_args():Proxy.tick_local_reuse_enabled=false
	var scene:=Node3D.new();root.add_child(scene)
	var batches:=Batches.new();batches.name="GroundRenderBatches";scene.add_child(batches)
	var service:=Proxy.new();scene.add_child(service);service.set_process(false)
	var material:=StandardMaterial3D.new();var meshes:Array[ArrayMesh]=[]
	var arrays:=BoxMesh.new().get_mesh_arrays()
	for i in 117:
		var mesh:=ArrayMesh.new()
		for slot in 8:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(slot,material)
		meshes.append(mesh)
	var sources:Dictionary={};var visuals:Array[MeshInstance3D]=[]
	for house in 31:
		for part in 7:
			var visual:=MeshInstance3D.new();visual.mesh=meshes[(house*7+part)%117]
			visual.position=Vector3(140+house%8*6,0,house/8*8+part*.1)
			visual.name="source_%d_%d"%[house,part]
			visual.set_meta("ground_batch_record",{"building":{"id":"house_"+str(house)},"house_prefab":{}})
			scene.add_child(visual);visuals.append(visual)
			if part<4:batches.groups[str(visual.get_instance_id())]={"category":"building","visual":visual,"members":[visual]}
			else:sources[str(visual.name)]=visual
	scene.set_meta("stream_meshes",sources)
	var times:Array=[]
	for i in 64:
		var began:=Time.get_ticks_usec();service.tick(Vector3.ZERO);times.append(Time.get_ticks_usec()-began)
	var measured:Dictionary=service.profile.duplicate(true)
	check(service._job.is_empty() and service._rows.is_empty(),"near cohorts produce no geometry worker or proxy")
	check(int(measured.near_snapshot_skips)==31*64,"every tick preserves all 31 near cohorts")
	if "--require-reuse" in OS.get_cmdline_user_args():
		check(int(measured.get("eligibility_mesh_evaluations",-1))==117*64,"shared mesh eligibility is evaluated once per tick")
		check(int(measured.get("cohort_key_builds",-1))==31*64,"each cohort string is built once per tick")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var prior:int=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips==prior,"shared material edits invalidate eligibility on the very next tick")
	material.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-prior==31,"restoring shared material restores every cohort")
	for visual:MeshInstance3D in visuals:
		if visual.get_meta("ground_batch_record").building.id=="house_0":visual.material_override=material
	prior=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-prior==30,"per-visual overrides remain outside shared mesh eligibility")
	for visual:MeshInstance3D in visuals:
		if visual.get_meta("ground_batch_record").building.id=="house_0":visual.material_override=null;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prior=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-prior==31,"next-tick shadow changes rebuild cohort identities")
	var identities:Dictionary={"values":{},"builds":0}
	var sample:MeshInstance3D=visuals[0];var record:Dictionary=sample.get_meta("ground_batch_record")
	for layer:int in [1,2,2147483648,4294967295]:
		for shadow:int in [0,1,2,3]:
			sample.layers=layer;sample.cast_shadow=shadow
			check(Proxy._cohort(record,sample,identities)==str([record.building.id,layer,shadow]),"cached identity preserves complete layer mask and shadow mode")
	times.sort();var result:={"checks":checks,"failures":failures,"ticks":64,"source_count":217,"unique_meshes":117,"surfaces_per_mesh":8,"cohorts":31,"tick_median_us":times[32],"tick_p95_us":times[60],"tick_max_us":times[-1],"tick_total_us":times.reduce(func(a,b):return a+b,0),"profile":measured}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PROXY_TICK_REUSE ",JSON.stringify(result));scene.free();await process_frame
	quit(0 if failures.is_empty() else 1)
