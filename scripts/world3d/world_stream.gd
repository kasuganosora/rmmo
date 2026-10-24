extends RefCounted
## Small residency cells index near physics and kilometre-scale landscape views.

const Location = preload("res://scripts/world3d/world_location.gd")
const CHUNK_M := 32.0
const RENDER_RADIUS := 1
const BUILDING_VIEW_M := 1000.0
const BUILDING_RENDER_RADIUS := int(ceil(BUILDING_VIEW_M / CHUNK_M))
const COLLISION_RADIUS := 2
## Gameplay spreads a chunk swap across frames. Tests pass 0 and finish in one call.
const FRAME_BUDGET := 12
## Loading has no moving player; use a 24 ms time slice without a tiny
## object-count ceiling that otherwise wastes hundreds of loading frames.
const LOAD_BUDGET := 512
const GroundBatcher = preload("res://scripts/world3d/ground_batcher.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const CollisionGeometry = preload("res://scripts/world3d/model_collision_requirements.gd")
const FortCollision = preload("res://scripts/world3d/fortification_collision_batcher.gd")
const Landscape = preload("res://scripts/world3d/stream_landscape.gd")
const FrameBudget = preload("res://scripts/world3d/frame_work_budget.gd")
const APPEND_INDEX_FIELDS:Array[StringName]=[&"stream_by_id",&"stream_known",&"stream_index",&"stream_prop_index",&"stream_collision_index",&"stream_building_groups",&"stream_landscape",&"stream_append_state",&"stream_building_count",&"stream_collision_revision",&"stream_collision_candidate_cache"]

## Validated query reuse with an A/B fallback. Only candidates/bounds are cached;
## bodies, collision modes, exact footprints and physics stamps remain live.
static var collision_candidate_cache_enabled:=true
static var collision_priority_reuse_enabled:=true # Per reorder only; live geometry and collision checks are unchanged.
static var bounded_collision_priority_enabled:=true
static var incremental_collision_priority_enabled:=true
static var reuse_job_classification_enabled:=true
static var progressive_white_batches_enabled:=false # Diagnostic only: partial groups currently increase rebuild work.
static var sliced_loading_batches_enabled:=true # Diagnostic control; synchronous editor calls keep their existing contract.
static var white_time_slice_enabled:=true # Same interactive time bound without the legacy twelve-object ceiling.
static var white_collision_prefetch_enabled:=true # Same bounded face queue after the covered entry handoff.
static var ready_collision_bypass_enabled:=true # White runtime only; ready independent work may pass a pending shape.
static var legacy_retirement_validation_enabled:=false # Same-code diagnostic of the previous scan order/repeated validation.
static var sliced_retirement_schema_enabled:=true
static var resident_retirement_catalog_enabled:=true # Runtime index owns membership; false retains the diagnostic full-directory proof.
## Opt-in diagnostics add per-candidate clocks; leave off for timing A/B runs.
static var collision_readiness_profile_enabled:=false
const COLLISION_CANDIDATE_RANGES:=8
const COLLISION_CANDIDATE_CELLS:=64
const COLLISION_CANDIDATE_LIMIT:=8192
class CollisionCandidate:
	extends RefCounted
	var spec:Dictionary
	var mesh:Mesh
	var pose:=Transform3D.IDENTITY
	var local_bounds:=AABB()
	var area:=Rect2()
	var initialized:=false
	func _init(source:Dictionary)->void:spec=source


static func chunk_key(position: Vector3) -> Vector2i:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.chunk_key") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return Vector2i(
		floori(position.x / CHUNK_M) if is_finite(position.x) else 0,
		floori(position.z / CHUNK_M) if is_finite(position.z) else 0
	)


static func ring(origin: Vector3, radius: int) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.ring") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var center := chunk_key(origin)
	var keys := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			keys[Vector2i(center.x + dx, center.y + dz)] = true
	return keys


static func sync(map_root: Node, host: Node, origin: Vector3, budget: int = 0) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.sync") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var slice_usec:=24000 if budget>=LOAD_BUDGET else interactive_work_budget_usec(map_root,origin,budget)
	map_root.set_meta("stream_budget_origin",origin)
	if budget<=0 or not FrameBudget.enabled:
		_sync_work(map_root,host,origin,budget,Time.get_ticks_usec()+slice_usec if slice_usec>3000 and budget==FRAME_BUDGET else 0,slice_usec)
		return
	var allowed:=FrameBudget.allowance("collision",slice_usec,budget>=LOAD_BUDGET)
	if allowed<=0:return
	var started:=Time.get_ticks_usec()
	_sync_work(map_root,host,origin,budget,started+allowed,slice_usec)
	FrameBudget.charge("collision",started)

static func interactive_work_budget_usec(map_root:Node,origin:Vector3,budget:int=FRAME_BUDGET)->int:
	# A stationary tail can reuse idle publication time. Moving focus, new
	# source transactions and explicit caller limits retain the ordinary slice.
	if budget!=FRAME_BUDGET or not white_time_slice_enabled:return 3000
	if map_root.get_meta("stream_budget_origin",Vector3(INF,INF,INF))!=origin:return 3000
	if map_root.get_meta("stream_target",null)!=chunk_key(origin):return 3000
	if map_root.get_meta("stream_source_revision",0)!=map_root.get_meta("stream_applied_source_revision",0):return 3000
	return GroundBatcher.SETTLED_WHITE_WORK_BUDGET_USEC if GroundBatcher.can_borrow_publication_budget(map_root) else 3000

static func _sync_work(map_root:Node,host:Node,origin:Vector3,budget:int,deadline:int=0,slice_usec:int=0)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._sync_work") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var sync_started:=Time.get_ticks_usec()
	if slice_usec<=0:slice_usec=24000 if budget>=LOAD_BUDGET else 3000
	var face_lookahead:bool=budget>=LOAD_BUDGET or (budget==FRAME_BUDGET and white_collision_prefetch_enabled and preload("res://scripts/world3d/white_native_asset_cache.gd").active())
	var source_revision:=int(map_root.get_meta("stream_source_revision",0))
	if int(map_root.get_meta("stream_applied_source_revision",0))!=source_revision:
		# A source transaction changes residency independently of player position.
		# Reconsider live + requested cells, never the rectangle between sources.
		map_root.remove_meta("stream_target");map_root.remove_meta("stream_chunk")
		map_root.remove_meta("stream_candidate_work")
		map_root.set_meta("stream_applied_source_revision",source_revision)
	if budget<=0:
		var pending=map_root.get_node_or_null("StreamCollisionPreparer")
		if pending!=null:pending.cancel_pending()
	elif not face_lookahead or not preload("res://scripts/world3d/stream_collision_preparer.gd").prefetch_enabled:
		var pending=map_root.get_node_or_null("StreamCollisionPreparer")
		if pending!=null:pending._face_prefetch.cancel()
	var library: Array = _library(map_root)
	var known := _dict(map_root, &"stream_known")
	var meshes := _dict(map_root, &"stream_meshes")
	var bodies := _dict(map_root, &"stream_bodies")
	_index_buildings(map_root,library)
	var jobs := _jobs(map_root)
	var target := chunk_key(origin)
	# Total membership only. The default external-child count rebuilds and sorts
	# the entire child cache after removals (Godot Node::_update_children_cache).
	var child_count := map_root.get_child_count(true)
	var previous_chunk:Variant=map_root.get_meta(&"stream_chunk") if map_root.has_meta(&"stream_chunk") else null
	var unfinished:Array=[]
	var additions:Array=map_root.get_meta("stream_append_pending",[])
	# Finish the current district plan before absorbing more same-target work.
	# Repeated arrivals must not cancel an in-flight collision preparation or
	# reset the plan cursor forever; new entries remain explicitly queued.
	var settling:bool=budget>0 and _chunk_is(map_root,&"stream_target",target) and not _chunk_is(map_root,&"stream_chunk",target)
	if not additions.is_empty() and not settling:
		# Replan only newly published/unfinished entries, including when the player
		# has not crossed a chunk boundary. Never re-adopt the live scene graph.
		# A move may still be applying its old plan. Preserve that plan's target
		# before invalidating it for publication; its unapplied tail below plus
		# the target-to-target delta describe all remaining work. Losing the base
		# here forced a synchronous full-resident scan on moving publications.
		if previous_chunk==null and map_root.has_meta("stream_target") and not _chunk_is(map_root,&"stream_target",target):
			previous_chunk=map_root.get_meta("stream_target")
		unfinished.append_array(additions)
		unfinished.append_array(jobs.slice(int(map_root.get_meta("stream_cursor",0))))
		unfinished.append_array(map_root.get_meta("stream_candidates",[]).slice(int(map_root.get_meta("stream_plan_cursor",0))))
		for bin:Array in map_root.get_meta("stream_plan_bins",[]):unfinished.append_array(bin)
		map_root.remove_meta("stream_append_pending")
		map_root.remove_meta("stream_target")
	if map_root.has_meta("stream_candidate_work"):
		var work:RefCounted=map_root.get_meta("stream_candidate_work")
		# No residency has changed while this candidate selection is pending.
		# An interrupted turn starts from the same settled/pending base, not from
		# a destination whose jobs have never been applied.
		previous_chunk=work.previous;unfinished.append_array(work.unfinished)
	if previous_chunk==null and map_root.has_meta(&"stream_target") and not _chunk_is(map_root,&"stream_target",target):
		previous_chunk=map_root.get_meta(&"stream_target")
		unfinished.append_array(jobs.slice(int(map_root.get_meta(&"stream_cursor",0))))
		if map_root.has_meta(&"stream_candidates"):
			unfinished.append_array(map_root.get_meta(&"stream_candidates").slice(int(map_root.get_meta(&"stream_plan_cursor",0))))
		for bin:Array in map_root.get_meta(&"stream_plan_bins",[]):unfinished.append_array(bin)
	if unfinished.is_empty() and jobs.is_empty() and _chunk_is(map_root, &"stream_chunk", target) and _child_count_is(map_root, child_count):
		return
	if not _child_count_is(map_root, child_count):
		previous_chunk=null
		map_root.remove_meta("stream_candidate_work")
		_adopt(map_root, library, known)
		_index_buildings(map_root,library)
		child_count = map_root.get_child_count(true)
		map_root.remove_meta(&"stream_target")
	if not _chunk_is(map_root, &"stream_target", target):
		var preparer=map_root.get_node_or_null("StreamCollisionPreparer")
		if preparer!=null:preparer.cancel_pending()
		map_root.set_meta(&"stream_target", target)
		map_root.remove_meta(&"stream_chunk")
		jobs.clear()
		map_root.remove_meta("stream_job_catalog")
		map_root.remove_meta("stream_ready_bypass_scan")
		map_root.remove_meta("stream_collision_priority_work")
		map_root.remove_meta("stream_collision_priority_partition")
		if previous_chunk is Vector2i and budget>0 and budget<LOAD_BUDGET and map_root.get_meta("stream_sources",{}).is_empty() and _entry_clip(map_root)==null:
			map_root.set_meta("stream_candidate_work",preload("res://scripts/world3d/stream_candidate_plan.gd").new(map_root,previous_chunk,target,unfinished,load("res://scripts/world3d/world_stream.gd")))
			map_root.remove_meta("stream_candidates")
		else:
			map_root.remove_meta("stream_candidate_work")
			map_root.set_meta(&"stream_candidates", _changed_candidates(map_root,previous_chunk,target,unfinished) if previous_chunk is Vector2i else _candidates(map_root, target, meshes, bodies))
		map_root.set_meta(&"stream_plan_cursor", 0)
		map_root.set_meta(&"stream_plan_bins", [[], [], [], [], []])
		map_root.set_meta("stream_plan_ids",{})
		map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_children", map_root.get_child_count(true))
	map_root.set_meta(&"stream_library", library)
	var plan_started:=Time.get_ticks_usec()
	if map_root.has_meta("stream_candidate_work"):
		var work:RefCounted=map_root.get_meta("stream_candidate_work")
		if budget<=0:
			while not work.advance(12000):pass
		elif not work.advance(mini(12000 if budget>=LOAD_BUDGET else 1500,maxi(1,deadline-Time.get_ticks_usec())) if deadline>0 else (12000 if budget>=LOAD_BUDGET else 1500)):return
		map_root.set_meta("stream_candidates",work.selected.values())
		map_root.remove_meta("stream_candidate_work")
		# Selection used this frame's budget. Planning/attachment starts next frame.
		if budget>0 and budget<LOAD_BUDGET:return
	var detailed:=bool(map_root.get_meta("profile_collision_details",false))
	if detailed:map_root.set_meta("stream_plan_detail",{})
	var plan_call_started:=Time.get_ticks_usec() if detailed else 0
	# A positive outer allowance must advance a pending plan even when fixed
	# metadata checks consumed a tiny slice. Planning itself stops after a unit.
	var planned_work:=map_root.has_meta("stream_candidates")
	var plan_ready:=_plan_jobs(map_root, jobs, meshes, bodies, target, budget,deadline)
	if detailed:map_root.get_meta("stream_plan_detail")["call_ms"]=(Time.get_ticks_usec()-plan_call_started)/1000.
	if not plan_ready:
		if detailed:map_root.set_meta("stream_phase_timing",{"frame":Engine.get_process_frames(),"phase":"planning","index_ms":(plan_started-sync_started)/1000.,"plan_ms":(Time.get_ticks_usec()-plan_started)/1000.,"plan_detail":map_root.get_meta("stream_plan_detail")})
		if map_root.has_meta("profile_frame") and Time.get_ticks_usec()-sync_started>10000:print("STREAM_PLAN_SLOW ",{"index":(plan_started-sync_started)/1000.0,"plan":(Time.get_ticks_usec()-plan_started)/1000.0})
		if budget>=LOAD_BUDGET:_profile_load(map_root,{"index":plan_started-sync_started,"plan":Time.get_ticks_usec()-plan_started})
		return
	if planned_work and deadline>0 and Time.get_ticks_usec()>=deadline:return
	var cursor := int(map_root.get_meta(&"stream_cursor", 0))
	var draw := _source_ring(map_root,target, RENDER_RADIUS)
	var solid := _source_ring(map_root,target, COLLISION_RADIUS)
	var appended_now:=false
	if budget>0 and budget<LOAD_BUDGET and not map_root.has_meta("stream_collision_priority_work"):
		appended_now=append_ready_jobs(map_root,jobs,cursor,draw,solid,meshes,bodies)
	if budget>0 and budget<LOAD_BUDGET and cursor<jobs.size():
		var priority_origin:Variant=map_root.get_meta("stream_collision_priority_origin",Vector3(INF,INF,INF))
		if bounded_collision_priority_enabled:
			var work:RefCounted=map_root.get_meta("stream_collision_priority_work") if map_root.has_meta("stream_collision_priority_work") else null
			if work==null and (appended_now or not priority_origin is Vector3 or Vector2(priority_origin.x,priority_origin.z).distance_squared_to(Vector2(origin.x,origin.z))>=1.0):
				# A stationary append changes only new/explicitly affected specs.
				# Pending tail bodies/visuals are still untouched by this serial plan.
				# Any movement or new plan reclassifies from live state as before.
				var previous:Dictionary=map_root.get_meta("stream_collision_priority_classes",{}) if incremental_collision_priority_enabled and priority_origin==origin else {}
				var partition:Dictionary=map_root.get_meta("stream_collision_priority_partition",{}) if not previous.is_empty() else {}
				work=load("res://scripts/world3d/collision_priority_plan.gd").new(load("res://scripts/world3d/world_stream.gd"),jobs,cursor,origin,bodies,draw,meshes,previous,map_root.get_meta("stream_collision_priority_dirty",{}),partition)
				map_root.remove_meta("stream_collision_priority_dirty")
				map_root.set_meta("stream_collision_priority_work",work)
			if work!=null:
				if not work.advance(mini(2000,maxi(1,deadline-Time.get_ticks_usec())) if deadline>0 else 2000):return
				map_root.set_meta("stream_collision_priority_origin",work.origin)
				map_root.set_meta("stream_collision_priority_classes",work.classifications)
				map_root.set_meta("stream_collision_priority_partition",work.partition)
				for field:String in ["classified_rows","reused_rows","bulk_reused_rows"]:map_root.set_meta("stream_priority_"+field,int(map_root.get_meta("stream_priority_"+field,0))+int(work.profile[field]))
				map_root.remove_meta("stream_collision_priority_work")
				map_root.remove_meta("stream_ready_bypass_scan")
				# Keep progress even if movement requests another reorder next frame.
		else:
			if appended_now or not priority_origin is Vector3 or Vector2(priority_origin.x,priority_origin.z).distance_squared_to(Vector2(origin.x,origin.z))>=1.0:
				prioritize_local_collisions(jobs,cursor,origin,bodies,draw,meshes)
				map_root.remove_meta("stream_ready_bypass_scan")
				map_root.set_meta("stream_collision_priority_origin",origin)
	var initial_cursor:=cursor
	var left := 1000000 if budget <= 0 else budget
	# Cheap cached instances/removals used to stop after twelve objects even
	# with most of the existing 3 ms allowance unused. Only the measured white
	# runtime uses time-based throughput; explicit small caller budgets and the
	# ordinary textured route retain their count limits. The checks below still
	# stop after each indivisible collision/apply operation, including deadlines.
	if budget==FRAME_BUDGET and white_time_slice_enabled and preload("res://scripts/world3d/white_native_asset_cache.gd").active():left=1000000
	var wrapper_profile:Variant=_collision_wrapper_slots(map_root) if detailed else null
	var apply_started := Time.get_ticks_usec()
	# The actual loading plan already bounds demand. Legacy/unclipped loading
	# needs the same batched CPU lookahead as entry-clipped loading; otherwise
	# each tiny imported mesh incurs its own worker and render-frame wait.
	if face_lookahead:
		_prefetch_collisions(map_root,host,jobs,cursor,solid,bodies,500 if budget<LOAD_BUDGET else 0)
	while left > 0 and cursor < jobs.size():
		if deadline>0 and Time.get_ticks_usec()>=deadline and cursor>initial_cursor:break
		var wrapper_stamps:Variant=null
		if detailed and budget>0 and budget<LOAD_BUDGET:
			if int(wrapper_profile.count)<wrapper_profile.slots.size():
				var wrapper_row:Dictionary=wrapper_profile.slots[wrapper_profile.count]
				wrapper_profile.count+=1;wrapper_row.uuid=str(jobs[cursor].uuid)
				wrapper_stamps=wrapper_row.stamps;wrapper_stamps.fill(0)
			else:wrapper_profile.dropped+=1
		var prepare_started:=Time.get_ticks_usec()
		if wrapper_stamps!=null:wrapper_stamps[0]=prepare_started
		# Covered entry and walking use identical exact collision geometry. A
		# larger loading budget must not silently select a monolithic collider.
		var collision_budget:=maxi(1,24000-int(Time.get_ticks_usec()-apply_started)) if budget>=LOAD_BUDGET else 1500
		if deadline>0:collision_budget=mini(collision_budget,maxi(1,deadline-Time.get_ticks_usec()))
		var collision_ready:bool=budget<=0 or _prepare_collision(map_root,host,jobs[cursor],solid,bodies,wrapper_stamps,collision_budget)
		if wrapper_stamps!=null:wrapper_stamps[7]=Time.get_ticks_usec()
		# Detailed runs retain absolute endpoints instead of synchronously printing
		# inside the interval whose unexplained tail is being investigated.
		if not detailed and map_root.has_meta("profile_frame") and Time.get_ticks_usec()-prepare_started>10000:
			print("COLLISION_PREP_SLOW ",jobs[cursor].uuid," ",(Time.get_ticks_usec()-prepare_started)/1000.0," ",map_root.get_meta("collision_prepare_timing",{}) if map_root.get_meta("profile_collision_details",false) else {})
		var apply_index:=cursor
		if not collision_ready:
			if ready_collision_bypass_enabled and budget>0 and preload("res://scripts/world3d/white_native_asset_cache.gd").active():
				var bypass_deadline:=apply_started+slice_usec
				if deadline>0:bypass_deadline=mini(bypass_deadline,deadline)
				apply_index=_ready_collision_bypass(map_root,jobs,cursor,draw,solid,meshes,bodies,bypass_deadline)
			if apply_index<=cursor:break
			# Selection is read-only. Only the chosen ready item may acquire its
			# cached shape; no other sliced terrain is passed to the active cursor.
			prepare_started=Time.get_ticks_usec()
			if not _prepare_collision(map_root,host,jobs[apply_index],solid,bodies,null,collision_budget):break
		# Finishing a large terrain shape can consume this frame's budget by
		# itself. Keep the prepared shape and attach its body on the next frame.
		# Optional planning/lookahead cannot monopolise every frame before a
		# ready head is attached. A genuinely slow shape still yields here; its
		# cached result gets one attachment on the next turn before yielding.
		if budget>0 and Time.get_ticks_usec()-apply_started>=slice_usec and (cursor>initial_cursor or Time.get_ticks_usec()-prepare_started>=slice_usec):break
		if apply_index!=cursor:
			if Time.get_ticks_usec()-apply_started>=slice_usec or (deadline>0 and Time.get_ticks_usec()>=deadline):break
			# Stable insertion leaves the held source first next turn. Swapping
			# would bury it behind unrelated entries and could switch its terrain
			# owner. Priority ranges describe the old order and cannot be reused.
			var ready:Dictionary=jobs[apply_index]
			# The scan may have advanced through several bounded windows. Move
			# references natively instead of a script loop across that whole prefix.
			jobs.remove_at(apply_index);jobs.insert(cursor,ready)
			map_root.remove_meta("stream_collision_priority_partition")
			map_root.remove_meta("stream_ready_bypass_scan")
			map_root.set_meta("stream_ready_bypass_applied",int(map_root.get_meta("stream_ready_bypass_applied",0))+1)
		var item_started:=Time.get_ticks_usec()
		if _apply(map_root, host, jobs[cursor], draw, solid, meshes, bodies):
			map_root.set_meta("stream_visibility_revision",int(map_root.get_meta("stream_visibility_revision",0))+1)
		if map_root.has_meta("stream_job_catalog"):
			var catalog:Dictionary=map_root.get_meta("stream_job_catalog")
			catalog.ids.erase(jobs[cursor].uuid);catalog.cursor=cursor+1
		if map_root.has_meta("profile_frame") and Time.get_ticks_usec()-item_started>10000:print("STREAM_SLOW ",jobs[cursor].uuid," ",(Time.get_ticks_usec()-item_started)/1000.0," ms ",jobs[cursor].get("profile_body",{}))
		cursor += 1
		left -= 1
		var item_us:=Time.get_ticks_usec()-item_started
		if budget>0 and item_us>=10000:
			# A single large fortification/terrain source can own most of this
			# frame. Do not stack batch/collision finalization on top of it; the
			# source is already applied and the next service resumes from here.
			map_root.set_meta(&"stream_cursor",cursor)
			return
		if budget > 0 and Time.get_ticks_usec() - apply_started >= slice_usec:
			break
	map_root.set_meta(&"stream_cursor", cursor)
	var batch_started:=Time.get_ticks_usec()
	var batcher: Node3D = map_root.get_node_or_null("GroundRenderBatches")
	if batcher == null:
		batcher = GroundBatcher.new(); batcher.name = "GroundRenderBatches"; batcher.set_meta("stream_instance",true); map_root.add_child(batcher)
	batcher.work_budget_usec=24000 if budget>=LOAD_BUDGET else 2000
	# Source visuals are visible while residency jobs are applied. A long queue
	# used to postpone every new batch until all collisions/sources completed.
	# The batcher now resumes exact root prefixes and retains completed bins:
	# allow bounded growth checkpoints, never a rescan for every twelve objects.
	var revision:int=map_root.get_meta("stream_visibility_revision",0)
	var sliced_loading:bool=budget>=LOAD_BUDGET and sliced_loading_batches_enabled
	var checkpoint:=false
	if progressive_white_batches_enabled and budget>0 and budget<LOAD_BUDGET and cursor<jobs.size() and preload("res://scripts/world3d/white_native_asset_cache.gd").active():
		var added:int=meshes.size()-int(map_root.get_meta("stream_batch_source_count",0))
		checkpoint=added>=64 and Time.get_ticks_msec()-int(map_root.get_meta("stream_batch_checkpoint_msec",0))>=250
	if (cursor>=jobs.size() or checkpoint) and int(map_root.get_meta("stream_batch_revision",-1))!=revision:
		if (budget>0 and budget<LOAD_BUDGET) or sliced_loading:batcher.request_residency_sync(meshes.values(),[],preload("res://scripts/world3d/white_native_asset_cache.gd").active())
		else:batcher.sync(meshes.values())
		map_root.set_meta("stream_batch_revision",revision)
		map_root.set_meta("stream_batch_source_count",meshes.size())
		map_root.set_meta("stream_batch_checkpoint_msec",Time.get_ticks_msec())
		if checkpoint:map_root.set_meta("stream_batch_checkpoints",int(map_root.get_meta("stream_batch_checkpoints",0))+1)
	var batches_prepared:=true
	if sliced_loading and cursor>=jobs.size():
		batches_prepared=_finish_loading_sources(map_root,batcher,deadline if deadline>0 else sync_started+24000)
	elif not sliced_loading and (cursor>=jobs.size() or checkpoint):
		_finish_loading_sources(map_root,batcher,0,false)
	if budget <= 0: batcher.flush()
	var collision_batches=map_root.get_node_or_null("FortificationCollisionBatches")
	if collision_batches==null:
		collision_batches=FortCollision.new(); map_root.add_child(collision_batches)
		map_root.set_meta("stream_fortification_collision_dirty",true)
	var fort_sync_ms:=0.0
	# Ordinary scenery can consume many residency slices without changing any
	# wall source. Reconcile exact collision only after an actual source update,
	# still before this slice can mark residency settled or expose readiness.
	if map_root.get_meta("stream_fortification_collision_dirty",false):
		var entries: Array=[]
		for spec: Dictionary in _dict(map_root,&"fortification_collision_sources").values(): entries.append(FortCollision.entry(spec.mesh,spec.transform,spec.uuid,spec.extras))
		collision_batches.sync(entries)
		fort_sync_ms=collision_batches.last_sync_ms
		map_root.remove_meta("stream_fortification_collision_dirty")
	if detailed:map_root.set_meta("stream_phase_timing",{"frame":Engine.get_process_frames(),"phase":"apply","index_ms":(plan_started-sync_started)/1000.,"plan_ms":(apply_started-plan_started)/1000.,"plan_detail":map_root.get_meta("stream_plan_detail"),"apply_ms":(batch_started-apply_started)/1000.,"batch_ms":(Time.get_ticks_usec()-batch_started)/1000.,"fort_ms":fort_sync_ms})
	if map_root.has_meta("profile_frame") and Time.get_ticks_usec()-sync_started>10000:print("STREAM_PHASES ",{"index":(plan_started-sync_started)/1000.0,"plan":(apply_started-plan_started)/1000.0,"apply":(batch_started-apply_started)/1000.0,"batch":(Time.get_ticks_usec()-batch_started)/1000.0,"fort":fort_sync_ms})
	map_root.set_meta(&"stream_library", library)
	map_root.set_meta(&"stream_children", map_root.get_child_count(true))
	if budget<=0:map_root.set_meta("stream_profile_ms",{"index":(plan_started-sync_started)/1000.0,"plan":(apply_started-plan_started)/1000.0,"apply":(batch_started-apply_started)/1000.0,"batch":(Time.get_ticks_usec()-batch_started)/1000.0})
	if budget>=LOAD_BUDGET:_profile_load(map_root,{"index":plan_started-sync_started,"plan":apply_started-plan_started,"apply":batch_started-apply_started,"batch":Time.get_ticks_usec()-batch_started})
	if cursor < jobs.size() or not batches_prepared:
		return
	var collision_preparer=map_root.get_node_or_null("StreamCollisionPreparer")
	if collision_preparer!=null:collision_preparer._face_prefetch.cancel()
	jobs.clear()
	map_root.remove_meta("stream_job_catalog")
	map_root.remove_meta("stream_ready_bypass_scan")
	map_root.remove_meta("stream_collision_priority_classes")
	map_root.remove_meta("stream_collision_priority_partition")
	map_root.remove_meta("stream_collision_priority_dirty")
	map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_chunk", target)

static func _track_deferred_source(map_root:Node,source:MeshInstance3D)->void:
	# Only _spawn creates this obligation. Track it at admission instead of
	# scanning every resident mesh after every later publication burst.
	if source.has_meta("deferred_gpu"):
		if not map_root.has_meta("deferred_gpu_sources"):map_root.set_meta("deferred_gpu_sources",[])
		map_root.get_meta("deferred_gpu_sources").append(source)

static func prepare_map_disposal(map_root:Node,tree:SceneTree=null)->void:
	# Permanent replacement only. Stop producers, then disconnect batch member
	# exit callbacks before ANY source exits. Otherwise the first dying member
	# restores all surviving CPU sources just before the whole map is destroyed.
	# Temporary tree detach and individual source removal keep their restore path.
	map_root.remove_meta("stream_ready_bypass_scan")
	for service:String in ["GroundRenderBatches","StreamCollisionPreparer"]:
		var outgoing:Node=map_root.get_node_or_null(service)
		if outgoing==null:continue
		outgoing.retire_workers(tree)
		if service=="GroundRenderBatches":outgoing.clear(false)

static func _finish_loading_sources(map_root:Node,batcher:Node,deadline:int,wait_for_membership:bool=true)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._finish_loading_sources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Membership must be complete before deciding which CPU sources need a
	# standalone upload. A merely queued batch is not proof of membership.
	if wait_for_membership and not batcher._preparation.is_empty():return false
	var sources:Array=map_root.get_meta("deferred_gpu_sources",[])
	var cursor:int=int(map_root.get_meta("deferred_gpu_cursor",0));var advanced:=false
	while cursor<sources.size() and (not advanced or deadline<=0 or Time.get_ticks_usec()<deadline):
		var candidate:Variant=sources[cursor];cursor+=1;advanced=true
		# Nodes do not acquire ownership through this array. Departure may have
		# freed one while preparation was pending; a returned UUID is a new node.
		if not is_instance_valid(candidate):continue
		if not batcher._member_groups.has(str(candidate.name)):GroundBatcher.restore(candidate)
		candidate.remove_meta("deferred_gpu")
	if cursor<sources.size():
		map_root.set_meta("deferred_gpu_cursor",cursor)
		return false
	if not sources.is_empty():
		map_root.remove_meta("deferred_gpu_sources");map_root.remove_meta("deferred_gpu_cursor")
	return true


static func append_specs(map_root:Node,additions:Array,preparation:RefCounted=null)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.append_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Collision-only instances do not enter the visual index. Validate their full
	# namespace before Index.append mutates its shared dictionaries, then transfer
	# the existing bodies in the same synchronous publication transaction.
	var collision_residency=map_root.get_node_or_null("CollisionInstanceResidency")
	# Cancellation returns an empty store to the ordinary loading path. A
	# terminated optional optimization must not reject unrelated visual batches.
	if collision_residency!=null and not collision_residency.has_instances():collision_residency=null
	var promotion:Dictionary={}
	var preflight_started:=Time.get_ticks_usec()
	if collision_residency!=null:
		promotion=collision_residency.preflight_promotion(additions)
		if not promotion.ok:return promotion
	var preflight_us:=Time.get_ticks_usec()-preflight_started
	var data:Dictionary={}
	# Index.append mutates these borrowed containers in place. Residency jobs,
	# cursors and observer metadata are unrelated to an index transaction.
	for key:StringName in APPEND_INDEX_FIELDS:data[str(key)]=map_root.get_meta(key,null)
	var index_started:=Time.get_ticks_usec()
	var result:Dictionary=preload("res://scripts/world3d/stream_index.gd").append(data,additions,preparation)
	var index_us:=Time.get_ticks_usec()-index_started
	if not result.ok:return result
	if collision_residency!=null:collision_residency.commit_promotion(promotion.token)
	var library_started:=Time.get_ticks_usec()
	_library(map_root).append_array(additions)
	var library_us:=Time.get_ticks_usec()-library_started
	# Only scalar counters are replaced; all index/cache container identities
	# remain the same. Avoid re-registering every borrowed container per burst.
	map_root.set_meta(&"stream_building_count",result.data.stream_building_count)
	map_root.set_meta(&"stream_collision_revision",result.data.stream_collision_revision)
	var pending_started:=Time.get_ticks_usec()
	var pending:Array=map_root.get_meta("stream_append_pending",[])
	pending.append_array(additions);pending.append_array(result.get("affected_existing_specs",[]));map_root.set_meta("stream_append_pending",pending)
	var timing:Dictionary={"specs":additions.size(),"preflight_us":preflight_us,"index_us":index_us,"library_us":library_us,"pending_us":Time.get_ticks_usec()-pending_started}
	if result.get("append_timing") is Dictionary:timing.merge(result.append_timing,true)
	map_root.set_meta("stream_append_timing",timing)
	if preflight_us+index_us+library_us>5000:
		var slow:Array=map_root.get_meta("stream_append_slow",[])
		slow.append(timing)
		slow.sort_custom(func(a,b):return int(a.preflight_us)+int(a.index_us)+int(a.library_us)>int(b.preflight_us)+int(b.index_us)+int(b.library_us))
		if slow.size()>16:slow.resize(16)
		map_root.set_meta("stream_append_slow",slow)
	return result


static func _resident_index_data(map_root:Node)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._resident_index_data") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var data:Dictionary={}
	for key:StringName in map_root.get_meta_list():
		if str(key).begins_with("stream_"):data[str(key)]=map_root.get_meta(key)
	return data

static func can_retire_specs(map_root:Node,ids:Array,complete_unit:bool=false)->Dictionary:
	var checked:=_retirement_preflight(map_root,ids,complete_unit)
	# Public preflight never transfers an owning plan to a persistent caller.
	return {"ok":checked.ok,"error":checked.get("error","")}

static func retirement_barrier(map_root:Node,complete_unit:bool=false,allow_preparation:bool=false)->String:
	# Entry temporarily masks distant demand; it never withdraws existing leases.
	if _entry_clip(map_root)!=null:return "entry_scope"
	# Retire only between residency plans. No candidate cursor or batch worker
	# may still own the removed specs. Busy is a retry, never a blocking join.
	if not map_root.has_meta("stream_chunk") or not _jobs(map_root).is_empty() or map_root.has_meta("stream_candidate_work") or not map_root.get_meta("stream_append_pending",[]).is_empty():return "stream_busy"
	var batcher=map_root.get_node_or_null("GroundRenderBatches")
	if batcher!=null and (not batcher._workers.is_empty() or not batcher.pending.is_empty() or not batcher._preparation.is_empty()):return "batch_leased"
	var proxy=map_root.get_node_or_null("DistantBuildingProxy")
	if proxy!=null and not proxy._job.is_empty():return "proxy_leased"
	# An existing schema job can advance without rebuilding a large selected-ID
	# array every frame. Absence/error/completion still reaches final validation.
	var index=preload("res://scripts/world3d/stream_index.gd")
	var resident_catalog:bool=allow_preparation and resident_retirement_catalog_enabled and index.reuse_owned_retirement_plan_enabled and not legacy_retirement_validation_enabled
	if complete_unit and allow_preparation and not resident_catalog and sliced_retirement_schema_enabled and not legacy_retirement_validation_enabled and _library(map_root).size()>=1024 and map_root.has_meta("retirement_schema_preparation"):
		var preparation:RefCounted=map_root.get_meta("retirement_schema_preparation")
		if not preparation.complete and preparation.error.is_empty():return "retirement_schema_pending"
	return ""

static func _retirement_preflight(map_root:Node,ids:Array,complete_unit:bool,allow_preparation:bool=false)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.can_retire_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var barrier:=retirement_barrier(map_root,complete_unit,allow_preparation)
	if not barrier.is_empty():return {"ok":false,"error":barrier}
	var index=preload("res://scripts/world3d/stream_index.gd")
	var target:Vector2i=map_root.get_meta("stream_chunk")
	var draw:=_source_ring(map_root,target,RENDER_RADIUS);var solid:=_source_ring(map_root,target,COLLISION_RADIUS)
	var specs:Array=[];var by_id:Dictionary=map_root.get_meta("stream_by_id",{})
	var resident_catalog:bool=allow_preparation and resident_retirement_catalog_enabled and index.reuse_owned_retirement_plan_enabled and not legacy_retirement_validation_enabled
	var draw_groups:Dictionary={};var solid_cells:Dictionary={}
	if resident_catalog and _resident_sources_pinned(map_root,ids,draw,solid):return {"ok":false,"error":"source_pinned"}
	# A pinned request cannot commit anything. Reject it before the expensive
	# whole-directory integrity scan, even when many distant native units are
	# retained by the kilometre-scale render/support dependency ring.
	for id:Variant in ids if not legacy_retirement_validation_enabled and not resident_catalog else []:
		if not id is String or not by_id.get(id) is Dictionary:continue
		var spec:Dictionary=by_id[id]
		# This pass may only reject a pinned request. Complete source schema is
		# checked by the authoritative index validator below, including every
		# selected member; checking it here too doubles that work for big units.
		if not spec.get("chunk_min") is Vector2i or not spec.get("chunk_max") is Vector2i:continue
		var draws:bool
		if spec.has("render_bounds"):
			var group:Variant=spec.get("render_building");var bounds:Variant=spec.render_bounds
			var dependents:Variant=spec.get("render_dependents",EMPTY_RETIRE_DEPENDENTS)
			var previous:Variant=draw_groups.get(group) if group!=null else null
			# Names alone do not prove shared ownership. Cache only identical
			# mutable envelopes/dependencies inside this synchronous transaction.
			if previous!=null and is_same(previous.bounds,bounds) and is_same(previous.dependents,dependents):draws=previous.draws
			else:
				if not _retirement_bounds_valid(bounds) or not dependents is Array:return {"ok":false,"error":"invalid retirement bounds"}
				for dependent:Variant in dependents:
					if not _retirement_bounds_valid(dependent):return {"ok":false,"error":"invalid retirement bounds"}
				draws=_draws(spec,draw)
				if group!=null:draw_groups[group]={"bounds":bounds,"dependents":dependents,"draws":draws}
		else:draws=_draws(spec,draw)
		if draws:return {"ok":false,"error":"source_pinned"}
		var low:Vector2i=spec.chunk_min;var high:Vector2i=spec.chunk_max
		var cells:=Vector4i(low.x,low.y,high.x,high.y)
		if not solid_cells.has(cells):solid_cells[cells]=_overlaps(spec,solid)
		if solid_cells[cells]:return {"ok":false,"error":"source_pinned"}
		specs.append(spec)
	var data:=_resident_index_data(map_root);var library:=_library(map_root)
	if complete_unit and not resident_catalog and not legacy_retirement_validation_enabled and index.owned_dependency_pinned(data,ids):return {"ok":false,"error":"retained building needs landscape support"}
	var preparation:RefCounted=null
	if not resident_catalog and allow_preparation and complete_unit and sliced_retirement_schema_enabled and not legacy_retirement_validation_enabled and library.size()>=1024:
		preparation=map_root.get_meta("retirement_schema_preparation") if map_root.has_meta("retirement_schema_preparation") else null
		if preparation==null:
			_start_retirement_preparation(map_root,library)
			return {"ok":false,"error":"retirement_schema_pending"}
		if not preparation.error.is_empty():
			map_root.remove_meta("retirement_schema_preparation")
			return {"ok":false,"error":preparation.error}
		if not preparation.complete:return {"ok":false,"error":"retirement_schema_pending"}
	var checked:Dictionary=index._owned_retire_plan(data,library,ids,index.reuse_owned_retirement_plan_enabled,preparation,resident_catalog) if complete_unit else index._retire_plan(data,library,ids,resident_catalog)
	if checked.get("error")=="stale_retirement_schema":
		_start_retirement_preparation(map_root,library)
		return {"ok":false,"error":"retirement_schema_pending"}
	if not checked.ok:return checked
	if resident_catalog:specs=checked.removed_specs
	if legacy_retirement_validation_enabled:
		for id:String in ids:
			var spec:Dictionary=by_id[id]
			if _draws(spec,draw) or _overlaps(spec,solid):return {"ok":false,"error":"source_pinned"}
			specs.append(spec)
	var collision=map_root.get_node_or_null("StreamCollisionPreparer")
	if collision!=null and not collision.release_retired_sources(specs):return {"ok":false,"error":"collision_leased"}
	return {"ok":true,"error":"","data":data,"library":library,"plan":checked,"preparation":preparation}

# Rejection only. The complete selected IDs and live gameplay/worker owners
# are still checked below. Keep this before expensive planning so a returning
# player does not repeatedly rebuild a transaction which cannot commit.
static func _resident_sources_pinned(map_root:Node,ids:Array,draw:Dictionary,solid:Dictionary)->bool:
	var state:Dictionary=map_root.get_meta("stream_append_state",{})
	var catalog:Dictionary=state.get("retirement_units",{});var prefixes:Dictionary={}
	for id:Variant in ids:
		if id is String:prefixes[id.get_slice("__",0)]=true
	var by_id:Dictionary=map_root.get_meta("stream_by_id",{});var groups:Dictionary=map_root.get_meta("stream_building_groups",{})
	var seen_groups:Dictionary={};var seen_bounds:Dictionary={}
	for prefix:String in prefixes:
		if not catalog.has(prefix):continue
		var unit:Dictionary=catalog[prefix]
		for group:String in unit.groups:
			if seen_groups.has(group) or not groups.has(group):continue
			seen_groups[group]=true
			var members:Array=groups[group]
			if not members.is_empty() and _draws(members[0],draw):return true
		for id:String in unit.probes:
			if by_id.has(id) and _draws(by_id[id],draw):return true
		for bounds:Vector4i in unit.bounds:
			if seen_bounds.has(bounds):continue
			seen_bounds[bounds]=true
			if _overlaps({"chunk_min":Vector2i(bounds.x,bounds.y),"chunk_max":Vector2i(bounds.z,bounds.w)},solid):return true
	return false

static func _start_retirement_preparation(map_root:Node,library:Array)->void:
	var preparation:RefCounted=load("res://scripts/world3d/retirement_schema_preparation.gd").new()
	preparation.begin(library);map_root.set_meta("retirement_schema_preparation",preparation)
	var profile:Dictionary=map_root.get_meta("retirement_schema_profile",{})
	profile.started=int(profile.get("started",0))+1;profile.cursor_rows=0;map_root.set_meta("retirement_schema_profile",profile)

static func advance_retirement_preparation(map_root:Node)->void:
	if not is_instance_valid(map_root) or not map_root.has_meta("retirement_schema_preparation"):return
	var preparation:RefCounted=map_root.get_meta("retirement_schema_preparation")
	if preparation.complete or not preparation.error.is_empty():return
	var budget:int=_retirement_budget(map_root).request(Engine.get_process_frames(),"native_retirement",1000)
	if budget<=0:return
	var started:=Time.get_ticks_usec();preparation.advance(mini(budget,1000))
	charge_retirement_work(map_root,"native_retirement",started)
	var profile:Dictionary=map_root.get_meta("retirement_schema_profile",{})
	profile.last=preparation.profile.duplicate()
	profile.slices=int(profile.get("slices",0))+1
	profile.rows=int(profile.get("rows",0))+int(preparation.profile.rows)-int(profile.get("cursor_rows",0))
	profile.cursor_rows=preparation.profile.rows
	profile.max_slice_us=maxi(int(profile.get("max_slice_us",0)),preparation.profile.max_slice_us)
	map_root.set_meta("retirement_schema_profile",profile)

const EMPTY_RETIRE_DEPENDENTS:Array=[]
static func _retirement_bounds_valid(value:Variant)->bool:
	return value is Dictionary and value.get("chunk_min",value.get("chunk")) is Vector2i and value.get("chunk_max",value.get("chunk")) is Vector2i

static func _retirement_budget(map_root:Node)->RefCounted:
	if map_root.has_meta("retirement_frame_budget"):return map_root.get_meta("retirement_frame_budget")
	var ledger:=preload("res://scripts/world3d/frame_work_budget.gd").new()
	ledger.interactive_limits={"ordinary_retirement":2000,"native_retirement":2000}
	ledger.covered_limits=ledger.interactive_limits
	ledger.interactive_budget_usec=2000;ledger.covered_budget_usec=2000
	map_root.set_meta("retirement_frame_budget",ledger)
	return ledger

static func charge_retirement_work(map_root:Node,lane:String,started:int)->void:
	_retirement_budget(map_root).record(Engine.get_process_frames(),lane,maxi(0,Time.get_ticks_usec()-started))

static func retire_specs(map_root:Node,ids:Array,complete_unit:bool=false,navigation:Node=null,retirement_lane:String="")->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.retire_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Both background residency owners share one map-local admission ledger.
	# Charge complete refusals too; its protected FIFO turn prevents the later
	# scene callback starving after the earlier owner repeatedly overruns.
	if retirement_lane.is_empty():return _retire_specs(map_root,ids,complete_unit,navigation)
	if _retirement_budget(map_root).request(Engine.get_process_frames(),retirement_lane,2000)<=0:return {"ok":false,"error":"retirement_budget"}
	var started:=Time.get_ticks_usec()
	var result:=_retire_specs(map_root,ids,complete_unit,navigation,retirement_lane in ["native_retirement","ordinary_retirement"])
	charge_retirement_work(map_root,retirement_lane,started)
	return result

static var live_node_retirement_enabled:=true # Diagnostic control for empty owner-slot work.
static func _retire_specs(map_root:Node,ids:Array,complete_unit:bool,navigation:Node,allow_preparation:bool=false)->Dictionary:
	# Keep the verified plan local to one synchronous transaction. Navigation's
	# source-release handshake changes no map/index state and emits no callbacks;
	# committing that same plan avoids three identical whole-library scans.
	if legacy_retirement_validation_enabled:
		var first:=can_retire_specs(map_root,ids,complete_unit)
		if not first.ok:return first
	var checked:=_retirement_preflight(map_root,ids,complete_unit,allow_preparation)
	if not checked.ok:return checked
	if navigation!=null:
		var released:Dictionary=navigation._try_retire_index_selection(checked.plan.selected) if checked.plan.has("selected") and navigation.has_method("_try_retire_index_selection") else navigation.try_retire_specs(ids)
		if not released.ok:return {"ok":false,"error":released.reason}
	var index=preload("res://scripts/world3d/stream_index.gd")
	var result:Dictionary
	var cleanup:Dictionary={}
	if complete_unit and index.retirement_metadata_enabled:
		if checked.plan.has("cleanup"):cleanup=checked.plan.cleanup
		else:
			var selected_specs:Array=checked.plan.get("removed_specs",[])
			if not checked.plan.has("removed_specs"):
				for id:String in ids:selected_specs.append(checked.data.stream_by_id[id])
			cleanup=index.retirement_metadata(selected_specs)
	if legacy_retirement_validation_enabled:result=index.retire_owned(checked.data,checked.library,ids) if complete_unit else index.retire(checked.data,checked.library,ids)
	else:result=index._commit_owned_retire(checked.data,checked.library,ids,checked.plan) if complete_unit else index._commit_retire(checked.data,checked.library,checked.plan)
	if not result.ok:return result
	if checked.preparation!=null:
		checked.preparation.retired(ids)
		var profile:Dictionary=map_root.get_meta("retirement_schema_profile",{})
		profile.commits=int(profile.get("commits",0))+1;profile.last=checked.preparation.profile.duplicate()
		map_root.set_meta("retirement_schema_profile",profile)
	elif map_root.has_meta("retirement_schema_preparation"):
		var preparation:RefCounted=map_root.get_meta("retirement_schema_preparation")
		if not preparation.retired(ids):map_root.remove_meta("retirement_schema_preparation")
	var usage:Node=map_root.get_node_or_null("AssetResidency")
	if usage!=null:usage.forget_specs(ids)
	var meshes:=_dict(map_root,&"stream_meshes");var bodies:=_dict(map_root,&"stream_bodies")
	# Index/navigation already retired the complete identity set. Scene owners
	# can be sparse after departure; collect them in the existing traversal.
	var owned:Dictionary
	if live_node_retirement_enabled:owned=preload("res://scripts/world3d/retirement_node_selection.gd").collect(ids,meshes,bodies)
	else:
		var nodes:Array=[]
		for id:String in ids:
			if is_instance_valid(meshes.get(id)):nodes.append(meshes[id])
		owned={"nodes":nodes,"ids":ids}
	var batcher=map_root.get_node_or_null("GroundRenderBatches")
	if batcher!=null:batcher.retire_sources(owned.nodes)
	for id:String in owned.ids:
		if not live_node_retirement_enabled or meshes.has(id):_drop(meshes,id,meshes.get(id))
		if not live_node_retirement_enabled or bodies.has(id):_drop(bodies,id,bodies.get(id))
	for key:String in result.data:map_root.set_meta(key,result.data[key])
	# Index retirement cannot leave transient planning or debug ownership.
	map_root.remove_meta("stream_candidates");map_root.remove_meta("stream_plan_bins")
	map_root.remove_meta("stream_plan_ids");map_root.remove_meta("stream_job_catalog")
	map_root.remove_meta("stream_ready_bypass_scan")
	map_root.remove_meta("stream_collision_priority_classes");map_root.remove_meta("stream_collision_priority_origin")
	map_root.remove_meta("stream_collision_priority_partition")
	map_root.set_meta("stream_children",map_root.get_child_count(true))
	# The local plan is the final owner of many retired mesh/spec dictionaries.
	# Do not let its stack destruction release the entire building in this frame.
	# Donate only the private container; borrowed specs/resources are never edited.
	preload("res://scripts/world3d/resource_retirement.gd").defer_private_array(checked.plan.get("removed_specs",[]))
	var response:={"ok":true,"error":"","removed":result.removed,"removed_ids":result.removed_ids}
	if not cleanup.is_empty():response.cleanup=cleanup
	return response


static func pin_source(map_root:Node,id:String,origin:Vector3)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.pin_source") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if id.is_empty() or not origin.is_finite():return
	var sources:Dictionary=map_root.get_meta("stream_sources",{})
	var cell:=chunk_key(origin)
	if sources.get(id)==cell:return
	sources[id]=cell;map_root.set_meta("stream_sources",sources)
	map_root.set_meta("stream_source_revision",int(map_root.get_meta("stream_source_revision",0))+1)

static func release_source(map_root:Node,id:String)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.release_source") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var sources:Dictionary=map_root.get_meta("stream_sources",{})
	if not sources.erase(id):return
	map_root.set_meta("stream_sources",sources)
	map_root.set_meta("stream_source_revision",int(map_root.get_meta("stream_source_revision",0))+1)

## Covered entry/transfer only. XZ bounds include the capsule and camera safety
## margin supplied by the caller; height is conservatively not culled here.
## Existing sources and live collision objects survive this temporary mask.
static func set_entry_scope(map_root:Node,clip:AABB)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.set_entry_scope") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not _valid_entry_clip(clip):return false
	if _entry_clip(map_root)==clip:return true
	map_root.set_meta("entry_stream_clip",clip)
	map_root.set_meta("stream_source_revision",int(map_root.get_meta("stream_source_revision",0))+1)
	return true


static func clear_entry_scope(map_root:Node)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.clear_entry_scope") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not map_root.has_meta("entry_stream_clip"):return
	map_root.remove_meta("entry_stream_clip")
	map_root.set_meta("stream_source_revision",int(map_root.get_meta("stream_source_revision",0))+1)


static func _valid_entry_clip(clip:AABB)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._valid_entry_clip") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return clip.position.is_finite() and clip.size.is_finite() and clip.end.is_finite() and clip.size.x>0 and clip.size.z>0 and clip.size.y>=0


static func _entry_clip(map_root:Node)->Variant:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._entry_clip") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not map_root.has_meta("entry_stream_clip"):return null
	var clip:Variant=map_root.get_meta("entry_stream_clip")
	return clip if clip is AABB and _valid_entry_clip(clip) else null


static func _entry_area(clip:AABB)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._entry_area") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return {"low":chunk_key(clip.position),"high":chunk_key(clip.end),"entry_clip":clip}


static func _in_entry_scope(spec:Dictionary,clip:AABB)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._in_entry_scope") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Use the actual visual and collision bounds, never the compact author proxy
	# or whole-building render_bounds (which may include distant supports).
	if spec.get("extras",{}).has("fixture"):
		# Fixture index bounds include the full hinge sweep, not only today's pose.
		return _overlaps(spec,{"low":chunk_key(clip.position),"high":chunk_key(clip.end)})
	var found:=false
	for mesh:Variant in [spec.get("mesh"),spec.get("collision_mesh")]:
		if not mesh is Mesh or not spec.get("transform") is Transform3D:continue
		var local:AABB=AABB(-mesh.size*.5,mesh.size) if mesh is BoxMesh else mesh.get_aabb()
		var bounds:AABB=spec.transform*local
		if not bounds.position.is_finite() or not bounds.size.is_finite():return true
		found=true
		if bounds.position.x<=clip.end.x and bounds.end.x>=clip.position.x and bounds.position.z<=clip.end.z and bounds.end.z>=clip.position.z:return true
	if found:return false
	# Older CPU-only index consumers may have no Mesh. Their cell bounds are a
	# conservative fallback; uncertainty must not hide a required source.
	if not spec.get("chunk_min",spec.get("chunk")) is Vector2i:return true
	return _overlaps(spec,{"low":chunk_key(clip.position),"high":chunk_key(clip.end)})


static func _entry_candidates(map_root:Node,clip:AABB)->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._entry_candidates") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var index:=_dict(map_root,&"stream_index");var by_id:=_dict(map_root,&"stream_by_id")
	var area:=_entry_area(clip);var selected:Dictionary={}
	for z in range(area.low.y,area.high.y+1):
		for x in range(area.low.x,area.high.x+1):
			for id:Variant in index.get(Vector2i(x,z),[]):
				if selected.has(id):continue
				var spec:Dictionary=by_id[id]
				if _in_entry_scope(spec,clip):selected[id]=spec
	return selected.values()


## Checks only entry-visible/collidable resident specs, not unrelated batch
## queues. The caller must separately gate unpublished dependency/terrain work.
static func entry_scope_ready(map_root:Node)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.entry_scope_ready") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var clip:Variant=_entry_clip(map_root)
	if clip==null:return false
	if not map_root.has_meta("stream_by_id") or int(map_root.get_meta("stream_applied_source_revision",-1))!=int(map_root.get_meta("stream_source_revision",0)):return false
	var meshes:=_dict(map_root,&"stream_meshes");var bodies:=_dict(map_root,&"stream_bodies")
	var batcher=map_root.get_node_or_null("GroundRenderBatches")
	var collision_batches=map_root.get_node_or_null("FortificationCollisionBatches")
	var batched:Dictionary={}
	if collision_batches!=null:
		for group:Dictionary in collision_batches.groups.values():
			if not is_instance_valid(group.get("body")):continue
			for member:Dictionary in group.members:batched[member.uuid]=true
	var area:=_entry_area(clip)
	for spec:Dictionary in _entry_candidates(map_root,clip):
		if _needs_work(spec,area,area,meshes,bodies,batched):return false
		if bool(spec.get("native_visual",false)):continue
		var source:MeshInstance3D=_live(meshes,str(spec.uuid))
		# A deferred/frozen CPU mesh is not a rendered source. Its own batch must
		# exist; other pending batch groups have no bearing on this entry gate.
		if source!=null and source.mesh is CpuMesh:
			if batcher==null:return false
			var key:String=str(batcher._member_groups.get(str(spec.uuid),""))
			if key.is_empty() or not batcher.groups.has(key) or not is_instance_valid(batcher.groups[key].get("visual")):return false
	return true


static func _source_ring(map_root:Node,target:Vector2i,radius:int)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._source_ring") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var clip:Variant=_entry_clip(map_root)
	if clip!=null:return _entry_area(clip)
	var area:=_ring_at(target,radius)
	var rings:Array=[]
	for cell:Vector2i in map_root.get_meta("stream_sources",{}).values():
		if cell!=target:rings.append(_ring_at(cell,radius))
	if not rings.is_empty():area.sources=rings
	return area


static func nearby_collision_ready(map_root:Node,origin:Vector3)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.nearby_collision_ready") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Publication and physics attachment are separate stages. Inspect only the
	# capsule's immediate neighborhood, not unfinished work across the town.
	var area:=Rect2(origin.x-2,origin.z-2,4,4)
	var low:=chunk_key(Vector3(area.position.x,0,area.position.y))
	var high:=chunk_key(Vector3(area.end.x,0,area.end.y))
	var index:Dictionary=map_root.get_meta("stream_collision_index",{})
	var bodies:Dictionary=map_root.get_meta("stream_bodies",{})
	var batched:Dictionary=map_root.get_meta("fortification_collision_sources",{})
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for spec:Dictionary in index.get(Vector2i(x,z),[]):
				var extra:Dictionary=spec.get("extras",{})
				if spec.get("native_visual",false) or extra.get("hostile",false) or extra.get("ally",false) or extra.get("rmmo_collision","")=="none":continue
				var bounds:AABB=spec.transform*spec.mesh.get_aabb()
				if not area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)):continue
				if not batched.has(spec.uuid) and not is_instance_valid(bodies.get(spec.uuid)):return false
	return true

## Exact residency and physics-publication evidence for one swept footprint.
## The caller separately proves unpublished reference dependencies are ready.
## Never accept the fortification source catalogue as an installed physics body.
static func collision_readiness(map_root:Node,clip:AABB)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.collision_readiness") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var profile:Dictionary={"candidates":0,"intersections":0,"bounds_us":0,"body_us":0,"bounds_updates":0} if collision_readiness_profile_enabled else {}
	var began:=Time.get_ticks_usec() if collision_readiness_profile_enabled else 0
	var result:=_collision_readiness_impl(map_root,clip,profile)
	if not profile.is_empty() and is_instance_valid(map_root):
		profile.total_us=Time.get_ticks_usec()-began
		# The remainder includes bucket enumeration/de-duplication/cache lookup,
		# mode checks, exact-area intersection and receipt bookkeeping.
		profile.candidate_us=maxi(0,profile.total_us-profile.bounds_us-profile.body_us)
		var totals:Dictionary=map_root.get_meta("stream_collision_readiness_profile",{})
		totals.calls=int(totals.get("calls",0))+1
		for key:String in profile:totals[key]=int(totals.get(key,0))+int(profile[key])
		totals.max_call_us=maxi(int(totals.get("max_call_us",0)),profile.total_us)
		totals.last=profile;map_root.set_meta("stream_collision_readiness_profile",totals)
	return result

static func _collision_readiness_impl(map_root:Node,clip:AABB,profile:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._collision_readiness_impl") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var result:={"ok":false,"reason":"collision_pending","physics_published_frame":-1}
	if not is_instance_valid(map_root) or not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.y<0 or clip.size.z<0:return result
	if not map_root.has_meta("stream_collision_index"):return result
	var low:=chunk_key(clip.position);var high:=chunk_key(clip.end)
	var index:Dictionary=map_root.get_meta("stream_collision_index",{})
	if collision_candidate_cache_enabled and map_root.has_meta("stream_collision_revision") and (high.x-low.x+1)*(high.y-low.y+1)<=COLLISION_CANDIDATE_CELLS:
		return _cached_collision_readiness(map_root,clip,index,low,high,result,profile)
	var bodies:Dictionary=map_root.get_meta("stream_bodies",{})
	var fort:Node=map_root.get_node_or_null("FortificationCollisionBatches")
	var seen:Dictionary={}
	var area:=Rect2(clip.position.x,clip.position.z,clip.size.x,clip.size.z)
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for spec:Dictionary in index.get(Vector2i(x,z),[]):
				if seen.has(spec.uuid):continue
				seen[spec.uuid]=true
				if not profile.is_empty():profile.candidates+=1
				var extra:Dictionary=spec.get("extras",{})
				if spec.get("native_visual",false) or extra.get("hostile",false) or extra.get("ally",false) or extra.get("rmmo_collision","")=="none":continue
				var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
				if mesh==null or not spec.get("transform") is Transform3D:return result
				var began:=Time.get_ticks_usec() if not profile.is_empty() else 0
				var bounds:AABB=spec.transform*(AABB(-mesh.size*.5,mesh.size) if mesh is BoxMesh else mesh.get_aabb())
				if not profile.is_empty():profile.bounds_us+=Time.get_ticks_usec()-began;profile.bounds_updates+=1
				if not area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true):continue
				if not profile.is_empty():profile.intersections+=1
				began=Time.get_ticks_usec() if not profile.is_empty() else 0
				var body:Variant=bodies.get(spec.uuid)
				if not is_instance_valid(body) and fort!=null:body=fort.body_for(str(spec.uuid))
				var valid:bool=is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and body.collision_layer!=0 and body.has_meta("stream_physics_published_frame")
				if not profile.is_empty():profile.body_us+=Time.get_ticks_usec()-began
				if not valid:return result
				result.physics_published_frame=maxi(result.physics_published_frame,int(body.get_meta("stream_physics_published_frame")))
	# With no intersecting solids, landing still fails its actual support ray.
	result.ok=Engine.get_physics_frames()>int(result.physics_published_frame)
	result.reason="" if result.ok else "physics_sync_pending"
	return result

## Static specs retain their indexed cells until Index.build/append/retire.
## Runtime fixtures instead index their whole hinge sweep. Never exact-filter
## this list by the query footprint or current pose: either may move on a hit.
static func _collision_candidates(map_root:Node,index:Dictionary,low:Vector2i,high:Vector2i)->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._collision_candidates") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var revision:=int(map_root.get_meta("stream_collision_revision"))
	var cache:Dictionary=map_root.get_meta("stream_collision_candidate_cache",{})
	if int(cache.get("revision",-1))!=revision or not is_same(cache.get("index"),index):
		cache.clear();cache.merge({"revision":revision,"index":index,"ranges":{},"serial":0,"hits":0,"misses":0})
		map_root.set_meta("stream_collision_candidate_cache",cache)
	var key:=Vector4i(low.x,low.y,high.x,high.y)
	cache.serial+=1
	if cache.ranges.has(key):
		cache.hits+=1;cache.ranges[key].stamp=cache.serial
		return cache.ranges[key].items
	cache.misses+=1
	var seen:Dictionary={};var items:Array=[]
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for spec:Dictionary in index.get(Vector2i(x,z),[]):
				if seen.has(spec.uuid):continue
				seen[spec.uuid]=true;items.append(CollisionCandidate.new(spec))
	# Large one-off queries stay correct without retaining another scene-sized
	# owner. Range count and retained candidate references are both bounded.
	if items.size()>COLLISION_CANDIDATE_LIMIT:return items
	while cache.ranges.size()>=COLLISION_CANDIDATE_RANGES:
		var oldest:Variant=null;var stamp:=9223372036854775807
		for existing:Vector4i in cache.ranges:
			if int(cache.ranges[existing].stamp)<stamp:oldest=existing;stamp=cache.ranges[existing].stamp
		cache.ranges.erase(oldest)
	cache.ranges[key]={"stamp":cache.serial,"items":items}
	return items

static func collision_candidate_cache_stats(map_root:Node)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.collision_candidate_cache_stats") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var cache:Dictionary=map_root.get_meta("stream_collision_candidate_cache",{})
	var count:=0
	for row:Dictionary in cache.get("ranges",{}).values():count+=row.items.size()
	return {"enabled":collision_candidate_cache_enabled,"revision":int(map_root.get_meta("stream_collision_revision",0)),"hits":cache.get("hits",0),"misses":cache.get("misses",0),"ranges":cache.get("ranges",{}).size(),"candidate_references":count,"profile":map_root.get_meta("stream_collision_readiness_profile",{}).duplicate(true)}

static func _cached_collision_readiness(map_root:Node,clip:AABB,index:Dictionary,low:Vector2i,high:Vector2i,result:Dictionary,profile:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._cached_collision_readiness") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var bodies:Dictionary=map_root.get_meta("stream_bodies",{})
	var fort:Node=map_root.get_node_or_null("FortificationCollisionBatches")
	var area:=Rect2(clip.position.x,clip.position.z,clip.size.x,clip.size.z)
	for candidate:CollisionCandidate in _collision_candidates(map_root,index,low,high):
		if not profile.is_empty():profile.candidates+=1
		var spec:Dictionary=candidate.spec
		var extra:Dictionary=spec.get("extras",{})
		if spec.get("native_visual",false) or extra.get("hostile",false) or extra.get("ally",false) or extra.get("rmmo_collision","")=="none":continue
		var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
		if mesh==null or not spec.get("transform") is Transform3D:return result
		var pose:Transform3D=spec.transform
		var began:=Time.get_ticks_usec() if not profile.is_empty() else 0
		# Bounds access is CPU metadata, not surface readback. Read it every time:
		# custom CPU meshes can replace bounds without emitting Resource.changed.
		var local_bounds:=AABB(-mesh.size*.5,mesh.size) if mesh is BoxMesh else mesh.get_aabb()
		if not candidate.initialized or candidate.mesh!=mesh or candidate.pose!=pose or candidate.local_bounds!=local_bounds:
			var bounds:AABB=pose*local_bounds
			candidate.mesh=mesh;candidate.pose=pose;candidate.local_bounds=local_bounds
			candidate.area=Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z);candidate.initialized=true
			if not profile.is_empty():profile.bounds_updates+=1
		if not profile.is_empty():profile.bounds_us+=Time.get_ticks_usec()-began
		if not area.intersects(candidate.area,true):continue
		if not profile.is_empty():profile.intersections+=1
		began=Time.get_ticks_usec() if not profile.is_empty() else 0
		var body:Variant=bodies.get(spec.uuid)
		if not is_instance_valid(body) and fort!=null:body=fort.body_for(str(spec.uuid))
		var valid:bool=is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and body.collision_layer!=0 and body.has_meta("stream_physics_published_frame")
		if not profile.is_empty():profile.body_us+=Time.get_ticks_usec()-began
		if not valid:return result
		result.physics_published_frame=maxi(result.physics_published_frame,int(body.get_meta("stream_physics_published_frame")))
	result.ok=Engine.get_physics_frames()>int(result.physics_published_frame)
	result.reason="" if result.ok else "physics_sync_pending"
	return result


static func _profile_load(map_root:Node,timings:Dictionary)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._profile_load") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var profile:Dictionary=map_root.get_meta("stream_load_profile_us",{})
	for key:String in timings:profile[key]=int(profile.get(key,0))+timings[key]
	map_root.set_meta("stream_load_profile_us",profile)


static func _collision_wrapper_slots(map_root:Node)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._collision_wrapper_slots") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var state:Dictionary=map_root.get_meta("collision_wrapper_profile",{})
	if state.is_empty():
		state={"frame":-1,"count":0,"dropped":0,"slots":[]}
		for i in 32:
			var stamps:Array=[];stamps.resize(8);stamps.fill(0)
			state.slots.append({"uuid":"","stamps":stamps})
		map_root.set_meta("collision_wrapper_profile",state)
	if state.frame!=Engine.get_process_frames():
		state.frame=Engine.get_process_frames();state.count=0;state.dropped=0
	return state


static func collision_wrapper_snapshot(map_root:Node)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.collision_wrapper_snapshot") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not map_root.get_meta("profile_collision_details",false):return {}
	var state:Dictionary=map_root.get_meta("collision_wrapper_profile",{})
	if state.is_empty():return {}
	var result:Dictionary={"frame":state.frame,"dropped":state.dropped,"calls":[]}
	const NAMES=["outer_begin_us","wrapper_begin_us","impl_begin_us","impl_end_us","publish_begin_us","publish_end_us","return_begin_us","outer_end_us"]
	for i in int(state.count):
		var source:Dictionary=state.slots[i]
		var row:Dictionary={"uuid":source.uuid}
		for j in NAMES.size():row[NAMES[j]]=source.stamps[j]
		result.calls.append(row)
	return result


static func _prepare_collision(map_root:Node,host:Node,spec:Dictionary,solid:Dictionary,bodies:Dictionary,wrapper_stamps:Variant=null,work_budget_usec:int=1500)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._prepare_collision") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if wrapper_stamps!=null:wrapper_stamps[1]=Time.get_ticks_usec()
	if not map_root.get_meta("profile_collision_details",false):return _prepare_collision_impl(map_root,host,spec,solid,bodies,work_budget_usec)
	var preparer=map_root.get_node_or_null("StreamCollisionPreparer")
	var previous_serial:int=preparer.profile_serial if preparer!=null else -1
	var started:=Time.get_ticks_usec()
	if wrapper_stamps!=null:wrapper_stamps[2]=started
	var ready:=_prepare_collision_impl(map_root,host,spec,solid,bodies,work_budget_usec)
	var impl_ended:=Time.get_ticks_usec()
	if wrapper_stamps!=null:wrapper_stamps[3]=impl_ended
	var timing:Dictionary={"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"uuid":str(spec.uuid),"ms":(impl_ended-started)/1000.,"ready":ready}
	preparer=map_root.get_node_or_null("StreamCollisionPreparer")
	if preparer!=null and preparer.profile_serial!=previous_serial:timing["preparer"]=preparer.last_profile
	# Keep the worst call in this render frame, not an unrelated later fast gate.
	var previous:Dictionary=map_root.get_meta("collision_prepare_timing",{})
	if wrapper_stamps!=null:wrapper_stamps[4]=Time.get_ticks_usec()
	if previous.get("frame",-1)!=timing.frame or float(previous.get("ms",0.))<timing.ms:map_root.set_meta("collision_prepare_timing",timing)
	if wrapper_stamps!=null:
		wrapper_stamps[5]=Time.get_ticks_usec()
		wrapper_stamps[6]=Time.get_ticks_usec()
	return ready


static func _prefetch_collisions(map_root:Node,host:Node,jobs:Array,cursor:int,solid:Dictionary,bodies:Dictionary,budget_usec:int=0)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._prefetch_collisions") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
	if not Preparer.prefetch_enabled or cursor>=jobs.size() or host==null or not host.is_inside_tree():return
	var preparer=map_root.get_node_or_null("StreamCollisionPreparer")
	if preparer==null:
		preparer=Preparer.new();preparer.name="StreamCollisionPreparer";map_root.add_child(preparer)
	if not preparer._face_prefetch.can_accept():return
	var requests:Array=[];var seen:Dictionary={}
	var started:=Time.get_ticks_usec()
	# Scan only a bounded prefix of the actual collision/residency plan. A very
	# sparse prefix simply falls back to the existing per-object preparation.
	for at in range(cursor,mini(jobs.size(),cursor+256)):
		if budget_usec>0 and at>cursor and Time.get_ticks_usec()-started>=budget_usec:break
		if requests.size()>=16:break
		var spec:Dictionary=jobs[at]
		if bodies.has(str(spec.uuid)) or not _overlaps(spec,solid):continue
		var extra:Dictionary=spec.get("extras",{})
		if extra.get("rmmo_collision","")=="none" or extra.get("hostile",false) or extra.get("ally",false):continue
		if not preload("res://scripts/world3d/flat_terrain_collision.gd").descriptor(spec).is_empty() or FortCollision.candidate(spec.get("ground_batch_record",{})):continue
		var request:Dictionary=preparer.prefetch_request(spec)
		if request.is_empty():continue
		var id:String=preparer._face_prefetch.key(request.source,request.cpu,request.basis)
		if seen.has(id):continue
		seen[id]=true;requests.append(request)
	preparer._face_prefetch.request(requests,host.get_tree(),budget_usec<=0)

static func _ready_collision_bypass(map_root:Node,jobs:Array,cursor:int,draw:Dictionary,solid:Dictionary,meshes:Dictionary,bodies:Dictionary,deadline:int)->int:
	# A bounded readiness scan only. Never call prepare to probe other terrain:
	# its single private cursor cancels when presented with a different spec.
	var scan_started:=Time.get_ticks_usec()
	var scan_deadline:=mini(deadline,scan_started+500)
	var head:Dictionary=jobs[cursor]
	var head_visual:Variant=meshes.get(str(head.uuid))
	var head_ground:bool=Landscape.ground(head) and _draws(head,draw) and (not is_instance_valid(head_visual) or head_visual.has_meta(GroundBatcher.SUSPENDED_DRAW)) and not head.get("native_visual",false)
	var target:Variant=map_root.get_meta("stream_target",null)
	var state:Dictionary=map_root.get_meta("stream_ready_bypass_scan",{})
	var reusable:bool=not state.is_empty() and is_same(state.jobs,jobs) and is_same(state.head,head) and state.cursor==cursor and state.target==target and state.count<=jobs.size()
	if not reusable:
		state={"jobs":jobs,"head":head,"cursor":cursor,"next":cursor+1,"count":jobs.size(),"target":target,"pending_ground":head_ground}
		map_root.set_meta("stream_ready_bypass_scan",state)
	# Visibility can become suspended without changing the pending Array owner.
	# Re-read the head every turn, even while continuing an earlier scan window.
	var pending_ground:bool=bool(state.pending_ground) or head_ground
	var begin:int=clampi(int(state.next),cursor+1,jobs.size())
	var scanned:=0
	var selected:=-1
	for at:int in range(begin,mini(jobs.size(),begin+64)):
		if Time.get_ticks_usec()>=scan_deadline:break
		state.next=at+1
		var spec:Dictionary=jobs[at]
		var draws:=_draws(spec,draw)
		var visual:Variant=meshes.get(str(spec.uuid))
		var ground:=Landscape.ground(spec)
		# Restoring a retained CPU source changes visibility just like creation.
		# Its mere node presence is not proof that supporting land is ready.
		var adding:bool=draws and (not is_instance_valid(visual) or visual.has_meta(GroundBatcher.SUSPENDED_DRAW)) and not spec.get("native_visual",false)
		scanned+=1
		# Source support must remain visible during departure. The ordinary
		# ordered path owns ground removal, even if its collider is already ready.
		if ground and not draws:continue
		var supports:Array=spec.get("render_supports",[])
		var support_ready:=true
		if adding:
			if not ground and pending_ground and supports.is_empty():support_ready=false
			for support:Dictionary in supports:
				var node:Variant=meshes.get(str(support.uuid))
				if not is_instance_valid(node) or node.is_queued_for_deletion() or node.has_meta(GroundBatcher.SUSPENDED_DRAW):support_ready=false;break
		if support_ready and _collision_ready_without_preparation(spec,solid,bodies):selected=at;break
		if ground and adding:pending_ground=true
	state.count=jobs.size();state.pending_ground=pending_ground
	# Append-only arrivals extend this sweep. A completed sweep revisits earlier
	# candidates next turn, so a formerly missing support/shape can become ready.
	# Target changes, reorders and successful bypasses invalidate the owner above.
	if state.next>=jobs.size():state.next=cursor+1;state.pending_ground=head_ground
	map_root.set_meta("stream_ready_bypass_scanned",int(map_root.get_meta("stream_ready_bypass_scanned",0))+scanned)
	var ended:=Time.get_ticks_usec();var elapsed:=ended-scan_started
	map_root.set_meta("stream_ready_bypass_scan_us",int(map_root.get_meta("stream_ready_bypass_scan_us",0))+elapsed)
	map_root.set_meta("stream_ready_bypass_max_scan_us",maxi(int(map_root.get_meta("stream_ready_bypass_max_scan_us",0)),elapsed))
	return selected if ended<deadline else -1


static func _collision_ready_without_preparation(spec:Dictionary,solid:Dictionary,bodies:Dictionary)->bool:
	var body:Variant=bodies.get(str(spec.uuid))
	if is_instance_valid(body) or not _overlaps(spec,solid):return true
	var extras:Dictionary=spec.get("extras",{})
	if extras.get("rmmo_collision","")=="none" or extras.get("hostile",false) or extras.get("ally",false):return true
	# Geometry specs are immutable; edits replace the spec. descriptor() returns
	# this existing product verbatim. Do not cook/cache a missing product here.
	if not spec.get("flat_terrain_collision",{}).is_empty():return true
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if mesh==null:return false
	if mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size!=Vector3.ZERO):return true
	# Even a spec retaining an old monolithic shape must use its sliced route.
	# Calling prepare for that spec would cancel the current private terrain.
	if preload("res://scripts/world3d/stream_collision_preparer.gd")._needs_slices(spec,mesh):return false
	return spec.get("shape") is Shape3D or (mesh.has_meta("runtime_concave_shape") and mesh.get_meta("runtime_concave_shape") is Shape3D)


static func _prepare_collision_impl(map_root:Node,host:Node,spec:Dictionary,solid:Dictionary,bodies:Dictionary,work_budget_usec:int=1500)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._prepare_collision_impl") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if bodies.has(str(spec.uuid)) or not _overlaps(spec,solid):return true
	var extras:Dictionary=spec.get("extras",{})
	if extras.get("rmmo_collision","")=="none" or extras.get("hostile",false) or extras.get("ally",false):return true
	if not preload("res://scripts/world3d/flat_terrain_collision.gd").descriptor(spec).is_empty():return true
	if FortCollision.candidate(spec.get("ground_batch_record",{})):return true
	var preparer:Node=map_root.get_node_or_null("StreamCollisionPreparer")
	if preparer==null:
		preparer=preload("res://scripts/world3d/stream_collision_preparer.gd").new()
		preparer.name="StreamCollisionPreparer";map_root.add_child(preparer)
	preparer.profile_enabled=bool(map_root.get_meta("profile_collision_details",false))
	return preparer.prepare(spec,host,work_budget_usec)


static func _library(map_root: Node) -> Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._library") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var existing: Variant = map_root.get_meta(&"stream_library", [])
	if existing is Array:
		return existing
	var created: Array = []
	map_root.set_meta(&"stream_library", created)
	return created


static func _dict(node: Node, key: StringName) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._dict") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.has_meta(key):
		var existing: Variant = node.get_meta(key)
		if existing is Dictionary:
			return existing
	var created := {}
	node.set_meta(key, created)
	return created


static func _live(bag: Dictionary, uuid: String):
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._live") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var node: Variant = bag.get(uuid, null)
	if node == null or not is_instance_valid(node):
		bag.erase(uuid)
		return null
	return node


static func _jobs(node: Node) -> Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._jobs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.has_meta(&"stream_jobs"):
		var existing: Variant = node.get_meta(&"stream_jobs")
		if existing is Array:
			return existing
	var created: Array = []
	node.set_meta(&"stream_jobs", created)
	return created


static func _chunk_is(node: Node, key: StringName, chunk: Vector2i) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._chunk_is") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not node.has_meta(key):
		return false
	var value: Variant = node.get_meta(key)
	return value is Vector2i and (value as Vector2i) == chunk


static func _child_count_is(node: Node, count: int) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._child_count_is") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return node.has_meta(&"stream_children") and int(node.get_meta(&"stream_children")) == count


static func _adopt(map_root: Node, library: Array, known: Dictionary) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._adopt") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var started:=Time.get_ticks_usec();var spec_us:=0;var free_us:=0;var freed_count:=0
	preload("res://scripts/world3d/scene_integrity.gd").prepare(map_root)
	var incoming: Array = []
	var compiled_holders:Dictionary={}
	var reused_count:=0
	_collect_meshes(map_root, incoming)
	for mesh in incoming:
		var ancestor:Node=mesh
		while ancestor!=null and ancestor!=map_root:
			if ancestor.has_meta("_compiled_resource_owner"):compiled_holders[ancestor.get_instance_id()]=weakref(ancestor)
			ancestor=ancestor.get_parent()
		var spec_started:=Time.get_ticks_usec()
		var spec := _spec(mesh as MeshInstance3D,mesh.global_transform)
		spec_us+=Time.get_ticks_usec()-spec_started
		var metadata: Dictionary = spec["extras"]
		spec["uuid"] = str(metadata.get("uuid", str(map_root.get_path_to(mesh)).replace("/", "__")))
		var adopted := str(spec.get("uuid", ""))
		library.append(spec)
		known[adopted] = true
		# A freshly built flat static source is already the required runtime
		# instance. Reuse it; deleting tens of thousands of siblings and then
		# recreating them dominated first adoption. Native graphs/NPCs keep their
		# established paths, and distant sources are still removed by residency.
		if mesh.get_parent()==map_root and spec.has("ground_batch_record") and not spec.ground_batch_record.has("fortification") and not spec.native_visual:
			mesh.set_meta("stream_instance",true);_dict(map_root,&"stream_meshes")[adopted]=mesh
			_track_deferred_source(map_root,mesh)
			preload("res://scripts/world3d/wind_response.gd").register(mesh)
			preload("res://scripts/world3d/building_shadow_proxy.gd").attach(mesh)
			reused_count+=1
		_dict(map_root, &"stream_by_id")[adopted] = spec
		var index := _dict(map_root, &"stream_index")
		var low: Vector2i = spec["chunk_min"]
		var high: Vector2i = spec["chunk_max"]
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, z)
				if not index.has(key):
					index[key] = []
				index[key].append(adopted)
	# Children must be removed before their mesh parents.
	incoming.reverse()
	var free_started:=Time.get_ticks_usec()
	for mesh in incoming:
		if mesh.has_meta("stream_instance"):continue
		if mesh.has_meta("native_visual"):
			mesh.set_meta("stream_instance", true)
			preload("res://scripts/world3d/wind_response.gd").register(mesh)
			continue
		mesh.get_parent().remove_child(mesh)
		(mesh as Node).free()
		freed_count+=1
	# Imported transform-only ancestors survive adoption. Their preview owner
	# must not retain the entire PackedScene after specs have taken ownership of
	# its resources. Preserve any real native graph or behavioural descendant.
	for reference:WeakRef in compiled_holders.values():
		var holder:Node=reference.get_ref()
		if is_instance_valid(holder) and _empty_compiled_holder(holder):holder.remove_meta("_compiled_resource_owner")
	free_us=Time.get_ticks_usec()-free_started
	map_root.set_meta("stream_adopt_ms",{"total":(Time.get_ticks_usec()-started)/1000.0,"spec":spec_us/1000.0,"free":free_us/1000.0,"freed_count":freed_count,"reused_count":reused_count})
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.adopt",started,map_root.get_meta("stream_adopt_ms"))


static func _empty_compiled_holder(node:Node)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._empty_compiled_holder") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.get_class()!="Node3D" or node.get_script()!=null or node.has_meta("native_visual") or node.has_meta("native_dynamic"):return false
	for child:Node in node.get_children():
		if not _empty_compiled_holder(child):return false
	return true


static func _collect_meshes(node: Node, result: Array) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._collect_meshes") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for child in node.get_children():
		if child.has_meta("stream_instance"):
			continue
		if child is MeshInstance3D:
			result.append(child)
		_collect_meshes(child, result)


static func _candidates(map_root: Node, target: Vector2i, meshes: Dictionary, bodies: Dictionary) -> Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._candidates") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var clip:Variant=_entry_clip(map_root)
	if clip!=null:return _entry_candidates(map_root,clip)
	var index := _dict(map_root, &"stream_index")
	var by_id := _dict(map_root, &"stream_by_id")
	var selected := {}
	for key in meshes:
		selected[key] = by_id[key]
	for key in bodies:
		selected[key] = by_id[key]
	for key in _dict(map_root,&"fortification_collision_sources"):
		selected[key]=by_id[key]
	var radius:=maxi(COLLISION_RADIUS,RENDER_RADIUS)
	var centers:Array=[target]
	centers.append_array(map_root.get_meta("stream_sources",{}).values())
	for center:Vector2i in centers:
		for z in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				for key in index.get(Vector2i(x, z), []):
					selected[key] = by_id[key]
	var groups:=_dict(map_root,&"stream_building_groups")
	var draw:=_source_ring(map_root,target,RENDER_RADIUS)
	for members:Array in groups.values():
		if not _draws(members[0],draw):continue
		for member:Dictionary in members:selected[member.uuid]=member
	for spec:Dictionary in map_root.get_meta("stream_landscape",[]):
		if _draws(spec,draw):selected[spec.uuid]=spec
	return selected.values()

static func _changed_candidates(map_root:Node,previous:Vector2i,target:Vector2i,unfinished:Array=[])->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._changed_candidates") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var clip:Variant=_entry_clip(map_root)
	if clip!=null:return _entry_candidates(map_root,clip)
	if not map_root.get_meta("stream_sources",{}).is_empty():
		var selected:Dictionary={}
		for spec:Dictionary in _candidates(map_root,target,_dict(map_root,&"stream_meshes"),_dict(map_root,&"stream_bodies"))+unfinished:selected[spec.uuid]=spec
		return selected.values()
	# After a settled swap, only the entering/leaving spatial strips can change
	# residency. Whole-building visibility is compared once per building.
	var selected:Dictionary={}
	for spec:Dictionary in unfinished:selected[spec.uuid]=spec
	if previous==target:return selected.values()
	for radius in [RENDER_RADIUS,COLLISION_RADIUS]:
		var index:Dictionary=_dict(map_root,&"stream_prop_index" if radius==RENDER_RADIUS else &"stream_collision_index")
		var old:=_ring_at(previous,radius);var next:=_ring_at(target,radius)
		for center in [previous,target]:
			for z in range(center.y-radius,center.y+radius+1):
				for x in range(center.x-radius,center.x+radius+1):
					var key:=Vector2i(x,z)
					var inside_old:bool=x>=old.low.x and x<=old.high.x and z>=old.low.y and z<=old.high.y
					var inside_next:bool=x>=next.low.x and x<=next.high.x and z>=next.low.y and z<=next.high.y
					if inside_old==inside_next:continue
					for spec:Dictionary in index.get(key,[]):selected[spec.uuid]=spec
	var old_draw:=_ring_at(previous,RENDER_RADIUS);var next_draw:=_ring_at(target,RENDER_RADIUS)
	for members:Array in _dict(map_root,&"stream_building_groups").values():
		if _draws(members[0],old_draw)==_draws(members[0],next_draw):continue
		for spec:Dictionary in members:selected[spec.uuid]=spec
	for spec:Dictionary in map_root.get_meta("stream_landscape",[]):
		if _draws(spec,old_draw)!=_draws(spec,next_draw):selected[spec.uuid]=spec
	return selected.values()


static func _index_buildings(map_root:Node,library:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._index_buildings") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if int(map_root.get_meta("stream_building_count",-1))==library.size():return
	var started:=Time.get_ticks_usec()
	var data:Dictionary=preload("res://scripts/world3d/stream_index.gd").build(library)
	for key:String in data:map_root.set_meta(key,data[key])
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.index_build",started,{"records":library.size()})


static func _draws(spec:Dictionary,draw:Dictionary)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._draws") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if draw.has("entry_clip"):return _in_entry_scope(spec,draw.entry_clip)
	for area:Dictionary in draw.get("sources",[]):
		if _draws(spec,area):return true
	if not spec.has("render_bounds"):return _overlaps(spec,draw)
	var extra:=BUILDING_RENDER_RADIUS-RENDER_RADIUS
	var far:={"low":draw.low-Vector2i(extra,extra),"high":draw.high+Vector2i(extra,extra)}
	if _overlaps(spec.render_bounds,far):return true
	for bounds:Dictionary in spec.get("render_dependents",[]):
		if _overlaps(bounds,far):return true
	return false


static func _plan_jobs(map_root: Node, jobs: Array, meshes: Dictionary, bodies: Dictionary, target: Vector2i, budget: int,deadline:int=0) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._plan_jobs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not map_root.has_meta(&"stream_candidates"):
		return true
	var detailed:=bool(map_root.get_meta("profile_collision_details",false))
	var entered:=Time.get_ticks_usec() if detailed else 0
	var candidates: Array = map_root.get_meta(&"stream_candidates")
	var cursor := int(map_root.get_meta(&"stream_plan_cursor", 0))
	var cursor_before:=cursor
	var bins: Array = map_root.get_meta(&"stream_plan_bins")
	var plan_ids:Dictionary=map_root.get_meta("stream_plan_ids",{})
	map_root.set_meta("stream_plan_ids",plan_ids)
	var draw := _source_ring(map_root,target, RENDER_RADIUS)
	var solid := _source_ring(map_root,target, COLLISION_RADIUS)
	var batched:=_dict(map_root,&"fortification_collision_sources")
	var draw_groups:Dictionary={};var solid_cells:Dictionary={}
	var reuse_bounds:=not _draw_uses_exact_geometry(draw) and not _draw_uses_exact_geometry(solid)
	var started := Time.get_ticks_usec()
	while cursor < candidates.size():
		var item: Dictionary = candidates[cursor]
		cursor += 1
		if reuse_job_classification_enabled:
			var bin:=_job_bin(item,draw,solid,meshes,bodies,batched,draw_groups,solid_cells,reuse_bounds)
			if bin>=0:bins[bin].append(item);plan_ids[item.uuid]=true
		elif _needs_work(item, draw, solid, meshes, bodies, batched):
			# Ground first on arrival, buildings first on departure. Even budgeted
			# swaps must never expose a house before its supporting land exists.
			var visible:=_draws(item,draw)
			var bin:=1 if _overlaps(item,solid) else 3
			if Landscape.ground(item):bin=0 if visible else 4
			elif item.has("render_building"):bin=2 if visible else 0
			bins[bin].append(item)
			plan_ids[item.uuid]=true
		if budget > 0 and (Time.get_ticks_usec() - started >= (12000 if budget>=LOAD_BUDGET else 2000) or (deadline>0 and Time.get_ticks_usec()>=deadline)):
			map_root.set_meta(&"stream_plan_cursor", cursor)
			if detailed:map_root.set_meta("stream_plan_detail",{"scan_ms":(Time.get_ticks_usec()-entered)/1000.,"scanned":cursor-cursor_before,"pending":true})
			return false
	var scanned:=Time.get_ticks_usec() if detailed else 0
	for bin in bins:
		jobs.append_array(bin)
	map_root.set_meta("stream_job_catalog",{"jobs":jobs,"ids":plan_ids,"cursor":0,"size":jobs.size()})
	map_root.remove_meta("stream_plan_ids")
	var appended:=Time.get_ticks_usec() if detailed else 0
	map_root.remove_meta(&"stream_candidates")
	map_root.remove_meta(&"stream_plan_bins")
	map_root.remove_meta("stream_collision_priority_origin")
	map_root.remove_meta("stream_collision_priority_partition")
	if detailed:map_root.set_meta("stream_plan_detail",{"scan_ms":(scanned-entered)/1000.,"append_ms":(appended-scanned)/1000.,"release_meta_ms":(Time.get_ticks_usec()-appended)/1000.,"scanned":cursor-cursor_before,"pending":false})
	return true


static var append_bounds_reuse_enabled:=true
static func append_ready_jobs(map_root:Node,jobs:Array,cursor:int,draw:Dictionary,solid:Dictionary,meshes:Dictionary,bodies:Dictionary)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.append_ready_jobs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Index.append already validated and published these immutable specs. Insert
	# them into the current plan without cancelling its active collision worker.
	# Holding every new near prop behind an entire district left streets empty.
	var pending:Array=map_root.get_meta("stream_append_pending",[])
	if pending.is_empty():return false
	var catalog:Dictionary=map_root.get_meta("stream_job_catalog",{})
	if catalog.is_empty() or not is_same(catalog.jobs,jobs) or catalog.cursor!=cursor or catalog.size!=jobs.size():
		var ids:Dictionary={}
		for i in range(cursor,jobs.size()):ids[jobs[i].uuid]=true
		catalog={"jobs":jobs,"ids":ids,"cursor":cursor,"size":jobs.size()}
		map_root.set_meta("stream_job_catalog",catalog)
		map_root.set_meta("stream_job_catalog_scan_rows",int(map_root.get_meta("stream_job_catalog_scan_rows",0))+jobs.size()-cursor)
	var queued:Dictionary=catalog.ids
	var batched:=_dict(map_root,&"fortification_collision_sources")
	var consumed:=mini(256,pending.size());var changed:=false
	var dirty:Dictionary=map_root.get_meta("stream_collision_priority_dirty",{})
	# Publication often appends hundreds of members sharing one building's
	# support envelope. Match planning's per-call reuse without retaining live
	# node state or envelope decisions across frames/source changes.
	var groups:Dictionary={};var cells:Dictionary={}
	var reuse:=not _draw_uses_exact_geometry(draw) and not _draw_uses_exact_geometry(solid)
	for i in consumed:
		var spec:Dictionary=pending[i]
		# Index.append also reports changed support envelopes already in the
		# queue. They must invalidate priority even when no job is newly appended.
		dirty[spec.uuid]=true
		if queued.has(spec.uuid):changed=true;continue
		if _job_bin(spec,draw,solid,meshes,bodies,batched,groups,cells,reuse)>=0 if append_bounds_reuse_enabled else _needs_work(spec,draw,solid,meshes,bodies,batched):
			jobs.append(spec);queued[spec.uuid]=true;changed=true
	if consumed==pending.size():map_root.remove_meta("stream_append_pending")
	else:map_root.set_meta("stream_append_pending",pending.slice(consumed))
	map_root.set_meta("stream_collision_priority_dirty",dirty)
	catalog.size=jobs.size()
	return changed


static func _job_bin(spec:Dictionary,draw:Dictionary,solid:Dictionary,meshes:Dictionary,bodies:Dictionary,batched:Dictionary,groups:Dictionary,cells:Dictionary,reuse:bool)->int:
	# This call owns the classification and insertion decision. Read live nodes
	# and gameplay flags per row, but calculate each envelope only once. Caches
	# last only for this synchronous slice; exact entry footprints never share.
	if draw.has("entry_clip") and not _in_entry_scope(spec,draw.entry_clip):return -1
	var id:String=str(spec.uuid);var visual:Node=_live(meshes,id)
	var body:bool=batched.has(id) or _live(bodies,id)!=null
	var extra:Dictionary=spec.get("extras",{})
	var overlap:=_priority_overlaps(spec,solid,cells) if reuse else _overlaps(spec,solid)
	var collides:bool=str(extra.get("rmmo_collision",""))!="none" and not (bool(extra.get("hostile",false)) or bool(extra.get("ally",false))) and overlap
	var visible:=_priority_draws(spec,draw,groups) if reuse else _draws(spec,draw)
	var visual_work:bool=not bool(spec.get("native_visual",false)) and (visible!=(visual!=null) or (visible and visual!=null and visual.has_meta(GroundBatcher.SUSPENDED_DRAW)))
	if not visual_work and collides==body:return -1
	if Landscape.ground(spec):return 0 if visible else 4
	if spec.has("render_building"):return 2 if visible else 0
	return 1 if overlap else 3


static func _draw_uses_exact_geometry(draw:Dictionary)->bool:
	if draw.has("entry_clip"):return true
	for source:Dictionary in draw.get("sources",EMPTY_RETIRE_DEPENDENTS):
		if _draw_uses_exact_geometry(source):return true
	return false

static func _priority_draws(spec:Dictionary,draw:Dictionary,groups:Dictionary)->bool:
	if not spec.has("render_bounds") or not spec.get("render_building") is String:return _draws(spec,draw)
	var group:String=spec.render_building
	var bounds:Dictionary=spec.render_bounds
	var dependents:Array=spec.get("render_dependents",EMPTY_RETIRE_DEPENDENTS)
	var previous:Variant=groups.get(group)
	# A group name alone is insufficient: editor/test callers may carry different
	# mutable support envelopes. Reuse only identical owners within this call.
	if previous!=null and is_same(previous.bounds,bounds) and is_same(previous.dependents,dependents):return previous.draws
	var draws:=_draws(spec,draw)
	groups[group]={"bounds":bounds,"dependents":dependents,"draws":draws}
	return draws

static func _priority_overlaps(spec:Dictionary,draw:Dictionary,cells:Dictionary)->bool:
	var low:Vector2i=spec.chunk_min if spec.has("chunk_min") else spec.chunk
	var high:Vector2i=spec.chunk_max if spec.has("chunk_max") else spec.chunk
	var key:=Vector4i(low.x,low.y,high.x,high.y)
	var previous:Variant=cells.get(key)
	if previous!=null:return previous
	var overlaps:=_overlaps(spec,draw);cells[key]=overlaps
	return overlaps

static func prioritize_local_collisions(jobs:Array,cursor:int,origin:Vector3,bodies:Dictionary,draw:Dictionary={},meshes:Dictionary={})->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream.prioritize_local_collisions") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Reorder only the pending residency plan. Keep its current item first:
	# a sliced/worker collision preparation may already own that exact source.
	# The 6 m lead gives nearby solids time to attach before the 2 m safety gate.
	# Never widen collision residency, skip a body, or change readiness rules.
	if cursor<0 or cursor+1>=jobs.size():return
	var area:=Rect2(origin.x-6.,origin.z-6.,12.,12.)
	var ground:Array=[];var local:Array=[];var visuals:Array=[];var rest:Array=[]
	var draw_groups:Dictionary={};var draw_cells:Dictionary={}
	var reuse_draws:=collision_priority_reuse_enabled and not _draw_uses_exact_geometry(draw)
	for i in range(cursor+1,jobs.size()):
		var spec:Dictionary=jobs[i];var extra:Dictionary=spec.get("extras",{})
		var is_ground:=Landscape.ground(spec)
		if not draw.is_empty() and is_ground and (_priority_draws(spec,draw,draw_groups) if reuse_draws else _draws(spec,draw)):ground.append(spec);continue
		var near:bool=not bodies.has(str(spec.uuid)) and extra.get("rmmo_collision","")!="none" and not extra.get("hostile",false) and not extra.get("ally",false) and not spec.get("native_visual",false)
		if near:
			var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
			var bounds:AABB=spec.transform*(AABB(-mesh.size*.5,mesh.size) if mesh is BoxMesh else mesh.get_aabb())
			near=area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true)
		if near:
			if is_ground:ground.append(spec)
			else:local.append(spec)
		elif not draw.is_empty() and not meshes.has(spec.uuid) and not spec.get("native_visual",false) and not extra.get("hostile",false) and not extra.get("ally",false) and (_priority_overlaps(spec,draw,draw_cells) if reuse_draws else _overlaps(spec,draw)) and (_priority_draws(spec,draw,draw_groups) if reuse_draws else _draws(spec,draw)):visuals.append(spec)
		else:rest.append(spec)
	var at:=cursor+1
	for group:Array in [ground,local,visuals,rest]:
		for spec:Dictionary in group:jobs[at]=spec;at+=1


static func _needs_work(spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary, batched: Dictionary={}) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._needs_work") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if draw.has("entry_clip") and not _in_entry_scope(spec,draw.entry_clip):return false
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var visual:Node=_live(meshes,uuid)
	var has_mesh := visual != null
	var has_body := batched.has(uuid) or _live(bodies, uuid) != null
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	collides=collides and _overlaps(spec,solid)
	if not bool(spec.get("native_visual", false)):
		var draws:=_draws(spec,draw)
		if draws!=has_mesh or (draws and visual!=null and visual.has_meta(GroundBatcher.SUSPENDED_DRAW)):return true
	if collides != has_body:
		return true
	return false


static func _apply(map_root: Node, host: Node, spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._apply") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if draw.has("entry_clip") and not _in_entry_scope(spec,draw.entry_clip):return false
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var inst = _live(meshes, uuid) as MeshInstance3D
	var body = _live(bodies, uuid) as StaticBody3D
	var changed:=false
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	collides=collides and _overlaps(spec,solid)
	var fort_sources:=_dict(map_root,&"fortification_collision_sources")
	if not collides or not FortCollision.candidate(spec.get("ground_batch_record",{})):
		if fort_sources.erase(uuid):map_root.set_meta("stream_fortification_collision_dirty",true)
	if bool(spec.get("native_visual", false)):
		pass
	elif _draws(spec, draw):
		if inst == null:
			inst = _spawn(spec, bool(map_root.get_meta("defer_source_upload",false)), map_root.has_meta("profile_frame"))
			map_root.add_child(inst)
			inst.global_transform = spec["transform"]
			meshes[uuid] = inst
			_track_deferred_source(map_root,inst)
			changed=true
		elif inst.has_meta(GroundBatcher.SUSPENDED_DRAW):
			GroundBatcher.restore(inst)
			changed=true
	elif inst != null:
		var batcher:Node=map_root.get_node_or_null("GroundRenderBatches")
		if batcher!=null:
			# One budgeted node removal can invalidate a much larger batch. Do
			# not upload the rest of that batch only to delete it on later slices.
			# Classify live members against this exact draw envelope; unknown
			# ownership stays conservative and keeps the ordinary restore path.
			var suspended:Dictionary={}
			var group:Dictionary=batcher.groups.get(batcher._member_groups.get(uuid,""),{})
			var by_id:Dictionary=_dict(map_root,&"stream_by_id")
			for member in group.get("members",[]):
				if not is_instance_valid(member):continue
				var owned:Variant=by_id.get(str(member.name))
				if owned is Dictionary and not owned.get("native_visual",false) and meshes.get(str(member.name))==member and not _draws(owned,draw):suspended[member.get_instance_id()]=true
			batcher.retire_sources([inst],suspended)
		_drop(meshes, uuid, inst)
		changed=true
	if collides:
		if FortCollision.candidate(spec.get("ground_batch_record",{})):
			fort_sources[uuid]=spec
			map_root.set_meta("stream_fortification_collision_dirty",true)
		elif body == null:
			body = _make_body(host, spec, map_root.has_meta("profile_frame"))
			if body != null:
				body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
				bodies[uuid] = body
	elif body != null:
		_drop(bodies, uuid, body)
	return changed


static func _ring_at(chunk: Vector2i, radius: int) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._ring_at") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return {"low": chunk - Vector2i(radius, radius), "high": chunk + Vector2i(radius, radius)}


static func _drop(bag: Dictionary, uuid: String, node: Node) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._drop") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node != null and is_instance_valid(node):
		node.free()
	bag.erase(uuid)


static func _spec(visual: MeshInstance3D,final_pose:Variant=null) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._spec") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var Io = load("res://scripts/world3d/gltf_map_io.gd")
	# Hierarchy collectors already know the final pose. Project bounds/hinges
	# once at that pose instead of computing and immediately replacing them.
	var pose:Transform3D=final_pose if final_pose is Transform3D else visual.transform
	var bounds: AABB = pose * visual.get_aabb()
	var extras: Dictionary = Io.extras_of(visual).duplicate(true)
	if visual.has_meta("native_dynamic"): extras["rmmo_collision"] = "none"
	var spec := {
		"native_visual": visual.has_meta("native_visual"),
		"uuid": str(visual.name),
		"position": pose.origin,
		"rotation": visual.rotation,
		"transform": pose,
		"chunk_min": chunk_key(bounds.position),
		"chunk_max": chunk_key(bounds.end),
		"mesh": visual.mesh,
		"material_override": visual.material_override,
		"surface_overrides": [],
		"cast_shadow": visual.cast_shadow,
		"extras": extras,
		"chunk": chunk_key(pose.origin),
	}
	var cpu_overrides_key:StringName=preload("res://scripts/world3d/river_materials.gd").CPU_SURFACE_OVERRIDES_META
	var cpu_overrides:Variant=visual.get_meta(cpu_overrides_key) if visual.has_meta(cpu_overrides_key) else null
	if visual.mesh is CpuMesh and cpu_overrides is Array:
		# Immutable indexing has no GPU surface slots. Preserve the same per-slot
		# materials for _spawn without uploading the disposable directory visual.
		spec.surface_overrides=cpu_overrides.duplicate()
	else:
		for slot in visual.mesh.get_surface_count(): spec.surface_overrides.append(visual.get_surface_override_material(slot))
	if visual.has_meta("map_draw_order"):spec.map_draw_order=visual.get_meta("map_draw_order")
	# Painting changes UVs/materials, never the authored solid. Preserve the
	# exact box primitive instead of downloading the painted mesh for physics.
	var collision_source: Mesh = visual.get_meta("collision_solid",visual.get_meta("paint_source", visual.mesh))
	var needs_collision:=CollisionGeometry.needs_adopted_collision(extras)
	if needs_collision and collision_source is CpuMesh and collision_source.box_size!=Vector3.ZERO:
		if not collision_source.has_meta("runtime_solid"):
			var solid:=BoxMesh.new();solid.size=collision_source.box_size;collision_source.set_meta("runtime_solid",solid)
		collision_source=collision_source.get_meta("runtime_solid")
	if needs_collision and collision_source is BoxMesh and not collision_source.flip_faces:
		spec["collision_mesh"] = collision_source
	elif needs_collision and (collision_source is ArrayMesh or collision_source is CpuMesh or visual.has_meta("collision_solid") or visual.mesh.has_meta("ground_cpu_cache")):
		# Direct glTF/editor playtests lack the cooked loader's CPU spec. Capture
		# their immutable triangles during adoption too, so walking into a house
		# never needs a GPU readback and synchronous TriangleMesh construction.
		spec["collision_mesh"] = CpuMesh.capture(collision_source)
	if visual.has_meta("ground_batch_record"):
		spec.ground_batch_record = visual.get_meta("ground_batch_record")
		# Off-screen terrain keeps CPU collision/authoring data, not GPU buffers.
		spec.mesh = spec.collision_mesh if collision_source==visual.mesh and spec.get("collision_mesh") is CpuMesh else CpuMesh.capture(visual.mesh)
	preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
	return spec


static func _spawn(spec: Dictionary, defer_upload:bool=false, profile:bool=false) -> MeshInstance3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._spawn") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var started:=Time.get_ticks_usec() if profile else 0
	var traced:=preload("res://scripts/world3d/load_trace.gd").methods_enabled
	var stage_started:=Time.get_ticks_usec() if traced else 0
	var visual := MeshInstance3D.new()
	visual.name = str(spec.get("uuid", "chunk"))
	var source:Mesh=spec.get("mesh")
	var deferred_materials:=false
	if source is CpuMesh and defer_upload and spec.has("ground_batch_record") and not spec.ground_batch_record.has("house_prefab"):
		# Instance overrides belong in this instance's CPU descriptor until batch
		# membership is known. Uploading just to install an override defeats the
		# covered-load path; RS surface overrides also require a real mesh base.
		var materials:Array[Material]=[]
		var overrides:Array=spec.get("surface_overrides",[])
		for slot:int in source.get_surface_count():
			materials.append(spec.material_override if spec.get("material_override")!=null else (overrides[slot] if slot<overrides.size() and overrides[slot]!=null else source.surface_get_material(slot)))
		if materials!=source.materials:
			var local:=CpuMesh.new();local.surfaces=source.surfaces;local.lods=source.lods;local.bounds=source.bounds;local.box_size=source.box_size;local.source_reference=source.source_reference;local.materials=materials;local._collision_faces=source._collision_faces
			if source.has_meta("static_batch_geometry_signature"):local.set_geometry_key(source.geometry_key())
			preload("res://scripts/world3d/prepared_cpu_upload.gd").inherit(source,local)
			source=local
		deferred_materials=true
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_cpu_projection",stage_started,{"uuid":spec.uuid})
	stage_started=Time.get_ticks_usec() if traced else 0
	visual.mesh = source
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_bind_source",stage_started,{"uuid":spec.uuid})
	stage_started=Time.get_ticks_usec() if traced else 0
	if visual.mesh is CpuMesh:
		if deferred_materials:visual.set_meta("deferred_gpu",true)
		else:visual.mesh = preload("res://scripts/world3d/prepared_cpu_upload.gd").restore(visual.mesh,str(spec.uuid))
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_restore",stage_started,{"uuid":spec.uuid})
	stage_started=Time.get_ticks_usec() if traced else 0
	var restored:=Time.get_ticks_usec() if profile else 0
	if spec.has("ground_batch_record"): visual.set_meta("ground_batch_record",spec.ground_batch_record)
	visual.material_override = null if deferred_materials else spec.get("material_override")
	visual.cast_shadow=spec.get("cast_shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for slot in spec.get("surface_overrides",[]).size():
		if not deferred_materials and spec.surface_overrides[slot]!=null:visual.set_surface_override_material(slot,spec.surface_overrides[slot])
	visual.set_meta("stream_instance", true)
	visual.position = spec.get("position", Vector3.ZERO)
	visual.rotation = spec.get("rotation", Vector3.ZERO)
	visual.transform = spec.get("transform", visual.transform)
	var extras: Dictionary = spec.get("extras", {})
	if not extras.is_empty():
		visual.set_meta("extras", extras)
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_metadata",stage_started,{"uuid":spec.uuid})
	stage_started=Time.get_ticks_usec() if traced else 0
	preload("res://scripts/world3d/asset_visibility_range.gd").register(visual)
	preload("res://scripts/world3d/wind_response.gd").register(visual)
	preload("res://scripts/world3d/streetlamp_lights.gd").register(visual)
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_registration",stage_started,{"uuid":spec.uuid})
	stage_started=Time.get_ticks_usec() if traced else 0
	if bool(extras.get("invisible", false)):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):
		visual.visible = false
		return visual
	if str(extras.get("kind", "")) == "npc":
		var bounds: AABB = visual.mesh.get_aabb()
		visual.mesh = null
		# Loaded on demand: a preload would compile the whole character, rig and cloth
		# stack (~50 scripts) into every map load, including maps without NPCs.
		var actor: Node3D = load("res://scripts/char/character_model_3d.gd").create_npc(extras.get("appearance", {}))
		actor.position.y = bounds.position.y
		visual.add_child(actor)
		var label = load("res://scripts/char/character_overhead_label.gd").new()
		label.model=actor
		label.text = str(extras.get("name", extras.get("npc_id", "NPC")))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.003
		visual.add_child(label)
	preload("res://scripts/world3d/building_shadow_proxy.gd").attach(visual)
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("stream.spawn_shadow",stage_started,{"uuid":spec.uuid})
	if profile and Time.get_ticks_usec()-started>5000:print("STREAM_VISUAL_SLOW ",spec.uuid," ",{"restore_ms":(restored-started)/1000.0,"setup_ms":(Time.get_ticks_usec()-restored)/1000.0})
	return visual


static func _body_shell(spec:Dictionary)->StaticBody3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._body_shell") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var extras: Dictionary = spec.get("extras", {})
	var body := StaticBody3D.new()
	body.name = "%s_body" % str(spec.get("uuid", "chunk"))
	body.set_meta("uuid", str(spec["uuid"]))
	body.set_meta("surface_id", str(extras.get("surface_id", "ground")))
	body.set_meta("kind", str(extras.get("kind", "box")))
	body.set_meta("target_path", str(extras.get("target_path", "")))
	body.set_meta("spawn", extras.get("spawn", [0, 0.9, 4]))
	body.set_meta("npc_id", str(extras.get("npc_id", "")))
	body.set_meta("node_id", str(extras.get("node_id", "")))
	body.set_meta("line", str(extras.get("line", "")))
	if extras.get("seat") is Dictionary:body.set_meta("seat",extras.seat.duplicate(true))
	var position: Vector3 = spec.get("position", Vector3.ZERO)
	body.set_meta("center", position)
	body.position = position
	body.rotation = spec.get("rotation", Vector3.ZERO)
	body.transform = spec.get("transform", body.transform)
	return body


static func _make_body(host: Node, spec: Dictionary, profile:bool=false) -> StaticBody3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._make_body") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var profile_started:=Time.get_ticks_usec()
	var extras:Dictionary=spec.get("extras",{})
	if str(extras.get("rmmo_collision", "")) == "none" or (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):return null
	var prepared=spec.get("prepared_body")
	if is_instance_valid(prepared):
		spec.erase("prepared_body")
		prepared.collision_layer=1;prepared.collision_mask=1
		if profile:spec.profile_body={"publish_ms":(Time.get_ticks_usec()-profile_started)/1000.0,"slices":prepared.get_child_count()}
		return prepared
	var body:=_body_shell(spec)
	var shape := CollisionShape3D.new()
	var mesh: Mesh = spec.get("collision_mesh", spec.get("mesh", null)) as Mesh
	if mesh == null:
		body.free()
		return null
	var flat:Dictionary=preload("res://scripts/world3d/flat_terrain_collision.gd").descriptor(spec)
	if not flat.is_empty():
		shape.shape=flat.shape;shape.position=flat.offset;body.add_child(shape)
		host.add_child(body);body.global_transform=spec.get("transform",body.transform)
		if profile:spec.profile_body={"flat_box_ms":(Time.get_ticks_usec()-profile_started)/1000.0}
		return body
	# A bounding box is not a collision mesh: it would fill arches and stairs.
	# Cache the static shape in the document view spec across residency changes.
	if not spec.has("shape"):
		if mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size != Vector3.ZERO):
			# Reading PrimitiveMesh.get_aabb() can allocate its render buffers.
			# Physics only needs the authored size, shared by immutable instances.
			var size_:Vector3=mesh.size if mesh is BoxMesh else mesh.box_size
			var box:BoxShape3D=mesh.get_meta("runtime_box_shape") if mesh.has_meta("runtime_box_shape") else null
			if box==null or box.size!=size_:
				box=BoxShape3D.new();box.size=size_;mesh.set_meta("runtime_box_shape",box)
			spec["shape"] = box
		else:
			if spec.get("ground_batch_record",{}).has("house_prefab"):
				if not mesh.has_meta("runtime_concave_shape"):mesh.set_meta("runtime_concave_shape",_triangle_shape(mesh))
				spec["shape"] = mesh.get_meta("runtime_concave_shape")
			else:spec["shape"] = _triangle_shape(mesh)
	var shape_ready:=Time.get_ticks_usec()
	shape.shape = spec["shape"]
	body.add_child(shape)
	host.add_child(body)
	body.global_transform = spec.get("transform", body.transform)
	if profile:spec.profile_body={"shape_ms":(shape_ready-profile_started)/1000.0,"attach_ms":(Time.get_ticks_usec()-shape_ready)/1000.0,"cpu":mesh is CpuMesh,"faces":spec["shape"].get_faces().size() if spec["shape"] is ConcavePolygonShape3D else 0}
	return body


static func _triangle_shape(mesh:Mesh)->ConcavePolygonShape3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._triangle_shape") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not mesh is CpuMesh:return mesh.create_trimesh_shape()
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(mesh.collision_faces());return shape


static func _overlaps(spec: Dictionary, chunks: Dictionary) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_stream._overlaps") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if chunks.has("entry_clip"):return _in_entry_scope(spec,chunks.entry_clip)
	for area:Dictionary in chunks.get("sources",[]):
		if _overlaps(spec,area):return true
	# The fallback expression of get() is eager. A min/max-only envelope is
	# valid; never read a missing legacy `chunk` key when those bounds exist.
	var low: Vector2i = spec["chunk_min"] if spec.has("chunk_min") else spec["chunk"]
	var high: Vector2i = spec["chunk_max"] if spec.has("chunk_max") else spec["chunk"]
	var ring_low: Vector2i = chunks["low"]
	var ring_high: Vector2i = chunks["high"]
	return low.x <= ring_high.x and high.x >= ring_low.x and low.y <= ring_high.y and high.y >= ring_low.y
