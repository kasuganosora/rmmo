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
const COVERED_LOADING_BUDGET_US:=16000
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
const SharedImages=preload("res://scripts/world3d/shared_prefab_images.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const CollisionGeometry=preload("res://scripts/world3d/model_collision_requirements.gd")
static var shared_prefab_texture_preparation_enabled:=true # Shared source tasks retain and charge pixels once.
static var prefab_texture_preparation_enabled:=true
static var native_entry_prefetch_enabled:=false
static var bridge_texture_preparation_enabled:=true # Demanded native bridges, after core publication only; full entry ABBA verified.
static var native_preparation_enabled:=true # Probe-only old native/readmission path.
static var native_budget_enabled:=true # Validated native reservations; invalid candidates use full raw admission.
static var ready_worker_yield_enabled:=true # Bytes remain charged after join.
static var fair_publication_enabled:=true # Probe may select the old distance-only order.
static var material_publication_slices_enabled:=true # Probe-only synchronous control.
static var collision_first_enabled:=false # Exact sidecar experiment; normal geometry/nav gates remain available.
static var collision_query_cache_enabled:=true # Disable for the legacy guard cost/behaviour comparison.
static var collision_query_profile_enabled:=false # Detailed timers are opt-in to avoid perturbing physics ticks.
static var owned_index_projection_enabled:=true # Private raw-model specs transfer without copying/remapping.
static var typed_demand_scan_enabled:=true # Diagnostic control retains the exact unfiltered scheduler.
static var demand_membership_cache_enabled:=true
static var native_demand_order_enabled:=true
static var native_demand_bounds_enabled:=true
static var incremental_pending_index_enabled:=true
static var demanded_template_scan_enabled:=true
const EMPTY_DEMAND:Dictionary={}
static var private_publication_packet_enabled:=true
const COLLISION_QUERY_CACHE_LIMIT:=16
var pending:Array=[]
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
var loading_worker_limit:=0 # 0 selects production CPU-based capacity; probes may override 2/4/6.
var _saved_interactive_worker_limit:=-1
var _demands:Dictionary={}
var _demand_scope:Dictionary={}
var _demand_revision:=0
var _candidates_revision:=-1
var _demand_membership:Dictionary={} # Per live ticket; spatial candidates only, never readiness/leases.
var _typed_pending:Dictionary={}
var _typed_pending_buildings:=-1
var _demanded:Array=[]
var _demanded_by_id:Dictionary={}
var _demanded_by_path:Dictionary={}
var _demanded_rank:Dictionary={}
var _completion_emitted:=false
var _prepared_paths:Dictionary={}
var _cancelled:=false
var _active:=false
var _priority:=Vector3.ZERO
var _priority_rank_anchor:Variant=null
var _pending_index:Dictionary={}
var _large_pending:Array=[]
var _indexed:=false
var _doc=preload("res://scripts/world3d/world_document.gd").new()
var _reference_index:Dictionary={}
var _reference_map_path:=""
var _reference_root:=""
var _reference_proof:OwnershipProof
var _runtime_record_ids:Dictionary={}
var runtime_fixture_states:Dictionary={} # Scalar state survives render retirement.
var _runtime_building_records:Dictionary={} # Verified live component adaptation; preserves long-view reload demand.
var _runtime_building_supports:Dictionary={} # Authored IDs only; no mesh/record ownership.
var _pending_by_record_id:Dictionary={}
var _memory_estimates:Dictionary={}
var _entry_loading:Dictionary={}
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
var _dispatch_deadline:=0
var _scheduler_epoch:=0
var _publication_queues:Dictionary={}
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
	return ready_job_limit if ready_job_limit>0 else maxi(4,_admission.worker_limit*2)

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
	_update_loading_worker_capacity(COVERED_LOADING_BUDGET_US)
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
		if job.has("result") and not job.result.get("waiting_pixels",false):ready+=1
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
	_demand_scope.clear()
	for id:String in _entry_prefetch.previous_scope:_demand_scope[id]=true
	_demand_revision+=1
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
		if not cover is TransferLoading or not cover.is_opaque_drawn():return false
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
	_invalidate_collision_queries()
	_runtime_building_records.clear()
	_runtime_building_supports.clear();_pending_by_record_id.clear()
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

func requeue_references(entries:Array)->int:
	# Called only after resident stream/navigation ownership has been released.
	# Preserve the compact catalog and verified model version for a later revisit.
	if _reference_index.is_empty():return 0
	var incremental:bool=incremental_pending_index_enabled and _indexed
	var known:Dictionary={};var selected:Dictionary={};var accepted:Array=[]
	for item:Dictionary in pending:known[item.record.uuid]=true
	for entry:Dictionary in entries:
		var uuid:String=entry.compact_record.uuid
		if known.has(uuid):continue
		known[uuid]=true;selected[uuid]=true;accepted.append(entry)
	if accepted.is_empty():return 0
	if incremental:
		# Keep empty cells until a requeue, matching the old query strategy
		# between publications. Prune only keys, without reindexing every row.
		for cell:Vector2i in _pending_index.keys():
			if _pending_index[cell].is_empty():_pending_index.erase(cell)
	var extra:Dictionary=_map.get_meta("extras",{})
	var records:Array=extra.get("rmmo_records",[])
	var write:=0
	for read:int in records.size():
		if selected.has(records[read].uuid):continue
		records[write]=records[read];write+=1
	records.resize(write)
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
		pending.append(item)
		if incremental:
			var previous:Dictionary=_pending_by_record_id.get(uuid,EMPTY_DEMAND)
			if not previous.is_empty():_unindex_pending_item(previous)
			_index_pending_item(item)
	if incremental:
		profile.pending_index_updates=int(profile.get("pending_index_updates",0))+1
		profile.pending_indexed_items=int(profile.get("pending_indexed_items",0))+accepted.size()
	else:
		_indexed=false;_pending_index.clear();_large_pending.clear()
	_demand_membership.clear();_typed_pending.clear();_typed_pending_buildings=-1
	_demand_revision+=1
	_invalidate_collision_queries()
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
	for item:Dictionary in pending:
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
	# Plain definition-policy hints survive individual jobs. Reserve their fixed
	# ceiling outside task leases so an exclusive model can still drain/run.
	profile.geometry_definition_reserved_bytes=CollisionGeometry.MAX_DEFINITION_BYTES if CollisionGeometry.enabled else 0
	_admission.byte_limit=maxi(1,_admission.byte_limit-int(profile.geometry_definition_reserved_bytes))

func is_complete()->bool:return pending.is_empty() and _jobs.is_empty()

func active_workers()->int:
	var count:=0
	for job:Dictionary in _jobs.values():
		if job.has("worker"):count+=1
	return count

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
	while not _jobs.is_empty():
		for path:String in _jobs.keys():
			var job:Dictionary=_jobs[path]
			if job.has("worker"):
				if job.worker.is_alive():continue
				job.result=job.worker.wait_to_finish()
				if is_instance_valid(_drainer):_drainer.forget(job.worker)
				job.erase("worker")
			# Even a scene-less result can own worker-created render resources.
			# Join before releasing its reservation; never wait for live GPU work
			# or take RAW_IMPORT_MUTEX on the main thread.
			Drainer.synchronize_transfer()
			_discard_job(path)
		if not _jobs.is_empty():
			if is_instance_valid(tree):await tree.process_frame
			else:shutdown();return
	profile.active_jobs=0;profile.reserved_bytes=_admission.reserved_bytes
	_raw_retries.clear()
	# pending and prepared paths are unchanged, so rollback can retry cancelled
	# work without duplicating already-published instances or cached models.
	set_process(false)
	if _prefetch_budget_owned:profile.entry_prefetch_mode="quiesced"

func shutdown()->void:
	_invalidate_collision_queries()
	_demand_membership.clear()
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
			Drainer.drain_shutdown(job.worker,job.token)
			job.erase("worker")
		else:Drainer.synchronize_transfer()
		_discard_job(path)
	profile.active_jobs=0;profile.reserved_bytes=_admission.reserved_bytes
	_raw_retries.clear()
	if _prefetch_budget_owned:profile.entry_prefetch_mode="shutdown"
	_runtime_record_ids.clear()
	_pending_by_record_id.clear();_runtime_building_records.clear();_runtime_building_supports.clear()

func _notification(what:int)->void:
	# An off-tree queue has never received _exit_tree. A forced loader teardown
	# must still keep live worker-owned resources alive until their safe drain.
	if what==NOTIFICATION_PREDELETE and (not _jobs.is_empty() or is_instance_valid(_collision_prefetch_service)):shutdown()

func is_idle()->bool:
	# Observers must not do unbudgeted scheduling work. Until the next admitted
	# process refresh, an outdated demand snapshot is conservatively not idle.
	return _candidates_revision==_demand_revision and _demanded.is_empty() and _jobs.is_empty()

func set_demand(id:String,clip:AABB,priority:int=0,kind:String="all",rank_from_player:bool=false)->void:
	if id.is_empty() or not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.z<0:return
	if kind not in ["all","building","road","structure"]:return
	var value:={"clip":clip,"priority":priority,"kind":kind}
	if rank_from_player:value.rank_from_player=true
	if _demands.get(id)==value:return
	_demands[id]=value;_demand_revision+=1;set_process(_active)

func release_demand(id:String)->void:
	_release_collision_request(id)
	_demand_membership.erase(id)
	if _demands.erase(id):
		_demand_revision+=1
		set_process(_active)

func set_group_demand(id:String,group_id:String,priority:int=-2)->bool:
	# Exact indexed membership; a whole-building request must not pull unrelated
	# objects merely because their bounds overlap the building. Scope is still
	# controlled separately by allow_demand_in_scope/set_demand_scope.
	var group:Dictionary=_reference_index.get("groups",{}).get(group_id,{})
	if id.is_empty() or group.is_empty() or not group.get("bounds") is AABB:return false
	var value:Dictionary={"clip":group.bounds,"priority":priority,"kind":"all","group_id":group_id}
	if _demands.get(id)!=value:_demands[id]=value;_demand_revision+=1;set_process(_active)
	return true

func group_is_published(group_id:String)->bool:
	# This is a Deferred publication endpoint, not a physics/readiness claim.
	# Members already installed by initial loading are absent from pending; the
	# authority consumer additionally verifies actual resident membership.
	if not error.is_empty() or not _reference_index.get("groups",{}).has(group_id):return false
	for item:Dictionary in pending:
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
	_demand_scope=allowed;_demand_revision+=1
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
	_invalidate_collision_queries()
	_prefab_texture_attempts.clear()
	for item:Dictionary in _in_clip(clip):
		path_errors.erase(item.path);instance_errors.erase(item.record.uuid)
	profile.failed_paths=path_errors.size();profile.failed_instances=instance_errors.size()
	_demand_revision+=1 # Reopen path cursors and admission fences after repair.
	set_process(_active)

func _path_failed(path:String,reason:String)->void:
	_invalidate_collision_queries()
	path_errors[path]=reason
	profile.failed_paths=path_errors.size()

func _instance_failed(uuid:String,reason:String)->void:
	_invalidate_collision_queries()
	instance_errors[uuid]=reason
	var failed:Dictionary=_demanded_by_id.get(uuid,{})
	if not failed.is_empty():
		var path:String=failed.path
		_path_first.erase(path)
		for item:Dictionary in _demanded_by_path.get(path,[]):
			if not instance_errors.has(item.record.uuid):_path_first[path]=item;break
		_reorder_dispatch_path(path)
	profile.failed_instances=instance_errors.size()

func _index_pending()->void:
	if _indexed:return
	_demand_membership.clear()
	_typed_pending.clear();_typed_pending_buildings=-1
	_pending_by_record_id.clear();_pending_index.clear();_large_pending.clear()
	for item:Dictionary in pending:_index_pending_item(item)
	profile.pending_index_builds=int(profile.get("pending_index_builds",0))+1
	profile.pending_indexed_items=int(profile.get("pending_indexed_items",0))+pending.size()
	_indexed=true

func _index_pending_item(item:Dictionary)->void:
	_pending_by_record_id[item.record.uuid]=item
	var box:AABB=item.bounds
	item.demand_rect=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
	var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>64:_large_pending.append(item);return
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key:=Vector2i(x,z)
			if not _pending_index.has(key):_pending_index[key]=[]
			_pending_index[key].append(item)

static func _erase_pending_identity(values:Array,item:Dictionary)->void:
	for i:int in values.size():
		if is_same(values[i],item):values.remove_at(i);return

func _unindex_pending_item(item:Dictionary,prune_empty:bool=true)->void:
	# Remove this exact old tombstone before appending the new queue member.
	# Keeping its old bucket position would change stable equal-priority order.
	var box:AABB=item.bounds
	var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>64:_erase_pending_identity(_large_pending,item)
	else:
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell:=Vector2i(x,z)
				if not _pending_index.has(cell):continue
				_erase_pending_identity(_pending_index[cell],item)
				if prune_empty and _pending_index[cell].is_empty():_pending_index.erase(cell)
	_pending_by_record_id.erase(item.record.uuid)

static func _intersects(a:AABB,b:AABB)->bool:
	return a.position.x<=b.end.x and a.end.x>=b.position.x and a.position.z<=b.end.z and a.end.z>=b.position.z

func _in_clip(clip:AABB)->Array:
	_index_pending()
	var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
	var candidates:Dictionary={}
	for item:Dictionary in _large_pending:
		if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[item.record.uuid]=item
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size():
		for item:Dictionary in pending:
			if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[item.record.uuid]=item
		return candidates.values()
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):
				if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):candidates[item.record.uuid]=item
	return candidates.values()

func _has_pending_in_clip(clip:AABB)->bool:
	# Readiness needs existence only. Do not allocate/deduplicate all matches or
	# keep scanning after the first unpublished source proves it is not ready.
	_index_pending()
	var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
	for item:Dictionary in _large_pending:
		if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	if (high.x-low.x+1)*(high.y-low.y+1)>_pending_index.size():
		for item:Dictionary in pending:
			if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
		return false
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):
				if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(clip,item.bounds)):return true
	return false

func _refresh_demanded()->void:
	if _candidates_revision==_demand_revision:return
	var began:=Time.get_ticks_usec()
	var candidates:Dictionary={}
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
			if cached.get("clip")==demand.clip and cached.get("kind")==demand.get("kind","all") and cached.get("group")==demand.get("group_id","") and cached.get("buildings")==_runtime_building_records.size():
				memberships[id]=cached.items
				profile.demand_membership_hits=int(profile.get("demand_membership_hits",0))+1
	var support_priorities:Dictionary={};var support_distances:Dictionary={};var support_visits:=0
	var typed_scans:Dictionary=_typed_full_scan_inputs(memberships) if typed_demand_scan_enabled else {}
	var trace=preload("res://scripts/world3d/load_trace.gd")
	if trace.enabled:trace.elapsed("demand.membership_setup",began)
	var rank_started:=Time.get_ticks_usec() if trace.enabled else 0
	for id:String in _demands:
		if not _demand_scope.is_empty() and not _demand_scope.has(id):continue
		var demand:Dictionary=_demands[id]
		var kind:String=demand.get("kind","all");var grouped:bool=demand.has("group_id")
		var priority:int=int(demand.priority);var base_score:=float(priority)*1e15
		var origin:Vector3=_priority if id=="player" or demand.get("rank_from_player",false) else demand.clip.get_center()
		var candidates_for_demand:Array
		if memberships.has(id):candidates_for_demand=memberships[id]
		elif grouped:candidates_for_demand=pending
		elif typed_scans.has(id):
			var matches:Dictionary={}
			var clip:AABB=demand.clip;var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
			for item:Dictionary in typed_scans[id]:
				if not item.get("published",false) and (flat.intersects(item.demand_rect,true) if native_demand_bounds_enabled and item.has("demand_rect") else _intersects(demand.clip,item.bounds)):matches[item.record.uuid]=item
			candidates_for_demand=matches.values()
		else:candidates_for_demand=_in_clip(demand.clip)
		if demand_membership_cache_enabled and not memberships.has(id):
			_demand_membership[id]={"clip":demand.clip,"kind":demand.get("kind","all"),"group":demand.get("group_id",""),"buildings":_runtime_building_records.size(),"items":candidates_for_demand}
			profile.demand_membership_misses=int(profile.get("demand_membership_misses",0))+1
		for item:Dictionary in candidates_for_demand:
			if item.get("published",false) or (grouped and item.get("group_id","")!=demand.group_id):continue
			if kind=="building" and not str(item.get("group_id","")).begins_with("building:") and not _runtime_building_records.has(item.record.uuid):continue
			if kind=="road" and item.get("reference_entry",EMPTY_DEMAND).get("reason","")!="native_road":continue
			if kind=="structure" and item.get("reference_entry",EMPTY_DEMAND).get("reason","") not in ["native_fortification","native_bridge"]:continue
			var uuid:String=item.record.uuid
			var distance:float=_distance_from(item,origin)
			var score:float=base_score+distance
			# Numeric keys precede the borrowed item. Native lexicographic sorting
			# compares doubles without one GDScript callback per comparison, and
			# insertion rank makes equal-score order deterministic.
			if not candidates.has(uuid):candidates[uuid]=[score,candidates.size(),item,priority]
			elif score<float(candidates[uuid][0]):
				var previous:Array=candidates[uuid];previous[0]=score;previous[2]=item;previous[3]=priority
			# Learned imported buildings retain the same supporting landscape as
			# their last verified live index. This closure stays inside the allowed
			# parent ticket/scope; it never broadens demand to unrelated far props.
			if support_priorities.has(uuid) and int(support_priorities[uuid])<=priority:continue
			if not _runtime_building_supports.has(uuid):continue
			support_priorities[uuid]=priority
			for support:String in _runtime_building_supports[uuid]:
				support_visits+=1
				var dependency:Dictionary=_pending_by_record_id.get(support,EMPTY_DEMAND)
				if dependency.is_empty() or dependency.get("published",false):continue
				var support_priority:int=priority-1
				if not support_distances.has(support):support_distances[support]=_distance_from(dependency,_priority)
				var support_score:float=float(support_priority)*1e15+float(support_distances[support])
				if not candidates.has(support):candidates[support]=[support_score,candidates.size(),dependency,support_priority]
				elif support_score<float(candidates[support][0]):
					var previous:Array=candidates[support];previous[0]=support_score;previous[2]=dependency;previous[3]=support_priority
	profile.support_candidate_visits=int(profile.get("support_candidate_visits",0))+support_visits
	var ordered:Array=candidates.values()
	if native_demand_order_enabled:ordered.sort()
	else:ordered.sort_custom(func(a,b):return a[0]<b[0] if a[0]!=b[0] else a[1]<b[1])
	if trace.enabled:trace.elapsed("demand.rank_candidates",rank_started,{"candidates":ordered.size()})
	var commit_started:=Time.get_ticks_usec() if trace.enabled else 0
	_demanded.clear()
	_demanded_by_id.clear()
	_demanded_by_path.clear();_demanded_rank.clear()
	_demanded_priority.clear();_path_first.clear();_publication_queues.clear();_dispatch_paths.clear()
	for row:Array in ordered:
		var item:Dictionary=row[2]
		_demanded_rank[item.record.uuid]=_demanded.size()
		_demanded_priority[item.record.uuid]=row[3]
		_demanded.append(item);_demanded_by_id[item.record.uuid]=item
		if not _demanded_by_path.has(item.path):_demanded_by_path[item.path]=[]
		if not _path_first.has(item.path) and not instance_errors.has(item.record.uuid):
			_path_first[item.path]=item;_dispatch_paths.append(item.path)
		_demanded_by_path[item.path].append(item)
	# ordered already has the exact live ranks; no second whole-path sort in
	# the much smaller dispatch slice is needed after rebuilding demands.
	_dispatch_revision=_demand_revision;_dispatch_capacity=[]
	_candidates_revision=_demand_revision
	if trace.enabled:trace.elapsed("demand.rebuild_dispatch_catalog",commit_started,{"candidates":ordered.size()})
	var elapsed:=Time.get_ticks_usec()-began
	profile.demand_refresh_us=int(profile.get("demand_refresh_us",0))+elapsed
	profile.max_demand_refresh_us=maxi(int(profile.get("max_demand_refresh_us",0)),elapsed)
	profile.demand_refreshes=int(profile.get("demand_refreshes",0))+1

func _typed_full_scan_inputs(cached:Dictionary={})->Dictionary:
	# Kind and source bounds do not change as the player moves. Partition at a
	# catalog change, not every demand refresh. Publication remains a live flag.
	var tickets:Dictionary={}
	for id:String in _demands:
		if cached.has(id):continue
		if not _demand_scope.is_empty() and not _demand_scope.has(id):continue
		var demand:Dictionary=_demands[id];var kind:String=demand.get("kind","all")
		if demand.has("group_id") or kind not in ["building","road","structure"]:continue
		var clip:AABB=demand.clip
		var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
		if (high.x-low.x+1)*(high.y-low.y+1)<=_pending_index.size():continue
		tickets[id]=kind
	if tickets.is_empty():return {}
	if _typed_pending_buildings!=_runtime_building_records.size():
		_typed_pending={"building":[],"road":[],"structure":[]}
		# Preserve large-first ordering and exact intersection before UUID dedup.
		for collection:Array in [_large_pending,pending]:
			for item:Dictionary in collection:
				if str(item.get("group_id","")).begins_with("building:") or _runtime_building_records.has(item.record.uuid):_typed_pending.building.append(item)
				var reason:Variant=item.get("reference_entry",EMPTY_DEMAND).get("reason","")
				if reason=="native_road":_typed_pending.road.append(item)
				if reason in ["native_fortification","native_bridge"]:_typed_pending.structure.append(item)
		_typed_pending_buildings=_runtime_building_records.size()
		profile.typed_partition_builds=int(profile.get("typed_partition_builds",0))+1
		profile.typed_full_scan_prefilter_tests=int(profile.get("typed_full_scan_prefilter_tests",0))+_large_pending.size()+pending.size()
	var count:=0
	for id:String in tickets:
		tickets[id]=_typed_pending[tickets[id]];count+=tickets[id].size()
	profile.typed_full_scan_tickets=int(profile.get("typed_full_scan_tickets",0))+tickets.size()
	profile.typed_full_scan_candidates=int(profile.get("typed_full_scan_candidates",0))+count
	profile.typed_full_scan_unfiltered=int(profile.get("typed_full_scan_unfiltered",0))+tickets.size()*(_large_pending.size()+pending.size())
	return tickets

func register_runtime_building(uuid:String,bounds:AABB,supports:Dictionary)->void:
	if _runtime_building_records.get(uuid)==bounds and _runtime_building_supports.get(uuid,{})==supports:return
	_runtime_building_records[uuid]=bounds;_runtime_building_supports[uuid]=supports.duplicate()
	_demand_revision+=1;set_process(_active)

func _runtime_supports_ready(uuid:String)->bool:
	_index_pending()
	for id:String in _runtime_building_supports.get(uuid,{}):
		var item:Dictionary=_pending_by_record_id.get(id,{})
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
	_collision_pending_snapshot=pending;_collision_pending_count=pending.size()

func _collision_query_slot(id:String)->Dictionary:
	# Publication keeps its cheap old spatial buckets (published aliases are
	# filtered live). An external pending replacement/append instead rebuilds
	# those buckets, so a newly added record cannot hide behind a cached query.
	if not is_same(_collision_pending_snapshot,pending) or _collision_pending_count!=pending.size():
		_indexed=false;_pending_index.clear();_large_pending.clear()
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
			for item:Dictionary in pending:candidates[item.record.uuid]=item
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
	if not _priority_rank_anchor is Vector3 or _priority_rank_anchor.distance_squared_to(flat_position)>=16.:
		_priority_rank_anchor=flat_position
		_demand_revision+=1
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
	for item:Dictionary in pending:
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

func _prefab_texture_plan(item:Dictionary,requests:Array)->Dictionary:
	if (not prefab_texture_preparation_enabled and not _targeted_bridge_textures(item)) or _reference_root.is_empty():return {}
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
	var sources:Dictionary={}
	for at:int in positions:
		if at>=0 and at<_reference_index.get("rows",[]).size():sources.merge(_reference_index.rows[at].get("prefab_textures",{}),true)
	var result:Dictionary=PrefabTextures.estimate(sources,_reference_root) if not sources.is_empty() else {}
	if result.get("rows",{}).is_empty():result={}
	if _prefab_texture_attempts.size()>=16:_prefab_texture_attempts.erase(_prefab_texture_attempts.keys()[0])
	_prefab_texture_attempts[key]=result
	profile.prefab_texture_plan_builds=int(profile.get("prefab_texture_plan_builds",0))+1
	return result

func _estimate_job(item:Dictionary,requests:Array,need_model:bool=true)->Dictionary:
	var reference_bytes:=0
	for request:Dictionary in requests:reference_bytes+=int(request.get("memory_bytes",65536))
	var positions:Array=[]
	for request:Dictionary in requests:
		if request.has("record_index"):positions.append(int(request.record_index))
	for row:Dictionary in preload("res://scripts/world3d/map_dependency_index.gd").terrain_context_rows(_reference_index,positions):reference_bytes+=int(row.memory_bytes)
	var texture_plan:Dictionary=_prefab_texture_plan(item,requests)
	var texture_bytes:int=int(texture_plan.get("estimated_bytes",0))
	if item.get("native_reference",false):
		var collision_workspace:=0
		if CollisionProducts.enabled:
			for request:Dictionary in requests:
				var at:int=int(request.get("record_index",-1))
				if at>=0 and at<_reference_index.get("rows",[]).size() and _reference_index.rows[at].get("prefab_locked",false):collision_workspace=CollisionProducts.WORKSPACE_BYTES;break
		return {"estimated_bytes":maxi(65536,reference_bytes)+texture_bytes+collision_workspace,"exclusive":false,"known":true,"prefab_texture_plan":texture_plan,"collision_workspace_bytes":collision_workspace,"targeted_bridge_textures":_targeted_bridge_textures(item)}
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
	return result

static func _prepare_job_inner(path:String,digest:String,token:RefCounted,manifest:Dictionary,faces:bool,root:String,index:Dictionary,map_path:String,requests:Array,native:bool,need_model:bool,ownership_proof:OwnershipProof=null,model_route:Dictionary={})->Dictionary:
	var started:=Time.get_ticks_usec()
	# This route consumes an already digest-bound template, never source GLB
	# geometry. Cheap preflight is sufficient before reference hydration; one
	# complete final source observation still gates every returned result.
	if not native and not need_model:
		var before:=_preflight_reused_source(path,digest,root,token)
		if not before.error.is_empty():return before
	var prepared:Dictionary={"error":"","records":[],"dependencies":{},"read_profile":{}}
	if not requests.is_empty():
		prepared=preload("res://scripts/world3d/chunk_reference_preparation.gd").prepare(index,requests,map_path,root,token,ownership_proof,model_route.get("prefab_texture_plan",{}),model_route.get("shared_pixels",{}),int(model_route.get("collision_workspace_bytes",0)),preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
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
		var after:=_verify_reused_source(path,digest,root,token)
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
	if model_route.get("stage")=="fixed_native":result=_prepare_fixed_scene(path,digest,token,manifest,faces,root,model_route.candidate,int(geometry.mode))
	else:result=prepare_scene(path,digest,token,manifest,faces,root,model_route.get("stage")=="raw_import",int(geometry.mode),true,preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
	if model_route.get("filter_collision_geometry",false) and str(result.get("error","")).is_empty() and not result.get("native_packet",{}).get("fallback_required",false):
		result.collision_geometry_mode=int(geometry.mode);result.collision_definitions=geometry.definitions
	result.records=prepared.records;result.dependencies=prepared.dependencies;result.read_profile=prepared.read_profile
	for field:String in ["prefab_cpu","prefab_texture_packet","surface_arrays","waiting_pixels","terrain_contexts"]:
		if prepared.has(field):result[field]=prepared[field]
	return result

static func _preflight_reused_source(path:String,digest:String,content_root:String,token:RefCounted)->Dictionary:
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if not Assets._valid_source_digest(digest) or content_root.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):return {"error":"复用素材缺少有效来源身份："+path}
	if not FileAccess.file_exists(path):return {"error":"复用素材来源已丢失："+path}
	# Filesystem/root checks may block; cancellation must stop before rmres IO.
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	return {"error":""}

static func _verify_reused_source(path:String,digest:String,content_root:String,token:RefCounted)->Dictionary:
	if preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return _preflight_reused_source(path,digest,content_root,token)
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
	if state.get_node_count()>65536:return {"ok":false,"reason":"node_limit"}
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
	_doc.terrain_neighbors.data.merge(result.get("terrain_contexts",{}),true)
	if not surfaces.is_empty():
		_doc.load_surface_arrays.merge(surfaces)
		profile.native_surface_records=int(profile.get("native_surface_records",0))+surfaces.size()
		profile.native_surface_worker_us=int(profile.get("native_surface_worker_us",0))+int(result.get("read_profile",{}).get("road_array_prepare_us",0))
	for item:Dictionary in pending:
		if records.has(item.record.uuid):item.record=records[item.record.uuid];item.reference_prepared=true
	profile.reference_records=int(profile.get("reference_records",0))+records.size()
	profile.reference_worker_us=int(profile.get("reference_worker_us",0))+int(result.get("read_profile",{}).get("elapsed_us",0))
	for field:String in result.get("read_profile",{}).get("collision_products",{}):
		profile["collision_product_"+field]=int(profile.get("collision_product_"+field,0))+int(result.read_profile.collision_products[field])
	var reference_profile:Dictionary=result.get("read_profile",{})
	for field in ["preflight_us","preflight_ownership_us","selected_ownership_us","selected_uuid_lookup_us"]:
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
	var preparation:RefCounted
	if specs.size()>256 and not items.is_empty() and _jobs.has(items[0].path):
		var packet:=_stage_publication_packet(items,specs)
		if not packet.has("index_preparation") and not packet.get("index_preparation_skipped",false):
			_apply_publication_fixture_states(specs)
			packet.index_preparation=preload("res://scripts/world3d/stream_index_preparation.gd").new()
			var owned:bool=owned_index_projection_enabled and not packet.get("index_owned_skipped",false)
			for item:Dictionary in items:
				if item.get("native_reference",false) or item.record.has("house_prefab"):owned=false;break
			if owned and private_publication_packet_enabled:packet.index_preparation.begin_runtime_owned(specs)
			elif owned:packet.index_preparation.begin_owned(specs)
			else:packet.index_preparation.begin(specs)
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
	var fixture_changed:=_apply_publication_fixture_states(preparation.fixtures if preparation!=null and preparation.runtime_owned else specs)
	if fixture_changed and preparation!=null and preparation.runtime_owned:
		var packet:=_stage_publication_packet(items,specs)
		preparation.dispose();packet.erase("index_preparation")
		profile.index_preparation_restarts=int(profile.get("index_preparation_restarts",0))+1
		return false
	var publication_packet:RefCounted=preparation.publication_packet if preparation!=null else null
	var registered:Dictionary=Stream.append_specs(_map,specs,preparation)
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
		# Strip hydrated definitions before either removing the spatial member or
		# retaining a tombstone in the diagnostic full-rebuild path.
		if item.has("reference_entry"):item.record=item.reference_entry.compact_record;item.reference_prepared=false
	_remove_published_demand(items);profile.specs+=specs.size()
	var details:Dictionary={"specs":specs.size(),"uuid":items[0].record.uuid if not items.is_empty() else "","index_prepared":preparation!=null}
	publication_metadata=publication_packet
	published.emit(specs)
	publication_metadata=null
	_note_preparation_latency(items)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.publish_commit",commit_began,details)
	return true

func _clear_collision_staging(items:Array)->void:
	for item:Dictionary in items:
		var job:Dictionary=_jobs.get(item.path,{})
		if job.has("collision_staged"):
			var packet:Dictionary=job.collision_staged.get(item.record.uuid,{})
			if packet.has("index_preparation"):packet.index_preparation.dispose()
			job.collision_staged.erase(item.record.uuid)

func _collision_publication_status(uuid:String)->Dictionary:
	if not is_instance_valid(_map):return {}
	var store:Node=_map.get_node_or_null("CollisionInstanceResidency")
	if store==null:return {}
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
	for item:Dictionary in items:
		var uuid:String=item.record.uuid
		removed[uuid]=true;paths[item.path]=true
		if incremental_pending_index_enabled and _indexed:_unindex_pending_item(item,false)
		_demanded_by_id.erase(uuid);_demanded_rank.erase(uuid);_demanded_priority.erase(uuid)
	pending=_without_published(pending,removed)
	_invalidate_collision_queries()
	_demanded=_without_published(_demanded,removed)
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
	job.staged[item.record.uuid]={"item":item,"specs":specs}
	var members:Array=_reference_index.groups[item.group_id].members
	var ordered:Array=[];var combined:Array=[]
	for at in members:
		var uuid:String=_reference_index.extras.rmmo_records[at].uuid
		if instance_errors.has(uuid):
			# A malformed component must not leave an apparently complete owner.
			for member_at in members:_instance_failed(_reference_index.extras.rmmo_records[member_at].uuid,"建筑组件准备失败："+uuid)
			job.staged.clear();return
		if not job.staged.has(uuid):return
		ordered.append(job.staged[uuid].item);combined.append_array(job.staged[uuid].specs)
	_publish_items(ordered,combined);job.staged.clear()

func _publication_ready()->Array:
	var began:=Time.get_ticks_usec();var ready:Array=[]
	# At most one ready item per admitted closure. A collision-owned waiting
	# head retains its consumption cursor. A separate bounded scan lets ready
	# siblings sharing the same model progress without rebuilding/sorting demand.
	for path:String in _jobs:
		if not _prepared_paths.has(path) or path_errors.has(path):continue
		var instance:Dictionary=_jobs[path].get("instance_preparation",{})
		if not instance.is_empty() and (not _demanded_by_id.has(instance.uuid) or instance_errors.has(instance.uuid)):
			instance.cursor.dispose();_jobs[path].erase("instance_preparation");instance={}
		var staged:Dictionary=_jobs.get(path,{}).get("staged",{})
		if not _publication_queues.has(path):_publication_queues[path]={"items":_demanded_by_path.get(path,[]).duplicate(),"cursor":0,"scan":0}
		var queue:Dictionary=_publication_queues[path]
		var checked:=0
		while queue.cursor<queue.items.size() and checked<64:
			var item:Dictionary=queue.items[queue.cursor];checked+=1
			if not _publication_discarded(item,staged):break
			queue.cursor+=1
		if queue.cursor>=queue.items.size():continue
		var at:int=maxi(int(queue.get("scan",queue.cursor)),int(queue.cursor))
		if at>=queue.items.size():at=queue.cursor
		var visited:=0
		while checked<64 and visited<queue.items.size()-queue.cursor:
			var selected_at:=at
			var item:Dictionary=queue.items[at];checked+=1;visited+=1
			at+=1
			if at>=queue.items.size():at=queue.cursor
			queue.scan=at
			if _publication_discarded(item,staged):continue
			if not instance.is_empty() and instance.uuid!=item.record.uuid:continue
			if not _runtime_supports_ready(str(item.record.uuid)):continue
			var collision:Dictionary=_collision_publication_status(str(item.record.uuid))
			if collision.get("owned",false):
				if not str(collision.get("error","")).is_empty():
					_instance_failed(str(item.record.uuid),"提前碰撞发布失败："+str(collision.error));continue
				if collision.get("pending",false):
					profile.collision_publication_waits=int(profile.get("collision_publication_waits",0))+1
					continue
			queue.chosen=selected_at
			ready.append(item);break
	ready.sort_custom(func(a,b):return _demanded_rank[a.record.uuid]<_demanded_rank[b.record.uuid])
	var elapsed:=Time.get_ticks_usec()-began
	profile.ready_scan_us=int(profile.get("ready_scan_us",0))+elapsed
	profile.max_ready_scan_us=maxi(int(profile.get("max_ready_scan_us",0)),elapsed)
	profile.ready_heads=ready.size();profile.ready_scan_items=int(profile.get("ready_scan_items",0))+ready.size()
	return ready

func _main_thread_budget_usec()->int:
	if _entry_loading_allowed() and _map.get_viewport().disable_3d:return COVERED_LOADING_BUDGET_US
	# A pending transfer alone is not proof that its opaque cover has been drawn.
	# Bind the larger budget to this queue's live same-map transaction. Cross-map
	# loaders own their own budgets and activate Deferred only after committing.
	if not is_instance_valid(_host) or not _host.is_inside_tree():return INTERACTIVE_BUDGET_US
	if not "_transfer_pending" in _host or not _host._transfer_pending:return INTERACTIVE_BUDGET_US
	if not "_local_transfer" in _host or not "_transfer_request_serial" in _host:return INTERACTIVE_BUDGET_US
	var context:Dictionary=_host._local_transfer
	if context.is_empty() or context.get("cancelled",false):return INTERACTIVE_BUDGET_US
	if not context.get("scope_applied",false) or not _demand_scope.has(context.get("demand_id","")):return INTERACTIVE_BUDGET_US
	if context.get("map")!=_map or context.get("deferred")!=self:return INTERACTIVE_BUDGET_US
	if context.get("request")!=_host._transfer_request_serial:return INTERACTIVE_BUDGET_US
	var cover:Variant=context.get("cover")
	if not is_instance_valid(cover) or not cover is TransferLoading:return INTERACTIVE_BUDGET_US
	if not cover.is_opaque_drawn():return INTERACTIVE_BUDGET_US
	var viewport:=_host.get_viewport()
	if cover.get_viewport()!=viewport or not viewport.disable_3d:return INTERACTIVE_BUDGET_US
	return COVERED_LOADING_BUDGET_US

static func automatic_loading_worker_limit(logical_threads:int)->int:
	return clampi(floori(float(logical_threads)*.5),2,6)

func _restore_uncovered_worker_capacity()->void:
	# Transaction cleanup can run after this queue stopped processing. Restore
	# synchronously, but never raise capacity from a scope setter before dispatch.
	if _saved_interactive_worker_limit>=0 and _main_thread_budget_usec()!=COVERED_LOADING_BUDGET_US:
		_update_loading_worker_capacity(INTERACTIVE_BUDGET_US)

func _update_loading_worker_capacity(budget_usec:int)->void:
	var processors:=OS.get_processor_count()
	var configured:=clampi(loading_worker_limit,2,6) if loading_worker_limit>0 else automatic_loading_worker_limit(processors)
	var covered:=budget_usec==COVERED_LOADING_BUDGET_US
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
	# These counters cover the shared acceptance/publication slice, including its
	# ready scan. Worker handoff/synchronization, demand refresh and dispatch are
	# outside this slice; elapsed_us is not a whole-frame or GPU-time measurement.
	var mode:="covered_loading" if budget==COVERED_LOADING_BUDGET_US else "interactive"
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
	# At least one real publication unit must advance even if result acceptance
	# or a previous scan spent this frame's soft budget. Individual resource
	# publication and the final whole-group append are not preemptible.
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
		var prefab_parts:Variant={} if preload("res://scripts/world3d/load_trace.gd").enabled else null
		if item.record.has("house_prefab"):
			var prepared:Dictionary=_jobs.get(item.path,{}).get("result",{}).get("prefab_cpu",{}).get(item.record.house_prefab.sha256,{})
			var textures:Dictionary=_jobs.get(item.path,{}).get("result",{}).get("prefab_texture_packet",{})
			# Prepared image/ticket packets already have a separate scoped owner and
			# invalidation protocol. Keep that route synchronous and unchanged.
			if (material_publication_slices_enabled and textures.is_empty()
				and not Prefab._meshes.has(item.record.house_prefab.sha256)
				and prepared.get("sha256")==item.record.house_prefab.sha256 and prepared.get("data") is Dictionary
				and prepared.get("geometry_keys",[]).size()==prepared.data.meshes.size()
				and prepared.get("collision_faces",[]).size()==prepared.data.meshes.size()):
				if not pixel_job.has("material_textures"):pixel_job.material_textures={}
				var phase:=preload("res://scripts/world3d/material_publication.gd").step(prepared.data.materials,_doc.load_paint_validation,_doc.load_material_pool,pixel_job.material_textures)
				if phase!=0:
					if phase<0:
						_instance_failed(publication_id,"预制件材质准备失败："+publication_id)
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
			if not preload("res://scripts/world3d/house_prefab.gd").publish_prepared(item.record,prepared,_doc.load_paint_validation,_doc.load_material_pool,prefab_parts,textures):
				textures={};prepared={}
				_instance_failed(item.record.uuid,"后台预制件数据无法发布："+item.record.uuid);_stage_building(item,[])
				_account_work_unit(timing,unit_began);continue
			textures={};prepared={}
		var prefab_finished:=Time.get_ticks_usec()
		var instance_parts:Variant={} if preload("res://scripts/world3d/load_trace.gd").enabled else null
		if not item.get("native_reference",false):
			var cursor:=preload("res://scripts/world3d/asset_instance_preparation.gd").new()
			cursor.begin(_doc,item.record,pixel_job.publication_template_owner)
			pixel_job.instance_preparation={"uuid":publication_id,"cursor":cursor,"phase":"asset","prefab_us":prefab_finished-unit_began,"instance_us":0,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts}
		else:
			var holder:Node3D=_doc._mesh(item.record,true,instance_parts)
			if _instance_error(holder,item):_account_work_unit(timing,unit_began);continue
			var cursor:=preload("res://scripts/world3d/instance_spec_preparation.gd").new()
			cursor.begin(holder,_local_collision_order(item),int(item.get("draw_order",0)))
			pixel_job.instance_preparation={"uuid":publication_id,"cursor":cursor,"phase":"spec","prefab_us":prefab_finished-unit_began,"instance_us":Time.get_ticks_usec()-prefab_finished,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts}
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.instance_begin",unit_began,{"uuid":publication_id,"path":item.path,"prefab_parts_ms":prefab_parts,"instance_parts_ms":instance_parts})
		var revision:=_demand_revision
		_advance_instance_specs(item,pixel_job,unit_began,maxi(1,budget_usec-(Time.get_ticks_usec()-began)))
		_account_work_unit(timing,unit_began)
		if _demand_revision!=revision:break
	profile.publication_units=int(profile.get("publication_units",0))+int(timing.units)
	return timing

func _advance_instance_specs(item:Dictionary,job:Dictionary,unit_began:int,budget_usec:int)->void:
	var preparation:Dictionary=job.instance_preparation
	if preparation.get("phase","")=="asset":
		var asset:RefCounted=preparation.cursor;var began:=Time.get_ticks_usec()
		var ready:bool=asset.advance(budget_usec)
		var elapsed:=Time.get_ticks_usec()-began
		profile.asset_instance_units=int(profile.get("asset_instance_units",0))+1
		profile.max_asset_instance_unit_us=maxi(int(profile.get("max_asset_instance_unit_us",0)),elapsed)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.asset_instance_step",began,{"uuid":item.record.uuid,"ready":ready})
		if not ready:
			var queue:Dictionary=_publication_queues[item.path];queue.scan=queue.chosen;return
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
		var queue:Dictionary=_publication_queues[item.path];queue.scan=queue.chosen
		return
	var specs:Array=cursor.specs
	job.erase("instance_preparation")
	var append_began:=Time.get_ticks_usec()
	if not str(item.get("group_id","")).is_empty():_stage_building(item,specs)
	else:_publish_items([item],specs)
	var publication:={"uuid":item.record.uuid,"path":item.path,"group_id":str(item.get("group_id","")),"prefab_us":preparation.prefab_us,"instance_us":preparation.instance_us,"collect_us":cursor.profile.elapsed_us,"collect_slices":cursor.profile.slices,"preparation_spans_frames":cursor.profile.slices>1,"append_us":Time.get_ticks_usec()-append_began,"elapsed_us":Time.get_ticks_usec()-unit_began,"covered":_main_thread_budget_usec()==COVERED_LOADING_BUDGET_US}
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
	holder.free();_instance_failed(str(item.record.uuid),"后台物件构建失败："+str(item.record.uuid))
	if not str(item.get("group_id","")).is_empty():_stage_building(item,[])
	return true

static func _manifest_matches(path:String,expected:Dictionary)->bool:
	if expected.is_empty() or preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return true
	var current:Dictionary=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(path)
	return current.get("known",false) and current.get("json_sha256")==expected.get("json_sha256") and current.get("file_length")==expected.get("file_length")

static func _native_private(packed:PackedScene,path:String,token:RefCounted,manifest:Dictionary,faces:bool,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
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
	if not _manifest_matches(path,manifest):result.error=ERR_BUSY;return result
	if token!=null and token.is_cancelled():result.error=ERR_SKIP;result.cancelled=true;return result
	result.error=OK;return result

static func _prepare_fixed_scene(path:String,digest:String,token:RefCounted,manifest:Dictionary,faces:bool,root:String,candidate:Dictionary,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
	var began:=Time.get_ticks_usec()
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if root.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(path,root):return {"error":"素材路径无效："+path}
	if not digest.is_empty() and (not Assets._valid_source_digest(digest) or candidate.get("source_sha")!=digest):return {"error":"素材已验证来源与原生候选不符："+path}
	if (digest.is_empty() and manifest.is_empty()) or not _manifest_matches(path,manifest):return {"error":"素材边界在后台准备前发生变化："+path}
	var packet:=CompiledPreparation.read(path,candidate,root,_native_private.bind(path,token,manifest,faces,geometry_mode),preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
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
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.prepare",began,{"path":path,"fixed_native":true})
	return result

static func prepare_scene(path:String,digest:String,token:RefCounted=null,expected_manifest:Dictionary={},collision_faces_required:bool=false,content_root:String="",raw_only:bool=false,geometry_mode:int=CollisionGeometry.ALL,pack_for_cache:bool=false,trusted_package:bool=false)->Dictionary:
	var began:=preload("res://scripts/world3d/load_trace.gd").begin("deferred.prepare")
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if content_root.is_empty():
		if OS.get_thread_caller_id()!=OS.get_main_thread_id():return {"error":"后台素材准备缺少资源根快照："+path}
		content_root=preload("res://scripts/world3d/map_paths.gd").external_root()
	if content_root.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):return {"error":"素材路径无效："+path}
	var Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
	if digest.is_empty() and not trusted_package:
		if expected_manifest.is_empty():return {"error":"缺少后台素材边界快照："+path}
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备前发生变化："+path}
	var source_digest:=preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path,digest) if trusted_package else FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.source_identity" if trusted_package else "deferred.source_sha",began,{"path":path})
	if source_digest.is_empty() or (not digest.is_empty() and source_digest!=digest):return {"error":"素材在后台准备前发生变化："+path}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	# Strict transactions verify source bytes after private preparation as well.
	var compiled:Dictionary={"hit":false,"elapsed_us":0}
	if not raw_only:compiled=Compiled.read(path,source_digest,content_root,true,trusted_package)
	if not compiled.hit and not compiled.get("retained_resources",[]).is_empty():
		# Post-allocation schema/path failures are not resource-free misses.
		# Keep the charged native result for main-thread failure disposal.
		return {"error":"原生素材校验失败："+path,"native_packet":compiled}
	var owners:=preload("res://scripts/world3d/model_resource_owners.gd").new()
	owners.packed=compiled.get("packed")
	var scene:Node
	if not compiled.hit:
		var fallback:=_fallback_scene(path,token,content_root)
		if not fallback.error.is_empty():return fallback
		owners=fallback.resource_owners
		fallback.erase("resource_owners")
		scene=fallback.scene
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	# Bind deferred classification to the same header after the potentially slow
	# full-file hash and parser read as well as before them.
	if not expected_manifest.is_empty() and not trusted_package:
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备期间发生变化："+path,"scene":scene,"resource_owners":owners}
	# The queue admits static self-contained files only. Every node/resource here
	# belongs to this worker and has never entered a SceneTree or shared scene cache.
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	var generate_started:=Time.get_ticks_usec()
	if compiled.hit:
		scene=preload("res://scripts/world3d/compiled_asset_cache.gd").instantiate(compiled.packed)
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.compiled_instantiate",generate_started,{"path":path})
	if scene==null:return {"error":"素材构建失败："+path,"resource_owners":owners}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	var capture_started:=Time.get_ticks_usec()
	var captured:=_capture_static_meshes(scene,collision_faces_required,token,geometry_mode)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.cpu_capture",capture_started,{"path":path,"collision_faces":collision_faces_required})
	if not captured.error.is_empty():
		captured.scene=scene;captured.resource_owners=owners
		return captured
	var packed:PackedScene
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
	var final_digest:=source_digest if trusted_package else FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.source_binding" if trusted_package else "deferred.final_source_sha",final_sha_started,{"path":path})
	if final_digest!=source_digest or (not content_root.is_empty() and not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root)):return {"error":"素材在后台准备期间发生变化："+path,"scene":scene,"resource_owners":owners}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene,"resource_owners":owners}
	if packed!=null:
		# The private Node instances can retire on their own worker, but every
		# renderer Resource must survive until main has joined and synchronized.
		Drainer._retain_visual_resources(scene,owners.visuals)
		var dispose_began:=Time.get_ticks_usec();scene.free();scene=null
		preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_private_disposal",dispose_began,{"path":path})
		captured.packed=packed
	else:captured.scene=scene
	captured.merge({"resource_owners":owners,"elapsed_us":Time.get_ticks_usec()-began,"source_digest":source_digest,"compiled":compiled.hit,"compiled_read_us":compiled.elapsed_us})
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.prepare",began,{"path":path})
	return captured

static func _fallback_scene(path:String,token:RefCounted,content_root:String)->Dictionary:
	# Godot's default GLTF extension registry is process-wide. Native products
	# read concurrently; raw fallback generation is serialized across loaders.
	var preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
	var waiting:=Time.get_ticks_usec()
	preparation.RAW_IMPORT_MUTEX.lock()
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.raw_import_wait",waiting,{"path":path})
	if token!=null and token.is_cancelled():
		preparation.RAW_IMPORT_MUTEX.unlock();return {"error":"素材准备已取消","cancelled":true}
	# A candidate miss can retry raw after waiting for another importer. Recheck
	# containment before allocating parser resources or reading the source.
	if content_root.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(path,content_root):
		preparation.RAW_IMPORT_MUTEX.unlock();return {"error":"素材路径无效："+path}
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var owners:=preload("res://scripts/world3d/model_resource_owners.gd").new()
	owners.document=document;owners.state=state
	preload("res://scripts/world3d/runtime_probe_controls.gd").configure_gltf(state)
	var began:=Time.get_ticks_usec()
	var code:=document.append_from_file(path,state,0,path.get_base_dir())
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_parse",began,{"path":path})
	if code!=OK:
		preparation.RAW_IMPORT_MUTEX.unlock();return {"error":"素材读取失败："+path+" "+error_string(code),"resource_owners":owners}
	if preload("res://scripts/world3d/asset_bounds_manifest.gd").has_native_identity(state.json):
		preparation.RAW_IMPORT_MUTEX.unlock();return {"error":"原生地图不能作为独立后台素材："+path,"resource_owners":owners}
	if token!=null and token.is_cancelled():
		preparation.RAW_IMPORT_MUTEX.unlock();return {"error":"素材准备已取消","cancelled":true,"resource_owners":owners}
	began=Time.get_ticks_usec()
	var scene:=Io.generate_scene(document,state,true)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.scene_generate",began,{"path":path})
	preparation.RAW_IMPORT_MUTEX.unlock()
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

func _process(_delta:float)->void:
	if not _active or _cancelled:return
	if not error.is_empty():
		_retire_failed_jobs()
		return
	var desired:=_main_thread_budget_usec()
	var budget:=FrameBudget.allowance("publication",desired,desired==COVERED_LOADING_BUDGET_US)
	# Demand scans, stale-template disposal and scheduling are main-thread work
	# too. A denied lane must not perform them outside the frame ledger, nor
	# publish using the previous frame's demand set.
	if budget<=0:return
	var frame_began:=Time.get_ticks_usec()
	_update_loading_worker_capacity(desired)
	_refresh_demanded()
	var required:Dictionary=_demanded_by_path
	_retire_stale_prepared(required)
	profile.frame_bookkeeping_us=Time.get_ticks_usec()-frame_began
	_poll_jobs(required)
	_resume_pixel_jobs(get_tree())
	# Preserve the existing publication/dispatch ownership gate during handoff.
	if is_instance_valid(_host) and "_ready_for_play" in _host and not _host._ready_for_play and not _entry_loading_allowed():FrameBudget.charge("publication",frame_began);return
	# Refill before publication, while there is a bounded scheduling slice. A
	# slow indivisible upload must not push dispatch into unaccounted frame tail.
	_dispatch_deadline=mini(frame_began+budget,Time.get_ticks_usec()+maxi(100,budget/4))
	_dispatch_jobs(get_tree());_dispatch_deadline=0
	# Covered initial entry owns publication until it is ready; ready results
	# keep their full byte reservation, preventing an unbounded result queue.
	var began:=frame_began
	var acceptance:Dictionary={"units":0,"unit_us":0,"max_unit_us":0}
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		if job.has("worker") or not job.has("result") or job.get("accepted",false) or job.result.get("waiting_pixels",false):continue
		if acceptance.units>0 and Time.get_ticks_usec()-began>=budget:break
		var unit_began:=Time.get_ticks_usec()
		var result:Dictionary=job.result
		if not _geometry_coverage_current(path,result):
			# A new stronger consumer appeared while the private worker ran. Keep
			# its budget until the old resources are disposed, then re-admit the
			# complete model route; never fill missing arrays under a reuse lease.
			_discard_job(path);_prepared_paths.erase(path)
			profile.geometry_requirement_retries=int(profile.get("geometry_requirement_retries",0))+1
			_account_work_unit(acceptance,unit_began);continue
		if job.has("pixel_consumer"):
			var texture_packet:Dictionary=result.get("prefab_texture_packet",{})
			if not Prefab.tickets_valid(job.pixel_tickets,texture_packet.get("sources",{})):
				_retry_pixel_job(path,{},"Resident texture changed before acceptance");_account_work_unit(acceptance,unit_began);continue
			texture_packet.resident_textures=job.pixel_tickets.duplicate()
		if result.has("scene") or result.has("packed"):
			var cached:bool=Assets.cache_packed(path,result.packed,str(result.get("source_digest",""))) if result.has("packed") else Assets.cache_scene(path,result.scene,str(result.get("source_digest","")))
			if not cached:
				job.result.erase("scene");_discard_job(path);_path_failed(path,"无法缓存后台素材："+path)
				_account_work_unit(acceptance,unit_began);continue
			if result.has("packed"):
				if result.has("resource_owners"):result.resource_owners.transfer_template(result.packed)
				profile.worker_packed_models=int(profile.get("worker_packed_models",0))+1
			job.result.erase("scene");job.result.erase("packed");profile.models+=1
			var cache_key:="compiled_hits" if result.get("compiled",false) else "compiled_misses"
			profile[cache_key]=int(profile.get(cache_key,0))+1
		# Another map may have replaced/evicted this path while the CPU reuse
		# transaction ran. Retry preparation instead of consuming a different
		# template under the verified old geometry identity.
		if result.get("reused_model",false) and not _reuse_template_current(path,job,str(result.get("source_digest",""))):
			_prepared_paths.erase(path);_discard_job(path);_account_work_unit(acceptance,unit_began);continue
		if result.get("reused_model",false) and not _accept_reused_faces(job,result):
			_prepared_paths.erase(path);_discard_job(path);_account_work_unit(acceptance,unit_began);continue
		_accept_prepared_records(result)
		if not job.get("native",false):preload("res://scripts/world3d/runtime_asset_cache_scope.gd").claim(_map,path)
		_remember_geometry_definitions(path,result)
		if not job.get("native",false):
			job.publication_template_owner=Assets._scenes.get(path)
			for uuid:String in job.get("publication_ids",[]):
				if _demanded_by_id.has(uuid):_demanded_by_id[uuid].model_verified=true
		job.accepted=true;_prepared_paths[path]=true;_publication_queues.erase(path);_scheduler_epoch+=1
		profile.worker_us+=int(result.get("elapsed_us",0))
		for key in ["capture_us","face_us","capture_bytes","face_bytes","captured_meshes","skipped_geometry_nodes"]:profile[key]=int(profile.get(key,0))+int(result.get(key,0))
		if result.has("source_digest"):source_signatures[path]=result.source_digest
		_account_work_unit(acceptance,unit_began)
	# One clock covers both acceptance and publication. This is a soft slice,
	# not a deadline for indivisible packing, group append or signal callbacks.
	var publication:=_publish_ready(began,budget)
	_record_main_thread_budget(desired,began,acceptance,publication)
	profile.frame_publication_allowance_us=budget
	# Publication observers can teach a new building/support closure. Refresh
	# that revision in the next admitted frame, not for a second full scan in
	# this already expensive commit frame. Stale membership cannot release jobs.
	# A joined group still owns its bytes until its ready records have
	# been published or discarded. Slow publication cannot create an unbounded
	# CPU result backlog beside the GPU/resource pipeline.
	for path:String in _jobs.keys() if _candidates_revision==_demand_revision else []:
		var job:Dictionary=_jobs[path]
		if job.get("accepted",false) and _job_consumed(job):_discard_job(path)
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
	var value:Dictionary=preload("res://scripts/world3d/compiled_asset_footprint.gd").candidate(path,root,digest)
	_native_candidates[path]={"digest":digest,"value":value.duplicate(true)}
	profile.native_candidate_lookups=int(profile.get("native_candidate_lookups",0))+1
	return value

func _refresh_raw_memory(path:String)->Dictionary:
	return MemoryEstimate.estimate(path)

func _start_worker(worker:Thread,prepare:Callable)->int:
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
	# Retire completed/cancelled jobs independently; never wait for a slow sibling.
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
			var result:Dictionary=job.worker.wait_to_finish()
			if is_instance_valid(_drainer):_drainer.forget(job.worker)
			job.erase("worker")
			_record_pixel_packet(path,job,result)
			if job.get("pixel_continuation",false):
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
			# The native-reference branch returns only private CPU arrays/Images,
			# never a renderer resource. Do not stall core rendering to join it.
			if not job.get("native",false):Drainer.synchronize_transfer()
			if not _entry_prefetch.is_empty():
				profile.entry_prefetch_joined_jobs=int(profile.get("entry_prefetch_joined_jobs",0))+1
				profile.entry_prefetch_sync_us=int(profile.get("entry_prefetch_sync_us",0))+Time.get_ticks_usec()-sync_started
				profile.entry_prefetch_last_ready_us=Time.get_ticks_usec()
			_admission.set_stage(path,"ready")
			if ready_worker_yield_enabled:_admission.park(path)
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
	if tree==null or _cancelled or not error.is_empty():return
	var dispatch_started:=Time.get_ticks_usec()
	var deadline:=_dispatch_deadline if _dispatch_deadline>0 else dispatch_started+1000
	var capacity:Array=[_demand_revision,_admission.reserved_bytes,_admission.active_workers(),_jobs.size(),_scheduler_epoch,prefetch_only,native_entry_prefetch_enabled,prefab_texture_preparation_enabled,shared_prefab_texture_preparation_enabled,bridge_texture_preparation_enabled]
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
			_yield_lower_job(_path_priority(path));_dispatch_cursor-=1;break
		if not _admission.has_capacity():
			if _path_priority(path)<0:_yield_lower_job(_path_priority(path))
			_dispatch_cursor-=1;break
		attempts+=1
		var requests:Array=_reference_requests(path)
		# One immutable dispatch decision governs both reservation and worker.
		# A missing/replaced template is retried by acceptance with a new full
		# reservation, never imported by this reduced-budget reuse job.
		var need_model:bool=not _prepared_paths.has(path)
		var native:bool=next.get("native_reference",false)
		var needs_faces:=false;var faces_known:=false
		var geometry_consumers:Array=_geometry_consumers(path) if CollisionGeometry.enabled and not native else []
		var geometry_mode:int=int(CollisionGeometry.resolve(geometry_consumers,[],[],path,_collision_definition_modes.get(path,{})).mode) if CollisionGeometry.enabled and not native else CollisionGeometry.ALL
		var template_owner:PackedScene
		if not native and not need_model:
			if _cached_model_matches(path):template_owner=Assets._scenes.get(path)
			if template_owner==null:
				_prepared_paths.erase(path);need_model=true
		var reuse_faces:Dictionary={}
		if (collision_first_enabled or CollisionGeometry.enabled) and not native and not need_model:
			faces_known=true
			if CollisionGeometry.enabled:needs_faces=geometry_mode!=CollisionGeometry.NONE
			else:
				for item:Dictionary in pending:
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
				var raw_bytes:=int(next.get("memory",{}).get("estimated_bytes",_admission.byte_limit))
				if offered.get("estimated_bytes") is int and offered.estimated_bytes>0 and offered.get("exclusive") is bool:
					# Both fixed and legacy readers may allocate the known native
					# product. Never discard its larger bound after GLB cleanup.
					raw_item.memory=next.get("memory",{}).duplicate()
					raw_item.memory.estimated_bytes=maxi(raw_bytes,offered.estimated_bytes)
					raw_item.memory.exclusive=bool(raw_item.memory.get("exclusive",false)) or offered.exclusive
					if native_preparation_enabled:
						candidate=offered.duplicate(true);stage="fixed_native"
						if native_budget_enabled:raw_item.memory={"estimated_bytes":candidate.estimated_bytes,"exclusive":candidate.exclusive,"known":true}
					estimate=_estimate_job(raw_item,requests,true)
					estimate.raw_model_bytes=raw_bytes
					estimate.native_model_bound_bytes=offered.estimated_bytes
		estimate.stage=stage
		if CollisionGeometry.enabled and not native:
			# Snapshot/learned-policy containers are private task inputs/outputs.
			# They remain charged through publication just like other job results.
			var descriptors:int=geometry_consumers.size()*2+_collision_definition_modes.get(path,{}).size()+mini(requests.size(),CollisionGeometry.MAX_CONSUMERS)
			estimate.geometry_workspace_bytes=65536+descriptors*CollisionGeometry.DESCRIPTOR_BYTES
			estimate.estimated_bytes=int(estimate.estimated_bytes)+int(estimate.geometry_workspace_bytes)
		var pixel_offer:Dictionary={};var pixel_tickets:Dictionary={};var reserve_estimate:Dictionary=estimate
		if (shared_prefab_texture_preparation_enabled or estimate.get("targeted_bridge_textures",false)) and not estimate.get("prefab_texture_plan",{}).is_empty():
			var plan:Dictionary=estimate.prefab_texture_plan
			if not _pixel_retries.has(path):pixel_tickets=Prefab.texture_tickets(plan.rows,_doc.load_material_pool)
			var cached:Dictionary={}
			for key:String in pixel_tickets:cached[key]=pixel_tickets[key].source_sha
			_shared_images.admission=_admission
			pixel_offer=_shared_images.offer(plan,cached,_pixel_retries.get(path,{}).get("revisions",{}))
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
		var worker:=Thread.new();var token:=Drainer.CancelToken.new()
		# A model is immutable and shared by all its instances; include future
		# collision consumers so reusing a decorative instance is still safe.
		if not faces_known:
			for item:Dictionary in pending:
				if item.path==path and str(item.record.get("collision",""))!="none":needs_faces=true;break
		_drainer=Drainer.for_tree(tree);_drainer.watch(worker,token)
		var publication_ids:Array=_job_publication_ids(path,requests)
		_jobs[path]={"worker":worker,"token":token,"estimate":estimate,"publication_ids":publication_ids,"native":native,"stage":stage,"candidate":candidate,"digest":digest,"dispatch_us":Time.get_ticks_usec()}
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
		token.set_meta("admission_release",_admission.release.bind(path))
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
			profile.reuse_reference_reservation_bytes=int(profile.get("reuse_reference_reservation_bytes",0))+int(estimate.estimated_bytes)
		preload("res://scripts/world3d/load_trace.gd").instant("deferred.dispatch",{"path":path,"stage":stage,"need_model":need_model,"native":native,"reserved_bytes":estimate.estimated_bytes,"references":requests.size()})
		var prepare:=_make_prepare_task(path,digest,token,next,needs_faces,content_root,requests,native,need_model)
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
	profile.peak_reserved_bytes=_admission.peak_bytes;profile.peak_jobs=_admission.peak_jobs
	profile.admission=_admission.snapshot()
	profile.shared_pixels=_shared_images.snapshot()
	profile.demanded_instances=_demanded.size();profile.deferred_instances=pending.size()

func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,needs_faces:bool,content_root:String,requests:Array,native:bool,need_model:bool)->Callable:
	var job:Dictionary=_jobs.get(path,{})
	var route:Dictionary={"stage":job.get("stage","legacy"),"candidate":job.get("candidate",{}).duplicate(true)}
	if job.has("geometry_consumers"):
		route.filter_collision_geometry=true;route.geometry_consumers=job.geometry_consumers.duplicate(true)
		route.geometry_known=_collision_definition_modes.get(path,{}).duplicate();route.geometry_mode=int(job.geometry_mode)
	route.prefab_texture_plan=job.get("estimate",{}).get("prefab_texture_plan",{}).duplicate(true)
	route.collision_workspace_bytes=int(job.get("estimate",{}).get("collision_workspace_bytes",0))
	route.reuse_face_snapshots=job.get("reuse_face_snapshots",[])
	if job.has("shared_pixels"):route.shared_pixels=job.shared_pixels
	return _prepare_job.bind(path,digest,token,item.get("manifest",{}),needs_faces,content_root,_reference_index,_reference_map_path,requests,native,need_model,_reference_proof,route)

func _discard_job(path:String)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.deferred_asset_loader._discard_job") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_invalidate_collision_queries()
	var job:Dictionary=_jobs[path]
	if job.has("instance_preparation"):
		job.instance_preparation.cursor.dispose();job.erase("instance_preparation")
	_publication_queues.erase(path);_scheduler_epoch+=1
	for key:Array in _prefab_texture_attempts.keys():
		if key[0]==path:_prefab_texture_attempts.erase(key)
	# The main-thread document borrows the worker output only for this job.
	# Published Mesh/CPU-mesh resources retain their own array references.
	var output:Dictionary=job.get("result",{}) if job.get("result",{}) is Dictionary else {}
	for uuid:String in output.get("surface_arrays",{}):
		_doc.load_surface_arrays.erase(uuid)
	for uuid:String in output.get("terrain_contexts",{}):_doc.terrain_neighbors.data.erase(uuid)
	# Large importer states retain thousands of GPU/CPU owners. Keep this same
	# byte reservation until the tree-owned retirement cursor drops every alias.
	var deferred_release:=preload("res://scripts/world3d/resource_retirement.gd").defer_model_packet(output,Callable(_admission,"release").bind(path),_admission)
	if not deferred_release:deferred_release=preload("res://scripts/world3d/resource_retirement.gd").defer_import_packet(output,Callable(_admission,"release").bind(path),_admission)
	if deferred_release:
		_admission.park(path);_admission.set_stage(path,"resource_retirement")
	if not output.is_empty():Drainer.dispose_result(output)
	if job.has("staged"):job.staged.clear()
	if job.has("collision_staged"):
		for packet:Dictionary in job.collision_staged.values():
			if packet.has("index_preparation"):packet.index_preparation.dispose()
		job.collision_staged.clear()
	job.erase("reuse_face_snapshots");job.erase("reuse_face_owners");job.erase("reuse_template_owner");job.erase("publication_template_owner")
	job.erase("pixel_tickets");job.erase("shared_pixels");job.erase("material_textures")
	Drainer.release_shared(job.token)
	# Unpublished ready definitions must not outlive their released reservation.
	# Published specs/runtime records retain their independently resident data.
	for item:Dictionary in pending:
		if item.path!=path:continue
		item.erase("model_verified")
		if item.has("reference_entry") and item.get("reference_prepared",false):
			item.record=item.reference_entry.compact_record;item.reference_prepared=false
	if job.token.has_meta("admission_release"):job.token.remove_meta("admission_release")
	_jobs.erase(path)
	if not deferred_release:_admission.release(path)
	_raw_retries.erase(path);_pixel_retries.erase(path)
	if job.token.has_meta("admission_owner"):job.token.remove_meta("admission_owner")

func _retry_pixel_job(path:String,revisions:Dictionary,reason:String)->void:
	var count_:int=int(_pixel_retries.get(path,{}).get("count",0))+1
	var current:Dictionary=revisions.duplicate()
	_discard_job(path);_prepared_paths.erase(path)
	if count_>2:_path_failed(path,"Shared image retry limit: "+reason);return
	_pixel_retries[path]={"count":count_,"revisions":current}
	profile.pixel_retries=int(profile.get("pixel_retries",0))+1

func _record_pixel_packet(path:String,job:Dictionary,packet:Dictionary)->void:
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
		var requested:Dictionary={}
		for key:String in plan.rows:requested[key]=[plan.rows[key].path,plan.rows[key].flip]
		var worker:=Thread.new();job.worker=worker;job.pixel_continuation=true
		# The previous result can contain raw/compiled GPU owners. Keep it on main
		# (or the drainer after exit), never pass it to the CPU continuation.
		job.token.set_meta("prefab_continuation_result",job.result)
		_drainer=Drainer.for_tree(tree);_drainer.watch(worker,job.token)
		var task:=_resume_pixels.bind(requested,plan,_reference_root,job.token,shared,_reference_map_path,str(_reference_index.get("source_sha256","")),job.result.get("dependencies",{}).duplicate(),path if not job.get("native",false) else "",str(job.result.get("source_digest","")))
		if _start_worker(worker,task)!=OK:
			_drainer.forget(worker);job.erase("worker");_discard_job(path);_path_failed(path,"Cannot resume shared image verification");continue
		profile.pixel_continuations=int(profile.get("pixel_continuations",0))+1

static func _resume_pixels(requested:Dictionary,plan:Dictionary,root:String,token:RefCounted,shared:Dictionary,map_path:String,map_sha:String,dependencies:Dictionary,model_path:String,model_sha:String)->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:=_resume_pixels_inner(requested,plan,root,token,shared,map_path,map_sha,dependencies,model_path,model_sha)
	result.continuation_us=Time.get_ticks_usec()-began
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.pixel_continuation",began,{"consumer":shared.get("consumer",""),"error":result.get("error",""),"waiting":result.get("waiting_pixels",false),"sources":requested.size()})
	return result

static func _resume_pixels_inner(requested:Dictionary,plan:Dictionary,root:String,token:RefCounted,shared:Dictionary,map_path:String,map_sha:String,dependencies:Dictionary,model_path:String,model_sha:String)->Dictionary:
	var packet:=PrefabTextures.prepare(requested,plan,root,token,false,shared)
	if not packet.error.is_empty() or packet.get("waiting_pixels",false):return packet
	var Paths=preload("res://scripts/world3d/map_paths.gd")
	var Store=preload("res://scripts/world3d/map_resource_store.gd")
	if token.is_cancelled():packet.error="Shared image continuation cancelled";packet.cancelled=true;return packet
	if not Paths.allowed(map_path,root) or FileAccess.get_sha256(map_path)!=map_sha or not Paths.allowed(map_path,root) or (not preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and not Store.verify_dependencies(dependencies,map_path,root,1)):packet.error="Reference identity changed while awaiting shared images";return packet
	if not model_path.is_empty() and not _verify_reused_source(model_path,model_sha,root,token).error.is_empty():packet.error="Model changed while awaiting shared images";return packet
	if not PrefabTextures.verify(packet,root,token):packet.error="Shared image source changed before handoff";packet.cancelled=token.is_cancelled()
	return packet

func _nearest_index()->int:
	var at:=-1;var nearest:=INF
	for i in pending.size():
		var distance:float=_distance(pending[i])
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
		var spec:Dictionary=Stream._spec(node)
		spec.transform=pose;spec.position=pose.origin;spec.rotation=pose.basis.get_euler()
		var box:AABB=pose*node.get_aabb()
		spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(box.position);spec.chunk_max=Stream.chunk_key(box.end)
		preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
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
	error=reason
	for job:Dictionary in _jobs.values():job.token.cancel()
	set_process(not _jobs.is_empty());failed.emit(reason)

func _exit_tree()->void:
	if _scene_handoff:return
	_cancelled=true
	_cancel_collision_prefetch("prefetch_owner_exited")
	for id:String in _collision_request_ids.keys():_release_collision_request(id)
	_prefab_texture_attempts.clear()
	for path:String in _jobs.keys():
		var job:Dictionary=_jobs[path]
		job.token.cancel()
		if job.has("worker"):
			if is_instance_valid(_drainer) and _drainer.is_inside_tree():_drainer.abandon(job.worker)
			else:Drainer.drain_shutdown(job.worker,job.token)
		else:_discard_job(path)
	_jobs.clear()
	_runtime_record_ids.clear()
