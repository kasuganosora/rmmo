extends RefCounted
## One covered entry, backed by the local server adapter. No worker touches Nodes.
const Gate=preload("res://scripts/world3d/entry_readiness.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var authority:RefCounted
var issued:Dictionary={}
var gate:RefCounted
var root:WeakRef
var demand_id:=""
var state_applied_frame:=-1
var state_snapshot:Dictionary={}
var residency_pins:Array[String]=[]

func begin(adapter:RefCounted,map_root:Node,session:String,world:String,map_ref:String,revision:String,feet:Vector3,reason:String,reuse_catalogue:bool=false)->Dictionary:
	authority=adapter;root=weakref(map_root)
	# Only the same immutable runtime root/revision selected by the authority
	# may reuse its catalogue. Direct callers still rebuild after author edits.
	if not reuse_catalogue or not authority.registered_root_current(map_ref,revision,map_root):
		var registered:Dictionary=authority.register_root(map_ref,revision,map_root)
		if not registered.ok:return registered
	issued=authority.begin(session,world,map_ref,revision,feet,reason)
	if not issued.ok:return issued
	gate=Gate.new()
	var started:Dictionary=gate.begin(issued.snapshot)
	if not started.ok:return started
	demand_id="building_entry:%d"%int(issued.ticket.epoch)
	gate.mark("metadata",gate.token())
	if not issued.membership_resolved:return {"ok":false,"reason":"membership_unresolved: "+str(issued.snapshot.reason)}
	return {"ok":true}

func prepare(world:Node,host:Node,centre:Vector3,cover:Node=null,cancelled:Callable=Callable())->String:
	var tree:SceneTree=world.get_tree() if is_instance_valid(world) else null
	if tree==null:return "entry_cancelled"
	var map:Node=root.get_ref()
	if not is_instance_valid(map):return "map_unavailable"
	var clip:AABB=map.get_meta("entry_stream_clip",preload("res://scripts/world3d/entry_plan.gd").create(centre).safety_clip)
	if issued.snapshot.membership=="indoor":clip=clip.merge(issued.required_bounds.grow(.1))
	if not Stream.set_entry_scope(map,clip):return "invalid_building_scope"
	var deferred:Node=map.get_node_or_null("DeferredAssets")
	if deferred!=null and not str(issued.required_group).is_empty() and not deferred._reference_index.is_empty():
		deferred.allow_demand_in_scope(demand_id)
		if not deferred.set_group_demand(demand_id,issued.required_group,-3):return "building_group_unavailable"
		deferred.activate(host)
	var deadline:=Time.get_ticks_msec()+180000
	while true:
		if cancelled.is_valid() and cancelled.call():return "entry_cancelled"
		var valid:Dictionary=authority.validate(issued.ticket)
		if not valid.ok:return str(valid.reason)
		if not is_instance_valid(map) or map.is_queued_for_deletion():return "map_unavailable"
		var published:bool=deferred==null or str(issued.required_group).is_empty() or deferred._reference_index.is_empty() or deferred.group_is_published(issued.required_group)
		if deferred!=null and not deferred.error.is_empty():return deferred.error
		Stream.sync(map,host,centre,Stream.LOAD_BUDGET)
		if published and Stream.entry_scope_ready(map):break
		if Time.get_ticks_msec()>=deadline:return "building_preparation_timeout"
		if cover!=null:cover.update_progress("准备所在建筑的完整成员与碰撞")
		else:world._loading_stage("准备所在建筑的完整成员与碰撞")
		await tree.process_frame
	gate.mark("geometry",gate.token())
	state_snapshot=issued.snapshot.duplicate(true)
	if issued.snapshot.membership=="indoor":
		var applied:Dictionary=authority.apply_state_snapshot(issued.ticket,map)
		if not applied.ok:return str(applied.reason)
		state_snapshot.building=applied.building
	state_applied_frame=Engine.get_physics_frames()
	# The signal is emitted before the physics iteration; wait until a later
	# process frame as well before inspecting actual server publication stamps.
	while Engine.get_physics_frames()<=state_applied_frame:
		await tree.physics_frame
		await tree.process_frame
		if not is_instance_valid(world) or not world.is_inside_tree() or not is_instance_valid(map) or map.is_queued_for_deletion():return "entry_cancelled"
	if cancelled.is_valid() and cancelled.call():return "entry_cancelled"
	var valid:Dictionary=authority.validate(issued.ticket)
	if not valid.ok:return str(valid.reason)
	if issued.snapshot.membership=="indoor":
		var receipt:Dictionary=authority.inspect_root(state_snapshot,map,Engine.get_physics_frames(),state_applied_frame)
		if not receipt.ok:return "building_evidence_pending: "+str(receipt.get("missing_members",[]))
		var completed:Dictionary=gate.complete_building(receipt,gate.token())
		if not completed.ok:return str(completed.reason)
	gate.mark("physics",gate.token());gate.mark("render",gate.token())
	return ""

func gameplay_ready()->void:
	if gate!=null:gate.mark("base_gameplay",gate.token())

func activate(rendered:bool,placement:Callable)->Dictionary:
	if gate==null:return {"ok":false,"reason":"entry_not_started"}
	if not rendered:return {"ok":false,"reason":"rendered_frame_unavailable"}
	var frame:Dictionary=gate.mark("first_frame",gate.token())
	if not frame.ok:return frame
	var approval:Dictionary=authority.authorize(issued.ticket,gate.report(),placement)
	if not approval.ok:return approval
	return gate.authorize_activation(gate.token(),approval.state_watermark)

func report()->Dictionary:return gate.report() if gate!=null else {"state":"not_started"}

func retain_residency()->void:
	if issued.get("snapshot",{}).get("membership")!="indoor" or not residency_pins.is_empty():return
	var map:Variant=root.get_ref()
	if not is_instance_valid(map):return
	if demand_id.is_empty():demand_id="building_entry:%d"%int(issued.ticket.epoch)
	var deferred:Node=map.get_node_or_null("DeferredAssets")
	if deferred!=null and not deferred._reference_index.is_empty():deferred.set_group_demand(demand_id,issued.required_group,-3)
	var bounds:AABB=issued.required_bounds
	var low:=Stream.chunk_key(bounds.position);var high:=Stream.chunk_key(bounds.end)
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var id:String=demand_id+":%d:%d"%[x,z]
			Stream.pin_source(map,id,Vector3((x+.5)*Stream.CHUNK_M,(bounds.position.y+bounds.end.y)*.5,(z+.5)*Stream.CHUNK_M))
			residency_pins.append(id)

func release_if_left(feet:Vector3)->void:
	if residency_pins.is_empty():return
	var current:Dictionary=authority.position_snapshot(issued.ticket.map_ref,issued.ticket.map_revision,feet)
	if current.ok and current.snapshot.get("building",{}).get("instance_id","")!=issued.snapshot.building.instance_id:release()

func release()->void:
	var map:Variant=root.get_ref() if root!=null else null
	if is_instance_valid(map):
		var deferred:Node=map.get_node_or_null("DeferredAssets")
		if deferred!=null:deferred.release_demand(demand_id)
		for id:String in residency_pins:Stream.release_source(map,id)
	residency_pins.clear()

func cancel(reason:String)->void:
	if authority!=null and issued.has("ticket"):authority.cancel(issued.ticket,reason)
	if gate!=null:gate.cancel(reason,gate.token())
	release()
