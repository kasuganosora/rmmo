extends RefCounted
## Optional experiment on an already loaded TEMPORARY map, never an optimization.
## Usage: await preload("res://tools/problem_chunk_physics_probe.gd").new().run(world)
## Does not move the player, read mesh triangles, write files, or change authored data.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const DOWN:=Vector3(0,-.003,0)
var _running:=false
var _cancelled:=false

func cancel()->void:_cancelled=true

func run(world:Node,options:Dictionary={})->Dictionary:
	if _running:return {"ok":false,"error":"probe_already_running"}
	if not is_instance_valid(world) or not world.is_inside_tree():return {"ok":false,"error":"world_missing"}
	var map_root:Node=world.get("_map_root")
	var player:CharacterBody3D=world.get("_player")
	var camera:Node3D=world.get("_camera")
	var path:=str(world.get("_map_path"))
	if not Paths.allowed(path,Paths.external_root().path_join("cache/world3d")):
		return {"ok":false,"error":"temporary_map_required"}
	if not is_instance_valid(map_root) or not is_instance_valid(player) or not is_instance_valid(camera):
		return {"ok":false,"error":"loaded_world_required"}
	if not bool(world.get("_ready_for_play")) or bool(world.get("_transfer_pending")):
		return {"ok":false,"error":"stationary_playable_world_required"}
	var navigation:Node=world.get("_navigation")
	if is_instance_valid(navigation) and bool(navigation.get("_resizing")):
		return {"ok":false,"error":"navigation_resize_in_progress"}
	var capsule:=_capsule_bounds(player)
	if not capsule.get("ok",false):return capsule
	var focus:Vector3=camera.get("last_focus");var desired:Vector3=camera.get("last_desired")
	if not focus.is_finite() or not desired.is_finite() or focus.distance_squared_to(desired)<.000001:
		return {"ok":false,"error":"camera_follow_not_initialized"}
	var query:=PhysicsShapeQueryParameters3D.new()
	var sphere:=SphereShape3D.new();sphere.radius=.2
	query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,focus)
	query.motion=desired-focus;query.margin=.015;query.collide_with_areas=false
	query.exclude=camera.visual_exclusions()
	var camera_bounds:=AABB(focus,Vector3.ZERO).expand(desired).grow(sphere.radius+query.margin)
	var character_bounds:AABB=capsule.bounds
	character_bounds=character_bounds.merge(AABB(character_bounds.position+DOWN,character_bounds.size)).grow(player.safe_margin)
	var tree:=world.get_tree()
	var deferred:Node=map_root.get_node_or_null("DeferredAssets")
	var saved:Dictionary={"nodes":[],"player_transform":player.global_transform,"velocity":player.velocity,
		"locked":player.get("input_locked"),"geometry_blocked":player.get("geometry_blocked"),
		"deferred_active":deferred.get("_active") if deferred!=null else false,
		"queue":_queue_snapshot(deferred),"bodies":{},"body_ids":{},"stream":_stream_snapshot(map_root)}
	_running=true;_cancelled=false
	var began:=Time.get_ticks_usec()
	var report:Dictionary={"ok":false,"error":"","map":path,"candidates":[],"skipped":[],
		"samples":clampi(int(options.get("samples",11)),3,101),"warmup":clampi(int(options.get("warmup",2)),0,20),
		"camera":{"focus":_vec(focus),"desired":_vec(desired),"radius":.2,"margin":.015,"mask":query.collision_mask,"exclude_count":query.exclude.size(),"bounds":_box(camera_bounds)},
		"character":{"position":_vec(player.global_position),"basis":[_vec(player.global_basis.x),_vec(player.global_basis.y),_vec(player.global_basis.z)],"motion":_vec(DOWN),"margin":player.safe_margin,"mask":player.collision_mask,"bounds":_box(character_bounds)},
		"note":"A/B query diagnosis only. collision_layer=0 is temporary, never a proposed fix. Median deltas are not additive; changed collision early-outs can change query paths. Only stream_bodies are tested; grouped/non-stream bodies remain enabled.",
		"queue_note":"quiesce cancels and reclaims admitted work; pending identities/order and demand tickets are preserved. Restoring active/process flags permits normal retry, not restoration of completed worker progress.",
		"jobs_before_quiesce":deferred.get("_jobs").size() if deferred!=null else 0}
	# Never set process_mode=DISABLED or pause the tree: CollisionObject3D's
	# default disable_mode removes it from the physics space and invalidates A/B.
	for node:Node in [world,player,camera,navigation,world.get("_combat")]:_pause_callbacks(node,saved.nodes)
	for name_:String in ["DeferredAssets","AssetResidency","GroundRenderBatches","StreamCollisionPreparer","FortificationCollisionBatches"]:
		_pause_callbacks(map_root.get_node_or_null(name_),saved.nodes)
	player.set("input_locked",true);player.set("geometry_blocked",true)
	var quiet_started:=Time.get_ticks_usec()
	if deferred!=null:await deferred.quiesce()
	report.quiesce_ms=(Time.get_ticks_usec()-quiet_started)/1000.
	# All subsequent failures flow through the common restoration block below.
	var candidates:Array=[]
	if not _alive(world,map_root,player):report.error="world_removed_during_quiesce"
	else:
		# Quiescence is preparation, outside the experiment. It may discard a
		# worker's hydrated record back to its compact retry form. Compare the
		# experiment against the post-quiesce queue/stream, and report that setup
		# transition separately instead of calling it a failed restoration.
		var quiet_queue:=_queue_snapshot(deferred)
		var quiet_stream:=_stream_snapshot(map_root)
		var changed_keys:Array=[]
		for key:Variant in saved.stream:
			if saved.stream[key]!=quiet_stream.get(key):changed_keys.append(str(key))
		report.quiesce_changes={"queue_changed":saved.queue!=quiet_queue,"stream_changed_keys":changed_keys,"pending_before":saved.queue.get("pending",[]).size(),"pending_after":quiet_queue.get("pending",[]).size(),"jobs_after":deferred.get("_jobs").size() if deferred!=null else 0}
		saved.queue=quiet_queue;saved.stream=quiet_stream
		var bodies:Dictionary=map_root.get_meta("stream_bodies",{})
		for uuid:Variant in bodies:
			var body:Variant=bodies[uuid]
			if not is_instance_valid(body) or not body is CollisionObject3D:continue
			saved.bodies[body.get_instance_id()]={"body":body,"layer":body.collision_layer,"mask":body.collision_mask,"transform":body.global_transform}
			saved.body_ids[uuid]=body.get_instance_id()
		candidates=_candidates(map_root,bodies,camera_bounds,character_bounds,query.collision_mask,player.collision_mask,report.skipped)
		report.candidate_count=candidates.size();report.resident_body_count=bodies.size()
		await _sync_physics(tree)
		var deadline:=Time.get_ticks_usec()+int(clampf(float(options.get("max_seconds",180.)),1.,1800.)*1000000.)
		var setup:={"world":world,"map":map_root,"player":player,"transform":saved.player_transform,"query":query,"samples":report.samples,"warmup":report.warmup,"deadline":deadline}
		if candidates.is_empty():report.error="no_local_stream_body_candidates"
		else:
			report.baseline=await _sample(tree,setup)
			if not report.baseline.ok:report.error=report.baseline.error
		for candidate:Dictionary in candidates:
			if not str(report.error).is_empty():break
			var body:CollisionObject3D=candidate.body
			var row:Dictionary=candidate.duplicate();row.erase("body")
			row.before=await _sample(tree,setup)
			if not row.before.ok:report.error=row.before.error;report.candidates.append(row);break
			if not is_instance_valid(body):report.error="candidate_removed";report.candidates.append(row);break
			body.collision_layer=0
			await _sync_physics(tree)
			row.without=await _sample(tree,setup)
			# Restore immediately, including cancellation/deadline/sample failure.
			if is_instance_valid(body):body.collision_layer=int(candidate.layer)
			await _sync_physics(tree)
			row.layer_restored=is_instance_valid(body) and body.collision_layer==int(candidate.layer)
			if not row.without.ok:report.error=row.without.error
			elif not row.layer_restored:report.error="candidate_restore_failed"
			else:
				row.after=await _sample(tree,setup)
				if not row.after.ok:report.error=row.after.error
				else:
					row.camera_comparison=_comparison(report.baseline.camera,row.before.camera,row.without.camera,row.after.camera)
					row.character_comparison=_comparison(report.baseline.character,row.before.character,row.without.character,row.after.character)
			report.candidates.append(row)
			report.last_uuid=candidate.uuid
	# Restore every snapshotted layer defensively before enabling any callbacks.
	var restore:={"layers":true,"masks":true,"body_transforms":true,"player_transform":false,"player_velocity":false,"player_flags":false,"callbacks":true,"queue":false,"stream":false,"body_membership":false}
	for entry:Dictionary in saved.bodies.values():
		if not is_instance_valid(entry.body):restore.layers=false;restore.masks=false;restore.body_transforms=false;continue
		entry.body.collision_layer=entry.layer
		restore.layers=restore.layers and entry.body.collision_layer==entry.layer
		restore.masks=restore.masks and entry.body.collision_mask==entry.mask
		restore.body_transforms=restore.body_transforms and entry.body.global_transform==entry.transform
	await _sync_physics(tree)
	if is_instance_valid(player):
		# test_move must not move the body. Do not hide external movement by
		# teleporting it back; report a failed restoration/invariance check instead.
		restore.player_transform=player.global_transform==saved.player_transform
		restore.player_velocity=player.velocity==saved.velocity
		player.set("input_locked",saved.locked);player.set("geometry_blocked",saved.geometry_blocked)
		restore.player_flags=player.get("input_locked")==saved.locked and player.get("geometry_blocked")==saved.geometry_blocked
	if is_instance_valid(deferred):deferred.set("_active",saved.deferred_active)
	restore.queue=_queue_snapshot(deferred)==saved.queue
	if is_instance_valid(map_root):
		restore.stream=_stream_snapshot(map_root)==saved.stream
		var current_ids:Dictionary={}
		for uuid:Variant in map_root.get_meta("stream_bodies",{}):
			var body:Variant=map_root.get_meta("stream_bodies")[uuid]
			if is_instance_valid(body):current_ids[uuid]=body.get_instance_id()
		restore.body_membership=current_ids==saved.body_ids
	for state:Dictionary in saved.nodes:
		if not is_instance_valid(state.node):restore.callbacks=false;continue
		state.node.set_process(state.process);state.node.set_physics_process(state.physics)
		state.node.set_process_input(state.input);state.node.set_process_unhandled_input(state.unhandled);state.node.set_process_unhandled_key_input(state.key)
		restore.callbacks=restore.callbacks and state.node.is_processing()==state.process and state.node.is_physics_processing()==state.physics and state.node.is_processing_input()==state.input and state.node.is_processing_unhandled_input()==state.unhandled and state.node.is_processing_unhandled_key_input()==state.key
	restore.deferred_active=not is_instance_valid(deferred) or deferred.get("_active")==saved.deferred_active
	report.restoration=restore
	if not restore.values().all(func(value):return value) and str(report.error).is_empty():report.error="state_restoration_or_invariance_failed"
	report.ok=str(report.error).is_empty();report.cancelled=_cancelled;report.elapsed_ms=(Time.get_ticks_usec()-began)/1000.
	_running=false
	return report

func _sample(tree:SceneTree,setup:Dictionary)->Dictionary:
	var camera_times:Array=[];var character_times:Array=[];var fractions:Array=[];var collisions:Array=[]
	for index in int(setup.warmup)+int(setup.samples):
		await _sync_physics(tree)
		if _cancelled:return {"ok":false,"error":"cancelled"}
		if Time.get_ticks_usec()>int(setup.deadline):return {"ok":false,"error":"probe_deadline"}
		if not _alive(setup.world,setup.map,setup.player):return {"ok":false,"error":"world_removed"}
		var player:CharacterBody3D=setup.player
		if player.global_transform!=setup.transform:return {"ok":false,"error":"player_moved_during_probe"}
		var space:=player.get_world_3d().direct_space_state
		var camera_us:=0;var character_us:=0;var result:=PackedFloat32Array();var collided:=false
		# Alternate ordering to avoid systematically attributing a warm-cache
		# advantage to the query always executed second. Timers exclude awaits.
		for kind in ([0,1] if index%2==0 else [1,0]):
			var began:=Time.get_ticks_usec()
			if kind==0:result=space.cast_motion(setup.query);camera_us=Time.get_ticks_usec()-began
			else:collided=player.test_move(setup.transform,DOWN,null,player.safe_margin,false,1);character_us=Time.get_ticks_usec()-began
		if player.global_transform!=setup.transform:return {"ok":false,"error":"test_move_changed_transform"}
		if index>=int(setup.warmup):
			camera_times.append(camera_us);character_times.append(character_us);fractions.append(Array(result));collisions.append(collided)
	return {"ok":true,"camera":_stats(camera_times),"character":_stats(character_times),"camera_fractions":fractions,"character_collided":collisions}

static func _sync_physics(tree:SceneTree)->void:
	# Resume in idle after a complete physics frame. Changed body layers have
	# reached broad phase and direct-space queries are outside physics callbacks.
	await tree.physics_frame
	await tree.process_frame

static func _pause_callbacks(node:Node,states:Array)->void:
	if not is_instance_valid(node):return
	for state:Dictionary in states:
		if state.node==node:return
	states.append({"node":node,"process":node.is_processing(),"physics":node.is_physics_processing(),"input":node.is_processing_input(),"unhandled":node.is_processing_unhandled_input(),"key":node.is_processing_unhandled_key_input()})
	node.set_process(false);node.set_physics_process(false);node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false)

static func _alive(world:Node,map_root:Node,player:CharacterBody3D)->bool:
	return is_instance_valid(world) and world.is_inside_tree() and is_instance_valid(map_root) and map_root.is_inside_tree() and is_instance_valid(player) and player.is_inside_tree() and world.get("_map_root")==map_root

static func _capsule_bounds(player:CharacterBody3D)->Dictionary:
	var found:=false;var result:=AABB()
	for owner_id:int in player.get_shape_owners():
		if player.is_shape_owner_disabled(owner_id):continue
		for index in player.shape_owner_get_shape_count(owner_id):
			var shape:=player.shape_owner_get_shape(owner_id,index)
			if not shape is CapsuleShape3D:return {"ok":false,"error":"expected_only_player_capsules"}
			var size_:=Vector3(shape.radius*2,shape.height,shape.radius*2)
			var bounds:AABB=player.global_transform*player.shape_owner_get_transform(owner_id)*AABB(-size_*.5,size_)
			result=result.merge(bounds) if found else bounds;found=true
	return {"ok":found,"bounds":result,"error":"" if found else "player_capsule_missing"}

static func _candidates(map_root:Node,bodies:Dictionary,camera_bounds:AABB,character_bounds:AABB,camera_mask:int,character_mask:int,skipped:Array)->Array:
	var by_id:Dictionary=map_root.get_meta("stream_by_id",{})
	# Older callers may lack the lookup; inspect only resident spec metadata,
	# never serialized records, ResourceLoader, CPU surfaces or mesh.get_faces().
	if by_id.is_empty():
		by_id={} # Do not populate or modify the map's own empty metadata dictionary.
		for spec:Dictionary in map_root.get_meta("stream_library",[]):
			if bodies.has(spec.get("uuid","")):by_id[spec.uuid]=spec
	var selected:Dictionary={}
	for uuid:Variant in bodies:
		var body:Variant=bodies[uuid]
		if not is_instance_valid(body) or not body is CollisionObject3D:skipped.append({"uuid":str(uuid),"reason":"missing_body"});continue
		if (body.collision_layer&(camera_mask|character_mask))==0:continue
		if not by_id.has(uuid):skipped.append({"uuid":str(uuid),"reason":"missing_stream_spec"});continue
		var spec:Dictionary=by_id[uuid];var mesh:Mesh=spec.get("mesh")
		if mesh==null:skipped.append({"uuid":str(uuid),"reason":"missing_bounds_mesh"});continue
		var transform:Transform3D=spec.get("transform",body.global_transform)
		var bounds:AABB=transform*mesh.get_aabb()
		var collision_mesh:Mesh=spec.get("collision_mesh")
		if collision_mesh!=null and collision_mesh!=mesh:bounds=bounds.merge(transform*collision_mesh.get_aabb())
		var camera_overlap:=bounds.intersects(camera_bounds)
		var character_overlap:=bounds.intersects(character_bounds)
		if not camera_overlap and not character_overlap:continue
		var identity:int=body.get_instance_id()
		if selected.has(identity):selected[identity].uuids.append(str(uuid));continue
		var shapes:=0;var enabled:=0;var types:Dictionary={}
		for owner_id:int in body.get_shape_owners():
			for index in body.shape_owner_get_shape_count(owner_id):
				shapes+=1
				if not body.is_shape_owner_disabled(owner_id):enabled+=1
				var shape:Shape3D=body.shape_owner_get_shape(owner_id,index)
				var kind:=shape.get_class() if shape!=null else "null"
				types[kind]=int(types.get(kind,0))+1
		selected[identity]={"body":body,"uuid":str(uuid),"uuids":[str(uuid)],"body_name":str(body.name),"layer":body.collision_layer,"shape_count":shapes,"enabled_shape_count":enabled,"shape_types":types,"basis_baked":body.get_meta("collision_basis_baked",false),"bounds":_box(bounds),"camera_overlap":camera_overlap,"character_overlap":character_overlap}
	var result:Array=selected.values();result.sort_custom(func(a,b):return a.uuid<b.uuid)
	return result

static func _queue_snapshot(deferred:Node)->Dictionary:
	if not is_instance_valid(deferred):return {}
	var rows:Array=[]
	for item:Dictionary in deferred.get("pending"):rows.append([str(item.get("record",{}).get("uuid","")),str(item.get("path",""))])
	return {"pending":rows,"demands":deferred.get("_demands").duplicate(true),"scope":deferred.get_demand_scope()}

static func _stream_snapshot(map_root:Node)->Dictionary:
	var snapshot:Dictionary={}
	for key:String in ["stream_cursor","stream_plan_cursor","stream_chunk","stream_target","stream_visibility_revision","stream_source_revision"]:
		snapshot[key]=map_root.get_meta(key) if map_root.has_meta(key) else null
	for key:String in ["stream_library","stream_jobs","stream_candidates","stream_append_pending"]:
		var ids:Array=[]
		for spec:Dictionary in map_root.get_meta(key,[]):ids.append(str(spec.get("uuid","")))
		snapshot[key]=ids
	return snapshot

static func _stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort();var middle:int=sorted.size()/2
	var median:float=sorted[middle] if sorted.size()%2 else (float(sorted[middle-1])+float(sorted[middle]))*.5
	return {"median_us":median,"min_us":sorted.front(),"max_us":sorted.back(),"samples_us":values}

static func _comparison(baseline:Dictionary,before:Dictionary,without:Dictionary,after:Dictionary)->Dictionary:
	var reference:float=(float(before.median_us)+float(after.median_us))*.5
	return {"baseline_median_us":baseline.median_us,"paired_reference_median_us":reference,"without_median_us":without.median_us,"saved_us":reference-float(without.median_us),"without_over_baseline":float(without.median_us)/maxf(1.,float(baseline.median_us)),"without_over_paired":float(without.median_us)/maxf(1.,reference),"after_over_before":float(after.median_us)/maxf(1.,float(before.median_us))}

static func _vec(value:Vector3)->Array:return [value.x,value.y,value.z]
static func _box(value:AABB)->Dictionary:return {"position":_vec(value.position),"size":_vec(value.size)}
