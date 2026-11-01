extends "res://tools/test_stream_batch_arrival_pipeline.gd"
## Real own-world SubViewport -> live World Node3D transfer. Inherit only the
## existing final-GPU-commit substitution, all actual pipeline/lifetime code.

class GuardPlayer extends CharacterBody3D:
	var geometry_blocked:=false
	var input_locked:=false

class GuardWorld extends "res://scripts/world3d/world_3d.gd":
	var failure_covers:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
	func _hold_transfer_presentation(_cover:CanvasLayer)->bool:
		failure_covers+=1;_player.input_locked=true;_player.set_physics_process(false);return false

func fixture()->Dictionary:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.disable_3d=true;root.add_child(viewport)
	var f:=super.fixture()
	f.host.reparent(viewport);f.host.position=Vector3(3,0,5)
	var world:=Node3D.new();world.name="HandoffWorld";root.add_child(world);world.position=Vector3(-2,0,7)
	f.viewport=viewport;f.world=world;f.stage=f.host
	return f

func transfer(f:Dictionary)->bool:
	# Baseline uses exactly the currently shipped reparent. Candidate must enter
	# through the same production wrapper that World.transfer_map will call.
	var api:RefCounted=Stream.new()
	var wrapped:bool=api.has_method("reparent_prepared_map")
	var ok:=true
	if wrapped:ok=bool(api.call("reparent_prepared_map",f.map,f.world))
	else:f.map.reparent(f.world)
	for body:Node in f.map.get_meta("stream_bodies",{}).values():
		if is_instance_valid(body):body.reparent(f.world)
	f.host=f.world
	check(f.map.get_parent()==f.world and f.map.is_inside_tree(),"actual prepared root is attached to World","fixture")
	return ok

func dispose(f:Dictionary)->void:
	check(not f.batch._scene_handoff and f.batch._handoff_parents.is_empty() and not f.batch._handoff_parent_changed.is_valid(),"handoff observation is disarmed before fixture cleanup")
	f.batch.clear(false)
	check(f.batch._source_parents.is_empty(),"group parent weak accounting empties with actual groups","work")
	super.dispose(f)
	if is_instance_valid(f.viewport):f.viewport.free()
	if is_instance_valid(f.world):f.world.free()

func source_receipt(f:Dictionary)->Dictionary:
	var result:Dictionary={}
	for id:String in f.map.get_meta("stream_meshes"):
		var node:MeshInstance3D=f.map.get_meta("stream_meshes")[id]
		var material:Material=node.get_active_material(0)
		result[id]={"node":node.get_instance_id(),"mesh":node.mesh.get_instance_id(),"transform":node.global_transform,"material":material.get_instance_id() if material!=null else 0}
	return result

func equal_receipt(a:Dictionary,b:Dictionary)->bool:
	if a.size()!=b.size():return false
	for id:String in a:
		if not b.has(id) or a[id].node!=b[id].node or a[id].mesh!=b[id].mesh or a[id].material!=b[id].material or not a[id].transform.is_equal_approx(b[id].transform):return false
	return true

func groups_receipt(batch:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batch.groups:
		var group:Dictionary=batch.groups[key]
		result[key]={"generation":group.generation,"visual":group.visual.get_instance_id() if is_instance_valid(group.get("visual")) else 0}
	return result

func settled_handoff()->void:
	var f:=fixture();append(f,make_specs(f,64),"64-group staged map")
	if not await settle(f,NEAR,"64-group entry readiness"):
		dispose(f);return
	var before:=work(f.batch);var sources:=source_receipt(f);var groups:=groups_receipt(f.batch)
	var old_world:World3D=f.map.get_world_3d();var geometry:=snapshot(f.batch)
	var ledger:RefCounted=f.map.get_meta(Stream.BATCH_ARRIVALS_META)
	var adoption:RefCounted=f.map.get_meta("runtime_adoption_changes")
	check(groups.size()==64 and not adoption.dirty() and not ledger.has_pending(),"64 complete groups have settled adoption/arrival state","fixture")
	var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape)
	f.stage.add_child(body);body.global_position=Vector3(8,0,8)
	f.map.get_meta("stream_bodies")["handoff_probe_body"]=body
	var body_id:=body.get_instance_id();var shape_id:=shape.shape.get_instance_id();var body_pose:=body.global_transform
	check(PhysicsServer3D.body_get_space(body.get_rid())==old_world.space,"collision probe belongs to staging physics world","fixture")
	f.batch.set_process(false)
	check(transfer(f),"controlled handoff succeeds")
	check(not f.batch.is_processing(),"handoff preserves deliberately paused automatic processing")
	check(groups_receipt(f.batch)==groups,"all 64 group generations and visuals survive handoff","work")
	check(equal_receipt(sources,source_receipt(f)),"same source Node/Mesh/Material identities and global transforms survive handoff")
	check(not adoption.dirty() and not ledger.has_pending(),"handoff does not fabricate adoption or owner loss","work")
	check(f.map.get_world_3d()!=old_world and f.map.get_world_3d()==f.world.get_world_3d(),"root resolves the destination World3D after real viewport migration")
	var visual_worlds:=true
	for group:Dictionary in f.batch.groups.values():visual_worlds=visual_worlds and group.visual.get_world_3d()==f.world.get_world_3d() and group.visual.get_viewport()==f.world.get_viewport()
	check(visual_worlds and f.batch.groups.size()==64,"retained visuals resolve destination viewport and World3D")
	check(body.get_instance_id()==body_id and shape.shape.get_instance_id()==shape_id and body.global_transform.is_equal_approx(body_pose) and PhysicsServer3D.body_get_space(body.get_rid())==f.world.get_world_3d().space,"collision identity/shape/pose survive and physics space updates")
	# This service probe tests the caller's existing body-reparent step; it is
	# not an authored source ID and must not enter source candidate planning.
	f.map.get_meta("stream_bodies").erase("handoff_probe_body");body.free()
	f.batch.set_process(true)
	await settle(f,NEAR,"post-handoff steady")
	check(work(f.batch).prepared==before.prepared and work(f.batch).packed==before.packed and work(f.batch).sync_count==before.sync_count,"unchanged handoff adds zero source preparation/packing/checkpoints","work")
	check(snapshot(f.batch)==geometry,"handoff preserves actual prepared geometry signatures")
	compare_full(f,"handoff output")
	cases.append({"case":"settled_64_group_handoff","before":before,"after":work(f.batch),"arrivals":ledger.profile.duplicate()})
	ledger=null;adoption=null;dispose(f)

func active_worker_handoff()->void:
	var f:=fixture();f.batch.set_process(false);append(f,make_specs(f,1),"handoff active worker")
	for turn:int in 100:
		Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
		if f.map.has_meta("stream_chunk"):break
	while not f.batch._preparation.is_empty():f.batch._prepare_step(0)
	f.batch._build_next(true)
	check(f.batch._workers.size()==1,"real worker exists before handoff","fixture")
	var worker_id:int=f.batch._workers[0].thread.get_instance_id() if not f.batch._workers.is_empty() else 0
	var before:=work(f.batch);var leases:int=f.batch._retired_leases.size()
	transfer(f)
	check(f.batch._workers.size()==1 and f.batch._workers[0].thread.get_instance_id()==worker_id,"handoff retains the exact unaccepted worker result owner","work")
	check(f.batch._retired_leases.size()==leases and not f.batch._retiring_workers,"handoff neither abandons a worker lease nor retires the live batcher","work")
	f.batch.set_process(true);await settle(f,NEAR,"handoff worker commits")
	check(f.batch.worker_receipt_commits>0 and work(f.batch).prepared==before.prepared,"the preserved real worker commits without repeated source preparation","work")
	append(f,make_specs(f,1),"next work after handoff");await settle(f,NEAR,"next work after handoff")
	check(f.batch.prepared_source_visits==16 and f.batch.groups.size()==2,"same batcher continues accepting fresh independent work","work")
	compare_full(f,"handoff worker and subsequent work")
	cases.append({"case":"active_worker_handoff","before":before,"after":work(f.batch)})
	dispose(f)

func offline_edit()->void:
	var f:=fixture();append(f,make_specs(f,2),"offline baseline");await settle(f,NEAR,"offline baseline")
	transfer(f);await settle(f,NEAR,"successful handoff before ordinary offline edit")
	var old:=snapshot(f.batch);var old_ids:=membership(f.batch);var changed:=BoxMesh.new();changed.size=Vector3(.9,.5,.4);changed.material=f.mesh.material
	f.map.get_parent().remove_child(f.map)
	check(f.batch.groups.is_empty() and f.batch._retiring_workers,"ordinary whole-root exit still invalidates groups and retires workers")
	for node:MeshInstance3D in f.map.get_meta("stream_meshes").values():node.mesh=changed
	f.world.add_child(f.map);f.host=f.world
	await settle(f,NEAR,"ordinary detached edit returns")
	check(membership(f.batch)==old_ids and snapshot(f.batch)!=old,"offline same-node edit rebuilds changed geometry")
	compare_full(f,"offline edit after real detach")
	cases.append({"case":"offline_same_node_mutation","after":work(f.batch)})
	dispose(f)

func loss_during_handoff()->void:
	var f:=fixture();append(f,make_specs(f,2),"handoff deletion baseline");await settle(f,NEAR,"handoff deletion baseline")
	var meshes:Dictionary=f.map.get_meta("stream_meshes");var id:String=meshes.keys()[1]
	var victim:Node=meshes[id];var old_id:=victim.get_instance_id();var key:String=f.batch._member_groups[id]
	var old_count:int=f.map.get_child_count(true)
	# tree_exited is the actual offline interval inside Node.reparent. Child
	# deletion here emits no source tree_exiting; equal count hides it from a
	# naive before/after count guard. Production must reject immutable reuse.
	f.map.tree_exited.connect(func():
		victim.free()
		var replacement:=Node3D.new();replacement.set_meta("stream_instance",true);f.map.add_child(replacement)
	,CONNECT_ONE_SHOT)
	transfer(f)
	check(f.map.get_child_count(true)==old_count,"handoff deletion and unrelated arrival preserve direct child count","fixture")
	check(not f.batch.groups.has(key),"actual source loss inside handoff invalidates old batch immediately")
	await settle(f,NEAR,"handoff deleted source repairs")
	var repaired:Variant=f.map.get_meta("stream_meshes").get(id)
	check(is_instance_valid(repaired) and repaired.get_instance_id()!=old_id,"handoff exception repairs lost canonical owner")
	compare_full(f,"actual loss during handoff")
	cases.append({"case":"loss_inside_handoff","after":work(f.batch)})
	dispose(f)

func loss_after_handoff()->void:
	var f:=fixture();append(f,make_specs(f,2),"post-handoff deletion baseline");await settle(f,NEAR,"post-handoff deletion baseline")
	transfer(f);await settle(f,NEAR,"post-handoff before deletion")
	var meshes:Dictionary=f.map.get_meta("stream_meshes");var id:String=meshes.keys()[1];var key:String=f.batch._member_groups[id]
	meshes[id].free()
	check(not f.batch.groups.has(key),"source lifetime watcher remains connected after handoff")
	var service:=Node3D.new();service.set_meta("stream_instance",true);f.map.add_child(service)
	await settle(f,NEAR,"post-handoff same-count deletion repair")
	compare_full(f,"post-handoff deletion")
	cases.append({"case":"post_handoff_deletion","after":work(f.batch)})
	dispose(f)

func pending_adoption()->void:
	var f:=fixture();append(f,make_specs(f,2),"pending adoption baseline");await settle(f,NEAR,"pending adoption baseline")
	var before:=work(f.batch)
	for part:int in 4:f.map.add_child(source_node(f.mesh,"during_stage_%d"%part,"during_stage",part))
	transfer(f);await settle(f,NEAR,"pending adoption crosses handoff")
	check(f.map.get_meta("stream_meshes").size()==20,"already pending unregistered roots survive controlled handoff")
	check(f.batch.prepared_source_visits-int(before.prepared)==4,"pending adoption prepares only actual four arrivals","work")
	compare_full(f,"pending adoption survives handoff")
	cases.append({"case":"pending_adoption","before":before,"after":work(f.batch)})
	dispose(f)

func nested_component_loss()->void:
	var f:=fixture();append(f,make_specs(f,1),"nested component root");await settle(f,NEAR,"nested component root")
	var carrier:Node=f.map.get_meta("stream_meshes").values()[0]
	var middle:=Node3D.new();middle.name="ActualComponentParent";carrier.add_child(middle)
	var components:Array=[]
	for part:int in 4:
		var node:=source_node(f.mesh,"nested_component_%d"%part,"nested_component_house",part)
		middle.add_child(node);components.append(node)
	carrier.set_meta("model_component_batch_sources",components)
	f.map.set_meta("stream_children",-1)
	await settle(f,NEAR,"real component expansion")
	var victim:Node=components[1];var key:String=f.batch._member_groups[str(victim.name)]
	check(f.batch.groups[key].members.size()==4,"actual model_component_batch_sources expands into four nested batch members","fixture")
	var root_count:int=f.map.get_child_count(true);var middle_count:=middle.get_child_count(true)
	f.map.tree_exited.connect(func():
		victim.free()
		var replacement:=Node3D.new();middle.add_child(replacement)
	,CONNECT_ONE_SHOT)
	transfer(f)
	check(f.map.get_child_count(true)==root_count and middle.get_child_count(true)==middle_count,"nested loss preserves both root and intermediate child counts","fixture")
	var invalidated:bool=not f.batch.groups.has(key)
	check(invalidated,"nested component deletion during handoff invalidates its old batch immediately")
	if not invalidated:
		cases.append({"case":"nested_component_handoff_loss","invalidated":false});dispose(f);return
	await settle(f,NEAR,"nested component handoff repair")
	var oracle_host:=Node3D.new();root.add_child(oracle_host)
	var oracle:=NoGpuCommitBatch.new();oracle_host.add_child(oracle);oracle.set_process(false)
	oracle.request_sync(f.map.get_meta("stream_meshes").values());oracle.flush()
	check(snapshot(f.batch)==snapshot(oracle),"nested component repair matches full generic expansion oracle")
	oracle.clear(false);oracle_host.free()
	cases.append({"case":"nested_component_handoff_loss","invalidated":true,"after":work(f.batch)})
	dispose(f)

func nested_unadmitted(singleton:bool)->void:
	var f:=fixture();append(f,make_specs(f,1),"unadmitted component root");await settle(f,NEAR,"unadmitted component root")
	var carrier:Node=f.map.get_meta("stream_meshes").values()[0]
	var middle:=Node3D.new();carrier.add_child(middle);var components:Array=[]
	for part:int in (1 if singleton else 4):
		var node:=source_node(f.mesh,"scratch_component_%d"%part,"scratch_house",part)
		middle.add_child(node);components.append(node)
	carrier.set_meta("model_component_batch_sources",components);f.map.set_meta("stream_children",-1)
	if singleton:await settle(f,NEAR,"completed filtered singleton")
	else:
		f.batch.set_process(false)
		for turn:int in 100:
			Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
			if f.map.has_meta("stream_chunk"):break
		for turn:int in 2000:
			if f.batch._preparation.get("phase","")=="filter":break
			f.batch._prepare_step(1)
		check(f.batch._preparation.get("phase","")=="filter","partial nested preparation reaches filter before group admission","fixture")
	check(not f.batch._member_groups.has("scratch_component_0"),"target nested source has no admitted group lifetime watcher","fixture")
	var victim:Node=components[0]
	f.map.tree_exited.connect(func():
		victim.free()
		var replacement:=source_node(f.mesh,"scratch_component_0","scratch_house",0);replacement.position+=Vector3(1,0,0)
		middle.add_child(replacement);components[0]=replacement
		if singleton:
			var added:=source_node(f.mesh,"scratch_component_1","scratch_house",1);middle.add_child(added);components.append(added)
	,CONNECT_ONE_SHOT)
	transfer(f)
	check(f.map.get_meta(Stream.BATCH_ARRIVALS_META).has_pending(),"unadmitted "+("completed singleton" if singleton else "partial prep")+" nested mutation revokes immutable reuse")
	f.batch.set_process(true);await settle(f,NEAR,"unadmitted nested mutation repair")
	var oracle_host:=Node3D.new();root.add_child(oracle_host)
	var oracle:=NoGpuCommitBatch.new();oracle_host.add_child(oracle);oracle.set_process(false)
	oracle.request_sync(f.map.get_meta("stream_meshes").values());oracle.flush()
	check(snapshot(f.batch)==snapshot(oracle),"unadmitted "+("singleton becomes group" if singleton else "partial preparation")+" equals full expansion oracle")
	oracle.clear(false);oracle_host.free()
	cases.append({"case":"nested_unadmitted","singleton":singleton,"after":work(f.batch)})
	dispose(f)

func attachment_failure(queued_during_exit:bool)->void:
	var f:=fixture();append(f,make_specs(f,1),"handoff rejection baseline");await settle(f,NEAR,"handoff rejection baseline")
	f.world.free();var world:=GuardWorld.new();f.world=world
	if queued_during_exit:root.add_child(world)
	var player:=GuardPlayer.new();world.add_child(player);world._player=player
	world._ready_for_play=true;world._transfer_pending=true
	var deferred:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();deferred.name="DeferredAssets";f.map.add_child(deferred)
	check(deferred.begin_scene_handoff(),"real quiesced deferred loader enters handoff","fixture")
	if queued_during_exit:f.map.tree_exited.connect(func():f.map.queue_free(),CONNECT_ONE_SHOT)
	var cover:=CanvasLayer.new();root.add_child(cover)
	var ok:bool=world._adopt_transfer_target(f.map,deferred,cover)
	check(not ok and world.failure_covers==1 and not world._ready_for_play,"production target guard rejects unsafe attachment without declaring readiness")
	check(world._transfer_pending and world._geometry_wait_locked and player.geometry_blocked and player.input_locked,"failed post-disposal attachment keeps the failure cover and movement lock")
	check(not deferred._scene_handoff and not f.batch._scene_handoff and f.batch._handoff_parents.is_empty(),"failure path releases actual deferred and batch handoff flags")
	check(is_instance_valid(f.viewport),"failed adoption retains staging lifetime for failure presentation")
	if queued_during_exit:
		check(f.map.is_queued_for_deletion() and f.batch.groups.is_empty(),"queued destruction during exit refuses immutable reuse and clears derived groups")
		f.host=world
	else:check(f.map.get_parent()==f.stage and f.map.is_inside_tree(),"invalid destination rejects before detaching the staged root")
	cases.append({"case":"production_attachment_failure","queued_during_exit":queued_during_exit})
	cover.free();dispose(f)

func run()->void:
	saved_frame_budget=FrameBudget.enabled;FrameBudget.enabled=false
	await settled_handoff()
	await active_worker_handoff()
	await offline_edit()
	await loss_during_handoff()
	await loss_after_handoff()
	await pending_adoption()
	await nested_component_loss()
	await nested_unadmitted(false)
	await nested_unadmitted(true)
	await attachment_failure(false)
	await attachment_failure(true)
	FrameBudget.enabled=saved_frame_budget
	var result:={"checks":checks,"failures":failures,"failures_by_kind":failures_by_kind,"cases":cases,"assertions":assertions,"mock_boundary":"inherited final GPU batch commit substitution only; actual Node reparent, World3D/physics lifecycle, Stream.sync and worker pipelines"}
	if not output_path.is_empty():FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("STREAM_SCENE_HANDOFF ",JSON.stringify(result));quit(1 if failures else 0)
