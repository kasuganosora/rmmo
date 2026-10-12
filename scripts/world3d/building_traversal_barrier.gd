extends RefCounted
## Incremental, main-thread readiness barrier for a trusted movement sweep.
## Never changes the player's pose, input lock, entry scope, or loading budget.
const Transaction=preload("res://scripts/world3d/building_entry_transaction.gd")
const Gate=preload("res://scripts/world3d/entry_readiness.gd")
var owner:WeakRef
var root:WeakRef
var authority:RefCounted
var anchor:Dictionary={}
var attempts:Dictionary={}
var last_reason:=""
var draw_serial:=0
var _cursor:=0
var _draw_callback:Callable
var _last_guard_tick:=-1

func setup(world:Node,map_root:Node,adapter:RefCounted,parent_ticket:Dictionary)->void:
	owner=weakref(world);root=weakref(map_root);authority=adapter;anchor=parent_ticket.duplicate(true)
	_draw_callback=_drawn
	RenderingServer.frame_post_draw.connect(_draw_callback)

func _drawn()->void:draw_serial+=1

func guard(clip:AABB,feet:Vector3)->Dictionary:
	_last_guard_tick=Engine.get_physics_frames()
	var required:Dictionary=authority.traversal_requirements(anchor,feet,clip)
	if not required.ok:
		# An unresolved forward intent is denied, not latched as a global lock.
		# A later retreat into a known area gets its own independent query.
		var here:Dictionary=authority.position_snapshot(anchor.map_ref,anchor.map_revision,feet)
		for id:String in attempts.keys():
			if here.ok and here.snapshot.get("building",{}).get("instance_id")!=id:_release(id,"sweep_unresolved")
		last_reason=str(required.reason);return required
	for id:String in attempts.keys():
		if not required.buildings.has(id):_release(id,"left_sweep")
	var world:Variant=owner.get_ref();var map:Variant=root.get_ref()
	if not is_instance_valid(world) or not is_instance_valid(map):return {"ok":false,"reason":"map_unavailable"}
	var waiting:=false;var failure:=""
	for id:String in required.buildings:
		# An initial/transfer indoor gate already owns this full building. Reuse
		# its live lease until the player actually leaves; no duplicate ticket.
		var initial:Variant=world._building_entry
		if initial!=null and not initial.residency_pins.is_empty() and initial.issued.snapshot.get("building",{}).get("instance_id")==id:continue
		if attempts.has(id):
			var row:Dictionary=attempts[id]
			var valid:Dictionary=authority.validate(row.transaction.issued.ticket)
			var moved:bool=row.phase!="active" and feet.distance_to(row.origin)>.05
			var current:Dictionary=authority.position_snapshot(anchor.map_ref,anchor.map_revision,feet)
			var inside:bool=current.ok and current.snapshot.get("building",{}).get("instance_id")==id
			var state:Dictionary=authority.state_snapshot(row.transaction.issued.ticket) if valid.ok else {}
			var changed:bool=row.phase=="active" and not inside and state.get("building",{}).get("state_watermark",-1)!=row.transaction.state_snapshot.get("building",{}).get("state_watermark",-2)
			if not valid.ok or moved or changed:_release(id,"traversal_context_changed")
		if not attempts.has(id):
			var issued:Dictionary=authority.begin_traversal(anchor,feet,clip,id)
			if not issued.ok:last_reason=str(issued.reason);return issued
			var tx:=Transaction.new();tx.authority=authority;tx.root=root;tx.issued=issued;tx.gate=Gate.new()
			tx.gate.begin(issued.snapshot);tx.gate.mark("metadata",tx.gate.token())
			tx.demand_id="building_walk:%d"%int(issued.ticket.epoch)
			tx.retain_residency()
			attempts[id]={"transaction":tx,"origin":feet,"phase":"preparing","draw":-1,"error":""}
		if attempts[id].phase!="active":
			waiting=true
			if not str(attempts[id].get("error","")).is_empty():failure=str(attempts[id].error)
	if waiting:last_reason=failure;return {"ok":false,"reason":"building_pending" if failure.is_empty() else failure}
	last_reason="";return {"ok":true}

func tick()->void:
	if attempts.is_empty():return
	var world:Variant=owner.get_ref();var map:Variant=root.get_ref()
	if not is_instance_valid(world) or not is_instance_valid(map) or world._map_root!=map or world._transfer_pending:
		_cancel_attempts("map_replaced");return
	# No intent has referenced this speculative demand recently (rest/death/UI).
	# An indoor full lease remains necessary even if movement input has stopped.
	if Engine.get_physics_frames()-_last_guard_tick>3:
		var here:Dictionary=authority.position_snapshot(anchor.map_ref,anchor.map_revision,world._player.global_position-Vector3.UP*.9)
		for id:String in attempts.keys():
			if here.ok and here.snapshot.get("building",{}).get("instance_id")!=id:_release(id,"intent_retired")
		if attempts.is_empty():return
	# At most one complete-building evidence scan per rendered process frame.
	var ids:Array=attempts.keys();_cursor%=(ids.size());var id:String=ids[_cursor];_cursor+=1
	var row:Dictionary=attempts[id]
	if row.phase=="active" or not row.error.is_empty():return
	var tx:RefCounted=row.transaction;var valid:Dictionary=authority.validate(tx.issued.ticket)
	if not valid.ok:row.error=str(valid.reason);return
	var deferred:Node=map.get_node_or_null("DeferredAssets")
	if deferred!=null and not deferred._reference_index.is_empty():
		if not deferred.error.is_empty():row.error=deferred.error;return
		if not deferred.group_is_published(tx.issued.required_group):return
	var current:Dictionary=authority.state_snapshot(tx.issued.ticket)
	if not current.ok:row.error=str(current.reason);return
	if tx.state_snapshot.is_empty() or tx.state_snapshot.building.state_watermark!=current.building.state_watermark:
		var applied:Dictionary=authority.apply_state_snapshot(tx.issued.ticket,map)
		if not applied.ok:return # Group publication may precede fixture installation.
		tx.state_snapshot=tx.issued.snapshot.duplicate(true);tx.state_snapshot.building=applied.building
		# A newer full authoritative snapshot may skip several door revisions.
		# Start fresh local evidence against the same fixed authority ticket;
		# never fabricate intermediate receipts or extend its deadline.
		tx.gate=Gate.new();tx.gate.begin(tx.issued.snapshot);tx.gate.mark("metadata",tx.gate.token())
		tx.state_applied_frame=Engine.get_physics_frames();row.phase="preparing"
		return
	var receipt:Dictionary=authority.inspect_root(tx.state_snapshot,map,Engine.get_physics_frames(),tx.state_applied_frame)
	if not receipt.ok:row.phase="preparing";return
	if row.phase=="preparing":
		var complete:Dictionary=tx.gate.complete_building(receipt,tx.gate.token())
		if not complete.ok:row.error=str(complete.reason);return
		for stage:String in ["geometry","physics","render","base_gameplay"]:tx.gate.mark(stage,tx.gate.token())
		row.phase="awaiting_draw";row.draw=draw_serial;return
	if DisplayServer.get_name()=="headless" or draw_serial<=int(row.draw):return
	tx.gate.mark("first_frame",tx.gate.token())
	var feet:Vector3=world._player.global_position-Vector3.UP*.9
	var approved:Dictionary=authority.authorize_traversal(tx.issued.ticket,tx.gate.report(),feet,_placement_valid)
	if not approved.ok:row.error=str(approved.reason);return
	var active:Dictionary=tx.gate.authorize_activation(tx.gate.token(),approved.state_watermark)
	if not active.ok:row.error=str(active.reason);return
	row.phase="active"

func _placement_valid(_snapshot:Dictionary)->bool:
	var world:Variant=owner.get_ref();var map:Variant=root.get_ref()
	# Only validate the unchanged authoritative origin here. The existing
	# motion authority still performs actual support/capsule/step collision.
	return is_instance_valid(world) and is_instance_valid(map) and world._map_root==map and not world._transfer_pending and world._building_entry!=null and world._building_entry.issued.ticket==anchor and world._building_movement_allowed()

func _release(id:String,reason:String)->void:
	var tx:RefCounted=attempts[id].transaction
	tx.cancel(reason);authority.forget_traversal(tx.issued.ticket);attempts.erase(id)

func _cancel_attempts(reason:String)->void:
	for id:String in attempts.keys():_release(id,reason)

func dispose()->void:
	_cancel_attempts("traversal_retired")
	if _draw_callback.is_valid() and RenderingServer.frame_post_draw.is_connected(_draw_callback):RenderingServer.frame_post_draw.disconnect(_draw_callback)
	_draw_callback=Callable()

func report()->Dictionary:
	var rows:Dictionary={}
	for id:String in attempts:rows[id]={"phase":attempts[id].phase,"epoch":attempts[id].transaction.issued.ticket.epoch,"pins":attempts[id].transaction.residency_pins.size(),"error":attempts[id].error}
	return {"reason":last_reason,"buildings":rows}
