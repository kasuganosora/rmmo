extends Node
## A map owns this demand queue. Native reference groups and independent static
## models prepare off-thread; shared publication and instance effects stay on main.
signal published(specs:Array)
signal completed
signal failed(reason:String)
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const TransferLoading=preload("res://scripts/world3d/transfer_loading.gd")
const OwnershipProof=preload("res://scripts/world3d/dependency_index_proof.gd")
const INTERACTIVE_BUDGET_US:=2000
static var interactive_budget_override_usec:=0 # Controlled throughput probe; zero retains policy.
static var force_covered_loading_budget:=false # Diagnostic: test the drawn-cover 16ms ceiling.
const COVERED_LOADING_BUDGET_US:=16000
const TRANSFER_COVERED_BUDGET_US:=16000
static var covered_loading_budget_usec:=48000
const REUSE_HASH_BLOCK_BYTES:=4*1024*1024
const REUSE_HASH_RESERVATION_BYTES:=4*REUSE_HASH_BLOCK_BYTES
const REUSE_FACE_MAX_MESHES:=64
const REUSE_FACE_MAX_BYTES:=128*1024*1024
const FacePrefetch=preload("res://scripts/world3d/collision_face_prefetch.gd")
const MOVING_DEMAND_HALO_M:=4.0
const COLLISION_CAMERA_HOLD_M:=12.0
const CompiledPreparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const MemoryEstimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
const PrefabTextures=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const PrefabSpecs=preload("res://scripts/world3d/prefab_spec_preparation.gd")
const SharedImages=preload("res://scripts/world3d/shared_prefab_images.gd")
const ParallelChunkWorker=preload("res://scripts/world3d/parallel_chunk_worker.gd")
const TexturePlanCatalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const CompletedTrace=preload("res://scripts/world3d/completed_job_trace.gd")
const CollisionGeometry=preload("res://scripts/world3d/model_collision_requirements.gd")
static var shared_prefab_texture_preparation_enabled:=true # Shared source tasks retain and charge pixels once.
static var parallel_texture_preparation_enabled:=true # Same byte lease and total worker cap; diagnostic serial control.
static var texture_plan_reuse_enabled:=true
static var async_texture_headers_enabled:=true
static var prefab_texture_preparation_enabled:=true
static var native_entry_prefetch_enabled:=false
static var bridge_texture_preparation_enabled:=true # Demanded native bridges, after core publication only; full entry ABBA verified.
static var native_preparation_enabled:=true # Probe-only old native/readmission path.
static var native_budget_enabled:=true # Validated native reservations; invalid candidates use full raw admission.
static var full_native_worker_prepack_enabled:=false # Candidate; retains the complete native job lease.
static var full_native_template_reuse_enabled:=false # Offline-proven direct original template; probe candidate.
static var full_native_material_plan_enabled:=true # Applies only inside the opt-in direct native route.
static var ready_worker_yield_enabled:=true # Bytes remain charged after join.
static var fair_publication_enabled:=true # Probe may select the old distance-only order.
static var independent_instance_preparation_enabled:=true # Diagnostic control for dependency-blocked private cursors.
static var native_prefab_direct_specs_enabled:=true
static var material_publication_slices_enabled:=true # Probe-only synchronous control.
static var prepared_material_slicing_enabled:=true # Probe-only control for prepared/shared pixel publication.
static var combined_material_publication_enabled:=true # Finish a ready material slice without reopening its synchronous scope.
static var collision_first_enabled:=false # Exact sidecar experiment; normal geometry/nav gates remain available.
static var collision_query_cache_enabled:=true # Disable for the legacy guard cost/behaviour comparison.
static var collision_query_profile_enabled:=false # Detailed timers are opt-in to avoid perturbing physics ticks.
static var owned_index_projection_enabled:=true # Private raw-model specs transfer without copying/remapping.
static var typed_demand_scan_enabled:=true # Diagnostic control retains the exact unfiltered scheduler.
static var reuse_typed_demand_filter_enabled:=true
static var demand_membership_cache_enabled:=true
static var native_demand_order_enabled:=true
static var native_demand_bounds_enabled:=true
static var incremental_pending_index_enabled:=true
static var demanded_template_scan_enabled:=true
static var ordered_publication_removal_enabled:=true
static var spatial_candidate_reuse_enabled:=true
static var batched_pending_unindex_enabled:=true
static var support_promotion_dedup_enabled:=true
static var native_spatial_union_enabled:=true
static var reuse_spatial_membership_catalogue_enabled:=true
static var reuse_demand_metadata_enabled:=true
static var lazy_demand_snapshot_enabled:=true # Diagnostic eager control; lookup/path catalogs remain live.
const EMPTY_DEMAND:Dictionary={}
static var private_publication_packet_enabled:=true
const COLLISION_QUERY_CACHE_LIMIT:=16
var _pending_snapshot:Array=[]
var _pending_snapshot_dirty:=false
var _pending_snapshot_private:=false # Array owner, not mutable item ownership.
var pending:Array:
	get:
		var value:Array=_materialize_pending_snapshot()
		_pending_snapshot_private=false # The caller may retain or mutate this Array.
		return value
	set(value):
		_pending_snapshot=value;_pending_snapshot_dirty=false;_pending_snapshot_private=false
var profile:Dictionary={"models":0,"instances":0,"specs":0,"worker_us":0,"max_publish_us":0}
var error:=""
var path_errors:Dictionary={}
var instance_errors:Dictionary={}
var source_signatures:Dictionary={}
var _map:Node
var _host:Node
var _drainer:Node
var _jobs:Dictionary={}
var _admission=preload("res://scripts/world3d/resource_admission.gd").new()
var _texture_plan_catalog:=TexturePlanCatalog.new()
var _native_plan_claims:Dictionary={}
var _native_plan_serial:=0
var _texture_attempt_generation:=-1
var loading_worker_limit:=0 # 0 selects production CPU-based capacity; probes may override 2/4/6.
var _saved_interactive_worker_limit:=-1
var _demands:Dictionary={}
var _demand_scope:Dictionary={}
var _demand_revision:=0
var _candidates_revision:=-1
var _demand_revision_trace:RefCounted # Opt-in only; normal loads allocate nothing.
var _demand_membership:Dictionary={} # Per live ticket; spatial candidates only, never readiness/leases.
var _membership_registration_epoch:=0 # Conservative requeue-cache guard.
var _typed_pending:Dictionary={}
var _typed_pending_buildings:=-1
var _pending_kinds:RefCounted
var _demanded_snapshot:Array=[]
var _demanded_snapshot_dirty:=false
var _demanded:Array:
	get:
		if _demanded_snapshot_dirty:
			_demanded_snapshot=_demanded_by_id.values();_demanded_snapshot_dirty=false
			profile.demand_snapshot_materializations=int(profile.get("demand_snapshot_materializations",0))+1
			profile.demand_snapshot_materialized_rows=int(profile.get("demand_snapshot_materialized_rows",0))+_demanded_snapshot.size()
		return _demanded_snapshot
	set(value):
		_demanded_snapshot=value;_demanded_snapshot_dirty=false
var _demanded_by_id:Dictionary={}
var _demanded_by_path:Dictionary={}
var _demanded_rank:Dictionary={}
var _demand_candidate_rows:Dictionary={}
var _demand_candidate_epoch:=0
var _demand_dispatch_catalogue_valid:=false
var _demand_dispatch_catalogue_had_errors:=false
var _completion_emitted:=false
var _prepared_paths:Dictionary={}
var _prepared_template_owners:Dictionary={} # Weak, exact fully prepared allocations; no residency pin.
var _cancelled:=false
var _active:=false
var _priority:=Vector3.ZERO
var _priority_rank_anchor:Variant=null
var _pending_index:Dictionary={}
var _large_pending:Array=[]
var _pending_native_index:Dictionary={}
var _large_native_pending:Dictionary={}
var _indexed:=false
var _doc=preload("res://scripts/world3d/world_document.gd").new()
var _reference_index:Dictionary={}
var _reference_map_path:=""
var _reference_root:=""
var _reference_handoff:RefCounted
var _reference_proof:OwnershipProof
var _runtime_record_ids:Dictionary={}
var runtime_fixture_states:Dictionary={} # Scalar state survives render retirement.
var _runtime_building_records:Dictionary={} # Verified live component adaptation; preserves long-view reload demand.
var _runtime_building_supports:Dictionary={} # Authored IDs only; no mesh/record ownership.
var _runtime_support_order:Dictionary={} # Immutable ordered ID sets, rebuilt only on registration.
var _runtime_support_set_ids:Dictionary={} # Building UUID -> exact ordered support identity.
var _support_set_interns:Dictionary={} # Live IDs only: order, hash bucket and registration users.
var _support_set_buckets:Dictionary={} # Hash collisions retain exact ordered Array comparison.
var _next_support_set_id:=1
var _pending_by_record_id:Dictionary={}
var _memory_estimates:Dictionary={}
var _entry_loading:Dictionary={}
var _loading_cover:Dictionary={}
var _scene_handoff:=false
var _entry_prefetch:Dictionary={}
var _lifetime_tree:SceneTree
var _prefetch_budget_owned:=false
var _native_candidates:Dictionary={}
var _raw_retries:Dictionary={} # Resource-free control; old allocation is retired first.
var _prefab_texture_attempts:Dictionary={} # Bounded plain descriptors, never Image/GPU owners.
var _prefab_texture_attempt_revision:=-1
var _shared_images:=SharedImages.new()
var _pixel_serial:=0
var _pixel_retries:Dictionary={}
var _dispatch_paths:Array=[]
var _dispatch_cursor:=0
var _dispatch_revision:=-1
var _dispatch_capacity:Array=[]
var _dispatch_fence:=""
var _job_cap_waiter:=""
var _dispatch_deadline:=0
var _scheduler_epoch:=0
var _publication_queues:Dictionary={}
var _deferred_removal_items:Array=[]
var _defer_demand_removal:=false
var _publication_order=preload("res://scripts/world3d/publication_order.gd").new()
var _demanded_priority:Dictionary={}
var _path_first:Dictionary={}
var ready_job_limit:=0 # 0: two complete closures per execution slot, at least four.
var _collision_loader_attempted:=false
var _collision_request_ids:Dictionary={}
var _collision_prefetch_service:Node
var _collision_core_priority_ids:Array=[]
var _collision_queries:Dictionary={} # Bounded candidate references/tickets, never readiness results.
var _collision_pending_snapshot:Array=[]
var _collision_pending_count:=-1
var _collision_definition_modes:Dictionary={} # Map/path/immutable rmres identity -> plain policy; never readiness.
var _collision_definition_count:=0
var _collision_definition_bytes:=0
var _preparation_seconds:Array[float]=[] # Bounded feedback, one sample per source job.
var publication_metadata:RefCounted # Borrowed only during the synchronous published signal.

func _note_preparation_latency(items:Array)->void:
	for item:Dictionary in items:
		var job:Dictionary=_jobs.get(item.path,{})
		if not job.has("dispatch_us") or job.get("latency_sampled",false):continue
		job.latency_sampled=true
		_preparation_seconds.append((Time.get_ticks_usec()-int(job.dispatch_us))/1000000.)
		if _preparation_seconds.size()>32:_preparation_seconds.pop_front()
		var ordered:=_preparation_seconds.duplicate();ordered.sort()
		profile.preparation_p90_seconds=ordered[mini(ordered.size()-1,int(ceil(ordered.size()*.9))-1)]
		profile.preparation_latency_samples=int(profile.get("preparation_latency_samples",0))+1

func _job_limit()->int:
	if ready_job_limit>0:return ready_job_limit
	return maxi(4,_admission.worker_limit*2)

func _path_priority(path:String)->int:
	var item:Dictionary=_path_first.get(path,{})
	return int(_demanded_priority.get(str(item.get("record",{}).get("uuid","")),2147483647))

func _path_rank(path:String)->int:
	var item:Dictionary=_path_first.get(path,{})
	return int(_demanded_rank.get(str(item.get("record",{}).get("uuid","")),2147483647))

func _reorder_dispatch_path(path:String)->void:
	# Publication can demote a shared model from a critical nearby instance to
	# distant scenery without changing demand revision. Keep its live head in
	# rank order, or every freed slot can restart the just-preempted lower job.
	# Move only this changed path; never sort the whole queue on each frame.
	if _dispatch_revision!=_demand_revision:return
	var old:=_dispatch_paths.find(path)
	if old<0:return
	_dispatch_paths.remove_at(old)
	if old<_dispatch_cursor:_dispatch_cursor-=1
	if _path_first.has(path):
		var rank:=_path_rank(path);var low:=0;var high:=_dispatch_paths.size()
		while low<high:
			var middle:=int((low+high)/2)
			if _path_rank(_dispatch_paths[middle])<rank:low=middle+1
			else:high=middle
		_dispatch_paths.insert(low,path)
	# A prior admission fence/cursor describes the old ordering. Restart from
	# the current best head on the next bounded dispatch call, even if byte and
	# slot counts have not changed while a whole group is being staged.
	_dispatch_capacity=[];_dispatch_fence=""
	profile.dispatch_path_reorders=int(profile.get("dispatch_path_reorders",0))+1

func _yield_lower_job(priority:int)->bool:
	# A new critical demand may retire one lower-priority private closure. Never
	# release a live worker or a shared producer's lease to manufacture capacity.
	var victim:="";var worst:=priority
	for path:String in _jobs:
		var job:Dictionary=_jobs[path]
		if job.has("pixel_consumer") or job.token.is_cancelled():continue
		var value:=_path_priority(path)
		if value>worst:victim=path;worst=value
	if victim.is_empty():return false
	var job:Dictionary=_jobs[victim]
	job.token.cancel()
	if not job.has("worker"):_discard_job(victim);_prepared_paths.erase(victim)
	profile.priority_retirements=int(profile.get("priority_retirements",0))+1
	return true

func begin_entry_prefetch(tree:SceneTree,clip:AABB,core_model_paths:Dictionary)->bool:
	# The loader calls this only after its core model coordinator has joined.
	# This private queue must never publish into the outgoing map while loading.
	if tree==null or not is_instance_valid(tree.root) or not tree.root.is_inside_tree():return false
	if is_inside_tree() or get_parent()!=null or _active or _cancelled or not _jobs.is_empty() or not _entry_prefetch.is_empty() or not _entry_loading.is_empty():return false
	if not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<=0 or clip.size.z<=0:return false
	for path:Variant in core_model_paths:
		if not path is String or path.is_empty():return false
	_lifetime_tree=tree
	_entry_prefetch={"clip":clip,"core_model_paths":core_model_paths.duplicate(),"previous_scope":get_demand_scope()}
	_configure_admission_budget()
	_prefetch_budget_owned=true
	set_demand("entry_safety",clip,-3)
	set_demand_scope(["entry_safety"])
	_update_loading_worker_capacity(covered_loading_budget_usec)
	profile.entry_prefetch_started_us=Time.get_ticks_usec()
	profile.entry_prefetch_mode="preparing"
	profile.entry_prefetch_budget_bytes=_admission.byte_limit
	set_process(false)
	return true

func pump_entry_prefetch()->void:
	if _entry_prefetch.is_empty() or _active or _cancelled:return
	if not is_instance_valid(_lifetime_tree) or not is_instance_valid(_lifetime_tree.root):return
	if is_instance_valid(_collision_prefetch_service):_collision_prefetch_service.pump_prefetch()
	var began:=Time.get_ticks_usec()
	if not error.is_empty():
		_retire_failed_jobs()
	else:
		_refresh_demanded()
		var required:Dictionary={}
		for item:Dictionary in _demanded:required[item.path]=true
		_poll_jobs(required)
		_resume_pixel_jobs(_lifetime_tree)
		# No acceptance, shared cache mutation or publication in this phase.
		# Finished outputs retain their full byte charge until handoff. A joined
		# worker can yield its execution slot without pretending those bytes freed.
		_dispatch_jobs(_lifetime_tree,true)
	var ready:=0
	for job:Dictionary in _jobs.values():
		if job.has("result") and not job.has("worker") and not job.result.get("waiting_pixels",false) and not job.get("native_binding_pending",false):ready+=1
	profile.entry_prefetch_ready_jobs=ready
	profile.active_jobs=_jobs.size();profile.reserved_bytes=_admission.reserved_bytes
	profile.entry_prefetch_pumps=int(profile.get("entry_prefetch_pumps",0))+1
	var elapsed:=Time.get_ticks_usec()-began
	profile.entry_prefetch_pump_us=int(profile.get("entry_prefetch_pump_us",0))+elapsed
	profile.entry_prefetch_max_pump_us=maxi(int(profile.get("entry_prefetch_max_pump_us",0)),elapsed)

func finish_entry_prefetch()->void:
	if _entry_prefetch.is_empty():return
	# Restore the real previous scope, not the temporary entry_safety scope.
	# Keep its ticket and jobs for begin_entry_loading; do not cancel retained
	# work while the map is still between its loader and destination parent.
	var old_scope:Variant=_demand_scope.duplicate() if _demand_revision_trace!=null else null
	_demand_scope.clear()
	for id:String in _entry_prefetch.previous_scope:_demand_scope[id]=true
	_demand_revision+=1
	if _demand_revision_trace!=null:_demand_revision_trace.scope_change("finish_entry_prefetch",old_scope,_demand_scope,_demand_revision)
	_entry_prefetch.clear()
	_update_loading_worker_capacity(INTERACTIVE_BUDGET_US)
	profile.entry_prefetch_finished_us=Time.get_ticks_usec()
	profile.entry_prefetch_mode="handoff"
	set_process(false)

func begin_scene_handoff()->bool:
	# Only a quiesced queue may cross the staged/committed scene boundary.
	# Reparent emits tree_exiting, but is not cancellation of this map.
	if _active or _cancelled or not is_inside_tree() or not _jobs.is_empty():return false
	_scene_handoff=true
	return true

func end_scene_handoff(host:Node)->void:
	_scene_handoff=false
	_map=get_parent();_host=host
	# Keep publication suspended until the destination frame has been drawn.

func begin_entry_loading(host:Node,clip:AABB,cover:Node=null)->bool:
	if not _entry_prefetch.is_empty():return false
	var map_root:=get_parent()
	if not is_instance_valid(map_root) or not is_instance_valid(host) or not host.is_inside_tree():return false
	var plan:Dictionary=map_root.get_meta("entry_plan",{})
	if plan.is_empty() or int(plan.get("core_resources_ready_us",0))<=0 or not clip.position.is_finite() or not clip.size.is_finite():return false
	if clip!=plan.safety_clip:return false
	if cover!=null:
		# Initial white loading uses InitialLoadingCover; same-map transfer uses
		# TransferLoading. The contract is an opaque drawn cover, not a class name.
		if not cover.has_method("is_opaque_drawn") or not cover.is_opaque_drawn():return false
	else:
		var session:=host.get_node_or_null("/root/GameSession")
		if not "_ready_for_play" in host or host._ready_for_play or session==null or not session.world3d_loading:return false
	var scope:=get_demand_scope()
	_entry_loading={"map":map_root,"host":host,"cover":cover,"previous_scope":scope}
	activate(host)
	set_demand("entry_safety",clip,-3)
	set_demand_scope(["entry_safety"])
	plan.neighbours_started_us=Time.get_ticks_usec()
	map_root.set_meta("entry_plan",plan)
	profile.entry_neighbours_started_us=plan.neighbours_started_us
	return true

func _entry_loading_allowed()->bool:
	if _entry_loading.is_empty() or _cancelled or not is_instance_valid(_host) or not _host.is_inside_tree():return false
	if _entry_loading.get("host")!=_host or _entry_loading.get("map")!=_map or not is_instance_valid(_map) or not _demand_scope.has("entry_safety"):return false
	var cover:Variant=_entry_loading.get("cover")
	if cover!=null:return is_instance_valid(cover) and cover.is_opaque_drawn()
	var session:=_host.get_node_or_null("/root/GameSession")
	return "_ready_for_play" in _host and not _host._ready_for_play and session!=null and session.world3d_loading

func begin_loading_cover(host:Node,cover:Node)->bool:
	# Initial-world loading can stay behind a drawn, opaque cover until the
	# current geometry demand is complete. This is separate from the short
	# entry-safety ticket: the entry ticket may end while the cover remains.
	if host==null or cover==null or not is_instance_valid(host) or not is_instance_valid(cover):return false
	if not cover.has_method("is_opaque_drawn") or not cover.is_opaque_drawn():return false
	_loading_cover={"host":host,"cover":cover}
	return true

func end_loading_cover()->void:
	_loading_cover.clear()

func _covered_loading_ready()->bool:
	if _loading_cover.is_empty() or _cancelled:return false
	if not is_instance_valid(_map) or not _map.is_inside_tree():return false
	var cover:Variant=_loading_cover.get("cover")
	return is_instance_valid(cover) and cover.is_opaque_drawn() and _map.get_viewport().disable_3d

func end_entry_loading(player_clip:Variant=null)->void:
	if _entry_loading.is_empty():return
	var scope:Array=_entry_loading.get("previous_scope",[])
	_entry_loading.clear()
	# Replace the entry's collision lease before withdrawing it. A same-frame
	# gap would discard still-unseen camera colliders and force another build.
	set_demand_scope(scope,["entry_safety"] if player_clip is AABB else [])
	if player_clip is AABB:
		allow_demand_in_scope("player_collision")
		ensure_collision(player_clip,"player_collision")
	release_demand("entry_safety")
	_collision_core_priority_ids.clear()
	_restore_uncovered_worker_capacity()

func _init()->void:
	name="DeferredAssets";set_meta("stream_instance",true);set_process(false)
	_doc.load_immutable_records=true;_doc.load_paint_validation={};_doc.load_texture_checks={};_doc.load_material_pool={};_doc.load_box_meshes={}

func configure_references(index:Dictionary,path:String,content_root:String,ownership_proof:OwnershipProof=null)->void:
	# A new mounted operation must not inherit the previous source identities.
	# In-flight consumers keep their original pool until their jobs retire.
	if _jobs.is_empty():_shared_images=SharedImages.new()
	_retire_native_plan_claims({});_texture_plan_catalog.reset();_texture_attempt_generation=-1
	if _reference_handoff!=null:_reference_handoff.retire();_reference_handoff=null
	_invalidate_collision_queries()
	_runtime_building_records.clear()
	_materialize_pending_snapshot()
	_runtime_building_supports.clear();_clear_runtime_support_sets();_pending_by_record_id.clear()
	_reference_index=index;_reference_map_path=path;_reference_root=content_root;_reference_proof=ownership_proof
	_collision_definition_modes.clear();_collision_definition_count=0;_collision_definition_bytes=0
	_prefab_texture_attempts.clear();_prefab_texture_attempt_revision=-1
	_collision_loader_attempted=false

func _new_collision_service()->Node:
	return load("res://scripts/world3d/collision_dependency_loader.gd").new()

func begin_collision_prefetch(owner:Node,clip:AABB,core_priority_ids:Array=[])->bool:
	# This is called only after MapLoader's initial integrity/record validation
	# and core CPU workers have completed. Selection stays within unbuilt safety
	# records; landing supports and complete native/building groups stay visual.
	if not collision_first_enabled or _entry_prefetch.is_empty() or _cancelled or _active or is_instance_valid(_collision_prefetch_service):return false
	if _reference_proof==null or _reference_index.is_empty() or not is_instance_valid(owner) or not owner.is_inside_tree():return false
	var entries:Array=[]
	for item:Dictionary in _in_clip(clip):
		if not _collision_entry_supported(item):continue
		var at:int=int(item.reference_entry.get("record_index",-1))
		if at<0 or at>=_reference_index.rows.size():continue
		var row:Dictionary=_reference_index.rows[at]
		if row.get("reason","")!="model_accessor_bounds" or not row.get("bounds_known",false) or not row.get("owner_keys",[]).is_empty():continue
		entries.append(item.reference_entry)
	if entries.is_empty():return false
	_collision_core_priority_ids=core_priority_ids.duplicate()
	entries=_prioritize_collision_entries(entries,_collision_core_priority_ids)
	var hinted:Dictionary={};var first_ids:Array=[]
	for entry:Dictionary in entries:
		var uuid:String=entry.compact_record.uuid
		if uuid in _collision_core_priority_ids:hinted[uuid]=true
		if first_ids.size()<16:first_ids.append(uuid)
	profile.collision_prefetch_core_hint_count=hinted.size()
	profile.collision_prefetch_request_head=first_ids
	var service:=_new_collision_service();owner.add_child(service)
	var configured:Dictionary=service.begin_prefetch(owner,_reference_index,_reference_map_path,_reference_root,_reference_proof)
	if not configured.get("ok",false):
		profile.collision_prefetch_error=str(configured.get("error",configured.get("reason","configuration_failed")))
		service.cancel("prefetch_configuration_failed");service.queue_free();return false
	_collision_prefetch_service=service
	var requested:Dictionary=service.request(entries,-3,"entry_safety")
	if not requested.get("ok",false):
		profile.collision_prefetch_error=str(requested.get("error",requested.get("reason","request_failed")))
		_cancel_collision_prefetch("prefetch_request_failed");return false
	_collision_request_ids.entry_safety=true
	profile.collision_prefetch_started_us=Time.get_ticks_usec()
	profile.collision_prefetch_entries=entries.size()
	return true

static func _prioritize_collision_entries(entries:Array,preferred:Array)->Array:
	var ids:Dictionary={}
	for value:Variant in preferred:
		if value is String and not value.is_empty():ids[value]=true
	if ids.is_empty():return entries
	var first:Array=[];var rest:Array=[]
	for entry:Dictionary in entries:
		if ids.has(str(entry.compact_record.uuid)):first.append(entry)
		else:rest.append(entry)
	first.append_array(rest);return first

func handoff_collision_prefetch(map_root:Node)->bool:
	if not is_instance_valid(_collision_prefetch_service):return true
	if not _collision_prefetch_service.matches_context(_reference_index,_reference_map_path,_reference_root,_reference_proof):
		profile.collision_prefetch_error="handoff_context_changed";_collision_loader_attempted=true;_cancel_collision_prefetch("prefetch_context_changed");return false
	var result:Dictionary=_collision_prefetch_service.handoff(map_root,map_root.get_instance_id())
	if not result.get("ok",false):
		profile.collision_prefetch_error=str(result.get("error",result.get("reason","handoff_failed")))
		_collision_loader_attempted=true;_cancel_collision_prefetch("prefetch_handoff_failed");return false
	# The same service is now a child of the returned, still off-tree map. Its
	# private outputs retain their admission until real adoption or cancellation.
	profile.collision_prefetch_handoff_us=Time.get_ticks_usec()
	return true

func _adopt_collision_prefetch()->void:
	if not is_instance_valid(_collision_prefetch_service):return
	if not _collision_prefetch_service.matches_context(_reference_index,_reference_map_path,_reference_root,_reference_proof):
		profile.collision_prefetch_error="adoption_context_changed";_collision_loader_attempted=true;_cancel_collision_prefetch("prefetch_context_changed");return
	var result:Dictionary=_collision_prefetch_service.adopt(_map,_map.get_instance_id())
	if not result.get("ok",false):
		profile.collision_prefetch_error=str(result.get("error",result.get("reason","adoption_failed")))
		_collision_loader_attempted=true;_cancel_collision_prefetch("prefetch_adoption_failed");return
	profile.collision_prefetch_adopted_us=Time.get_ticks_usec()
	_collision_prefetch_service=null # Map service now owns its tickets and results.

func _cancel_collision_prefetch(reason:String)->void:
	_invalidate_collision_queries()
	if not is_instance_valid(_collision_prefetch_service):return
	var service:Node=_collision_prefetch_service;_collision_prefetch_service=null
	_collision_request_ids.erase("entry_safety")
	# cancel transfers active CPU leases to Drainer; never join them on main.
	service.cancel(reason);service.queue_free()

func _collision_loader(create:bool=false)->Node:
	if is_instance_valid(_collision_prefetch_service):return _collision_prefetch_service
	if not is_instance_valid(_map):return null
	var existing:Node=_map.get_node_or_null("CollisionDependencyLoader")
	if existing!=null:return existing
	# configure_references runs while this queue is still a private off-tree
	# loader result. Instantiate the map-owned service only after real adoption.
	if not create or not collision_first_enabled or _collision_loader_attempted or not _map.is_inside_tree() or _reference_proof==null or _reference_index.is_empty():return null
	_collision_loader_attempted=true
	var service:Node=_new_collision_service()
	_map.add_child(service)
	var configured:Dictionary=service.configure(_reference_index,_reference_map_path,_reference_root,_reference_proof,_map,_map.get_instance_id())
	if not configured.get("ok",false):
		profile.collision_configuration_error=str(configured.get("error",configured.get("reason","configuration_failed")))
		service.free();return null
	return service

func _release_collision_request(id:String)->void:
	_collision_queries.erase(id)
	if not _collision_request_ids.erase(id):return
	var service:=_collision_loader()
	if service!=null:service.release_request(id)

func requeue_reference(entry:Dictionary)->bool:
	return requeue_references([entry])==1

static var native_reference_batching_enabled:=true
const ROAD_REFERENCE_BATCH_SIZE:=16
const ROAD_REFERENCE_BATCH_BYTES:=64*1024*1024
static func reference_path(entry:Dictionary)->String:
	var asset:String=entry.get("asset_path","")
	if not asset.is_empty():return asset
	var group:String=entry.get("group_id","")
	if not group.is_empty():return "reference:"+group
	# Independent road rows share one bounded read/validation transaction. Only
	# live demands enter _reference_requests; spatial and publication units stay
	# independent. Stable catalog pages also work after retirement and revisit.
	if native_reference_batching_enabled and entry.get("reason","")=="native_road":
		return "reference:road_batch:"+str(floori(float(entry.record_index)/ROAD_REFERENCE_BATCH_SIZE))
	return "reference:"+str(entry.record_index)

static var background_requeue_records_enabled:=true
static var dirty_requeue_index_enabled:=true
static var selective_requeue_membership_enabled:=true
var require_native_products:=false: # Copied from the owning game MapLoader.
	set(value):
		require_native_products=value
		_doc.load_require_native_products=value
func requeue_references(entries:Array)->int:
	# Called only after resident stream/navigation ownership has been released.
	# Preserve the compact catalog and verified model version for a later revisit.
	if _reference_index.is_empty():return 0
	var incremental:bool=incremental_pending_index_enabled and _indexed
	# A dirty snapshot was detached when publication transferred authoritative
	# ownership to the UUID index. Never reuse an externally borrowed live Array.
	var canonical_pending:bool=incremental and _pending_by_record_id.size()==pending_count() and _large_native_pending.size()==_large_pending.size() and _pending_kinds!=null and _pending_kinds.owners.size()==pending_count()
	var direct_pending:bool=dirty_requeue_index_enabled and _pending_snapshot_dirty and canonical_pending
	# Membership preservation and skipping Array materialization are independent.
	var preserve_membership:bool=selective_requeue_membership_enabled and canonical_pending and (_pending_snapshot_dirty or _pending_snapshot_private)
	var known:Dictionary={};var selected:Dictionary={};var accepted:Array=[]
	# The ordered pending catalog already owns these UUIDs. Borrow it only for
	# membership queries; accepted entries enter through _index_pending_item,
	# so neither duplicates nor a refused requeue can mutate the live index.
	if incremental and _pending_by_record_id.size()==pending_count():known=_pending_by_record_id
	else:
		for item:Dictionary in _materialize_pending_snapshot():known[item.record.uuid]=true
		profile.requeue_membership_scan_rows=int(profile.get("requeue_membership_scan_rows",0))+pending_count()
	for entry:Dictionary in entries:
		var uuid:String=entry.compact_record.uuid
		if known.has(uuid) or selected.has(uuid):continue
		selected[uuid]=true;accepted.append(entry)
	if accepted.is_empty():return 0
	if incremental:
		# Keep empty cells until a requeue, matching the old query strategy
		# between publications. Prune only keys, without reindexing every row.
		for cell:Vector2i in _pending_index.keys():
			if _pending_index[cell].is_empty():_pending_index.erase(cell);_pending_native_index.erase(cell)
	var extra:Dictionary=_map.get_meta("extras",{})
	var records:Array=extra.get("rmmo_records",[])
	var retired_records:Array=[]
	var defer_records:bool=background_requeue_records_enabled and preload("res://scripts/world3d/resource_retirement.gd").background_decoded_release_enabled
	var write:=0;var moved:=0
	for read:int in records.size():
		if selected.has(records[read].uuid):
			# These are decoded authoring records, never scene specs or Resources.
			# Keep their last roots until both map catalogs relinquish ownership;
			# otherwise nested height/definition arrays destruct in this callback.
			if defer_records:retired_records.append(records[read])
			continue
		# Preserve the untouched prefix without redundant Variant ref/unref work.
		if write!=read:records[write]=records[read];moved+=1
		write+=1
	profile.requeue_record_scan_rows=int(profile.get("requeue_record_scan_rows",0))+records.size()
	profile.requeue_record_write_rows=int(profile.get("requeue_record_write_rows",0))+moved
	if write!=records.size():records.resize(write)
	# Retirement is a scene-thread operation, not a new filesystem read. A path
	# admitted before carries its original decoded-size estimate. An initially
	# resident-only path without that estimate safely retries in exclusive mode.
	for entry:Dictionary in accepted:
		var uuid:String=entry.compact_record.uuid;var path:String=entry.asset_path
		var native:=path.is_empty()
		if native:path=reference_path(entry)
		_runtime_record_ids.erase(uuid)
		var memory:Dictionary=_memory_estimates.get(path,{"estimated_bytes":_admission.byte_limit,"exclusive":true,"known":false})
		var runtime_bounds:Variant=_runtime_building_records.get(uuid)
		var item:Dictionary={"record":entry.compact_record,"path":path,"bounds":runtime_bounds if runtime_bounds is AABB else entry.bounds,"digest":source_signatures.get(path,""),"memory":memory,"manifest":_reference_index.models.get(path,{}),"draw_order":int(entry.record_index)*65536,"reference_entry":entry,"reference_prepared":false,"native_reference":native,"group_id":entry.get("group_id","")}
		if not direct_pending:_materialize_pending_snapshot().append(item)
		if incremental:
			var previous:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
			if not previous.is_empty():_unindex_pending_item(previous)
			_index_pending_item(item)
	if incremental:
		profile.pending_index_updates=int(profile.get("pending_index_updates",0))+1
		profile.pending_indexed_items=int(profile.get("pending_indexed_items",0))+accepted.size()
	else:
		_indexed=false;_pending_index.clear();_large_pending.clear();_pending_native_index.clear();_large_native_pending.clear()
	if preserve_membership:_preserve_unrelated_typed_memberships(accepted)
	else:_demand_membership.clear()
	_typed_pending.clear();_typed_pending_buildings=-1
	if direct_pending:profile.requeue_direct_pending_items=int(profile.get("requeue_direct_pending_items",0))+accepted.size()
	_demand_revision+=1
	if _demand_revision_trace!=null:_demand_revision_trace.change("requeue","",0,accepted.size(),_demand_revision)
	_invalidate_collision_queries()
	if not retired_records.is_empty() and preload("res://scripts/world3d/resource_retirement.gd").defer_cpu_values(retired_records,0):
		# No recursive byte scan solely for disposal statistics. Zero here is
		# unmeasured, not an estimate of the records' actual resident memory.
		profile.requeue_retired_records=int(profile.get("requeue_retired_records",0))+retired_records.size()
	_completion_emitted=false;set_process(_active)
	return accepted.size()

func activate(host:Node)->void:
	if not _entry_prefetch.is_empty():return # Only finish + entry ownership permits publication.
	_invalidate_collision_queries()
	_map=get_parent();_host=host;_active=true;set_process(true)
	_lifetime_tree=get_tree()
	_adopt_collision_prefetch()
	_runtime_record_ids.clear()
	for record:Dictionary in _map.get_meta("extras",{}).get("rmmo_records",[]):_runtime_record_ids[record.uuid]=record
	for item:Dictionary in _materialize_pending_snapshot():
		if not _memory_estimates.has(item.path) and item.has("memory"):_memory_estimates[item.path]=item.memory
	# Keep decoded outputs and upload copies inside a conservative physical-RAM
	# envelope. Oversized/unknown tasks run alone rather than starving forever.
	# Early preparation and normal consumption share this exact ledger. Do not
	# resize its allowance or misreport retained outputs as freed at adoption.
	if not _prefetch_budget_owned:_configure_admission_budget()

func _configure_admission_budget()->void:
	var memory:=OS.get_memory_info()
	var physical:=int(memory.get("physical",16*1024*1024*1024))
	var total:=clampi(physical/4,512*1024*1024,8*1024*1024*1024)
	_admission.byte_limit=preload("res://scripts/world3d/definition_cache_policy.gd").work_budget(total)
	profile.definition_cache_reserved_bytes=preload("res://scripts/world3d/definition_cache_policy.gd").reserved_bytes()
	# Lazy canonical collision arrays share the existing bounded decode cache.
	# Reserve its entire ceiling separately; private task outputs stay charged.
	profile.prefab_decode_reserved_bytes=Prefab.DECODE_BUDGET if Prefab.raw_face_reuse_active() else 0
	_admission.byte_limit=maxi(1,_admission.byte_limit-int(profile.prefab_decode_reserved_bytes))
	# Plain definition-policy hints survive individual jobs. Reserve their fixed
	# ceiling outside task leases so an exclusive model can still drain/run.
	profile.geometry_definition_reserved_bytes=CollisionGeometry.MAX_DEFINITION_BYTES if CollisionGeometry.enabled else 0
	_admission.byte_limit=maxi(1,_admission.byte_limit-int(profile.geometry_definition_reserved_bytes))
	profile.reference_handoff_reserved_bytes=_reference_handoff.reserved_bytes if _reference_handoff!=null else 0
	_admission.byte_limit=maxi(1,_admission.byte_limit-int(profile.reference_handoff_reserved_bytes))
	profile.texture_plan_reserved_bytes=TexturePlanCatalog.RESERVED_BYTES if texture_plan_reuse_enabled and not preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures else 0
	_admission.byte_limit=maxi(1,_admission.byte_limit-int(profile.texture_plan_reserved_bytes))
	_texture_plan_catalog.reapply_metadata_budget(_admission)

func is_complete()->bool:return pending_count()==0 and _jobs.is_empty() and _texture_plan_catalog.pending_count()==0

func active_workers()->int:
	var count:=0
	for path:String in _jobs:
		if _jobs[path].has("worker"):
			var lease:Dictionary=_admission._entries.get(path,{})
			if lease.get("occupies_worker",true):count+=int(lease.get("worker_slots",1))
	# Shared pixel retirement borrows this ledger's execution slots but has no
	# _jobs entry. Keep header and cross-map prefetch reporting semantics intact:
	# headers are counted by the catalog below, unrelated leases are not added.
	for lease:Dictionary in _admission._entries.values():
		if lease.get("stage","")=="shared_pixel_retiring" and lease.get("occupies_worker",false):count+=int(lease.get("worker_slots",1))
	return count+_texture_plan_catalog.pending_count()

func quiesce()->void:
	_invalidate_collision_queries()
	# Cross-map raw import must not overlap an old map's raw GLTF worker.
	# Stay inactive until the owner explicitly restores the previous state:
	# navigation providers can still update demand tickets while we await frames.
	_active=false;set_process(false)
	_cancel_collision_prefetch("prefetch_quiesced")
	finish_entry_prefetch()
	var tree:SceneTree=get_tree() if is_inside_tree() else _lifetime_tree
	for job:Dictionary in _jobs.values():job.token.cancel()
	while not _jobs.is_empty() or _texture_plan_catalog.pending_count()>0 or _admission.retiring_pixel_outputs>0:
		_texture_plan_catalog.poll()
		for path:String in _jobs.keys():
			var job:Dictionary=_jobs[path]
			if job.has("worker"):
				if job.worker.is_alive():continue
				job.result=job.worker.wait_to_finish()
				if CompletedTrace.enabled:CompletedTrace.joined(path,job.token.get_instance_id(),job.result)
				if is_instance_valid(_drainer):_drainer.forget(job.worker)
				job.erase("worker")
			# Even a scene-less result can own worker-created render resources.
			# Join before releasing its reservation; never wait for live GPU work
			# or take RAW_IMPORT_MUTEX on the main thread.
			Drainer.synchronize_transfer()
			_discard_job(path)
		if not _jobs.is_empty() or _texture_plan_catalog.pending_count()>0 or _admission.retiring_pixel_outputs>0:
			if is_instance_valid(tree):await tree.process_frame
			else:shutdown();return
	profile.active_jobs=0;profile.reserved_bytes=_admission.reserved_bytes
	_raw_retries.clear()
	_retire_native_plan_claims({})
	# pending and prepared paths are unchanged, so rollback can retry cancelled
	# work without duplicating already-published instances or cached models.
	set_process(false)
	if _prefetch_budget_owned:profile.entry_prefetch_mode="quiesced"

func shutdown()->void:
	_texture_plan_catalog.shutdown()
	_retire_native_plan_claims({})
	if _reference_handoff!=null:_reference_handoff.retire();_reference_handoff=null
	_invalidate_collision_queries()
	_demand_membership.clear()
	_pending_kinds=null
	_typed_pending.clear();_typed_pending_buildings=-1
	# Final owner teardown has no future frame on which to poll. Ordinary load
	# failure uses await quiesce() before resuming the old map, never this drain.
	_active=false;_cancelled=true;set_process(false)
	_cancel_collision_prefetch("prefetch_shutdown")
	for id:String in _collision_request_ids.keys():_release_collision_request(id)
	finish_entry_prefetch()
	for job:Dictionary in _jobs.values():job.token.cancel()
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if job.has("worker"):
			if is_instance_valid(_drainer):_drainer.forget(job.worker)
			_clear_native_plan_aliases(job)
			Drainer.drain_shutdown(job.worker,job.token)
			job.erase("worker")
		else:Drainer.synchronize_transfer()
		_discard_job(path)
	# This explicit synchronous shutdown has no later owner to await the
	# transferred byte leases. Ordinary quiesce waits asynchronously instead.
	preload("res://scripts/world3d/resource_retirement.gd").drain_shared_pixel_buffers(_admission)
	profile.active_jobs=0;profile.reserved_bytes=_admission.reserved_bytes
	_raw_retries.clear()
	if _prefetch_budget_owned:profile.entry_prefetch_mode="shutdown"
	_runtime_record_ids.clear()
	_materialize_pending_snapshot()
	_pending_by_record_id.clear();_runtime_building_records.clear();_runtime_building_supports.clear();_clear_runtime_support_sets()

func _notification(what:int)->void:
	# An off-tree queue has never received _exit_tree. A forced loader teardown
	# must still keep live worker-owned resources alive until their safe drain.
	if what==NOTIFICATION_PREDELETE and (not _jobs.is_empty() or _texture_plan_catalog.pending_count()>0 or is_instance_valid(_collision_prefetch_service) or _reference_handoff!=null):shutdown()

func is_idle()->bool:
	# Observers must not do unbudgeted scheduling work. Until the next admitted
	# process refresh, an outdated demand snapshot is conservatively not idle.
	return _candidates_revision==_demand_revision and _demanded_count()==0 and _jobs.is_empty() and _texture_plan_catalog.pending_count()==0

func start_demand_revision_trace(capacity:int=4096)->void:
	_demand_revision_trace=preload("res://scripts/world3d/demand_revision_trace.gd").new(capacity)

func demand_revision_trace_snapshot()->Dictionary:
	return _demand_revision_trace.snapshot() if _demand_revision_trace!=null else {}

func stop_demand_revision_trace()->Dictionary:
	var value:Dictionary=demand_revision_trace_snapshot();_demand_revision_trace=null;return value

func set_demand(id:String,clip:AABB,priority:int=0,kind:String="all",rank_from_player:bool=false)->void:
	if id.is_empty() or not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.z<0:return
	if kind not in ["all","building","road","structure","terrain"]:return
	var value:={"clip":clip,"priority":priority,"kind":kind}
	if rank_from_player:value.rank_from_player=true
	var previous:Variant=_demands.get(id)
	if previous==value:return
	_demands[id]=value;_demand_revision+=1;set_process(_active)
	if _demand_revision_trace!=null:_demand_revision_trace.change("set_demand",id,previous,value,_demand_revision)

func release_demand(id:String)->void:
	_release_collision_request(id)
	_demand_membership.erase(id)
	var previous:Variant=_demands.get(id) if _demand_revision_trace!=null else null
	if _demands.erase(id):
		_demand_revision+=1
		if _demand_revision_trace!=null:_demand_revision_trace.change("release_demand",id,previous,null,_demand_revision)
		set_process(_active)

func set_group_demand(id:String,group_id:String,priority:int=-2)->bool:
	# Exact indexed membership; a whole-building request must not pull unrelated
	# objects merely because their bounds overlap the building. Scope is still
	# controlled separately by allow_demand_in_scope/set_demand_scope.
	var group:Dictionary=_reference_index.get("groups",{}).get(group_id,{})
	if id.is_empty() or group.is_empty() or not group.get("bounds") is AABB:return false
	var value:Dictionary={"clip":group.bounds,"priority":priority,"kind":"all","group_id":group_id}
	var previous:Variant=_demands.get(id)
	if previous!=value:
		_demands[id]=value;_demand_revision+=1;set_process(_active)
		if _demand_revision_trace!=null:_demand_revision_trace.change("group_demand",id,previous,value,_demand_revision)
	return true

func group_is_published(group_id:String)->bool:
	# This is a Deferred publication endpoint, not a physics/readiness claim.
	# Members already installed by initial loading are absent from pending; the
	# authority consumer additionally verifies actual resident membership.
	if not error.is_empty() or not _reference_index.get("groups",{}).has(group_id):return false
	for item:Dictionary in _materialize_pending_snapshot():
		if item.get("group_id","")==group_id and not item.get("published",false):return false
	return true

func get_demand_scope()->Array:
	return _demand_scope.keys()

func set_demand_scope(ids:Array,retained_collision_tickets:Array=[])->bool:
	# Empty means normal scheduling. Tickets remain intact while a transaction
	# temporarily permits only its destination and staged-navigation demands.
	var allowed:Dictionary={}
	for id:Variant in ids:
		if not id is String or id.is_empty():return false
		allowed[id]=true
	if allowed==_demand_scope:
		_restore_uncovered_worker_capacity();return true
	var old_scope:Variant=_demand_scope if _demand_revision_trace!=null else null
	_demand_scope=allowed;_demand_revision+=1
	if _demand_revision_trace!=null:_demand_revision_trace.scope_change("set_scope",old_scope,allowed,_demand_revision)
	for id:String in _collision_request_ids.keys():
		if not _demand_scope.is_empty() and not _demand_scope.has(id) and id not in retained_collision_tickets:_release_collision_request(id)
	_refresh_demanded()
	# Cooperative cancellation only. A live worker keeps its admission charge
	# and is joined by _process after it finishes, never by this scope setter.
	# Use instance identities: an old far-only job may share the target's model.
	for job:Dictionary in _jobs.values():
		var needed:=false
		for uuid:String in job.get("publication_ids",[]):
			if _demanded_by_id.has(uuid):needed=true;break
		if not needed:job.token.cancel()
	_restore_uncovered_worker_capacity()
	set_process(_active)
	return true

func allow_demand_in_scope(id:String)->bool:
	if id.is_empty():return false
	# Unrestricted operation must not accidentally become a one-ticket scope.
	if _demand_scope.is_empty() or _demand_scope.has(id):return true
	_demand_scope[id]=true;_demand_revision+=1;set_process(_active)
	if _demand_revision_trace!=null:_demand_revision_trace.change("allow_scope",id,null,_demand_scope.size(),_demand_revision)
	return true

func error_for_clip(clip:AABB)->String:
	# The normal path has no scoped failure to locate. Keep the global error
	# and exact spatial lookup for failures, without scanning pending twice on
	# every successful physics tick (ensure_geometry checks the same footprint).
	if instance_errors.is_empty() and path_errors.is_empty():return error
	for item:Dictionary in _in_clip(clip):
		if instance_errors.has(item.record.uuid):return str(instance_errors[item.record.uuid])
		if path_errors.has(item.path):return str(path_errors[item.path])
	return error

func retry_failed(clip:AABB)->void:
	_demand_dispatch_catalogue_valid=false
	_invalidate_collision_queries()
	_prefab_texture_attempts.clear()
	for item:Dictionary in _in_clip(clip):
		path_errors.erase(item.path);instance_errors.erase(item.record.uuid)
	profile.failed_paths=path_errors.size();profile.failed_instances=instance_errors.size()
	_demand_revision+=1 # Reopen path cursors and admission fences after repair.
	if _demand_revision_trace!=null:_demand_revision_trace.change("retry_failed","",null,clip,_demand_revision)
	set_process(_active)

func _path_failed(path:String,reason:String)->void:
	_demand_dispatch_catalogue_valid=false
	_invalidate_collision_queries()
	path_errors[path]=reason
	profile.failed_paths=path_errors.size()

func _instance_failed(uuid:String,reason:String)->void:
	_demand_dispatch_catalogue_valid=false
	_invalidate_collision_queries()
	instance_errors[uuid]=reason
	var failed:Dictionary=_demanded_by_id.get(uuid,_pending_by_record_id.get(uuid,{}))
	var group:String=failed.get("group_id","")
	var ids:Array=[uuid]
	if not group.is_empty() and _reference_index.get("groups",{}).has(group):
		ids=[]
		for at:int in _reference_index.groups[group].members:ids.append(_reference_index.extras.rmmo_records[at].uuid)
	# Failure may be the final member's ONLY event. Waiting for another arrival
	# in _stage_building would pin its already-staged healthy peers indefinitely.
	# Abort this atomic group, never unrelated groups sharing the model path.
	var paths:Dictionary={}
	for id:String in ids:
		instance_errors[id]=reason if id==uuid else "Atomic building member failed: "+uuid
		var member:Dictionary=_demanded_by_id.get(id,_pending_by_record_id.get(id,{}))
		if member.is_empty():continue
		paths[member.path]=true
		var job:Dictionary=_jobs.get(member.path,{})
		if CompletedTrace.enabled and job.has("token"):CompletedTrace.record(member.path,job.token.get_instance_id(),"failed",{"uuid":id,"reason":instance_errors[id]})
		job.get("staged",{}).erase(id);job.get("staged_groups",{}).erase(group)
	for path:String in paths:
		_path_first.erase(path)
		for item:Dictionary in _demanded_by_path.get(path,[]):
			if not instance_errors.has(item.record.uuid):_path_first[path]=item;break
		_reorder_dispatch_path(path)
	profile.failed_instances=instance_errors.size()

func pending_count()->int:
	return _pending_by_record_id.size() if _pending_snapshot_dirty else _pending_snapshot.size()

func pending_demanded_count()->int:
	# Count the existing observer predicate without exposing the snapshot.
	# Mutable/aliased or diagnostic rows retain exact per-Array semantics.
	var canonical:bool=incremental_pending_index_enabled and _indexed and (_pending_snapshot_dirty or _pending_snapshot_private) and _pending_by_record_id.size()==pending_count() and _large_native_pending.size()==_large_pending.size() and _pending_kinds!=null and _pending_kinds.owners.size()==pending_count()
	var count:=0
	if canonical:
		var smaller:Dictionary=_pending_by_record_id if _pending_by_record_id.size()<=_demanded_by_id.size() else _demanded_by_id
		var other:Dictionary=_demanded_by_id if is_same(smaller,_pending_by_record_id) else _pending_by_record_id
		for uuid:String in smaller:
			if other.has(uuid):count+=1
	else:
		for item:Dictionary in _materialize_pending_snapshot():
			if _demanded_by_id.has(item.record.uuid):count+=1
	return count

func _materialize_pending_snapshot()->Array:
	if _pending_snapshot_dirty:
		# Internal publication already invalidated collision queries. Replacing
		# this private representation is not an external membership mutation.
		var observed:=is_same(_collision_pending_snapshot,_pending_snapshot) and _collision_pending_count==pending_count()
		_pending_snapshot=_pending_by_record_id.values();_pending_snapshot_dirty=false;_pending_snapshot_private=true
		if observed:_collision_pending_snapshot=_pending_snapshot
		profile.pending_snapshot_materializations=int(profile.get("pending_snapshot_materializations",0))+1
		profile.pending_snapshot_materialized_rows=int(profile.get("pending_snapshot_materialized_rows",0))+_pending_snapshot.size()
	return _pending_snapshot

func pending_record_catalogue()->Variant:
	# Borrow only during one synchronous observation. Publication and requeue
	# already maintain this authoritative UUID map; callers must not mutate or
	# retain it across a yield. Diagnostic/non-indexed producers keep their scan.
	if not incremental_pending_index_enabled or not _indexed or _pending_by_record_id.size()!=pending_count():return null
	return _pending_by_record_id

func adopt_prepared_pending(prepared:RefCounted)->bool:
	# Only a fresh queue accepts the parser's private catalogue. Dynamic callers
	# and diagnostic UUID aliases retain the general rebuild/incremental path.
	if prepared==null or _indexed or not _runtime_building_records.is_empty() or not prepared.matches(_materialize_pending_snapshot()):return false
	var began:=Time.get_ticks_usec()
	_pending_by_record_id=prepared.owners;_pending_index=prepared.cells
	_pending_native_index=prepared.native_cells;_large_pending=prepared.large;_large_native_pending=prepared.native_large
	_pending_kinds=prepared.kinds;_indexed=true
	profile.pending_worker_indexed_rows=prepared.count
	profile.pending_worker_prepare_us=prepared.elapsed_us
	profile.typed_worker_partition_rows=prepared.count
	prepared.relinquish()
	profile.pending_worker_adopt_us=Time.get_ticks_usec()-began
	return true

func _index_pending()->void:
	if _indexed:return
	_demand_membership.clear()
	_pending_kinds=null
	_typed_pending.clear();_typed_pending_buildings=-1
	var records:Array=_materialize_pending_snapshot() # Materialize before clearing its authoritative owners.
	_pending_by_record_id.clear();_pending_index.clear();_large_pending.clear();_pending_native_index.clear();_large_native_pending.clear()
	for item:Dictionary in records:_index_pending_item(item)
	profile.pending_index_builds=int(profile.get("pending_index_builds",0))+1
	profile.pending_indexed_items=int(profile.get("pending_indexed_items",0))+pending_count()
	_indexed=true

func _index_pending_item(item:Dictionary)->void:
	_pending_by_record_id[item.record.uuid]=item
	var box:AABB=item.bounds
	item.demand_rect=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
	var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
	if _pending_kinds!=null:
		_pending_kinds.add(item,(high.x-low.x+1)*(high.y-low.y+1)>64,_runtime_building_records)
		profile.typed_incremental_classifications=int(profile.get("typed_incremental_classifications",0))+1
	if (high.x-low.x+1)*(high.y-low.y+1)>64:_large_pending.append(item);_large_native_pending[item.record.uuid]=item;return
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key:=Vector2i(x,z)
			if not _pending_index.has(key):_pending_index[key]=[]
			_pending_index[key].append(item)
			if not _pending_native_index.has(key):_pending_native_index[key]={}
			_pending_native_index[key][item.record.uuid]=item

static func _erase_pending_identity(values:Array,item:Dictionary)->void:
	for i:int in values.size():
		if is_same(values[i],item):values.remove_at(i);return

func _unindex_pending_batch(items:Array)->bool:
	# Publication keeps empty buckets so the full-scan/bucket selection and its
	# stable order do not change. Sparse requeue removals keep their own path.
	if _pending_by_record_id.size()!=pending_count():return false
	var owners:Dictionary={};var cells:Dictionary={};var large:Dictionary={};var visits:=0
	for item:Dictionary in items:
		var uuid:String=item.record.uuid
		if owners.has(uuid) or not is_same(_pending_by_record_id.get(uuid),item):return false
		owners[uuid]=item
		var box:AABB=item.bounds;var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
		var count_:int=(high.x-low.x+1)*(high.y-low.y+1)
		if count_>64:large[uuid]=item;visits+=1;continue
		visits+=count_
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var key:=Vector2i(x,z)
				if not cells.has(key):cells[key]={}
				cells[key][uuid]=item
	# Avoid whole-bucket filtering for a batch of unrelated sparse removals.
	if visits<4*(cells.size()+int(not large.is_empty())):return false
	var rows:=0;var filters:=0;var tail_rows:=0
	for key:Vector2i in cells:
		if not _pending_index.has(key):continue
		var work:=_filter_pending_owners(_pending_index[key],cells[key])
		for uuid:String in cells[key]:
			if is_same(_pending_native_index.get(key,EMPTY_DEMAND).get(uuid),cells[key][uuid]):_pending_native_index[key].erase(uuid)
		rows+=work.x;tail_rows+=work.y;filters+=1
	if not large.is_empty():
		var work:=_filter_pending_owners(_large_pending,large)
		for uuid:String in large:
			if is_same(_large_native_pending.get(uuid),large[uuid]):_large_native_pending.erase(uuid)
		rows+=work.x;tail_rows+=work.y;filters+=1
	for uuid:String in owners:
		if _pending_kinds!=null:_pending_kinds.remove(owners[uuid])
		_pending_by_record_id.erase(uuid)
	profile.pending_bucket_filter_rows=int(profile.get("pending_bucket_filter_rows",0))+rows
	profile.pending_bucket_filters=int(profile.get("pending_bucket_filters",0))+filters
	profile.pending_bucket_tail_rows=int(profile.get("pending_bucket_tail_rows",0))+tail_rows
	return true

static func _filter_pending_owners(values:Array,owners:Dictionary)->Vector2i:
	# Preserve the original bucket Array and stable survivors. Remove only the
	# first exact occurrence of each owner, even with duplicate UUID aliases.
	if owners.is_empty():return Vector2i.ZERO
	var remaining:Dictionary=owners.duplicate();var count_:=values.size();var write:=0
	for read:int in count_:
		var item:Dictionary=values[read];var uuid:String=item.record.uuid
		if is_same(remaining.get(uuid),item):
			remaining.erase(uuid)
			if remaining.is_empty():
				# All requested owners for THIS bucket have been found. Copy the
				# unchanged suffix in native code instead of scanning every row.
				var tail:Array=values.slice(read+1)
				values.resize(write);values.append_array(tail)
				return Vector2i(read+1,tail.size())
			continue
		if write!=read:values[write]=item
		write+=1
	values.resize(write);return Vector2i(count_,0)

func _unindex_pending_item(item:Dictionary,prune_empty:bool=true)->void:
	if _pending_kinds!=null:_pending_kinds.remove(item)
	# Remove this exact old tombstone before appending the new queue member.
	# Keeping its old bucket position would change stable equal-priority order.
	var box:AABB=item.bounds
	var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>64:
		_erase_pending_identity(_large_pending,item)
		if is_same(_large_native_pending.get(item.record.uuid),item):_large_native_pending.erase(item.record.uuid)
	else:
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell:=Vector2i(x,z)
				if not _pending_index.has(cell):continue
				_erase_pending_identity(_pending_index[cell],item)
				if is_same(_pending_native_index.get(cell,EMPTY_DEMAND).get(item.record.uuid),item):_pending_native_index[cell].erase(item.record.uuid)
				if prune_empty and _pending_index[cell].is_empty():_pending_index.erase(cell);_pending_native_index.erase(cell)
	_pending_by_record_id.erase(item.record.uuid)

static func _intersects(a:AABB,b:AABB)->bool:
	return a.position.x<=b.end.x and a.end.x>=b.position.x and a.position.z<=b.end.z and a.end.z>=b.position.z

func _in_clip(clip:AABB)->Array:
	return _in_clip_catalogue(clip).values()

func _in_clip_catalogue(clip:AABB)->Dictionary:
	_index_pending()
	var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
	var candidates:Dictionary={}
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	# UUID-unique queue catalogs let native Dictionary.merge union repeated
	# cell references in their original insertion order. The final live bounds
	# test still runs once per owner. Non-canonical/aliased buckets retain the
	# original filtering-before-UUID-deduplication path below.
	if native_spatial_union_enabled and _pending_by_record_id.size()==pending_count() and _large_native_pending.size()==_large_pending.size() and (high.x-low.x+1)*(high.y-low.y+1)<=_pending_index.size():
		var buckets:Array[Dictionary]=[_large_native_pending];var canonical:=true
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var key:=Vector2i(x,z)
				if not _pending_index.has(key):continue
				var bucket:Dictionary=_pending_native_index.get(key,EMPTY_DEMAND)
				if bucket.size()!=_pending_index[key].size():canonical=false;break
				buckets.append(bucket)
			if not canonical:break
		if canonical:
			var unique:Dictionary={}
			for bucket:Dictionary in buckets:unique.merge(bucket,true)
			for item:Dictionary in unique.values():
				if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[item.record.uuid]=item
			profile.spatial_union_merges=int(profile.get("spatial_union_merges",0))+buckets.size()
			profile.spatial_script_rows=int(profile.get("spatial_script_rows",0))+unique.size()
			profile.spatial_candidate_tests=int(profile.get("spatial_candidate_tests",0))+unique.size()
			return candidates
	var tests:=0;var script_rows:=0
	for item:Dictionary in _large_pending:
		script_rows+=1
		var uuid:String=item.record.uuid
		if spatial_candidate_reuse_enabled and is_same(candidates.get(uuid),item):continue
		tests+=1
		if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[uuid]=item
	if (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size():
		for item:Dictionary in _materialize_pending_snapshot():
			script_rows+=1
			var uuid:String=item.record.uuid
			if spatial_candidate_reuse_enabled and is_same(candidates.get(uuid),item):continue
			tests+=1
			if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[uuid]=item
	else:
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):
					script_rows+=1
					var uuid:String=item.record.uuid
					# Repeated cells borrow the same immutable queue member. Only
					# reuse a successful exact test for the CURRENT winning owner;
					# another object with the same UUID must still test/replace it.
					if spatial_candidate_reuse_enabled and is_same(candidates.get(uuid),item):continue
					tests+=1
					if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[uuid]=item
	profile.spatial_candidate_tests=int(profile.get("spatial_candidate_tests",0))+tests
	profile.spatial_script_rows=int(profile.get("spatial_script_rows",0))+script_rows
	return candidates

func _has_pending_in_clip(clip:AABB)->bool:
	# Readiness needs existence only. Do not allocate/deduplicate all matches or
	# keep scanning after the first unpublished source proves it is not ready.
	_index_pending()
	var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
	for item:Dictionary in _large_pending:
		if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size():
		for item:Dictionary in _materialize_pending_snapshot():
			if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
		return false
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):
				if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
	return false

static var demand_score_pruning_enabled:=true
static var shared_support_closure_enabled:=true
static var support_set_ids_enabled:=true # Diagnostic old/new key control; same exact ordered closure.
static var filtered_demand_membership_enabled:=true
static var reuse_demand_candidate_rows_enabled:=true
static var reuse_demand_candidate_catalogue_enabled:=true
static var reuse_demand_dispatch_catalogue_enabled:=true
static var reuse_demand_membership_rows_enabled:=true
static var borrow_publication_rows_enabled:=true
const EMPTY_CANDIDATE:Array=[]

func _requeue_typed_full_strategy(demand:Dictionary)->bool:
	# A tag is saved only when the original ticket used typed full-scan. Check
	# the current bucket threshold again after requeue, not just pre/post sizes.
	if not selective_requeue_membership_enabled or not demand_membership_cache_enabled or not typed_demand_scan_enabled or not reuse_typed_demand_filter_enabled or not reuse_spatial_membership_catalogue_enabled or not filtered_demand_membership_enabled:return false
	if not incremental_pending_index_enabled or not _indexed or demand.has("group_id"):return false
	if demand.get("kind","all") not in ["building","road","structure","terrain"] or not demand.get("clip") is AABB:return false
	if _pending_by_record_id.size()!=pending_count() or _large_native_pending.size()!=_large_pending.size() or _pending_kinds==null:return false
	if _pending_kinds.owners.size()!=pending_count() or _pending_kinds.building_count!=_runtime_building_records.size():return false
	var clip:AABB=demand.clip
	if not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.z<0:return false
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	return (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size()

func _preserve_unrelated_typed_memberships(accepted:Array)->void:
	# This is membership reuse only: the original demand revision, retries,
	# collision invalidation and full candidate re-rank remain in force.
	for id:String in _demand_membership.keys():
		var cached:Dictionary=_demand_membership[id];var demand:Variant=_demands.get(id)
		if not demand is Dictionary or not cached.get("requeue_typed_full",false) or int(cached.get("registration_epoch",-1))!=_membership_registration_epoch or cached.get("requeue_native_bounds")!=native_demand_bounds_enabled or not cached.get("items") is Dictionary or not _requeue_typed_full_strategy(demand):
			_demand_membership.erase(id);continue
		var clip:AABB=demand.clip;var unaffected:=true
		for entry:Dictionary in accepted:
			var uuid:String=entry.compact_record.uuid
			var item:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
			if item.is_empty() or not item.get("bounds") is AABB or cached.items.has(uuid):unaffected=false;break
			var bounds:AABB=item.bounds
			if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<0 or bounds.size.z<0 or _intersects(clip,bounds):unaffected=false;break
		if not unaffected:_demand_membership.erase(id)
		else:profile.requeue_memberships_preserved=int(profile.get("requeue_memberships_preserved",0))+1

func _demand_membership_rows(cached:Dictionary)->Array:
	var members:Variant=cached.items
	if not members is Dictionary:return members
	if reuse_demand_membership_rows_enabled and cached.has("rows"):
		profile.demand_membership_rows_reused=int(profile.get("demand_membership_rows_reused",0))+members.size()
		return cached.rows
	var rows:Array=members.values()
	profile.demand_membership_rows_created=int(profile.get("demand_membership_rows_created",0))+rows.size()
	if reuse_demand_membership_rows_enabled:cached.rows=rows
	return rows

func _cache_demand_items(items:Array)->Variant:
	# Real queue members have one authoritative UUID owner. An ordered lookup
	# keeps their spatial order while publication removes only completed owners.
	# Diagnostic aliases retain the original array and live publication checks.
	var live:Dictionary={}
	for item:Dictionary in items:
		var uuid:String=item.record.uuid
		if live.has(uuid) or not is_same(_pending_by_record_id.get(uuid),item):return items
		live[uuid]=item
	return live

func _demanded_count()->int:
	return _demanded_by_id.size() if _demanded_snapshot_dirty else _demanded_snapshot.size()

func _refresh_demanded()->void:
	if _candidates_revision==_demand_revision:return
	var began:=Time.get_ticks_usec()
	var trace_session:RefCounted=_demand_revision_trace
	var trace_ticket:Variant=null
	if trace_session!=null:trace_ticket=trace_session.begin_refresh(_demand_revision,_candidates_revision,_priority,_priority_rank_anchor,began,_demands.size(),_demand_scope.size())
	# Scores/owners are still recomputed from live inputs. The epoch only marks
	# first membership in this refresh so stable UUIDs retain their hash slots.
	var reuse_catalogue:=reuse_demand_candidate_catalogue_enabled and reuse_demand_candidate_rows_enabled
	var candidates:Dictionary=_demand_candidate_rows if reuse_catalogue else {}
	var ordered:Array=[];var candidate_count:=0;var catalogue_inserts:=0;var catalogue_erased:=0;var catalogue_scan_rows:=0
	_demand_candidate_epoch+=1
	var epoch:=_demand_candidate_epoch
	if not reuse_demand_candidate_rows_enabled:_demand_candidate_rows.clear()
	var candidate_rows_created:=0;var candidate_rows_reused:=0
	_index_pending()
	var memberships:Dictionary={}
	# Movement changes ranks every four metres, much more often than the stable
	# ticket envelopes change. Reuse membership, but always read publication,
	# errors, support closure, scope and priority from the live queue below.
	for id:String in _demand_membership.keys():
		if not _demands.has(id):_demand_membership.erase(id)
	if demand_membership_cache_enabled:
		for id:String in _demands:
			var cached:Dictionary=_demand_membership.get(id,{})
			var demand:Dictionary=_demands[id]
			var kind:String=demand.get("kind","all")
			# Learning a building changes only building-kind membership. Support
			# closure is read live below for every kind, including cached tickets.
			if cached.get("clip")==demand.clip and cached.get("kind")==kind and cached.get("group")==demand.get("group_id","") and (kind!="building" or cached.get("buildings")==_runtime_building_records.size()):
				memberships[id]=cached.items
				profile.demand_membership_hits=int(profile.get("demand_membership_hits",0))+1
	var support_priorities:Dictionary={};var support_distances:Dictionary={};var support_visits:=0
	var support_set_priorities:Dictionary={};var support_sets_reused:=0;var kind_tests:=0
	var support_id_queries:=0;var support_array_queries:=0;var support_array_rows:=0
	var applied_support_priorities:Dictionary={};var support_promotions:=0
	var typed_scans:Dictionary=_typed_full_scan_inputs(memberships) if typed_demand_scan_enabled else {}
	var trace=preload("res://scripts/world3d/load_trace.gd")
	if trace.enabled:trace.elapsed("demand.membership_setup",began)
	var rank_started:=Time.get_ticks_usec() if trace.enabled else 0
	var input_rows:=0;var distance_evaluations:=0;var scores_reused:=0
	for id:String in _demands:
		if not _demand_scope.is_empty() and not _demand_scope.has(id):continue
		var demand:Dictionary=_demands[id]
		var kind:String=demand.get("kind","all");var grouped:bool=demand.has("group_id")
		var priority:int=int(demand.priority);var base_score:=float(priority)*1e15
		var origin:Vector3=_priority if id=="player" or demand.get("rank_from_player",false) else demand.clip.get_center()
		var candidates_for_demand:Array
		var typed_saw_published:=false
		# Spatial and typed queries already own an ordered, UUID-deduplicated
		# catalogue. Transfer it to the ticket instead of rebuilding it from its
		# values. Publication prunes by exact identity, including diagnostic aliases.
		var fresh_members:Variant=null
		if memberships.has(id):
			candidates_for_demand=_demand_membership_rows(_demand_membership[id])
		elif grouped:candidates_for_demand=_materialize_pending_snapshot()
		elif typed_scans.has(id):
			var matches:Dictionary={}
			var clip:AABB=demand.clip;var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
			for item:Dictionary in typed_scans[id]:
				if item.get("published",false):typed_saw_published=true;continue
				if flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(demand.clip,item.bounds):matches[item.record.uuid]=item
			candidates_for_demand=matches.values()
			if reuse_spatial_membership_catalogue_enabled:fresh_members=matches
		elif reuse_spatial_membership_catalogue_enabled:
			fresh_members=_in_clip_catalogue(demand.clip);candidates_for_demand=fresh_members.values()
		else:candidates_for_demand=_in_clip(demand.clip)
		var filtered:bool=filtered_demand_membership_enabled and memberships.has(id) and _demand_membership[id].get("filtered",false)
		var kind_qualified:bool=filtered or (reuse_typed_demand_filter_enabled and typed_scans.has(id))
		var eligible:Array=[]
		input_rows+=candidates_for_demand.size()
		for item:Dictionary in candidates_for_demand:
			if not kind_qualified:
				kind_tests+=1
				var excluded:bool=(grouped and item.get("group_id","")!=demand.group_id) or (kind=="building" and not str(item.get("group_id","")).begins_with("building:") and not _runtime_building_records.has(item.record.uuid)) or (kind=="road" and item.get("reference_entry",EMPTY_DEMAND).get("reason","")!="native_road") or (kind=="structure" and item.get("reference_entry",EMPTY_DEMAND).get("reason","") not in ["native_fortification","native_bridge"]) or (kind=="terrain" and item.get("reference_entry",EMPTY_DEMAND).get("reason","")!="terrain_context_global")
				if excluded:
					if fresh_members!=null and filtered_demand_membership_enabled:fresh_members.erase(item.record.uuid)
					continue
			# Typed inputs already passed the same kind predicate. Still retain
			# their eligible membership for the next refresh, before live checks.
			if filtered_demand_membership_enabled and not memberships.has(id) and fresh_members==null:eligible.append(item)
			# Publication stays live; a cached membership grants no readiness.
			if item.get("published",false):continue
			var uuid:String=item.record.uuid
			var winner:Array=candidates.get(uuid,EMPTY_CANDIDATE)
			var present:bool=not winner.is_empty() and (not reuse_catalogue or int(winner[5])==epoch)
			# Distance is nonnegative. A score already below this ticket's base
			# cannot lose; the same immutable owner/origin also cannot improve at
			# an equal or weaker priority. Support closure still runs below.
			var dominated:bool=demand_score_pruning_enabled and present and (float(winner[0])<=base_score or (is_same(winner[2],item) and winner[4]==origin and int(winner[3])<=priority))
			var score:float=0.
			if dominated:scores_reused+=1
			else:score=base_score+_distance_from(item,origin);distance_evaluations+=1
			# Numeric keys precede the borrowed item. Native lexicographic sorting
			# compares doubles without one GDScript callback per comparison, and
			# insertion rank makes equal-score order deterministic.
			if not present:
				var row:Array=winner if reuse_catalogue else _demand_candidate_rows.get(uuid,EMPTY_CANDIDATE)
				if row.is_empty():row=[score,candidate_count,item,priority,origin,epoch,""];candidate_rows_created+=1
				else:
					row[0]=score;row[1]=candidate_count;row[2]=item;row[3]=priority;row[4]=origin;row[5]=epoch;candidate_rows_reused+=1
				candidate_count+=1
				if not reuse_catalogue or winner.is_empty():candidates[uuid]=row;catalogue_inserts+=1
				if reuse_catalogue:ordered.append(row)
			elif not dominated and score<float(winner[0]):
				winner[0]=score;winner[2]=item;winner[3]=priority;winner[4]=origin
			# Learned imported buildings retain the same supporting landscape as
			# their last verified live index. This closure stays inside the allowed
			# parent ticket/scope; it never broadens demand to unrelated far props.
			if not _runtime_building_supports.has(uuid):continue
			if support_priorities.has(uuid) and int(support_priorities[uuid])<=priority:continue
			support_priorities[uuid]=priority
			# Shared support identity was resolved exactly at registration. Hashing
			# the whole immutable Array on each refresh would repeat its string walk.
			# Unregistered diagnostic owners retain the original ordered Array key.
			var support_order:Array=_runtime_support_order.get(uuid,EMPTY_CANDIDATE)
			if shared_support_closure_enabled and not support_order.is_empty():
				var support_id:int=int(_runtime_support_set_ids.get(uuid,0)) if support_set_ids_enabled else 0
				var support_key:Variant=support_id if support_id>0 else support_order
				if support_id>0:support_id_queries+=1
				else:support_array_queries+=1;support_array_rows+=support_order.size()
				var applied_set:Variant=support_set_priorities.get(support_key)
				if applied_set!=null and int(applied_set)<=priority:support_sets_reused+=1;continue
				if support_id>0:support_id_queries+=1
				else:support_array_queries+=1;support_array_rows+=support_order.size()
				support_set_priorities[support_key]=priority
			for support:String in _runtime_building_supports[uuid]:
				support_visits+=1
				var support_priority:int=priority-1
				# Several buildings share the same landscape. Within this synchronous
				# refresh, its owner/publication/origin stay fixed and winning scores
				# only improve. Repeat a promotion only for a stronger parent ticket.
				if support_promotion_dedup_enabled:
					var applied:Variant=applied_support_priorities.get(support)
					if applied!=null and int(applied)<=support_priority:continue
					applied_support_priorities[support]=support_priority
				support_promotions+=1
				var dependency:Dictionary=_pending_by_record_id.get(support,EMPTY_DEMAND)
				if dependency.is_empty() or dependency.get("published",false):continue
				if not support_distances.has(support):support_distances[support]=_distance_from(dependency,_priority)
				var support_score:float=float(support_priority)*1e15+float(support_distances[support])
				var previous:Array=candidates.get(support,EMPTY_CANDIDATE)
				var support_present:bool=not previous.is_empty() and (not reuse_catalogue or int(previous[5])==epoch)
				if not support_present:
					var row:Array=previous if reuse_catalogue else _demand_candidate_rows.get(support,EMPTY_CANDIDATE)
					if row.is_empty():row=[support_score,candidate_count,dependency,support_priority,_priority,epoch,""];candidate_rows_created+=1
					else:
						row[0]=support_score;row[1]=candidate_count;row[2]=dependency;row[3]=support_priority;row[4]=_priority;row[5]=epoch;candidate_rows_reused+=1
					candidate_count+=1
					if not reuse_catalogue or previous.is_empty():candidates[support]=row;catalogue_inserts+=1
					if reuse_catalogue:ordered.append(row)
				elif support_score<float(previous[0]):
					previous[0]=support_score;previous[2]=dependency;previous[3]=support_priority;previous[4]=_priority
		if demand_membership_cache_enabled and not memberships.has(id):
			_demand_membership[id]={"clip":demand.clip,"kind":kind,"group":demand.get("group_id",""),"buildings":_runtime_building_records.size(),"items":fresh_members if fresh_members!=null else _cache_demand_items(eligible if filtered_demand_membership_enabled else candidates_for_demand),"filtered":filtered_demand_membership_enabled,"requeue_typed_full":typed_scans.has(id) and not typed_saw_published and _requeue_typed_full_strategy(demand),"requeue_native_bounds":native_demand_bounds_enabled,"registration_epoch":_membership_registration_epoch}
			if fresh_members!=null:profile.demand_catalogue_rows_reused=int(profile.get("demand_catalogue_rows_reused",0))+fresh_members.size()
			profile.demand_membership_misses=int(profile.get("demand_membership_misses",0))+1
	profile.demand_input_rows=int(profile.get("demand_input_rows",0))+input_rows
	profile.demand_kind_tests=int(profile.get("demand_kind_tests",0))+kind_tests
	profile.support_sets_reused=int(profile.get("support_sets_reused",0))+support_sets_reused
	profile.support_set_id_queries=int(profile.get("support_set_id_queries",0))+support_id_queries
	profile.support_array_key_queries=int(profile.get("support_array_key_queries",0))+support_array_queries
	# Key payload rows are deterministic work counters, not native hash timing.
	profile.support_array_key_rows=int(profile.get("support_array_key_rows",0))+support_array_rows
	profile.demand_distance_evaluations=int(profile.get("demand_distance_evaluations",0))+distance_evaluations
	profile.demand_scores_reused=int(profile.get("demand_scores_reused",0))+scores_reused
	profile.support_candidate_visits=int(profile.get("support_candidate_visits",0))+support_visits
	profile.support_promotions=int(profile.get("support_promotions",0))+support_promotions
	if reuse_catalogue:
		# Growth/rank-only refreshes need no retirement scan. Equal counts are
		# sufficient here because every newly encountered UUID was inserted and
		# counted once; any old unseen UUID makes the catalogue strictly larger.
		if candidates.size()!=candidate_count:
			if candidate_count==0:
				# Complete withdrawal needs no per-row epoch checks in GDScript.
				catalogue_erased=candidates.size();candidates.clear()
			else:
				catalogue_scan_rows=candidates.size()
				for uuid:String in candidates.keys():
					if int(candidates[uuid][5])!=epoch:candidates.erase(uuid);catalogue_erased+=1
	else:ordered=candidates.values()
	profile.demand_candidate_catalogue_inserts=int(profile.get("demand_candidate_catalogue_inserts",0))+catalogue_inserts
	profile.demand_candidate_catalogue_erased=int(profile.get("demand_candidate_catalogue_erased",0))+catalogue_erased
	profile.demand_candidate_catalogue_scan_rows=int(profile.get("demand_candidate_catalogue_scan_rows",0))+catalogue_scan_rows
	# Only live rows survive. The cache table is lookup-only; ordered/row[1]
	# carry this refresh's first-seen order. Recompute all live winner fields.
	# No item owns its row; publication erases it before releasing the source.
	_demand_candidate_rows=candidates if reuse_demand_candidate_rows_enabled else {}
	profile.demand_candidate_rows_created=int(profile.get("demand_candidate_rows_created",0))+candidate_rows_created
	profile.demand_candidate_rows_reused=int(profile.get("demand_candidate_rows_reused",0))+candidate_rows_reused
	if trace.enabled:trace.elapsed("demand.collect_candidates",rank_started,{"input_rows":input_rows,"candidates":ordered.size(),"support_visits":support_visits,"support_promotions":support_promotions})
	var sort_started:=Time.get_ticks_usec() if trace.enabled else 0
	if native_demand_order_enabled:ordered.sort()
	else:ordered.sort_custom(func(a,b):return a[0]<b[0] if a[0]!=b[0] else a[1]<b[1])
	if trace.enabled:trace.elapsed("demand.sort_candidates",sort_started,{"candidates":ordered.size()})
	if trace.enabled:trace.elapsed("demand.rank_candidates",rank_started,{"candidates":ordered.size()})
	var commit_started:=Time.get_ticks_usec() if trace.enabled else 0
	if _can_reuse_demand_dispatch(ordered):
		# The existing maps/path arrays already have these exact owners, ranks,
		# paths and priorities. Keep their allocations and any valid lazy view.
		# Retry/publication cursors retain the same refresh boundary as before.
		_publication_queues.clear();_dispatch_capacity=[]
		_dispatch_revision=_demand_revision;_candidates_revision=_demand_revision
		profile.demand_dispatch_catalogue_rows_reused=int(profile.get("demand_dispatch_catalogue_rows_reused",0))+ordered.size()
		if trace.enabled:trace.elapsed("demand.rebuild_dispatch_catalog",commit_started,{"candidates":ordered.size(),"reused":true})
		_record_demand_refresh(began,trace_session,trace_ticket)
		return
	_demanded=[]
	_demanded_by_id.clear()
	_demanded_by_path.clear()
	var metadata_erased:=0
	if reuse_demand_metadata_enabled:
		# These two maps are lookup-only. Preserve allocations for live UUIDs;
		# the ordered item/path catalogs above still follow the new sorted order.
		for uuid:String in _demanded_rank.keys():
			if not candidates.has(uuid):_demanded_rank.erase(uuid);_demanded_priority.erase(uuid);metadata_erased+=2
	else:
		metadata_erased=_demanded_rank.size()+_demanded_priority.size()
		_demanded_rank.clear();_demanded_priority.clear()
	profile.demand_metadata_erased=int(profile.get("demand_metadata_erased",0))+metadata_erased
	profile.demand_metadata_created=int(profile.get("demand_metadata_created",0))+2*(ordered.size()-_demanded_rank.size())
	_path_first.clear();_publication_queues.clear();_dispatch_paths.clear()
	var demand_rank:=0
	for row:Array in ordered:
		var item:Dictionary=row[2]
		var uuid:String=item.record.uuid;var path:String=item.path
		row[6]=path # Last committed path; detects an in-place owner path change.
		_demanded_rank[uuid]=demand_rank;demand_rank+=1
		_demanded_priority[uuid]=row[3]
		if not lazy_demand_snapshot_enabled:_demanded_snapshot.append(item)
		_demanded_by_id[uuid]=item
		var siblings:Array=_demanded_by_path.get(path,EMPTY_CANDIDATE)
		if siblings.is_empty():siblings=[];_demanded_by_path[path]=siblings
		if not _path_first.has(path) and not instance_errors.has(uuid):
			_path_first[path]=item;_dispatch_paths.append(path)
		siblings.append(item)
	# The ordered UUID catalogue already owns every demanded item. Normal
	# scheduling/counts use it or the path catalogue; only an explicit aggregate
	# traversal needs another ordered Array. Never mutate a borrowed old Array.
	_demanded_snapshot_dirty=lazy_demand_snapshot_enabled and not ordered.is_empty()
	# These count eager full snapshots, separately from the getter's existing
	# materialization counters. Empty reset arrays are not full snapshots.
	profile.demand_snapshot_refresh_materializations=int(profile.get("demand_snapshot_refresh_materializations",0))+int(not lazy_demand_snapshot_enabled and not ordered.is_empty())
	profile.demand_snapshot_refresh_materialized_rows=int(profile.get("demand_snapshot_refresh_materialized_rows",0))+(0 if lazy_demand_snapshot_enabled else ordered.size())
	# ordered already has the exact live ranks; no second whole-path sort in
	# the much smaller dispatch slice is needed after rebuilding demands.
	_dispatch_revision=_demand_revision;_dispatch_capacity=[]
	_candidates_revision=_demand_revision
	_demand_dispatch_catalogue_valid=true
	_demand_dispatch_catalogue_had_errors=not instance_errors.is_empty() or not path_errors.is_empty()
	profile.demand_dispatch_catalogue_rows_written=int(profile.get("demand_dispatch_catalogue_rows_written",0))+ordered.size()
	if trace.enabled:trace.elapsed("demand.rebuild_dispatch_catalog",commit_started,{"candidates":ordered.size()})
	_record_demand_refresh(began,trace_session,trace_ticket)

func _can_reuse_demand_dispatch(ordered:Array)->bool:
	if not reuse_demand_dispatch_catalogue_enabled or not _demand_dispatch_catalogue_valid or _demand_dispatch_catalogue_had_errors or not instance_errors.is_empty() or not path_errors.is_empty():return false
	if ordered.size()!=_demanded_by_id.size() or ordered.size()!=_demanded_rank.size() or ordered.size()!=_demanded_priority.size():return false
	var same:=true;var checked:=0
	for i:int in ordered.size():
		var row:Array=ordered[i];var item:Dictionary=row[2];var uuid:String=item.record.uuid
		checked+=1
		if _demanded_rank.get(uuid,-1)!=i or _demanded_priority.get(uuid)!=row[3] or not is_same(_demanded_by_id.get(uuid),item) or row[6]!=item.path:
			same=false;break
	profile.demand_dispatch_catalogue_guard_rows=int(profile.get("demand_dispatch_catalogue_guard_rows",0))+checked
	return same

func _record_demand_refresh(began:int,trace_session:RefCounted=null,trace_ticket:Variant=null)->void:
	var elapsed:=Time.get_ticks_usec()-began
	profile.demand_refresh_us=int(profile.get("demand_refresh_us",0))+elapsed
	profile.max_demand_refresh_us=maxi(int(profile.get("max_demand_refresh_us",0)),elapsed)
	profile.demand_refreshes=int(profile.get("demand_refreshes",0))+1
	if trace_session!=null:trace_session.end_refresh(trace_ticket,_demand_revision,pending_count(),_demanded_count(),profile)

func _typed_full_scan_inputs(cached:Dictionary={})->Dictionary:
	# Kind and source bounds do not change as the player moves. Partition at a
	# catalog change, not every demand refresh. Publication remains a live flag.
	var tickets:Dictionary={}
	for id:String in _demands:
		if cached.has(id):continue
		if not _demand_scope.is_empty() and not _demand_scope.has(id):continue
		var demand:Dictionary=_demands[id];var kind:String=demand.get("kind","all")
		if demand.has("group_id") or kind not in ["building","road","structure","terrain"]:continue
		var clip:AABB=demand.clip
		var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
		if (high.x-low.x+1)*(high.y-low.y+1)<=_pending_index.size():continue
		tickets[id]=kind
	if tickets.is_empty():return {}
	# The real queue already maintains exact UUID and large-owner membership.
	# Requeue changes only its appended owners; it must not reclassify the town.
	# Aliased/diagnostic arrays retain the original filter-before-dedup path.
	if incremental_pending_index_enabled and _pending_by_record_id.size()==pending_count() and _large_native_pending.size()==_large_pending.size():
		if _pending_kinds==null or _pending_kinds.owners.size()!=pending_count() or _pending_kinds.building_count!=_runtime_building_records.size():
			_pending_kinds=preload("res://scripts/world3d/pending_kind_catalogue.gd").new()
			for item:Dictionary in _materialize_pending_snapshot():_pending_kinds.add(item,_large_native_pending.has(item.record.uuid),_runtime_building_records)
			_pending_kinds.building_count=_runtime_building_records.size()
			profile.typed_partition_builds=int(profile.get("typed_partition_builds",0))+1
			profile.typed_full_scan_prefilter_tests=int(profile.get("typed_full_scan_prefilter_tests",0))+pending_count()
		var count:=0;var by_kind:Dictionary={}
		for id:String in tickets:
			var kind:String=tickets[id]
			if not by_kind.has(kind):by_kind[kind]=_pending_kinds.items(kind)
			tickets[id]=by_kind[kind];count+=tickets[id].size()
		profile.typed_full_scan_tickets=int(profile.get("typed_full_scan_tickets",0))+tickets.size()
		profile.typed_full_scan_candidates=int(profile.get("typed_full_scan_candidates",0))+count
		profile.typed_full_scan_unfiltered=int(profile.get("typed_full_scan_unfiltered",0))+tickets.size()*(_large_pending.size()+pending_count())
		return tickets
	if _typed_pending_buildings!=_runtime_building_records.size():
		_typed_pending={"building":[],"road":[],"structure":[],"terrain":[]}
		# Preserve large-first ordering and exact intersection before UUID dedup.
		for collection:Array in [_large_pending,_materialize_pending_snapshot()]:
			for item:Dictionary in collection:
				if str(item.get("group_id","")).begins_with("building:") or _runtime_building_records.has(item.record.uuid):_typed_pending.building.append(item)
				var reason:Variant=item.get("reference_entry",EMPTY_DEMAND).get("reason","")
				if reason=="native_road":_typed_pending.road.append(item)
				if reason in ["native_fortification","native_bridge"]:_typed_pending.structure.append(item)
				if reason=="terrain_context_global":_typed_pending.terrain.append(item)
		_typed_pending_buildings=_runtime_building_records.size()
		profile.typed_partition_builds=int(profile.get("typed_partition_builds",0))+1
		profile.typed_full_scan_prefilter_tests=int(profile.get("typed_full_scan_prefilter_tests",0))+_large_pending.size()+pending_count()
	var count:=0
	for id:String in tickets:
		tickets[id]=_typed_pending[tickets[id]];count+=tickets[id].size()
	profile.typed_full_scan_tickets=int(profile.get("typed_full_scan_tickets",0))+tickets.size()
	profile.typed_full_scan_candidates=int(profile.get("typed_full_scan_candidates",0))+count
	profile.typed_full_scan_unfiltered=int(profile.get("typed_full_scan_unfiltered",0))+tickets.size()*(_large_pending.size()+pending_count())
	return tickets

func _support_order_hash(order:Array)->int:
	return order.hash()

func _release_support_set(id:int)->void:
	if id==0:return
	var entry:Dictionary=_support_set_interns[id]
	entry.users-=1
	if int(entry.users)>0:return
	var bucket:Array=_support_set_buckets[entry.hash]
	bucket.erase(id)
	if bucket.is_empty():_support_set_buckets.erase(entry.hash)
	_support_set_interns.erase(id)

func _intern_runtime_support_order(uuid:String,order:Array)->void:
	var previous:int=int(_runtime_support_set_ids.get(uuid,0))
	if order.is_empty():
		_runtime_support_set_ids.erase(uuid);_runtime_support_order[uuid]=order
		_release_support_set(previous);return
	var hash_:int=_support_order_hash(order)
	var bucket:Array=_support_set_buckets.get(hash_,EMPTY_CANDIDATE)
	var selected:=0
	for id:int in bucket:
		if _support_set_interns[id].order==order:selected=id;break
	if selected==0:
		selected=_next_support_set_id;_next_support_set_id+=1
		_support_set_interns[selected]={"order":order,"hash":hash_,"users":0}
		if bucket.is_empty():bucket=[];_support_set_buckets[hash_]=bucket
		bucket.append(selected)
	# Preserve each registration's immutable order for the diagnostic Array-key
	# control; only the shared integer identity enters the normal refresh path.
	_runtime_support_order[uuid]=order
	if selected==previous:return
	_support_set_interns[selected].users+=1
	_runtime_support_set_ids[uuid]=selected
	_release_support_set(previous)

func _clear_runtime_support_sets()->void:
	_runtime_support_order.clear();_runtime_support_set_ids.clear()
	_support_set_interns.clear();_support_set_buckets.clear();_next_support_set_id=1

func support_set_snapshot()->Dictionary:
	# Explicit diagnostic snapshot only: no resource/spec references, no per-frame
	# histogram upkeep. Registration count is distinct from refresh query traffic.
	var unique_lengths:Dictionary={};var registration_lengths:Dictionary={}
	var unique_rows:=0;var registration_rows:=0;var maximum:=0
	var empty_count:=_runtime_support_order.size()-_runtime_support_set_ids.size()
	if empty_count>0:registration_lengths["0"]=empty_count
	for entry:Dictionary in _support_set_interns.values():
		var count_:int=entry.order.size();var key:=str(count_);var users:int=entry.users
		unique_lengths[key]=int(unique_lengths.get(key,0))+1
		registration_lengths[key]=int(registration_lengths.get(key,0))+users
		unique_rows+=count_;registration_rows+=count_*users;maximum=maxi(maximum,count_)
	return {"ids_enabled":support_set_ids_enabled,"registered_buildings":_runtime_support_order.size(),"unique_nonempty_sets":_support_set_interns.size(),"unique_set_length_histogram":unique_lengths,"registration_set_length_histogram":registration_lengths,"unique_support_rows":unique_rows,"registered_support_rows":registration_rows,"max_set_length":maximum}

func register_runtime_building(uuid:String,bounds:AABB,supports:Dictionary)->void:
	var order:Array=supports.keys()
	# Dictionary equality ignores insertion order; closure score ties do not.
	if _runtime_building_records.get(uuid)==bounds and _runtime_building_supports.get(uuid,{})==supports and _runtime_support_order.get(uuid,EMPTY_CANDIDATE)==order:return
	_membership_registration_epoch+=1
	var previous_buildings:=_runtime_building_records.size()
	_runtime_building_records[uuid]=bounds;_runtime_building_supports[uuid]=supports.duplicate()
	order.make_read_only();_intern_runtime_support_order(uuid,order)
	# Registration is a live membership delta, not a reason to rebuild every
	# ticket. Advance current membership catalogues by appending this building
	# when it intersects their clip; a later publication/movement refresh still
	# revalidates live flags and support closure.
	var pending_item:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
	if _indexed and not _covered_loading_ready():
		var learned_buildings:=_runtime_building_records.size()
		if learned_buildings!=previous_buildings:
			if _typed_pending_buildings==previous_buildings:_typed_pending_buildings=learned_buildings
			if _pending_kinds!=null and _pending_kinds.building_count==previous_buildings:_pending_kinds.building_count=learned_buildings
			for cached:Dictionary in _demand_membership.values():
				if cached.get("buildings")!=previous_buildings:continue
				var cached_kind:String=str(cached.get("kind",""))
				if cached_kind!="building" and cached_kind!="all":continue
				cached.buildings=learned_buildings
				if pending_item.is_empty() or pending_item.get("published",false):continue
				if not cached.get("clip") is AABB or not cached.clip.intersects(pending_item.bounds):continue
				var group:String=str(cached.get("group",""))
				if not group.is_empty() and group!=str(pending_item.get("group_id","")):continue
				var items:Variant=cached.get("items")
				if not items is Array:continue
				if not items.has(pending_item):items.append(pending_item)
		profile.runtime_registration_refresh_skips=int(profile.get("runtime_registration_refresh_skips",0))+1
		return
	# Initial covered load keeps the original live-pending invalidation. Only
	# post-reveal registration uses the bounded incremental catalogue delta.
	if _indexed and (pending_item.is_empty() or pending_item.get("published",false)):
		var learned_buildings:=_runtime_building_records.size()
		if learned_buildings!=previous_buildings:
			if _typed_pending_buildings==previous_buildings:_typed_pending_buildings=learned_buildings
			if _pending_kinds!=null and _pending_kinds.building_count==previous_buildings:_pending_kinds.building_count=learned_buildings
			for cached:Dictionary in _demand_membership.values():
				if cached.get("kind")=="building" and cached.get("buildings")==previous_buildings:cached.buildings=learned_buildings
		profile.runtime_registration_refresh_skips=int(profile.get("runtime_registration_refresh_skips",0))+1
		return
	_demand_revision+=1;set_process(_active)
	if _demand_revision_trace!=null:_demand_revision_trace.change("register_building",uuid,null,bounds,_demand_revision)

func _runtime_supports_ready(uuid:String)->bool:
	var supports:Dictionary=_runtime_building_supports.get(uuid,EMPTY_DEMAND)
	if supports.is_empty():return true
	_index_pending()
	for id:String in supports:
		var item:Dictionary=_pending_by_record_id.get(id,EMPTY_DEMAND)
		if item.is_empty() or item.get("published",false):continue
		if instance_errors.has(id) or path_errors.has(item.path):_instance_failed(uuid,"建筑支撑地形准备失败："+id)
		return false
	return true

func ensure_geometry(clip:AABB,id:String="navigation")->bool:
	var priority:=mini(-1,int(_demands.get(id,{}).get("priority",-1)))
	var requested:=_moving_demand_envelope(id,clip,priority) if id in ["manual_traversal","player_collision"] else clip
	set_demand(id,requested,priority)
	# The envelope only stabilizes preparation membership. Readiness remains the
	# exact current footprint, including new edges while a worker is in flight.
	return not _has_pending_in_clip(clip)

func geometry_published(clip:AABB)->bool:
	# A read-only narrower gate must not shrink/rebuild its owner's wider ticket.
	return not _has_pending_in_clip(clip)

func ensure_collision(clip:AABB,id:String="player_collision")->bool:
	var began:=Time.get_ticks_usec() if collision_query_profile_enabled else 0
	var ready:=_ensure_collision(clip,id)
	profile.collision_guard_calls=int(profile.get("collision_guard_calls",0))+1
	if collision_query_profile_enabled:
		var elapsed:=Time.get_ticks_usec()-began
		profile.collision_guard_us=int(profile.get("collision_guard_us",0))+elapsed
		profile.collision_guard_max_us=maxi(int(profile.get("collision_guard_max_us",0)),elapsed)
	profile.collision_query_cache_enabled=collision_query_cache_enabled
	return ready

func _ensure_collision(clip:AABB,id:String)->bool:
	# Geometry publication remains demanded for visuals and unsupported records.
	# Only exact, verified ordinary reference instances can substitute collision
	# coverage while their visuals are pending; empty Store clips prove nothing.
	if not collision_first_enabled:return ensure_geometry(clip,id)
	var priority:=mini(-1,int(_demands.get(id,{}).get("priority",-1)))
	var moving:=id in ["manual_traversal","player_collision"]
	var requested:=_moving_demand_envelope(id,clip,priority) if moving else clip
	set_demand(id,requested,priority)
	var began:=Time.get_ticks_usec() if collision_query_profile_enabled else 0
	var remaining:=_collision_in_clip(clip,id,"exact") if collision_query_cache_enabled else _in_clip(clip)
	if not _demand_scope.is_empty() and not _demand_scope.has(id):_release_collision_request(id);return remaining.is_empty()
	# Releasing the entry-safety ticket must not remove unseen camera colliders
	# while only the player's own visual footprint has finished publishing.
	# Hold a stable margin around movement demand, but never widen readiness.
	var held:Array=remaining
	if moving:
		var hold_clip:=requested.grow(COLLISION_CAMERA_HOLD_M)
		held=_collision_in_clip(hold_clip,id,"held") if collision_query_cache_enabled else _in_clip(hold_clip)
	if collision_query_profile_enabled:profile.collision_candidate_us=int(profile.get("collision_candidate_us",0))+Time.get_ticks_usec()-began
	var service:=_collision_loader(true)
	if service==null:return remaining.is_empty()
	var exact_entries:Array=[];var entries:Array=[];var selected:Dictionary={};var needs_visual:=false
	for item:Dictionary in remaining:
		if not _collision_entry_supported(item):
			needs_visual=true;continue
		exact_entries.append(item.reference_entry);entries.append(item.reference_entry);selected[item.record.uuid]=true
	for item:Dictionary in held:
		if not selected.has(item.record.uuid) and _collision_entry_supported(item):entries.append(item.reference_entry);selected[item.record.uuid]=true
	if entries.is_empty():_release_collision_request(id);return remaining.is_empty()
	if id=="entry_safety":entries=_prioritize_collision_entries(entries,_collision_core_priority_ids)
	_collision_request_ids[id]=true
	began=Time.get_ticks_usec() if collision_query_profile_enabled else 0
	var admitted:=_request_collision_entries(service,entries,priority,id)
	if collision_query_profile_enabled:profile.collision_request_us=int(profile.get("collision_request_us",0))+Time.get_ticks_usec()-began
	if not admitted:return remaining.is_empty()
	if remaining.is_empty():return true
	began=Time.get_ticks_usec() if collision_query_profile_enabled else 0
	var coverage:Dictionary=service.coverage(exact_entries)
	if collision_query_profile_enabled:profile.collision_coverage_us=int(profile.get("collision_coverage_us",0))+Time.get_ticks_usec()-began
	return not needs_visual and coverage.get("ok",false)

func _invalidate_collision_queries()->void:
	_collision_queries.clear()
	_collision_pending_snapshot=_pending_snapshot;_collision_pending_count=pending_count()

func _collision_query_slot(id:String)->Dictionary:
	# Publication keeps its cheap old spatial buckets (published aliases are
	# filtered live). An external pending replacement/append instead rebuilds
	# those buckets, so a newly added record cannot hide behind a cached query.
	if not is_same(_collision_pending_snapshot,_pending_snapshot) or _collision_pending_count!=pending_count():
		_indexed=false;_pending_index.clear();_large_pending.clear();_pending_native_index.clear();_large_native_pending.clear()
		_invalidate_collision_queries()
	if not _collision_queries.has(id):
		if _collision_queries.size()>=COLLISION_QUERY_CACHE_LIMIT:_collision_queries.erase(_collision_queries.keys()[0])
		_collision_queries[id]={}
	return _collision_queries[id]

func _collision_in_clip(clip:AABB,id:String,kind:String)->Array:
	var slot:=_collision_query_slot(id)
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	var cached:Dictionary=slot.get(kind,{})
	if cached.get("low")!=low or cached.get("high")!=high:
		_index_pending()
		var candidates:Dictionary={}
		# Match _in_clip's ordering exactly, including large objects and the
		# sparse-directory whole-array fallback. Cache broad bucket membership;
		# the moving footprint and published flags are always evaluated below.
		for item:Dictionary in _large_pending:candidates[item.record.uuid]=item
		if (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size():
			for item:Dictionary in _materialize_pending_snapshot():candidates[item.record.uuid]=item
		else:
			for z in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):candidates[item.record.uuid]=item
		cached={"low":low,"high":high,"items":candidates.values()};slot[kind]=cached
		profile.collision_candidate_builds=int(profile.get("collision_candidate_builds",0))+1
	else:profile.collision_candidate_hits=int(profile.get("collision_candidate_hits",0))+1
	var result:Array=[]
	for item:Dictionary in cached.items:
		if not item.get("published",false) and _intersects(clip,item.bounds):result.append(item)
	return result

func _request_collision_entries(service:Node,entries:Array,priority:int,id:String)->bool:
	if not collision_query_cache_enabled:
		_collision_queries.erase(id)
		profile.collision_request_submissions=int(profile.get("collision_request_submissions",0))+1
		var legacy:Dictionary=service.request(entries,priority,id)
		return legacy.get("ok",false)
	# Only an issued, deeply sealed catalog may bypass repeated request snapshot
	# construction. The service still checks that exact proof and source context
	# every time; coverage still verifies current entries/bodies on every call.
	# Mutable/test descriptors keep the original request validation path.
	var reusable:bool=collision_query_cache_enabled and _reference_proof!=null and _reference_index.is_read_only() and service.has_method("matches_context") and service.matches_context(_reference_index,_reference_map_path,_reference_root,_reference_proof)
	var slot:Dictionary=_collision_query_slot(id) if collision_query_cache_enabled else {}
	var previous:Dictionary=slot.get("ticket",{})
	var same:bool=reusable and previous.get("service_id")==service.get_instance_id() and previous.get("priority")==priority and previous.get("entries",[]).size()==entries.size()
	for i in entries.size():
		var entry:Dictionary=entries[i]
		var record:Variant=entry.get("compact_record")
		if not record is Dictionary or not record.is_read_only():reusable=false;same=false;break
		if not same:continue
		var old:Dictionary=previous.entries[i]
		# Compact source trees are immutable; compare their identity, not every
		# nested author value. The mutable wrapper's full validated identity is
		# compared by value, including pose bounds and source path/index changes.
		if not is_same(record,old.compact_record) or entry.get("record_index")!=old.record_index or entry.get("bounds")!=old.bounds or entry.get("group_id","")!=old.group_id or entry.get("asset_path","")!=old.asset_path:same=false
	if same:
		profile.collision_request_reuses=int(profile.get("collision_request_reuses",0))+1
		return true
	profile.collision_request_submissions=int(profile.get("collision_request_submissions",0))+1
	var admitted:Dictionary=service.request(entries,priority,id)
	slot.erase("ticket")
	if not admitted.get("ok",false):return false
	if reusable:
		var snapshots:Array=[]
		for entry:Dictionary in entries:
			snapshots.append({"compact_record":entry.compact_record,"record_index":entry.get("record_index"),"bounds":entry.get("bounds"),"group_id":entry.get("group_id",""),"asset_path":entry.get("asset_path","")})
		slot.ticket={"service_id":service.get_instance_id(),"priority":priority,"entries":snapshots}
	return true

static func _collision_entry_supported(item:Dictionary)->bool:
	return not item.get("native_reference",false) and str(item.get("group_id","")).is_empty() and item.has("reference_entry") and not str(item.reference_entry.get("asset_path","")).is_empty()

func _moving_demand_envelope(id:String,clip:AABB,priority:int)->AABB:
	if not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.z<0:return clip
	var previous:Dictionary=_demands.get(id,{})
	if previous.get("clip") is AABB and previous.get("priority")==priority and previous.get("kind")=="all" and not previous.has("group_id"):
		var held:AABB=previous.clip
		if held.position.x<=clip.position.x and held.end.x>=clip.end.x and held.position.z<=clip.position.z and held.end.z>=clip.end.z:
			profile.moving_demand_reuses=int(profile.get("moving_demand_reuses",0))+1
			return held
	profile.moving_demand_updates=int(profile.get("moving_demand_updates",0))+1
	# Membership and ranking already use XZ only. Height/jump noise must not
	# invalidate the entire town demand set. Do not snap inward at cell edges.
	return AABB(Vector3(clip.position.x-MOVING_DEMAND_HALO_M,0,clip.position.z-MOVING_DEMAND_HALO_M),Vector3(clip.size.x+2*MOVING_DEMAND_HALO_M,1,clip.size.z+2*MOVING_DEMAND_HALO_M))

func prioritize(position:Vector3)->void:
	# The membership tickets below already invalidate on chunk changes. Sorting
	# every remaining town object for centimetres of movement only changes tie
	# order, and used to invalidate preparation plans on every player frame.
	# Safety/explicit geometry demands retain their exact independent revisions.
	var flat_position:=Vector3(position.x,0,position.z)
	# Four metres made every return frame re-rank the whole town while the
	# chunk-aligned demand clips stayed unchanged. A 32m anchor matches the
	# demand cell cadence and caps whole-town refreshes without changing
	# demand membership; nearest local work remains chunk-driven.
	if not _priority_rank_anchor is Vector3 or _priority_rank_anchor.distance_squared_to(flat_position)>=1024.:
		var previous:Variant=_priority_rank_anchor if _demand_revision_trace!=null else null
		_priority_rank_anchor=flat_position
		_demand_revision+=1
		if _demand_revision_trace!=null:_demand_revision_trace.change("priority_anchor","",previous,flat_position,_demand_revision)
		set_process(_active)
	_priority=position
	# A chunk-aligned ticket is stable while walking inside one cell. Nothing
	# outside live tickets is parsed just because the queue still has entries.
	var cell:=Stream.chunk_key(position)
	var center:=Vector3((cell.x+.5)*Stream.CHUNK_M,0,(cell.y+.5)*Stream.CHUNK_M)
	set_demand("player",AABB(center-Vector3(128,100000,128),Vector3(256,200000,256)),0)
	# Preserve the existing long building view as a lower priority visual demand.
	# Stream still controls collision by its short physical residency ring.
	if not _reference_index.is_empty():set_demand("building_render",AABB(center-Vector3(1000,100000,1000),Vector3(2000,200000,2000)),10,"building")
	if not _reference_index.is_empty():
		# Match the existing landscape draw cells. This is a background visual
		# demand only; Stream continues to attach physics within its short ring.
		var radius:int=Stream.BUILDING_RENDER_RADIUS
		var corner:=Vector3((cell.x-radius)*Stream.CHUNK_M,-100000,(cell.y-radius)*Stream.CHUNK_M)
		var width:float=(2*radius+1)*Stream.CHUNK_M
		set_demand("road_render",AABB(corner,Vector3(width,200000,width)),10,"road")
		set_demand("structure_render",AABB(corner,Vector3(width,200000,width)),10,"structure")
		# Cold entry initially includes global terrain. After retirement its
		# compact rows need the same far draw coverage as their live specs.
		set_demand("terrain_render",AABB(corner,Vector3(width,200000,width)),10,"terrain")

func _reference_requests(path:String)->Array:
	var requests:Array=[];var ids:Dictionary={};var groups:Dictionary={}
	var road_batch:=path.begins_with("reference:road_batch:")
	var priority:=_path_priority(path);var selected_bytes:=0
	for item:Dictionary in _demanded_by_path.get(path,[]):
		if instance_errors.has(item.record.uuid) or not item.has("reference_entry") or item.get("reference_prepared",false):continue
		var entry:Dictionary=item.reference_entry
		if road_batch:
			# A critical local solid must not wait for lower-priority distant roads.
			if int(_demanded_priority.get(str(item.record.uuid),2147483647))>priority:continue
			var bytes:=int(entry.get("memory_bytes",65536))
			# Large legal roads still run alone under their complete old estimate.
			if not requests.is_empty() and selected_bytes+bytes>ROAD_REFERENCE_BATCH_BYTES:continue
			selected_bytes+=bytes
		if not str(entry.get("group_id","")).is_empty():
			if groups.has(entry.group_id):continue
			groups[entry.group_id]=true
			# Cancelled staging retries the complete immutable owner group. An
			# ownership group is never published in partially constructed pieces.
			var group:Dictionary=_reference_index.groups[entry.group_id]
			for at in group.members:
				if ids.has(at):continue
				var row:Dictionary=_reference_index.rows[at]
				requests.append({"record_index":at,"compact_record":_reference_index.extras.rmmo_records[at],"bounds":group.bounds,"group_id":row.group_id,"asset_path":row.asset_path,"memory_bytes":row.memory_bytes});ids[at]=true
		else:
			if not ids.has(entry.record_index):requests.append(entry);ids[entry.record_index]=true
	return requests

func _job_publication_ids(path:String,requests:Array)->Array:
	var result:Array=[]
	if path.begins_with("reference:road_batch:"):
		for entry:Dictionary in requests:result.append(str(entry.compact_record.uuid))
	else:
		for item:Dictionary in _demanded_by_path.get(path,[]):
			if not instance_errors.has(item.record.uuid):result.append(str(item.record.uuid))
	return result

func _geometry_consumers(path:String)->Array:
	# Include off-screen/future instances from the immutable directory, not only
	# the demanded chunk. Current hydrated records override their compact form.
	# Called at a dispatch attempt and once at joined acceptance, never by each
	# published instance or the steady gameplay collision query.
	profile.geometry_census_calls=int(profile.get("geometry_census_calls",0))+1
	var rows:Dictionary={}
	for row:Dictionary in _reference_index.get("rows",[]):
		if row.get("asset_path","")!=path:continue
		var at:int=int(row.get("order",-1));var compact:Array=_reference_index.get("extras",{}).get("rmmo_records",[])
		if at<0 or at>=compact.size():return [{"mode":CollisionGeometry.ALL}]
		var record:Dictionary=compact[at]
		rows[str(record.uuid)]=CollisionGeometry.consumer(record)
		if rows.size()>CollisionGeometry.MAX_CONSUMERS:return [{"mode":CollisionGeometry.ALL}]
	if is_instance_valid(_map):
		for record:Dictionary in _map.get_meta("extras",{}).get("rmmo_records",[]):
			if record.get("asset_path","")!=path:continue
			# Preserve a directory definition identity for reuse proofs. Complete
			# record policy itself is authoritative, including a stronger override.
			var key:String=str(record.get("uuid",""));var previous:Dictionary=rows.get(key,{})
			rows[key]={"mode":CollisionGeometry.record_mode(record),"definition":previous.get("definition","")}
			if rows.size()>CollisionGeometry.MAX_CONSUMERS:return [{"mode":CollisionGeometry.ALL}]
	# Pending is the newest consumer, including a requeued/changed record. An
	# older published record with the same UUID must not weaken this demand.
	for item:Dictionary in _materialize_pending_snapshot():
		if item.get("path")!=path:continue
		var record:Dictionary=item.record
		rows[str(record.uuid)]=CollisionGeometry.consumer(record,item.get("reference_entry",EMPTY_DEMAND).get("compact_record",{}))
		if rows.size()>CollisionGeometry.MAX_CONSUMERS:return [{"mode":CollisionGeometry.ALL}]
	return rows.values()

func _geometry_coverage_current(path:String,result:Dictionary)->bool:
	if not CollisionGeometry.enabled or not result.has("collision_geometry_mode"):return true
	var known:Dictionary=_collision_definition_modes.get(path,{}).duplicate()
	known.merge(result.get("collision_definitions",{}),true)
	var required:=CollisionGeometry.resolve(_geometry_consumers(path),[],[],path,known)
	return result.collision_geometry_mode is int and result.collision_geometry_mode in [CollisionGeometry.NONE,CollisionGeometry.AUTHORED,CollisionGeometry.ALL] and int(result.collision_geometry_mode)>=int(required.mode)

func _remember_geometry_definitions(path:String,result:Dictionary)->void:
	if not CollisionGeometry.enabled:return
	var learned:Dictionary=result.get("collision_definitions",{})
	if learned.is_empty():return
	var known:Dictionary=_collision_definition_modes.get(path,{})
	for key:String in learned:
		if known.has(key):known[key]=maxi(int(known[key]),int(learned[key]));continue
		if _collision_definition_count>=CollisionGeometry.MAX_DEFINITIONS:break
		var bytes:=path.to_utf8_buffer().size()+key.to_utf8_buffer().size()+256
		if _collision_definition_bytes+bytes>CollisionGeometry.MAX_DEFINITION_BYTES:break
		known[key]=learned[key];_collision_definition_count+=1;_collision_definition_bytes+=bytes
	if not known.is_empty():_collision_definition_modes[path]=known
	profile.geometry_definition_bytes=_collision_definition_bytes

func _targeted_bridge_textures(item:Dictionary)->bool:
	# Core Images still belong to MapLoader before adoption. Do not start a
	# duplicate decode during early prefetch or borrow its prepared-image table.
	if not bridge_texture_preparation_enabled or _cancelled or not _active or _scene_handoff or not _entry_prefetch.is_empty():return false
	if not is_instance_valid(_map) or _map!=get_parent() or int(_map.get_meta("entry_plan",{}).get("core_resources_ready_us",0))<=0:return false
	return item.get("native_reference",false) and item.get("reference_entry",EMPTY_DEMAND).get("reason","")=="native_bridge" and _demanded_by_id.has(str(item.get("record",{}).get("uuid","")))

func _texture_sources(requests:Array)->Dictionary:
	var sources:Dictionary={}
	for request:Dictionary in requests:
		var at:int=int(request.get("record_index",-1))
		if at>=0 and at<_reference_index.get("rows",[]).size():sources.merge(_reference_index.rows[at].get("prefab_textures",{}),true)
	return sources

func _texture_headers_ready(item:Dictionary,requests:Array,tree:SceneTree)->bool:
	if not async_texture_headers_enabled or not texture_plan_reuse_enabled or _reference_root.is_empty() or (not prefab_texture_preparation_enabled and not _targeted_bridge_textures(item)):return true
	var began:=Time.get_ticks_usec() if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled else 0
	var ready:bool=_texture_plan_catalog.prepare_async(_texture_sources(requests),_reference_root,_admission,tree)
	_record_texture_dispatch("header_ready",began,str(item.get("path","")),requests.size())
	if not _texture_plan_catalog.error.is_empty():_fail(_texture_plan_catalog.error)
	return ready

func _native_model_plan(path:String,candidate:Dictionary,root:String,tree:SceneTree)->Dictionary:
	if not candidate.get("texture_table") is Dictionary:
		_fail("Invalid native model texture descriptor: "+path);return {}
	var capability_error:String=preload("res://scripts/world3d/native_texture_capability.gd").error_for(candidate.texture_table,_shared_images.get_script()!=SharedImages)
	if not capability_error.is_empty():_fail(capability_error);return {}
	var scope:RefCounted=_native_plan_claims.get(path)
	if scope!=null and (scope.root!=root or scope.candidate.texture_table!=candidate.texture_table):
		scope.release_now();_native_plan_claims.erase(path);scope=null
	if scope!=null and not scope.prepared.is_empty():return scope.prepared
	if scope==null:
		scope=preload("res://scripts/world3d/deferred_native_texture_scope.gd").new()
		scope.catalog=_texture_plan_catalog;scope.candidate={"texture_table":candidate.texture_table.duplicate()};scope.root=root
		_native_plan_serial+=1;scope.consumer="native_model:%d:%d"%[get_instance_id(),_native_plan_serial]
		_native_plan_claims[path]=scope
	if not _texture_plan_catalog.prepare_model_async(candidate,root,_admission,tree,scope.consumer):
		if not _texture_plan_catalog.error.is_empty():_fail(_texture_plan_catalog.error)
		return {}
	scope.prepared=_texture_plan_catalog.model_plan(candidate,root)
	return scope.prepared

func _retire_native_plan_claims(required:Dictionary)->void:
	for path:String in _native_plan_claims.keys():
		if required.has(path) and not path_errors.has(path):continue
		_native_plan_claims[path].release_now();_native_plan_claims.erase(path)

static func _clear_native_plan_aliases(job:Dictionary)->void:
	job.erase("native_model_plan")
	job.erase("native_texture_sources")
	job.get("estimate",{}).erase("prefab_texture_plan")

func _prefab_texture_plan(item:Dictionary,requests:Array)->Dictionary:
	if (not prefab_texture_preparation_enabled and not _targeted_bridge_textures(item)) or _reference_root.is_empty():return {}
	var generation:int=preload("res://scripts/world3d/surface_materials.gd").source_generation
	if generation!=_texture_attempt_generation:
		_prefab_texture_attempts.clear();_texture_attempt_generation=generation
	if _prefab_texture_attempt_revision!=_demand_revision:
		_prefab_texture_attempts.clear();_prefab_texture_attempt_revision=_demand_revision
	var positions:Array=[]
	for request:Dictionary in requests:positions.append(int(request.get("record_index",-1)))
	positions.sort()
	var key:Array=[str(item.get("path","")),positions]
	# Admission may retry every frame, and a native/raw route may be repriced in
	# the same dispatch. Reuse this exact request's header attempt, not a global
	# filesystem proof. The worker independently checks its immutable plan.
	if _prefab_texture_attempts.has(key):
		profile.prefab_texture_plan_hits=int(profile.get("prefab_texture_plan_hits",0))+1
		return _prefab_texture_attempts[key]
	var sources:Dictionary=_texture_sources(requests)
	# Compressed sources still need admitted CPU reads and sliced GPU uploads.
	# Omitting DDS here made real record construction synchronously load every
	# material layer, bypassing both the worker and the publication budget.
	var texture_plan_started:=Time.get_ticks_usec() if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled else 0
	var result:Dictionary={}
	if not sources.is_empty():
		result=_texture_plan_catalog.estimate(sources,_reference_root) if texture_plan_reuse_enabled else PrefabTextures.estimate(sources,_reference_root)
		if texture_plan_reuse_enabled:profile.texture_plan_catalog=_texture_plan_catalog.snapshot()
	_record_texture_dispatch("header_plan",texture_plan_started,str(item.get("path","")),sources.size())
	if result.get("rows",{}).is_empty():result={}
	if _prefab_texture_attempts.size()>=16:_prefab_texture_attempts.erase(_prefab_texture_attempts.keys()[0])
	_prefab_texture_attempts[key]=result
	profile.prefab_texture_plan_builds=int(profile.get("prefab_texture_plan_builds",0))+1
	return result

func _record_texture_dispatch(label:String,started:int,path:String,keys:int)->void:
	if started==0:return
	var elapsed:=Time.get_ticks_usec()-started
	if not profile.has("texture_dispatch"):profile.texture_dispatch={}
	var stages:Dictionary=profile.texture_dispatch
	if not stages.has(label):stages[label]={"calls":0,"total_us":0,"max_us":0,"keys":0,"slowest_path":""}
	var entry:Dictionary=stages[label];entry.calls+=1;entry.total_us+=elapsed;entry.keys+=keys
	if elapsed>entry.max_us:entry.max_us=elapsed;entry.slowest_path=path

func _estimate_job(item:Dictionary,requests:Array,need_model:bool=true)->Dictionary:
	var reference_bytes:=0
	var paint_workspace:=0
	for request:Dictionary in requests:reference_bytes+=int(request.get("memory_bytes",65536))
	var positions:Array=[]
	for request:Dictionary in requests:
		if request.has("record_index"):
			var at:=int(request.record_index);positions.append(at)
			if preload("res://scripts/world3d/surface_paint_preparation.gd").active() and at>=0 and at<_reference_index.get("rows",[]).size() and _reference_index.rows[at].get("reason")=="native_road":
				# Same byte lease as the road; no extra worker or unaccounted cache.
				paint_workspace+=int(_reference_index.rows[at].memory_bytes)
	reference_bytes+=paint_workspace
	for row:Dictionary in preload("res://scripts/world3d/map_dependency_index.gd").terrain_context_rows(_reference_index,positions):reference_bytes+=int(row.memory_bytes)
	var texture_plan:Dictionary=_prefab_texture_plan(item,requests)
	var texture_bytes:int=int(texture_plan.get("estimated_bytes",0))
	if item.get("native_reference",false):
		var collision_workspace:=0
		if CollisionProducts.enabled:
			for request:Dictionary in requests:
				var at:int=int(request.get("record_index",-1))
				if at>=0 and at<_reference_index.get("rows",[]).size() and _reference_index.rows[at].get("prefab_locked",false):collision_workspace=CollisionProducts.WORKSPACE_BYTES;break
		return {"estimated_bytes":maxi(65536,reference_bytes)+texture_bytes+collision_workspace,"exclusive":false,"known":true,"prefab_texture_plan":texture_plan,"collision_workspace_bytes":collision_workspace,"road_paint_workspace_bytes":paint_workspace,"targeted_bridge_textures":_targeted_bridge_textures(item)}
	if not need_model:
		# The verified template is already owned by the resident asset cache.
		# This job cannot decode/import a model: it only hydrates references and
		# hashes source bytes with bounded scratch. Keep reference output charged
		# until publication/discard, without charging a second model decode peak.
		return {"estimated_bytes":maxi(65536,reference_bytes)+REUSE_HASH_RESERVATION_BYTES+texture_bytes,"exclusive":false,"known":true,"stage":"reuse_reference","shared_model_estimate_bytes":int(item.get("memory",{}).get("estimated_bytes",0)),"prefab_texture_plan":texture_plan}
	var result:Dictionary=item.get("memory",{"estimated_bytes":_admission.byte_limit,"exclusive":true}).duplicate()
	result.estimated_bytes=int(result.get("estimated_bytes",_admission.byte_limit))+reference_bytes+texture_bytes
	result.prefab_texture_plan=texture_plan
	return result

static func _prepare_job(path:String,digest:String,token:RefCounted,manifest:Dictionary,faces:bool,root:String,index:Dictionary,map_path:String,requests:Array,native:bool,need_model:bool,ownership_proof:OwnershipProof=null,model_route:Dictionary={})->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=_prepare_job_inner(path,digest,token,manifest,faces,root,index,map_path,requests,native,need_model,ownership_proof,model_route)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.job",started,{"path":path,"native":native,"need_model":need_model,"reference_count":requests.size(),"failed":not str(result.get("error","")).is_empty()})
	if model_route.get("completed_job_trace",false):
		result.audit_worker_start_us=started;result.audit_worker_end_us=Time.get_ticks_usec()
	return result

static func _prepare_job_inner(path:String,digest:String,token:RefCounted,manifest:Dictionary,faces:bool,root:String,index:Dictionary,map_path:String,requests:Array,native:bool,need_model:bool,ownership_proof:OwnershipProof=null,model_route:Dictionary={})->Dictionary:
	var started:=Time.get_ticks_usec()
	# This route consumes an already digest-bound template, never source GLB
	# geometry. Cheap preflight is sufficient before reference hydration; one
	# complete final source observation still gates every returned result.
	if not native and not need_model:
		var before:=_preflight_reused_source(path,digest,root,token,model_route.get("require_native_products",false))
		if not before.error.is_empty():return before
	var prepared:Dictionary={"error":"","records":[],"dependencies":{},"read_profile":{}}
	if not requests.is_empty():
		prepared=preload("res://scripts/world3d/chunk_reference_preparation.gd").prepare(index,requests,map_path,root,token,ownership_proof,model_route.get("prefab_texture_plan",{}),model_route.get("shared_pixels",{}),int(model_route.get("collision_workspace_bytes",0)),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),model_route.get("hydrated_records",{}),model_route.get("parallel_pixels",false) or model_route.has("native_model_plan"),int(model_route.get("road_paint_workspace_bytes",0)))
		if not prepared.error.is_empty():prepared.reference_failure=true;return prepared
	var geometry:Dictionary={"mode":CollisionGeometry.ALL,"definitions":{}}
	if model_route.get("filter_collision_geometry",false) and not native:
		geometry=CollisionGeometry.resolve(model_route.get("geometry_consumers",[]),prepared.records,requests,path,model_route.get("geometry_known",{}))
	if not native and not need_model:
		var face_snapshots:Array=model_route.get("reuse_face_snapshots",[])
		if not face_snapshots.is_empty():
			var face_started:=Time.get_ticks_usec()
			var face_result:Dictionary=FacePrefetch._build(face_snapshots,token)
			if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
			if face_result.get("faces",{}).size()!=face_snapshots.size():return {"error":"复用素材碰撞面准备失败："+path}
			prepared.reuse_faces=face_result.faces;prepared.reuse_face_us=Time.get_ticks_usec()-face_started
			preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.reused_faces",face_started,{"path":path,"meshes":face_snapshots.size()})
		var after:=_verify_reused_source(path,digest,root,token,model_route.get("require_native_products",false))
		if not after.error.is_empty():return after
		prepared.source_digest=digest;prepared.reused_model=true
		if model_route.get("filter_collision_geometry",false):
			# Reuse was checked on main against this (possibly more conservative)
			# policy before receiving its bounded arrays/face reservation.
			prepared.collision_geometry_mode=int(model_route.get("geometry_mode",CollisionGeometry.ALL))
			prepared.collision_definitions=geometry.definitions
		prepared.elapsed_us=Time.get_ticks_usec()-started
		return prepared
	if native:
		prepared.elapsed_us=int(prepared.get("read_profile",{}).get("elapsed_us",0));prepared.native_reference=native
		return prepared
	var result:Dictionary
	if model_route.get("stage")=="fixed_native":result=_prepare_fixed_scene(path,digest,token,manifest,faces,root,model_route.candidate,int(geometry.mode),model_route.get("require_native_products",false),model_route.get("worker_prepack",false),model_route.get("direct_material_plan",false))
	else:result=prepare_scene(path,digest,token,manifest,faces,root,model_route.get("stage")=="raw_import",int(geometry.mode),true,preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),model_route.get("require_native_products",false))
	if model_route.get("require_native_products",false) and result.has("native_packet"):
		var packet:Dictionary=result.native_packet
		if packet.get("fallback_required",false) or packet.get("native_source_retry",false):
			packet.erase("fallback_required");packet.erase("native_source_retry")
			packet.merge(preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,str(packet.get("cache_reason","invalid_product"))),true)
			result.error=packet.error_message
	if model_route.get("filter_collision_geometry",false) and str(result.get("error","")).is_empty() and not result.get("native_packet",{}).get("fallback_required",false):
		result.collision_geometry_mode=int(geometry.mode);result.collision_definitions=geometry.definitions
	result.records=prepared.records;result.dependencies=prepared.dependencies;result.read_profile=prepared.read_profile
	for field:String in ["prefab_cpu","prefab_texture_packet","surface_arrays","surface_bounds","surface_paints","surface_uploads","waiting_pixels","terrain_contexts"]:
		if prepared.has(field):result[field]=prepared[field]
	if model_route.has("native_model_plan") and not model_route.get("parallel_pixels",false) and str(result.get("error","")).is_empty():
		# This also runs for direct models without any reference records. The
		# same callable runs as the separately admitted half when slots permit.
		var pixels:Dictionary=model_route.native_pixels_task.call()
		result.prefab_texture_packet=pixels;result.waiting_pixels=pixels.get("waiting_pixels",false)
		result.error=pixels.get("error","")
		result.read_profile.prefab_textures=pixels.get("profile",{})
		for field:String in ["cancelled","retry_pixels","source_revisions"]:
			if pixels.has(field):result[field]=pixels[field]
	return result

static func _preflight_reused_source(path:String,digest:String,content_root:String,token:RefCounted,native_only:bool=false)->Dictionary:
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	var native_package:bool=native_only
	var confined:bool=preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path,content_root) if native_package else preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root)
	if not Assets._valid_source_digest(digest) or content_root.is_empty() or not confined:return {"error":"复用素材缺少有效来源身份："+path}
	# A reused native template already owns its accepted product and digest. Its
	# logical authoring key need not have a raw source file beside the package.
	if not native_package and not FileAccess.file_exists(path):return {"error":"复用素材来源已丢失："+path}
	# Filesystem/root checks may block; cancellation must stop before rmres IO.
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	return {"error":""}

static func _verify_reused_source(path:String,digest:String,content_root:String,token:RefCounted,native_only:bool=false)->Dictionary:
	if native_only or preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return _preflight_reused_source(path,digest,content_root,token,native_only)
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if not Assets._valid_source_digest(digest) or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):return {"error":"复用素材缺少有效来源身份："+path}
	var started:=Time.get_ticks_usec()
	var current:=_bounded_source_sha(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.reused_source_sha",started,{"path":path})
	if current!=digest or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):return {"error":"复用素材来源已改变："+path}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	return {"error":""}

static func _bounded_source_sha(path:String)->String:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return ""
	var size:=file.get_length();var consumed:=0
	var hash:=HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK:return ""
	while consumed<size:
		var amount:=mini(REUSE_HASH_BLOCK_BYTES,size-consumed)
		var block:=file.get_buffer(amount)
		if block.size()!=amount or hash.update(block)!=OK:return ""
		consumed+=amount
	if file.get_length()!=size:return ""
	return hash.finish().hex_encode()

func _cached_model_matches(path:String)->bool:
	var digest:String=source_signatures.get(path,"")
	return Assets._valid_source_digest(digest) and Assets.has_cached_scene(path,digest)

func _resident_prepared_template(path:String)->PackedScene:
	if _raw_retries.has(path) or not _cached_model_matches(path):return null
	var current:PackedScene=Assets._scenes.get(path)
	if _prepared_paths.has(path):return current
	# Cancelling a reference job invalidates its publication state, not an
	# already accepted immutable model. Reuse only this queue's exact full
	# capture; another same-SHA allocation may have weaker geometry coverage.
	var previous:WeakRef=_prepared_template_owners.get(path)
	if previous!=null and previous.get_ref()==current:return current
	return null

func _reuse_template_current(path:String,job:Dictionary,digest:String)->bool:
	var owner:Variant=job.get("reuse_template_owner")
	return owner is PackedScene and Assets.has_cached_scene(path,digest) and Assets._scenes.get(path)==owner

func _publication_template_current(path:String,job:Dictionary)->bool:
	# Source identity alone does not prove optional CPU captures exist on this
	# allocation. A concurrent load can replace a same-SHA template with a graph
	# prepared for weaker consumers. Publish only the exact accepted template.
	var owner:Variant=job.get("publication_template_owner",job.get("reuse_template_owner"))
	return owner is PackedScene and Assets.has_cached_scene(path,str(job.get("result",{}).get("source_digest",""))) and Assets._scenes.get(path)==owner

static func _reuse_face_offer(packed:PackedScene,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
	# Read existing main-owned CPU captures only. A missing capture cannot be
	# downloaded from RenderingServer under the small reuse reservation.
	var owners:Dictionary={};var snapshots:Array=[];var bytes:=0;var seen:Dictionary={}
	var state:=packed.get_state()
	for at in state.get_node_count():
		var extras:Variant={}
		for property in state.get_node_property_count(at):
			if state.get_node_property_name(at,property)==&"metadata/extras":extras=state.get_node_property_value(at,property)
		if not CollisionGeometry.needs_geometry(extras,geometry_mode):continue
		for property in state.get_node_property_count(at):
			if state.get_node_property_name(at,property)!=&"mesh":continue
			var source:Variant=state.get_node_property_value(at,property)
			if not source is ArrayMesh:return {"ok":false,"reason":"unsupported_mesh"}
			var id:=str(source.get_instance_id())
			if seen.has(id):continue
			seen[id]=true
			if not source.has_meta("ground_cpu_cache"):return {"ok":false,"reason":"missing_cpu_capture"}
			var cpu:Variant=source.get_meta("ground_cpu_cache")
			if not cpu is FacePrefetch.Cpu:return {"ok":false,"reason":"missing_cpu_capture"}
			if not cpu._collision_faces.is_empty():continue
			if snapshots.size()>=REUSE_FACE_MAX_MESHES:return {"ok":false,"reason":"mesh_limit"}
			var snapshot:=FacePrefetch._snapshot({"source":source,"cpu":cpu,"basis":Basis.IDENTITY})
			if snapshot.is_empty():return {"ok":false,"reason":"unsupported_cpu_capture"}
			var input_bytes:=0
			for arrays:Array in snapshot.surfaces:
				for channel:Variant in arrays:input_bytes+=_packed_payload_bytes(channel)
			bytes+=input_bytes+int(snapshot.count)*12+65536
			if bytes>REUSE_FACE_MAX_BYTES:return {"ok":false,"reason":"face_budget"}
			snapshot.id=id;snapshots.append(snapshot)
			# Array containers and source identity are immutable capture ownership.
			# Mesh changes invalidate ground_cpu_cache; no main-thread deep face
			# comparisons or hashing are needed before consuming the worker packet.
			owners[id]={"source":source,"cpu":cpu,"surfaces":cpu.surfaces,"slots":cpu.surfaces.duplicate(),"count":snapshot.count}
	return {"ok":true,"owners":owners,"snapshots":snapshots,"estimated_bytes":bytes}

func _accept_reused_faces(job:Dictionary,result:Dictionary)->bool:
	var owners:Dictionary=job.get("reuse_face_owners",{})
	if owners.is_empty():return true
	var outputs:Dictionary=result.get("reuse_faces",{})
	if outputs.size()!=owners.size():return false
	for id:String in owners:
		var owner:Dictionary=owners[id];var source:Mesh=owner.source;var cpu:Mesh=owner.cpu
		if not source.has_meta("ground_cpu_cache") or source.get_meta("ground_cpu_cache")!=cpu or not is_same(cpu.surfaces,owner.surfaces) or cpu.surfaces.size()!=owner.slots.size():return false
		for slot in cpu.surfaces.size():
			if not is_same(cpu.surfaces[slot],owner.slots[slot]):return false
		if not outputs.get(id) is PackedVector3Array or outputs[id].size()!=int(owner.count):return false
	# Every owner passed before any shared resident CPU capture is changed.
	for id:String in owners:
		var cpu:Mesh=owners[id].cpu
		if cpu._collision_faces.is_empty():cpu._collision_faces=outputs[id]
	profile.reuse_face_prepared_meshes=int(profile.get("reuse_face_prepared_meshes",0))+owners.size()
	profile.reuse_face_worker_us=int(profile.get("reuse_face_worker_us",0))+int(result.get("reuse_face_us",0))
	return true

func _accept_prepared_records(result:Dictionary)->void:
	var records:Dictionary={}
	for record:Dictionary in result.get("records",[]):records[record.uuid]=record
	if not records.is_empty():_invalidate_collision_queries()
	var surfaces:Dictionary=result.get("surface_arrays",{})
	var terrain_contexts:Dictionary=result.get("terrain_contexts",{})
	if not terrain_contexts.is_empty():_doc.terrain_neighbors.data.merge(terrain_contexts,true)
	if not surfaces.is_empty():
		# Optional products belong to this exact array generation. A fresh result
		# without a product revokes an older one for the same UUID as well.
		for uuid:String in surfaces:
			_doc.load_surface_arrays[uuid]=surfaces[uuid]
			_doc.load_surface_bounds.erase(uuid);_doc.load_surface_uploads.erase(uuid);_doc.load_surface_paints.erase(uuid)
		_doc.load_surface_bounds.merge(result.get("surface_bounds",{}),true)
		_doc.load_surface_paints.merge(result.get("surface_paints",{}),true)
		for field:String in ["road_paint_us","road_paint_bytes","road_paint_records","road_paint_bounds_scans","reused_paint_source_bounds"]:profile[field]=int(profile.get(field,0))+int(result.get("read_profile",{}).get(field,0))
		_doc.load_surface_uploads.merge(result.get("surface_uploads",{}),true)
		for field:String in ["surface_upload_bytes","surface_upload_us","surface_upload_records"]:profile[field]=int(profile.get(field,0))+int(result.get("read_profile",{}).get(field,0))
		profile.worker_surface_bounds=int(profile.get("worker_surface_bounds",0))+result.get("surface_bounds",{}).size()
		profile.native_surface_records=int(profile.get("native_surface_records",0))+surfaces.size()
		profile.native_surface_worker_us=int(profile.get("native_surface_worker_us",0))+int(result.get("read_profile",{}).get("road_array_prepare_us",0))
	if _indexed and incremental_pending_index_enabled:
		# The live UUID catalog already owns these exact pending items. A result
		# should touch its records only, even after an earlier sibling retired.
		for uuid:String in records:
			var item:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
			if not item.is_empty():item.record=records[uuid];item.reference_prepared=true
		profile.acceptance_record_visits=int(profile.get("acceptance_record_visits",0))+records.size()
	else:
		for item:Dictionary in _materialize_pending_snapshot():
			if records.has(item.record.uuid):item.record=records[item.record.uuid];item.reference_prepared=true
		profile.acceptance_record_visits=int(profile.get("acceptance_record_visits",0))+pending_count()
	profile.reference_records=int(profile.get("reference_records",0))+records.size()
	profile.reference_worker_us=int(profile.get("reference_worker_us",0))+int(result.get("read_profile",{}).get("elapsed_us",0))
	for field:String in result.get("read_profile",{}).get("collision_products",{}):
		profile["collision_product_"+field]=int(profile.get("collision_product_"+field,0))+int(result.read_profile.collision_products[field])
	var reference_profile:Dictionary=result.get("read_profile",{})
	for field:String in ["prefab_faces_prepared_slots","prefab_faces_skipped_slots","prefab_faces_canonical_slots","prefab_faces_prepared_vertices"]:
		profile["reference_"+field]=int(profile.get("reference_"+field,0))+int(reference_profile.get(field,0))
	for field in ["preflight_us","preflight_ownership_us","selected_ownership_us","selected_uuid_lookup_us","map_authentications","directory_rows_recomputed","groups_checked","terrain_context_source_rows","terrain_boundary_normals","terrain_mask_generations","terrain_mask_bytes","terrain_mask_us","terrain_mask_on_main","road_cache_hits","road_array_generations","cached_surface_bounds","scanned_surface_bounds","surface_bounds_us","definition_copies","definition_transfers","reads_started","handoff_records"]:
		profile["reference_"+field]=int(profile.get("reference_"+field,0))+int(reference_profile.get(field,0))
	if not records.is_empty():
		var key:String="reference_proof_jobs" if reference_profile.get("ownership_proof_used",false) else "reference_full_scan_jobs"
		profile[key]=int(profile.get(key,0))+1

func runtime_record(uuid:String)->Dictionary:
	var record:Variant=_runtime_record_ids.get(uuid)
	return record if record is Dictionary else {}

func _note_runtime_record(item:Dictionary)->void:
	if not item.has("reference_entry") or _runtime_record_ids.has(item.record.uuid):return
	var extra:Dictionary=_map.get_meta("extras",{})
	if not extra.get("rmmo_records") is Array:return
	extra.rmmo_records.append(item.record);_runtime_record_ids[item.record.uuid]=item.record
	var dependencies:Dictionary=extra.get("rmmo_resource_dependencies",{})
	var reference:Dictionary=item.reference_entry.compact_record.rmmo_ref
	dependencies[reference.uri]=reference.sha256;extra.rmmo_resource_dependencies=dependencies
	_map.set_meta("extras",extra)

func _job_consumed(job:Dictionary)->bool:
	for uuid:String in job.get("publication_ids",[]):
		var item:Dictionary=_demanded_by_id.get(uuid,{})
		if not item.is_empty() and not item.get("published",false) and not instance_errors.has(uuid) and not path_errors.has(item.path):return false
	return true

func _stage_publication_packet(items:Array,specs:Array)->Dictionary:
	var first:Dictionary=_jobs.get(items[0].path,{})
	var packet:Dictionary=first.get("collision_staged",{}).get(items[0].record.uuid,{})
	if packet.is_empty() or not is_same(packet.specs,specs):packet={"items":items,"specs":specs}
	if not first.has("publication_packets"):first.publication_packets={}
	first.publication_packets[items[0].record.uuid]=packet
	for item:Dictionary in items:
		var job:Dictionary=_jobs.get(item.path,{})
		if job.is_empty():continue
		if not job.has("collision_staged"):job.collision_staged={}
		job.collision_staged[item.record.uuid]=packet
	return packet

func _apply_publication_fixture_states(specs:Array)->bool:
	var changed:=false
	for spec:Dictionary in specs:
		var extra:Dictionary=spec.get("extras",{})
		if not extra.has("fixture"):continue
		var uuid:String=spec.get("ground_batch_record",{}).get("uuid",str(spec.uuid).get_slice("__",0))
		if runtime_fixture_states.has(uuid):
			var value:Variant=runtime_fixture_states[uuid]
			var pose:Transform3D=preload("res://scripts/world3d/building_fixtures.gd").pose(spec.closed_transform,extra.fixture,float(value))
			changed=changed or extra.fixture.get("open",0.)!=value or spec.transform!=pose
			extra.fixture.open=value;spec.transform=pose;spec.position=pose.origin
	return changed

func _publish_items(items:Array,specs:Array)->bool:
	# Stream indexes require a whole building/fixture namespace in one atomic
	# append. Staging can span frames; no component becomes visible beforehand.
	if not _publication_packet_ready(items):
		# A ready selection is not a commit permit: dependency installation can
		# begin during construction, and a group's representative is not its peers.
		if _publication_packet_valid(items):_stage_publication_packet(items,specs)
		return false
	var preparation:RefCounted
	if specs.size()>=32 and not items.is_empty():
		var packet:=_stage_publication_packet(items,specs)
		if not packet.has("index_preparation") and not packet.get("index_preparation_skipped",false):
			_apply_publication_fixture_states(specs)
			packet.index_preparation=preload("res://scripts/world3d/stream_index_preparation.gd").new()
			var owned:bool=owned_index_projection_enabled and not packet.get("index_owned_skipped",false)
			for item:Dictionary in items:
				if item.get("native_reference",false) or item.record.has("house_prefab"):owned=false;break
			if owned and private_publication_packet_enabled:packet.index_preparation.begin_runtime_owned(specs)
			elif owned:packet.index_preparation.begin_owned(specs,true)
			else:packet.index_preparation.begin(specs,true)
			profile.index_preparation_instances=int(profile.get("index_preparation_instances",0))+1
		if packet.has("index_preparation"):
			preparation=packet.index_preparation
			var began:=Time.get_ticks_usec()
			var ready:bool=preparation.advance(2000)
			var elapsed:=Time.get_ticks_usec()-began
			profile.index_preparation_slices=int(profile.get("index_preparation_slices",0))+1
			profile.index_preparation_us=int(profile.get("index_preparation_us",0))+elapsed
			profile.max_index_preparation_slice_us=maxi(int(profile.get("max_index_preparation_slice_us",0)),elapsed)
			preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.index_prepare",began,{"specs":specs.size(),"ready":ready})
			if not ready:return false
			if preparation.error=="existing_derived_fields":
				preparation.dispose()
				packet.erase("index_preparation");packet.index_preparation_skipped=true;preparation=null
			elif preparation.error=="owned_projection_ineligible":
				preparation.dispose();packet.erase("index_preparation");packet.index_owned_skipped=true
				return false
			elif not preparation.error.is_empty():
				var failure:String=preparation.error
				_clear_collision_staging(items)
				for item:Dictionary in items:_instance_failed(str(item.record.uuid),"后台索引准备失败："+failure)
				return false
	var commit_began:=Time.get_ticks_usec()
	# Reapply only at initial capture and final publication, not on every cursor
	# slice. A changed pose invalidates the private signature and retries safely.
	var fixture_started:=Time.get_ticks_usec()
	var fixture_changed:=_apply_publication_fixture_states(preparation.fixtures if preparation!=null and preparation.runtime_owned else specs)
	var fixture_us:=Time.get_ticks_usec()-fixture_started
	profile.publication_fixture_us=int(profile.get("publication_fixture_us",0))+fixture_us
	if fixture_changed and preparation!=null and preparation.runtime_owned:
		var packet:=_stage_publication_packet(items,specs)
		preparation.dispose();packet.erase("index_preparation")
		profile.index_preparation_restarts=int(profile.get("index_preparation_restarts",0))+1
		return false
	var publication_packet:RefCounted=preparation.publication_packet if preparation!=null else null
	var append_started:=Time.get_ticks_usec()
	var registered:Dictionary=Stream.append_specs(_map,specs,preparation,true)
	var append_us:=Time.get_ticks_usec()-append_started
	profile.publication_append_us=int(profile.get("publication_append_us",0))+append_us
	if not registered.ok:
		if registered.get("error","")=="stale_private_index":
			var packet:=_stage_publication_packet(items,specs)
			preparation.dispose()
			packet.erase("index_preparation")
			profile.index_preparation_restarts=int(profile.get("index_preparation_restarts",0))+1
			return false
		if registered.get("error","")=="promotion_collision_pending":
			# A collision installer can win the race after this frame's ready
			# selection. Keep the already-instantiated specs with their admitted
			# job; neither fail the author instance nor instantiate it again.
			_stage_publication_packet(items,specs)
			profile.collision_publication_races=int(profile.get("collision_publication_races",0))+1
			return false
		_clear_collision_staging(items)
		for item:Dictionary in items:_instance_failed(str(item.record.uuid),"后台物件登记失败："+str(registered.error))
		return false
	_clear_collision_staging(items)
	for item:Dictionary in items:
		_note_runtime_record(item)
		item.published=true;profile.instances+=1
		if CompletedTrace.enabled and _jobs.has(item.path):
			CompletedTrace.record(item.path,_jobs[item.path].token.get_instance_id(),"committed",{"uuid":str(item.record.uuid)})
		# Strip hydrated definitions before either removing the spatial member or
		# retaining a tombstone in the diagnostic full-rebuild path.
		if item.has("reference_entry"):item.record=item.reference_entry.compact_record;item.reference_prepared=false
	var remove_started:=Time.get_ticks_usec()
	if _defer_demand_removal:
		_deferred_removal_items.append_array(items)
	else:
		_remove_published_demand(items)
	var remove_us:=Time.get_ticks_usec()-remove_started
	profile.specs+=specs.size()
	profile.publication_remove_us=int(profile.get("publication_remove_us",0))+remove_us
	var details:Dictionary={"specs":specs.size(),"uuid":items[0].record.uuid if not items.is_empty() else "","index_prepared":preparation!=null}
	publication_metadata=publication_packet
	var emit_started:=Time.get_ticks_usec()
	published.emit(specs)
	var emit_us:=Time.get_ticks_usec()-emit_started
	profile.publication_emit_us=int(profile.get("publication_emit_us",0))+emit_us
	publication_metadata=null
	var unit_us:=Time.get_ticks_usec()-commit_began
	if unit_us>10000:
		if not profile.has("publish_slow"):profile.publish_slow=[]
		profile.publish_slow.append({"at_us":commit_began,"us":unit_us,"specs":specs.size(),"items":items.size(),"append_us":append_us,"remove_us":remove_us,"emit_us":emit_us,"fixture_us":fixture_us,"path":str(items[0].path) if not items.is_empty() else "","kind":str(items[0].record.get("kind","")) if not items.is_empty() else "","group":str(items[0].get("group_id","")) if not items.is_empty() else ""})
		profile.publish_slow.sort_custom(func(a,b):return int(a.us)>int(b.us))
		if profile.publish_slow.size()>16:profile.publish_slow.resize(16)
	_note_preparation_latency(items)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.publish_commit",commit_began,details)
	return true

func _clear_collision_staging(items:Array)->void:
	var disposed:Dictionary={}
	for item:Dictionary in items:
		var job:Dictionary=_jobs.get(item.path,{})
		if job.has("collision_staged"):
			var packet:Dictionary=job.collision_staged.get(item.record.uuid,{})
			if not packet.is_empty() and not disposed.has(packet.items[0].record.uuid):
				disposed[packet.items[0].record.uuid]=true
				var owner:Dictionary=_jobs.get(packet.items[0].path,{})
				owner.get("publication_packets",{}).erase(packet.items[0].record.uuid)
				if packet.has("index_preparation"):packet.index_preparation.dispose();packet.erase("index_preparation")
				var bytes:int=packet.get("workspace_charge",0)
				if bytes>0:_admission.release_publication_workspace(item.path,bytes);packet.erase("workspace_charge")
			job.collision_staged.erase(item.record.uuid)

func _publication_packet_valid(items:Array)->bool:
	for item:Dictionary in items:
		if item.get("published",false) or not _demanded_by_id.has(item.record.uuid) or instance_errors.has(item.record.uuid) or path_errors.has(item.path):return false
	return true

func _publication_packet_ready(items:Array)->bool:
	if not _publication_packet_valid(items):return false
	profile.publication_packet_checks=int(profile.get("publication_packet_checks",0))+1
	profile.publication_packet_member_checks=int(profile.get("publication_packet_member_checks",0))+items.size()
	var ready:=true;var failed:=""
	for item:Dictionary in items:
		if not _publication_dependencies_ready(item):ready=false
		if instance_errors.has(item.record.uuid):failed=item.record.uuid
	if not failed.is_empty():
		for item:Dictionary in items:
			if not instance_errors.has(item.record.uuid):_instance_failed(item.record.uuid,"Atomic publication member failed: "+failed)
		_clear_collision_staging(items)
	return ready

func _prune_publication_packets(job:Dictionary)->void:
	# Exceptional staged outputs only. Visit each atomic packet once, promptly
	# dropping invalid/lost-demand owners even while healthy siblings keep a job.
	for packet:Dictionary in job.get("publication_packets",{}).values():
		var failed:=""
		for item:Dictionary in packet.items:
			if instance_errors.has(item.record.uuid) or path_errors.has(item.path):failed=item.record.uuid;break
		if not failed.is_empty():
			for item:Dictionary in packet.items:
				if not instance_errors.has(item.record.uuid):_instance_failed(item.record.uuid,"Atomic publication member failed: "+failed)
		if not _publication_packet_valid(packet.items):_clear_collision_staging(packet.items)

func _publication_workspace_available(job:Dictionary,path:String,reserve:bool=false)->bool:
	# Whole native groups already budget their complete staged output. Worker
	# spec packets also retain their existing batch reservation when moved here.
	var uncharged:Array=[]
	for packet:Dictionary in job.get("publication_packets",{}).values():
		if packet.items.size()!=1 or packet.get("worker_prepared",false) or int(packet.get("workspace_charge",0))>0:continue
		uncharged.append(packet)
	if uncharged.is_empty():return true
	var minimum_bytes:=0
	for packet:Dictionary in uncharged:
		if not packet.has("publication_workspace_bound"):
			# Reuse admission deliberately omits the resident model. Its smaller
			# lease is not a bound on another full unpublished instance.
			var model_bound:int=int(job.get("estimate",{}).get("shared_model_estimate_bytes",0))
			var instance_bound:=var_to_bytes(packet.items[0].record).size()*8
			packet.publication_workspace_bound=maxi(model_bound,instance_bound)
		minimum_bytes=maxi(minimum_bytes,int(packet.publication_workspace_bound))
	# One conservative unit for this batch makes the capacity preview and the
	# selected-path reservation identical; no bytes are charged during selection.
	if _admission.publication_workspace_capacity(path,uncharged.size(),minimum_bytes)==0:
		profile.publication_workspace_waits=int(profile.get("publication_workspace_waits",0))+1
		return false
	if not reserve:return true # Readiness must not reserve for an unselected path.
	for packet:Dictionary in uncharged:
		var bytes:=_admission.retain_publication_workspace(path,minimum_bytes)
		assert(bytes>0)
		packet.workspace_charge=bytes
		profile.publication_workspace_reservations=int(profile.get("publication_workspace_reservations",0))+1
	return true

func _collision_publication_status(uuid:String)->Dictionary:
	if not is_instance_valid(_map):return EMPTY_DEMAND
	var store:Node=_map.get_node_or_null("CollisionInstanceResidency")
	if store==null:return EMPTY_DEMAND
	return store.publication_status(uuid)

func _publication_discarded(item:Dictionary,staged:Dictionary)->bool:
	if item.get("published",false) or not _demanded_by_id.has(item.record.uuid) or instance_errors.has(item.record.uuid) or staged.has(item.record.uuid):return true
	if item.has("reference_entry") and not item.get("reference_prepared",false):return true
	return not item.get("native_reference",false) and not item.get("model_verified",false)

static func _without_published(values:Array,removed:Dictionary)->Array:
	# Keep stable order and a fresh array, without one Variant callable dispatch
	# per pending record during the synchronous publication transaction.
	var remaining:Array=[]
	for item:Dictionary in values:
		if not removed.has(item.record.uuid):remaining.append(item)
	return remaining

func _remove_published_demand(items:Array)->void:
	# Publishing does not change the relative priority of any remaining demand.
	# Remove the completed batch once instead of rebuilding/sorting all tickets
	# after every instance. Sparse ranks remain valid until a real demand change.
	var removed:Dictionary={};var paths:Dictionary={}
	# These private catalogs have the same insertion order and item identities
	# as their arrays. Preserve fresh-array semantics for outstanding cursors.
	var ordered_pending:=ordered_publication_removal_enabled and incremental_pending_index_enabled and _indexed and _pending_by_record_id.size()==pending_count()
	var ordered_demand:=ordered_publication_removal_enabled and _demanded_by_id.size()==_demanded_count()
	profile.publication_survivor_scan_rows=int(profile.get("publication_survivor_scan_rows",0))+(0 if ordered_pending else pending_count())+(0 if ordered_demand else _demanded_count())
	var batch_unindexed:bool=batched_pending_unindex_enabled and incremental_pending_index_enabled and _indexed and items.size()>=16 and _unindex_pending_batch(items)
	for item:Dictionary in items:
		var uuid:String=item.record.uuid
		removed[uuid]=true;paths[item.path]=true
		_demand_candidate_rows.erase(uuid)
		if incremental_pending_index_enabled and _indexed and not batch_unindexed:_unindex_pending_item(item,false)
		_demanded_by_id.erase(uuid);_demanded_rank.erase(uuid);_demanded_priority.erase(uuid)
	var pruned:=0
	for cached:Dictionary in _demand_membership.values():
		if not cached.items is Dictionary or cached.items.is_empty():continue
		for item:Dictionary in items:
			var uuid:String=item.record.uuid
			if is_same(cached.items.get(uuid),item):
				# Drop our old snapshot immediately, without clearing arrays held
				# by outstanding consumers. The next traversal materializes once.
				cached.erase("rows")
				cached.items.erase(uuid);pruned+=1
				if cached.items.is_empty():break
	profile.demand_membership_pruned=int(profile.get("demand_membership_pruned",0))+pruned
	if ordered_pending:
		# The ordered catalogue is already the complete survivor list. Keep
		# borrowed arrays intact; only an actual traversal needs a fresh Array.
		if not _pending_snapshot_dirty:
			_pending_snapshot=[];_pending_snapshot_private=true
		_pending_snapshot_dirty=true
		profile.pending_snapshot_rows_deferred=int(profile.get("pending_snapshot_rows_deferred",0))+_pending_by_record_id.size()
	else:pending=_without_published(_materialize_pending_snapshot(),removed)
	_invalidate_collision_queries()
	if ordered_demand:
		# The ordered UUID catalogue already contains the exact survivors. Most
		# publication consumers only query it or ask for a count. Materialize a
		# new Array only for an actual traversal, preserving old borrowed arrays.
		if not _demanded_snapshot_dirty:_demanded_snapshot=[]
		_demanded_snapshot_dirty=true
		profile.demand_snapshot_rows_deferred=int(profile.get("demand_snapshot_rows_deferred",0))+_demanded_by_id.size()
	else:_demanded=_without_published(_demanded,removed)
	for path:String in paths:
		if not _demanded_by_path.has(path):continue
		var remaining:Array=_without_published(_demanded_by_path[path],removed)
		if remaining.is_empty():
			_demanded_by_path.erase(path);_path_first.erase(path)
		else:
			_demanded_by_path[path]=remaining;_path_first.erase(path)
			for candidate:Dictionary in remaining:
				if not instance_errors.has(candidate.record.uuid):_path_first[path]=candidate;break
		_reorder_dispatch_path(path)

func _stage_building(item:Dictionary,specs:Array)->void:
	var job:Dictionary=_jobs.get(item.path,{})
	if job.is_empty():return
	if not job.has("staged"):job.staged={}
	if not job.has("staged_groups"):job.staged_groups={}
	var group:String=item.group_id
	# Count each prepared component once. Rebuilding an ordered prefix on every
	# arrival turns a large building into quadratic copying of the same specs.
	if not job.staged.has(item.record.uuid):job.staged_groups[group]=int(job.staged_groups.get(group,0))+1
	job.staged[item.record.uuid]={"item":item,"specs":specs}
	var members:Array=_reference_index.groups[group].members
	if not instance_errors.is_empty():
		# Failure may precede staging (for example collision preparation). Only
		# the exceptional path scans for it; an incomplete prefix must not hide it.
		for at in members:
			var uuid:String=_reference_index.extras.rmmo_records[at].uuid
			if not instance_errors.has(uuid):continue
			for member_at in members:
				var member_id:String=_reference_index.extras.rmmo_records[member_at].uuid
				_instance_failed(member_id,"建筑组件准备失败："+uuid);job.staged.erase(member_id)
			job.staged_groups.erase(group);return
	if int(job.staged_groups[group])<members.size():return
	var ordered:Array=[];var combined:Array=[]
	for at in members:
		var uuid:String=_reference_index.extras.rmmo_records[at].uuid
		var ready:Dictionary=job.staged[uuid]
		ordered.append(ready.item);combined.append_array(ready.specs)
		job.staged.erase(uuid)
	profile.staging_member_visits=int(profile.get("staging_member_visits",0))+members.size()
	job.staged_groups.erase(group)
	_publish_items(ordered,combined)

func _publication_ready()->Array:
	var began:=Time.get_ticks_usec();var ready:Array=[]
	var building_ranks:Dictionary={};var pruned:=0
	var paths_checked:=0;var prefix_checks:=0;var eligible_calls:=0
	# At most one ready item per admitted closure. A collision-owned waiting
	# head retains its consumption cursor. A separate bounded scan lets ready
	# siblings sharing the same model progress without rebuilding/sorting demand.
	for path:String in _jobs:
		paths_checked+=1
		# A reusable cached model is not this task's accepted publication result.
		# Restored model_verified flags must not bypass the new lease/CPU handoff.
		var job:Dictionary=_jobs[path]
		if not job.get("accepted",false) or not _prepared_paths.has(path) or path_errors.has(path):continue
		if job.has("collision_staged"):_prune_publication_packets(job)
		# Fair publication can select only the earliest READY house at a visual
		# priority. A native house path contains that one atomic closure. Its
		# first demanded rank is a lower bound, including staged/private members:
		# once an earlier house is ready, checking this one cannot change choice.
		# Never apply this to shared model paths, safety priorities, stale ranks,
		# or when the earlier house was blocked. Re-evaluate on every selection.
		if fair_publication_enabled and _candidates_revision==_demand_revision and path.begins_with("reference:building:"):
			var first:Dictionary=_path_first.get(path,EMPTY_DEMAND)
			if not first.is_empty():
				var priority:int=_demanded_priority.get(first.record.uuid,2147483647)
				if priority>=0 and building_ranks.has(priority) and int(_demanded_rank.get(first.record.uuid,-1))>=int(building_ranks[priority]):
					pruned+=1;continue
		var instance:Dictionary=job.get("instance_preparation",EMPTY_DEMAND)
		if not instance.is_empty() and (not _demanded_by_id.has(instance.uuid) or instance_errors.has(instance.uuid)):
			instance.cursor.dispose();_record_instance_work(instance.cursor,true,instance.get("worker_prepared",false));job.erase("instance_preparation");instance=EMPTY_DEMAND
		var staged:Dictionary=job.get("staged",EMPTY_DEMAND)
		if not _publication_queues.has(path):
			# Refresh builds new path arrays; publication replaces rather than
			# mutates them. Cursors can borrow that immutable ordered generation.
			var rows:Array=_demanded_by_path.get(path,EMPTY_CANDIDATE)
			_publication_queues[path]={"items":rows if borrow_publication_rows_enabled else rows.duplicate(),"cursor":0,"scan":0}
			profile.publication_snapshot_rows_copied=int(profile.get("publication_snapshot_rows_copied",0))+(0 if borrow_publication_rows_enabled else rows.size())
		var queue:Dictionary=_publication_queues[path]
		if not instance.is_empty():
			# The existing private workspace can finish without scene dependencies.
			# A dependency wait belongs to its completed packet, never to this cursor
			# or the model's healthy siblings. Retain one active graph per job.
			var active:Dictionary=_demanded_by_id[instance.uuid]
			if active.get("published",false):continue
			eligible_calls+=1
			var runnable:=not _publication_discarded(active,staged) if independent_instance_preparation_enabled else _publication_eligible(active,staged)
			if runnable:
				ready.append(active)
				if str(active.get("group_id","")).begins_with("building:"):
					var priority:int=_demanded_priority.get(active.record.uuid,2147483647)
					building_ranks[priority]=mini(int(building_ranks.get(priority,2147483647)),int(_demanded_rank[active.record.uuid]))
			continue
		var checked:=0
		while queue.cursor<queue.items.size() and checked<64:
			var item:Dictionary=queue.items[queue.cursor];checked+=1;prefix_checks+=1
			if not _publication_discarded(item,staged):break
			queue.cursor+=1
		if queue.cursor>=queue.items.size():continue
		var at:int=maxi(int(queue.get("scan",queue.cursor)),int(queue.cursor))
		if at>=queue.items.size():at=queue.cursor
		var visited:=0
		var packet_readiness:Dictionary={}
		while checked<64 and visited<queue.items.size()-queue.cursor:
			var selected_at:=at
			var item:Dictionary=queue.items[at];checked+=1;visited+=1
			at+=1
			if at>=queue.items.size():at=queue.cursor
			queue.scan=at
			eligible_calls+=1
			var packet:Dictionary=job.get("collision_staged",{}).get(item.record.uuid,{})
			if not packet.is_empty():
				var first:String=packet.items[0].record.uuid
				if not packet_readiness.has(first):packet_readiness[first]=_publication_packet_ready(packet.items)
				if not packet_readiness[first]:continue
			if not _publication_eligible(item,staged):continue
			if packet.is_empty() and not _publication_workspace_available(job,path):continue
			queue.chosen=selected_at
			ready.append(item)
			if str(item.get("group_id","")).begins_with("building:"):
				var priority:int=_demanded_priority.get(item.record.uuid,2147483647)
				building_ranks[priority]=mini(int(building_ranks.get(priority,2147483647)),int(_demanded_rank[item.record.uuid]))
			break
	ready.sort_custom(func(a,b):return _demanded_rank[a.record.uuid]<_demanded_rank[b.record.uuid])
	var elapsed:=Time.get_ticks_usec()-began
	profile.ready_scan_us=int(profile.get("ready_scan_us",0))+elapsed
	profile.max_ready_scan_us=maxi(int(profile.get("max_ready_scan_us",0)),elapsed)
	profile.ready_heads=ready.size();profile.ready_scan_items=int(profile.get("ready_scan_items",0))+ready.size()
	profile.ready_building_skips=int(profile.get("ready_building_skips",0))+pruned
	# Count actual selection work, separately from the legacy returned-head count.
	# Prefix discard and eligible checks can visit the same candidate twice.
	profile.ready_selection_calls=int(profile.get("ready_selection_calls",0))+1
	profile.ready_paths_checked=int(profile.get("ready_paths_checked",0))+paths_checked
	profile.ready_prefix_discard_checks=int(profile.get("ready_prefix_discard_checks",0))+prefix_checks
	profile.ready_eligible_calls=int(profile.get("ready_eligible_calls",0))+eligible_calls
	return ready

func _publication_eligible(item:Dictionary,staged:Dictionary)->bool:
	return not _publication_discarded(item,staged) and _publication_dependencies_ready(item)

func _publication_dependencies_ready(item:Dictionary)->bool:
	var collision:Dictionary=_collision_publication_status(str(item.record.uuid))
	if collision.get("owned",false):
		if not str(collision.get("error","")).is_empty():
			_instance_failed(str(item.record.uuid),"提前碰撞发布失败："+str(collision.error));return false
		if collision.get("pending",false):
			profile.collision_publication_waits=int(profile.get("collision_publication_waits",0))+1
			return false
	return _runtime_supports_ready(str(item.record.uuid))

func _main_thread_budget_usec()->int:
	var interactive:=clampi(interactive_budget_override_usec,1000,8000) if interactive_budget_override_usec>0 else INTERACTIVE_BUDGET_US
	if force_covered_loading_budget and _map.get_viewport().disable_3d:return covered_loading_budget_usec
	if _covered_loading_ready():return covered_loading_budget_usec
	if _entry_loading_allowed() and _map.get_viewport().disable_3d:return covered_loading_budget_usec
	# A pending transfer alone is not proof that its opaque cover has been drawn.
	# Bind the larger budget to this queue's live same-map transaction. Cross-map
	# loaders own their own budgets and activate Deferred only after committing.
	if not is_instance_valid(_host) or not _host.is_inside_tree():return interactive
	if not "_transfer_pending" in _host or not _host._transfer_pending:return interactive
	if not "_local_transfer" in _host or not "_transfer_request_serial" in _host:return interactive
	var context:Dictionary=_host._local_transfer
	if context.is_empty() or context.get("cancelled",false):return interactive
	if not context.get("scope_applied",false) or not _demand_scope.has(context.get("demand_id","")):return interactive
	if context.get("map")!=_map or context.get("deferred")!=self:return interactive
	if context.get("request")!=_host._transfer_request_serial:return interactive
	var cover:Variant=context.get("cover")
	if not is_instance_valid(cover) or not cover is TransferLoading:return interactive
	if not cover.is_opaque_drawn():return interactive
	var viewport:=_host.get_viewport()
	if cover.get_viewport()!=viewport or not viewport.disable_3d:return interactive
	# Same-map transfer retains its established 16 ms allowance. Only the
	# initial loading cover may use its independently configured budget.
	return TRANSFER_COVERED_BUDGET_US

static func automatic_loading_worker_limit(logical_threads:int)->int:
	return clampi(floori(float(logical_threads)*.5),2,6)

func _restore_uncovered_worker_capacity()->void:
	# Transaction cleanup can run after this queue stopped processing. Restore
	# synchronously, but never raise capacity from a scope setter before dispatch.
	if _saved_interactive_worker_limit>=0 and _main_thread_budget_usec()<COVERED_LOADING_BUDGET_US:
		_update_loading_worker_capacity(INTERACTIVE_BUDGET_US)

func _update_loading_worker_capacity(budget_usec:int)->void:
	var processors:=OS.get_processor_count()
	var configured:=clampi(loading_worker_limit,2,6) if loading_worker_limit>0 else automatic_loading_worker_limit(processors)
	var covered:=budget_usec>=COVERED_LOADING_BUDGET_US
	if _admission.worker_limit==0:
		# Tests and owners may explicitly disable dispatch, including mid-load.
		# Never revive that queue by applying or restoring an automatic capacity.
		_saved_interactive_worker_limit=-1
	elif covered:
		if _saved_interactive_worker_limit<0:_saved_interactive_worker_limit=_admission.worker_limit
		_admission.worker_limit=configured
	elif _saved_interactive_worker_limit>=0:
		_admission.worker_limit=_saved_interactive_worker_limit;_saved_interactive_worker_limit=-1
	# Capacity changes only gate future reservations. Already admitted live and
	# completed jobs keep their slots/bytes until normal consumption or cancel.
	profile.worker_capacity={"mode":"disabled" if _admission.worker_limit==0 else ("covered_loading" if covered else "interactive"),"logical_threads":processors,"loading_override":loading_worker_limit,"loading_configured":configured,"effective_limit":_admission.worker_limit,"interactive_limit":_saved_interactive_worker_limit if _saved_interactive_worker_limit>=0 else _admission.worker_limit,"byte_limit":_admission.byte_limit}

static func _account_work_unit(timing:Dictionary,began:int)->void:
	var elapsed:=Time.get_ticks_usec()-began
	timing.units+=1;timing.unit_us+=elapsed;timing.max_unit_us=maxi(timing.max_unit_us,elapsed)

func _record_main_thread_budget(budget:int,began:int,acceptance:Dictionary,publication:Dictionary)->void:
	# The clock starts at this service's frame entry: elapsed_us includes demand,
	# join, dispatch, acceptance, publication, release and bounded refill. The
	# unit counters separate acceptance/publication; this is not GPU/frame time.
	var mode:="covered_loading" if budget>=COVERED_LOADING_BUDGET_US else "interactive"
	if not profile.has("main_thread_budgets"):profile.main_thread_budgets={}
	if not profile.main_thread_budgets.has(mode):
		profile.main_thread_budgets[mode]={"budget_us":budget,"frames":0,"elapsed_us":0,"max_elapsed_us":0,"over_budget_frames":0,"acceptance_units":0,"acceptance_us":0,"max_acceptance_unit_us":0,"publication_units":0,"publication_us":0,"max_publication_unit_us":0}
	var counters:Dictionary=profile.main_thread_budgets[mode]
	var elapsed:=Time.get_ticks_usec()-began
	counters.frames+=1;counters.elapsed_us+=elapsed;counters.max_elapsed_us=maxi(counters.max_elapsed_us,elapsed)
	if elapsed>budget:counters.over_budget_frames+=1
	counters.acceptance_units+=acceptance.units;counters.acceptance_us+=acceptance.unit_us
	counters.max_acceptance_unit_us=maxi(counters.max_acceptance_unit_us,acceptance.max_unit_us)
	counters.publication_units+=publication.units;counters.publication_us+=publication.unit_us
	counters.max_publication_unit_us=maxi(counters.max_publication_unit_us,publication.max_unit_us)
	profile.main_thread_budget_mode=mode;profile.main_thread_budget_us=budget
	profile.max_publish_us=maxi(profile.max_publish_us,elapsed)

func _publish_ready(began:int,budget_usec:int=INTERACTIVE_BUDGET_US)->Dictionary:
	var timing:Dictionary={"units":0,"unit_us":0,"max_unit_us":0}
	_defer_demand_removal=true
	_deferred_removal_items.clear()
	# Once admitted, advance at least one indivisible publication unit. _process
	# admits this stage only with time remaining after bookkeeping/acceptance;
	# explicit direct callers retain their forced-progress soft-slice contract.
	while timing.units==0 or Time.get_ticks_usec()-began<budget_usec:
		var heads:=_publication_ready()
		if heads.is_empty():break
		var item:Dictionary=_publication_order.choose(heads,_demanded_priority,_demanded_rank,_jobs) if fair_publication_enabled else heads[0]
		if item.path!=heads[0].path:profile.fair_publication_units=int(profile.get("fair_publication_units",0))+1
		if item.get("published",false) or instance_errors.has(item.record.uuid) or path_errors.has(item.path):continue
		var unit_began:=Time.get_ticks_usec()
		var publication_id:String=item.record.uuid
		var pixel_job:Dictionary=_jobs.get(item.path,{})
		if not item.get("native_reference",false) and not _publication_template_current(item.path,pixel_job):
			# published callbacks can replace a global template within this same
			# slice, after the frame-start check. Do not instantiate that unrelated
			# allocation or reconstruct its missing captures on the scene thread.
			_discard_job(item.path);_prepared_paths.erase(item.path)
			profile.model_template_retries=int(profile.get("model_template_retries",0))+1
			_account_work_unit(timing,unit_began);continue
		if CollisionGeometry.enabled and not item.get("native_reference",false):
			var mode:int=CollisionGeometry.record_mode(item.record)
			var covered:int=int(pixel_job.get("result",{}).get("collision_geometry_mode",CollisionGeometry.ALL))
			if mode==CollisionGeometry.UNKNOWN or mode>covered:
				_discard_job(item.path);_prepared_paths.erase(item.path)
				profile.geometry_requirement_retries=int(profile.get("geometry_requirement_retries",0))+1
				_account_work_unit(timing,unit_began);continue
		if pixel_job.has("pixel_consumer") and not Prefab.tickets_valid(pixel_job.get("pixel_tickets",{}),pixel_job.get("result",{}).get("prefab_texture_packet",{}).get("sources",{})):
			_retry_pixel_job(item.path,{},"Resident texture changed before publication");_account_work_unit(timing,unit_began);continue
		if pixel_job.get("collision_staged",{}).has(publication_id):
			var packet:Dictionary=pixel_job.collision_staged[publication_id]
			_publish_items(packet.items,packet.specs)
			_account_work_unit(timing,unit_began)
			continue
		if pixel_job.has("instance_preparation"):
			var revision:=_demand_revision
			_advance_instance_specs(item,pixel_job,unit_began,maxi(1,budget_usec-(Time.get_ticks_usec()-began)))
			_account_work_unit(timing,unit_began)
			if _demand_revision!=revision:break
			continue
		if not _publication_workspace_available(pixel_job,item.path,true):break
		var prefab_parts:Variant={} if preload("res://scripts/world3d/load_trace.gd").enabled else null
		var record_pixels:Dictionary=pixel_job.get("result",{}).get("prefab_texture_packet",{})
		if (material_publication_slices_enabled and prepared_material_slicing_enabled
			and not preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures
			and (not item.record.has("house_prefab") or not item.record.get("surface_paint",[]).is_empty()) and not record_pixels.is_empty()):
			if not pixel_job.has("streamed_texture_owners"):pixel_job.streamed_texture_owners={};pixel_job.streamed_texture_scope={}
			var texture_phase:int=preload("res://scripts/world3d/material_publication.gd").step_record_prepared(item.record,_doc.load_paint_validation,pixel_job.streamed_texture_owners,record_pixels,pixel_job.streamed_texture_scope)
			if texture_phase!=0:
				if texture_phase<0:
					_instance_failed(publication_id,"区块纹理准备失败："+publication_id)
					if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
				else:
					var queue:Dictionary=_publication_queues[item.path];queue.scan=queue.chosen
				var elapsed:int=Time.get_ticks_usec()-unit_began
				profile.record_texture_units=int(profile.get("record_texture_units",0))+1
				profile.record_texture_us=int(profile.get("record_texture_us",0))+elapsed
				profile.max_record_texture_unit_us=maxi(int(profile.get("max_record_texture_unit_us",0)),elapsed)
				preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.record_texture_step",unit_began,{"uuid":publication_id,"phase":texture_phase})
				_account_work_unit(timing,unit_began);continue
		if item.record.has("house_prefab"):
			var prefab_published:=false
			var prepared:Dictionary=_jobs.get(item.path,{}).get("result",{}).get("prefab_cpu",{}).get(item.record.house_prefab.sha256,{})
			var textures:Dictionary=_jobs.get(item.path,{}).get("result",{}).get("prefab_texture_packet",{})
			# CPU preparation does not pay the main-thread texture upload cost.
			# Keep the admitted image owner while advancing the same material slices.
			if (material_publication_slices_enabled
				and ((textures.is_empty() and not Prefab._meshes.has(item.record.house_prefab.sha256))
					or (not textures.is_empty() and prepared_material_slicing_enabled))
				and prepared.get("sha256")==item.record.house_prefab.sha256 and prepared.get("data") is Dictionary
				and prepared.get("geometry_keys",[]).size()==prepared.data.meshes.size()
				and prepared.get("collision_faces",[]).size()==prepared.data.meshes.size()):
				if not pixel_job.has("material_textures"):pixel_job.material_textures={}
				if not textures.is_empty() and not pixel_job.has("material_scope"):pixel_job.material_scope={}
				var publication=preload("res://scripts/world3d/material_publication.gd")
				var phase:int
				if textures.is_empty():phase=publication.step(prepared.data.materials,_doc.load_paint_validation,_doc.load_material_pool,pixel_job.material_textures)
				elif combined_material_publication_enabled:
					phase=publication.step_and_publish_prepared(item.record,prepared,_doc.load_paint_validation,_doc.load_material_pool,pixel_job.material_textures,textures,pixel_job.material_scope,prefab_parts)
					prefab_published=phase==publication.READY
					if prefab_published:profile.combined_material_publications=int(profile.get("combined_material_publications",0))+1
				else:phase=publication.step_prepared(item.record,prepared.data.materials,_doc.load_paint_validation,_doc.load_material_pool,pixel_job.material_textures,textures,pixel_job.material_scope)
				if phase!=0:
					if phase<0:
						_instance_failed(publication_id,"预制件材质准备或发布失败："+publication_id)
						if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
					else:
						# Revisit this ready member next turn; all readiness/collision and
						# demand-priority checks still run. A demand revision rebuilds it.
						var queue:Dictionary=_publication_queues[item.path];queue.scan=queue.chosen
					var elapsed:int=Time.get_ticks_usec()-unit_began
					profile.material_preparation_units=int(profile.get("material_preparation_units",0))+1
					profile.material_preparation_us=int(profile.get("material_preparation_us",0))+elapsed
					profile.max_material_preparation_unit_us=maxi(int(profile.get("max_material_preparation_unit_us",0)),elapsed)
					preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.material_step",unit_began,{"uuid":publication_id,"path":item.path,"phase":phase})
					_account_work_unit(timing,unit_began);continue
			if not prefab_published and not preload("res://scripts/world3d/house_prefab.gd").publish_prepared(item.record,prepared,_doc.load_paint_validation,_doc.load_material_pool,prefab_parts,textures,pixel_job.get("material_scope")):
				textures={};prepared={}
				_instance_failed(item.record.uuid,"后台预制件数据无法发布："+item.record.uuid);_stage_building(item,[])
				_account_work_unit(timing,unit_began);continue
			textures={};prepared={}
		var prefab_finished:=Time.get_ticks_usec()
		var instance_parts:Variant={} if preload("res://scripts/world3d/load_trace.gd").enabled else null
		if not item.get("native_reference",false):
			var cursor:=preload("res://scripts/world3d/asset_instance_preparation.gd").new()
			var texture_scope:=_begin_record_texture_scope(item,pixel_job)
			if not texture_scope.ok:
				_instance_failed(publication_id,"区块纹理在实例化前改变："+publication_id)
				if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
				_account_work_unit(timing,unit_began);continue
			cursor.begin(_doc,item.record,pixel_job.publication_template_owner)
			preload("res://scripts/world3d/material_publication.gd").end_record_scope(texture_scope)
			pixel_job.instance_preparation={"uuid":publication_id,"cursor":cursor,"phase":"asset","prefab_us":prefab_finished-unit_began,"instance_us":0,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts,"worker_prepared":false}
		else:
			var cursor:RefCounted
			var entry:Dictionary=Prefab._meshes.get(item.record.house_prefab.sha256,{}) if item.record.has("house_prefab") else {}
			# A job with a record-specific texture handoff must still open its
			# existing scope and reacquire the resulting prefab owner through _mesh.
			# The trusted immutable route with no such handoff has no texture
			# validation or scope side effects to repeat after publication above.
			var direct_textured:bool=item.record.has("house_prefab") and not pixel_job.has("streamed_texture_owners") and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
			if native_prefab_direct_specs_enabled and item.record.has("house_prefab") and PrefabSpecs.supports(item.record,entry,_local_collision_order(item),direct_textured) and _doc.load_immutable_records:
				# Geometry publication above already chose the canonical shared owner.
				# Project this instance directly instead of constructing, inspecting
				# and freeing a temporary MeshInstance3D for the same fields.
				cursor=PrefabSpecs.new();cursor.begin(item.record,entry,int(item.get("draw_order",0)))
				profile.native_prefab_direct_instances=int(profile.get("native_prefab_direct_instances",0))+1
				profile.instance_nodes_avoided=int(profile.get("instance_nodes_avoided",0))+1
			else:
				var texture_scope:=_begin_record_texture_scope(item,pixel_job)
				if not texture_scope.ok:
					_instance_failed(publication_id,"区块纹理在实例化前改变："+publication_id)
					if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
					_account_work_unit(timing,unit_began);continue
				var holder:Node3D=_doc._mesh(item.record,true,instance_parts)
				preload("res://scripts/world3d/material_publication.gd").end_record_scope(texture_scope)
				if _instance_error(holder,item):_account_work_unit(timing,unit_began);continue
				cursor=preload("res://scripts/world3d/instance_spec_preparation.gd").new()
				cursor.begin(holder,_local_collision_order(item),int(item.get("draw_order",0)))
			pixel_job.instance_preparation={"uuid":publication_id,"cursor":cursor,"phase":"spec","prefab_us":prefab_finished-unit_began,"instance_us":Time.get_ticks_usec()-prefab_finished,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts}
		if CompletedTrace.enabled:CompletedTrace.record(item.path,pixel_job.token.get_instance_id(),"private_started",{"uuid":publication_id,"phase":pixel_job.instance_preparation.phase})
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.instance_begin",unit_began,{"uuid":publication_id,"path":item.path,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts})
		var revision:=_demand_revision
		_advance_instance_specs(item,pixel_job,unit_began,maxi(1,budget_usec-(Time.get_ticks_usec()-began)))
		_account_work_unit(timing,unit_began)
		if _demand_revision!=revision:break
	_defer_demand_removal=false
	if not _deferred_removal_items.is_empty():
		var remove_started:=Time.get_ticks_usec()
		var removed_count:=_deferred_removal_items.size()
		_remove_published_demand(_deferred_removal_items)
		_deferred_removal_items.clear()
		profile.deferred_demand_removal_units=int(profile.get("deferred_demand_removal_units",0))+removed_count
		profile.publication_remove_batch_us=int(profile.get("publication_remove_batch_us",0))+Time.get_ticks_usec()-remove_started
	profile.publication_units=int(profile.get("publication_units",0))+int(timing.units)
	return timing

const INSTANCE_WORK_FIELDS:={"namespace_nodes_visited":"instance_namespace_nodes_visited","component_node_steps":"instance_component_node_steps","finish_nodes_visited":"instance_finish_nodes_visited","finish_visuals_registered":"instance_finish_visuals_registered","nodes_visited":"instance_projection_nodes_visited","nodes_freed":"instance_projection_nodes_freed","subtree_free_calls":"instance_cancel_subtree_free_calls","meshes_projected":"instance_meshes_projected"}
func _record_instance_work(cursor:RefCounted,cancelled:bool=false,worker_prepared:bool=false)->void:
	# One handoff per completed/cancelled cursor, never a per-node profile update.
	# Worker template packets use the same profile; these are accepted cursor
	# totals, not a claim to include discarded worker packets never adopted here.
	var work:Dictionary=cursor.profile
	for source:String in work:
		if not INSTANCE_WORK_FIELDS.has(source):continue
		var target_key:String=INSTANCE_WORK_FIELDS[source]
		profile[target_key]=int(profile.get(target_key,0))+int(work[source])
		if worker_prepared:profile["worker_"+target_key]=int(profile.get("worker_"+target_key,0))+int(work[source])
	var stage_key:="instance_work_cancelled_stages" if cancelled else "instance_work_completed_stages"
	profile[stage_key]=int(profile.get(stage_key,0))+1

func _begin_record_texture_scope(item:Dictionary,job:Dictionary)->Dictionary:
	if not job.has("streamed_texture_owners"):return {"ok":true}
	return preload("res://scripts/world3d/material_publication.gd").begin_record_scope(item.record,job.result.get("prefab_texture_packet",{}),job.streamed_texture_owners,job.streamed_texture_scope)

func _advance_instance_specs(item:Dictionary,job:Dictionary,unit_began:int,budget_usec:int)->void:
	var preparation:Dictionary=job.instance_preparation
	if preparation.get("phase","")=="asset":
		var asset:RefCounted=preparation.cursor;var began:=Time.get_ticks_usec()
		var texture_scope:=_begin_record_texture_scope(item,job)
		if not texture_scope.ok:
			asset.dispose();job.erase("instance_preparation");_instance_failed(item.record.uuid,"区块纹理在实例化期间改变："+item.record.uuid)
			if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
			return
		var ready:bool=asset.advance(budget_usec)
		preload("res://scripts/world3d/material_publication.gd").end_record_scope(texture_scope)
		var elapsed:=Time.get_ticks_usec()-began
		profile.asset_instance_units=int(profile.get("asset_instance_units",0))+1
		profile.max_asset_instance_unit_us=maxi(int(profile.get("max_asset_instance_unit_us",0)),elapsed)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.asset_instance_step",began,{"uuid":item.record.uuid,"ready":ready})
		if not ready:
			return # The active UUID is selected directly on its next turn.
		_record_instance_work(asset)
		var holder:Node3D=asset.take_holder()
		if _instance_error(holder,item):job.erase("instance_preparation");return
		preparation.instance_us=asset.profile.elapsed_us;preparation.instance_slices=asset.profile.slices
		var prepared_specs:=preload("res://scripts/world3d/instance_spec_preparation.gd").new()
		prepared_specs.begin(holder,_local_collision_order(item),int(item.get("draw_order",0)))
		preparation.cursor=prepared_specs;preparation.phase="spec"
		budget_usec=maxi(1,budget_usec-elapsed)
	var cursor:RefCounted=preparation.cursor;var began:=Time.get_ticks_usec()
	var ready:bool=cursor.advance(budget_usec)
	var elapsed:=Time.get_ticks_usec()-began
	profile.instance_spec_units=int(profile.get("instance_spec_units",0))+1
	profile.instance_spec_us=int(profile.get("instance_spec_us",0))+elapsed
	profile.max_instance_spec_unit_us=maxi(int(profile.get("max_instance_spec_unit_us",0)),elapsed)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.instance_specs",began,{"uuid":item.record.uuid,"ready":ready})
	if not ready:
		return # The active UUID is selected directly on its next turn.
	_record_instance_work(cursor,false,preparation.get("worker_prepared",false))
	var specs:Array=cursor.specs
	if CompletedTrace.enabled:CompletedTrace.record(item.path,job.token.get_instance_id(),"private_finished",{"uuid":str(item.record.uuid),"specs":specs.size(),"worker_prepared":preparation.get("worker_prepared",false)})
	job.erase("instance_preparation")
	var append_began:=Time.get_ticks_usec()
	if not str(item.get("group_id","")).is_empty():_stage_building(item,specs)
	else:_publish_items([item],specs)
	var packet:Dictionary=job.get("collision_staged",{}).get(item.record.uuid,{})
	if not packet.is_empty() and preparation.get("worker_prepared",false):packet.worker_prepared=true
	var publication:={"uuid":item.record.uuid,"path":item.path,"group_id":str(item.get("group_id","")),"prefab_us":preparation.prefab_us,"instance_us":preparation.instance_us,"collect_us":cursor.profile.elapsed_us,"collect_slices":cursor.profile.slices,"preparation_spans_frames":cursor.profile.slices>1,"append_us":Time.get_ticks_usec()-append_began,"elapsed_us":Time.get_ticks_usec()-unit_began,"covered":_main_thread_budget_usec()>=COVERED_LOADING_BUDGET_US}
	publication.instance_slices=int(preparation.get("instance_slices",1))
	publication.preparation_spans_frames=publication.preparation_spans_frames or publication.instance_slices>1
	for field:String in ["prefab_parts_ms","instance_parts_ms"]:
		if preparation[field]!=null:publication[field]=preparation[field]
	if int(publication.elapsed_us)>int(profile.get("slowest_publication",{}).get("elapsed_us",0)):profile.slowest_publication=publication
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.publication",unit_began,publication)

func _local_collision_order(item:Dictionary)->bool:
	return collision_first_enabled and _collision_entry_supported(item) and preload("res://scripts/world3d/collision_instance_preparation.gd")._supported_record(item.record) and _collision_publication_status(str(item.record.uuid)).get("owned",false)

func _instance_error(holder:Node3D,item:Dictionary)->bool:
	if not holder.has_meta("missing_asset") and not holder.has_meta("paint_error") and not holder.has_meta("tile_error"):return false
	profile.instance_failed_holder_free_calls=int(profile.get("instance_failed_holder_free_calls",0))+1
	holder.free();_instance_failed(str(item.record.uuid),"后台物件构建失败："+str(item.record.uuid))
	if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
	return true

static func _manifest_matches(path:String,expected:Dictionary)->bool:
	if expected.is_empty() or preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return true
	var current:Dictionary=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(path)
	return current.get("known",false) and current.get("json_sha256")==expected.get("json_sha256") and current.get("file_length")==expected.get("file_length")

static func _native_private(packed:PackedScene,path:String,token:RefCounted,manifest:Dictionary,faces:bool,geometry_mode:int=CollisionGeometry.ALL,prepack:bool=false,direct_material_plan:bool=false,published_product:bool=false)->Dictionary:
	if token!=null and token.is_cancelled():return {"error":ERR_SKIP,"cancelled":true}
	var began:=Time.get_ticks_usec()
	var scene:Node=Compiled.instantiate(packed)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.compiled_instantiate",began,{"path":path})
	var result:Dictionary={"error":ERR_INVALID_DATA,"scene":scene}
	if scene==null:return result
	began=Time.get_ticks_usec()
	var captured:=_capture_static_meshes(scene,faces,token,geometry_mode)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.cpu_capture",began,{"path":path,"collision_faces":faces})
	result.capture=captured
	if not captured.error.is_empty():
		result.error=ERR_SKIP if captured.get("cancelled",false) else ERR_INVALID_DATA
		result.cancelled=captured.get("cancelled",false);return result
	# The reader's one full source SHA follows this callback, covering both
	# instantiation/capture and the final immutable classification observation.
	if not published_product and not _manifest_matches(path,manifest):result.error=ERR_BUSY;return result
	if token!=null and token.is_cancelled():result.error=ERR_SKIP;result.cancelled=true;return result
	if direct_material_plan:
		# This frozen route owns a detached native scene and its resource graph.
		# Partial plans stay in the packet for the existing main-thread drainer.
		var plan_began:=Time.get_ticks_usec()
		result.native_texture_plan=preload("res://scripts/world3d/model_texture_direct_plan.gd").prepare(scene,token)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.native_texture_plan_prepare",plan_began,{"path":path,"state":result.native_texture_plan.get("state",""),"uses":result.native_texture_plan.get("names",[]).size(),"materials":result.native_texture_plan.get("materials",[]).size()})
		if result.native_texture_plan.get("state")=="cancelled":result.error=ERR_SKIP;result.cancelled=true;return result
	if prepack:
		# Reader retains the original packed owner on success, failure and cancel.
		if scene.has_meta("_compiled_resource_owner"):scene.remove_meta("_compiled_resource_owner")
		Assets._own(scene,scene)
		var prepared:=PackedScene.new();var pack_started:=Time.get_ticks_usec()
		var error:=prepared.pack(scene)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.worker_native_pack",pack_started,{"path":path})
		result.prepacked=prepared
		if error!=OK:result.error=error;return result
		if token!=null and token.is_cancelled():result.error=ERR_SKIP;result.cancelled=true;return result
	result.error=OK;return result

static func _prepare_fixed_scene(path:String,digest:String,token:RefCounted,manifest:Dictionary,faces:bool,root:String,candidate:Dictionary,geometry_mode:int=CollisionGeometry.ALL,native_only:bool=false,worker_prepack:bool=false,direct_material_plan:bool=false)->Dictionary:
	var began:=Time.get_ticks_usec()
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	var native_package:bool=native_only
	var confined:bool=preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path,root) if native_package else preload("res://scripts/world3d/map_paths.gd").allowed(path,root)
	if root.is_empty() or not confined:return {"error":"素材路径无效："+path}
	if native_package and digest.is_empty():digest=str(candidate.get("source_sha",""))
	if not digest.is_empty() and (not Assets._valid_source_digest(digest) or candidate.get("source_sha")!=digest):return {"error":"素材已验证来源与原生候选不符："+path}
	if (digest.is_empty() and manifest.is_empty()) or (not native_package and not _manifest_matches(path,manifest)):return {"error":"素材边界在后台准备前发生变化："+path}
	var prepack:bool=worker_prepack and native_package
	var packet:=CompiledPreparation.read(path,candidate,root,_native_private.bind(path,token,manifest,faces,geometry_mode,prepack,direct_material_plan and native_package and not prepack and bool(candidate.get("direct_template_reuse_safe",false)),native_only),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),not native_only,"",native_only)
	var result:Dictionary={"error":"","native_packet":packet,"elapsed_us":Time.get_ticks_usec()-began}
	if token!=null and token.is_cancelled():result.error="素材准备已取消";result.cancelled=true;return result
	if packet.get("fallback_required",false):return result # Main validates + re-admits raw.
	if packet.get("error",ERR_INVALID_DATA)!=OK:
		result.error="原生素材准备失败："+path+" "+str(packet.get("cache_reason",packet.get("error")))
		return result
	var private_result:Dictionary=packet.get("private_preparation",{})
	if not is_instance_valid(private_result.get("scene")):result.error="原生素材缺少私有场景："+path;return result
	result.merge(private_result.get("capture",{}))
	result.merge({"error":"","scene":private_result.scene,"source_digest":packet.source_digest,"compiled":true,"compiled_read_us":packet.get("cache_us",0)},true)
	if private_result.has("prepacked"):result.prepacked=private_result.prepacked
	if private_result.has("native_texture_plan"):result.native_texture_plan=private_result.native_texture_plan
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.prepare",began,{"path":path,"fixed_native":true})
	return result

static func prepare_scene(path:String,digest:String,token:RefCounted=null,expected_manifest:Dictionary={},collision_faces_required:bool=false,content_root:String="",raw_only:bool=false,geometry_mode:int=CollisionGeometry.ALL,pack_for_cache:bool=false,trusted_package:bool=false,native_only:bool=false)->Dictionary:
	var began:=preload("res://scripts/world3d/load_trace.gd").begin("deferred.prepare")
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if native_only and raw_only:return {"error":preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,"raw_import_not_allowed").error_message}
	if content_root.is_empty():
		if OS.get_thread_caller_id()!=OS.get_main_thread_id():return {"error":"后台素材准备缺少资源根快照："+path}
		content_root=preload("res://scripts/world3d/map_paths.gd").external_root()
	var native_package:bool=native_only
	var confined:bool=preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path,content_root) if native_package else preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root)
	if content_root.is_empty() or not confined:return {"error":"素材路径无效："+path}
	var Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
	if digest.is_empty() and not trusted_package and not native_package:
		if expected_manifest.is_empty():return {"error":"缺少后台素材边界快照："+path}
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备前发生变化："+path}
	var source_digest:=""
	if native_package:
		# Admission already required the published metadata. Reuse its identity
		# when available; otherwise the native reader's one index read supplies it.
		# No second index/descriptor read solely to rediscover the same identity.
		source_digest=digest if not digest.is_empty() else str(expected_manifest.get("native_source_sha",""))
		if not source_digest.is_empty() and not Assets._valid_source_digest(source_digest):return {"error":"素材缺少有效原生来源身份："+path}
		if source_digest.is_empty() and Assets._valid_source_digest(path.get_file().get_basename()):source_digest=path.get_file().get_basename()
	else:source_digest=preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path,digest) if trusted_package else FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.source_identity" if trusted_package else "deferred.source_sha",began,{"path":path})
	if not native_package and (source_digest.is_empty() or (not digest.is_empty() and source_digest!=digest)):return {"error":"素材在后台准备前发生变化："+path}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	# Strict transactions verify source bytes after private preparation as well.
	var compiled:Dictionary={"hit":false,"elapsed_us":0}
	if native_package:
		var candidate:Dictionary=expected_manifest.get("native_candidate",{})
		if candidate.is_empty():candidate=preload("res://scripts/world3d/compiled_asset_footprint.gd").candidate(path,content_root,source_digest,true)
		if candidate.is_empty() or (not source_digest.is_empty() and candidate.get("source_sha")!=source_digest):return {"error":preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,"native_footprint_missing_or_stale").error_message}
		var packet:=CompiledPreparation.read(path,candidate,content_root,Callable(),trusted_package,false,"",true)
		if packet.get("error",FAILED)!=OK or packet.get("fallback_required",false):
			return {"error":preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,str(packet.get("cache_reason","invalid_product"))).error_message,"native_packet":packet}
		compiled={"hit":true,"packed":packet.packed,"source_digest":packet.source_digest,"elapsed_us":int(packet.get("cache_us",0))}
	elif not raw_only:compiled=Compiled.read(path,source_digest,content_root,not source_digest.is_empty(),trusted_package)
	if native_only and not compiled.hit:
		return {"error":preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,str(compiled.get("reason","invalid_product"))).error_message,"native_packet":compiled}
	if native_package:
		if not compiled.hit or not Assets._valid_source_digest(compiled.get("source_digest","")):
			return {"error":preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,"native_identity_missing").error_message,"native_packet":compiled}
		source_digest=compiled.source_digest
	if not compiled.hit and not compiled.get("retained_resources",[]).is_empty():
		# Post-allocation schema/path failures are not resource-free misses.
		# Keep the charged native result for main-thread failure disposal.
		return {"error":"原生素材校验失败："+path,"native_packet":compiled}
	var owners:=preload("res://scripts/world3d/model_resource_owners.gd").new()
	owners.packed=compiled.get("packed")
	var scene:Node
	if not compiled.hit:
		# The index stores accepted model facts without the transient `known`
		# field. A nonempty model manifest is the existing static-route proof.
		var fallback:=_fallback_scene(path,token,content_root,trusted_package and not expected_manifest.is_empty() and expected_manifest.get("known",true))
		if not fallback.error.is_empty():return fallback
		owners=fallback.resource_owners
		fallback.erase("resource_owners")
		scene=fallback.scene
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	# Bind deferred classification to the same header after the potentially slow
	# full-file hash and parser read as well as before them.
	if not expected_manifest.is_empty() and not trusted_package and not native_package:
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备期间发生变化："+path,"scene":scene,"resource_owners":owners}
	# The queue admits static self-contained files only. Every node/resource here
	# belongs to this worker and has never entered a SceneTree or shared scene cache.
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	var captured:Dictionary={"error":""}
	var packed:PackedScene
	var generate_started:=Time.get_ticks_usec()
	if compiled.hit:
		scene=Compiled.instantiate(compiled.packed)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.compiled_instantiate",generate_started,{"path":path})
	if scene==null:return {"error":"素材构建失败："+path,"resource_owners":owners}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	var capture_started:=Time.get_ticks_usec()
	captured=_capture_static_meshes(scene,collision_faces_required,token,geometry_mode)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.cpu_capture",capture_started,{"path":path,"collision_faces":collision_faces_required})
	if not captured.error.is_empty():
		captured.scene=scene;captured.resource_owners=owners
		return captured
	if pack_for_cache and not compiled.hit:
		# This static graph is still exclusively worker-owned. Pack it here so
		# acceptance never performs a whole imported hierarchy traversal/pack.
		var pack_began:=Time.get_ticks_usec()
		Assets._own(scene,scene);packed=PackedScene.new()
		owners.packed=packed
		var code:=packed.pack(scene)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_pack",pack_began,{"path":path})
		if code!=OK:return {"error":"后台素材打包失败："+path,"scene":scene,"resource_owners":owners}
	var final_sha_started:=Time.get_ticks_usec()
	var final_digest:=source_digest if native_package or trusted_package else FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.source_binding" if trusted_package else "deferred.final_source_sha",final_sha_started,{"path":path})
	var final_confined:bool=preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path,content_root) if native_package else preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root)
	if final_digest!=source_digest or (not content_root.is_empty() and not final_confined):return {"error":"素材在后台准备期间发生变化："+path,"scene":scene,"resource_owners":owners}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	if packed!=null:
		# The private Node instances can retire on their own worker, but every
		# renderer Resource must survive until main has joined and synchronized.
		if scene!=null:
			Drainer._retain_visual_resources(scene,owners.visuals)
			var dispose_began:=Time.get_ticks_usec();scene.free();scene=null
			preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_private_disposal",dispose_began,{"path":path})
		captured.packed=packed
	else:captured.scene=scene
	captured.merge({"resource_owners":owners,"elapsed_us":Time.get_ticks_usec()-began,"source_digest":source_digest,"compiled":compiled.hit,"compiled_read_us":compiled.elapsed_us})
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.prepare",began,{"path":path})
	return captured

static func _fallback_scene(path:String,token:RefCounted,content_root:String,static_private:bool=false)->Dictionary:
	# Explicit source imports retain the full-material exclusive import gate.
	# Registration of extensions is a startup operation.
	var preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
	var waiting:=Time.get_ticks_usec()
	preparation.enter_raw_import(static_private)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.raw_import_wait",waiting,{"path":path})
	if token!=null and token.is_cancelled():
		preparation.leave_raw_import();return {"error":"素材准备已取消","cancelled":true}
	# A candidate miss can retry raw after waiting for another importer. Recheck
	# containment before allocating parser resources or reading the source.
	if content_root.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):
		preparation.leave_raw_import();return {"error":"素材路径无效："+path}
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var owners:=preload("res://scripts/world3d/model_resource_owners.gd").new()
	owners.document=document;owners.state=state
	preload("res://scripts/world3d/runtime_probe_controls.gd").configure_gltf(state)
	var began:=Time.get_ticks_usec()
	var code:=document.append_from_file(path,state,0,path.get_base_dir())
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_parse",began,{"path":path})
	if code!=OK:
		preparation.leave_raw_import();return {"error":"素材读取失败："+path+" "+error_string(code),"resource_owners":owners}
	if preload("res://scripts/world3d/asset_bounds_manifest.gd").has_native_identity(state.json):
		preparation.leave_raw_import();return {"error":"原生地图不能作为独立后台素材："+path,"resource_owners":owners}
	if token!=null and token.is_cancelled():
		preparation.leave_raw_import();return {"error":"素材准备已取消","cancelled":true,"resource_owners":owners}
	began=Time.get_ticks_usec()
	var scene:=Io.generate_scene(document,state,true)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.scene_generate",began,{"path":path})
	preparation.leave_raw_import()
	return {"error":"" if scene!=null else "素材构建失败："+path,"scene":scene,"resource_owners":owners}

static func _capture_static_meshes(scene:Node,faces_required:bool,token:RefCounted=null,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
	return preload("res://scripts/world3d/static_mesh_cpu_preparation.gd").capture(scene,faces_required,token,geometry_mode)

static func _packed_payload_bytes(value:Variant)->int:
	return preload("res://scripts/world3d/static_mesh_cpu_preparation.gd").packed_payload_bytes(value)

func _retire_stale_prepared(required:Dictionary)->void:
	# Dormant prepared flags own no Resource. Check them when demanded again,
	# before dispatch/publication, instead of revisiting all past models each frame.
	# Undemanded accepted jobs are still cancelled/disposed by _poll_jobs below.
	var checks:=0
	for path:String in (required if demanded_template_scan_enabled else _prepared_paths).keys():
		if not _prepared_paths.has(path) or path.begins_with("reference:"):continue
		checks+=1
		var job:Dictionary=_jobs.get(path,{})
		var stale_owner:bool=job.get("accepted",false) and not job.get("native",false) and not _publication_template_current(path,job)
		if not _cached_model_matches(path) or stale_owner:
			_prepared_paths.erase(path)
			if job.get("accepted",false):
				_discard_job(path)
				if stale_owner:profile.model_template_retries=int(profile.get("model_template_retries",0))+1
	profile.template_checks=int(profile.get("template_checks",0))+checks

static var phase_budget_guard_enabled:=true
func _process(_delta:float)->void:
	if not _active or _cancelled:return
	if not error.is_empty():
		_retire_failed_jobs()
		return
	var desired:=_main_thread_budget_usec()
	var budget:=FrameBudget.allowance("publication",desired,desired>=COVERED_LOADING_BUDGET_US)
	# Demand scans, stale-template disposal and scheduling are main-thread work
	# too. A denied lane must not perform them outside the frame ledger, nor
	# publish using the previous frame's demand set.
	if budget<=0:return
	var frame_began:=Time.get_ticks_usec()
	var stage:Dictionary={"at_us":frame_began}
	_update_loading_worker_capacity(desired)
	_refresh_demanded()
	var required:Dictionary=_demanded_by_path
	_retire_stale_prepared(required)
	stage.bookkeeping_us=Time.get_ticks_usec()-frame_began
	profile.frame_bookkeeping_us=stage.bookkeeping_us
	var poll_started:=Time.get_ticks_usec()
	_poll_jobs(required)
	stage.poll_us=Time.get_ticks_usec()-poll_started
	profile.last_poll_us=stage.poll_us
	var resume_started:=Time.get_ticks_usec()
	_resume_pixel_jobs(get_tree())
	stage.resume_us=Time.get_ticks_usec()-resume_started
	# Preserve the existing publication/dispatch ownership gate during handoff.
	if is_instance_valid(_host) and "_ready_for_play" in _host and not _host._ready_for_play and not _entry_loading_allowed() and not _covered_loading_ready():FrameBudget.charge("publication",frame_began);return
	# Refill before publication, while there is a bounded scheduling slice. A
	# slow indivisible upload must not push dispatch into unaccounted frame tail.
	_dispatch_deadline=mini(frame_began+budget,Time.get_ticks_usec()+maxi(100,budget/4))
	var dispatch_started:=Time.get_ticks_usec()
	_dispatch_jobs(get_tree());_dispatch_deadline=0
	stage.dispatch_us=Time.get_ticks_usec()-dispatch_started
	profile.last_dispatch_us=stage.dispatch_us
	# Covered initial entry owns publication until it is ready; ready results
	# keep their full byte reservation, preventing an unbounded result queue.
	var began:=frame_began
	var acceptance:Dictionary={"units":0,"unit_us":0,"max_unit_us":0}
	var accept_started:=Time.get_ticks_usec()
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if job.has("worker") or not job.has("result") or job.get("accepted",false) or job.result.get("waiting_pixels",false) or job.get("native_binding_pending",false):continue
		if (phase_budget_guard_enabled or acceptance.units>0) and Time.get_ticks_usec()-began>=budget:break
		var unit_began:=Time.get_ticks_usec()
		var result:Dictionary=job.result
		var acceptance_phase:=Time.get_ticks_usec()
		if not _geometry_coverage_current(path,result):
			# A new stronger consumer appeared while the private worker ran. Keep
			# its budget until the old resources are disposed, then re-admit the
			# complete model route; never fill missing arrays under a reuse lease.
			_discard_job(path);_prepared_paths.erase(path)
			profile.geometry_requirement_retries=int(profile.get("geometry_requirement_retries",0))+1
			_account_work_unit(acceptance,unit_began);continue
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.accept_coverage",acceptance_phase,{"path":path});acceptance_phase=Time.get_ticks_usec()
		if job.has("pixel_consumer"):
			var texture_packet:Dictionary=result.get("prefab_texture_packet",{})
			if not Prefab.tickets_valid(job.pixel_tickets,texture_packet.get("sources",{})):
				_retry_pixel_job(path,{},"Resident texture changed before acceptance");_account_work_unit(acceptance,unit_began);continue
			texture_packet.resident_textures=job.pixel_tickets.duplicate()
			texture_packet.uploaded_textures=_shared_images.textures(job.pixel_consumer)
		if result.has("scene") or result.has("packed"):
			var planned:bool=job.get("direct_material_plan",false)
			var plan_state:="";var plan_uses:=0
			if planned:
				var plan:Dictionary=result.get("native_texture_plan",{})
				plan_state=str(plan.get("state",""));plan_uses=plan.get("names",[]).size()
			var cached:bool
			if job.get("direct_template_reuse",false):cached=Assets.cache_direct_native_scene(path,result.scene,result.get("native_packet",{}).get("packed"),str(result.get("source_digest","")),result.get("native_texture_plan",{}))
			elif result.has("prepacked"):cached=Assets.cache_prepared_native_scene(path,result.scene,result.prepacked,result.get("native_packet",{}).get("packed"),str(result.get("source_digest","")))
			elif result.has("packed"):cached=Assets.cache_packed(path,result.packed,str(result.get("source_digest","")))
			else:cached=Assets.cache_scene(path,result.scene,str(result.get("source_digest","")))
			if not cached:
				job.result.erase("scene");_discard_job(path);_path_failed(path,"无法缓存后台素材："+path)
				_account_work_unit(acceptance,unit_began);continue
			_publish_native_texture_owners(path,job)
			if result.has("packed"):
				if result.has("resource_owners"):result.resource_owners.transfer_template(result.packed)
				profile.worker_packed_models=int(profile.get("worker_packed_models",0))+1
			if job.get("direct_template_reuse",false):profile.full_native_reused_templates=int(profile.get("full_native_reused_templates",0))+1
			if planned:
				if plan_state=="ready":
					profile.native_texture_plans=int(profile.get("native_texture_plans",0))+1
					profile.native_texture_plan_uses=int(profile.get("native_texture_plan_uses",0))+plan_uses
				else:profile.native_texture_plan_fallbacks=int(profile.get("native_texture_plan_fallbacks",0))+1
			if result.has("prepacked"):profile.worker_prepacked_native_models=int(profile.get("worker_prepacked_native_models",0))+1
			job.result.erase("scene");job.result.erase("packed");job.result.erase("prepacked");profile.models+=1
			var cache_key:="compiled_hits" if result.get("compiled",false) else "compiled_misses"
			profile[cache_key]=int(profile.get(cache_key,0))+1
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.accept_template",acceptance_phase,{"path":path});acceptance_phase=Time.get_ticks_usec()
		# Another map may have replaced/evicted this path while the CPU reuse
		# transaction ran. Retry preparation instead of consuming a different
		# template under the verified old geometry identity.
		if result.get("reused_model",false) and not _reuse_template_current(path,job,str(result.get("source_digest",""))):
			_prepared_paths.erase(path);_discard_job(path);_account_work_unit(acceptance,unit_began);continue
		if result.get("reused_model",false) and not _accept_reused_faces(job,result):
			_prepared_paths.erase(path);_discard_job(path);_account_work_unit(acceptance,unit_began);continue
		_accept_prepared_records(result)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.accept_records",acceptance_phase,{"path":path});acceptance_phase=Time.get_ticks_usec()
		if not job.get("native",false):preload("res://scripts/world3d/runtime_asset_cache_scope.gd").claim(_map,path)
		_remember_geometry_definitions(path,result)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.accept_definitions",acceptance_phase,{"path":path});acceptance_phase=Time.get_ticks_usec()
		if not job.get("native",false):
			job.publication_template_owner=Assets._scenes.get(path)
			if int(result.get("collision_geometry_mode",CollisionGeometry.ALL))==CollisionGeometry.ALL:
				_prepared_template_owners[path]=weakref(job.publication_template_owner)
			for uuid:String in job.get("publication_ids",[]):
				if _demanded_by_id.has(uuid):_demanded_by_id[uuid].model_verified=true
		job.accepted=true;_prepared_paths[path]=true;_publication_queues.erase(path);_scheduler_epoch+=1
		if CompletedTrace.enabled:CompletedTrace.record(path,job.token.get_instance_id(),"accepted")
		profile.worker_us+=int(result.get("elapsed_us",0))
		for key in ["capture_us","face_us","capture_bytes","face_bytes","captured_meshes","importer_surfaces","renderer_surfaces","skipped_geometry_nodes","index_validation_us","indices_checked","readback_wait_us","readback_main_us","readback_meshes"]:profile[key]=int(profile.get(key,0))+int(result.get(key,0))
		if result.has("source_digest"):source_signatures[path]=result.source_digest
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.accept_complete",acceptance_phase,{"path":path})
		_account_work_unit(acceptance,unit_began)
	stage.accept_us=Time.get_ticks_usec()-accept_started
	profile.last_accept_us=stage.accept_us
	# One clock covers both acceptance and publication. This is a soft slice,
	# not a deadline for indivisible packing, group append or signal callbacks.
	var publication:Dictionary={"units":0,"unit_us":0,"max_unit_us":0}
	var publication_started:=Time.get_ticks_usec()
	if not phase_budget_guard_enabled or Time.get_ticks_usec()-began<budget:
		publication=_publish_ready(began,budget)
	else:
		# An indivisible demand refresh/acceptance already consumed this slice.
		# Keep the accepted job and its lease for the next frame; do not stack a
		# second forced unit here. Direct _publish_ready callers retain their API.
		profile.phase_budget_deferrals=int(profile.get("phase_budget_deferrals",0))+1
	stage.publish_us=Time.get_ticks_usec()-publication_started
	profile.frame_publication_allowance_us=budget
	# Publication observers can teach a new building/support closure. Refresh
	# that revision in the next admitted frame, not for a second full scan in
	# this already expensive commit frame. Stale membership cannot release jobs.
	# A joined group still owns its bytes until its ready records have
	# been published or discarded. Slow publication cannot create an unbounded
	# CPU result backlog beside the GPU/resource pipeline.
	var jobs_before_release:=_jobs.size()
	for path:String in _jobs.keys() if _candidates_revision==_demand_revision else []:
		var job:Dictionary=_jobs[path]
		if job.get("accepted",false) and _job_consumed(job):_discard_job(path)
	# A consumed result may have held the last ready slot at the first dispatch.
	# Let its successor overlap the rest of this frame, but only inside the
	# ORIGINAL slice. Never rescan unchanged capacity or stale demand after a
	# publication observer, and never extend an indivisible upload's overrun.
	if _jobs.size()<jobs_before_release and _candidates_revision==_demand_revision and not _cancelled and error.is_empty():
		var refill_began:=Time.get_ticks_usec()
		if refill_began<frame_began+budget:
			var attempts_before:int=int(profile.get("dispatch_attempts",0))
			_dispatch_deadline=mini(frame_began+budget,refill_began+maxi(100,budget/4))
			_dispatch_jobs(get_tree());_dispatch_deadline=0
			stage.refill_us=Time.get_ticks_usec()-refill_began
			profile.same_frame_refill_calls=int(profile.get("same_frame_refill_calls",0))+1
			profile.same_frame_refill_attempts=int(profile.get("same_frame_refill_attempts",0))+int(profile.get("dispatch_attempts",0))-attempts_before
			profile.same_frame_refill_us=int(profile.get("same_frame_refill_us",0))+Time.get_ticks_usec()-refill_began
	stage.total_us=Time.get_ticks_usec()-frame_began
	if not profile.has("stage_ring"):profile.stage_ring=[]
	profile.stage_ring.append(stage)
	if profile.stage_ring.size()>1024:profile.stage_ring.pop_front()
	if stage.total_us>5000:
		if not profile.has("stage_slow"):profile.stage_slow=[]
		profile.stage_slow.append(stage)
		profile.stage_slow.sort_custom(func(a,b):return int(a.total_us)>int(b.total_us))
		if profile.stage_slow.size()>24:profile.stage_slow.resize(24)
	_record_main_thread_budget(desired,began,acceptance,publication)
	FrameBudget.charge("publication",frame_began)
	if is_complete():
		_update_loading_worker_capacity(INTERACTIVE_BUDGET_US)
		set_process(false)
		if not _completion_emitted:_completion_emitted=true;completed.emit()

func _retire_failed_jobs()->void:
	# Cancellation is cheap and immediate. Destruction is not: joined results
	# keep their owners and admission charge until a retirement slice is granted.
	for job:Dictionary in _jobs.values():job.token.cancel()
	var budget:=FrameBudget.allowance("retire",1000,false)
	if budget<=0:return
	var began:=Time.get_ticks_usec()
	var retired:=0
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if FrameBudget.enabled and retired>0 and Time.get_ticks_usec()-began>=budget:break
		if job.has("worker"):
			if job.worker.is_alive():continue
			job.result=job.worker.wait_to_finish()
			if CompletedTrace.enabled:CompletedTrace.joined(path,job.token.get_instance_id(),job.result)
			if is_instance_valid(_drainer):_drainer.forget(job.worker)
			job.erase("worker")
			Drainer.synchronize_transfer()
		_discard_job(path)
		retired+=1
	FrameBudget.charge("retire",began)
	if _jobs.is_empty():set_process(false)

func _candidate_for_job(path:String,root:String,digest:String)->Dictionary:
	var cached:Dictionary=_native_candidates.get(path,{})
	if not cached.is_empty() and cached.digest==digest:return cached.value
	var value:Dictionary=_path_first.get(path,{}).get("manifest",{}).get("native_candidate",{}) if require_native_products else {}
	if value.is_empty():value=preload("res://scripts/world3d/compiled_asset_footprint.gd").candidate(path,root,digest,preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
	if not digest.is_empty() and value.get("source_sha")!=digest:value={}
	_native_candidates[path]={"digest":digest,"value":value.duplicate(true)}
	profile.native_candidate_lookups=int(profile.get("native_candidate_lookups",0))+1
	return value

func _refresh_raw_memory(path:String)->Dictionary:
	return MemoryEstimate.estimate(path)

func _start_worker(worker:RefCounted,prepare:Callable)->int:
	return worker.start(prepare)

static func _retry_decision(job:Dictionary,result:Dictionary)->String:
	# The worker wrapper uses String errors; the reader packet has typed engine
	# errors. Never treat str(OK) as failure or arbitrary packed/fallback flags as
	# permission to allocate raw GLTF under the candidate's smaller reservation.
	var packet:Variant=result.get("native_packet")
	if not packet is Dictionary:return ""
	if job.get("stage")!="fixed_native":return "invalid"
	if packet.has("fallback_required"):
		if not result.get("error") is String or not result.error.is_empty():return "invalid"
		if not packet.get("error") is int or packet.error!=OK or not packet.fallback_required is bool or not packet.fallback_required or not packet.get("cache_reason") is String:return "invalid"
		# The preparation reader's preallocation misses have exactly this plain
		# control schema. Any scene/resource/extra marker makes it a fatal result.
		for key:Variant in packet:
			if key not in ["error","fallback_required","cache_reason"]:return "invalid"
		for key:Variant in result:
			if key not in ["error","native_packet","elapsed_us","records","dependencies","read_profile"]:return "invalid"
		var retained:Variant=result.get("retained_resources",[])
		if result.get("scene")!=null or not retained is Array or not retained.is_empty():return "invalid"
		return "retry"
	if packet.has("native_source_retry"):
		if not result.get("error") is String or result.error.is_empty():return "invalid"
		var candidate:Dictionary=job.get("candidate",{})
		if not packet.native_source_retry is bool or not packet.native_source_retry or not packet.get("error") is int or packet.error!=ERR_BUSY or not packet.get("packed") is PackedScene or not packet.get("compiled") is bool or not packet.compiled or not Compiled._sha(candidate.get("source_sha")) or not packet.get("source_digest") is String or packet.source_digest!=candidate.source_sha or not packet.get("cache_reason") is String or packet.cache_reason!="candidate_source_changed_after_read":return "invalid"
		# A previously published/reused identity remains authoritative. An unknown
		# first observation may retry under the original accessor-manifest guard.
		if not str(job.get("digest","")).is_empty():return "identity_changed"
		return "retry"
	return ""

func _road_batch_superseded(path:String,job:Dictionary)->bool:
	if not path.begins_with("reference:road_batch:"):return false
	var first:Dictionary=_path_first.get(path,{})
	if first.is_empty():return true
	var ids:Array=job.get("publication_ids",[])
	if ids.has(str(first.record.uuid)):return false
	var priority:=_path_priority(path)
	for id:String in ids:
		if _demanded_by_id.has(id) and int(_demanded_priority.get(id,2147483647))<=priority:return false
	return true

func _poll_jobs(required:Dictionary)->void:
	_texture_plan_catalog.poll()
	_retire_native_plan_claims(required)
	profile.texture_plan_catalog=_texture_plan_catalog.snapshot()
	profile.native_texture_metadata_reserved_bytes=_texture_plan_catalog.native_metadata_reserved_bytes
	# Retire completed/cancelled jobs independently; never wait for a slow sibling.
	profile.last_poll_join_us=0;profile.last_poll_sync_us=0
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if not required.has(path):job.token.cancel()
		elif _road_batch_superseded(path,job):
			# A page is an IO identity, not an inseparable model. A newly critical
			# road must not inherit the priority of an older background-only batch.
			if not job.token.is_cancelled():profile.road_batch_preemptions=int(profile.get("road_batch_preemptions",0))+1
			job.token.cancel()
		if job.has("worker"):
			if job.worker.is_alive():continue
			var join_started:=Time.get_ticks_usec()
			var result:Dictionary=job.worker.wait_to_finish()
			profile.last_poll_join_us=int(profile.get("last_poll_join_us",0))+Time.get_ticks_usec()-join_started
			if is_instance_valid(_drainer):_drainer.forget(job.worker)
			job.erase("worker")
			_record_pixel_packet(path,job,result)
			if result.has("parallel_cpu") and not job.get("native_binding_continuation",false):
				if not profile.has("parallel_cpu"):profile.parallel_cpu={"jobs":0,"geometry_us":0,"pixels_us":0,"overlap_us":0}
				profile.parallel_cpu.jobs+=1
				for field:String in ["geometry_us","pixels_us","overlap_us"]:profile.parallel_cpu[field]+=int(result.parallel_cpu[field])
			if CompletedTrace.enabled:CompletedTrace.joined(path,job.token.get_instance_id(),result)
			if job.get("native_binding_continuation",false):
				job.erase("native_binding_continuation");job.native_binding_pending=false;job.result=result
				if job.token.has_meta("prefab_continuation_result"):job.token.remove_meta("prefab_continuation_result")
				var binding:Dictionary=result.get("native_binding_profile",{})
				if not profile.has("native_model_binding"):profile.native_model_binding={"jobs":0,"elapsed_us":0,"sets":0,"unchanged":0}
				profile.native_model_binding.jobs+=1
				for field:String in ["elapsed_us","sets","unchanged"]:profile.native_model_binding[field]+=int(binding.get(field,0))
				if str(result.get("error","")).is_empty() and job.has("pixel_consumer") and not job.get("native_handoff_keys",[]).is_empty():
					if not _shared_images.handoff_streamed(job.pixel_consumer,result.get("prefab_texture_packet",{}).get("uploaded_textures",{}),job.native_handoff_keys):
						result.error="Native model textures were not accepted by streaming residency"
				if str(result.get("error","")).is_empty() and job.has("pixel_consumer"):
					_admission.park(path);_admission.shrink_joined(path,int(job.estimate.pixel_retained_bytes))
			elif job.get("pixel_continuation",false):
				job.erase("pixel_continuation")
				job.result.get("prefab_texture_packet",{}).clear()
				job.result.prefab_texture_packet=result
				job.result.waiting_pixels=result.get("waiting_pixels",false)
				job.result.error=result.get("error","")
				job.result.elapsed_us=int(job.result.get("elapsed_us",0))+int(result.get("continuation_us",0))
				if job.result.has("read_profile"):job.result.read_profile.prefab_texture_continuation=result.get("profile",{})
				for field:String in ["retry_pixels","source_revisions","cancelled"]:
					if result.has(field):job.result[field]=result[field]
				if job.token.has_meta("prefab_continuation_result"):job.token.remove_meta("prefab_continuation_result")
			else:job.result=result
			var sync_started:=Time.get_ticks_usec()
			# Native references return private arrays/Images. Optional pool textures
			# are already created via RenderingServer's thread-safe direct path,
			# with no queued scene/material setup to flush at this CPU join.
			if not job.get("native",false):
				var transfer_started:=Time.get_ticks_usec()
				Drainer.synchronize_transfer()
				profile.last_poll_sync_us=int(profile.get("last_poll_sync_us",0))+Time.get_ticks_usec()-transfer_started
			if not _entry_prefetch.is_empty():
				profile.entry_prefetch_joined_jobs=int(profile.get("entry_prefetch_joined_jobs",0))+1
				profile.entry_prefetch_sync_us=int(profile.get("entry_prefetch_sync_us",0))+Time.get_ticks_usec()-sync_started
				profile.entry_prefetch_last_ready_us=Time.get_ticks_usec()
			_admission.set_stage(path,"ready")
			if ready_worker_yield_enabled or job.get("native_binding_pending",false):_admission.park(path)
			if job.get("native",false) and job.has("pixel_consumer"):
				var retained:int=int(job.estimate.pixel_retained_bytes)-int(job.estimate.get("collision_workspace_bytes",0))+(SharedImages.HASH_SCRATCH if job.result.get("waiting_pixels",false) else 0)
				_admission.park(path);_admission.shrink_joined(path,retained)
			elif job.get("native",false) and int(job.estimate.get("collision_workspace_bytes",0))>0:
				_admission.park(path);_admission.shrink_joined(path,int(job.estimate.estimated_bytes)-int(job.estimate.collision_workspace_bytes))
			elif job.has("pixel_consumer") and job.result.get("waiting_pixels",false):_admission.park(path)
		if job.token.is_cancelled() or not required.has(path):
			_discard_job(path);continue
		if job.has("pixel_consumer") and job.result.get("retry_pixels",false) is bool and job.result.get("retry_pixels",false) and job.result.get("error") is String and not job.result.error.is_empty() and job.result.get("source_revisions",{}) is Dictionary:
			_retry_pixel_job(path,job.result.get("source_revisions",{}),str(job.result.get("error","Shared image preparation changed")));continue
		var decision:=_retry_decision(job,job.result)
		if decision=="retry":
			var reason:String=job.result.native_packet.cache_reason
			var previous_charge:=int(job.get("estimate",{}).get("estimated_bytes",0))
			# All aliases of the old packet are cleared on main while its complete
			# reservation is still charged. Only then can the raw stage be enqueued.
			_discard_job(path)
			var raw:Variant=_refresh_raw_memory(path)
			if not raw is Dictionary or not raw.get("estimated_bytes") is int or raw.estimated_bytes<=0 or not raw.get("exclusive") is bool:raw=MemoryEstimate._unknown("invalid_deferred_fallback_estimate")
			_raw_retries[path]={"memory":raw.duplicate(),"reason":reason}
			_memory_estimates[path]=raw.duplicate()
			profile.native_retries=int(profile.get("native_retries",0))+1
			profile.native_retired_charge_bytes=int(profile.get("native_retired_charge_bytes",0))+previous_charge
			preload("res://scripts/world3d/load_trace.gd").instant("deferred.native_retired",{"path":path,"previous_charge":previous_charge,"raw_model_bytes":raw.estimated_bytes,"reason":reason})
			continue
		if not decision.is_empty():job.result.error="原生素材重试身份无效："+path+" "+decision
		if job.get("stage")=="fixed_native" and str(job.result.get("error","")).is_empty():
			var source:Variant=job.result.get("source_digest")
			if not source is String or source!=job.get("candidate",{}).get("source_sha") or (not str(job.get("digest","")).is_empty() and source!=job.digest):job.result.error="原生素材返回来源不符："+path
		if not str(job.result.get("error","")).is_empty():
			var reason:String=job.result.error
			if job.result.get("reference_failure",false) and (not job.get("native",false) or path.begins_with("reference:road_batch:")):
				var failed_uuid:String=job.result.get("failed_uuid","")
				if not failed_uuid.is_empty():_instance_failed(failed_uuid,reason)
				else:
					for uuid:String in job.get("publication_ids",[]):_instance_failed(uuid,reason)
			else:_path_failed(path,reason)
			_discard_job(path);continue

func _dispatch_jobs(tree:SceneTree,prefetch_only:bool=false)->void:
	_job_cap_waiter=""
	if tree==null or _cancelled or not error.is_empty():return
	var dispatch_started:=Time.get_ticks_usec()
	var deadline:=_dispatch_deadline if _dispatch_deadline>0 else dispatch_started+1000
	var capacity:Array=[_demand_revision,_admission.reserved_bytes,_admission.active_workers(),_jobs.size(),_scheduler_epoch,_texture_plan_catalog.revision,prefetch_only,native_entry_prefetch_enabled,prefab_texture_preparation_enabled,shared_prefab_texture_preparation_enabled,bridge_texture_preparation_enabled]
	if _dispatch_revision!=_demand_revision:
		_dispatch_paths=_demanded_by_path.keys();_dispatch_revision=_demand_revision
		_dispatch_paths.sort_custom(func(a,b):return _path_rank(a)<_path_rank(b))
		_dispatch_capacity=[]
	if capacity!=_dispatch_capacity:
		_dispatch_capacity=capacity;_dispatch_cursor=0;_dispatch_fence=""
	profile.admission_drain_path=_dispatch_fence
	var scanned:=0;var attempts:=0
	while _dispatch_cursor<_dispatch_paths.size() and _dispatch_fence.is_empty():
		if Time.get_ticks_usec()>=deadline or scanned>=64:break
		if _admission.worker_limit<=0:break
		var path:String=_dispatch_paths[_dispatch_cursor];_dispatch_cursor+=1;scanned+=1
		var next:Dictionary=_path_first.get(path,{})
		if next.is_empty() or path_errors.has(path) or _jobs.has(path):continue
		if prefetch_only:
			if _entry_prefetch.core_model_paths.has(path) or _prepared_paths.has(path):continue
			if next.get("native_reference",false) or path.begins_with("reference:"):
				# Only an indexed native request can enter the CPU-only branch. The
				# existing safety scope and complete group closure are unchanged.
				if not native_entry_prefetch_enabled or not next.get("native_reference",false) or not next.has("reference_entry") or _reference_index.is_empty():continue
		if instance_errors.has(next.record.uuid):continue
		# Verification flags are not a publication lease. A normal accepted path
		# still has its job (and was skipped above); discard clears these flags.
		# If an orphan flag survives restoration, re-admit its source transaction
		# instead of silently skipping it forever or publishing without an owner.
		# Excluded entry-prefetch paths still never consume or evict a slot.
		if _jobs.size()>=_job_limit():
			# A critical closure can replace a lower-priority private ready result.
			# A running victim is only cancelled; poll/join still owns its bytes.
			if not prefetch_only:_job_cap_waiter=path
			_yield_lower_job(_path_priority(path));_dispatch_cursor-=1;break
		if not _admission.has_capacity():
			if _path_priority(path)<0:_yield_lower_job(_path_priority(path))
			_dispatch_cursor-=1;break
		attempts+=1
		var requests:Array=_reference_requests(path)
		# A slow first header must not occupy the main dispatch loop or stop other
		# ready geometry. Header jobs share admission and complete out of order.
		if not _texture_headers_ready(next,requests,tree):
			if not error.is_empty():return
			continue
		# One immutable dispatch decision governs both reservation and worker.
		# A missing/replaced template is retried by acceptance with a new full
		# reservation, never imported by this reduced-budget reuse job.
		var need_model:bool=not _prepared_paths.has(path)
		var native:bool=next.get("native_reference",false)
		var worker_prepack:=false;var direct_template_reuse:=false
		var needs_faces:=false;var faces_known:=false
		var geometry_consumers:Array=_geometry_consumers(path) if CollisionGeometry.enabled and not native else []
		var geometry_mode:int=int(CollisionGeometry.resolve(geometry_consumers,[],[],path,_collision_definition_modes.get(path,{})).mode) if CollisionGeometry.enabled and not native else CollisionGeometry.ALL
		var template_owner:PackedScene
		if not native:
			template_owner=_resident_prepared_template(path)
			need_model=template_owner==null
			if need_model:_prepared_paths.erase(path)
		var reuse_faces:Dictionary={}
		if (collision_first_enabled or CollisionGeometry.enabled) and not native and not need_model:
			faces_known=true
			if CollisionGeometry.enabled:needs_faces=geometry_mode!=CollisionGeometry.NONE
			else:
				for item:Dictionary in _materialize_pending_snapshot():
					if item.path==path and str(item.record.get("collision",""))!="none":needs_faces=true;break
			if needs_faces:reuse_faces=_reuse_face_offer(template_owner,geometry_mode)
		if not reuse_faces.is_empty():
			if not reuse_faces.get("ok",false):
				profile.reuse_face_fallbacks=int(profile.get("reuse_face_fallbacks",0))+1
				profile.reuse_face_fallback_reason=str(reuse_faces.get("reason","unavailable"))
				# Re-admit the real complete private model route; never capture shared
				# GPU arrays or decode under the bounded reference/hash allowance.
				reuse_faces={};template_owner=null;_prepared_paths.erase(path);need_model=true
		var content_root:String=_reference_root if not _reference_root.is_empty() else preload("res://scripts/world3d/map_paths.gd").external_root()
		var digest:String=source_signatures.get(path,next.digest)
		var candidate:Dictionary={}
		var stage:String="native_reference" if native else ("legacy" if need_model else "reuse_reference")
		var estimate:Dictionary=_estimate_job(next,requests,need_model)
		if path.begins_with("reference:road_batch:") and requests.size()>1 and int(estimate.estimated_bytes)>_admission.byte_limit:
			# Complete image/hash workspaces also count. A CPU-bounded page must
			# not combine valid solo jobs into a permanently inadmissible request.
			requests=[requests[0]];estimate=_estimate_job(next,requests,need_model)
			profile.road_batch_budget_solos=int(profile.get("road_batch_budget_solos",0))+1
		if not reuse_faces.is_empty():estimate.estimated_bytes+=int(reuse_faces.estimated_bytes);estimate.reuse_face_bytes=int(reuse_faces.estimated_bytes)
		if need_model and not native:
			var raw_item:Dictionary=next.duplicate()
			if _raw_retries.has(path):
				stage="raw_import";raw_item.memory=_raw_retries[path].memory
				estimate=_estimate_job(raw_item,requests,true)
			else:
				var offered:Dictionary=_candidate_for_job(path,content_root,digest)
				var full_native:bool=require_native_products and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
				if full_native and offered.is_empty():
					_path_failed(path,preload("res://scripts/world3d/model_parse_preparation.gd").native_failure(path,"native_footprint_missing_or_stale").error_message)
					continue
				var raw_bytes:=int(next.get("memory",{}).get("estimated_bytes",_admission.byte_limit))
				if offered.get("estimated_bytes") is int and offered.estimated_bytes>0 and offered.get("exclusive") is bool:
					# Both fixed and legacy readers may allocate the known native
					# product. Never discard its larger bound after GLB cleanup.
					raw_item.memory=next.get("memory",{}).duplicate()
					raw_item.memory.estimated_bytes=maxi(raw_bytes,offered.estimated_bytes)
					raw_item.memory.exclusive=bool(raw_item.memory.get("exclusive",false)) or offered.exclusive
					if native_preparation_enabled or full_native:
						candidate=offered.duplicate(true);stage="fixed_native"
						if native_budget_enabled:raw_item.memory={"estimated_bytes":candidate.estimated_bytes,"exclusive":candidate.exclusive,"known":true}
						if full_native and full_native_template_reuse_enabled:
							direct_template_reuse=bool(offered.get("direct_template_reuse_safe",false))
						elif full_native and full_native_worker_prepack_enabled:
							worker_prepack=true
							# The existing full-job estimate already spans cache_scene's
							# original packet, private scene and new PackedScene; moving
							# that pack earlier must retain the same lease through disposal.
					estimate=_estimate_job(raw_item,requests,true)
					estimate.raw_model_bytes=raw_bytes
					estimate.native_model_bound_bytes=offered.estimated_bytes
		# Split geometry has no embedded ImageTextures for the legacy direct
		# plan to discover. Keep template reuse, but skip its scan and 12 MiB.
		var direct_material_plan:bool=direct_template_reuse and full_native_material_plan_enabled and not candidate.has("texture_table")
		var native_model_plan:Dictionary={}
		if stage=="fixed_native" and candidate.has("texture_table"):
			native_model_plan=_native_model_plan(path,candidate,content_root,tree)
			if native_model_plan.is_empty():
				if not error.is_empty():return
				continue
			var merged:Dictionary=_native_plan_claims[path].merge_plan(estimate.get("prefab_texture_plan",{}),native_model_plan.plan)
			estimate.estimated_bytes=int(estimate.estimated_bytes)-int(estimate.get("prefab_texture_plan",{}).get("estimated_bytes",0))+int(merged.estimated_bytes)
			estimate.prefab_texture_plan=merged
		elif _native_plan_claims.has(path):
			_native_plan_claims[path].release_now();_native_plan_claims.erase(path)
		if direct_material_plan:
			estimate.texture_plan_workspace_bytes=preload("res://scripts/world3d/model_texture_direct_plan.gd").EXTRA_RESERVATION_BYTES
			estimate.estimated_bytes=int(estimate.estimated_bytes)+int(estimate.texture_plan_workspace_bytes)
		estimate.stage=stage
		if CollisionGeometry.enabled and not native:
			# Snapshot/learned-policy containers are private task inputs/outputs.
			# They remain charged through publication just like other job results.
			var descriptors:int=geometry_consumers.size()*2+_collision_definition_modes.get(path,{}).size()+mini(requests.size(),CollisionGeometry.MAX_CONSUMERS)
			estimate.geometry_workspace_bytes=65536+descriptors*CollisionGeometry.DESCRIPTOR_BYTES
			estimate.estimated_bytes=int(estimate.estimated_bytes)+int(estimate.geometry_workspace_bytes)
		var pixel_offer:Dictionary={};var pixel_tickets:Dictionary={};var reserve_estimate:Dictionary=estimate
		if (shared_prefab_texture_preparation_enabled or estimate.get("targeted_bridge_textures",false) or not native_model_plan.is_empty()) and not estimate.get("prefab_texture_plan",{}).get("rows",{}).is_empty():
			var plan:Dictionary=estimate.prefab_texture_plan
			var texture_started:=Time.get_ticks_usec() if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled else 0
			if not _pixel_retries.has(path):pixel_tickets=Prefab.texture_tickets(plan.rows,_doc.load_material_pool)
			_record_texture_dispatch("ticket_lookup",texture_started,path,plan.rows.size())
			var cached:Dictionary={}
			for key:String in pixel_tickets:cached[key]=pixel_tickets[key].source_sha
			_shared_images.admission=_admission
			texture_started=Time.get_ticks_usec() if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled else 0
			pixel_offer=_shared_images.offer(plan,cached,_pixel_retries.get(path,{}).get("revisions",{}))
			_record_texture_dispatch("shared_offer",texture_started,path,plan.rows.size())
			estimate.pixel_retained_bytes=int(estimate.estimated_bytes)-int(plan.estimated_bytes)
			estimate.estimated_bytes=int(estimate.pixel_retained_bytes)+int(pixel_offer.scratch_bytes)
			reserve_estimate=estimate.duplicate();reserve_estimate.estimated_bytes=int(estimate.estimated_bytes)
			for bytes:int in pixel_offer.retained.values():reserve_estimate.estimated_bytes+=bytes
		var admitted:bool=_admission.reserve(path,estimate) if pixel_offer.is_empty() else _admission.reserve_bundle(path,estimate,pixel_offer.retained)
		if not admitted:
			# A required exclusive asset needs every current output to retire. Do
			# not keep filling its empty sibling slot with lower-ranked scenery:
			# that would starve the foreground asset until the far queue empties.
			# Recompute the fence from live demand each frame so cancellation or a
			# newer, higher-priority request never inherits an obsolete barrier.
			if _admission.requires_exclusive(reserve_estimate):
				if _path_priority(path)<0:_yield_lower_job(_path_priority(path))
				_dispatch_fence=path;profile.admission_drain_path=path
				break
			if _path_priority(path)<0:
				# Foreground navigation/transfer must not wait for a stream of cheap
				# scenery to repeatedly refill its required byte window.
				_yield_lower_job(_path_priority(path))
				_dispatch_fence=path;profile.admission_drain_path=path
				break
			continue
		var worker:RefCounted=Thread.new();var token:=Drainer.CancelToken.new()
		# Only immutable native CPU transactions can split their final proof.
		# All-resident/follower-only requests have no unique decode to overlap.
		var parallel_pixels:bool=parallel_texture_preparation_enabled and ((native and not requests.is_empty()) or not native_model_plan.is_empty()) and not pixel_offer.get("leaders",{}).is_empty() and preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and preload("res://scripts/world3d/chunk_reference_preparation.gd").trusted_directory_snapshot_enabled
		if parallel_pixels and _admission.add_worker_slot(path):
			worker=ParallelChunkWorker.new();worker.admission=_admission;worker.path=path
		else:parallel_pixels=false
		# A model is immutable and shared by all its instances; include future
		# collision consumers so reusing a decorative instance is still safe.
		# Native references prepare their own exact CPU geometry. This flag is
		# consumed only by the shared model route; scanning all pending native
		# records also forced a fresh ordered snapshot after each publication.
		if not native and not faces_known:
			for item:Dictionary in _materialize_pending_snapshot():
				if item.path==path and str(item.record.get("collision",""))!="none":needs_faces=true;break
		_drainer=Drainer.for_tree(tree);_drainer.watch(worker,token)
		var publication_ids:Array=_job_publication_ids(path,requests)
		_jobs[path]={"worker":worker,"token":token,"estimate":estimate,"publication_ids":publication_ids,"native":native,"stage":stage,"candidate":candidate,"digest":digest,"dispatch_us":Time.get_ticks_usec(),"parallel_pixels":parallel_pixels,"worker_prepack":worker_prepack,"direct_template_reuse":direct_template_reuse,"direct_material_plan":direct_material_plan}
		if not native_model_plan.is_empty():
			_jobs[path].native_model_plan=native_model_plan;_jobs[path].native_binding_pending=true
			_jobs[path].native_texture_sources=_native_plan_claims[path].sources(native_model_plan)
			token.set_meta("native_texture_scope",_native_plan_claims[path]);_native_plan_claims.erase(path)
		if CompletedTrace.enabled:CompletedTrace.record(path,token.get_instance_id(),"dispatch",{"publication_ids":publication_ids.duplicate(),"estimated_bytes":int(estimate.estimated_bytes),"exclusive":bool(estimate.get("exclusive",true)),"native":native})
		if CollisionGeometry.enabled and not native:
			_jobs[path].geometry_consumers=geometry_consumers;_jobs[path].geometry_mode=geometry_mode
		if not reuse_faces.get("snapshots",[]).is_empty():
			_jobs[path].reuse_face_snapshots=reuse_faces.snapshots;_jobs[path].reuse_face_owners=reuse_faces.owners
			token.set_meta("reuse_face_owners",reuse_faces.owners)
			profile.reuse_face_jobs=int(profile.get("reuse_face_jobs",0))+1
			profile.reuse_face_prepare_bytes=int(profile.get("reuse_face_prepare_bytes",0))+int(reuse_faces.estimated_bytes)
		profile.max_total_jobs=maxi(int(profile.get("max_total_jobs",0)),_jobs.size())
		if not pixel_offer.is_empty():
			_pixel_serial+=1;var consumer:String=path+"#"+str(_pixel_serial)
			_shared_images.commit(consumer,pixel_offer)
			_jobs[path].pixel_consumer=consumer;_jobs[path].pixel_tickets=pixel_tickets
			_jobs[path].shared_pixels={"pool":_shared_images,"consumer":consumer,"leaders":pixel_offer.leaders,"cached":pixel_offer.cached}
			token.cancel_callback=_shared_images.cancel.bind(consumer)
			token.set_meta("prefab_shared_owner",_shared_images);token.set_meta("prefab_shared_release",_shared_images.release.bind(consumer));token.set_meta("prefab_texture_tickets",pixel_tickets)
			if estimate.get("targeted_bridge_textures",false):
				profile.bridge_texture_jobs=int(profile.get("bridge_texture_jobs",0))+1
				profile.bridge_texture_declared_keys=int(profile.get("bridge_texture_declared_keys",0))+pixel_offer.rows.size()
				profile.bridge_texture_resident_keys=int(profile.get("bridge_texture_resident_keys",0))+pixel_tickets.size()
				profile.bridge_texture_missing_keys=int(profile.get("bridge_texture_missing_keys",0))+pixel_offer.bindings.size()
				if pixel_offer.bindings.is_empty():profile.bridge_texture_all_resident_jobs=int(profile.get("bridge_texture_all_resident_jobs",0))+1
				preload("res://scripts/world3d/load_trace.gd").instant("deferred.bridge_textures",{"path":path,"declared":pixel_offer.rows.size(),"resident":pixel_tickets.size(),"missing":pixel_offer.bindings.size(),"leaders":pixel_offer.leaders.size(),"scratch_bytes":pixel_offer.scratch_bytes,"reserved_bytes":reserve_estimate.estimated_bytes})
		token.set_meta("admission_release",CompletedTrace.release.bind(_admission,path,token.get_instance_id()) if CompletedTrace.enabled else _admission.release.bind(path))
		# A method Callable stores an ObjectID, not a strong RefCounted owner.
		token.set_meta("admission_owner",_admission)
		# A lease keeps resources alive through worker completion and delayed
		# publication. It does not permit publishing through an evicted/replaced
		# cache entry: acceptance and later frames compare this exact object.
		if template_owner!=null:
			_jobs[path].reuse_template_owner=template_owner
			# On map exit the tree-owned drainer retains the token until join;
			# keep the lease alive even after this queue's job dictionary is gone.
			token.set_meta("reuse_template_owner",template_owner)
		if not native and not need_model:
			profile.reuse_reference_jobs=int(profile.get("reuse_reference_jobs",0))+1
			if not _prepared_paths.has(path):profile.recovered_template_jobs=int(profile.get("recovered_template_jobs",0))+1
			profile.reuse_reference_reservation_bytes=int(profile.get("reuse_reference_reservation_bytes",0))+int(estimate.estimated_bytes)
		preload("res://scripts/world3d/load_trace.gd").instant("deferred.dispatch",{"path":path,"stage":stage,"need_model":need_model,"native":native,"reserved_bytes":estimate.estimated_bytes,"references":requests.size()})
		var prepare:=_make_prepare_task(path,digest,token,next,needs_faces,content_root,requests,native,need_model)
		if parallel_pixels:
			worker.pixels=_make_native_pixel_prepare_task(estimate.prefab_texture_plan,_jobs[path].native_texture_sources,content_root,token,_jobs[path].shared_pixels) if not native_model_plan.is_empty() else _make_pixel_prepare_task(estimate.prefab_texture_plan,content_root,token,_jobs[path].shared_pixels)
			profile.parallel_pixel_jobs=int(profile.get("parallel_pixel_jobs",0))+1
		if _start_worker(worker,prepare)!=OK:
			_drainer.forget(worker);_jobs[path].erase("worker");_discard_job(path);_fail("无法启动附近素材后台准备："+path);return
		if stage=="fixed_native":profile.fixed_native_jobs=int(profile.get("fixed_native_jobs",0))+1
		if stage=="raw_import":profile.raw_readmission_jobs=int(profile.get("raw_readmission_jobs",0))+1
		if prefetch_only:
			profile.entry_prefetch_jobs=int(profile.get("entry_prefetch_jobs",0))+1
			if native:profile.entry_prefetch_native_jobs=int(profile.get("entry_prefetch_native_jobs",0))+1
			if not profile.has("entry_prefetch_first_dispatch_us"):profile.entry_prefetch_first_dispatch_us=Time.get_ticks_usec()
	var dispatch_elapsed:=Time.get_ticks_usec()-dispatch_started
	profile.dispatch_scan_us=int(profile.get("dispatch_scan_us",0))+dispatch_elapsed
	profile.max_dispatch_scan_us=maxi(int(profile.get("max_dispatch_scan_us",0)),dispatch_elapsed)
	profile.dispatch_scanned=int(profile.get("dispatch_scanned",0))+scanned
	profile.dispatch_attempts=int(profile.get("dispatch_attempts",0))+attempts
	profile.dispatch_cursor=_dispatch_cursor;profile.dispatch_paths=_dispatch_paths.size()
	profile.ready_job_limit=_job_limit()
	profile.total_jobs=_jobs.size()
	profile.max_total_jobs=maxi(int(profile.get("max_total_jobs",0)),_jobs.size())
	profile.active_jobs=_jobs.size();profile.reserved_bytes=_admission.reserved_bytes
	profile.retiring_pixel_bytes=_admission.retiring_pixel_bytes;profile.retiring_pixel_outputs=_admission.retiring_pixel_outputs
	profile.peak_reserved_bytes=_admission.peak_bytes;profile.peak_jobs=_admission.peak_jobs
	profile.admission=_admission.snapshot()
	profile.shared_pixels=_shared_images.snapshot()
	profile.demanded_instances=_demanded_count();profile.deferred_instances=pending_count()

func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,needs_faces:bool,content_root:String,requests:Array,native:bool,need_model:bool)->Callable:
	var job:Dictionary=_jobs.get(path,{})
	var route:Dictionary={"stage":job.get("stage","legacy"),"candidate":job.get("candidate",{}).duplicate(true),"require_native_products":require_native_products,"worker_prepack":job.get("worker_prepack",false),"direct_template_reuse":job.get("direct_template_reuse",false),"direct_material_plan":job.get("direct_material_plan",false)}
	if CompletedTrace.enabled:route.completed_job_trace=true
	if job.has("geometry_consumers"):
		route.filter_collision_geometry=true;route.geometry_consumers=job.geometry_consumers.duplicate(true)
		route.geometry_known=_collision_definition_modes.get(path,{}).duplicate();route.geometry_mode=int(job.geometry_mode)
	if job.has("native_model_plan"):
		# Immutable catalog values are already pinned by the operation scope.
		# Do not deep-copy the shared table once for every model/continuation.
		route.native_model_plan=job.native_model_plan
		route.prefab_texture_plan=job.estimate.prefab_texture_plan
		route.native_pixels_task=_make_native_pixel_prepare_task(route.prefab_texture_plan,job.native_texture_sources,content_root,token,job.get("shared_pixels",{}))
	else:route.prefab_texture_plan=job.get("estimate",{}).get("prefab_texture_plan",{}).duplicate(true)
	route.parallel_pixels=job.get("parallel_pixels",false)
	route.collision_workspace_bytes=int(job.get("estimate",{}).get("collision_workspace_bytes",0))
	route.road_paint_workspace_bytes=int(job.get("estimate",{}).get("road_paint_workspace_bytes",0))
	route.reuse_face_snapshots=job.get("reuse_face_snapshots",[])
	if job.has("shared_pixels"):route.shared_pixels=job.shared_pixels
	if _reference_handoff!=null:
		route.hydrated_records=_reference_handoff.take(_reference_index,requests)
		profile.reference_handoff_transferred=_reference_handoff.transferred
		profile.reference_handoff_remaining=_reference_handoff.records.size()
	return _prepare_job.bind(path,digest,token,item.get("manifest",{}),needs_faces,content_root,_reference_index,_reference_map_path,requests,native,need_model,_reference_proof,route)

func _make_pixel_prepare_task(plan:Dictionary,content_root:String,token:RefCounted,shared:Dictionary)->Callable:
	var requested:Dictionary={}
	for key:String in plan.rows:requested[key]=[plan.rows[key].path,plan.rows[key].flip,plan.rows[key].normal]
	return PrefabTextures.prepare.bind(requested,plan,content_root,token,true,shared,true)

func _make_native_pixel_prepare_task(plan:Dictionary,requested:Dictionary,content_root:String,token:RefCounted,shared:Dictionary)->Callable:
	return PrefabTextures.prepare.bind(requested,plan,content_root,token,true,shared,true)

func _discard_job(path:String)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.deferred_asset_loader._discard_job") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_invalidate_collision_queries()
	var job:Dictionary=_jobs[path]
	_discard_pending_preparation(path,job)
	if job.has("instance_preparation"):
		job.instance_preparation.cursor.dispose();_record_instance_work(job.instance_preparation.cursor,true,job.instance_preparation.get("worker_prepared",false));job.erase("instance_preparation")
	_publication_queues.erase(path);_scheduler_epoch+=1
	for key:Array in _prefab_texture_attempts.keys():
		if key[0]==path:_prefab_texture_attempts.erase(key)
	# The main-thread document borrows the worker output only for this job.
	# Published Mesh/CPU-mesh resources retain their own array references.
	var output:Dictionary=job.get("result",{}) if job.get("result",{}) is Dictionary else {}
	for uuid:String in output.get("surface_arrays",{}):
		_doc.load_surface_arrays.erase(uuid);_doc.load_surface_bounds.erase(uuid);_doc.load_surface_uploads.erase(uuid);_doc.load_surface_paints.erase(uuid)
	for uuid:String in output.get("terrain_contexts",{}):_doc.terrain_neighbors.data.erase(uuid)
	# Large importer states retain thousands of GPU/CPU owners. Keep this same
	# byte reservation until the tree-owned retirement cursor drops every alias.
	var release:Callable=CompletedTrace.release.bind(_admission,path,job.token.get_instance_id()) if CompletedTrace.enabled else _admission.release.bind(path)
	var deferred_release:=preload("res://scripts/world3d/resource_retirement.gd").defer_model_packet(output,release,_admission)
	if not deferred_release:deferred_release=preload("res://scripts/world3d/resource_retirement.gd").defer_import_packet(output,release,_admission)
	if deferred_release:
		_admission.park(path);_admission.set_stage(path,"resource_retirement")
	if not output.is_empty():Drainer.dispose_result(output)
	if job.has("staged"):job.staged.clear()
	job.erase("staged_groups")
	if job.has("collision_staged"):
		for packet:Dictionary in job.get("publication_packets",{}).values():
			if packet.has("index_preparation"):packet.index_preparation.dispose()
		job.collision_staged.clear()
	job.erase("publication_packets")
	job.erase("reuse_face_snapshots");job.erase("reuse_face_owners");job.erase("reuse_template_owner");job.erase("publication_template_owner")
	job.erase("pixel_tickets");job.erase("shared_pixels");job.erase("material_textures");job.erase("material_scope")
	job.erase("streamed_texture_owners");job.erase("streamed_texture_scope")
	_clear_native_plan_aliases(job)
	Drainer.release_shared(job.token)
	if job.token.has_meta("admission_release"):job.token.remove_meta("admission_release")
	if CompletedTrace.enabled:
		var outcomes:Dictionary={}
		for uuid:String in job.get("publication_ids",[]):
			outcomes[uuid]="failed" if instance_errors.has(uuid) or path_errors.has(path) else ("cancelled" if job.token.is_cancelled() or _cancelled else ("demanded" if _demanded_by_id.has(uuid) else "undemanded"))
		CompletedTrace.record(path,job.token.get_instance_id(),"slot_released",{"outcomes":outcomes,"deferred_lease":deferred_release})
	_jobs.erase(path)
	if not deferred_release:release.call()
	_raw_retries.erase(path);_pixel_retries.erase(path)
	if job.token.has_meta("admission_owner"):job.token.remove_meta("admission_owner")

func _discard_pending_preparation(path:String,job:Dictionary)->void:
	# Only this job's publication IDs can receive model_verified, and only its
	# returned records can receive hydrated definitions. Resolve both through
	# the live catalogue, including accepted group members no longer demanded.
	# Do this before disposing the result; published/retired IDs are already gone.
	var items:Array=[]
	if _indexed and incremental_pending_index_enabled and _pending_by_record_id.size()==pending_count() and job.has("publication_ids"):
		var ids:Dictionary={}
		for uuid:String in job.publication_ids:ids[uuid]=true
		var output:Variant=job.get("result",{})
		if output is Dictionary:
			for record:Dictionary in output.get("records",[]):ids[record.uuid]=true
		for uuid:String in ids:
			var item:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
			if not item.is_empty():items.append(item)
	else:items=_materialize_pending_snapshot() # Standalone/diagnostic producers may not have a catalogue.
	profile.discard_pending_visits=int(profile.get("discard_pending_visits",0))+items.size()
	for item:Dictionary in items:
		if item.path!=path:continue
		item.erase("model_verified")
		if item.has("reference_entry") and item.get("reference_prepared",false):
			item.record=item.reference_entry.compact_record;item.reference_prepared=false

func _retry_pixel_job(path:String,revisions:Dictionary,reason:String)->void:
	var count_:int=int(_pixel_retries.get(path,{}).get("count",0))+1
	var current:Dictionary=revisions.duplicate()
	_discard_job(path);_prepared_paths.erase(path)
	if count_>2:_path_failed(path,"Shared image retry limit: "+reason);return
	_pixel_retries[path]={"count":count_,"revisions":current}
	profile.pixel_retries=int(profile.get("pixel_retries",0))+1

func _record_pixel_packet(path:String,job:Dictionary,packet:Dictionary)->void:
	if job.get("native_binding_continuation",false):return
	if job.get("estimate",{}).get("prefab_texture_plan",{}).is_empty():return
	var continuation:bool=job.get("pixel_continuation",false)
	var values:Dictionary=packet.get("profile",{}) if continuation else packet.get("read_profile",{}).get("prefab_textures",{})
	if not profile.has("prefab_pixels"):profile.prefab_pixels={"packets":0,"continuations":0,"jobs":{},"dropped_paths":0,"totals":{}}
	var metrics:Dictionary=profile.prefab_pixels;metrics.packets+=1
	if continuation:metrics.continuations+=1
	var scalars:Dictionary={}
	for field:String in values:
		if values[field] is int or values[field] is float:
			scalars[field]=values[field];metrics.totals[field]=metrics.totals.get(field,0)+values[field]
	if not metrics.jobs.has(path):
		if metrics.jobs.size()>=128:metrics.dropped_paths+=1;return
		metrics.jobs[path]={"packets":0,"continuations":0,"totals":{}}
	var row:Dictionary=metrics.jobs[path];row.packets+=1
	if continuation:row.continuations+=1
	var worker_us:int=int(packet.get("continuation_us",0)) if continuation else int(packet.get("elapsed_us",packet.get("read_profile",{}).get("elapsed_us",0)))
	row.worker_us=int(row.get("worker_us",0))+worker_us
	metrics.worker_us=int(metrics.get("worker_us",0))+worker_us
	for field:String in scalars:row.totals[field]=row.totals.get(field,0)+scalars[field]
	var ready_us:int=Time.get_ticks_usec()-int(job.get("dispatch_us",Time.get_ticks_usec()))
	if not continuation:row.last_first_ready_us=ready_us
	if not packet.get("waiting_pixels",false):row.last_fully_ready_us=ready_us
	row.last_error=str(packet.get("error",""));row.last_cancelled=bool(packet.get("cancelled",false))

func _resume_pixel_jobs(tree:SceneTree)->void:
	if tree==null or _cancelled or not error.is_empty():return
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if job.has("worker") or not job.has("pixel_consumer") or not job.get("result",{}).get("waiting_pixels",false) or job.token.is_cancelled():continue
		if not _shared_images.ready(job.pixel_consumer) or not _admission.resume_worker(path):continue
		var shared:Dictionary=job.shared_pixels.duplicate();shared.leaders={}
		var plan:Dictionary=job.estimate.prefab_texture_plan
		var requested:Dictionary=job.get("native_texture_sources",{})
		if not job.has("native_model_plan"):
			for key:String in plan.rows:requested[key]=[plan.rows[key].path,plan.rows[key].flip,plan.rows[key].normal]
		var worker:=Thread.new();job.worker=worker;job.pixel_continuation=true
		# The previous result can contain raw/compiled GPU owners. Keep it on main
		# (or the drainer after exit), never pass it to the CPU continuation.
		job.token.set_meta("prefab_continuation_result",job.result)
		_drainer=Drainer.for_tree(tree);_drainer.watch(worker,job.token)
		var content_root:String=_reference_root if not _reference_root.is_empty() else preload("res://scripts/world3d/map_paths.gd").external_root()
		var native_pixels:Callable=_make_native_pixel_prepare_task(plan,requested,content_root,job.token,shared) if job.has("native_model_plan") else Callable()
		var task:=_resume_pixels.bind(requested,plan,content_root,job.token,shared,_reference_map_path,str(_reference_index.get("source_sha256","")),job.result.get("dependencies",{}).duplicate(),path if not job.get("native",false) else "",str(job.result.get("source_digest","")),require_native_products,native_pixels)
		if _start_worker(worker,task)!=OK:
			_drainer.forget(worker);job.erase("worker");_discard_job(path);_path_failed(path,"Cannot resume shared image verification");continue
		profile.pixel_continuations=int(profile.get("pixel_continuations",0))+1
	_resume_native_bindings(tree)

func _resume_native_bindings(tree:SceneTree)->void:
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if job.has("worker") or not job.get("native_binding_pending",false) or job.token.is_cancelled():continue
		if not job.has("result") or job.result.get("waiting_pixels",false) or not str(job.result.get("error","")).is_empty():continue
		var packet:Dictionary=job.result.get("prefab_texture_packet",{})
		var tickets:Dictionary=job.get("pixel_tickets",{})
		if not Prefab.tickets_valid(tickets,packet.get("sources",{})):
			_retry_pixel_job(path,{},"Resident native texture changed before binding");continue
		if not _admission.resume_worker(path):continue
		# Resident tickets own their exact Texture2D already. Bind those owners
		# without a duplicate load and transfer only newly pooled native outputs.
		var textures:Dictionary=packet.get("uploaded_textures",{});var handoff:Array=[]
		for key:String in job.native_model_plan.plan.rows:
			if tickets.has(key):textures[key]=tickets[key].texture
			else:handoff.append(key)
		packet.uploaded_textures=textures;job.result.prefab_texture_packet=packet;job.native_handoff_keys=handoff
		_admission.set_stage(path,"native_texture_binding")
		var worker:=Thread.new();job.worker=worker;job.native_binding_continuation=true
		job.token.set_meta("prefab_continuation_result",job.result)
		_drainer=Drainer.for_tree(tree);_drainer.watch(worker,job.token)
		var task:=_make_native_binding_task(job.result,job.native_model_plan,job.token)
		if _start_worker(worker,task)!=OK:
			_drainer.forget(worker);job.erase("worker");_discard_job(path);_path_failed(path,"Cannot start native texture binding");continue
		profile.native_texture_binding_jobs=int(profile.get("native_texture_binding_jobs",0))+1

func _publish_native_texture_owners(path:String,job:Dictionary)->int:
	# Only a successfully cached model advertises its completed owners. Binding
	# workers never access the main-thread weak directory.
	if not job.has("native_model_plan") or job.has("worker") or job.get("native_binding_pending",true) or job.token.is_cancelled():return 0
	var result:Dictionary=job.get("result",{})
	var packed:PackedScene=Assets._scenes.get(path)
	if not str(result.get("error","")).is_empty() or packed==null or packed.get_meta("_rmmo_source_digest","")!=result.get("source_digest"):return 0
	return preload("res://scripts/world3d/native_texture_sharing.gd").publish(result.get("prefab_texture_packet",{}).get("uploaded_textures",{}),job.native_model_plan.plan.rows,job.get("pixel_tickets",{}))

func _make_native_binding_task(result:Dictionary,plan:Dictionary,token:RefCounted)->Callable:
	return preload("res://scripts/world3d/deferred_native_texture_binding.gd").prepare.bind(result,plan,token)

static func _resume_pixels(requested:Dictionary,plan:Dictionary,root:String,token:RefCounted,shared:Dictionary,map_path:String,map_sha:String,dependencies:Dictionary,model_path:String,model_sha:String,native_only:bool=false,native_pixels:Callable=Callable())->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:=_resume_pixels_inner(requested,plan,root,token,shared,map_path,map_sha,dependencies,model_path,model_sha,native_only,native_pixels)
	result.continuation_us=Time.get_ticks_usec()-began
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.pixel_continuation",began,{"consumer":shared.get("consumer",""),"error":result.get("error",""),"waiting":result.get("waiting_pixels",false),"sources":requested.size()})
	return result

static func _resume_pixels_inner(requested:Dictionary,plan:Dictionary,root:String,token:RefCounted,shared:Dictionary,map_path:String,map_sha:String,dependencies:Dictionary,model_path:String,model_sha:String,native_only:bool=false,native_pixels:Callable=Callable())->Dictionary:
	var mounted_snapshot:bool=preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and preload("res://scripts/world3d/chunk_reference_preparation.gd").trusted_directory_snapshot_enabled
	var packet:Dictionary=native_pixels.call() if native_pixels.is_valid() else PrefabTextures.prepare(requested,plan,root,token,false,shared,mounted_snapshot)
	if not packet.error.is_empty() or packet.get("waiting_pixels",false):return packet
	var Paths=preload("res://scripts/world3d/map_paths.gd")
	var Store=preload("res://scripts/world3d/map_resource_store.gd")
	if token.is_cancelled():packet.error="Shared image continuation cancelled";packet.cancelled=true;return packet
	if not map_path.is_empty() and (not Paths.allowed(map_path,root) or (not mounted_snapshot and FileAccess.get_sha256(map_path)!=map_sha) or not Paths.allowed(map_path,root) or (not preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and not Store.verify_dependencies(dependencies,map_path,root,1))):packet.error="Reference identity changed while awaiting shared images";return packet
	if not model_path.is_empty() and not _verify_reused_source(model_path,model_sha,root,token,native_only).error.is_empty():packet.error="Model changed while awaiting shared images";return packet
	if not PrefabTextures.verify(packet,root,token,shared,mounted_snapshot):packet.error="Shared image source changed before handoff";packet.cancelled=token.is_cancelled()
	return packet

func _nearest_index()->int:
	var at:=-1;var nearest:=INF
	for i in pending_count():
		var distance:float=_distance(_materialize_pending_snapshot()[i])
		if distance<nearest:nearest=distance;at=i
	return at

func _distance(item:Dictionary)->float:
	return _distance_from(item,_priority)

static func _distance_from(item:Dictionary,origin:Vector3)->float:
	var bounds:AABB=item.bounds
	var point:=Vector3(clampf(origin.x,bounds.position.x,bounds.end.x),origin.y,clampf(origin.z,bounds.position.z,bounds.end.z))
	return origin.distance_squared_to(point)

static func _collect(node:Node,pose:Transform3D,result:Array)->void:
	if node is Node3D:pose=pose*node.transform
	if node is MeshInstance3D:
		var spec:Dictionary=Stream._spec(node,pose)
		spec.rotation=pose.basis.get_euler()
		spec.uuid=str(spec.extras.get("uuid",node.name));result.append(spec)
	for child:Node in node.get_children():_collect(child,pose,result)

static func _collect_collision_asset(holder:Node3D,result:Array)->void:
	# The sidecar flattens the source-local hierarchy before placement. Use the
	# same multiplication order on actual visual nodes: ((A * B) * C) can differ
	# bitwise from A * (B * C). No expected Store pose is copied or tolerated.
	var local:Array=[]
	for child:Node in holder.get_children():_collect(child,Transform3D.IDENTITY,local)
	for spec:Dictionary in local:
		var pose:Transform3D=holder.transform*spec.transform
		spec.transform=pose;spec.position=pose.origin;spec.rotation=pose.basis.get_euler()
		var bounds:AABB=pose*spec.mesh.get_aabb()
		spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(bounds.position);spec.chunk_max=Stream.chunk_key(bounds.end)
		result.append(spec)

func _fail(reason:String)->void:
	_texture_plan_catalog.abandon()
	_retire_native_plan_claims({})
	error=reason
	for job:Dictionary in _jobs.values():job.token.cancel()
	set_process(not _jobs.is_empty());failed.emit(reason)

func _exit_tree()->void:
	if _scene_handoff:return
	_texture_plan_catalog.abandon()
	_retire_native_plan_claims({})
	_cancelled=true
	_cancel_collision_prefetch("prefetch_owner_exited")
	for id:String in _collision_request_ids.keys():_release_collision_request(id)
	_prefab_texture_attempts.clear()
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		job.token.cancel()
		if job.has("worker"):
			_clear_native_plan_aliases(job)
			if is_instance_valid(_drainer) and _drainer.is_inside_tree():_drainer.abandon(job.worker)
			else:Drainer.drain_shutdown(job.worker,job.token)
		else:_discard_job(path)
	_jobs.clear()
	_runtime_record_ids.clear()
