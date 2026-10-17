extends SceneTree
## Run only with run_godot_background.py on a private desktop.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const EntryPlan=preload("res://scripts/world3d/entry_plan.gd")
var failures:=0
var directory:=""
var callbacks:=0
var world:Node
var _diagnostic_refs:Dictionary={}
var _bake_ids:Dictionary={}
var indexed_fixtures:Dictionary={}
const LoaderScript=preload("res://scripts/world3d/map_loader.gd")
const NavigationScript=preload("res://scripts/world3d/world_navigation.gd")
const DrainerScript=preload("res://scripts/world3d/asset_worker_drainer.gd")
const DeferredScript=preload("res://scripts/world3d/deferred_asset_loader.gd")

func remember_ref(value:Variant,label_:String)->void:
	if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is RefCounted:return
	var id:int=value.get_instance_id()
	if _diagnostic_refs.has(id):return
	var script:Script=value.get_script()
	var path:String=script.resource_path if script!=null else "<native>"
	# Store scalars only. These diagnostics must not prolong a candidate's life.
	_diagnostic_refs[id]={"label":label_,"script":path}
	print("TRANSFER_REF ",JSON.stringify({"id":str(id),"id_hi":(id>>32)&0xffffffff,"id_lo":id&0xffffffff,"label":label_,"script":path,"class":value.get_class(),"refs":value.get_reference_count()}))

func survey_script_refs(value:Object,label_:String,depth:int=0)->void:
	# Inspect script-owned helper/weak-reference members, not native render data
	# or large authoring arrays. This covers initial character/world helpers too.
	if depth>2 or value.get_script()==null:return
	for property:Dictionary in value.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE==0:continue
		var member:Variant=value.get(property.name)
		if typeof(member)!=TYPE_OBJECT or not is_instance_valid(member) or not member is RefCounted:continue
		var unseen:bool=not _diagnostic_refs.has(member.get_instance_id())
		remember_ref(member,label_+"."+str(property.name))
		if unseen:survey_script_refs(member,label_+"."+str(property.name),depth+1)

func sample_refs()->Dictionary:
	var status:Dictionary={"loaders":[],"navigation":[],"drainer_jobs":0,"active_bakes":[]}
	var nodes:Array[Node]=[root]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		var label_:String=str(node.get_path())
		# Do not inspect worker-owned loader fields via general introspection.
		if node.get_script()!=LoaderScript:survey_script_refs(node,label_)
		if node.get_script()==LoaderScript:
			var row:Dictionary={"node":label_,"path":node._path,"queued":node.is_queued_for_deletion(),"workers":{}}
			for field:String in ["_thread","_cache_thread","_mesh_cache_thread","_mesh_read_thread","_texture_thread","_terrain_thread","_index_thread"]:
				var worker:Thread=node.get(field)
				row.workers[field]=worker!=null and worker.is_alive()
			remember_ref(node._model_preparation,label_+"._model_preparation")
			# The loading thread owns these fields until it has finished.
			if node._thread==null or not node._thread.is_alive():
				remember_ref(node._source_snapshot,label_+"._source_snapshot")
				remember_ref(node._terrain_context,label_+"._terrain_context")
			status.loaders.append(row)
		elif node.get_script()==NavigationScript:
			var row:Dictionary={"node":label_,"phase":node._phase,"fully_ready":node.fully_ready,"bake_pending":node._bake_pending,"baking":false,"nearby_baking":false,"source_jobs":node._source_jobs.size(),"orphan_sources":node._orphan_sources.size(),"workers":{}}
			if node._baking_mesh!=null:
				row.baking=NavigationServer3D.is_baking_navigation_mesh(node._baking_mesh)
				_bake_ids[node._baking_mesh.get_instance_id()]=label_+"._baking_mesh"
			if node._nearby!=null:
				row.nearby_baking=NavigationServer3D.is_baking_navigation_mesh(node._nearby.mesh)
				_bake_ids[node._nearby.mesh.get_instance_id()]=label_+"._nearby.mesh"
			for field:String in ["_surface_index_worker","_face_worker","_cache_writer"]:
				var worker:Thread=node.get(field)
				row.workers[field]=worker!=null and worker.is_alive()
			remember_ref(node._nearby,label_+"._nearby")
			remember_ref(node._surface_index,label_+"._surface_index")
			for job:RefCounted in node._source_jobs.values():remember_ref(job,label_+"._source_jobs")
			for job:RefCounted in node._orphan_sources:remember_ref(job,label_+"._orphan_sources")
			status.navigation.append(row)
		elif node.get_script()==DrainerScript:
			status.drainer_jobs+=node.jobs.size()
			for job:Dictionary in node.jobs:remember_ref(job.token,label_+".cancel_token")
		elif node.get_script()==DeferredScript:
			remember_ref(node._doc,label_+"._doc")
			for job:Dictionary in node._jobs.values():remember_ref(job.token,label_+".worker_token")
	# Failed transfers can already have destroyed their navigation Node while
	# the engine still owns its async bake. Track IDs, never persistent strong refs.
	for id:int in _bake_ids:
		if not is_instance_id_valid(id):continue
		var mesh:NavigationMesh=instance_from_id(id) as NavigationMesh
		if mesh!=null and NavigationServer3D.is_baking_navigation_mesh(mesh):status.active_bakes.append({"id":str(id),"owner":_bake_ids[id]})
	return status

func cleanup_world()->void:
	var began:=Time.get_ticks_msec();var deadline:int=began+30000
	var status:Dictionary
	while true:
		status=sample_refs()
		var idle:bool=status.active_bakes.is_empty()
		for nav:Dictionary in status.navigation:
			if nav.baking or nav.nearby_baking or nav.source_jobs>0 or nav.orphan_sources>0 or nav.workers.values().has(true):idle=false
		if idle:break
		if Time.get_ticks_msec()>=deadline:
			check(false,"navigation background cleanup reached deadline")
			print("TRANSFER_CLEANUP_NAV_TIMEOUT ",JSON.stringify(status));break
		await process_frame
	print("TRANSFER_CLEANUP_BEFORE_FREE ",JSON.stringify(status))
	var world_id:int=world.get_instance_id()
	world.queue_free();current_scene=null;world=null
	deadline=Time.get_ticks_msec()+30000
	while true:
		status=sample_refs()
		if not is_instance_id_valid(world_id) and status.loaders.is_empty() and status.drainer_jobs==0 and status.active_bakes.is_empty():break
		if Time.get_ticks_msec()>=deadline:
			check(false,"world, map-loader retirement and drainer cleanup reached deadline")
			print("TRANSFER_CLEANUP_RETIRE_TIMEOUT ",JSON.stringify(status));break
		await process_frame
	check(not is_instance_id_valid(world_id) and status.loaders.is_empty() and status.drainer_jobs==0 and status.active_bakes.is_empty(),"world freed, all map loaders retired, navigation bakes finished and orphan asset workers joined")
	var survivors:Array=[]
	for id:int in _diagnostic_refs:
		if is_instance_id_valid(id):survivors.append({"id":str(id),"id_hi":(id>>32)&0xffffffff,"id_lo":id&0xffffffff,"candidate":_diagnostic_refs[id]})
	print("TRANSFER_CLEANUP_FINISHED ",JSON.stringify({"elapsed_ms":Time.get_ticks_msec()-began,"status":status,"live_candidates":survivors}))

static func ordinary_fixture(path:String)->Error:
	# Raw, self-contained glTF 2.0 cube. Godot's scene exporter declares
	# GODOT_single_root, which the conservative deferred manifest rejects.
	var binary:=PackedFloat32Array([-.5,-.5,-.5,.5,-.5,-.5,.5,.5,-.5,-.5,.5,-.5,-.5,-.5,.5,.5,-.5,.5,.5,.5,.5,-.5,.5,.5]).to_byte_array()
	binary.append_array(PackedInt32Array([0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]).to_byte_array())
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Crate","mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1,"material":0}]}],"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[.5,.3,.15,1],"metallicFactor":0,"roughnessFactor":.8}}],"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":8,"min":[-.5,-.5,-.5],"max":[.5,.5,.5]},{"bufferView":1,"componentType":5125,"type":"SCALAR","count":36}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":96},{"buffer":0,"byteOffset":96,"byteLength":144}],"buffers":[{"byteLength":binary.size()}]}
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+bytes.size()+binary.size())
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()
	return OK

func _initialize()->void:
	if "--with-collision-first" in OS.get_cmdline_user_args():DeferredScript.collision_first_enabled=true
	if "--with-no-collision-proof" in OS.get_cmdline_user_args():preload("res://scripts/world3d/collision_dependency_loader.gd").no_collision_proof_enabled=true
	if "--dispatch-before-collision-installation" in OS.get_cmdline_user_args():preload("res://scripts/world3d/collision_dependency_loader.gd").dispatch_before_installation=true
	if "--with-collision-query-caches" in OS.get_cmdline_user_args():
		DeferredScript.collision_query_cache_enabled=true
		Stream.collision_candidate_cache_enabled=true
	if "--with-background-services" in OS.get_cmdline_user_args():
		preload("res://scripts/world3d/world_3d.gd").navigation_background_enabled=true
		preload("res://scripts/world3d/world_3d.gd").wind_background_enabled=true
		preload("res://scripts/world3d/frame_work_budget.gd").enabled=true
	call_deferred("run")

func physical_destination_ready()->bool:
	var exclude:Array[RID]=[world._player.get_rid()]
	return world._physical_destination_fits(world._map_root,world.get_world_3d().direct_space_state,world._player.global_position,exclude)
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1

func make_map(path:String,asset:String,large:bool)->bool:
	var doc:=Doc.new();doc.map_meta={"spawn":[0,.9,4],"map_ref":"transfer_fixture_"+path.get_file()}
	doc.add_box("ground",Vector3(0,-.1,0),Vector3(24,.2,24))
	var safety_id:="";var neighbour_id:=""
	if large:
		doc.add_box("ground",Vector3(300,-.1,0),Vector3(24,.2,24))
		doc.add_box("block",Vector3(300,1,0),Vector3(2,2,2))
		doc.add_asset({"label":"Far prop","asset_path":asset,"bounds_position":[-.5,-.5,-.5]},Vector3(304,.5,4))
	else:
		# The negative-X prop lies outside cell (0,0), inside its entry safety
		# halo. The other prop is normal player-prefetch work, outside that halo.
		safety_id=doc.add_asset({"label":"Safety halo prop","asset_path":asset,"bounds_position":[-.5,-.5,-.5]},Vector3(-8,.5,4))
		neighbour_id=doc.add_asset({"label":"Later neighbour prop","asset_path":asset,"bounds_position":[-.5,-.5,-.5]},Vector3(96,.5,4))
	var saved:bool=doc.save(path)==OK
	check(saved,"save temporary map "+path.get_file())
	if not saved:return false
	var source:RefCounted=Snapshot.read_file(path)
	var native:int=Cursor.native_root(source._data) if source.error.is_empty() else -1
	check(native>=0,"temporary map has a native reference snapshot "+path.get_file())
	if native<0:return false
	var hydrated:Dictionary=Cursor.hydrate_references(source._data.nodes[native].extras,path,Paths.external_root())
	check(hydrated.get("ok",false),"temporary map references hydrate before indexing "+path.get_file())
	if not hydrated.get("ok",false):return false
	var built:Dictionary=Index.build(path,Paths.external_root(),hydrated.extras.rmmo_records,source._signature)
	check(built.get("ok",false),"temporary map dependency index builds "+path.get_file()+" "+str(built.get("reason","")))
	if not built.get("ok",false):return false
	var verified:Dictionary=Index.read(path,Paths.external_root(),source._signature)
	check(verified.get("ok",false) and source.matches_disk(),"temporary dependency index matches unchanged author source "+path.get_file())
	if not verified.get("ok",false):return false
	indexed_fixtures[path]={"source_sha":source._signature,"safety_id":safety_id,"neighbour_id":neighbour_id}
	if not large:
		var plan:Dictionary=EntryPlan.create(Vector3(0,.9,4))
		var core:Dictionary=Index.select(verified,[plan.core_clip]);var safety:Dictionary=Index.select(verified,[plan.safety_clip])
		var core_ids:Array=core.get("extras",{}).get("rmmo_records",[]).map(func(record):return record.uuid)
		var safety_ids:Array=safety.get("extras",{}).get("rmmo_records",[]).map(func(record):return record.uuid)
		check(core.get("ok",false) and safety.get("ok",false) and not core_ids.has(safety_id) and safety_ids.has(safety_id) and not safety_ids.has(neighbour_id),"small fixture has a real core, deferred safety dependency and excluded neighbour")
	return true

func staged_entry_map(old_map_id:int)->Node:
	if is_instance_valid(world._map_root) and world._map_root.get_instance_id()!=old_map_id:return world._map_root
	for viewport:Node in world.get_children():
		if not viewport is SubViewport:continue
		for host:Node in viewport.get_children():
			for candidate:Node in host.get_children():
				if candidate.has_meta("entry_plan"):return candidate
	return null

func observe_indexed_entry(map_root:Node,destination:Vector3,fixture:Dictionary,observation:Dictionary)->void:
	if map_root==null:return
	observation.seen=true
	var plan:Dictionary=map_root.get_meta("entry_plan",{})
	var expected:Dictionary=EntryPlan.create(destination)
	observation.plan=plan.duplicate(true)
	observation.index_hit=map_root.get_meta("load_profile",{}).get("reference_index_hit",false)
	observation.scope_valid=observation.scope_valid and map_root.get_meta("entry_stream_clip")==expected.safety_clip
	var queue:Node=map_root.get_node_or_null("DeferredAssets")
	if queue==null:return
	var ids:Array=queue.get_demand_scope()
	observation.scope_valid=observation.scope_valid and ids.has("entry_safety")
	for id:String in ids:
		if id!="entry_safety" and not id.begins_with("navigation:"):observation.scope_valid=false
	if not str(fixture.safety_id).is_empty():
		observation.safety_published=observation.safety_published or queue._runtime_record_ids.has(fixture.safety_id)
		observation.neighbour_held=observation.neighbour_held and not queue._runtime_record_ids.has(fixture.neighbour_id)

func execute(target:String,destination:Vector3,result:Dictionary,gate:Callable)->void:
	result.ok=await world.transfer_map(target,destination,gate)
	# Observe rollback in the same continuation, before an idle queue can
	# legitimately disable its own _process on the next frame.
	var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
	result.return_state={"disable_3d":world.get_viewport().disable_3d,"deferred_id":queue.get_instance_id() if queue!=null else 0,"deferred_processing":queue.is_processing() if queue!=null else false,"deferred_active":queue._active if queue!=null else false,"deferred_cancelled":queue._cancelled if queue!=null else false}
	result.done=true

func listener_snapshot(queue:Node)->Dictionary:
	var snapshot:Dictionary={}
	if queue==null:return snapshot
	for signal_name:String in ["published","completed","failed"]:
		var callbacks_:Array=[]
		for connection:Dictionary in queue.get_signal_connection_list(signal_name):callbacks_.append(connection.callable)
		snapshot[signal_name]=callbacks_
	return snapshot

func transfer(target:String,destination:Vector3,gate:Callable=Callable())->Dictionary:
	var old_map:Node=world._map_root;var old_position:Vector3=world._player.global_position
	var old_map_id:int=old_map.get_instance_id()
	var indexed_cross:bool=indexed_fixtures.has(target) and target!=world._map_path
	var entry_observation:Dictionary={"seen":false,"scope_valid":true,"neighbour_held":true,"safety_published":false,"index_hit":false,"plan":{}}
	var outgoing:Node=old_map.get_node_or_null("DeferredAssets")
	var result:Dictionary={"done":false,"ok":false}
	execute(target,destination,result,gate)
	var saw_cover:=false;var frozen:=true;var stayed:=true;var draw_before_loader:=true;var captured:=false;var outgoing_idle:=true
	var presentation:={"fade_out":false,"fade_in":false,"source_visible":true,"covered_permission":true,"camera_ready":true,"combat_frozen":true}
	var started:=Time.get_ticks_msec()
	while not result.done:
		sample_refs()
		if indexed_cross:observe_indexed_entry(staged_entry_map(old_map_id),destination,indexed_fixtures[target],entry_observation)
		var cover:=world.get_node_or_null("TransferLoading")
		if cover!=null:
			saw_cover=true
			presentation.combat_frozen=presentation.combat_frozen and not world._combat.is_physics_processing()
			if cover.phase=="covering":
				presentation.fade_out=true
				presentation.source_visible=presentation.source_visible and not world.get_viewport().disable_3d and world._map_root==old_map
				presentation.covered_permission=presentation.covered_permission and not cover.is_opaque_drawn()
			if cover.phase=="revealing":
				presentation.fade_in=true
				presentation.covered_permission=presentation.covered_permission and not cover.is_opaque_drawn()
				presentation.camera_ready=presentation.camera_ready and world._camera.last_focus.distance_to(world._player.global_position+Vector3.UP*world._camera.pivot_height)<.01 and not world.get_viewport().disable_3d
			frozen=frozen and world._player.input_locked and not world._player.is_physics_processing()
			if is_instance_valid(world._transfer_loader):
				draw_before_loader=draw_before_loader and cover.drawn_frame>=0
				if is_instance_valid(outgoing):outgoing_idle=outgoing_idle and outgoing._jobs.is_empty() and not outgoing._active
			if cover.drawn_frame>=0 and not captured:
				var capture_path:=directory.path_join("loading_cover.webp")
				var capture:=get_root().get_texture().get_image();capture.save_webp(capture_path,true,.9)
				FileAccess.open(directory.path_join("loading_cover_compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(capture_path),"quality":90,"lossy":true,"width":capture.get_width(),"height":capture.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=.9)"}));captured=true
			if world._map_root==old_map and not world._local_transfer.get("committed",false):stayed=stayed and world._player.global_position.is_equal_approx(old_position)
		await process_frame
	check(presentation.fade_out and presentation.fade_in and presentation.source_visible,"source rendering persists through fade-out and restored/target scene fades in")
	check(presentation.covered_permission and presentation.combat_frozen,"partial covers never authorize covered budget; combat freezes through reveal")
	check(presentation.camera_ready,"destination/rollback camera snaps before reveal including short teleports")
	check(saw_cover and frozen,"loading cover stays visible with input and gravity frozen")
	check(stayed and draw_before_loader,"old position remains until commit and cover draws before loader starts")
	check(outgoing_idle,"cross-map loader starts only after outgoing workers retire and remain suspended")
	var profile:Dictionary=world.get_meta("transfer_loading_profile",{})
	check(profile.get("drawn_frame",-1)>=0 and profile.get("elapsed_ms",-1)>=0,"cover exposes actual draw and elapsed evidence")
	check(profile.get("ready_ms",0)>=profile.get("covered_ms",1) and profile.get("reveal_started_ms",0)>=profile.get("ready_ms",1) and profile.get("input_restored_ms",0)>=profile.get("revealed_ms",1),"opaque frame, destination frame, reveal and input restoration are ordered")
	if result.ok:check(profile.ready_frame>profile.drawn_frame,"destination gets a rendered frame before cover retirement")
	if result.ok:
		if profile.get("same_map",false):check(profile.get("radar_region_ready_at_retire",false),"destination radar region is prepared before loading cover retires")
		else:check(world._hud._radar.region_is_prepared(Vector2(destination.x,destination.z)),"cross-map destination radar region is prepared before loading cover retires")
	if indexed_cross and entry_observation.seen:
		var plan:Dictionary=entry_observation.plan
		check(entry_observation.index_hit and int(plan.get("core_resources_ready_us",0))>0,"cross-map loader actually uses its verified index and core milestone")
		check(int(plan.get("neighbours_started_us",0))>=int(plan.get("core_resources_ready_us",0)) and int(plan.get("neighbours_started_us",0))>0,"core resources finish before safety publication is activated")
		check(entry_observation.scope_valid and entry_observation.neighbour_held,"staged transfer keeps exact safety scope and holds unrelated neighbour publication")
		check(entry_observation.safety_published,"safety-only external instance is published while the loading cover remains")
	if result.ok and indexed_cross:
		check(entry_observation.seen,"successful cross-map fixture exercised indexed entry preparation")
		var plan:Dictionary=world._map_root.get_meta("entry_plan",{})
		var expected:Dictionary=EntryPlan.create(destination)
		var navigation:Node=world._navigation
		var local:AABB=navigation._local_clip
		var expected_clip:AABB=expected.navigation_clip
		check(plan.get("core_clip")==expected.core_clip and plan.get("safety_clip")==expected.safety_clip and navigation.initial_geometry_clip==expected_clip,"cross-map core, safety and navigation use the same entry plan")
		check(navigation._initial_geometry_clip_active and is_equal_approx(local.position.x,expected_clip.position.x) and is_equal_approx(local.position.z,expected_clip.position.z) and is_equal_approx(local.end.x,expected_clip.end.x) and is_equal_approx(local.end.z,expected_clip.end.z),"published Recast region keeps the compact XZ clip instead of expanding to the old radius")
		check(int(world.loading_profile.get("entry_safety_ready_us",0))>=int(plan.get("neighbours_started_us",0)) and Stream.nearby_collision_ready(world._map_root,destination),"safety geometry and physical collision are complete before cover retirement")
		var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
		check(not world._map_root.has_meta("entry_stream_clip") and queue!=null and queue._entry_loading.is_empty() and queue.get_demand_scope().is_empty() and queue._active,"successful first frame releases stream scope and restores normal deferred scheduling")
		check(queue!=null and not queue._cancelled and not result.get("return_state",{}).get("deferred_cancelled",true),"staged map reparent preserves a live non-cancelled deferred queue")
	await process_frame
	check(world.get_node_or_null("TransferLoading")==null and not world._transfer_pending,"transfer retires cover and transaction lock")
	print("TRANSFER_CASE target=",target," ok=",result.ok," ms=",Time.get_ticks_msec()-started," indexed_entry=",entry_observation)
	return result

func fail_case(target:String,destination:Vector3,gate:Callable,label_:String,expected_calls:int=0)->void:
	var old_map_id:int=world._map_root.get_instance_id();var old_nav_id:int=world._navigation.get_instance_id()
	var old_combat_id:int=world._combat.get_instance_id();var old_position:Vector3=world._player.global_position
	var old_path:String=world._map_path;var old_locked:bool=world._player.input_locked
	var old_processing:bool=world._player.is_physics_processing();var before:=callbacks
	var old_disabled:bool=world.get_viewport().disable_3d
	var old_deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	var old_deferred_processing:bool=old_deferred.is_processing() if old_deferred!=null else false
	var old_deferred_active:bool=old_deferred._active if old_deferred!=null else false
	var old_listeners:Dictionary=listener_snapshot(old_deferred)
	var result:=await transfer(target,destination,gate)
	check(not result.ok and world._map_root.get_instance_id()==old_map_id and world._navigation.get_instance_id()==old_nav_id and world._combat.get_instance_id()==old_combat_id,label_+" preserves map, navigation and combat identity")
	check(world._map_path==old_path and world._player.global_position.is_equal_approx(old_position) and world._player.input_locked==old_locked and world._player.is_physics_processing()==old_processing,label_+" restores position and input/physics state")
	check(callbacks==before+expected_calls,label_+" invokes commit conditions only after valid preparation")
	var restored:Dictionary=result.get("return_state",{})
	check(restored.get("disable_3d") ==old_disabled and world.get_viewport().disable_3d==old_disabled and (old_deferred==null or (restored.get("deferred_id")==old_deferred.get_instance_id() and restored.get("deferred_processing")==old_deferred_processing)),label_+" restores rendering and outgoing deferred work at transaction return")
	check(old_deferred==null or (restored.get("deferred_active")==old_deferred_active and old_deferred._active==old_deferred_active),label_+" restores outgoing queue activation after temporary quiescence")
	check(listener_snapshot(old_deferred)==old_listeners,label_+" preserves outgoing publication, completion and failure listeners")
	print("TRANSFER_ROLLBACK_STATE ",JSON.stringify({"case":label_,"before_processing":old_deferred_processing,"at_return":restored,"after_frame_processing":old_deferred.is_processing() if old_deferred!=null else false}))

static func raw_cancellation_probe(token:RefCounted,probe:Dictionary)->Dictionary:
	var mutex:Mutex=preload("res://scripts/world3d/model_parse_preparation.gd").RAW_IMPORT_MUTEX
	mutex.lock()
	var deadline:=Time.get_ticks_msec()+5000
	while not token.is_cancelled() and Time.get_ticks_msec()<deadline:OS.delay_msec(1)
	probe.cancelled=token.is_cancelled()
	var scene:=Node3D.new();probe.scene_id=scene.get_instance_id()
	mutex.unlock()
	return {"error":"", "scene":scene}

func install_outgoing_probe(queue:Node)->Dictionary:
	var path:="quiesce://raw-cancellation-probe"
	var estimate:={"estimated_bytes":1024,"exclusive":false}
	var token:=DrainerScript.CancelToken.new();var worker:=Thread.new();var probe:Dictionary={}
	check(queue._admission.reserve(path,estimate),"reserve outgoing raw-import lifetime probe")
	queue._drainer=DrainerScript.for_tree(self);queue._drainer.watch(worker,token)
	queue._jobs[path]={"worker":worker,"token":token,"estimate":estimate}
	check(worker.start(raw_cancellation_probe.bind(token,probe))==OK,"start raw-import worker before cross-map transfer")
	return probe

func run()->void:
	create_timer(240).timeout.connect(func():print("TRANSFER_LOADING_TIMEOUT");quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("transfer_loading_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var asset:=directory.path_join("prop.glb")
	check(ordinary_fixture(asset)==OK,"create ordinary self-contained GLB fixture")
	check(preload("res://scripts/world3d/asset_bounds_manifest.gd").read(asset).get("known",false),"far asset qualifies for deferred geometry admission")
	var first:=directory.path_join("large.gltf");var second:=directory.path_join("small.gltf")
	if not make_map(first,asset,true) or not make_map(second,asset,false):quit(1);return
	var empty_path:=directory.path_join("no_floor.gltf");var empty_doc:=Doc.new()
	empty_doc.add_box("block",Vector3(0,5,0),Vector3(.1,10,.1))
	check(empty_doc.save(empty_path)==OK,"save target with no viable navigation polygons")
	var first_sha:=FileAccess.get_sha256(first);var second_sha:=FileAccess.get_sha256(second)
	var session:=root.get_node("GameSession");session.world3d_map_path=first;session.world3d_spawn=Vector3(0,.9,4)
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.go_world_3d()
	while true:
		await process_frame
		sample_refs()
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"real loading entry: "+str(current_scene.status_label.text));quit(1);return
		if not is_instance_valid(current_scene) or not current_scene.has_method("is_world_ready"):continue
		world=current_scene
		if world.is_world_ready() and not session._world_transition_active:break
	check(world._map_root.has_meta("entry_plan") and world._map_root.get_meta("load_profile",{}).get("reference_index_hit",false),"initial world also completed its real indexed entry without suppressing the safety queue")
	if "--baseline-entry-only" in OS.get_cmdline_user_args():
		await cleanup_world()
		print("TRANSFER_ENTRY_BASELINE_FINISHED failures=",failures)
		quit(1 if failures else 0);return
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:deferred.set_process(false)
	check(deferred!=null and not deferred.ensure_geometry(AABB(Vector3(292,-100,0),Vector3(20,200,12))),"same-map far destination really starts with unpublished external geometry")
	var gate:=func()->bool:
		callbacks+=1
		check(world.get_node_or_null("TransferLoading")!=null and world._player.input_locked,"commit conditions run under loading cover")
		return true
	var moved:=await transfer(first,Vector3(300,.9,4),gate)
	check(moved.ok and callbacks==1 and world._map_path==first,"same-map distant transfer commits once after preparation")
	var background_services:bool=preload("res://scripts/world3d/world_3d.gd").navigation_background_enabled
	check(world._player.global_position.distance_to(Vector3(300,.9,4))<.1 and Stream.nearby_collision_ready(world._map_root,world._player.global_position) and (background_services or world._navigation.ready_for_queries),"far destination collision and required entry services ready before gameplay")
	if background_services:
		check(physical_destination_ready() and root.get_node("MockServer").world3d_authority.traversal_guard.is_valid(),"background navigation entry has real synchronized support and manual movement guard")
		var deadline:=Time.get_ticks_msec()+15000
		while not world._navigation.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
		check(world._navigation.ready_for_queries,"optional navigation subsequently becomes available within bounded time")
	check(world._navigation.find_path(Vector3(298,.05,4),Vector3(302,.05,4)).ok,"destination local navigation actually supports a route")
	var outgoing_probe:=install_outgoing_probe(deferred)
	await fail_case(directory.path_join("missing.gltf"),Vector3(0,.9,4),gate,"missing target")
	check(outgoing_probe.get("cancelled",false) and not is_instance_id_valid(int(outgoing_probe.get("scene_id",0))),"failed cross-map transfer cancels raw worker and destroys its unpublished output before rollback")
	await fail_case(first,Vector3(300,.9,0),gate,"blocked destination")
	await fail_case(empty_path,Vector3(3,.9,0),gate,"no navigable target surface")
	var reject:=func()->bool:callbacks+=1;return false
	var before:=callbacks
	await fail_case(second,Vector3(0,.9,4),reject,"changed commit condition",1)
	check(callbacks==before+1,"failed commit condition runs exactly once after preparation")
	var crossed:=await transfer(second,Vector3(0,.9,4),gate)
	check(crossed.ok and world._map_path==second and (background_services or world._navigation.ready_for_queries),"cross-map transfer uses same complete loading transaction")
	if background_services:check(physical_destination_ready(),"cross-map target physical readiness is independent of navigation completion")
	if crossed.ok:
		var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
		var neighbour_id:String=indexed_fixtures[second].neighbour_id
		var deadline:=Time.get_ticks_msec()+15000
		while queue!=null and (not queue._runtime_record_ids.has(neighbour_id) or not queue._jobs.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
		check(queue!=null and queue._runtime_record_ids.has(neighbour_id),"normal nearby prefetch actually resumes after first-frame scope release")
		check(queue!=null and not queue._cancelled and queue._jobs.is_empty() and queue._admission.count()==0 and queue._admission.reserved_bytes==0,"cross-map safety and neighbour work retire every worker and admission reservation")
	check(FileAccess.get_sha256(first)==first_sha and FileAccess.get_sha256(second)==second_sha,"transfers do not rewrite either source map")
	await cleanup_world()
	print("TRANSFER_LOADING_GPU_FINISHED failures=",failures," fixture=",directory)
	quit(1 if failures else 0)
