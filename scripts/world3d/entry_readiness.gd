extends RefCounted
## One entry transaction's evidence, not a loader, physics query or server.
## Producers must report verified results after their real synchronization point.
## This contract does not replace the existing production gates until integrated.
const Plan=preload("res://scripts/world3d/entry_plan.gd")
const CONTEXT_FIELDS:=["session_id","world_id","map_ref","map_revision","epoch"]
const BUILDING_FIELDS:=["instance_id","structure_revision","pose_revision"]
const STAGES:=["metadata","geometry","physics","render","base_gameplay","first_frame"]
const OPTIONAL:=["navigation","wind"]
const TERMINAL:=["failed","cancelled","obsolete"]

var _clock:Callable
var _last_now:=0
var _state:="idle"
var _reason:=""
var _context:Dictionary={}
var _plan:Dictionary={}
var _membership:="unresolved"
var _building:Dictionary={}
var _building_complete:=false
var _applied_sequence:=-1
var _building_members:Array=[]
var _fixture_states:Dictionary={}
var _gates:Dictionary={}
var _capabilities:Dictionary={}
var _milestones:Dictionary={}
var _started_us:=0
var _deadline_us:=0


func _init(clock:Callable=Callable())->void:
	_clock=clock


## snapshot.position_m accepts WorldLocation's [x,y,z] or its Vector3 input.
## Reuse EntryPlan's actual chunk/safety contract; this module invents no radius.
## An object is single-use. Retry uses a new attempt token even for the same epoch.
func begin(snapshot:Dictionary,timeout_ms:int=180000)->Dictionary:
	if _state!="idle":return _reject("already_started")
	for key:String in ["session_id","world_id","map_ref","map_revision"]:
		if not _text(snapshot.get(key)):return _reject("invalid_"+key)
	if not _integer(snapshot.get("epoch")):return _reject("invalid_epoch")
	if timeout_ms<=0 or timeout_ms>2147483647:return _reject("invalid_timeout")
	var origin:=_position(snapshot.get("position_m"))
	var plan:Dictionary=Plan.create(origin)
	if plan.is_empty():return _reject("invalid_position")
	var membership_error:=_membership_error(snapshot)
	if not membership_error.is_empty():return _reject(membership_error)
	for key:String in CONTEXT_FIELDS:_context[key]=snapshot[key]
	_context.position_m=[origin.x,origin.y,origin.z]
	_context.attempt_id=get_instance_id()
	_plan=plan
	_set_membership(snapshot)
	for stage:String in STAGES:_gates[stage]=false
	for capability:String in OPTIONAL:_capabilities[capability]={"state":"pending","reason":""}
	_started_us=_now();_deadline_us=_started_us+timeout_ms*1000
	_state="preparing"
	return {"ok":true,"token":token(),"plan":entry_plan()}


func token()->Dictionary:
	return _context.duplicate(true)


func entry_plan()->Dictionary:
	return _plan.duplicate(true)


## Only a trusted authority adapter may resolve an unknown membership.
## Conflicting ownership needs a new transaction, never a silent gate rewrite.
func resolve_membership(snapshot:Dictionary,ticket:Dictionary)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	for key:String in CONTEXT_FIELDS:
		if snapshot.get(key)!=_context[key]:return _reject("membership_context_mismatch")
	if _position(snapshot.get("position_m"))!=_position(_context.position_m):return _reject("membership_position_mismatch")
	var validation:=_membership_error(snapshot)
	if not validation.is_empty():return _reject(validation)
	if snapshot.membership=="unresolved":return _reject("membership_unresolved")
	if _membership!="unresolved":
		if snapshot.membership!=_membership:return _reject("membership_conflict")
		if _membership=="indoor" and snapshot.building!=_building:return _reject("membership_conflict")
		return {"ok":true,"duplicate":true}
	_set_membership(snapshot)
	_refresh_state()
	return {"ok":true}


## geometry means the entire required local support/blocking closure is ready,
## not merely terrain_ready or a cached mesh. physics follows actual server sync.
func mark(stage:String,ticket:Dictionary)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	if stage not in STAGES:return _reject("unknown_stage")
	if _gates[stage]:return {"ok":true,"duplicate":true}
	if stage!="metadata" and not _gates.metadata:return _reject("metadata_pending")
	if stage in ["physics","render"] and not _gates.geometry:return _reject("geometry_pending")
	if stage=="first_frame" and not _can_draw_ready_frame():return _reject("required_content_pending")
	_gates[stage]=true
	_milestones[stage+"_ready_us"]=_now()
	_refresh_state()
	return {"ok":true}


## Complete building evidence is separate from any outdoor collision proxy.
## Pose revision also matters: reusing a shape at an old transform is not ready.
func complete_building(receipt:Dictionary,ticket:Dictionary)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	error=_building_receipt_error(receipt)
	if not error.is_empty():return _reject(error)
	if not _gates.metadata:return _reject("metadata_pending")
	for key:String in ["structure_ready","render_ready","physics_synchronized","interactions_bound"]:
		if not _true(receipt.get(key)):return _reject("building_"+key+"_pending")
	if int(receipt.state_sequence)<int(_building.state_watermark):return _reject("building_state_pending")
	if _building.has("member_ids") and receipt.get("member_ids",[])!=_building.member_ids:return _reject("building_members_pending")
	if _building.has("fixture_states") and not receipt.get("fixture_states") is Dictionary:return _reject("building_fixture_states_missing")
	if _building_complete:
		if int(receipt.state_sequence)!=_applied_sequence:return _reject("use_ordered_state_update")
		return {"ok":true,"duplicate":true}
	_building_complete=true;_applied_sequence=int(receipt.state_sequence)
	_building_members=receipt.get("member_ids",[]).duplicate();_fixture_states=receipt.get("fixture_states",{}).duplicate(true)
	_milestones.building_ready_us=_now()
	_refresh_state()
	return {"ok":true}


## Report an applied contiguous dynamic-state update, after collision/render sync.
## No structural gates are reset. A not-yet-active entry must draw the new state;
## an active world handles later door updates normally without re-entering loading.
func apply_building_state(receipt:Dictionary,ticket:Dictionary)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	error=_building_receipt_error(receipt)
	if not error.is_empty():return _reject(error)
	if not _building_complete:return _reject("building_pending")
	if _building.has("member_ids") and receipt.get("member_ids",[])!=_building.member_ids:return _reject("building_members_pending")
	if _building.has("fixture_states") and not receipt.get("fixture_states") is Dictionary:return _reject("building_fixture_states_missing")
	var sequence:int=receipt.state_sequence
	if sequence==_applied_sequence:return {"ok":true,"duplicate":true}
	if sequence<_applied_sequence:return _reject("stale_building_state")
	if sequence!=_applied_sequence+1:return _reject("building_state_gap")
	for key:String in ["render_ready","physics_synchronized","interactions_bound"]:
		if not _true(receipt.get(key)):return _reject("building_"+key+"_pending")
	_applied_sequence=sequence
	_fixture_states=receipt.get("fixture_states",{}).duplicate(true)
	if _state!="active":
		_gates.first_frame=false;_milestones.erase("first_frame_ready_us")
	_refresh_state()
	return {"ok":true}


## Called by the authority adapter for this transaction, not by a mesh callback.
## The authority chooses a fixed state cut; ordinary position packets do not
## advance epoch or continuously move this watermark. Deadline never restarts.
func authorize_activation(ticket:Dictionary,state_watermark:int=-1)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	if _membership=="indoor":
		if state_watermark<int(_building.state_watermark):return _reject("invalid_activation_watermark")
		if not _building_complete or _applied_sequence<state_watermark:return _reject("building_state_pending")
	elif state_watermark!=-1:return _reject("unexpected_activation_watermark")
	if _state=="active":return {"ok":true,"duplicate":true}
	if not _all_required():return _reject("required_content_pending")
	_state="active";_milestones.playable_ready_us=_now()
	return {"ok":true}


func set_capability(capability:String,ready:bool,ticket:Dictionary,reason:String="")->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	if capability not in OPTIONAL:return _reject("unknown_capability")
	_capabilities[capability]={"state":"ready" if ready else ("pending" if reason.is_empty() else "failed"),"reason":reason}
	if ready:_milestones[capability+"_ready_us"]=_now()
	return {"ok":true}


func fail(reason:String,ticket:Dictionary)->Dictionary:
	return _finish("failed",reason,ticket)


func cancel(reason:String,ticket:Dictionary)->Dictionary:
	return _finish("cancelled",reason,ticket)


func obsolete(reason:String,ticket:Dictionary)->Dictionary:
	return _finish("obsolete",reason,ticket)


func can_play()->bool:
	_poll_timeout()
	return _state=="active"


func report()->Dictionary:
	_poll_timeout()
	var pending:Array=[]
	for stage:String in STAGES:
		if not _gates.get(stage,false):pending.append(stage)
	if _membership=="unresolved":pending.append("membership")
	if _membership=="indoor" and not _building_complete:pending.append("building")
	if _state=="ready":pending.append("activation_authorization")
	return {"state":_state,"reason":_reason,"token":token(),"membership":_membership,
		"building":_building.duplicate(true),"building_complete":_building_complete,
		"building_members":_building_members.duplicate(),"fixture_states":_fixture_states.duplicate(true),
		"applied_state_sequence":_applied_sequence,"gates":_gates.duplicate(true),
		"pending":pending,"capabilities":_capabilities.duplicate(true),
		"milestones":_milestones.duplicate(true),"started_us":_started_us,"deadline_us":_deadline_us}


func _finish(state:String,reason:String,ticket:Dictionary)->Dictionary:
	var error:=_receipt_error(ticket)
	if not error.is_empty():return _reject(error)
	if reason.strip_edges().is_empty():return _reject("missing_reason")
	_state=state;_reason=reason;_milestones.terminal_us=_now()
	return {"ok":true}


func _receipt_error(ticket:Dictionary)->String:
	_poll_timeout()
	if _state=="idle":return "not_started"
	if ticket!=_context:return "stale_ticket"
	if _state in TERMINAL:return "terminal_"+_state
	return ""


func _poll_timeout()->void:
	if _state in ["preparing","ready"] and _now()>=_deadline_us:
		_state="failed";_reason="entry_timeout";_milestones.terminal_us=_now()


func _all_required()->bool:
	return _can_draw_ready_frame() and _gates.first_frame


func _can_draw_ready_frame()->bool:
	if _membership=="unresolved":return false
	if _membership=="indoor" and not _building_complete:return false
	for stage:String in STAGES:
		if stage!="first_frame" and not _gates.get(stage,false):return false
	return true


func _refresh_state()->void:
	if _state in ["preparing","ready"]:_state="ready" if _all_required() else "preparing"


func _building_receipt_error(receipt:Dictionary)->String:
	if _membership!="indoor":return "building_not_required"
	for key:String in BUILDING_FIELDS:
		if receipt.get(key)!=_building[key]:return "building_identity_mismatch"
	if not _integer(receipt.get("state_sequence")):return "invalid_state_sequence"
	return ""


static func _membership_error(snapshot:Dictionary)->String:
	if snapshot.get("membership") not in ["unresolved","outdoor","indoor"]:return "invalid_membership"
	var building:Variant=snapshot.get("building",{})
	if not building is Dictionary:return "invalid_building"
	if snapshot.membership!="indoor":return "unexpected_building" if not building.is_empty() else ""
	for key:String in BUILDING_FIELDS:
		if not _text(building.get(key)):return "invalid_building_"+key
	if not _integer(building.get("state_watermark")):return "invalid_building_state_watermark"
	return ""


func _set_membership(snapshot:Dictionary)->void:
	_membership=snapshot.membership
	_building=snapshot.get("building",{}).duplicate(true)


func _now()->int:
	var current:int=int(_clock.call()) if _clock.is_valid() else Time.get_ticks_usec()
	_last_now=maxi(_last_now,current)
	return _last_now


func _reject(reason:String)->Dictionary:
	return {"ok":false,"reason":reason,"state":_state}


static func _text(value:Variant)->bool:
	return value is String and not value.strip_edges().is_empty()


static func _integer(value:Variant)->bool:
	return typeof(value)==TYPE_INT and value>=0


static func _true(value:Variant)->bool:
	return typeof(value)==TYPE_BOOL and value


static func _position(raw:Variant)->Vector3:
	if raw is Vector3:return raw
	if raw is Array and raw.size()==3:
		for value:Variant in raw:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return Vector3(NAN,NAN,NAN)
		return Vector3(raw[0],raw[1],raw[2])
	return Vector3(NAN,NAN,NAN)
