extends RefCounted
## Main-thread arrival ledger. Holds Node handles/IDs only, never source specs,
## meshes or index member arrays that could pin retired resource ownership.
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const SOURCE_ID_META:=&"runtime_batch_source_id"
var roots:Array=[]
var selected:Dictionary={}
var unsubmitted:Dictionary={}
var pending:Dictionary={}
var ready:Dictionary={}
var needs_full:=false
var _needs_request:=false
var _mutable_invalidated:=false
var _owner_lost:=false
var _owned_exit_id:=0
var _root:WeakRef
var _scene_handoff:=false
var _tracked_ids:Dictionary={}
var profile:Dictionary={"arrivals":0,"closed_units":0,"early_requests":0,"verified_members":0,"invalidations":0,"max_dispatch_us":0,"full_roster_builds":0,"full_roster_rows":0,"appended_roots":0,"duplicate_arrivals":0,"owner_loss_repairs":0}

func _init(existing:Dictionary={},map_root:Node=null)->void:
	# Adoption before this ledger existed has no per-source completion proof.
	needs_full=not existing.is_empty()
	# Attaching the ledger to settled residency is not itself a source change.
	# Its next real checkpoint obtains a baseline; do not create an extra one.
	if map_root!=null:
		_root=weakref(map_root)
		# One map-level lifetime feed; no per-source signal/Callable allocation.
		map_root.child_exiting_tree.connect(_child_exiting)
		map_root.tree_exited.connect(_tree_exited)

func has_pending()->bool:return _needs_request

func submitted_mutable()->void:
	# The editor already reconciled everything. Rebuild the runtime roster on
	# its next actual change, without requesting the same editor snapshot again.
	invalidate(true);_needs_request=false;_mutable_invalidated=false

func invalidate_mutable()->void:
	# A roster restart alone cannot revoke descriptors for the same live Node.
	_mutable_invalidated=true;invalidate(true)

func take_mutable_invalidation()->bool:
	var result:=_mutable_invalidated;_mutable_invalidated=false;return result

func take_owner_loss()->bool:
	var result:=_owner_lost;_owner_lost=false
	if result:profile.owner_loss_repairs+=1
	return result

func begin_owned_exit(identity:int)->int:
	var previous:=_owned_exit_id;_owned_exit_id=identity;return previous

func end_owned_exit(previous:int)->void:_owned_exit_id=previous

func begin_scene_handoff(_state:Dictionary)->void:_scene_handoff=true

func end_scene_handoff(reusable:bool)->void:
	_scene_handoff=false
	if not reusable:invalidate_mutable()

func _child_exiting(child:Node)->void:
	if _scene_handoff:return
	var identity:=child.get_instance_id()
	if identity==_owned_exit_id:return # Only a synchronous Stream._drop owns this guard.
	var known:bool=_tracked_ids.has(identity)
	if not known and needs_full:
		# A late-attached ledger has not visited its old owners yet. Resolve a
		# recorded canonical UUID, never a potentially normalized Node.name.
		var map_root:Node=_root.get_ref() if _root!=null else null
		if map_root!=null and child.has_meta(SOURCE_ID_META):
			known=map_root.get_meta("stream_meshes",{}).get(child.get_meta(SOURCE_ID_META))==child
		elif child is MeshInstance3D and child.get_meta("stream_instance",false):
			# Legacy owners without an identity receipt require one conservative
			# repair on exit. This is an event, never a per-frame roster scan.
			known=true
	if known:_owner_lost=true;invalidate(true)

func _tree_exited()->void:
	if _scene_handoff:return
	# Mutations outside the tree emit no child lifetime signal. Re-entry must
	# establish a fresh roster even when the direct child count did not change.
	invalidate_mutable()

func dispose()->void:
	var map_root:Node=_root.get_ref() if _root!=null else null
	if map_root!=null:
		if map_root.child_exiting_tree.is_connected(_child_exiting):map_root.child_exiting_tree.disconnect(_child_exiting)
		if map_root.tree_exited.is_connected(_tree_exited):map_root.tree_exited.disconnect(_tree_exited)
	_root=null;roots=[];selected={};unsubmitted={};pending={};ready={};_tracked_ids={}
	needs_full=false;_needs_request=false;_mutable_invalidated=false;_owner_lost=false;_owned_exit_id=0

func invalidate(require_full:bool=false)->void:
	if needs_full:_needs_request=true;return
	if not require_full and roots.is_empty() and unsubmitted.is_empty():return
	needs_full=true;_needs_request=true;roots=[];selected={};unsubmitted={};pending={};ready={};_tracked_ids={}
	profile.invalidations+=1

func arrived(spec:Dictionary,node:MeshInstance3D,groups:Dictionary={},prepare_closed_units:bool=true)->void:
	var id:String=spec.uuid
	node.set_meta(SOURCE_ID_META,id)
	if needs_full:_needs_request=true;return
	var previous:Variant=selected.get(id,unsubmitted.get(id))
	if previous==node:profile.duplicate_arrivals+=1;return
	if previous!=null:invalidate();return
	profile.arrivals+=1;unsubmitted[id]=node;_tracked_ids[node.get_instance_id()]=id;_needs_request=true
	# The first runtime integration preserves the existing checkpoint cadence.
	# Do not build closure tickets or add early requests when they are unused.
	if not prepare_closed_units:return
	var record:Dictionary=spec.get("ground_batch_record",{})
	var owner:String=record.get("building",{}).get("id","")
	if owner.is_empty() or spec.get("render_building","")!=owner or not groups.has(owner) or Geometry.category(record)!="building" or node.has_meta("model_component_batch_sources"):return
	var count:int=groups[owner].size()
	if not pending.has(owner):pending[owner]={"count":count,"nodes":{}}
	var row:Dictionary=pending[owner]
	if row.count!=count:return # Changed closure waits for the ordinary full reconciliation.
	row.nodes[id]=node
	if row.nodes.size()==count:
		ready[owner]=row;pending.erase(owner)

func dispatch(batcher:Node,meshes:Dictionary,groups:Dictionary,by_id:Dictionary)->void:
	if needs_full or ready.is_empty():return
	var began:=Time.get_ticks_usec()
	# One completed unit per existing residency turn. Other sources stay in
	# the authoritative stream queues; no worker, budget or hidden work queue.
	var owner:=""
	for id:String in ready:owner=id;break
	var row:Dictionary=ready[owner];ready.erase(owner)
	if not groups.has(owner) or groups[owner].size()!=row.count:return
	for id:String in row.nodes:
		var node:Variant=row.nodes[id];var spec:Dictionary=by_id.get(id,{})
		profile.verified_members+=1
		if not is_instance_valid(node) or node.is_queued_for_deletion() or meshes.get(id)!=node or spec.get("render_building","")!=owner or not is_same(node.get_meta("ground_batch_record",{}),spec.get("ground_batch_record",{})):return
	# All IDs are unique and still belong to the authoritative complete group.
	# Later full requests append only unseen roots, preserving this exact prefix.
	roots.append_array(row.nodes.values());selected.merge(row.nodes)
	for id:String in row.nodes:unsubmitted.erase(id)
	batcher.request_residency_sync(roots,[],true)
	profile.closed_units+=1;profile.early_requests+=1
	profile.max_dispatch_us=maxi(profile.max_dispatch_us,Time.get_ticks_usec()-began)

func all_sources(meshes:Dictionary)->Array:
	if needs_full:
		roots=[];selected={};_tracked_ids={}
		profile.full_roster_builds+=1;profile.full_roster_rows+=meshes.size()
		for id:String in meshes:
			var node:Variant=meshes[id]
			if not is_instance_valid(node) or node.is_queued_for_deletion():continue
			node.set_meta(SOURCE_ID_META,id)
			roots.append(node);selected[id]=node;_tracked_ids[node.get_instance_id()]=id
		needs_full=false
	else:
		for id:String in unsubmitted:
			var node:Variant=unsubmitted[id]
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				invalidate(true);return all_sources(meshes)
			roots.append(node);selected[id]=node;profile.appended_roots+=1
	unsubmitted={};pending={};ready={}
	_needs_request=false
	return roots
