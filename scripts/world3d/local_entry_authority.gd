extends RefCounted
## In-process server adapter. Wire payloads are plain data; never retains Nodes.
## Only trusted local producers register verified maps and authority positions.
const Membership=preload("res://scripts/world3d/building_membership.gd")
const Gate=preload("res://scripts/world3d/entry_readiness.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const PROTOCOL_VERSION=1
const CAPABILITIES=["building_membership_v1","complete_building_v1","ordered_fixture_state_v1","building_traversal_v1"]
var _maps:Dictionary={}
var _sessions:Dictionary={}
var _epoch:=0
var _generation:=0
var _clock:Callable
var _last_now:=0

func _init(clock:Callable=Callable())->void:_clock=clock
func _now()->int:
	_last_now=maxi(_last_now,int(_clock.call()) if _clock.is_valid() else Time.get_ticks_usec())
	return _last_now
func clear()->void:
	_maps.clear();_sessions.clear();_generation+=1

func capabilities()->Dictionary:return {"protocol_version":PROTOCOL_VERSION,"capabilities":CAPABILITIES.duplicate(),"adapter":"in_process","persistent_reconnect":false}

func register_root(map_ref:String,map_revision:String,root:Node)->Dictionary:
	if not is_instance_valid(root):return _fail("map_unavailable")
	var complete:Dictionary=root.get_meta("author_reference_extras",root.get_meta("extras",{}))
	if root.get_meta("runtime_record_subset",false) and not root.has_meta("author_reference_extras"):return _fail("complete_author_metadata_unavailable")
	var bounds:Dictionary={};var imported:Array=[]
	var annotated:Dictionary={};var member_owners:Dictionary={}
	for raw:Dictionary in complete.get("rmmo_records",[]):
		var r:Dictionary=Membership.header(raw)
		if not r.has("model_building"):continue
		if not Membership.Imported.valid_record(r):return _fail("invalid_imported_building")
		annotated[r.uuid]=true
		for member:String in Membership.Imported.member_ids(r):member_owners[member]=r.uuid
	var deferred:=root.get_node_or_null("DeferredAssets")
	var index:Dictionary=deferred.get("_reference_index") if deferred!=null else {}
	if not index.is_empty():
		# Compact state deliberately omits immutable asset_path. Its verified
		# directory supplies the path only for this authority-side snapshot.
		complete=complete.duplicate(true)
		var paths:Dictionary={}
		for row:Dictionary in index.get("rows",[]):
			if annotated.has(row.uuid):paths[row.uuid]=str(row.get("asset_path",""))
			if row.get("bounds_known",false):
				bounds[row.uuid]=row.bounds
				if not str(row.get("asset_path","")).is_empty() and not annotated.has(row.uuid):imported.append(row.bounds)
			elif not str(row.get("asset_path","")).is_empty():return _fail("unclassified_asset_bounds")
		for raw:Dictionary in complete.get("rmmo_records",[]):
			if annotated.has(raw.uuid):raw.asset_path=paths.get(raw.uuid,"")
	else:
		# Compact references do not carry immutable kind/asset_path. Without a
		# verified directory use the complete hydrated author list, or deny proof.
		var hydrated:Dictionary=root.get_meta("extras",{})
		if root.get_meta("runtime_record_subset",false):return _fail("complete_directory_unavailable")
		if hydrated.get("rmmo_records",[]).size()!=complete.get("rmmo_records",[]).size():return _fail("complete_author_metadata_unavailable")
		complete=hydrated
		for spec:Dictionary in root.get_meta("stream_library",[]):
			var r:Dictionary=spec.get("extras",{})
			if spec.get("mesh")!=null:
				bounds[spec.uuid]=spec.transform*spec.mesh.get_aabb()
				var member:String=str(r.get("uuid",spec.uuid))
				if member_owners.has(member):
					var owner:String=member_owners[member]
					bounds[owner]=bounds[owner].merge(bounds[spec.uuid]) if bounds.has(owner) else bounds[spec.uuid]
				elif (r.get("kind")=="asset" or r.has("asset_path")) and not annotated.has(member):imported.append(bounds[spec.uuid])
	return register_map(map_ref,map_revision,complete,bounds,imported)

func register_map(map_ref:String,map_revision:String,complete_author_meta:Dictionary,bounds:Dictionary={},imported_bounds:Array=[])->Dictionary:
	if map_ref.is_empty() or map_revision.is_empty():return _fail("invalid_map_identity")
	var built:=Membership.build(complete_author_meta,bounds,imported_bounds)
	if not built.ok:return built
	var prior:Dictionary=_maps.get(map_ref,{})
	for id:String in built.buildings:
		var b:Dictionary=built.buildings[id];var previous:Dictionary=prior.get("buildings",{}).get(id,{})
		b.state_sequence=0;b.history={}
		if previous.get("structure_revision")==b.structure_revision:
			b.fixtures=previous.fixtures.duplicate(true);b.state_sequence=previous.state_sequence;b.history=previous.history.duplicate(true)
	_maps[map_ref]={"ok":true,"revision":map_revision,"buildings":built.buildings,"unknown":built.unknown,"spatial":built.spatial,"record_count":built.record_count}
	return {"ok":true,"buildings":built.buildings.size(),"protocol_version":PROTOCOL_VERSION}

## Trusted local movement authority supplies the current body feet. This is a
## checkpoint, not a new activation attempt; movement never advances epoch.
func position_snapshot(map_ref:String,map_revision:String,feet:Vector3)->Dictionary:
	var map:Dictionary=_maps.get(map_ref,{})
	if map.is_empty() or map.revision!=map_revision or not feet.is_finite():return _fail("map_revision_unavailable")
	var located:=Membership.locate(map,feet)
	if located.membership=="unresolved":return _fail("membership_unresolved")
	var snapshot:Dictionary={"map_ref":map_ref,"map_revision":map_revision,"position_m":[feet.x,feet.y,feet.z],"membership":located.membership}
	if located.membership=="indoor":snapshot.building=_building_snapshot(map.buildings[located.instance_id])
	return {"ok":true,"snapshot":snapshot}

## feet are metres, NOT the CharacterBody centre (centre minus UP * 0.9).
## A new begin supersedes the previous attempt for this session, including retry.
func begin(session_id:String,world_id:String,map_ref:String,map_revision:String,feet:Vector3,reason:String="entry",timeout_ms:int=180000)->Dictionary:
	if session_id.is_empty() or world_id.is_empty() or not feet.is_finite() or timeout_ms<=0 or timeout_ms>180000:return _fail("invalid_entry_request")
	var map:Dictionary=_maps.get(map_ref,{})
	if map.is_empty() or map.revision!=map_revision:return _fail("map_revision_unavailable")
	var located:=Membership.locate(map,feet)
	_epoch+=1
	var snapshot:Dictionary={"protocol_version":PROTOCOL_VERSION,"capabilities":CAPABILITIES.duplicate(),"session_id":session_id,"world_id":world_id,"map_ref":map_ref,"map_revision":map_revision,"epoch":_epoch,"position_m":[feet.x,feet.y,feet.z],"membership":located.membership,"reason":located.get("reason",reason)}
	var members:Array=[];var group:="";var bounds:=AABB()
	if located.membership=="indoor":
		var b:Dictionary=map.buildings[located.instance_id]
		snapshot.building=_building_snapshot(b);snapshot.floor_id=located.floor
		members=b.members.duplicate();group="building:"+located.instance_id;bounds=b.bounds
	var ticket:Dictionary={"authority_generation":_generation,"authority_id":get_instance_id(),"session_id":session_id,"world_id":world_id,"map_ref":map_ref,"map_revision":map_revision,"epoch":_epoch,"position_m":snapshot.position_m.duplicate()}
	_sessions[session_id]={"ticket":ticket,"snapshot":snapshot,"deadline_us":_now()+timeout_ms*1000,"state":"preparing","reason":""}
	return {"ok":true,"snapshot":snapshot.duplicate(true),"ticket":ticket.duplicate(true),"required_members":members,"required_group":group,"required_bounds":bounds,"membership_resolved":located.membership!="unresolved"}

func validate(ticket:Dictionary)->Dictionary:
	var current:Dictionary=_sessions.get(str(ticket.get("session_id","")),{})
	if current.is_empty() or current.ticket!=ticket:return _fail("stale_authority_ticket")
	if current.state in ["cancelled","obsolete","failed"]:return _fail(current.reason)
	if current.has("traversal"):
		var anchor:=validate(current.traversal.anchor)
		if not anchor.ok or anchor.state!="active":return _obsolete(current,"traversal_anchor_obsolete")
	if current.state!="active" and _now()>=int(current.deadline_us):current.state="failed";current.reason="entry_timeout";return _fail(current.reason)
	var map:Dictionary=_maps.get(ticket.map_ref,{})
	if map.is_empty() or map.revision!=ticket.map_revision:return _obsolete(current,"map_revision_changed")
	var snapshot:Dictionary=current.snapshot
	var located:=Membership.locate(map,Membership._vector(snapshot.position_m))
	if snapshot.membership=="unresolved" or located.membership=="unresolved":return _fail("membership_unresolved")
	if located.membership!=snapshot.membership:return _obsolete(current,"membership_changed")
	if snapshot.membership=="indoor":
		if located.get("instance_id")!=snapshot.building.instance_id:return _obsolete(current,"building_membership_changed")
		var b:Dictionary=map.buildings[located.instance_id]
		for field:String in Gate.BUILDING_FIELDS:
			if b[field]!=snapshot.building[field]:return _obsolete(current,"building_"+field+"_changed")
	return {"ok":true,"snapshot":snapshot.duplicate(true),"state":current.state}

## Reconnection keeps world state, but a fresh epoch invalidates every old reply.
func reconnect(session_id:String,world_id:String,saved_snapshot:Dictionary)->Dictionary:
	return begin(session_id,world_id,str(saved_snapshot.get("map_ref","")),str(saved_snapshot.get("map_revision","")),Membership._vector(saved_snapshot.get("position_m")),"reconnect")

## Re-resolve old position; caller must still verify CURRENT support/occupancy.
## Changed source-map/building revision cannot restore the saved transform.
func begin_recovery(session_id:String,world_id:String,previous:Dictionary)->Dictionary:
	var map:Dictionary=_maps.get(str(previous.get("map_ref","")),{})
	if map.is_empty() or map.revision!=previous.get("map_revision"):return _fail("recovery_map_changed")
	if previous.get("membership")=="indoor":
		var old:Dictionary=previous.get("building",{});var b:Dictionary=map.buildings.get(old.get("instance_id",""),{})
		for field:String in Gate.BUILDING_FIELDS:
			if b.get(field)!=old.get(field):return _fail("recovery_building_changed")
	return begin(session_id,world_id,previous.map_ref,previous.map_revision,Membership._vector(previous.get("position_m")),"recovery")

func cancel(ticket:Dictionary,reason:String="cancelled")->Dictionary:
	var current:Dictionary=_sessions.get(str(ticket.get("session_id","")),{})
	if current.is_empty() or current.ticket!=ticket:return _fail("stale_authority_ticket")
	if current.state=="cancelled":return {"ok":true,"duplicate":true}
	current.state="cancelled";current.reason=reason;return {"ok":true}

## A server adapter also checks its own current position/support/occupancy. A
## client's gate report alone can never grant movement permission.
func authorize(ticket:Dictionary,report:Dictionary,placement_check:Callable)->Dictionary:
	if ticket.get("purpose")=="building_traversal":return _fail("traversal_is_not_player_activation")
	return _authorize(ticket,report,placement_check)

func _authorize(ticket:Dictionary,report:Dictionary,placement_check:Callable)->Dictionary:
	var valid:=validate(ticket)
	if not valid.ok:return valid
	if not placement_check.is_valid() or not bool(placement_check.call(valid.snapshot)):return _fail("authority_position_unavailable")
	for field:String in Gate.CONTEXT_FIELDS:
		if report.get("token",{}).get(field)!=valid.snapshot.get(field):return _fail("stale_client_report")
	if report.get("token",{}).get("position_m")!=ticket.position_m:return _fail("position_report_mismatch")
	if report.get("state") not in ["ready","active"] or report.get("membership")!=valid.snapshot.membership:return _fail("client_not_ready")
	for stage:String in Gate.STAGES:
		if report.get("gates",{}).get(stage)!=true:return _fail("client_"+stage+"_pending")
	var watermark:=-1
	if valid.snapshot.membership=="indoor":
		var b:Dictionary=_maps[ticket.map_ref].buildings[valid.snapshot.building.instance_id]
		for field:String in Gate.BUILDING_FIELDS:
			if report.get("building",{}).get(field)!=b[field]:return _fail("building_report_mismatch")
		if not report.get("building_complete",false) or report.get("building_members",[])!=b.members:return _fail("building_members_pending")
		var applied:int=report.get("applied_state_sequence",-1)
		watermark=valid.snapshot.building.state_watermark # Fixed activation cut.
		if applied<watermark or applied>b.state_sequence:return _fail("building_state_pending")
		var expected:Variant=b.fixtures if applied==b.state_sequence else b.history.get(applied)
		if applied==watermark:expected=valid.snapshot.building.fixture_states
		if expected==null or report.get("fixture_states",{})!=expected:return _fail("building_state_pending")
	var session:Dictionary=_sessions[ticket.session_id]
	var duplicate:bool=session.state=="active"
	session.state="active"
	return {"ok":true,"duplicate":duplicate,"state_watermark":watermark,"snapshot":valid.snapshot}

## Trusted movement code submits its capsule sweep before applying the intent.
## A permit licenses complete-building readiness, not a teleport or player pose.
func traversal_requirements(anchor:Dictionary,feet:Vector3,clip:AABB)->Dictionary:
	var active:=validate(anchor)
	if not active.ok or active.state!="active":return _fail("traversal_anchor_obsolete")
	if anchor.get("purpose")=="building_traversal" or not feet.is_finite() or not clip.grow(.01).has_point(feet):return _fail("invalid_traversal_origin")
	return footprint_requirements(anchor.map_ref,anchor.map_revision,clip)

## Entry/transfer must prove the same conservative footprint as subsequent
## movement. A feet-only outdoor point beside an unresolved volume is not a
## safe starting point if every future sweep would already overlap that volume.
func footprint_requirements(map_ref:String,map_revision:String,clip:AABB)->Dictionary:
	var map:Dictionary=_maps.get(map_ref,{})
	if map.is_empty() or map.revision!=map_revision:return _fail("map_revision_unavailable")
	return Membership.sweep(map,clip)

func begin_traversal(anchor:Dictionary,feet:Vector3,clip:AABB,building_id:String)->Dictionary:
	var required:=traversal_requirements(anchor,feet,clip)
	if not required.ok:return required
	if not required.buildings.has(building_id):return _fail("building_outside_sweep")
	var issued:=begin(anchor.session_id+":traversal:"+building_id,anchor.world_id,anchor.map_ref,anchor.map_revision,required.buildings[building_id],"building_traversal")
	if not issued.ok:return issued
	if issued.snapshot.membership!="indoor" or issued.snapshot.building.instance_id!=building_id:
		cancel(issued.ticket,"ambiguous_traversal_membership");return _fail("membership_unresolved")
	var session:Dictionary=_sessions[issued.ticket.session_id]
	session.traversal={"anchor":anchor.duplicate(true),"origin":feet,"clip":clip}
	session.ticket.purpose="building_traversal";session.ticket.anchor_epoch=anchor.epoch
	session.snapshot.purpose="building_traversal"
	issued.ticket=session.ticket.duplicate(true);issued.snapshot=session.snapshot.duplicate(true)
	return issued

func authorize_traversal(ticket:Dictionary,report:Dictionary,current_feet:Vector3,placement_check:Callable)->Dictionary:
	var session:Dictionary=_sessions.get(str(ticket.get("session_id","")),{})
	if session.is_empty() or session.ticket!=ticket or not session.has("traversal"):return _fail("invalid_traversal_ticket")
	if not current_feet.is_finite() or current_feet.distance_to(session.traversal.origin)>.05:return _fail("traversal_origin_changed")
	return _authorize(ticket,report,placement_check)

func forget_traversal(ticket:Dictionary)->void:
	var id:String=str(ticket.get("session_id",""));var session:Dictionary=_sessions.get(id,{})
	if session.get("ticket") == ticket and session.has("traversal"):_sessions.erase(id)

func state_snapshot(ticket:Dictionary)->Dictionary:
	var valid:=validate(ticket)
	if not valid.ok:return valid
	if valid.snapshot.membership!="indoor":return {"ok":true,"building":{}}
	return {"ok":true,"building":_building_snapshot(_maps[ticket.map_ref].buildings[valid.snapshot.building.instance_id])}

func update_fixture(map_ref:String,map_revision:String,building_id:String,fixture_id:String,amount:float,expected_sequence:int)->Dictionary:
	var map:Dictionary=_maps.get(map_ref,{})
	if map.is_empty() or map.revision!=map_revision:return _fail("map_revision_unavailable")
	var b:Dictionary=map.buildings.get(building_id,{})
	if b.is_empty() or not b.fixtures.has(fixture_id):return _fail("fixture_unavailable")
	if not is_finite(amount) or amount<0 or amount>1:return _fail("invalid_fixture_state")
	if expected_sequence!=b.state_sequence:return _fail("fixture_sequence_conflict")
	if is_equal_approx(float(b.fixtures[fixture_id]),amount):return {"ok":true,"duplicate":true,"building":_building_snapshot(b)}
	b.history[b.state_sequence]=b.fixtures.duplicate(true)
	if b.history.size()>64:b.history.erase(b.history.keys().min())
	b.fixtures[fixture_id]=amount;b.state_sequence+=1
	return {"ok":true,"building":_building_snapshot(b),"fixture_id":fixture_id,"open":amount}

## Existing World3D door/window API delegates here. No author records are edited.
func set_runtime_fixture(root:Node,map_ref:String,map_revision:String,building_id:String,fixture_id:String,amount:float,duration:float=.35)->Dictionary:
	var map:Dictionary=_maps.get(map_ref,{})
	if map.is_empty() or map.revision!=map_revision:return _fail("map_revision_unavailable")
	var b:Dictionary=map.buildings.get(building_id,{})
	if b.is_empty() or not b.fixtures.has(fixture_id):return _fail("fixture_unavailable")
	if not is_instance_valid(root):return _fail("map_unavailable")
	var result:=Fixtures.set_runtime(root,building_id,fixture_id,amount,duration)
	if not result.ok:return result
	var changed:=update_fixture(map_ref,map_revision,building_id,fixture_id,amount,b.state_sequence)
	result.authority_state=changed
	return result

func apply_state_snapshot(ticket:Dictionary,root:Node)->Dictionary:
	var current:=state_snapshot(ticket)
	if not current.ok or current.building.is_empty():return current
	var present:Dictionary={}
	for row:Dictionary in Fixtures.list_runtime(root,current.building.instance_id):present[row.id]=true
	for id:String in current.building.fixture_states:
		if not present.has(id):return _fail("fixture_members_pending")
	for id:String in current.building.fixture_states:
		var result:=Fixtures.set_runtime(root,current.building.instance_id,id,current.building.fixture_states[id],0)
		if not result.ok:return _fail("fixture_apply_failed")
	return current

func inspect_root(snapshot:Dictionary,root:Node,physics_frame:int,published_frame:int)->Dictionary:
	return preload("res://scripts/world3d/building_readiness_evidence.gd").inspect(snapshot,root,physics_frame,published_frame)

static func _building_snapshot(b:Dictionary)->Dictionary:
	return {"instance_id":b.instance_id,"structure_revision":b.structure_revision,"pose_revision":b.pose_revision,"state_watermark":b.state_sequence,"member_ids":b.members.duplicate(),"fixture_states":b.fixtures.duplicate(true)}

static func _obsolete(session:Dictionary,reason:String)->Dictionary:
	session.state="obsolete";session.reason=reason;return _fail(reason)
static func _fail(reason:String)->Dictionary:return {"ok":false,"reason":reason}
