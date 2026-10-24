extends RefCounted
## Bound service bursts between already prepared closures. White visual work
## also gives lower priorities bounded turns. No resource ownership.
const MAX_BURST:=4
const DRAIN_BURST:=16
const MAX_DRAIN_BYPASSES:=4
static var completed_owner_drain_enabled:=true
static var white_building_turns_enabled:=true
static var white_priority_turns_enabled:=true
static func preserve_building_material_order()->bool:
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	# White results have no authored textures to localise. Serialising all houses
	# behind one large group leaves ready owners occupying the producer slots.
	return not white_building_turns_enabled or not (controls.white_materials and controls.discard_map_textures)
var _serial:=0
var _served:Dictionary={}
var _burst_path:=""
var _burst_count:=0
var _near_service_count:=0
var _near_priority:=2147483647
var _drain_path:=""
var _drain_generation:=0
var _drain_burst:=0
var _drain_age:Dictionary={}
var _drain_protected:=false
var _ready_epoch:=0
var _ready_seen:Dictionary={}
var drain_selected:=false

func choose(heads:Array,priorities:Dictionary,ranks:Dictionary,jobs:Dictionary,pressure:bool=false,remaining:Dictionary={})->Dictionary:
	drain_selected=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var drain_mode:bool=completed_owner_drain_enabled and pressure and controls.white_materials and controls.discard_map_textures
	if not drain_mode:_clear_drain()
	for path:String in _served.keys():
		if not jobs.has(path):_served.erase(path)
	if not _drain_age.is_empty():
		var generations:Dictionary={}
		for job:Dictionary in jobs.values():
			if job.has("token"):generations[job.token.get_instance_id()]=true
		for generation:int in _drain_age.keys():
			if not generations.has(generation):_drain_age.erase(generation)
		for generation:int in _ready_seen.keys():
			if not generations.has(generation):_ready_seen.erase(generation)
	if heads.is_empty():
		_clear_drain()
		_burst_path="";_burst_count=0;_near_service_count=0;_near_priority=2147483647
		return {}
	# Heads arrive in the existing exact priority/distance order. Do not admit
	# an unready closure or weaken navigation/transfer priority to improve art.
	var nearest:Dictionary=heads[0]
	var priority:int=priorities.get(nearest.record.uuid,2147483647)
	if priority<0:
		_burst_path="";_burst_count=0;_near_service_count=0;_near_priority=2147483647
		return nearest
	if drain_mode:
		return _choose_drain(heads,ranks,jobs,remaining)
	_clear_drain()
	var priority_turns:bool=white_priority_turns_enabled and controls.white_materials and controls.discard_map_textures
	if not priority_turns or priority!=_near_priority:_near_service_count=0
	_near_priority=priority
	var selected:Dictionary={}
	var oldest:=9223372036854775807
	if priority_turns and _near_service_count>=MAX_BURST:
		# Already prepared distant owners hold the same bounded producer slots.
		# One turn after four nearby units lets them finish and release those slots,
		# even while a nearby shared model has many more instances. Safety heads
		# returned above; no dependency or admission check is bypassed here.
		for item:Dictionary in heads:
			if int(priorities.get(item.record.uuid,2147483647))<=priority:continue
			var turn:int=_served.get(item.path,0)
			if selected.is_empty() or turn<oldest or (turn==oldest and int(ranks[item.record.uuid])<int(ranks[selected.record.uuid])):
				selected=item;oldest=turn
		if not selected.is_empty():
			_serial+=1;_served[selected.path]=_serial;_near_service_count=0
			# Preserve the nearby burst; the distant path receives only this unit.
			return selected
	var building_seen:=false
	var material_order:=preserve_building_material_order()
	for item:Dictionary in heads:
		if int(priorities.get(item.record.uuid,2147483647))!=priority:continue
		# Keep the original ready-building order: interleaving distant house
		# materials can concentrate texture uploads into a worse single hitch.
		# Independent props/vegetation still get bounded turns between its units.
		if material_order and str(item.get("group_id","")).begins_with("building:"):
			if building_seen:continue
			building_seen=true
		if item.path==_burst_path and _burst_count<MAX_BURST:
			_burst_count+=1
			if priority_turns:_near_service_count=mini(MAX_BURST,_near_service_count+1)
			return item
		var turn:int=_served.get(item.path,0)
		if selected.is_empty() or turn<oldest or (turn==oldest and int(ranks[item.record.uuid])<int(ranks[selected.record.uuid])):
			selected=item;oldest=turn
	_serial+=1;_served[selected.path]=_serial
	_burst_path=selected.path;_burst_count=1
	if priority_turns:_near_service_count=mini(MAX_BURST,_near_service_count+1)
	return selected

func _clear_drain()->void:
	_drain_path="";_drain_generation=0;_drain_burst=0
	_drain_protected=false;_ready_seen.clear();_ready_epoch=0

func needs_drain_target(heads:Array,jobs:Dictionary)->bool:
	var current:=false;var new_ready:=false
	for item:Dictionary in heads:
		var generation:int=jobs[item.path].token.get_instance_id()
		if item.path==_drain_path and generation==_drain_generation:current=true
		if int(_ready_seen.get(generation,-1))!=_ready_epoch:new_ready=true
	return not current or (new_ready and not _drain_protected)

func _choose_drain(heads:Array,ranks:Dictionary,jobs:Dictionary,remaining:Dictionary)->Dictionary:
	# A completed result retains a whole producer slot until its final member
	# commits. Equal round-robin bursts can prepare every atomic owner almost
	# completely before ANY slot becomes available. Finish one ready owner first.
	var target:Dictionary={}
	for item:Dictionary in heads:
		if item.path==_drain_path and jobs[item.path].token.get_instance_id()==_drain_generation:
			target=item;break
	var previous_path:=_drain_path
	var new_shorter:=false;var ready_changed:=false;var aged_peer:=false
	if not target.is_empty() and not _drain_protected:
		for item:Dictionary in heads:
			var generation:int=jobs[item.path].token.get_instance_id()
			if generation!=_drain_generation and int(_drain_age.get(generation,0))>=MAX_DRAIN_BYPASSES:aged_peer=true
			if int(_ready_seen.get(generation,-1))==_ready_epoch:continue
			ready_changed=true
			if int(remaining.get(item.path,2147483647))<int(remaining.get(target.path,2147483647)):new_shorter=true
		# A newly ready one-member result need not wait for a large sticky owner.
		# Only a real ready-set change can trigger this reconsideration. An aged
		# target is protected so an endless stream of short arrivals cannot starve it.
		if ready_changed and (new_shorter or aged_peer):target={}
	if target.is_empty():
		_clear_drain()
		var oldest:=-1;var shortest:=2147483647
		for item:Dictionary in heads:
			var generation:int=jobs[item.path].token.get_instance_id()
			var age:int=_drain_age.get(generation,0)
			var cost:int=remaining.get(item.path,2147483647)
			# New small results cannot indefinitely overtake an existing ready
			# owner. Age counts distinct drain choices, not frame time or UUIDs.
			if age>=MAX_DRAIN_BYPASSES:
				if age>oldest:target=item;oldest=age
			elif oldest<MAX_DRAIN_BYPASSES and (target.is_empty() or cost<shortest or (cost==shortest and int(ranks[item.record.uuid])<int(ranks[target.record.uuid]))):
				target=item;shortest=cost
		_drain_path=target.path;_drain_generation=jobs[target.path].token.get_instance_id()
		_drain_protected=int(_drain_age.get(_drain_generation,0))>=MAX_DRAIN_BYPASSES
		var trace=preload("res://scripts/world3d/completed_job_trace.gd")
		if trace.enabled:trace.record(_drain_path,_drain_generation,"drain_target",{"reason":"aged" if _drain_protected else ("new_ready_shorter" if new_shorter else "shortest"),"previous_path":previous_path,"remaining_members":int(remaining.get(_drain_path,-1)),"ready_heads":heads.size()})
		for item:Dictionary in heads:
			var generation:int=jobs[item.path].token.get_instance_id()
			_drain_age[generation]=0 if generation==_drain_generation else int(_drain_age.get(generation,0))+1
	_ready_epoch+=1
	for item:Dictionary in heads:_ready_seen[jobs[item.path].token.get_instance_id()]=_ready_epoch
	var selected:Dictionary=target
	if _drain_burst>=DRAIN_BURST:
		# A large target still gives other ready owners bounded service. This
		# does not reset its target, and an unready target never enters heads.
		var oldest:=9223372036854775807
		for item:Dictionary in heads:
			if item.path==target.path:continue
			var turn:int=_served.get(item.path,0)
			if turn<oldest:selected=item;oldest=turn
		_drain_burst=0
	else:_drain_burst+=1
	_serial+=1;_served[selected.path]=_serial;drain_selected=true
	return selected
