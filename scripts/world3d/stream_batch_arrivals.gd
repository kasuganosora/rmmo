extends RefCounted
## Main-thread arrival ledger. Holds Node handles/IDs only, never source specs,
## meshes or index member arrays that could pin retired resource ownership.
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
var roots:Array=[]
var selected:Dictionary={}
var unsubmitted:Dictionary={}
var pending:Dictionary={}
var ready:Dictionary={}
var needs_full:=false
var profile:Dictionary={"arrivals":0,"closed_units":0,"early_requests":0,"verified_members":0,"invalidations":0,"max_dispatch_us":0}

func _init(existing:Dictionary={})->void:
	# Adoption before this ledger existed has no per-source completion proof.
	needs_full=not existing.is_empty()

func invalidate(require_full:bool=false)->void:
	if needs_full:return
	if not require_full and roots.is_empty() and unsubmitted.is_empty():return
	needs_full=true;roots=[];selected={};unsubmitted={};pending={};ready={}
	profile.invalidations+=1

func arrived(spec:Dictionary,node:MeshInstance3D,groups:Dictionary)->void:
	if needs_full:return
	var id:String=spec.uuid
	var previous:Variant=selected.get(id,unsubmitted.get(id))
	if previous==node:return
	if previous!=null:invalidate();return
	profile.arrivals+=1;unsubmitted[id]=node
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
		roots=meshes.values();selected=meshes.duplicate();needs_full=false
	else:
		roots.append_array(unsubmitted.values());selected.merge(unsubmitted)
	unsubmitted={};pending={};ready={}
	return roots
