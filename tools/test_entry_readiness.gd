extends SceneTree
## Pure CPU contract tests. No map writes, rendering or real server assumptions.
const Gate=preload("res://scripts/world3d/entry_readiness.gd")
const Observer=preload("res://scripts/world3d/entry_readiness_observer.gd")
class Clock extends RefCounted:
	var value:=1000000
	func now()->int:return value
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func snapshot(membership:String="outdoor")->Dictionary:
	var result:={"session_id":"session_1","world_id":"world_1","map_ref":"town/river","map_revision":"source_sha_1","epoch":4,"position_m":[321.2,.9,160.3],"membership":membership}
	if membership=="indoor":result.building={"instance_id":"house_1","structure_revision":"asset_sha_7","pose_revision":"pose_3","state_watermark":8}
	return result
func proof(sequence:int=8)->Dictionary:
	return {"instance_id":"house_1","structure_revision":"asset_sha_7","pose_revision":"pose_3","state_sequence":sequence,"structure_ready":true,"render_ready":true,"physics_synchronized":true,"interactions_bound":true}
func fixture(membership:String="outdoor")->Dictionary:
	var clock:=Clock.new()
	var gate=Gate.new(clock.now)
	check(gate.begin(snapshot(membership),1000).ok,"start "+membership+" transaction")
	return {"gate":gate,"clock":clock,"ticket":gate.token()}
func local_ready(f:Dictionary)->void:
	for stage:String in ["metadata","geometry","physics","render","base_gameplay"]:
		check(f.gate.mark(stage,f.ticket).ok,"verified local stage "+stage)
func outdoor()->void:
	var f:=fixture()
	check(f.gate.entry_plan().cell==Vector2i(10,5),"contract uses current EntryPlan at reported problem point")
	var exposed:Dictionary=f.gate.entry_plan();exposed.origin=Vector3.ZERO
	check(f.gate.entry_plan().origin!=Vector3.ZERO,"plan read cannot mutate transaction")
	check(not f.gate.mark("physics",f.ticket).ok,"cannot synchronize unknown geometry")
	check(not f.gate.mark("navigation",f.ticket).ok,"optional capability cannot pretend to be a critical stage")
	local_ready(f)
	check(not f.gate.can_play(),"prepared geometry and gameplay do not imply first-frame readiness")
	check(not f.gate.authorize_activation(f.ticket).ok,"authority cannot bypass missing first frame")
	check(f.gate.mark("first_frame",f.ticket).ok and f.gate.report().state=="ready","first frame prepares but does not authorize gameplay")
	check(f.gate.set_capability("navigation",false,f.ticket,"bake_failed").ok,"navigation failure is capability-local")
	check(f.gate.set_capability("wind",false,f.ticket,"shader_failed").ok,"wind failure is capability-local")
	check(f.gate.authorize_activation(f.ticket).ok and f.gate.can_play(),"outdoor activation does not wait for navigation or wind")
	f.clock.value+=2000000
	check(f.gate.can_play(),"entry deadline does not relock an already active world")
	check(f.gate.set_capability("wind",true,f.ticket).ok and f.gate.can_play(),"late wind completion keeps active state")
	check(f.gate.authorize_activation(f.ticket).get("duplicate",false),"duplicate valid activation is idempotent")
	var report:Dictionary=f.gate.report();report.gates.physics=false
	check(f.gate.report().gates.physics,"diagnostic report is detached from state")
func indoor()->void:
	var f:=fixture("indoor")
	local_ready(f)
	check(not f.gate.mark("first_frame",f.ticket).ok,"terrain and local collision cannot release indoor player")
	for field:String in ["structure_ready","render_ready","physics_synchronized","interactions_bound"]:
		var incomplete:=proof();incomplete[field]=false
		check(not f.gate.complete_building(incomplete,f.ticket).ok,"building requires "+field)
	for field:String in ["instance_id","structure_revision","pose_revision"]:
		var wrong:=proof();wrong[field]="old_value"
		check(not f.gate.complete_building(wrong,f.ticket).ok,"reject stale building "+field)
	check(not f.gate.complete_building(proof(7),f.ticket).ok,"old door snapshot cannot satisfy authority watermark")
	check(f.gate.complete_building(proof(),f.ticket).ok,"complete exact building can become ready")
	check(f.gate.mark("first_frame",f.ticket).ok,"indoor first frame follows complete building")
	var built_us:int=f.gate.report().milestones.building_ready_us
	check(not f.gate.apply_building_state(proof(10),f.ticket).ok,"state gap requires resynchronization, not silent sequence skipping")
	var unsynchronized:=proof(9);unsynchronized.physics_synchronized=false
	check(not f.gate.apply_building_state(unsynchronized,f.ticket).ok and f.gate.report().applied_state_sequence==8,"unapplied door collision cannot advance state watermark")
	check(f.gate.apply_building_state(proof(9),f.ticket).ok,"door increment applies without rebuilding structure")
	check(f.gate.report().building_complete and f.gate.report().milestones.building_ready_us==built_us,"door increment retains complete-building evidence")
	check(not f.gate.authorize_activation(f.ticket,9).ok,"new door state must be drawn before entry activation")
	check(f.gate.mark("first_frame",f.ticket).ok,"new first frame observes applied door increment")
	check(not f.gate.authorize_activation(f.ticket,10).ok,"authority cut cannot exceed applied dynamic state")
	check(f.gate.authorize_activation(f.ticket,9).ok and f.gate.can_play(),"exact indoor revision, state and epoch permit entry")
	check(f.gate.apply_building_state(proof(10),f.ticket).ok and f.gate.can_play(),"door change after entry does not reopen whole-building loading")
	check(f.gate.apply_building_state(proof(10),f.ticket).get("duplicate",false),"duplicate door event is idempotent")
	check(not f.gate.apply_building_state(proof(9),f.ticket).ok and f.gate.report().applied_state_sequence==10,"late door event cannot overwrite newer state")
	var changed:=proof(11);changed.pose_revision="moved_house"
	check(not f.gate.apply_building_state(changed,f.ticket).ok,"building movement is not a door-state update")
	check(f.gate.obsolete("building_pose_changed",f.ticket).ok and not f.gate.can_play(),"owner can revoke stale structural or pose evidence")
func unknown_and_stale()->void:
	var f:=fixture("unresolved")
	local_ready(f)
	check(not f.gate.mark("first_frame",f.ticket).ok,"unresolved ownership never defaults to outdoor")
	var source:=snapshot("indoor")
	check(f.gate.resolve_membership(source,f.ticket).ok,"authority can resolve unknown membership to indoor")
	source.building.pose_revision="mutated_by_caller"
	check(f.gate.report().building.pose_revision=="pose_3","membership owns immutable snapshot copy")
	check(not f.gate.resolve_membership(snapshot(),f.ticket).ok,"confirmed indoor membership cannot silently become outdoor")
	for field:String in ["session_id","world_id","map_ref","map_revision","epoch","attempt_id"]:
		var stale:Dictionary=f.ticket.duplicate()
		stale[field]=int(stale[field])+1 if typeof(stale[field])==TYPE_INT else "different"
		check(not f.gate.complete_building(proof(),stale).ok,"reject completion from another "+field)
	check(not f.gate.report().building_complete,"stale receipts cannot unlock or damage pending current building")
	var retry:=fixture("indoor")
	check(not retry.gate.mark("metadata",f.ticket).ok,"retry at same epoch still rejects prior attempt receipt")
	var outdoor_f:=fixture("unresolved")
	check(outdoor_f.gate.resolve_membership(snapshot(),outdoor_f.ticket).ok,"explicit outdoor ownership is valid")
	check(outdoor_f.gate.resolve_membership(snapshot(),outdoor_f.ticket).get("duplicate",false),"repeated ownership snapshot does not restart deadline")
func terminal_and_timeout()->void:
	for terminal:String in ["fail","cancel","obsolete"]:
		var f:=fixture()
		check(f.gate.call(terminal,"test_terminal",f.ticket).ok,"enter "+terminal+" terminal state")
		check(not f.gate.mark("metadata",f.ticket).ok and not f.gate.can_play(),"late success cannot resurrect "+terminal)
		check(not f.gate.begin(snapshot()).ok,"terminal object cannot be reused under old token")
	var f:=fixture("indoor")
	f.gate.mark("metadata",f.ticket)
	var deadline:int=f.gate.report().deadline_us
	f.clock.value=deadline-1
	check(f.gate.complete_building(proof(),f.ticket).ok,"building can finish within bounded deadline")
	check(f.gate.apply_building_state(proof(9),f.ticket).ok and f.gate.report().deadline_us==deadline,"dynamic updates do not extend entry deadline")
	f.clock.value=deadline
	check(f.gate.report().state=="failed" and f.gate.report().reason=="entry_timeout","pending entry reaches explicit timeout failure")
	check(not f.gate.mark("geometry",f.ticket).ok,"completion after timeout cannot revive entry")
	var clock:=Clock.new();var gate=Gate.new(clock.now)
	gate.begin(snapshot(),1000)
	clock.value+=900000;gate.report();clock.value-=800000
	gate.report();clock.value=2000000
	check(gate.report().reason=="entry_timeout","clock rollback cannot postpone monotonic deadline")
func invalid_inputs()->void:
	for field:String in ["session_id","world_id","map_ref","map_revision","epoch","position_m","membership"]:
		var gate=Gate.new();var bad:=snapshot();bad.erase(field)
		check(not gate.begin(bad).ok and gate.report().state=="idle","invalid snapshot fails without state change: "+field)
	var gate=Gate.new();var bad:=snapshot("indoor");bad.building.erase("pose_revision")
	check(not gate.begin(bad).ok,"indoor snapshot requires placement revision")
	bad=snapshot();bad.position_m=[INF,0,0]
	check(not gate.begin(bad).ok,"nonfinite position cannot enter readiness contract")
	bad=snapshot();bad.epoch=4.0
	check(not gate.begin(bad).ok,"protocol epoch must be integer")
	check(not gate.begin(snapshot(),0).ok,"entry timeout must be bounded positive value")
	check(not gate.can_play(),"invalid metadata never yields playable")
func required_gates()->void:
	for missing:String in Gate.STAGES:
		var f:=fixture()
		for stage:String in Gate.STAGES:
			if stage!=missing:f.gate.mark(stage,f.ticket)
		check(not f.gate.authorize_activation(f.ticket).ok and not f.gate.can_play(),"missing "+missing+" cannot activate")
func shadow_observation()->void:
	var clock:=Clock.new();var observer=Observer.new(clock.now)
	observer.begin(snapshot("indoor"))
	check(observer.report().membership=="unresolved" and observer.report().building.is_empty(),"legacy observer cannot invent authoritative building membership")
	observer.geometry_published(10)
	observer.observe_physics_frame(10)
	check(not observer.report().gates.physics and observer.needs_physics_frame(),"same publishing frame is not physics synchronization evidence")
	clock.value+=100;observer.observe_physics_frame(11)
	check(observer.report().gates.physics and not observer.needs_physics_frame(),"actual later physics tick is recorded once")
	observer.base_gameplay_mounted();observer.render_prepared();observer.navigation_ready();observer.wind_prepared()
	observer.first_frame(false)
	check(observer.report().observed.has("headless_frame_surrogate_us") and not observer.report().observed.has("first_frame_rendered_us"),"headless process tick does not claim a rendered world frame")
	observer.first_frame(true)
	var observed:Dictionary=observer.report()
	check(observed.observed.has("first_frame_rendered_us") and not observed.gates.first_frame,"real rendered frame remains distinct from missing authority evidence")
	check(observed.first_frame_contract_result.reason=="required_content_pending" and "membership" in observed.pending,"shadow explains why new entry contract is still incomplete")
	check(observed.capabilities.navigation.state=="ready" and observed.capabilities.wind.state=="pending","shader warmup is not misreported as wind receiver activation")
	observer.legacy_released()
	var frozen:Dictionary=observer.report()
	check(frozen.mode=="shadow_only" and not frozen.early_entry_enabled and frozen.observed.has("legacy_full_gate_released_us"),"old full-gate handoff does not authorize proposed early-entry policy")
	clock.value+=900000000
	observer.cancelled("later_world_exit")
	check(observer.report()==frozen,"entry observation freezes at old handoff without later timeout or exit contamination")
	frozen.observed.clear()
	check(not observer.report().observed.is_empty(),"frozen profile cannot be mutated through report")
	var failure=Observer.new(clock.now);failure.begin(snapshot());failure.failed("geometry_missing")
	check(failure.report().state=="failed" and failure.report().reason=="geometry_missing","real entry failure has an explicit shadow terminal result")
	var cancelled=Observer.new(clock.now);cancelled.begin(snapshot());cancelled.cancelled("world_exited")
	check(cancelled.report().state=="cancelled","entry teardown before handoff records cancellation")
func run()->void:
	outdoor();indoor();unknown_and_stale();terminal_and_timeout();invalid_inputs();required_gates();shadow_observation()
	print("ENTRY_READINESS ",checks," checks / ",failures," failures")
	quit(1 if failures else 0)
