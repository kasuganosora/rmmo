extends "res://tools/test_sliced_native_retirement.gd"
## Prototype: only immutable selected rows, no scene/physics work in children.
static func row_plan(existing:Dictionary,ids:Array,complete_unit:bool=true)->Dictionary:
	var by_id:Dictionary=existing.stream_by_id;var state:Dictionary=existing.stream_append_state
	var selected:Dictionary={};var prefixes:Dictionary={};var groups:Dictionary={};var ground:Dictionary={}
	var removed:Array=[];var shapes:Dictionary={};var fixtures:Dictionary={}
	var fixture_states:Dictionary={};var digests:Dictionary={};var model_paths:Dictionary={}
	for id:Variant in ids:
		if not id is String or selected.has(id) or not by_id.has(id):return Index._retire_failure("invalid complete retirement identity")
		var spec:Dictionary=by_id[id]
		if spec.get("uuid")!=id:return Index._retire_failure("invalid resident identity")
		if not complete_unit:
			var dependency:=Index._retire_dependency(spec,true)
			if not dependency.is_empty():return Index._retire_failure("pinned dependency "+dependency+": "+id)
		if spec.get("native_visual",false):return Index._retire_failure("active native owner")
		var extra:Dictionary=spec.get("extras",Index.EMPTY_RECORD);var record:Dictionary=spec.get("ground_batch_record",Index.EMPTY_RECORD)
		for field:String in Index.RETIRE_GAMEPLAY_FIELDS:
			if extra.has(field) or record.has(field):return Index._retire_failure("active gameplay owner")
		if extra.get("kind","") in Index.RETIRE_GAMEPLAY_KINDS:return Index._retire_failure("active gameplay owner")
		if complete_unit and Index.retirement_metadata_enabled:
			# The selected row and its live extras are already in hand. Capture
			# scalar cleanup data here; no extra native-residency UUID traversal.
			if extra.has("fixture"):
				var open_state:Variant=extra.fixture.get("open")
				if open_state is float or open_state is int:fixture_states[record.get("uuid",id.get_slice("__",0))]=float(open_state)
			if record.get("house_prefab",Index.EMPTY_RECORD).get("sha256") is String:digests[record.house_prefab.sha256]=true
			if record.get("asset_path") is String:model_paths[record.asset_path]=true
		selected[id]=true;removed.append(spec)
		var prefix:String=id.get_slice("__",0);prefixes[prefix]=int(prefixes.get(prefix,0))+1
		if spec.has("render_building"):
			var group:String=spec.render_building
			groups[group]=int(groups.get(group,0))+1
		if state.ground_order.has(id):
			ground[id]=true
	return {"ok":true,"selected":selected,"prefixes":prefixes,"groups":groups,"ground_ids":ground,"removed_specs":removed,"cleanup":{"fixtures":fixture_states,"digests":digests,"model_paths":model_paths}}

static func parallel(existing:Dictionary,ids:Array,workers:int)->Dictionary:
	if workers<=8:return Index.ResidentSelection.prepare(existing.stream_by_id,existing.stream_append_state.ground_order,ids,Index.retirement_metadata_enabled,workers)
	if workers==1:return row_plan(existing,ids)
	var packets:Array=[];packets.resize(workers)
	var stride:=ceili(float(ids.size())/workers)
	for i:int in range(1,workers):
		var thread:=Thread.new();var slice:=ids.slice(i*stride,mini((i+1)*stride,ids.size()))
		if thread.start(row_plan.bind(existing,slice))==OK:packets[i]=thread
		else:packets[i]=row_plan(existing,slice)
	packets[0]=row_plan(existing,ids.slice(0,stride))
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
	if result.selected.size()!=ids.size():return Index._retire_failure("duplicate across partitions")
	return result

func run()->void:
	var f:=setup();var original:=Index._resident_owned_retire_plan(f.data,f.library,f.ids)
	check(original.ok,"whole real index control accepts complete namespace")
	var expected:=row_plan(f.data,f.ids)
	for key:String in expected:
		if key=="ok":continue
		check(expected[key]==original[key],"serial prototype agrees with actual retirement "+key)
	var trials:Array=[]
	for workers:int in [1,4,8,12,12,8,4,1]:
		var began:=Time.get_ticks_usec();var result:Dictionary={}
		for iteration:int in 16:result=parallel(f.data,f.ids,workers)
		var elapsed:=Time.get_ticks_usec()-began
		check(result==expected,"parallel immutable row plan preserves all cleanup and selected ordering")
		trials.append({"workers":workers,"selected_rows":16*f.ids.size(),"elapsed_us":elapsed})
	var invalid:Array=f.ids.duplicate();invalid[1100]=invalid[0]
	check(not parallel(f.data,invalid,3).ok,"duplicate across partitions fails before mutation")
	var failed_start:=Index.ResidentSelection.prepare(f.data.stream_by_id,f.data.stream_append_state.ground_order,f.ids,true,8,func(_thread:Thread,_task:Callable):return ERR_CANT_CREATE)
	check(failed_start==expected,"failed child starts retain exact source order and all selected metadata")
	Index.ResidentSelection.enabled=false
	var legacy_failure:=Index._resident_owned_retire_plan(f.data,f.library,invalid)
	Index.ResidentSelection.enabled=true
	check(Index._resident_owned_retire_plan(f.data,f.library,invalid)==legacy_failure,"invalid parallel projection preserves the original exact rejection")
	var selected:Dictionary=f.data.stream_by_id[f.ids[1500]];selected.extras.event={}
	check(not parallel(f.data,f.ids,3).ok,"live gameplay pin in a child partition remains authoritative")
	selected.extras.erase("event")
	check(f.library.size()==4600 and f.nav._specs.size()==4600,"pure preparation changes no index/navigation/resource owners")
	print("RESIDENT_SELECTION_PARALLEL ",JSON.stringify({"trials":trials,"failures":failures}))
	f.map.free();f={};drain();quit(1 if failures else 0)
