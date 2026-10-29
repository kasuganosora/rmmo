extends "res://tools/test_editor_native_texture_join_gpu.gd"
## Real source world, native-only target, production prefetch and transfer.
## Only the final cancellation sample gates a real SCN reader's return.
const CpuPrefetch=preload("res://scripts/world3d/cross_map_prefetch.gd")
const GpuPrefetch=preload("res://scripts/world3d/target_scene_prefetch.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const Presented=preload("res://scripts/util/frame_presentation.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var process_frames:=0

class GatedNativeRead extends RefCounted:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var content_root:String
	var entered:=false
	var owner:WeakRef
	func read(path:String,candidate:Dictionary)->Dictionary:
		var packet:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(path,candidate,content_root,Callable(),true,false,"",true)
		mutex.lock();entered=true;owner=weakref(packet.get("packed"));mutex.unlock()
		gate.wait()
		return packet
	func has_entered()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
	func alive()->bool:
		mutex.lock();var value:bool=owner!=null and owner.get_ref()!=null;mutex.unlock();return value
	func release_later()->void:
		OS.delay_msec(1000);gate.post()

func save_map(path:String,model:String="")->bool:
	var doc:=Document.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(64,.4,64))
	# The image plane must be strictly inside the selected core cell, rather
	# than on its z=0 boundary where the real near-first policy defers it.
	if not model.is_empty():doc.add_asset({"asset_path":model},Vector3(0,1,8))
	doc.map_meta={"spawn":[0,.9,6],"map_ref":path.get_file().get_basename()}
	return doc.save(path)==OK

func cpu_ready(service:Node)->bool:
	var deadline:=Time.get_ticks_msec()+30000
	while service._packet==null and Time.get_ticks_msec()<deadline:await process_frame
	return service._packet!=null

func target_ready(service:Node)->bool:
	var deadline:=Time.get_ticks_msec()+60000
	while not service._gpu_ready and Time.get_ticks_msec()<deadline:
		service._touched=Time.get_ticks_msec();await process_frame
	return service._gpu_ready

func native_identities(service:Node)->Dictionary:
	# Resource locals end with this observation call. The test retains only IDs
	# and WeakRefs while it measures the last production owner being released.
	var meshes:Array=[];var textures:Dictionary={};var owners:Array=[];var seen:Dictionary={}
	for mesh:Mesh in service._warm:
		meshes.append(mesh.get_rid().get_id())
		owners.append({"kind":"mesh","id":mesh.get_instance_id(),"class":mesh.get_class(),"weak":weakref(mesh)})
		for surface:int in mesh.get_surface_count():
			var material:Material=mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var texture:Texture2D=material.albedo_texture
				if texture!=null and texture.is_class("StreamedTexture2D"):
					check(texture.call("is_streaming_active"),"actual private draw uses a registered streamed texture")
					textures[texture.get_instance_id()]={"rid":texture.get_rid().get_id(),"weak":weakref(texture)}
					for row:Dictionary in [{"kind":"material","owner":material},{"kind":"texture","owner":texture}]:
						if not seen.has(row.owner.get_instance_id()):
							seen[row.owner.get_instance_id()]=true
							owners.append({"kind":row.kind,"id":row.owner.get_instance_id(),"class":row.owner.get_class(),"weak":weakref(row.owner)})
	return {"meshes":meshes,"textures":textures,"owners":owners}

func watch_packed(values:Dictionary)->Array:
	var result:Array=[]
	for path:String in values:
		var packed:PackedScene=values[path]
		result.append({"kind":"packed","path":path,"id":packed.get_instance_id(),"class":packed.get_class(),"weak":weakref(packed)})
	return result

func owner_sample(owners:Array)->Dictionary:
	var rows:Array=[]
	for row:Dictionary in owners:
		rows.append({"kind":row.kind,"class":row["class"],"id":row.id,"alive":row.weak.get_ref()!=null})
	return {"engine_bytes":Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"),"owners":rows}

func same_warmed_meshes(scene:Node,ids:Array)->bool:
	for spec:Dictionary in scene.get_meta("stream_library",[]):
		var mesh:Mesh=spec.mesh.restore() if spec.mesh is CpuMesh else spec.mesh
		if mesh.get_rid().get_id() not in ids:return false
	return true

func finish_target()->void:
	report.checks=checks;report.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TARGET_PREFETCH_LIFETIME ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(180).timeout.connect(func():printerr("TARGET_PREFETCH_TIMEOUT");quit(2))
	process_frame.connect(func():process_frames+=1)
	Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false
	report.engine_initial=Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used")
	var original:=fixture()
	for part:MeshInstance3D in original.get_children():
		var old:PrimitiveMesh=part.mesh;var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,old.get_mesh_arrays())
		mesh.surface_set_material(0,old.material);part.mesh=mesh
	var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"publish real split-native products before target loading")
	var normal_model:=publish_fixture(original,prepared,"target_normal")
	var cancel_model:=publish_fixture(original,prepared,"target_cancel")
	Products.restore(prepared);original.free();prepared.clear()
	var map_dir:=folder.path_join("temporary_maps");DirAccess.make_dir_recursive_absolute(map_dir)
	var source_map:=map_dir.path_join("source.gltf");var target_map:=map_dir.path_join("target.gltf");var cancel_map:=map_dir.path_join("cancel.gltf")
	check(save_map(source_map) and save_map(target_map,normal_model) and save_map(cancel_map,cancel_model),"save isolated real source and native-only target maps")
	if not failures.is_empty():finish_target();return
	var source_sha:=FileAccess.get_sha256(source_map);var target_sha:=FileAccess.get_sha256(target_map)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:=root.get_node("GameSession");session.world3d_map_path=source_map;session.world3d_spawn=Vector3(0,.9,6)
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.go_world_3d()
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):break
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	var world:Node=current_scene
	check(is_instance_valid(world) and world.has_method("is_world_ready") and world.is_world_ready() and is_instance_valid(world._player),"real world completes normal entry with an actual player and source geometry")
	if not failures.is_empty():finish_target();return
	world._update_approach_preparation();world._approach_clock=-1000.
	var target:Node=world._target_scene_prefetch;var cpu:Node=world._cross_map_prefetch
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	var ledger:RefCounted=deferred._admission if deferred!=null else world._prefetch_fallback_ledger
	if deferred==null:ledger.byte_limit=GpuPrefetch.LEASE_BYTES+CpuPrefetch.LEASE_BYTES
	var destination:=Vector3(0,.9,6)
	check(target==GpuPrefetch.for_world(world) and target.get_parent()==Drainer.for_tree(self),"production world uses its stable root-owned prefetch service")
	check(cpu.request(target_map,destination,ledger) and await cpu_ready(cpu),"production CPU prefetch discovers the native-only target")
	check(cpu._packet!=null and not cpu._packet.scene_plan.is_empty(),"target plan accepts the bounded native fixture")
	if not failures.is_empty():world.free();finish_target();return
	check(target.request(target_map,destination,ledger,cpu),"production target acquires the source runtime admission")
	var loaded:Dictionary={};var observed_owners:Array=[]
	target._loader.finished.connect(func(_scene:Node,_path:String,_error:String):
		loaded.submitted=Presented.clock().submitted;loaded.completed=Presented.clock().completed
		observed_owners.append_array(watch_packed(target._loader._private_assets))
		loaded.profile=target._loader._profile.duplicate(true))
	check(await target_ready(target),"normal prefetch completes native binding and real private draw warmup")
	if not failures.is_empty():world.free();finish_target();return
	check(not loaded.is_empty() and Presented.clock().completed>=int(loaded.submitted)+2,"park occurs after two actual presentation serials, not process ticks")
	check(loaded.profile.initial_asset_paths==1 and loaded.profile.native_texture_preparation.get("pool",{}).get("streamed_loads",0)==2,"normal initial coordinator binds the selected native model and loads its two real STEX products")
	check(ledger.reserved_bytes==GpuPrefetch.LEASE_BYTES and ledger.active_workers()==0,"READY parks workers while retaining its full outer lease")
	var identities:=native_identities(target)
	observed_owners.append_array(identities.owners)
	var mesh_ids:Array=identities.meshes;var texture_ids:Dictionary=identities.textures;identities.clear()
	report.owners_ready=owner_sample(observed_owners)
	check(not texture_ids.is_empty() and not mesh_ids.is_empty(),"prepared native texture and mesh identities are observed")
	report.normal_loaded=loaded;report.ready_presented=Presented.clock().completed
	var hits:int=target.profile.hits
	check(await world.transfer_map(target_map,destination),"real confirmed cross-map transfer adopts the prepared target")
	world._approach_clock=-1000.
	check(target.profile.hits==hits+1 and world._map_root.get_meta("gpu_preload_hit",false),"production transfer consumed the exact prefetched scene")
	check(target._ledger==null and ledger.reserved_bytes==0 and not world._map_root.has_meta("prefetched_gpu_owners"),"after target presentation, speculative admission and temporary warm alias are gone")
	check(same_warmed_meshes(world._map_root,mesh_ids) and texture_ids.values().all(func(item):return item.weak.get_ref()!=null),"adopted target preserves warmed mesh and native texture owners")
	report.owners_adopted=owner_sample(observed_owners)
	check(FileAccess.get_sha256(source_map)==source_sha and FileAccess.get_sha256(target_map)==target_sha,"prefetch and adoption do not edit authored map bytes")
	# A second, cold geometry transaction is gated only after its real SCN read.
	deferred=world._map_root.get_node_or_null("DeferredAssets")
	ledger=deferred._admission if deferred!=null else world._prefetch_fallback_ledger
	if deferred==null:ledger.byte_limit=GpuPrefetch.LEASE_BYTES+CpuPrefetch.LEASE_BYTES
	check(cpu.request(cancel_map,destination,ledger) and await cpu_ready(cpu),"prepare separate cold target before world-exit cancellation")
	var gate:=GatedNativeRead.new();gate.content_root=folder
	var intercept:=func(node:Node):
		if node.get_parent()==target and node.get_script()==load("res://scripts/world3d/map_loader.gd"):
			node._model_preparation.candidate_reader=gate.read
	node_added.connect(intercept)
	check(target.request(cancel_map,destination,ledger,cpu),"dispatch real private loader for world-exit smoke")
	node_added.disconnect(intercept)
	deadline=Time.get_ticks_msec()+30000
	while not gate.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(gate.has_entered() and gate.alive(),"real native SCN owner is alive while its worker return is gated")
	if not gate.has_entered():gate.gate.post();world.free();finish_target();return
	var releaser:=Thread.new();check(releaser.start(gate.release_later)==OK,"independent releaser bounds the gated worker")
	var before_frames:=process_frames;var began:=Time.get_ticks_usec();world.free();world=null
	var elapsed:=Time.get_ticks_usec()-began
	report.owners_world_exited=owner_sample(observed_owners)
	check(elapsed<250000 and gate.alive() and ledger.reserved_bytes==GpuPrefetch.LEASE_BYTES,"real world exit returns while native worker and original lease remain live")
	# Model/native paths were captured at dispatch; removing the temporary map
	# after consumer exit must not force a session lookup or a publication retry.
	session.world3d_map_path="";session.clear_prepared_world3d()
	check(DirAccess.remove_absolute(cancel_map)==OK,"remove only the cancelled test map after world exit")
	deadline=Time.get_ticks_msec()+10000
	while (is_instance_valid(target) or ledger.reserved_bytes>0 or releaser.is_alive()) and Time.get_ticks_msec()<deadline:await process_frame
	if not releaser.is_alive():releaser.wait_to_finish()
	check(not is_instance_valid(target) and not gate.alive() and ledger.reserved_bytes==0,"cancelled private loader and scene retire before the outer admission returns")
	check(process_frames>before_frames+2,"real rendered frames continue during detached worker retirement")
	report.world_exit={"call_us":elapsed,"frames_until_retired":process_frames-before_frames,"lease_after":ledger.reserved_bytes,"owner_alive_after":gate.alive(),"worker_hold_ms":1000,"performance_claim":false}
	loaded.clear()
	await wait_engine_zero("prefetch_lifetime")
	report.owners_retired=owner_sample(observed_owners)
	check(texture_ids.values().all(func(item):return item.weak.get_ref()==null),"last native Texture owners disappear after real world and private job retirement")
	texture_ids.clear()
	finish_target()
