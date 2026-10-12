extends RefCounted
## One main-thread frame ledger, shared by loading services. This bounds when
## work may START, not the duration of an indivisible engine upload/shape call.
## Lane caps bound admission; a FIFO protected turn prevents repeated earlier
## indivisible overruns starving later callbacks across render frames.
static var enabled:=false # Enable only after full-entry and walking comparison.
const INTERACTIVE:={"collision":2000,"publication":1500,"batch":1000,"navigation":500,"wind":500,"retire":500}
const COVERED:={"collision":8000,"publication":7000,"batch":5000,"navigation":2000,"wind":1000,"retire":1000}
var _frame:=-1
var _covered:=false
var _spent:Dictionary={}
var _total:=0
var _seen:Dictionary={}
var _granted:Dictionary={}
var _waiting:Array[String]=[]
var _protected_lane:=""
var counters:Dictionary={"frames":0,"elapsed_us":0,"max_frame_us":0,"over_budget_frames":0,"denied":0,"lanes":{},"protected_turns":0,"protected_grants":0,"priority_denials":0,"absent_protected_turns":0}
static var _shared:RefCounted

static func shared()->RefCounted:
	if _shared==null:_shared=load("res://scripts/world3d/frame_work_budget.gd").new()
	return _shared

static func allowance(lane:String,wanted:int,covered:bool=false)->int:
	if not enabled:return maxi(0,wanted)
	return shared().request(Engine.get_process_frames(),lane,wanted,covered)

static func charge(lane:String,started:int)->void:
	if enabled:shared().record(Engine.get_process_frames(),lane,maxi(0,Time.get_ticks_usec()-started))

static func report()->Dictionary:
	return shared().snapshot()

func _advance(frame:int)->void:
	if frame==_frame:return
	if _frame>=0:
		counters.max_frame_us=maxi(counters.max_frame_us,_total)
		if _total>_limit():counters.over_budget_frames+=1
		if not _protected_lane.is_empty() and not _seen.has(_protected_lane):counters.absent_protected_turns+=1
		# A service that disappeared may hold one frame, never an enduring lock.
		# Request/record have no callback into that service and retain only names.
		for i in range(_waiting.size()-1,-1,-1):
			if not _seen.has(_waiting[i]) or _granted.has(_waiting[i]):_waiting.remove_at(i)
	_protected_lane=_waiting[0] if not _waiting.is_empty() else ""
	if not _protected_lane.is_empty():counters.protected_turns+=1
	_seen.clear();_granted.clear()
	_frame=frame;_covered=false;_spent.clear();_total=0;counters.frames+=1

func _limit()->int:return 24000 if _covered else 6000

func request(frame:int,lane:String,wanted:int,covered:bool=false)->int:
	_advance(frame)
	if not INTERACTIVE.has(lane) or wanted<=0:return 0
	_seen[lane]=true
	_covered=_covered or covered
	# Only one previously denied lane owns this frame's first production turn.
	# Do not add per-lane minimums after overrun: defer earlier callbacks instead.
	# Retirement also respects this turn, but an absent head expires next frame.
	if not _protected_lane.is_empty() and lane!=_protected_lane:
		counters.priority_denials+=1
		return _deny(lane)
	var limits:Dictionary=COVERED if _covered else INTERACTIVE
	var lane_left:int=maxi(0,int(limits[lane])-int(_spent.get(lane,0)))
	var left:int=maxi(0,_limit()-_total)
	# At most one bounded retire slice may still START after an indivisible
	# producer overruns. It prevents live results monopolising memory forever.
	# Its actual cost is charged and exposed as an overrun, never hidden.
	if lane=="retire" and int(_spent.get(lane,0))==0:left=maxi(left,250)
	var result:int=mini(wanted,mini(lane_left,left))
	if result==0:return _deny(lane)
	_granted[lane]=true;_waiting.erase(lane)
	if lane==_protected_lane:
		_protected_lane="";counters.protected_grants+=1
	return result

func _deny(lane:String)->int:
	counters.denied+=1
	# A lane that already received work this frame is not starvation debt.
	if not _granted.has(lane) and not _waiting.has(lane):_waiting.append(lane)
	return 0

func record(frame:int,lane:String,elapsed:int)->void:
	_advance(frame)
	if not INTERACTIVE.has(lane):return
	var cost:=maxi(0,elapsed)
	_spent[lane]=int(_spent.get(lane,0))+cost;_total+=cost
	counters.elapsed_us+=cost
	if not counters.lanes.has(lane):counters.lanes[lane]={"calls":0,"elapsed_us":0,"max_call_us":0}
	var row:Dictionary=counters.lanes[lane]
	row.calls+=1;row.elapsed_us+=cost;row.max_call_us=maxi(row.max_call_us,cost)

func snapshot()->Dictionary:
	var result:Dictionary=counters.duplicate(true)
	result.enabled=enabled;result.frame=_frame;result.covered=_covered
	result.current_spent_us=_total;result.current_lanes=_spent.duplicate()
	result.current_limit_us=_limit();result.max_frame_us=maxi(result.max_frame_us,_total)
	result.current_over_budget=_total>_limit()
	result.current_priority_lane=_protected_lane;result.waiting_lanes=_waiting.duplicate()
	return result
