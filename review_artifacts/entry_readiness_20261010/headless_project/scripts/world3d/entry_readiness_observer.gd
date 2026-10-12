extends RefCounted
## Observation only: no caller may use this object to unlock, freeze or load.
## Legacy entry lacks authoritative building membership, so the proposed contract
## deliberately remains pending while we measure the existing full-gate path.
const Contract=preload("res://scripts/world3d/entry_readiness.gd")
var _contract:RefCounted
var _ticket:Dictionary={}
var _clock:Callable
var _observed:Dictionary={}
var _start_result:Dictionary={}
var _first_frame_result:Dictionary={}
var _geometry_physics_frame:=-1
var _physics_observed:=false
var _frozen:Dictionary={}

func _init(clock:Callable=Callable())->void:
	_clock=clock
	_contract=Contract.new(clock)

func begin(snapshot:Dictionary)->void:
	if not _start_result.is_empty():return
	var unknown:=snapshot.duplicate(true)
	unknown.membership="unresolved";unknown.erase("building")
	_start_result=_contract.begin(unknown)
	if _start_result.ok:
		_ticket=_contract.token()
		_contract.mark("metadata",_ticket)
	_event("metadata_observed_us")

func geometry_published(physics_frame:int)->void:
	if not _frozen.is_empty() or _geometry_physics_frame>=0:return
	_geometry_physics_frame=physics_frame
	_contract.mark("geometry",_ticket)
	_event("geometry_published_us")

func needs_physics_frame()->bool:
	return _frozen.is_empty() and _geometry_physics_frame>=0 and not _physics_observed

func observe_physics_frame(physics_frame:int)->void:
	if not needs_physics_frame() or physics_frame<=_geometry_physics_frame:return
	_physics_observed=true
	_observed.physics_frame=physics_frame
	_contract.mark("physics",_ticket)
	_event("physics_frame_observed_us")

func base_gameplay_mounted()->void:
	if not _frozen.is_empty():return
	_contract.mark("base_gameplay",_ticket)
	_event("base_gameplay_mounted_us")

func render_prepared()->void:
	if not _frozen.is_empty():return
	_contract.mark("render",_ticket)
	_event("legacy_render_prepared_us")

func navigation_ready()->void:
	if not _frozen.is_empty():return
	_contract.set_capability("navigation",true,_ticket)
	_event("navigation_ready_observed_us")

func wind_prepared()->void:
	if not _frozen.is_empty():return
	# Current prepare() warms shader variants, but does not prove every receiver
	# has its runtime material bound. Do not misreport this as wind_ready.
	_event("wind_preparation_completed_us")

func first_frame(rendered:bool)->void:
	if not _frozen.is_empty():return
	if rendered:
		_event("first_frame_rendered_us")
		_first_frame_result=_contract.mark("first_frame",_ticket)
	else:_event("headless_frame_surrogate_us")

func legacy_released()->void:
	if not _frozen.is_empty():return
	_event("legacy_full_gate_released_us")
	# Stop observation at this entry's old handoff. Unknown membership must not
	# produce an unrelated timeout report minutes later in the active game.
	_frozen=report()

func cancelled(reason:String)->void:
	if not _frozen.is_empty():return
	_contract.cancel(reason,_ticket)
	_event("observation_cancelled_us")
	_frozen=report()

func failed(reason:String)->void:
	if not _frozen.is_empty():return
	_contract.fail(reason,_ticket)
	_event("observation_failed_us")
	_frozen=report()

func report()->Dictionary:
	if not _frozen.is_empty():return _frozen.duplicate(true)
	var result:Dictionary=_contract.report()
	result.mode="shadow_only"
	result.early_entry_enabled=false
	result.observation_scope="initial_world_entry_only"
	result.authority_evidence="building_membership_unavailable"
	result.note="Legacy full gate is unchanged. Observations are not authority/building proof; the proposed early-entry contract remains unresolved. Wind preparation is not receiver activation."
	result.start_result=_start_result.duplicate(true)
	result.observed=_observed.duplicate(true)
	result.geometry_physics_frame=_geometry_physics_frame
	result.first_frame_contract_result=_first_frame_result.duplicate(true)
	return result

func _event(key:String)->void:
	if not _observed.has(key):_observed[key]=int(_clock.call()) if _clock.is_valid() else Time.get_ticks_usec()
