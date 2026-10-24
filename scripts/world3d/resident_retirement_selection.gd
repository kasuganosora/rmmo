extends RefCounted
## Private CPU projections of an immutable resident selection. The synchronous
## owner holds all source resources and joins every child before any commit.
const EMPTY_RECORD:Dictionary={}
const GAMEPLAY_FIELDS:Array=["event","event_template","hostile","ally","seat"]
const GAMEPLAY_KINDS:Array=["npc","gather","event","teleport","warp"]
const MIN_ROWS:=2048
const MAX_WORKERS:=8
static var enabled:=true
static func failure(reason:String)->Dictionary:
	return {"ok":false,"error":reason,"removed":0,"removed_ids":[],"removed_specs":[]}
static func rows(by_id:Dictionary,ground_order:Dictionary,ids:Array,metadata:bool)->Dictionary:
	var selected:Dictionary={};var prefixes:Dictionary={};var groups:Dictionary={};var ground:Dictionary={}
	var removed:Array=[]
	var fixture_states:Dictionary={};var digests:Dictionary={};var model_paths:Dictionary={}
	for id:Variant in ids:
		if not id is String or selected.has(id) or not by_id.has(id):return failure("invalid complete retirement identity")
		var spec:Dictionary=by_id[id]
		if spec.get("uuid")!=id:return failure("invalid resident identity")
		if spec.get("native_visual",false):return failure("active native owner")
		var extra:Dictionary=spec.get("extras",EMPTY_RECORD);var record:Dictionary=spec.get("ground_batch_record",EMPTY_RECORD)
		for field:String in GAMEPLAY_FIELDS:
			if extra.has(field) or record.has(field):return failure("active gameplay owner")
		if extra.get("kind","") in GAMEPLAY_KINDS:return failure("active gameplay owner")
		if metadata:
			# The selected row and its live extras are already in hand. Capture
			# scalar cleanup data here; no extra native-residency UUID traversal.
			if extra.has("fixture"):
				var open_state:Variant=extra.fixture.get("open")
				if open_state is float or open_state is int:fixture_states[record.get("uuid",id.get_slice("__",0))]=float(open_state)
			if record.get("house_prefab",EMPTY_RECORD).get("sha256") is String:digests[record.house_prefab.sha256]=true
			if record.get("asset_path") is String:model_paths[record.asset_path]=true
		selected[id]=true;removed.append(spec)
		var prefix:String=id.get_slice("__",0);prefixes[prefix]=int(prefixes.get(prefix,0))+1
		if spec.has("render_building"):
			var group:String=spec.render_building
			groups[group]=int(groups.get(group,0))+1
		if ground_order.has(id):
			ground[id]=true
	return {"ok":true,"selected":selected,"prefixes":prefixes,"groups":groups,"ground_ids":ground,"removed_specs":removed,"cleanup":{"fixtures":fixture_states,"digests":digests,"model_paths":model_paths}}

static func prepare(by_id:Dictionary,ground_order:Dictionary,ids:Array,metadata:bool,workers:int=MAX_WORKERS,child_starter:Callable=Callable())->Dictionary:
	workers=clampi(workers,1,mini(MAX_WORKERS,maxi(1,ids.size())))
	if workers==1:return rows(by_id,ground_order,ids,metadata)
	var packets:Array=[];packets.resize(workers)
	var stride:=ceili(float(ids.size())/workers)
	for i:int in range(1,workers):
		var thread:=Thread.new();var slice:=ids.slice(i*stride,mini((i+1)*stride,ids.size()))
		var task:=rows.bind(by_id,ground_order,slice,metadata)
		var error:int=child_starter.call(thread,task) if child_starter.is_valid() else thread.start(task)
		if error==OK:packets[i]=thread
		else:packets[i]=task.call()
	packets[0]=rows(by_id,ground_order,ids.slice(0,stride),metadata)
	# Do not return on an early failure until ALL sibling readers have stopped.
	for i:int in packets.size():
		if packets[i] is Thread:packets[i]=packets[i].wait_to_finish()
	var result:={"ok":true,"selected":{},"prefixes":{},"groups":{},"ground_ids":{},"removed_specs":[],"cleanup":{"fixtures":{},"digests":{},"model_paths":{}}}
	for packet:Dictionary in packets:
		if not packet.ok:return packet
		result.selected.merge(packet.selected);result.ground_ids.merge(packet.ground_ids)
		result.removed_specs.append_array(packet.removed_specs)
		for field:String in ["prefixes","groups"]:
			for key:String in packet[field]:result[field][key]=int(result[field].get(key,0))+int(packet[field][key])
		for field:String in ["fixtures","digests","model_paths"]:result.cleanup[field].merge(packet.cleanup[field],true)
	if result.selected.size()!=ids.size():return failure("invalid complete retirement identity")
	return result
