extends SceneTree
## Reproduce a settled map with thousands of unrelated resident meshes.
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Directory=preload("res://scripts/world3d/distant_proxy_sources.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class Batches extends Node:
	var groups:Dictionary={}
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	if "--scan" in OS.get_cmdline_user_args():Proxy.source_catalog_enabled=false
	var scene:=Node3D.new();root.add_child(scene)
	var batches:=Batches.new();batches.name="GroundRenderBatches";scene.add_child(batches)
	var service:=Proxy.new();scene.add_child(service);service.set_process(false)
	var mesh:=BoxMesh.new();mesh.material=StandardMaterial3D.new()
	var sources:Dictionary={};var buildings:Array=[]
	for i in 4160:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.name="source_"+str(i)
		var record:Dictionary={"kind":"ground"}
		if i<64:
			record={"building":{"id":"house_"+str(i/2)},"house_prefab":{}}
			node.position=Vector3(140+i/2%8*6,0,i/16*8+i%2*3);buildings.append(node)
		node.set_meta("ground_batch_record",record);scene.add_child(node);sources[str(node.name)]=node
	scene.set_meta("stream_meshes",sources)
	for node:MeshInstance3D in sources.values():Stream._track_deferred_source(scene,node)
	var before:=Time.get_ticks_usec()
	for i in 120:service.tick(Vector3.ZERO)
	var elapsed:=Time.get_ticks_usec()-before
	check(service._rows.is_empty() and service._job.is_empty(),"near map creates no proxy workers")
	check(not mesh.has_meta("ground_cpu_cache"),"near map never captures mesh arrays")
	var settled_profile:Dictionary=service.profile.duplicate(true)
	var directory:RefCounted=scene.get_meta(Directory.META)
	check(directory.sources.size()==64 and directory.admitted==64,"one entry per possible source; repeated admission is idempotent")
	check(service.profile.source_visits==(64 if Proxy.source_catalog_enabled else 4160)*120,"stable ticks visit only the selected directory")
	root.remove_child(scene)
	check(directory.sources.is_empty(),"detaching map withdraws all live candidates")
	root.add_child(scene)
	check(directory.sources.size()==64,"reattaching the same map restores candidates without republication")
	var first:MeshInstance3D=buildings[0];var first_id:=first.get_instance_id()
	var removed_name:=str(first.name);var record:Dictionary=first.get_meta("ground_batch_record")
	Stream._drop(sources,removed_name,first,scene)
	check(not directory.sources.has(first_id) and directory.sources.size()==63,"actual residency removal updates candidates synchronously")
	var replacement:=MeshInstance3D.new();replacement.name=removed_name;replacement.mesh=mesh;replacement.position=Vector3(140,0,0)
	replacement.set_meta("ground_batch_record",record);scene.add_child(replacement);sources[removed_name]=replacement
	Stream._track_deferred_source(scene,replacement)
	check(directory.sources.size()==64 and directory.sources.has(replacement.get_instance_id()),"same-name return publication is visible immediately")
	var skips:int=service.profile.near_snapshot_skips
	replacement.mesh=Cpu.capture(mesh);service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-skips==31,"live CPU freeze suppresses source without rebuilding directory")
	replacement.mesh=mesh;skips=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-skips==32,"restoring live renderer mesh restores eligibility")
	replacement.material_override=StandardMaterial3D.new();skips=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-skips==31,"material override is still checked live")
	replacement.material_override=null;replacement.hide();skips=service.profile.near_snapshot_skips;service.tick(Vector3.ZERO)
	check(service.profile.near_snapshot_skips-skips==31,"hidden source cannot enter a snapshot")
	replacement.show();service._cooldown.clear();replacement.position=Vector3(1000,0,0);service.tick(Vector3.ZERO)
	check(service._job.is_empty(),"live pose and cohort extent reject separated sources")
	replacement.position=Vector3(140,0,0);service._cooldown.clear();service.tick(Vector3(-300,0,0))
	check(not service._job.is_empty(),"moving camera admits eligible far source immediately")
	var deadline:=Time.get_ticks_msec()+10000
	while not service._job.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;service._poll()
	check(not service._rows.is_empty(),"catalog still publishes a far proxy")
	if not service._rows.is_empty():
		var row:Dictionary=service._rows.values()[0];var member:Node3D=row.members[0].get_ref()
		Stream._drop(sources,str(member.name),member,scene)
		check(service._rows.is_empty(),"source removal withdraws active draw before another tick")
	var generic:=Node3D.new();root.add_child(generic);var generic_batches:=Batches.new();generic_batches.name="GroundRenderBatches";generic.add_child(generic_batches)
	var generic_service:=Proxy.new();generic.add_child(generic_service);generic_service.set_process(false)
	generic_service.tick(Vector3.ZERO)
	check(generic_service.profile.fallback_ticks==1,"unowned public maps retain live scan fallback")
	generic.free()
	var result:={"checks":checks,"failures":failures,"source_count":4160,"eligible_sources":64,"ticks":120,"tick_us":elapsed,"profile":settled_profile}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));scene.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
