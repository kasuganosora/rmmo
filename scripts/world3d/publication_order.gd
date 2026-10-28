extends RefCounted
## Bound service bursts between prepared closures without changing resource ownership.
const MAX_BURST:=4
var _serial:=0
var _served:Dictionary={}
var _burst_path:=""
var _burst_count:=0

func choose(heads:Array,priorities:Dictionary,ranks:Dictionary,jobs:Dictionary)->Dictionary:
	for path:String in _served.keys():
		if not jobs.has(path):_served.erase(path)
	if heads.is_empty():
		_burst_path="";_burst_count=0
		return {}
	# Heads arrive in the existing exact priority/distance order. Do not admit
	# an unready closure or weaken navigation/transfer priority to improve art.
	var nearest:Dictionary=heads[0]
	var priority:int=priorities.get(nearest.record.uuid,2147483647)
	if priority<0:
		_burst_path="";_burst_count=0
		return nearest
	var selected:Dictionary={}
	var oldest:=9223372036854775807
	var building_seen:=false
	for item:Dictionary in heads:
		if int(priorities.get(item.record.uuid,2147483647))!=priority:continue
		# Keep the original ready-building order: interleaving distant house
		# materials can concentrate texture uploads into a worse single hitch.
		# Independent props/vegetation still get bounded turns between its units.
		if str(item.get("group_id","")).begins_with("building:"):
			if building_seen:continue
			building_seen=true
		if item.path==_burst_path and _burst_count<MAX_BURST:
			_burst_count+=1
			return item
		var turn:int=_served.get(item.path,0)
		if selected.is_empty() or turn<oldest or (turn==oldest and int(ranks[item.record.uuid])<int(ranks[selected.record.uuid])):
			selected=item;oldest=turn
	_serial+=1;_served[selected.path]=_serial
	_burst_path=selected.path;_burst_count=1
	return selected
