extends SceneTree
## Run only with run_godot_background.py on a private desktop.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
var directory:=""
var callbacks:=0
var world:Node
var _diagnostic_refs:Dictionary={}
var _bake_ids:Dictionary={}
const LoaderScript=preload("res://scripts/world3d/map_loader.gd")
const NavigationScript=preload("res://scripts/world3d/world_navigation.gd")
const DrainerScript=preload("res://scripts/world3d/asset_worker_drainer.gd")
const DeferredScript=preload("res://scripts/world3d/deferred_asset_loader.gd")

func remember_ref(value:Variant,label_:String)->void:
	if not value is RefCounted:return
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
		if not member is RefCounted:continue
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
			remember_ref(node._worker_token,label_+"._worker_token")
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

func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1

func make_map(path:String,asset:String,large:bool)->void:
	var doc:=Doc.new();doc.map_meta={"spawn":[0,.9,4],"map_ref":"transfer_fixture_"+path.get_file()}
	doc.add_box("ground",Vector3(0,-.1,0),Vector3(24,.2,24))
	if large:
		doc.add_box("ground",Vector3(300,-.1,0),Vector3(24,.2,24))
		doc.add_box("block",Vector3(300,1,0),Vector3(2,2,2))
		doc.add_asset({"label":"Far prop","asset_path":asset,"bounds_position":[-.5,-.5,-.5]},Vector3(304,.5,4))
	check(doc.save(path)==OK,"save temporary map "+path.get_file())

func execute(target:String,destination:Vector3,result:Dictionary,gate:Callable)->void:
	result.ok=await world.transfer_map(target,destination,gate);result.done=true

func transfer(target:String,destination:Vector3,gate:Callable=Callable())->Dictionary:
	var old_map:Node=world._map_root;var old_position:Vector3=world._player.global_position
	var result:Dictionary={"done":false,"ok":false}
	execute(target,destination,result,gate)
	var saw_cover:=false;var frozen:=true;var stayed:=true;var draw_before_loader:=true;var captured:=false
	var started:=Time.get_ticks_msec()
	while not result.done:
		sample_refs()
		var cover:=world.get_node_or_null("TransferLoading")
		if cover!=null:
			saw_cover=true
			frozen=frozen and world._player.input_locked and not world._player.is_physics_processing()
			if is_instance_valid(world._transfer_loader):draw_before_loader=draw_before_loader and cover.drawn_frame>=0
			if cover.drawn_frame>=0 and not captured:
				get_root().get_texture().get_image().save_png(directory.path_join("loading_cover.png"));captured=true
			if world._map_root==old_map:stayed=stayed and world._player.global_position.is_equal_approx(old_position)
		await process_frame
	check(saw_cover and frozen,"loading cover stays visible with input and gravity frozen")
	check(stayed and draw_before_loader,"old position remains until commit and cover draws before loader starts")
	var profile:Dictionary=world.get_meta("transfer_loading_profile",{})
	check(profile.get("drawn_frame",-1)>=0 and profile.get("elapsed_ms",-1)>=0,"cover exposes actual draw and elapsed evidence")
	if result.ok:check(profile.ready_frame>profile.drawn_frame,"destination gets a rendered frame before cover retirement")
	if result.ok:check(world._hud._radar.terrain_is_prepared(),"destination radar is prepared before loading cover retires")
	await process_frame
	check(world.get_node_or_null("TransferLoading")==null and not world._transfer_pending,"transfer retires cover and transaction lock")
	print("TRANSFER_CASE target=",target," ok=",result.ok," ms=",Time.get_ticks_msec()-started)
	return result

func fail_case(target:String,destination:Vector3,gate:Callable,label_:String,expected_calls:int=0)->void:
	var old_map_id:int=world._map_root.get_instance_id();var old_nav_id:int=world._navigation.get_instance_id()
	var old_combat_id:int=world._combat.get_instance_id();var old_position:Vector3=world._player.global_position
	var old_path:String=world._map_path;var old_locked:bool=world._player.input_locked
	var old_processing:bool=world._player.is_physics_processing();var before:=callbacks
	var old_disabled:bool=world.get_viewport().disable_3d
	var old_deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	var old_deferred_processing:bool=old_deferred.is_processing() if old_deferred!=null else false
	var result:=await transfer(target,destination,gate)
	check(not result.ok and world._map_root.get_instance_id()==old_map_id and world._navigation.get_instance_id()==old_nav_id and world._combat.get_instance_id()==old_combat_id,label_+" preserves map, navigation and combat identity")
	check(world._map_path==old_path and world._player.global_position.is_equal_approx(old_position) and world._player.input_locked==old_locked and world._player.is_physics_processing()==old_processing,label_+" restores position and input/physics state")
	check(callbacks==before+expected_calls,label_+" invokes commit conditions only after valid preparation")
	check(world.get_viewport().disable_3d==old_disabled and (old_deferred==null or old_deferred.is_processing()==old_deferred_processing),label_+" restores rendering and outgoing deferred work")

func run()->void:
	create_timer(240).timeout.connect(func():print("TRANSFER_LOADING_TIMEOUT");quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("transfer_loading_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var asset:=directory.path_join("prop.glb")
	check(ordinary_fixture(asset)==OK,"create ordinary self-contained GLB fixture")
	check(preload("res://scripts/world3d/asset_bounds_manifest.gd").read(asset).get("known",false),"far asset qualifies for deferred geometry admission")
	var first:=directory.path_join("large.gltf");var second:=directory.path_join("small.gltf")
	make_map(first,asset,true);make_map(second,asset,false)
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
		if is_instance_valid(world._map_root):
			var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
			if queue!=null:queue.set_process(false)
		if world.is_world_ready() and not session._world_transition_active:break
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
	check(world._player.global_position.distance_to(Vector3(300,.9,4))<.1 and Stream.nearby_collision_ready(world._map_root,world._player.global_position) and world._navigation.ready_for_queries,"far destination collision and navigation ready before gameplay")
	check(world._navigation.find_path(Vector3(298,.05,4),Vector3(302,.05,4)).ok,"destination local navigation actually supports a route")
	await fail_case(directory.path_join("missing.gltf"),Vector3(0,.9,4),gate,"missing target")
	await fail_case(first,Vector3(300,.9,0),gate,"blocked destination")
	await fail_case(empty_path,Vector3(3,.9,0),gate,"no navigable target surface")
	var reject:=func()->bool:callbacks+=1;return false
	var before:=callbacks
	await fail_case(second,Vector3(0,.9,4),reject,"changed commit condition",1)
	check(callbacks==before+1,"failed commit condition runs exactly once after preparation")
	var crossed:=await transfer(second,Vector3(0,.9,4),gate)
	check(crossed.ok and world._map_path==second and world._navigation.ready_for_queries,"cross-map transfer uses same complete loading transaction")
	check(FileAccess.get_sha256(first)==first_sha and FileAccess.get_sha256(second)==second_sha,"transfers do not rewrite either source map")
	await cleanup_world()
	print("TRANSFER_LOADING_GPU_FINISHED failures=",failures," fixture=",directory)
	quit(1 if failures else 0)
