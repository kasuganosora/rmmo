extends SceneTree
## Component fixture for the actual WorldStream permanent-disposal entry.
## External instrument_for_test.py enables exact work counters; --require-work-ledger makes them mandatory.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const WorkerRetirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
var checks:=0
var failures:Array[String]=[]
var reports:Array=[]
var count_per_group:=8
class CountedCpu extends Cpu:
	var uploads:=0
	func restore()->Mesh:
		uploads+=1
		return BoxMesh.new()
class PoseWatch extends Node3D:
	var changed:Callable
	func ping()->void:
		if changed.is_valid():changed.call()
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var batch:=Batch.new();map.add_child(batch);batch.set_process(false)
	var meshes:Array=[];var nodes:Array=[];var held:Array=[];var visuals:Array[int]=[];var watches:Array=[]
	var source_map:Dictionary={};var parents:Array=[]
	for category:String in ["building","vegetation","ground"]:
		var members:Array=[]
		var component:=Node3D.new();component.name=category+"Component";map.add_child(component);parents.append(component)
		for index:int in count_per_group:
			var mesh:=CountedCpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
			mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);meshes.append(mesh)
			var node:=MeshInstance3D.new();node.name=category+str(index);node.mesh=mesh
			node.set_meta("ground_batch_record",{"uuid":str(node.name),"building":"fixture"})
			component.add_child(node);nodes.append(node);members.append(node);source_map[str(node.name)]=node
		var group:Dictionary={"members":members,"category":category,"generation":held.size()+1,"vertices":3*count_per_group,"cutout_instanced":category=="vegetation","cpu":meshes.slice(meshes.size()-count_per_group),"data":{"mesh":BoxMesh.new(),"cpu_metadata":[[1,2,3],[4,5,6]]}}
		var visual:=MeshInstance3D.new();visual.mesh=BoxMesh.new();batch.add_child(visual);group.visual=visual;visuals.append(visual.get_instance_id())
		var watcher:=PoseWatch.new();map.add_child(watcher);group.pose_watcher=watcher;watches.append(watcher)
		batch.groups[category]=group;batch._watch_group(category,group)
		watcher.changed=batch._sync_pose.bind(category,int(group.generation))
		for node:Node in members:batch._member_groups[str(node.name)]=category
		batch.terrain_lod_visuals[visual.get_instance_id()]=group
		if category=="vegetation":batch.cutout_visuals[visual.get_instance_id()]=group
		held.append(group)
	map.set_meta("stream_meshes",source_map)
	var descriptor:Dictionary={"reference":weakref(nodes[0]),"pose":Transform3D.IDENTITY,"keys":["borrowed"],"nested":[[7,8,9]]}
	batch._residency_descriptors[1]=descriptor
	var desired:Dictionary={"held":{"members":[nodes[0]],"data":{"mesh":meshes[0]}}}
	var prep_parent:=Node3D.new();map.add_child(prep_parent);parents.append(prep_parent)
	var bin_parent:=Node3D.new();map.add_child(bin_parent);parents.append(bin_parent)
	batch._preparation={"phase":"add","desired":desired,"raw_desired":desired,"handoff_parents":{prep_parent.get_instance_id():weakref(prep_parent)}}
	batch._residency_bins={"desired":desired,"handoff_parents":{bin_parent.get_instance_id():weakref(bin_parent)}};batch._next_residency={"nodes":nodes.duplicate()}
	batch.pending.assign(["building","vegetation","ground"])
	batch._material_keys["held"]="value";batch._instance_meshes["held"]=weakref(meshes[0])
	batch._building_meshes["held"]={"reference":weakref(meshes[0])}
	batch._audit_keys.assign(["building"]);batch._audit_cursor=1
	batch._cutout_timing={"held":1};batch._cutout_samples=[1];batch._cutout_gpu_samples=[1];batch._cutout_camera_state=[1]
	return {"map":map,"batch":batch,"meshes":meshes,"nodes":nodes,"groups":held,"visual_ids":visuals,"watchers":watches,"descriptor":descriptor,"parents":parents}
func uploads(meshes:Array)->int:
	var result:=0
	for mesh:CountedCpu in meshes:result+=mesh.uploads
	return result
func catalogs_empty(batch:Node)->bool:
	for field:String in ["groups","pending","_material_keys","_instance_meshes","_member_groups","_building_meshes","_preparation","_residency_descriptors","_residency_bins","_next_residency","terrain_lod_visuals","cutout_visuals","_cutout_camera_state","_cutout_timing","_cutout_samples","_cutout_gpu_samples","_audit_keys","_loading_budgets","_source_parents","_handoff_parents"]:
		if not batch.get(field).is_empty():return false
	return not batch._scene_handoff and not batch._handoff_parent_changed.is_valid()
func work(batch:Node)->Dictionary:
	var required:Array[String]=["_test_close_member_erases","_test_close_visual_erases","_test_close_visibility_restores"]
	for property:Dictionary in batch.get_property_list():required.erase(str(property.name))
	if not required.is_empty():return {}
	return {"member_erases":batch.get("_test_close_member_erases"),"visual_erases":batch.get("_test_close_visual_erases"),"visibility_restores":batch.get("_test_close_visibility_restores")}
func stop_retirement()->Node:
	var service:=root.get_node_or_null(Retirement.NODE_NAME)
	if service!=null:service.set_process(false)
	return service
func gated_worker(started:Semaphore,release:Semaphore)->Dictionary:
	started.post();release.wait()
	return {"retired_cpu_only":PackedInt32Array([1,2,3])}
func permanent_case()->void:
	var f:=fixture();var batch:Node=f.batch
	var descriptor:Dictionary=f.descriptor;var descriptor_data:=var_to_bytes(descriptor.nested)
	var cpu_data:=var_to_bytes(f.meshes[0].surfaces)
	var held_data:Dictionary=f.groups[0].data;var held_bytes:=var_to_bytes(held_data.cpu_metadata)
	var source_ids:Array=[]
	for node:Node in f.nodes:source_ids.append(node.get_instance_id())
	var started:=Semaphore.new();var release:=Semaphore.new();var thread:=Thread.new()
	var ticket:=WorkerRetirement.watch(thread,self,[f.meshes[0],held_data,descriptor]);var lease:RefCounted=ticket.lease
	var drainer:Node=ticket.drainer;drainer.set_process(false)
	var status:=thread.start(gated_worker.bind(started,release))
	check(status==OK,"real background worker starts with the existing owner lease")
	if status!=OK:
		WorkerRetirement.complete(ticket);f.batch.clear(false);f.map.free();return
	started.wait()
	batch._workers.append({"key":"building","generation":f.groups[0].generation,"thread":thread,"started":Time.get_ticks_usec(),"retirement":ticket})
	var before_rebuild:int=batch.rebuild_count;var before_sync:int=batch.sync_count
	check(batch._source_parents.size()==3,"real nested group parents are present in the shared parent directory")
	var handoff:Dictionary={"changed":false};batch.begin_scene_handoff(handoff)
	var parent_callback:Callable=batch._handoff_parent_changed
	check(batch._handoff_parents.size()==5 and f.parents.all(func(n:Node)->bool:return n.child_order_changed.is_connected(parent_callback)),"handoff observes nested group, prepare-only and raw-bin-only parents")
	Stream.prepare_map_disposal(f.map,self);stop_retirement()
	check(thread.is_alive() and not lease.released and batch._workers.is_empty(),"permanent close abandons, never joins, the live worker and retains inputs")
	check(batch.live_worker_joins==0,"close does not synchronously wait for worker completion")
	check(catalogs_empty(batch),"every live batch catalog is empty after the permanent entry")
	check(f.parents.all(func(n:Node)->bool:return not n.child_order_changed.is_connected(parent_callback)),"permanent close revokes all temporary nested and scratch parent observers")
	for parent:Node in f.parents:parent.child_order_changed.emit()
	check(not handoff.changed,"old parent structural signals cannot reach the closed handoff")
	check(uploads(f.meshes)==0,"permanent close does not restore CPU meshes")
	check(f.visual_ids.all(func(id:int)->bool:return instance_from_id(id)==null),"current group visual.free behavior stays immediate")
	var disconnected:=true
	for group:Dictionary in f.groups:
		for node:Node in group.members:
			disconnected=disconnected and not node.tree_exiting.is_connected(group.exit_callback)
			if group.has("visible_callback"):disconnected=disconnected and not node.visibility_changed.is_connected(group.visible_callback)
	check(disconnected,"all registered source exit and visibility observers are revoked")
	for watcher:PoseWatch in f.watchers:watcher.ping()
	for node:Node in f.nodes:node.visibility_changed.emit();node.tree_exiting.emit()
	for group:Dictionary in f.groups:group.exit_callback.call()
	check(uploads(f.meshes)==0 and batch.rebuild_count==before_rebuild and catalogs_empty(batch),"old source and pose callbacks cannot restore, enqueue or publish")
	check(var_to_bytes(descriptor.nested)==descriptor_data and descriptor.keys==["borrowed"],"borrowed prepared descriptor remains intact")
	check(is_same(f.groups[0].data,held_data) and var_to_bytes(held_data.cpu_metadata)==held_bytes,"borrowed group data is unchanged")
	check(var_to_bytes(f.meshes[0].surfaces)==cpu_data and source_ids==f.nodes.map(func(n:Node)->int:return n.get_instance_id()),"CPU geometry and source identities stay unchanged")
	var counts:=work(batch);reports.append({"case":"permanent","members":f.nodes.size(),"groups":f.groups.size(),"work_count_instrumented":not counts.is_empty(),"work":counts})
	if "--require-work-ledger" in OS.get_cmdline_user_args():check(not counts.is_empty(),"required external instrumentation is present")
	if not counts.is_empty():
		check(counts.member_erases==0,"WORK: permanent close performs zero per-member index erases")
		check(counts.visual_erases==0,"WORK: permanent close performs zero per-visual catalog erases")
		check(counts.visibility_restores==0,"WORK: permanent close performs zero doomed-source visibility restores")
	else:print("SKIP exact-work counters: normal production source has no test instrumentation")
	Stream.prepare_map_disposal(f.map,self);stop_retirement()
	check(work(batch)==counts and catalogs_empty(batch),"repeated permanent disposal is idempotent")
	batch.end_scene_handoff(false);batch.end_scene_handoff(true);batch.begin_scene_handoff({"changed":false})
	check(batch._retiring_workers and not batch.is_processing() and catalogs_empty(batch),"late handoff finish/start cannot revive permanent disposal")
	batch.request_sync(f.nodes);batch.request_residency_sync(f.nodes,[],true)
	check(batch.sync_count==before_sync and catalogs_empty(batch),"closed service rejects late direct and residency requests")
	# Keep the negative control from running newly admitted test work after its recorded failure.
	batch._preparation.clear();batch._residency_bins.clear();batch._next_residency.clear()
	root.remove_child(f.map);root.add_child(f.map);batch._process(0.)
	check(not batch.is_processing() and batch._retiring_workers,"tree re-entry cannot revive a permanently closed worker service")
	release.post();drainer.set_process(true)
	var turns:=0
	while not lease.released and turns<1000:
		await process_frame;stop_retirement();turns+=1
	check(lease.released and not thread.is_alive(),"existing drainer joins the finished abandoned worker and releases its fence")
	batch._process(0.)
	check(batch.rebuild_count==before_rebuild and batch._workers.is_empty() and catalogs_empty(batch),"late background result never publishes into the closed owner")
	check(var_to_bytes(f.meshes[0].surfaces)==cpu_data and var_to_bytes(held_data.cpu_metadata)==held_bytes,"worker retirement preserves external CPU borrowers")
	f.map.free()
func ordinary_case()->void:
	var f:=fixture();var batch:Node=f.batch
	# Discard synthetic unfinished cursors; release itself remains production.
	batch._preparation.clear();batch._residency_bins.clear();batch._next_residency.clear()
	batch.release_sources([f.nodes[0]])
	check(uploads(f.meshes)==count_per_group,"ordinary single-source release restores the group's surviving sources")
	check(f.groups[0].members.all(func(n:Node)->bool:return not n.mesh is Cpu),"ordinary release keeps surviving source drawings usable")
	batch.clear()
	check(uploads(f.meshes)==f.meshes.size(),"ordinary editor clear continues restoring all remaining groups")
	batch.request_sync(f.nodes)
	check(not batch._preparation.is_empty(),"ordinary clear does not permanently reject new edit requests")
	batch.clear(false);f.map.free()
func never_entered_case()->void:
	var map:=Node3D.new();var batch:=Batch.new();batch.name="GroundRenderBatches";map.add_child(batch)
	# Disposal can happen before this scene has ever run _ready.
	Stream.prepare_map_disposal(map,self);stop_retirement()
	root.add_child(map)
	check(not RenderingServer.frame_pre_draw.is_connected(batch.update_cutout_visibility),"closed service never reconnects frame_pre_draw on its first tree entry")
	map.free()
func run()->void:
	if "--large" in OS.get_cmdline_user_args():count_per_group=256
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	await permanent_case();ordinary_case();never_entered_case()
	var service:=stop_retirement()
	if service!=null:
		var turns:=0
		while not service.pending.is_empty() and turns<10000:
			service._process(0.);service.set_process(false);await process_frame;turns+=1
		check(service.pending.is_empty(),"retained catalog and group owners drain on the existing retirement service")
		service.free()
	var report:Dictionary={"checks":checks,"failures":failures,"work":reports,"scope":"real WorldStream/Batch/worker retirement component; no wall-time acceptance"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BATCH_FAST_CLOSE56 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
