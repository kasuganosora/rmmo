extends "res://tools/test_owned_retirement_delta.gd"
## Run after applying the adjacent candidate. --legacy-delta keeps the old
## maintenance but expects reduced work, providing an intentional red control.
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
func _initialize()->void:
	# Install before run: a runtime assertion/script error can otherwise return
	# without quit and leave this tiny SceneTree alive until runner timeout.
	create_timer(20.0).timeout.connect(func():push_error("RETIREMENT_DELTA_WORK watchdog timeout");quit(124))
	run.call_deferred()
func world166()->Array:
	var rows:Array=[]
	for i:int in 36:
		var cell:=Vector2i.ZERO if i<4 else Vector2i(30+i,30)
		rows.append(spec("ground%d"%i,cell,cell,{"kind":"box","surface_id":"ground","size":[32,1,32]}))
	for house:int in 4:
		for part:int in 3:
			var id:="house%d__part%d"%[house,part]
			rows.append(spec(id,Vector2i.ZERO,Vector2i.ZERO,{"kind":"box","building":{"id":"house%d"%house,"floor":0,"part":str(part),"role":"wall"}}))
	for kind:String in ["road_mesh","bridge_mesh","fortification","channel_mesh"]:
		rows.append(spec(kind,Vector2i(80,80),Vector2i(80,80),{"kind":"box",kind:{}}))
	rows.append(spec("ordinary",Vector2i(90,90),Vector2i(90,90),{"kind":"asset"}))
	return rows
func fixture166()->Dictionary:
	var rows:=world166();return {"library":rows,"data":Index.build(rows)}
func house_ids(house:int)->Array:
	return ["house%d__part0"%house,"house%d__part1"%house,"house%d__part2"%house]
func comparable166(data:Dictionary)->Dictionary:
	var copied:=data.duplicate(true)
	for field:String in ["stream_collision_revision","stream_collision_candidate_cache"]:copied.erase(field)
	# Older directories intentionally lack only the new optional scalar. It is
	# tested separately; absence must not prevent the original commit behavior.
	for unit:Dictionary in copied.stream_append_state.retirement_units.values():unit.erase("landscape_count")
	return copied
func exact166(f:Dictionary,label:String)->void:
	check(comparable166(f.data)==comparable166(Index.build(f.library.duplicate(true))),label+" matches rebuilt indices, dense ranks and support order")
	for id:String in f.data.stream_append_state.dependents:
		var links:Array=f.data.stream_append_state.dependents[id]
		var envelopes:Array=f.data.stream_by_id[id].render_dependents
		var exact:=links.size()==envelopes.size()
		for i:int in mini(links.size(),envelopes.size()):exact=exact and is_same(envelopes[i],f.data.stream_building_groups[links[i]][0].render_bounds)
		check(exact,label+" keeps exact distinct bounds owners "+id)
func retire166(f:Dictionary,ids:Array,empty_plan:bool=false)->Dictionary:
	var checked:=Index._owned_retire_plan(f.data,f.library,ids,true,null,true)
	check(checked.ok,"real owned preflight accepts complete selection")
	if not checked.ok:return checked
	var before:Array=f.library.duplicate()
	var result:=Index._commit_owned_retire(f.data,f.library,ids,{} if empty_plan else checked)
	check(result.ok and result.removed==ids.size(),"real commit removes the complete selected membership")
	var survivors:Array=[]
	for row:Dictionary in before:
		if row.uuid not in ids:survivors.append(row)
	check(f.library==survivors,"stable library order is exact")
	for i:int in survivors.size():check(is_same(f.library[i],survivors[i]),"surviving source owner is unchanged")
	return result
func return166(f:Dictionary,removed:Array,label:String)->void:
	check(Index.append(f.data,removed).ok,label+" returns through real append")
	f.library.append_array(removed);exact166(f,label)
func run()->void:
	var legacy:=OS.get_cmdline_user_args().has("--legacy-delta")
	Index.retirement_delta_reuse_enabled=not legacy
	Index.retirement_delta_work_probe_enabled=true;Index.retirement_delta_work_probe.clear()
	var f:=fixture166()
	var a:Dictionary=f.data.stream_building_groups.house0[0].render_bounds
	var b:Dictionary=f.data.stream_building_groups.house1[0].render_bounds
	check(a==b and not is_same(a,b),"fixture has equal-valued bounds with distinct mutable owners")
	var borrowed:Array=f.data.stream_by_id.ground0.render_dependents
	var removed:Array=[]
	for id:String in house_ids(1):removed.append(f.data.stream_by_id[id])
	retire166(f,house_ids(1));var work:=Index.retirement_delta_work_probe.duplicate()
	check(is_same(borrowed,f.data.stream_by_id.ground0.render_dependents),"parallel compaction preserves borrowed dependent Array identity")
	check(int(work.get("ground_rank_rows",0))==0,"unmodified ground ranks require zero rows")
	check(int(work.get("landscape_rows",0))==0,"building-only retirement requires zero landscape rows")
	check(int(work.get("dependency_rebind_rows",0))==0 and int(work.get("dependency_scan_rows",0))>0,"support IDs and exact bounds compact in one pass without rebuilding survivors")
	exact166(f,"middle equal-bounds building retirement")
	return166(f,removed,"same building UUID return")
	var mixed:Array=house_ids(2)+["road_mesh","bridge_mesh","fortification","channel_mesh"]
	removed=[]
	for id:String in mixed:removed.append(f.data.stream_by_id[id])
	Index.retirement_delta_work_probe.clear();retire166(f,mixed)
	check(int(Index.retirement_delta_work_probe.get("landscape_rows",0))>0,"road bridge fortification and channel membership trigger landscape compaction")
	exact166(f,"mixed building and nonground landscapes")
	return166(f,removed,"mixed return preserves dense append ranks")
	var all_ids:Array=f.data.stream_by_id.keys();retire166(f,all_ids)
	check(f.library.is_empty() and f.data.stream_landscape.is_empty() and f.data.stream_append_state.group_order.is_empty() and f.data.stream_append_state.ground_order.is_empty(),"all-delete empties both rank catalogues and landscape")
	exact166(f,"complete unload")
	# Ground-only changes do not require visiting unrelated building ranks.
	f=fixture166();Index.retirement_delta_work_probe.clear();retire166(f,["ground35"])
	check(int(Index.retirement_delta_work_probe.get("group_rank_rows",0))==0,"ground-only retirement skips unrelated group ranks")
	exact166(f,"independent ground removal")
	# Generic/empty plans keep the old rebinding behavior and exact append order.
	f=fixture166();retire166(f,house_ids(0)+["road_mesh"],true);exact166(f,"empty-plan fallback")
	# Missing optional metadata must fall back to the old full landscape scan.
	f=fixture166()
	for unit:Dictionary in f.data.stream_append_state.retirement_units.values():unit.erase("landscape_count")
	Index.retirement_delta_work_probe.clear();retire166(f,house_ids(0))
	check(int(Index.retirement_delta_work_probe.get("landscape_rows",0))>0,"older directory without landscape_count takes the complete fallback")
	exact166(f,"old directory fallback")
	# The scalar describes catalogue membership, not authorization by mutable
	# authored type. Deleting a previously indexed landscape still removes it
	# after its record changes; a former prop never gained a catalogue row.
	f=fixture166();f.data.stream_by_id.road_mesh.ground_batch_record.erase("road_mesh")
	retire166(f,["road_mesh"]);exact166(f,"former landscape still leaves its original catalogue")
	f=fixture166();f.data.stream_by_id.ordinary.ground_batch_record.road_mesh={}
	retire166(f,["ordinary"]);exact166(f,"changed prop type cannot invent an old landscape membership")
	# A malformed parallel-array shape uses the repairing former rebind path.
	f=fixture166();f.data.stream_by_id.ground0.render_dependents.remove_at(0)
	Index.retirement_delta_work_probe.clear();retire166(f,house_ids(1))
	check(int(Index.retirement_delta_work_probe.get("dependency_rebind_rows",0))>0,"parallel length mismatch retains the complete legacy rebind")
	exact166(f,"dependency length fallback")
	# The common member writer also runs for private preparation and append.
	var rows:=world166();var cursor:=Preparation.new();cursor.begin(rows)
	while not cursor.advance(0):pass
	check(cursor.error.is_empty(),"private index preparation succeeds")
	var expected:=Index.build(rows.duplicate(true))
	check(cursor.result.stream_append_state.retirement_units==expected.stream_append_state.retirement_units,"private preparation uses the same landscape membership counts")
	f={"library":[],"data":Index.build([])}
	check(Index.append(f.data,rows,cursor).ok,"real prepared append accepts the private catalogue")
	f.library.append_array(rows);cursor.dispose()
	retire166(f,house_ids(3)+["bridge_mesh"]);exact166(f,"prepared append and retirement")
	Index.retirement_delta_work_probe_enabled=false;Index.retirement_delta_work_probe.clear();Index.retirement_delta_reuse_enabled=true
	print("RETIREMENT_DELTA_WORK ",JSON.stringify({"legacy":legacy,"building_work":work,"checks":checks,"failures":failures,"scope":"CPU-only real index plan/commit/append; external candidate initially unrun"}))
	quit(1 if failures else 0)
