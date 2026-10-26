extends Node3D
## Spatial render cache. The source nodes, UUIDs, physics and records remain independent.
const Geometry = preload("res://scripts/world3d/ground_batch_geometry.gd")
const FrameBudget = preload("res://scripts/world3d/frame_work_budget.gd")
const Timeline = preload("res://scripts/world3d/ground_batch_timeline.gd")
const WorkerRetirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
static var canonical_buildings_enabled:=true
static var inflight_building_sharing_enabled:=true
static var sliced_source_collection_enabled:=true
static var resumable_bin_ledger_enabled:=true # Diagnostic old partial-bucket restart control.
static var legacy_loading_worker_wait_enabled:=false # Diagnostic control; frame callbacks never wait on live workers.
static var covered_source_coalescing_enabled:=true
static var closed_building_preparation_enabled:=true # Complete index-owned units, unchanged budgets/workers.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SUSPENDED_DRAW:="stream_suspended_draw"
var suspended_source_uploads:=0
var _production_turn:=false
var production_turns_while_preparing:=0
var closed_units_prepared:=0
var closed_unit_groups_admitted:=0
var covered_source_waits:=0
var groups: Dictionary = {}
var pending: Array[String] = []
var enabled := true
var rebuild_count := 0
var last_build_ms := 0.0
var max_build_ms := 0.0
var _material_keys: Dictionary = {}
var _instance_meshes: Dictionary = {}
var _workers: Array = []
var _retiring_workers:=false
var _retired_leases:Array=[]
var _resume_processing:=true
const MAX_WORKERS=3
var _generation := 0
var last_commit_ms := 0.0
var max_commit_ms := 0.0
var last_sync_ms := 0.0
var sync_profile: Dictionary={}
var sync_count:=0
var resumed_collections:=0
var prepared_source_visits:=0
var packed_source_visits:=0
var bin_ledger_reused_rows:=0
var bin_ledger_invalidated_buckets:=0
var bin_ledger_invalidated_rows:=0
var reused_collection_roots:=0
var completed_prefix_reuses:=0
var completed_source_visits_avoided:=0
var release_groups_visited:=0
var live_worker_joins:=0
var live_worker_join_us:=0
var _member_groups: Dictionary={}
var _audit_cursor:=0
var _audit_keys:Array=[]
var _building_meshes:Dictionary={}
var building_mesh_hits:=0
var building_worker_reuses:=0
var worker_packed_surfaces:=0
var main_packed_surfaces:=0
var worker_surface_prepare_us:=0
const INTERACTIVE_WORK_BUDGET_USEC:=2000
const SETTLED_WHITE_WORK_BUDGET_USEC:=6000
static var settled_white_budget_enabled:=true
static var covered_idle_budget_enabled:=true
static var profile_preparation_units_enabled:=false
const MAX_LOADING_WORK_BUDGET_USEC:=24000
var work_budget_usec:=INTERACTIVE_WORK_BUDGET_USEC
var _loading_budget_serial:=0
var _loading_budgets:Array[Dictionary]=[]
var residency_budget_frame:=-1
var residency_budget_remaining_usec:=2000
# Residency requests prepare on the main thread in bounded slices. Existing
# batches stay visible until replacement membership is ready; workers still only
# receive immutable geometry snapshots. Editor sync/flush remain synchronous.
var _preparation:Dictionary={}
var _residency_descriptors:Dictionary={}
# Raw, pre-filter bins survive completed runtime rounds. Generic requests still
# check live eligibility/pose. The explicit immutable append path reuses its
# completed source prefix until identity, edit or lifetime invalidation.
var _residency_bins:Dictionary={}
var _next_residency:Dictionary={}
var last_prepare_slice_ms:=0.0
var max_prepare_slice_ms:=0.0

func begin_loading_budget(budget_usec:int=16000)->int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.begin_loading_budget") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# A temporary scheduling allowance, not a deadline for native mesh uploads
	# or one source's geometry capture. Callers end the token on success/failure.
	if budget_usec<=0 or budget_usec>MAX_LOADING_WORK_BUDGET_USEC:return 0
	_loading_budget_serial+=1
	_loading_budgets.append({"token":_loading_budget_serial,"usec":budget_usec})
	return _loading_budget_serial

func end_loading_budget(token:int)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.end_loading_budget") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Removing an older load cannot undo a newer load's allowance. The base
	# setting also remains editable while the temporary allowance is active.
	var index:=_loading_budgets.find_custom(func(scope):return scope.token==token)
	if index<0:return false
	_loading_budgets.remove_at(index)
	return true

func effective_work_budget_usec()->int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.effective_work_budget_usec") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not _loading_budgets.is_empty():return int(_loading_budgets.back().usec)
	if work_budget_usec==INTERACTIVE_WORK_BUDGET_USEC and _can_use_settled_budget():return SETTLED_WHITE_WORK_BUDGET_USEC
	return work_budget_usec

func _can_use_settled_budget()->bool:
	# Borrow unused publication/collision time for white rendering or a covered
	# textured tail. Interactive textured traversal keeps its original budget.
	# Read live ownership state at consumption, not a latched "finished" flag:
	# a new destination/publication must revoke the allowance in the same frame.
	var map:=get_parent()
	if not can_borrow_publication_budget(map):return false
	if map==null or not map.has_meta("stream_chunk"):return false
	if map.get_meta("stream_chunk")!=map.get_meta("stream_target",null):return false
	if map.get_meta("stream_source_revision",0)!=map.get_meta("stream_applied_source_revision",0):return false
	for key:String in ["stream_jobs","stream_append_pending"]:
		if not map.get_meta(key,[]).is_empty():return false
	for key:String in ["stream_candidate_work","stream_candidates","stream_collision_priority_work"]:
		if map.has_meta(key):return false
	return true

static func can_borrow_publication_budget(map:Node)->bool:
	# The idle publication lane can also finish residency. Requiring residency
	# itself to be finished left that allowance unused behind a pending queue.
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	if map==null:return false
	var queue:=map.get_node_or_null("DeferredAssets")
	if queue==null or not queue.is_idle():return false
	var white:bool=settled_white_budget_enabled and controls.white_materials and controls.discard_map_textures
	if not white and (not covered_idle_budget_enabled or not queue._covered_loading_ready()):return false
	if map.has_meta("retirement_schema_preparation") and not map.get_meta("retirement_schema_preparation").complete:return false
	if map.has_meta("retirement_frame_budget"):
		var ledger:RefCounted=map.get_meta("retirement_frame_budget")
		if ledger._frame==Engine.get_process_frames() and ledger._total>0:return false
	return true

func share_residency_budget(started:int)->void:
	# Used by both gameplay and the white traversal probe. Streaming and batch
	# work share one allowance; an indivisible collision overrun leaves zero.
	var total:=SETTLED_WHITE_WORK_BUDGET_USEC if can_borrow_publication_budget(get_parent()) else 3000
	residency_budget_frame=Engine.get_process_frames()
	residency_budget_remaining_usec=maxi(0,total-(Time.get_ticks_usec()-started))

static func _fingerprint(value:Variant)->String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._fingerprint") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value));return hash.finish().hex_encode()

func _enter_tree()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._enter_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_retiring_workers=false;set_process(_resume_processing)

func _ready() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._ready") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	name = "GroundRenderBatches"
	set_meta("stream_instance", true)

static func freeze(node: MeshInstance3D, captured: Mesh = null) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.freeze") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.mesh is Cpu: return
	var cpu: Mesh = captured if captured != null else Cpu.capture(node.mesh)
	var materials: Array[Material]=[]
	for slot in node.mesh.get_surface_count(): materials.append(node.get_active_material(slot))
	# Geometry can be shared, but per-instance paint must not overwrite another
	# source's materials when the original GPU mesh is shared by both objects.
	if cpu.materials!=materials:
		var local:=Cpu.new(); local.surfaces=cpu.surfaces;local.lods=cpu.lods; local.bounds=cpu.bounds; local.box_size=cpu.box_size; local.source_reference=cpu.source_reference; local.materials=materials
		if cpu.has_meta("static_batch_geometry_signature"): local.set_geometry_key(cpu.geometry_key())
		preload("res://scripts/world3d/prepared_cpu_upload.gd").inherit(cpu,local)
		local._collision_faces=cpu._collision_faces; cpu=local
	for slot in node.get_surface_override_material_count(): node.set_surface_override_material(slot,null)
	# Empty the instance's override list before assigning a CPU mesh (no RS base).
	node.mesh = null; node.material_override = null; node.mesh = cpu
	if node.has_meta("paint_source"): node.set_meta("paint_source", Cpu.capture(node.get_meta("paint_source")))

static func restore(node: MeshInstance3D) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.restore") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.mesh is Cpu: node.mesh = preload("res://scripts/world3d/prepared_cpu_upload.gd").restore(node.mesh,str(node.name))
	if node.has_meta(SUSPENDED_DRAW):node.remove_meta(SUSPENDED_DRAW)

func clear(restore_sources: bool = true) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.clear") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if get_parent()!=null:
		var proxy:=get_parent().get_node_or_null("DistantBuildingProxy")
		if proxy!=null:proxy.clear()
	_preparation.clear();_residency_descriptors.clear();_residency_bins.clear();_next_residency.clear()
	for group: Dictionary in groups.values(): _drop(group,restore_sources)
	groups.clear(); pending.clear(); _material_keys.clear(); _instance_meshes.clear(); _member_groups.clear();_building_meshes.clear()
	_audit_keys.clear();_audit_cursor=0

func release(ids: Array) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.release") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_preparation.clear();_residency_descriptors.clear();_residency_bins.clear();_next_residency.clear() # Editor mutations invalidate captured descriptors.
	_release_groups(ids)

func release_sources(nodes: Array) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.release_sources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# A local editor replacement knows exactly which sources are dirty. Keep
	# immutable descriptors for every other source; regroup on the frame budget.
	_preparation.clear();_residency_bins.clear();_next_residency.clear()
	var ids:Array=[]
	for node in _expanded_sources(nodes):
		if not is_instance_valid(node):continue
		ids.append(str(node.name))
		_residency_descriptors.erase(node.get_instance_id())
	_release_groups(ids)

func retire_sources(nodes:Array,suspended:Dictionary={})->void:
	# A retiring source is about to be destroyed, so rebuilding its GPU buffers
	# just before free is wasted work. Surviving members still need their exact
	# standalone draw until a replacement batch is published.
	_preparation.clear();_residency_bins.clear();_next_residency.clear()
	var ids:Array=[];var retiring:Dictionary={}
	for node in _expanded_sources(nodes):
		if not is_instance_valid(node):continue
		ids.append(str(node.name));retiring[node.get_instance_id()]=true
		_residency_descriptors.erase(node.get_instance_id())
	_release_groups(ids,retiring,suspended)

func _release_groups(ids: Array,retiring:Dictionary={},suspended:Dictionary={}) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._release_groups") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Editing is synchronous: remove the old combined draw before changing a source.
	var affected: Dictionary={}
	for id in ids:
		if _member_groups.has(str(id)): affected[_member_groups[str(id)]]=true
	for key: String in affected:
		if not groups.has(key): continue
		release_groups_visited+=1
		_drop(groups[key],true,retiring,suspended); groups.erase(key); pending.erase(key)

func _drop(group: Dictionary, restore_sources: bool = true,retiring:Dictionary={},suspended:Dictionary={}) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._drop") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var watcher=group.get("pose_watcher")
	if is_instance_valid(watcher):
		watcher.changed=Callable();watcher.set_notify_transform(false);watcher.queue_free()
	for id in group.get("member_ids",[]):_member_groups.erase(id)
	for node in group.members:
		if not is_instance_valid(node):continue
		_member_groups.erase(str(node.name))
		var callback:Callable=group.get("exit_callback",Callable())
		if callback.is_valid() and node.tree_exiting.is_connected(callback):node.tree_exiting.disconnect(callback)
		var visible_callback:Callable=group.get("visible_callback",Callable())
		if visible_callback.is_valid() and node.visibility_changed.is_connected(visible_callback):node.visibility_changed.disconnect(visible_callback)
	if is_instance_valid(group.get("visual")): group.visual.free()
	if not restore_sources: return
	for node in group.members:
		if not is_instance_valid(node) or node.is_queued_for_deletion() or retiring.has(node.get_instance_id()):continue
		if suspended.has(node.get_instance_id()) and node.mesh is Cpu:
			# The streaming caller proved this source is outside current demand.
			# Leave destruction on its budgeted cursor. A changed destination must
			# explicitly restore this node, even though its identity still exists.
			node.set_meta(SUSPENDED_DRAW,true);suspended_source_uploads+=1
		else:restore(node)

func _invalidate_group(key:String,generation:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._invalidate_group") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not groups.has(key) or groups[key].generation!=generation:return
	if Timeline.enabled:Timeline.record("source_exit",generation,Time.get_ticks_usec(),[key,groups[key].category,groups[key].members.size()])
	if _residency_bins.get("immutable_append",false):_residency_bins={}
	var group:Dictionary=groups[key]
	groups.erase(key);pending.erase(key)
	_drop(group)

func _watch_group(key:String,group:Dictionary)->void:
	if Timeline.enabled:Timeline.record("queued",group.generation,Time.get_ticks_usec(),[key,group.category,group.members.size(),group.vertices,sync_count])
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._watch_group") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Residency can free sources before the next sync. Invalidate the combined
	# visual immediately, including when a non-leading member leaves the tree.
	var callback:=_invalidate_group.bind(key,group.generation)
	group.exit_callback=callback;group.member_ids=[]
	group.moving=group.category=="building" and group.members[0].get_meta("ground_batch_record",{}).has("fixture")
	if group.category=="building":
		group.visible_callback=_sync_visibility.bind(key,group.generation)
		group.members[0].visibility_changed.connect(group.visible_callback)
	for node in group.members:
		group.member_ids.append(str(node.name))
		node.tree_exiting.connect(callback)

func _sync_visibility(key:String,generation:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._sync_visibility") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not groups.has(key) or groups[key].generation!=generation:return
	var group:Dictionary=groups[key]
	if is_instance_valid(group.get("visual")) and is_instance_valid(group.members[0]):
		group.visual.visible=group.members[0].is_visible_in_tree()

func _sync_pose(key:String,generation:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._sync_pose") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not groups.has(key) or groups[key].generation!=generation:return
	var group:Dictionary=groups[key]
	if not is_instance_valid(group.get("visual")) or group.members.is_empty() or not is_instance_valid(group.members[0]):return
	var pose:Transform3D=group.members[0].global_transform
	if pose!=group.last_source_pose:
		group.visual.global_transform=pose*group.relative_pose;group.last_source_pose=pose

func sync(nodes: Array, excluded: Array = []) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.sync") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_residency_descriptors.clear() # Editor callers may have changed any material/geometry.
	request_sync(nodes,excluded)
	while not _preparation.is_empty(): _prepare_step(0)

func sync_selection(nodes: Array, excluded: Array) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.sync_selection") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Selection changes no source geometry/materials. Restore selected sources
	# immediately, then regroup remaining sources within the normal frame budget.
	_preparation.clear();_residency_bins.clear();_next_residency.clear()
	_release_groups(_expanded_exclusions(nodes,excluded))
	request_sync(nodes,excluded)

func invalidate_source(node: MeshInstance3D) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.invalidate_source") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# An excluded source may change size/materials without changing its pose.
	# Its next selection release must recapture its own descriptor only.
	_residency_descriptors.erase(node.get_instance_id())
	_residency_bins={} # An explicit edit revokes the immutable append contract.
	if resumable_bin_ledger_enabled:
		# A pending generation also owns descriptors and already packed rows.
		# It cannot keep those owners after geometry/material/metadata changes.
		# Excluded editor selections have no membership in that generation;
		# dragging one must not cancel the other sources' pending regroup.
		var excluded_source:bool=not _preparation.is_empty() and (str(node.name) in _preparation.get("excluded",[]) or str(node.name) in _preparation.get("root_excluded",[]))
		if not excluded_source:_preparation.clear();_next_residency.clear()
		_release_groups([str(node.name)])

static func _expanded_sources(nodes:Array)->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._expanded_sources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var result:Array=[]
	for node in nodes:
		if not is_instance_valid(node):continue
		if node.has_meta("model_component_batch_sources"):
			for source in node.get_meta("model_component_batch_sources"):
				if is_instance_valid(source):result.append(source)
		else:result.append(node)
	return result

static func _expanded_exclusions(nodes:Array,excluded:Array)->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._expanded_exclusions") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if excluded.is_empty():return []
	var result:=excluded.duplicate()
	for node in nodes:
		if not is_instance_valid(node) or str(node.name) not in excluded:continue
		if node.has_meta("model_component_batch_sources"):
			for source in node.get_meta("model_component_batch_sources"):
				if is_instance_valid(source):result.append(str(source.name))
	return result

func request_residency_sync(nodes:Array,excluded:Array=[],immutable_append:bool=false)->void:
	# Streaming appends immutable sources. Keep the already collected names
	# while that exact root prefix survives; arbitrary editor requests still
	# supersede preparation through request_sync. Native array comparison uses
	# Node identities, including replacement/removal, without a script scan.
	if _preparation.get("unit_plan_active",false) and _preparation.runtime_excluded==excluded and _preparation.runtime_enabled==enabled:
		var previous:Array=_preparation.runtime_roots
		if nodes.size()>=previous.size() and nodes.slice(0,previous.size())==previous:
			if nodes.size()>previous.size():_next_residency={"nodes":nodes.duplicate(),"excluded":excluded.duplicate(),"immutable_append":immutable_append}
			return
	if sliced_source_collection_enabled and not _preparation.is_empty() and _preparation.phase in ["collect","prepare","bin"] and _preparation.has("runtime_roots") and _preparation.runtime_excluded==excluded and _preparation.runtime_enabled==enabled:
		var previous:Array=_preparation.runtime_roots
		if nodes.size()>=previous.size() and nodes.slice(0,previous.size())==previous:
			resumed_collections+=1;reused_collection_roots+=previous.size()
			if nodes.size()==previous.size():return
			var additions:=nodes.slice(previous.size())
			if _preparation.phase!="collect":
				# Keep prepared owners and each bucket's completed prefix. New
				# earlier names invalidate only the packing order they can change.
				_preparation.phase="collect";_preparation.cursor=0;_preparation.items=additions
				_preparation.root_excluded=excluded.duplicate()
			else:_preparation.items.append_array(additions)
			_preparation.runtime_roots=nodes.duplicate()
			return
	# Once grouping is complete, finish its bounded drop/add pass. Appending a
	# source cannot invalidate that subset. Restarting here threw away the raw
	# bins just before they became reusable, on nearly every publication burst.
	if sliced_source_collection_enabled and _preparation.has("runtime_roots") and _preparation.phase in ["unique","filter","drop","add"] and _preparation.runtime_excluded==excluded and _preparation.runtime_enabled==enabled:
		var previous:Array=_preparation.runtime_roots
		if nodes.size()>=previous.size() and nodes.slice(0,previous.size())==previous:
			if nodes.size()>previous.size():_next_residency={"nodes":nodes.duplicate(),"excluded":excluded.duplicate(),"immutable_append":immutable_append}
			return
	var completed:Dictionary=_residency_bins
	var reuse_completed:=false
	if sliced_source_collection_enabled and immutable_append and completed.get("immutable_append",false) and completed.runtime_excluded==excluded and completed.runtime_enabled==enabled:
		var previous:Array=completed.runtime_roots
		reuse_completed=nodes.size()>=previous.size() and nodes.slice(0,previous.size())==previous
		if reuse_completed:
			completed_prefix_reuses+=1;completed_source_visits_avoided+=completed.named.size()
			if nodes.size()==previous.size() and _preparation.get("phase")!="await_sources":return
	request_sync(nodes,excluded)
	_preparation.runtime_roots=nodes.duplicate();_preparation.runtime_excluded=excluded.duplicate();_preparation.runtime_enabled=enabled
	_preparation.immutable_append=immutable_append
	_preparation.prepared_descriptors={};_preparation.prepare_names={}
	_preparation.bin_names={};_preparation.bin_keys={};_preparation.dirty_bins={};_preparation.bin_remaining={}
	# Main-thread single-writer ledger, owned by this existing raw-bin state.
	# Descriptor identity includes its source owner, geometry/material grouping
	# and pose; edits/removal revoke the corresponding completed membership.
	_preparation.bin_pending={};_preparation.bin_last_name={};_preparation.bin_rebuild={}
	if closed_building_preparation_enabled and immutable_append and get_parent()!=null:
		_preparation.unit_candidates={}
		_preparation.unit_groups=get_parent().get_meta("stream_building_groups",{})
		_preparation.unit_specs=get_parent().get_meta("stream_by_id",{})
	if sliced_source_collection_enabled and not completed.is_empty():
		# Transfer the private raw-bin state; no shared geometry or material copy.
		# Collection remains complete so removals and changed eligibility are seen.
		for field:String in ["prepared_descriptors","bin_names","bin_keys","desired"]:_preparation[field]=completed[field]
		for field:String in ["bin_pending","bin_last_name"]:_preparation[field]=completed.get(field,{})
		if reuse_completed:
			# The streaming owner explicitly promises unchanged prefix sources.
			# Retain collected names and prepared bins across a completed round,
			# exactly as during an unfinished round. Generic/editor callers still
			# recheck live eligibility; edits, lifetime invalidation and retirement
			# revoke this cache, while identity/removal checks reject a new prefix.
			_preparation.named=completed.named
			_preparation.items=nodes.slice(completed.runtime_roots.size())
		else:_preparation.refresh_bins=true

func _collect_named(state:Dictionary,node:Node)->void:
	var key:=str(node.name)
	if state.has("unit_candidates") and not state.named.has(key):
		var spec:Dictionary=state.unit_specs.get(key,{})
		var record:Dictionary=node.get_meta("ground_batch_record",{})
		var owner:String=record.get("building",{}).get("id","")
		# Both identities must come from the published index. Merely counting
		# current stream jobs or similarly named imported components is unsafe.
		if not owner.is_empty() and spec.get("render_building","")==owner and state.unit_groups.has(owner) and Geometry.category(record)=="building":
			if not state.unit_candidates.has(owner):state.unit_candidates[owner]=[]
			state.unit_candidates[owner].append(key)
	if state.get("refresh_bins",false):state.prepare_names[key]=true
	elif state.has("prepared_descriptors") and state.named.get(key)!=node:
		_remove_prepared_descriptor(state,key);state.prepare_names[key]=true
	state.named[key]=node

func _closed_unit_valid(state:Dictionary,unit:Dictionary)->bool:
	var current:Dictionary=get_parent().get_meta("stream_building_groups",{}) if get_parent()!=null else {}
	return current.has(unit.owner) and is_same(current[unit.owner],unit.members) and current[unit.owner].size()==unit.names.size()

func _next_closed_unit(state:Dictionary)->void:
	state.cursor=0;state.phase="prepare";state.active_unit={}
	if not state.unit_queue.is_empty():
		state.active_unit=state.unit_queue.pop_front()
		closed_units_prepared+=1
		state.items=state.active_unit.names
	else:
		state.items=state.remaining_prepare
		state.remaining_prepare=[]
	state.items.sort()

func _admit_group(key:String,group:Dictionary,state:Dictionary,copy_raw:bool=false)->void:
	if groups.has(key):return
	if not group.members.all(func(node):return is_instance_valid(node) and not node.is_queued_for_deletion()):
		if resumable_bin_ledger_enabled:state.immutable_append=false
		return
	# Renderer data must never be written into the retained raw-bin dictionary.
	if copy_raw:group=group.duplicate()
	_generation+=1;group.generation=_generation
	groups[key]=group;pending.append(key);_watch_group(key,group)
	for node in group.members:_member_groups[str(node.name)]=key

func request_sync(nodes:Array,excluded:Array=[])->void:
	if Timeline.enabled:Timeline.record("request",sync_count+1,Time.get_ticks_usec(),[nodes.size(),_preparation.get("phase",""),pending.size(),_workers.size()])
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.request_sync") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# New residency supersedes unfinished preparation. No source has been hidden
	# by preparation; lifetime signals immediately remove already-built stale draws.
	for id in _residency_descriptors.keys():
		if _residency_descriptors[id].reference.get_ref()==null:_residency_descriptors.erase(id)
	_residency_bins={};_next_residency={}
	sync_count+=1
	sync_profile={"material_us":0,"geometry_us":0,"capture_us":0}
	_material_keys.clear()
	# Expanding every source here previously ran outside the preparation budget.
	# Runtime sources are immutable until a new request supersedes this one;
	# editor sync/flush still drain the same cursor synchronously.
	_preparation={"phase":"collect","cursor":0,"items":nodes.duplicate() if sliced_source_collection_enabled else _expanded_sources(nodes),"named":{},"desired":{},"excluded":excluded.duplicate() if sliced_source_collection_enabled else _expanded_exclusions(nodes,excluded),"cpu_us":0,"expand_components":sliced_source_collection_enabled,"root_excluded":excluded.duplicate(),"components":[],"component_cursor":0,"exclude_components":false}
	for cached:String in _instance_meshes.keys():
		if _instance_meshes[cached].get_ref()==null:_instance_meshes.erase(cached)
	for cached:String in _building_meshes.keys():
		if _building_meshes[cached].reference.get_ref()==null:_building_meshes.erase(cached)

func _prepare_node(node:Node,desired:Dictionary,excluded:Array)->void:
	prepared_source_visits+=1
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._prepare_node") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not node is MeshInstance3D or not node.has_meta("ground_batch_record") or str(node.name) in excluded: return
	if not node.is_visible_in_tree() or node.transparency > 0 or node.material_overlay != null or node.skin != null: return
	var record: Dictionary = node.get_meta("ground_batch_record")
	# Runtime residency only adds/removes immutable sources. Their captured
	# grouping data survives chunk crossings and CPU/GPU mesh substitution.
	# sync/release clear this cache before editor changes; no material is pinned.
	var identity:=node.get_instance_id()
	if _residency_descriptors.has(identity):
		var cached:Dictionary=_residency_descriptors[identity]
		if cached.reference.get_ref()==node and cached.pose==node.global_transform:
			_append_descriptor(node,cached,desired);return
	if not Geometry.candidate(record) or not node.global_basis.is_conformal() or (not record.get("vegetation_batch",false) and not node.global_basis.get_scale().is_equal_approx(Vector3.ONE)) or node.global_basis.determinant() < 0: return
	var keys: Array = []; var eligible := true
	var mark:=Time.get_ticks_usec()
	for slot in node.mesh.get_surface_count():
		var material: Material = node.get_active_material(slot)
		if not _material_keys.has(material): _material_keys[material] = Geometry.material_key(material)
		var key: String = _material_keys[material]
		if key.is_empty(): eligible = false; break
		keys.append(key)
		if material is ShaderMaterial and (absf(node.global_basis.y.x) > .00001 or absf(node.global_basis.y.z) > .00001): eligible = false
	if not eligible: return
	sync_profile.material_us+=Time.get_ticks_usec()-mark
	# Small surfaces use 128 m bins; a 200 m terrain uses 512 m bins. Never
	# merge a whole city, so culling and local edits stay spatially bounded.
	var extent: Vector3 = (node.custom_aabb if node.custom_aabb.has_volume() else node.get_aabb()).size
	var kind:=Geometry.category(record)
	var cell := maxf(32. if kind in ["fortification","vegetation"] else 128., pow(2., ceil(log(maxf(1., maxf(extent.x,extent.z))) / log(2.))) * (1. if kind in ["fortification","vegetation"] else 2.))
	var center: Vector3 = node.global_position
	var shape: Array = [record.terrain_mesh.columns,record.terrain_mesh.rows] if record.has("terrain_mesh") else []
	if kind=="vegetation":shape=[record.asset_path]
	if kind=="building":
		var b:Dictionary=record.building
		var presentation:String="ceiling" if str(b.part).ends_with("/ceiling") else ("roof" if b.role=="roof" else "body")
		shape=[b.id,b.floor,presentation,record.get("fixture",{}).get("id","")]
	var merge_base:=_fingerprint([kind,floor(center.x/cell),floor(center.z/cell),cell,keys,shape,node.cast_shadow,node.layers])
	# Keep repeated modules together even when a spatial cell also contains
	# other stone shapes. Mixing shapes defeats vertex-buffer sharing.
	mark=Time.get_ticks_usec()
	var cpu:=Cpu.capture(node.mesh)
	sync_profile.capture_us+=Time.get_ticks_usec()-mark; mark=Time.get_ticks_usec()
	if kind=="fortification": shape=[_geometry_signature(cpu)]
	sync_profile.geometry_us+=Time.get_ticks_usec()-mark
	var base:String = _fingerprint([kind,floor(center.x/cell),floor(center.z/cell),cell,keys,shape,node.cast_shadow,node.layers]) if kind=="fortification" else merge_base
	var vertices := Geometry.vertex_count(node.mesh)
	if vertices > Geometry.MAX_VERTICES: return
	# Building cache identities used to hash every member together at worker
	# launch. Resolve each immutable identity inside the existing sliced pass.
	if kind=="building":cpu.geometry_key()
	if profile_preparation_units_enabled:
		preload("res://scripts/world3d/load_trace.gd").instant("batch.geometry_preparation",{"uuid":record.get("uuid",str(node.name)),"kind":kind,"vertices":vertices,"prefab":record.has("house_prefab"),"asset":record.get("asset_path",""),"building":record.get("building",{}),"elapsed_us":Time.get_ticks_usec()-mark,"geometry":cpu.get_meta("static_batch_geometry_signature","")})
	var descriptor:={"reference":weakref(node),"pose":node.global_transform,"base":base,"merge_base":merge_base,"category":kind,"vertices":vertices,"keys":keys,"limit":Geometry.member_limit(record),"origin":Vector3((floor(center.x/cell)+.5)*cell,0,(floor(center.z/cell)+.5)*cell)}
	_residency_descriptors[identity]=descriptor
	_append_descriptor(node,descriptor,desired)

func _append_descriptor(node:Node,descriptor:Dictionary,desired:Dictionary)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._append_descriptor") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not _preparation.is_empty() and _preparation.phase=="prepare" and _preparation.has("prepared_descriptors"):
		var name_:=str(node.name)
		_preparation.current_eligible=true
		var previous:Dictionary=_preparation.prepared_descriptors.get(name_,{})
		if is_same(previous,descriptor):return
		_remove_prepared_descriptor(_preparation,name_)
		_preparation.prepared_descriptors[name_]=descriptor
		if not _preparation.bin_names.has(descriptor.base):_preparation.bin_names[descriptor.base]={}
		_preparation.bin_names[descriptor.base][name_]=true;_preparation.dirty_bins[descriptor.base]=true
		if resumable_bin_ledger_enabled:
			if not _preparation.bin_pending.has(descriptor.base):_preparation.bin_pending[descriptor.base]={}
			_preparation.bin_pending[descriptor.base][name_]=true
			# First-fit member/vertex limits depend on sorted source order. A
			# new earlier member really changes layout; it must rebuild its bin.
			if _preparation.bin_last_name.has(descriptor.base) and name_<=str(_preparation.bin_last_name[descriptor.base]):_preparation.bin_rebuild[descriptor.base]=true
		return
	packed_source_visits+=1
	var bin:=0;var key:String=descriptor.base+":0"
	while desired.has(key) and (desired[key].members.size()>=descriptor.limit or desired[key].vertices+descriptor.vertices>Geometry.MAX_VERTICES):
		bin+=1;key=descriptor.base+":"+str(bin)
	if not desired.has(key):
		desired[key]={"merge_base":descriptor.merge_base,"category":descriptor.category,"members":[],"vertices":0,"keys":descriptor.keys,"signature":[],"origin":descriptor.origin,"sort_name":str(node.name)}
		if not _preparation.is_empty() and _preparation.phase=="bin" and _preparation.has("bin_keys"):
			if not _preparation.bin_keys.has(descriptor.base):_preparation.bin_keys[descriptor.base]=[]
			_preparation.bin_keys[descriptor.base].append(key)
	if resumable_bin_ledger_enabled and groups.has(key) and is_same(desired[key].members,groups[key].members):
		# Completed raw bins share read-only arrays with their live draw. A
		# later append must detach the changed bucket before writing membership
		# or signatures, so the old generation remains intact until replacement.
		var owned:Dictionary=desired[key].duplicate()
		owned.members=owned.members.duplicate();owned.signature=owned.signature.duplicate();desired[key]=owned
	desired[key].members.append(node);desired[key].vertices+=descriptor.vertices
	desired[key].signature.append([node.get_instance_id(),node.global_transform])
	if resumable_bin_ledger_enabled and not _preparation.is_empty() and _preparation.phase=="bin" and _preparation.has("bin_pending"):
		_preparation.bin_pending[descriptor.base].erase(str(node.name))
		_preparation.bin_last_name[descriptor.base]=str(node.name)

func _remove_prepared_descriptor(state:Dictionary,name_:String)->void:
	var previous:Dictionary=state.prepared_descriptors.get(name_,{})
	if previous.is_empty():return
	state.bin_names[previous.base].erase(name_);state.dirty_bins[previous.base]=true
	if resumable_bin_ledger_enabled:
		if state.bin_pending.has(previous.base):state.bin_pending[previous.base].erase(name_)
		state.bin_rebuild[previous.base]=true
	state.prepared_descriptors.erase(name_)

func _restart_dirty_bins(state:Dictionary)->void:
	if resumable_bin_ledger_enabled:
		_resume_dirty_bins(state);return
	# A publication only changes its own material/spatial/building buckets. Keep
	# completed unrelated buckets; interrupted buckets retain their dirty flag.
	state.items=[]
	for base:String in state.dirty_bins.keys():
		for key:String in state.bin_keys.get(base,[]):state.desired.erase(key)
		state.bin_keys.erase(base)
		var names:Array=state.bin_names.get(base,{}).keys()
		state.bin_remaining[base]=names.size()
		if names.is_empty():
			state.dirty_bins.erase(base);state.bin_names.erase(base);state.bin_remaining.erase(base)
		else:state.items.append_array(names)
	state.items.sort();state.phase="bin"

func _resume_dirty_bins(state:Dictionary)->void:
	# A completed ID is represented by the retained raw-bin membership; only
	# unfinished IDs stay in this work table. Other buckets' arrivals cannot
	# clear either owner. Rebuild is reserved for actual input/order changes.
	state.items=[]
	for base:String in state.dirty_bins.keys():
		var pending_names:Dictionary=state.bin_pending.get(base,{})
		var completed_count:=maxi(0,state.bin_names.get(base,{}).size()-pending_names.size())
		if state.bin_rebuild.has(base):
			bin_ledger_invalidated_buckets+=1;bin_ledger_invalidated_rows+=completed_count
			for key:String in state.bin_keys.get(base,[]):state.desired.erase(key)
			state.bin_keys.erase(base);state.bin_last_name.erase(base)
			pending_names=state.bin_names.get(base,{}).duplicate()
			state.bin_pending[base]=pending_names;state.bin_rebuild.erase(base)
		else:bin_ledger_reused_rows+=completed_count
		state.bin_remaining[base]=pending_names.size()
		if pending_names.is_empty():
			state.dirty_bins.erase(base);state.bin_remaining.erase(base)
			if state.bin_names.get(base,{}).is_empty():state.bin_names.erase(base);state.bin_pending.erase(base);state.bin_last_name.erase(base)
		else:state.items.append_array(pending_names.keys())
	state.items.sort();state.phase="bin"

func _order_runtime_bins(state:Dictionary)->Dictionary:
	# Unique fortification groups can combine across base keys in the next pass.
	# Preserve the full sorted-source insertion order, including earlier names
	# that arrived after an unrelated bucket had already completed.
	var order:Array=[]
	for key:String in state.desired:order.append([state.desired[key].sort_name,key])
	order.sort_custom(func(a:Array,b:Array)->bool:return a[0]<b[0])
	var ordered:Dictionary={}
	# Live groups later gain renderer data and callbacks. Keep only membership
	# in the reusable raw bins so invalidation cannot retain a retired GPU mesh.
	for row:Array in order:ordered[row[1]]=state.desired[row[1]].duplicate()
	return ordered

func _coalesce_covered_sources()->bool:
	# Growing ground cells can omit intermediate membership behind a drawn
	# opaque cover. Buildings/other groups continue production in parallel.
	if not covered_source_coalescing_enabled or not _preparation.get("immutable_append",false):return false
	var map:=get_parent()
	if map==null:return false
	var queue:=map.get_node_or_null("DeferredAssets")
	return queue!=null and queue._covered_loading_ready() and not queue.is_idle()

func _prepare_step(budget_usec:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._prepare_step") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _preparation.is_empty():return
	if _preparation.phase=="await_sources":
		if not _next_residency.is_empty():
			var next:Dictionary=_next_residency;_next_residency={}
			request_residency_sync(next.nodes,next.excluded,next.get("immutable_append",false))
		elif budget_usec>0 and _coalesce_covered_sources():
			covered_source_waits+=1;return
		else:
			# Reuse all captured descriptors, including skipped ground bins. The
			# synchronous flush path also reaches this branch without waiting.
			request_residency_sync(_preparation.runtime_roots,_preparation.runtime_excluded,true)
	var hold_ground:bool=budget_usec>0 and _coalesce_covered_sources()
	var started:=Time.get_ticks_usec()
	var trace_stage_started:=started
	var trace_stage:String=_preparation.phase if Timeline.enabled else ""
	while not _preparation.is_empty():
		var item_started:=Time.get_ticks_usec()
		var stage:String=_preparation.phase
		if Timeline.enabled and stage!=trace_stage:
			Timeline.record("prepare",sync_count,trace_stage_started,[trace_stage])
			trace_stage_started=Time.get_ticks_usec();trace_stage=stage
		var state:Dictionary=_preparation
		var desired:Dictionary=state.desired
		if stage=="collect" and state.component_cursor<state.components.size():
			# A single imported root can own thousands of parts. Admit its parts
			# individually as well, rather than moving the same spike one level down.
			var child:Variant=state.components[state.component_cursor];state.component_cursor+=1
			if is_instance_valid(child):
				var child_name:=str(child.name)
				if enabled:_collect_named(state,child)
				if state.exclude_components:state.excluded.append(child_name)
		elif state.cursor>=state.items.size():
			state.cursor=0
			match state.phase:
				"collect":
					if state.get("refresh_bins",false):state.items=state.prepared_descriptors.keys();state.phase="prune"
					elif state.has("unit_candidates") and not state.unit_candidates.is_empty():
						state.unit_plan_active=true;state.unit_queue=[];state.active_unit={}
						state.remaining_names=state.prepare_names.duplicate()
						state.items=state.unit_candidates.keys();state.phase="units"
					else:
						state.items=state.prepare_names.keys() if state.has("prepared_descriptors") else state.named.keys()
						state.items.sort();state.phase="prepare"
					state.components=[];state.root_excluded=[]
				"prune":state.items=state.prepare_names.keys();state.items.sort();state.phase="prepare"
				"units":
					state.remaining_prepare=state.remaining_names.keys();state.erase("remaining_names")
					_next_closed_unit(state)
				"prepare":
					if state.has("prepared_descriptors"):
						_restart_dirty_bins(state)
					else:state.items=desired.keys();state.named.clear();state.phase="unique"
				"bin":
					if not state.get("active_unit",{}).is_empty():
						var bases:Dictionary={}
						for name_:String in state.active_unit.names:
							if state.prepared_descriptors.has(name_):bases[state.prepared_descriptors[name_].base]=true
						state.items=[]
						if _closed_unit_valid(state,state.active_unit):
							for base:String in bases:state.items.append_array(state.bin_keys.get(base,[]))
						state.phase="unit_add"
						continue
					state.raw_desired=desired
					desired=_order_runtime_bins(state);state.desired=desired
					if state.get("immutable_append",false):state.collected_named=state.named;state.named={}
					else:state.named.clear()
					state.items=desired.keys();state.phase="unique"
				"unique":state.items=desired.keys();state.phase="filter"
				"filter":state.items=groups.keys();state.phase="drop"
				"drop":state.items=desired.keys();state.phase="add"
				"unit_add":_next_closed_unit(state)
				"add":
					_material_keys.clear()
					_audit_keys=groups.keys();_audit_cursor=0
					last_sync_ms=(state.cpu_us+Time.get_ticks_usec()-started)/1000.0
					if state.has("raw_desired"):
						_residency_bins={"prepared_descriptors":state.prepared_descriptors,"bin_names":state.bin_names,"bin_keys":state.bin_keys,"desired":state.raw_desired}
						for field:String in ["bin_pending","bin_last_name"]:_residency_bins[field]=state[field]
						if state.get("immutable_append",false):
							for field:String in ["runtime_roots","runtime_excluded","runtime_enabled","immutable_append"]:_residency_bins[field]=state[field]
							_residency_bins.named=state.collected_named
					# Keep held ground work visible to every readiness consumer.
					# Complete independent groups now; future arrivals reuse raw bins.
					_preparation={"phase":"await_sources","immutable_append":true,"cpu_us":0,"runtime_roots":state.runtime_roots,"runtime_excluded":state.runtime_excluded} if state.get("held_ground",false) else {}
					if not _preparation.is_empty():break
		else:
			var item:Variant=state.items[state.cursor];state.cursor+=1
			match state.phase:
				"collect":
					if is_instance_valid(item):
						if state.expand_components and item.has_meta("model_component_batch_sources"):
							state.components=item.get_meta("model_component_batch_sources").duplicate();state.component_cursor=0
							state.exclude_components=not state.root_excluded.is_empty() and str(item.name) in state.root_excluded
						elif enabled:_collect_named(state,item)
				"prune":
					if not state.named.has(item):_remove_prepared_descriptor(state,item)
				"units":
					var names:Array=state.unit_candidates[item]
					var members:Array=state.unit_groups.get(item,[])
					# Existing drawings may have keys removed by an edit. They need
					# the full drop/add reconciliation before replacement admission.
					# Only previously unbatched complete units bypass that barrier.
					if names.size()==members.size() and not names.any(func(name_:String)->bool:return _member_groups.has(name_)):
						state.unit_queue.append({"owner":item,"members":members,"names":names})
						for name_:String in names:state.remaining_names.erase(name_)
				"prepare":
					if state.has("prepared_descriptors"):state.prepare_names.erase(item);state.current_eligible=false
					var node:Variant=state.named[item]
					if is_instance_valid(node) and not node.is_queued_for_deletion():_prepare_node(node,desired,state.excluded)
					if state.has("prepared_descriptors") and not state.current_eligible:_remove_prepared_descriptor(state,item)
				"bin":
					var node:Variant=state.named[item]
					if state.prepared_descriptors.has(item):
						var descriptor:Dictionary=state.prepared_descriptors[item]
						if is_instance_valid(node) and not node.is_queued_for_deletion():_append_descriptor(node,descriptor,desired)
						elif resumable_bin_ledger_enabled:
							# A component can disappear while its root stays resident.
							# Recollect/prune next round instead of preserving its ticket.
							state.immutable_append=false;state.bin_pending[descriptor.base].erase(item)
						state.bin_remaining[descriptor.base]-=1
						if int(state.bin_remaining[descriptor.base])==0:state.dirty_bins.erase(descriptor.base)
				"unique":
					var source:Dictionary=desired[item]
					if source.category=="fortification" and source.members.size()==1:
						desired.erase(item)
						var bin:=0;var target:String="unique:"+source.merge_base+":0"
						while desired.has(target) and (desired[target].members.size()>=Geometry.MAX_FORTIFICATION_MEMBERS or desired[target].vertices+source.vertices>Geometry.MAX_VERTICES):
							bin+=1;target="unique:"+source.merge_base+":"+str(bin)
						if not desired.has(target):
							# Unique merging mutates its output; preserve the raw singleton.
							var unique:Dictionary=source.duplicate()
							unique.members=source.members.duplicate();unique.signature=source.signature.duplicate()
							desired[target]=unique
						else:
							desired[target].members.append_array(source.members);desired[target].signature.append_array(source.signature);desired[target].vertices+=source.vertices
				"filter":
					if desired[item].members.size()<2:desired.erase(item)
				"unit_add":
					# Building ID is part of the base key: a complete building's
					# bins cannot gain members from another independent building.
					if _closed_unit_valid(state,state.active_unit):
						var group:Dictionary=desired[item]
						if group.members.size()>=2:
							var already_admitted:=groups.has(item)
							if groups.has(item) and groups[item].signature!=group.signature:
								_drop(groups[item]);groups.erase(item);pending.erase(item)
							_admit_group(item,group,state,true)
							if not already_admitted and groups.has(item):closed_unit_groups_admitted+=1
				"drop":
					if groups.has(item) and (not desired.has(item) or desired[item].signature!=groups[item].signature):
						if hold_ground and groups[item].category=="ground":state.held_ground=true
						else:
							if Timeline.enabled:Timeline.record("membership_replace",groups[item].generation,Time.get_ticks_usec(),[item,groups[item].category,groups[item].members.size(),desired.get(item,{}).get("members",[]).size(),sync_count])
							_drop(groups[item]);groups.erase(item);pending.erase(item)
				"add":
					if not groups.has(item):
						var group:Dictionary=desired[item]
						# A source can leave residency between preparation slices.
						if hold_ground and group.category=="ground":state.held_ground=true
						else:_admit_group(item,group,state)
		if has_meta("profile_frame") and Time.get_ticks_usec()-item_started>10000:print("BATCH_SLOW ",stage," ",(Time.get_ticks_usec()-item_started)/1000.0," ms")
		if profile_preparation_units_enabled and Time.get_ticks_usec()-item_started>=1000:
			preload("res://scripts/world3d/load_trace.gd").instant("batch.preparation_unit",{"stage":stage,"cursor":state.cursor,"elapsed_us":Time.get_ticks_usec()-item_started,"item":str(state.items[state.cursor-1]) if state.cursor>0 and state.cursor<=state.items.size() and state.items[state.cursor-1] is String else ""})
		if budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec:break
	var elapsed:=Time.get_ticks_usec()-started
	if Timeline.enabled:Timeline.record("prepare",sync_count,trace_stage_started,[trace_stage])
	if not _preparation.is_empty():_preparation.cpu_us+=elapsed
	last_prepare_slice_ms=elapsed/1000.0
	max_prepare_slice_ms=maxf(max_prepare_slice_ms,last_prepare_slice_ms)
	if _preparation.is_empty() and not _next_residency.is_empty():
		var next:Dictionary=_next_residency;_next_residency={}
		request_residency_sync(next.nodes,next.excluded,next.get("immutable_append",false))

func _process(_delta: float) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._process") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _retiring_workers:return
	var wanted:=effective_work_budget_usec()
	if residency_budget_frame==Engine.get_process_frames():wanted=mini(wanted,residency_budget_remaining_usec)
	var covered:=wanted>=24000
	if not covered and wanted>INTERACTIVE_WORK_BUDGET_USEC and is_instance_valid(get_parent()):
		var queue:=get_parent().get_node_or_null("DeferredAssets")
		covered=queue!=null and queue._covered_loading_ready()
	var allowed:=FrameBudget.allowance("batch",wanted,covered)
	if allowed<=0:
		if Timeline.enabled and (not _preparation.is_empty() or not pending.is_empty() or not _workers.is_empty()):Timeline.record("denied",sync_count,Time.get_ticks_usec(),[wanted,pending.size(),_workers.size(),_preparation.get("phase","")])
		return
	var began:=Time.get_ticks_usec()
	var trace_busy:=Timeline.enabled and (not _preparation.is_empty() or not pending.is_empty() or not _workers.is_empty())
	_process_work(allowed)
	FrameBudget.charge("batch",began)
	if trace_busy:Timeline.record("slice",sync_count,began,[wanted,allowed,pending.size(),_workers.size(),_preparation.get("phase",""),_loading_budgets.size()])

func _process_work(allowed:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._process_work") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if allowed<=0:return
	var started:=Time.get_ticks_usec()
	# Cursor work / one finished-worker commit must precede the optional audit.
	# Otherwise even a permanently positive 1 us slice can spend every frame
	# auditing without ever consuming a pending group or joined worker.
	var advanced:=false
	# Continuous source arrivals can keep collection alive for seconds. Give
	# completed/pending groups a turn too: otherwise they never replace their
	# thousands of source draws until all collection finishes. Alternate the
	# first unit so an indivisible overrun cannot starve either side next frame.
	if not _preparation.is_empty() and _production_turn:
		advanced=_advance_production()
		if advanced:production_turns_while_preparing+=1;_production_turn=false
	if not _preparation.is_empty() and (not advanced or Time.get_ticks_usec()-started<allowed):
		var remaining:=maxi(1,allowed-(Time.get_ticks_usec()-started))
		var preparation_budget:=maxi(1,remaining/2) if not pending.is_empty() or not _workers.is_empty() else remaining
		_prepare_step(preparation_budget)
		advanced=true;_production_turn=true
	while not advanced or Time.get_ticks_usec()-started<allowed:
		if not _advance_production():break
		if not _preparation.is_empty():production_turns_while_preparing+=1
		advanced=true;_production_turn=false
	# Lifetime signals are immediate. A bounded audit also repairs stale caches
	# without polling thousands of static/closed fixtures every frame.
	for i in mini(32,_audit_keys.size()):
		if i>0 and Time.get_ticks_usec()-started>=allowed:break
		_audit_cursor%=_audit_keys.size()
		var key:String=_audit_keys[_audit_cursor];_audit_cursor+=1
		if not groups.has(key):continue
		var group:Dictionary=groups[key]
		if group.category!="building" or not is_instance_valid(group.get("visual")):continue
		# Check the Variant before typed assignment: casting a freed Object fails
		# before an is_instance_valid() check on the typed local can run.
		if group.members.is_empty() or not is_instance_valid(group.members[0]):
			_invalidate_group(key,group.generation);continue

func _advance_production()->bool:
	var ready:int=_workers.find_custom(func(job):return not job.thread.is_alive())
	if ready>=0:_finish_worker(ready);return true
	if _workers.size()+WorkerRetirement.pending(_retired_leases)>=MAX_WORKERS:
		# Retain only the explicit legacy covered-loading join policy.
		if legacy_loading_worker_wait_enabled and not _workers.is_empty() and not FrameBudget.enabled and _loading_budgets.is_empty() and work_budget_usec>=24000:_finish_worker(0);return true
		return false
	if pending.is_empty():return false
	_build_next(true);return true

func flush() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.flush") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _retiring_workers:return
	while not _preparation.is_empty():_prepare_step(0)
	while not _workers.is_empty(): _finish_worker(0)
	while not pending.is_empty(): _build_next()

func _build_next(background: bool = false) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._build_next") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _retiring_workers:return
	var key: String = pending.pop_front()
	if not groups.has(key): return
	var group: Dictionary = groups[key]
	if Timeline.enabled:Timeline.record("dispatch",group.generation,Time.get_ticks_usec(),[key,group.has("shared_result")])
	if group.has("shared_result"):
		var shared:Dictionary=group.shared_result;var prepared_at:int=group.shared_started
		group.erase("shared_result");group.erase("shared_started")
		_commit(group,shared,prepared_at);return
	for node in group.members:
		if not is_instance_valid(node): _drop(group); groups.erase(key); return
	var started := Time.get_ticks_usec()
	if group.category=="building":group.origin=group.members[0].global_position
	group.render_pose=Transform3D(Basis.IDENTITY,group.origin)
	group.reference_pose=group.members[0].global_transform
	var snapshot: Array = []
	group.cpu = []
	for node: MeshInstance3D in group.members:
		var cpu: Mesh = Cpu.capture(node.mesh); var materials: Array = []
		group.cpu.append(cpu)
		for slot in node.mesh.get_surface_count(): materials.append(node.get_active_material(slot))
		snapshot.append({"record":node.get_meta("ground_batch_record"),"transform":node.global_transform,"surfaces":cpu.surfaces,"materials":materials,"keys":group.keys})
	if group.category=="building" and not snapshot[0].materials.any(func(material):return material is ShaderMaterial):
		# Reuse geometry across rotated copies as well as translated ones. Each
		# floor/fixture still owns its own instance, visibility and pose watcher.
		if canonical_buildings_enabled:
			group.render_pose=group.reference_pose
			var inverse:Transform3D=group.reference_pose.affine_inverse()
			for source:Dictionary in snapshot:source.transform=inverse*source.transform
			group.origin=Vector3.ZERO
		group.cache_poses=[];group.cache_bounds=[]
		var identity:Array=[]
		for i in snapshot.size():
			var pose:Transform3D=snapshot[i].transform;pose.origin-=group.origin
			group.cache_poses.append(pose);group.cache_bounds.append(group.cpu[i].get_aabb())
			# World float cancellation differs between translated copies. Render
			# cache comparisons tolerate at most 0.1 mm, without editing records.
			pose.origin=pose.origin.snapped(Vector3.ONE*.0001)
			pose.basis=Basis(pose.basis.x.snapped(Vector3.ONE*.000001),pose.basis.y.snapped(Vector3.ONE*.000001),pose.basis.z.snapped(Vector3.ONE*.000001))
			identity.append([group.cpu[i].geometry_key(),pose,group.keys])
		group.mesh_cache_key=_fingerprint(identity)
		if _building_meshes.has(group.mesh_cache_key):
			var entry:Dictionary=_building_meshes[group.mesh_cache_key]
			var shared:Mesh=entry.reference.get_ref()
			if shared!=null and _compatible_poses(group,entry):
				var data:Dictionary=entry.data.duplicate();data.mesh=shared;building_mesh_hits+=1
				_commit(group,data,started);return
		# A completed mesh cache alone misses simultaneous requests: three
		# identical houses can all start before the first result is installed.
		# Join the CPU result, retaining each group's own pose/visibility/cursor.
		if background and inflight_building_sharing_enabled:
			for running:Dictionary in _workers:
				if running.get("mesh_cache_key","")==group.mesh_cache_key and _compatible_poses(group,running):
					running.reusers.append({"key":key,"generation":group.generation,"started":started})
					building_worker_reuses+=1;return
	# Repeated stone modules should share one vertex buffer. Flattening them
	# all into a combined mesh trades fewer draws for duplicated GPU geometry.
	if group.category in ["fortification","vegetation"] and _identical_geometry(group.cpu):
		_commit_instances(group,snapshot,started)
		return
	if background:
		var job:={"key":key,"generation":group.generation,"started":started,"thread":Thread.new()}
		if group.has("mesh_cache_key"):
			job.mesh_cache_key=group.mesh_cache_key;job.poses=group.cache_poses;job.reusers=[]
		var origin: Vector3=group.origin
		# Workers never own a Node callable. Keep GPU-linked input materials on a
		# main-owned lease even if the entire source map is removed mid-build.
		for source:Dictionary in snapshot:source.surfaces=WorkerRetirement.snapshot_surfaces(source.surfaces)
		job.retirement=WorkerRetirement.watch(job.thread,get_tree(),[snapshot,group.cpu.duplicate()])
		var build_call:Callable=Timeline.build.bind(snapshot,origin) if Timeline.enabled else Geometry.build.bind(snapshot,origin,true)
		if not job.retirement.is_empty() and job.thread.start(build_call) == OK: _workers.append(job); return
		WorkerRetirement.complete(job.retirement)
	_commit(group,Geometry.build(snapshot,group.origin),started)

func _compatible_poses(group:Dictionary,entry:Dictionary)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._compatible_poses") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Hash rounding is only a candidate lookup. Bound the world-position error
	# over every source AABB, including very large authored parts, before reuse.
	if group.cache_poses.size()!=entry.poses.size():return false
	for i in group.cache_poses.size():
		var a:Transform3D=group.cache_poses[i];var b:Transform3D=entry.poses[i]
		var box:AABB=group.cache_bounds[i]
		var extent:Vector3=box.position.abs().max(box.end.abs())
		var error:=a.origin.distance_to(b.origin)
		error+=(a.basis.x-b.basis.x).length()*extent.x+(a.basis.y-b.basis.y).length()*extent.y+(a.basis.z-b.basis.z).length()*extent.z
		# Frobenius norm bounds amplification by nonuniform scale or shear.
		var basis:Basis=group.render_pose.basis
		error*=sqrt(basis.x.length_squared()+basis.y.length_squared()+basis.z.length_squared())
		if error>.0001:return false
	return true

func _identical_geometry(meshes: Array) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._identical_geometry") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var expected: String=""
	for mesh: Mesh in meshes:
		var signature:=_geometry_signature(mesh)
		if expected.is_empty(): expected=signature
		elif signature!=expected: return false
	return true

func _geometry_signature(mesh: Mesh) -> String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._geometry_signature") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return mesh.geometry_key()

func _commit_instances(group: Dictionary,snapshot: Array,started: int) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._commit_instances") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var key: String=(str(group.cpu[0].get_meta("static_batch_geometry_signature"))+var_to_str(group.keys)).sha256_text()
	var mesh: Mesh=_instance_meshes[key].get_ref() if _instance_meshes.has(key) else null
	if mesh==null:
		var original: Mesh=group.cpu[0].source_reference.get_ref() if group.cpu[0].source_reference!=null else null
		var compatible:=original!=null
		if compatible:
			for slot in original.get_surface_count():
				if original.surface_get_material(slot)!=snapshot[0].materials[slot]: compatible=false; break
		if compatible:mesh=original
		else:
			# restore() may return the shared original. Give the batch a private
			# material owner rather than changing that original's materials.
			var source:Mesh=group.cpu[0];var local:=Cpu.new()
			local.surfaces=source.surfaces;local.lods=source.lods;local.bounds=source.bounds;local.box_size=source.box_size
			local.materials.assign(snapshot[0].materials)
			mesh=local.restore()
		_instance_meshes[key]=weakref(mesh)
	var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.mesh=mesh; multi.instance_count=snapshot.size()
	for i in snapshot.size():
		var pose: Transform3D=snapshot[i].transform; pose.origin-=group.origin; multi.set_instance_transform(i,pose)
	var visual:=MultiMeshInstance3D.new(); visual.multimesh=multi; visual.cast_shadow=group.members[0].cast_shadow; visual.layers=group.members[0].layers; visual.set_meta("ground_render_batch",true)
	add_child(visual); visual.global_position=group.origin
	var vertices:=Geometry.vertex_count(mesh)
	group.visual=visual; group.data={"mesh":mesh,"source_surfaces":mesh.get_surface_count()*snapshot.size(),"source_vertices":vertices*snapshot.size(),"render_vertices":vertices,"instanced":true}
	for i in group.members.size(): freeze(group.members[i],group.cpu[i])
	group.erase("cpu"); rebuild_count+=1
	last_build_ms=(Time.get_ticks_usec()-started)/1000.; max_build_ms=maxf(max_build_ms,last_build_ms); last_commit_ms=last_build_ms
	max_commit_ms=maxf(max_commit_ms,last_commit_ms)

func _finish_worker(index: int) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._finish_worker") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var job: Dictionary=_workers[index]; _workers.remove_at(index)
	var waiting:bool=job.thread.is_alive();var join_started:=Time.get_ticks_usec()
	var data: Dictionary = job.thread.wait_to_finish()
	if Timeline.enabled:Timeline.record("join",job.generation,join_started,[data.get("batch_worker_interval",[]),waiting,job.get("reusers",[]).size()])
	if waiting:live_worker_joins+=1;live_worker_join_us+=Time.get_ticks_usec()-join_started
	var targets:Array=[{"key":job.key,"generation":job.generation,"started":job.started}]
	targets.append_array(job.get("reusers",[]))
	var shared:Dictionary={}
	for target:Dictionary in targets:
		if not groups.has(target.key) or groups[target.key].generation!=target.generation:continue
		if shared.is_empty():
			# The initiating group may have been removed while its worker ran.
			# The first surviving equivalent group can install the same result.
			var group:Dictionary=groups[target.key]
			_commit(group,data,target.started)
			shared=group.get("data",{})
		else:
			# Do not publish every follower in this join's indivisible slice.
			# Each group consumes its own normal frame-budgeted production turn.
			var group:Dictionary=groups[target.key]
			group.shared_result=shared;group.shared_started=target.started
			if not pending.has(target.key):pending.append(target.key)
	WorkerRetirement.complete(job.get("retirement",{}))

func retire_workers(_tree:SceneTree=null)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.retire_workers") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not _retiring_workers:_resume_processing=is_processing()
	_retiring_workers=true;set_process(false)
	_loading_budgets.clear()
	for job:Dictionary in _workers:
		# Reparenting within the same SceneTree also exits. If this node returns,
		# rebuild only the still-current group after its retired slot drains.
		if groups.has(job.get("key","")) and groups[job.key].generation==job.generation and not pending.has(job.key):pending.append(job.key)
		for target:Dictionary in job.get("reusers",[]):
			if groups.has(target.key) and groups[target.key].generation==target.generation and not pending.has(target.key):pending.append(target.key)
		WorkerRetirement.abandon(job.get("retirement",{}),_retired_leases)
	_workers.clear()

func _exit_tree() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._exit_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	retire_workers()

func _commit(group: Dictionary, data: Dictionary, started: int) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher._commit") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if data.is_empty(): return
	for node in group.members:
		if not is_instance_valid(node): return
	var commit_started := Time.get_ticks_usec()
	if not data.has("mesh"):
		var count:int=data.get("prepared_surface_count",0)
		if count>0 and data.get("surface_prepare_thread",OS.get_main_thread_id())!=OS.get_main_thread_id():
			worker_packed_surfaces+=count;worker_surface_prepare_us+=int(data.get("surface_prepare_us",0))
		else:main_packed_surfaces+=data.get("slots",[]).size()
		data=Geometry.upload(data)
	if data.is_empty() or data.mesh.get_surface_count()==0: return
	if group.has("mesh_cache_key"):
		var info:Dictionary=data.duplicate();info.erase("mesh");info.erase("slots")
		_building_meshes[group.mesh_cache_key]={"reference":weakref(data.mesh),"data":info,"poses":group.cache_poses}
	var visual := MeshInstance3D.new(); visual.mesh = data.mesh
	visual.cast_shadow = group.members[0].cast_shadow; visual.layers = group.members[0].layers
	visual.set_meta("ground_render_batch", true)
	if group.category=="ground" and data.source_surfaces == group.members.size(): visual.set_meta("extras", {"kind":"ground"})
	add_child(visual)
	group.visual = visual; group.data = data
	group.relative_pose=group.reference_pose.affine_inverse()*group.render_pose
	group.last_source_pose=group.members[0].global_transform
	visual.global_transform=group.last_source_pose*group.relative_pose if group.category=="building" else group.render_pose
	if group.get("moving",false):
		var watcher:=preload("res://scripts/world3d/batch_transform_watch.gd").new()
		watcher.changed=_sync_pose.bind(_member_groups[str(group.members[0].name)],group.generation)
		group.pose_watcher=watcher;group.members[0].add_child(watcher)
	visual.visible=group.members[0].is_visible_in_tree()
	for i in group.members.size(): freeze(group.members[i],group.cpu[i])
	group.erase("cpu")
	rebuild_count += 1
	last_build_ms = (Time.get_ticks_usec()-started)/1000.; max_build_ms = maxf(max_build_ms,last_build_ms)
	last_commit_ms = (Time.get_ticks_usec()-commit_started)/1000.
	if Timeline.enabled:Timeline.record("commit",group.generation,commit_started,[group.category,group.members.size(),data.get("source_vertices",0),data.mesh.get_surface_count()])
	max_commit_ms=maxf(max_commit_ms,last_commit_ms)

func stats(category: String="") -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batcher.stats") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var result := {"enabled":enabled,"pending_groups":pending.size()+_workers.size()+(0 if _preparation.is_empty() else 1),"groups":0,"instanced_groups":0,"source_objects":0,"source_surfaces":0,"render_surfaces":0,"source_vertices":0,"render_vertices":0,"rebuild_count":rebuild_count,"last_build_ms":last_build_ms,"max_build_ms":max_build_ms,"last_commit_ms":last_commit_ms,"max_commit_ms":max_commit_ms,"last_sync_ms":last_sync_ms,"sync_profile_us":sync_profile.duplicate()}
	result.worker_packed_surfaces=worker_packed_surfaces;result.main_packed_surfaces=main_packed_surfaces;result.worker_surface_prepare_us=worker_surface_prepare_us
	result.sync_count=sync_count; result.release_groups_visited=release_groups_visited
	result.resumed_collections=resumed_collections;result.reused_collection_roots=reused_collection_roots
	result.prepared_source_visits=prepared_source_visits;result.packed_source_visits=packed_source_visits
	result.bin_ledger_reused_rows=bin_ledger_reused_rows;result.bin_ledger_invalidated_buckets=bin_ledger_invalidated_buckets;result.bin_ledger_invalidated_rows=bin_ledger_invalidated_rows
	result.completed_prefix_reuses=completed_prefix_reuses;result.completed_source_visits_avoided=completed_source_visits_avoided
	result.suspended_source_uploads=suspended_source_uploads
	result.production_turns_while_preparing=production_turns_while_preparing
	result.closed_units_prepared=closed_units_prepared;result.closed_unit_groups_admitted=closed_unit_groups_admitted
	result.covered_source_waits=covered_source_waits
	result.building_mesh_hits=building_mesh_hits
	result.building_worker_reuses=building_worker_reuses
	result.work_budget_usec=effective_work_budget_usec();result.base_work_budget_usec=work_budget_usec
	result.loading_budget_scopes=_loading_budgets.size()
	result.live_worker_joins=live_worker_joins;result.live_worker_join_us=live_worker_join_us
	for group: Dictionary in groups.values():
		if not category.is_empty() and group.category!=category: continue
		if not group.has("data"): continue
		result.groups += 1; result.source_objects += group.members.size()
		if group.data.get("instanced",false): result.instanced_groups+=1
		result.source_surfaces += group.data.source_surfaces
		result.render_surfaces += group.data.mesh.get_surface_count()
		result.source_vertices += group.data.source_vertices; result.render_vertices += group.data.render_vertices
	return result
