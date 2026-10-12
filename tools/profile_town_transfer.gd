extends SceneTree
## Real entry and same-map transfer; only a pre-existing disposable checkpoint.
const MAP="D:/code/rmmo_runtime/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const TARGET_BRIDGE="stone_e_0be972769041dbc9"
const TARGET_XZ=Vector2(292.9,151.4)
var map_path:=MAP
var output:="D:/code/rmmo_runtime/review_artifacts/town_transfer_20261008.json"
var report:Dictionary={"failures":0,"stages":[]}
var world:Node
var result:Dictionary={"done":false,"ok":false}
var deferred_workers:=0 # Production automatic capacity; 2/4/6 are explicit probe overrides.
var destination_only:=false # CPU author-data verification, without entering a world.

func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if not value:report.failures+=1
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func surface_at(specs:Array,point:Vector2)->Dictionary:
	var answer:Dictionary={};var highest:=-INF;var visited:=0;var triangles:=0
	for spec:Dictionary in specs:
		var extra:Dictionary=spec.get("extras",{})
		if extra.get("rmmo_collision","")=="none" or extra.get("hostile",false) or extra.get("ally",false):continue
		# The caller supplies only the privately decoded authored bridge source,
		# never a runtime terrain fallback or a prepared/published deferred model.
		var shape:Mesh=spec.mesh
		if shape.get_script()!=Cpu and not shape.has_meta("ground_cpu_cache"):continue
		var pose:Transform3D=spec.transform;var bounds:AABB=pose*shape.get_aabb()
		if point.x<bounds.position.x or point.x>bounds.end.x or point.y<bounds.position.z or point.y>bounds.end.z:continue
		visited+=1
		var cpu:Mesh=shape if shape.get_script()==Cpu else shape.get_meta("ground_cpu_cache")
		var faces:PackedVector3Array=cpu.collision_faces()
		var origin:=Vector3(point.x,bounds.end.y+1,point.y)
		for index in range(0,faces.size()-2,3):
			var a:Vector3=pose*faces[index];var b:Vector3=pose*faces[index+1];var c:Vector3=pose*faces[index+2]
			var normal:Vector3=(b-a).cross(c-a).normalized();triangles+=1
			if absf(normal.y)<cos(deg_to_rad(40)):continue
			var hit:Variant=Geometry3D.ray_intersects_triangle(origin,Vector3.DOWN,a,b,c)
			if hit is Vector3 and hit.y>highest:
				highest=hit.y
				answer={"uuid":str(spec.get("uuid","")),"surface_id":str(extra.get("surface_id","")),"kind":str(extra.get("kind","")),"y":hit.y,"normal":[normal.x,normal.y,normal.z],"triangle":[[a.x,a.y,a.z],[b.x,b.y,b.z],[c.x,c.y,c.z]]}
	answer.scanned_specs=visited;answer.scanned_triangles=triangles
	return answer

func preparation_cache_state()->Dictionary:
	House._decode_mutex.lock()
	var state:={"decoded":House._decoded.keys(),"decoded_bytes":House._decoded_bytes}
	House._decode_mutex.unlock()
	state.geometry=House._meshes.keys();state.render=House._render_meshes.keys()
	state.definitions=Store.definition_cache_stats()
	Store._mutex.lock();state.identities=Store._identities.size();state.encoded_bytes=Store._cache_size;Store._mutex.unlock()
	return state

func authored_bridge_surface(path:String,point:Vector2)->Dictionary:
	# An independent bounded CPU oracle, executed before the game-entry timer.
	# Do not call House.decode/geometry, Cook.restore or document open: those
	# would warm production prefab/material caches before the transfer probe.
	var snapshot=preload("res://scripts/world3d/document_source_snapshot.gd").read_file(path)
	if not snapshot.error.is_empty():return {"error":snapshot.error}
	var native:int=preload("res://scripts/world3d/document_open_cursor.gd").native_root(snapshot._data)
	if native<0:return {"error":"Expected a reference map"}
	var extra:Dictionary=snapshot._data.nodes[native].extras
	if not extra.get("rmmo_resource_dependencies") is Dictionary:return {"error":"Missing resource manifest"}
	var compact:Dictionary={};var found:=0
	for row:Variant in extra.rmmo_records:
		if row is Dictionary and row.get("uuid")==TARGET_BRIDGE:compact=row;found+=1
	if found!=1 or not Store._shape(compact,true):return {"error":"Target bridge compact record is missing or invalid"}
	var ref:Dictionary=compact.rmmo_ref
	if ref.size()!=4 or not Store._integer(ref.get("version")) or ref.version!=1 or not Store._integer(ref.get("length")) or ref.length<=16 or ref.length>Store.MAX_FILE_BYTES:return {"error":"Invalid bridge resource header"}
	var location:=Store._location(ref.get("uri"),ref.get("sha256"),path,Paths.external_root())
	if location.is_empty() or extra.rmmo_resource_dependencies.get(ref.uri)!=ref.sha256:return {"error":"Bridge resource path or manifest does not match"}
	var file:=FileAccess.open(location,FileAccess.READ)
	if file==null or file.get_length()!=int(ref.length):return {"error":"Bridge resource length does not match"}
	var bytes:=file.get_buffer(int(ref.length));file.close()
	if bytes.size()!=int(ref.length) or Store._sha(bytes)!=ref.sha256 or bytes.slice(0,8).get_string_from_ascii()!=Store.MAGIC:return {"error":"Bridge resource SHA or envelope does not match"}
	var raw_length:int=bytes.decode_u64(8)
	if raw_length<=0 or raw_length>Store.MAX_RAW_BYTES:return {"error":"Invalid bridge resource raw length"}
	var raw:=bytes.slice(16).decompress(raw_length,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_length:return {"error":"Bridge resource decompression failed"}
	var definition:Variant=bytes_to_var(raw)
	if not definition is Dictionary or not Store._safe(definition,[],[2000000]):return {"error":"Invalid bridge resource structure"}
	for field:String in Store.FIELDS+Store.STATE_FIELDS+["rmmo_ref","rmmo_state"]:
		if definition.has(field):return {"error":"Bridge definition overrides instance identity"}
	var record:Dictionary=definition
	for field:String in Store.FIELDS:record[field]=compact[field]
	for field:String in compact.rmmo_state:record[field]=Store._json_copy(compact.rmmo_state[field])
	if not Store._shape(record) or not record.has("bridge_mesh") or not preload("res://scripts/world3d/bridge_data.gd").valid(record) or record.get("prefab_locked")!=true or record.get("collision")!="walk" or not record.get("house_prefab") is Dictionary:return {"error":"Target is not a frozen walkable bridge"}
	var prefab:Dictionary=record.house_prefab
	if prefab.get("version")!=1 or not prefab.get("data") is String or not Store._digest(prefab.get("sha256")) or not Store._integer(prefab.get("length")) or prefab.length<=0 or prefab.length>16777216 or prefab.data.length()>24000000:return {"error":"Invalid frozen bridge header"}
	var packed:=Marshalls.base64_to_raw(prefab.data).decompress(int(prefab.length),FileAccess.COMPRESSION_ZSTD)
	if packed.size()!=int(prefab.length) or Cook.Envelope.checksum(packed).hex_encode()!=prefab.sha256:return {"error":"Frozen bridge content SHA does not match"}
	var data:Variant=bytes_to_var(packed)
	# Cook's schema permits numeric LOD distance keys; the outer rmres schema
	# deliberately allows only string keys and must not be applied to this body.
	if not data is Dictionary or not Cook.valid_data(data) or data.entries.size()!=1:return {"error":"Invalid frozen bridge mesh structure"}
	# Runtime House.visual installs entry.source as collision_solid. Use the
	# original source slot and base indices; the render row/LODs are irrelevant.
	var source_id:int=data.entries[0][1][1];var source:Dictionary=data.meshes[source_id]
	if source.box_size!=Vector3.ZERO or source.surfaces.is_empty():return {"error":"Expected authored triangle collision source"}
	var cpu:=Cpu.new();cpu.surfaces=source.surfaces;cpu.bounds=source.bounds
	var faces:=cpu.collision_faces()
	if faces.is_empty() or faces.size()%3!=0:return {"error":"Invalid bridge collision triangle count"}
	for vertex:Vector3 in faces:
		if not vertex.is_finite():return {"error":"Invalid bridge collision vertex"}
	var pose:=Pose.pose(record)
	if not pose.is_finite() or is_zero_approx(pose.basis.determinant()):return {"error":"Invalid bridge instance transform"}
	var hit:=surface_at([{"uuid":TARGET_BRIDGE,"mesh":cpu,"transform":pose,"extras":{"rmmo_collision":record.collision,"kind":record.kind,"surface_id":record.get("surface_id","")}}],point)
	if hit.get("uuid")!=TARGET_BRIDGE or not hit.has("y"):return {"error":"No walkable target-bridge collision triangle at requested XZ"}
	# Recheck source authority after every private decode, just as the real
	# loading transaction must. Return evidence scalars only; release all arrays.
	if Store._location(ref.uri,ref.sha256,path,Paths.external_root())!=location or FileAccess.get_sha256(location)!=ref.sha256 or not snapshot.matches_disk():return {"error":"Bridge source changed during destination query"}
	hit.source="verified_authored_bridge_collision";hit.resource=ref.duplicate(true)
	hit.prefab_sha256=prefab.sha256;hit.collision_source_slot=source_id;hit.base_collision_faces=faces.size()
	hit.map_sha=snapshot._signature;hit.record_pose={"position":record.position,"rotation":record.rotation,"size":record.size}
	return hit

func execute_transfer(destination:Vector3)->void:
	result.ok=await world.transfer_map(map_path,destination);result.done=true

func queue_status()->Dictionary:
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	if deferred==null:return {}
	var jobs:Array=[]
	for path:String in deferred._jobs:
		var job:Dictionary=deferred._jobs[path]
		jobs.append({"path":path,"alive":job.has("worker") and job.worker.is_alive(),"ready":job.has("result"),"accepted":job.get("accepted",false),"publication_ids":job.get("publication_ids",[]).size(),"staged":job.get("staged",{}).size(),"native":job.get("native",false),"bytes":job.estimate.get("estimated_bytes",0)})
	return {"jobs":jobs,"profile":deferred.profile.duplicate(),"worker_limit":deferred._admission.worker_limit,"loading_worker_override":deferred.loading_worker_limit,"pending":deferred.pending.size(),"demanded":deferred._demanded.size(),"host_ready":world._ready_for_play,"active":deferred._active,"path_errors":deferred.path_errors,"instance_errors":deferred.instance_errors}

func inspect_transfer_readiness(destination:Vector3,diagnostic_clip:AABB)->Dictionary:
	# Observe the production transaction's exact contract without adding demand,
	# pumping preparation, changing scope or waiting for unrelated neighbourhoods.
	var map:Node=world._map_root;var deferred:Node=map.get_node_or_null("DeferredAssets")
	var plan:=preload("res://scripts/world3d/entry_plan.gd").create(destination)
	var clip:AABB=plan.safety_clip
	var landing:=AABB(Vector3(destination.x-2,-100000,destination.z-2),Vector3(4,200000,4))
	var observation:={"safety_clip":{"position":CpuVector(clip.position),"size":CpuVector(clip.size)},"collision_first":bool(map.get_meta("collision_first_loading",false)),"pending_required":[],"pending_diagnostic":[],"unsupported_required":[],"collision_states":{},"dependency_ready":true,"landing_visual_ready":true}
	var revision:int=deferred._demand_revision if deferred!=null else -1
	var entries:Array=[]
	if deferred!=null:
		for item:Dictionary in deferred._in_clip(diagnostic_clip):observation.pending_diagnostic.append(str(item.record.uuid))
		for item:Dictionary in deferred._in_clip(clip):
			observation.pending_required.append(str(item.record.uuid))
			if observation.collision_first and deferred._collision_entry_supported(item):entries.append(item.reference_entry)
			else:observation.unsupported_required.append(str(item.record.uuid))
		observation.dependency_ready=observation.unsupported_required.is_empty()
		observation.landing_visual_ready=deferred.geometry_published(landing)
		observation.local_error=deferred.error_for_clip(clip)
		if not str(observation.local_error).is_empty():observation.dependency_ready=false
		if not entries.is_empty():
			var service:Node=deferred._collision_loader(false) # Never create a service for the test.
			var coverage:Dictionary=service.coverage(entries) if service!=null else {"ok":false,"reason":"collision_service_missing"}
			observation.collision_coverage=coverage
			observation.dependency_ready=observation.dependency_ready and coverage.get("ok",false)
			if service!=null:
				for entry:Dictionary in entries:
					# This API validates the map/epoch/entry-bound typed absence receipt
					# or installed exact collision bodies and their physics watermark.
					observation.collision_states[entry.compact_record.uuid]=service.instance_readiness(entry.compact_record.uuid)
	observation.dependency_ready=observation.dependency_ready and observation.landing_visual_ready
	observation.collision_receipt=Stream.collision_readiness(map,clip)
	observation.bridge_group_published=deferred!=null and deferred.group_is_published("bridge:"+TARGET_BRIDGE)
	var spec:Dictionary=map.get_meta("stream_by_id",{}).get(TARGET_BRIDGE,{})
	var expected:Dictionary=report.destination_surface.record_pose.duplicate(true);expected.kind="asset"
	var expected_pose:=Pose.pose(expected)
	observation.bridge_spec_matches=not spec.is_empty() and spec.get("uuid")==TARGET_BRIDGE and spec.get("transform") is Transform3D and spec.transform.is_equal_approx(expected_pose) and spec.get("collision_mesh")!=null and spec.get("extras",{}).get("rmmo_collision")=="walk"
	var visual:Variant=map.get_meta("stream_meshes",{}).get(TARGET_BRIDGE)
	observation.bridge_render_ready=is_instance_valid(visual) and visual is MeshInstance3D and visual.is_inside_tree() and not visual.is_queued_for_deletion() and visual.mesh!=null
	if observation.bridge_render_ready and visual.mesh is Cpu:
		var batches:Node=map.get_node_or_null("GroundRenderBatches")
		var key:String=str(batches._member_groups.get(TARGET_BRIDGE,"")) if batches!=null else ""
		var batch_visual:Variant=batches.groups.get(key,{}).get("visual") if batches!=null else null
		observation.bridge_render_ready=is_instance_valid(batch_visual) and batch_visual is MeshInstance3D and batch_visual.is_inside_tree() and batch_visual.mesh!=null
	var body:Variant=map.get_meta("stream_bodies",{}).get(TARGET_BRIDGE)
	var shape_count:=0
	if is_instance_valid(body) and body is StaticBody3D:
		for owner:int in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner):shape_count+=body.shape_owner_get_shape_count(owner)
	observation.bridge_shape_count=shape_count
	observation.bridge_physics_frame=int(body.get_meta("stream_physics_published_frame",-1)) if is_instance_valid(body) else -1
	observation.physics_frame=Engine.get_physics_frames()
	observation.bridge_body_ready=is_instance_valid(body) and body is StaticBody3D and body.is_inside_tree() and not body.is_queued_for_deletion() and body.collision_layer!=0 and shape_count>0 and observation.bridge_physics_frame>=0 and observation.bridge_physics_frame<observation.physics_frame
	if observation.bridge_body_ready:
		var source_pose:Transform3D=body.get_meta("collision_source_transform",body.global_transform)
		observation.bridge_body_ready=source_pose.is_equal_approx(expected_pose)
	var feet:=destination-Vector3.UP*.9
	var ray:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.1,feet-Vector3.UP*.4,world._player.collision_mask,[world._player.get_rid()])
	ray.collide_with_areas=false
	var floor_hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	observation.bridge_ray_hits_body=not floor_hit.is_empty() and floor_hit.get("collider")==body and observation.bridge_body_ready and absf(floor_hit.position.y-feet.y)<.03 and floor_hit.normal.y>=preload("res://scripts/world3d/physical_traversal.gd").FLOOR_NORMAL_Y
	if not floor_hit.is_empty():observation.bridge_ray={"position":CpuVector(floor_hit.position),"normal":CpuVector(floor_hit.normal),"collider":str(floor_hit.collider.name)}
	observation.demand_unchanged=deferred==null or deferred._demand_revision==revision
	return observation

func CpuVector(value:Vector3)->Array:return [value.x,value.y,value.z]

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--deferred-workers="):deferred_workers=arg.trim_prefix("--deferred-workers=").to_int()
		elif arg=="--destination-only":destination_only=true
		elif arg=="--collision-geometry" or arg.begins_with("--collision-geometry="):
			var mode:=arg.trim_prefix("--collision-geometry=")
			if mode not in ["off","on"]:push_error("Expected --collision-geometry=off or on");quit(2);return
			preload("res://scripts/world3d/model_collision_requirements.gd").enabled=mode=="on"
		elif arg=="--model-texture-sharing" or arg.begins_with("--model-texture-sharing="):
			var mode:=arg.trim_prefix("--model-texture-sharing=")
			if mode not in ["off","on"]:push_error("Expected --model-texture-sharing=off or on");quit(2);return
			preload("res://scripts/world3d/model_texture_cache.gd").enabled=mode=="on"
	if deferred_workers not in [0,2,4,6]:quit(1);return
	if not Paths.allowed(map_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(map_path):quit(1);return
	if not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")):quit(1);return
	create_timer(900).timeout.connect(func():report.timeout=true;persist();quit(2))
	Engine.max_fps=60;root.size=Vector2i(1440,900);root.content_scale_size=root.size
	report.map=map_path;report.map_sha=FileAccess.get_sha256(map_path);report.formal_sha=FileAccess.get_sha256(FORMAL)
	report.collision_geometry=preload("res://scripts/world3d/model_collision_requirements.gd").enabled
	report.model_texture_sharing=preload("res://scripts/world3d/model_texture_cache.gd").enabled
	var cache_before:=preparation_cache_state();var height_started:=Time.get_ticks_usec()
	var hit:=authored_bridge_surface(map_path,TARGET_XZ)
	report.height_query_ms=(Time.get_ticks_usec()-height_started)/1000.;report.height_query_phase="before_game_entry";report.destination_surface=hit
	var query_valid:bool=hit.get("uuid")==TARGET_BRIDGE and hit.has("y") and hit.get("map_sha")==report.map_sha
	report.destination_query_cache_unchanged=preparation_cache_state()==cache_before
	check(query_valid,"bridge destination height comes from SHA-verified authored target-bridge collision triangles")
	check(report.destination_query_cache_unchanged,"private destination query leaves production prefab and resource caches unchanged")
	if not query_valid or not report.destination_query_cache_unchanged:persist();quit(1);return
	var destination:=Vector3(TARGET_XZ.x,float(hit.y)+.9,TARGET_XZ.y)
	report.destination=[destination.x,destination.y,destination.z]
	if destination_only:
		check(FileAccess.get_sha256(map_path)==report.map_sha and FileAccess.get_sha256(FORMAL)==report.formal_sha,"destination-only query leaves temporary and formal maps unchanged")
		persist();print("TOWN_TRANSFER_DESTINATION_FINISHED failures=",report.failures," report=",output);quit(0 if report.failures==0 else 1);return
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=map_path
	report.entry_epoch_s=Time.get_unix_time_from_system()
	var entry_started:=Time.get_ticks_usec();session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"real loading entry: "+str(current_scene.status_label.text));persist();quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene;report.entry_ms=(Time.get_ticks_usec()-entry_started)/1000.
	report.entry_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	var old_map:Node=world._map_root;var old_position:Vector3=world._player.global_position
	report.origin=[old_position.x,old_position.y,old_position.z]
	var deferred:Node=old_map.get_node_or_null("DeferredAssets")
	if deferred!=null:deferred.loading_worker_limit=deferred_workers
	report.deferred_workers_override=deferred_workers
	report.deferred_workers_mode="auto" if deferred_workers==0 else "override"
	report.logical_threads=OS.get_processor_count()
	report.deferred_workers=preload("res://scripts/world3d/deferred_asset_loader.gd").automatic_loading_worker_limit(report.logical_threads) if deferred_workers==0 else deferred_workers
	report.deferred_workers_interactive_before=deferred._admission.worker_limit if deferred!=null else 0
	report.deferred_workers_observed=[]
	report.initial_pending=deferred.pending.size() if deferred!=null else 0
	check(report.initial_pending>0,"real town enters with remote ordinary models still pending")
	var xz:=TARGET_XZ
	var nearby:=AABB(Vector3(xz.x-48,-100000,xz.y-48),Vector3(96,200000,96))
	var unprepared:bool=deferred!=null and not deferred.geometry_published(nearby)
	check(unprepared,"bridge district really contains unprepared nearby ordinary models")
	report.target_pending=[]
	if deferred!=null:
		for item:Dictionary in deferred.pending:
			var box:AABB=item.bounds
			if Rect2(nearby.position.x,nearby.position.z,nearby.size.x,nearby.size.z).intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z)):
				report.target_pending.append({"uuid":str(item.record.uuid),"path":str(item.path)})
	var bridge_pending:=false;var bridge_published:=false
	if deferred!=null:
		for item:Dictionary in deferred.pending:
			if item.record.uuid==TARGET_BRIDGE and not item.get("published",false):bridge_pending=true
	for spec:Dictionary in old_map.get_meta("stream_library",[]):
		if spec.get("uuid")==TARGET_BRIDGE:bridge_published=true
	report.destination_bridge_pending=bridge_pending;report.destination_bridge_published=bridge_published
	check(bridge_pending and not bridge_published,"authored height oracle did not prepare or publish the pending runtime target bridge")
	if not bridge_pending or bridge_published or not unprepared:persist();world.free();current_scene=null;quit(1);return
	report.transfer_epoch_s=Time.get_unix_time_from_system()
	var began:=Time.get_ticks_usec();var last_log:=began;var previous_stage:=""
	var saw_cover:=false;var continuous:=true;var frozen:=true;var stayed:=true;var drawn_first:=true;var captured:=false
	execute_transfer(destination)
	while not result.done:
		if deferred!=null and deferred.profile.get("worker_capacity",{}).get("mode","")=="covered_loading":
			var actual:int=deferred._admission.worker_limit
			if not report.deferred_workers_observed.has(actual):report.deferred_workers_observed.append(actual)
		var cover:Node=world.get_node_or_null("TransferLoading")
		continuous=continuous and cover!=null
		if cover!=null:
			saw_cover=true;frozen=frozen and world._player.input_locked and not world._player.is_physics_processing()
			if world._map_root==old_map and not world._local_transfer.get("committed",false):stayed=stayed and world._player.global_position.is_equal_approx(old_position)
			if is_instance_valid(world._transfer_loader):drawn_first=drawn_first and cover.drawn_frame>=0
			if str(cover.stage)!=previous_stage:
				previous_stage=cover.stage;report.stages.append({"stage":previous_stage,"at_ms":(Time.get_ticks_usec()-began)/1000.})
			if not captured and cover.drawn_frame>=0:
				var capture_started:=Time.get_ticks_usec();report.cover_image=output.get_basename()+"_cover.png"
				check(root.get_texture().get_image().save_png(report.cover_image)==OK,"capture one actual transfer loading frame")
				report.cover_capture_ms=(Time.get_ticks_usec()-capture_started)/1000.;captured=true
		if Time.get_ticks_usec()-last_log>=15000000:
			last_log=Time.get_ticks_usec();print("TOWN_TRANSFER_STAGE ",previous_stage," elapsed_ms=",(last_log-began)/1000.)
			print("TOWN_TRANSFER_QUEUE ",JSON.stringify(queue_status()))
		await process_frame
	report.transfer_ms=(Time.get_ticks_usec()-began)/1000.;report.transfer_ok=result.ok
	report.transfer_end_epoch_s=Time.get_unix_time_from_system()
	report.queue=queue_status()
	check(saw_cover and continuous and frozen,"cover remains throughout transfer with input and gravity frozen")
	check(stayed and drawn_first,"no early target placement and loading cover precedes heavy work")
	check(result.ok,"real same-town bridge transfer commits")
	report.loading_profile=world.get_meta("transfer_loading_profile",{}).duplicate(true)
	report.destination_map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	report.destination_nav_profile=world._navigation.loading_profile.duplicate(true)
	check(report.loading_profile.get("ready_frame",0)>report.loading_profile.get("drawn_frame",0),"target first rendered frame precedes cover retirement")
	check(report.loading_profile.get("radar_ready_at_retire",false) and report.loading_profile.get("radar_region_ready_at_retire",false),"target minimap commands and layout are ready at cover retirement before background publication resumes")
	await process_frame
	report.deferred_workers_interactive_after=deferred._admission.worker_limit if deferred!=null else 0
	check(world.get_node_or_null("TransferLoading")==null and not world._transfer_pending,"loading cover retires at completed handoff")
	check(report.deferred_workers_observed==[report.deferred_workers] and report.deferred_workers_interactive_after==report.deferred_workers_interactive_before,"observed covered worker capacity matches configuration and restores the prior interactive capacity")
	check(world._hud._radar.region_is_prepared(Vector2(destination.x,destination.z)),"target visible minimap draw IDs and outline widths stay ready after background publication resumes")
	check(world._player.global_position.distance_to(destination)<.15 and not world._player.input_locked,"player arrives at calculated bridge height and regains input")
	report.target_readiness=inspect_transfer_readiness(destination,nearby)
	var readiness:Dictionary=report.target_readiness
	check(readiness.dependency_ready,"exact transfer safety scope has published dependencies or verified instance collision/absence proofs")
	check(readiness.collision_receipt.ok,"exact transfer safety scope has synchronized real collision bodies")
	check(readiness.bridge_group_published and readiness.bridge_spec_matches and readiness.bridge_render_ready,"authored target bridge group and transformed render/collision spec are published")
	check(readiness.bridge_body_ready and readiness.bridge_ray_hits_body,"landing ray hits the target bridge's installed synchronized collision body at authored height")
	check(readiness.demand_unchanged,"readiness inspection does not create or widen background loading demand")
	check(Stream.nearby_collision_ready(world._map_root,destination) and world._navigation.ready_for_queries and world._navigation.near_surface(destination-Vector3.UP*.9,.35,.4),"target collision and actual local navigation surface are ready")
	world._camera.yaw=-2.2
	var capture_avatar:Node3D=world._player._model
	var capture_avatar_visible:bool=capture_avatar.visible if is_instance_valid(capture_avatar) else false
	if is_instance_valid(capture_avatar):capture_avatar.visible=false
	report.screenshot_avatar_hidden=is_instance_valid(capture_avatar)
	await process_frame;await RenderingServer.frame_post_draw
	report.final_image=output.get_basename()+"_destination.png"
	check(root.get_texture().get_image().save_png(report.final_image)==OK,"capture one final bridge view facing town")
	if is_instance_valid(capture_avatar):capture_avatar.visible=capture_avatar_visible
	check(FileAccess.get_sha256(map_path)==report.map_sha and FileAccess.get_sha256(FORMAL)==report.formal_sha,"checkpoint and formal source map SHA remain unchanged")
	persist();print("TOWN_TRANSFER_FINISHED failures=",report.failures," transfer_ms=",report.transfer_ms," report=",output)
	world.free();current_scene=null
	for frame in 3:await process_frame
	quit(0 if report.failures==0 else 1)
