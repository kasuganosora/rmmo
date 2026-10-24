extends "res://tools/test_stream_index_append.gd"
## Shared-support appends: dependency order, owner identity and retire/return.
## CPU-only fixture. The pressure cases report measurements, never assert time.
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/"

func equivalent(data:Dictionary,library:Array,label:String)->void:
	var rebuilt:=Index.build(library.duplicate(true))
	check(public_index(data)==public_index(rebuilt) and data.stream_append_state==rebuilt.stream_append_state,label+" equals a complete rebuild")

func owners_match(data:Dictionary,support:Dictionary)->bool:
	var ids:Array=data.stream_append_state.dependents[support.uuid]
	if ids.size()!=support.render_dependents.size():return false
	for at:int in ids.size():
		if not is_same(support.render_dependents[at],data.stream_building_groups[ids[at]][0].render_bounds):return false
	return true

func cursor_for(values:Array,mode:String)->RefCounted:
	if mode=="direct":return null
	var cursor:=Preparation.new()
	match mode:
		"copied":cursor.begin(values)
		"owned":cursor.begin_owned(values)
		"runtime_owned":cursor.begin_runtime_owned(values)
	while not cursor.advance(100):pass
	check(cursor.error.is_empty(),mode+" preparation completes")
	return cursor

func semantic_case(mode:String)->void:
	var near:=ground("ground_near",Vector2i(-1,0),Vector2i(1,0))
	var side:=ground("ground_side",Vector2i(1,0),Vector2i(3,0))
	var far:=ground("ground_far",Vector2i(20,0),Vector2i(21,0))
	var first:=house("first_wall","z_first",Vector2i.ZERO)
	var equal:=house("equal_wall","a_second",Vector2i.ZERO)
	var library:Array=[near,side,far,first,equal]
	var data:=Index.build(library)
	var old_ids:Array=data.stream_append_state.dependents[near.uuid]
	var old_envelopes:Array=near.render_dependents
	var first_bound:Dictionary=first.render_bounds
	var equal_bound:Dictionary=equal.render_bounds
	var far_envelopes:Array=far.render_dependents
	check(first_bound==equal_bound and not is_same(first_bound,equal_bound),mode+" starts with distinct equal-valued group owners")
	# Interleave two groups so the append must preserve first appearance order,
	# not UUID order, lexical group order or per-member arrival order.
	var added:Array=[house("z_wall","z_new",Vector2i(1,0)),house("a_wall","a_new",Vector2i.ZERO),house("z_roof","z_new",Vector2i(1,0),1),house("distant","distant_new",Vector2i(40,0))]
	var cursor:RefCounted=cursor_for(added,mode)
	var result:=Index.append(data,added,cursor)
	check(result.ok,mode+" appends complete new groups")
	if cursor!=null:cursor.dispose()
	library.append_array(added)
	check(is_same(old_ids,data.stream_append_state.dependents[near.uuid]) and is_same(old_envelopes,near.render_dependents),mode+" keeps both shared support array identities")
	check(old_ids==["z_first","a_second","z_new","a_new"],mode+" preserves old prefix plus new first-appearance order")
	check(is_same(near.render_dependents[0],first_bound) and is_same(near.render_dependents[1],equal_bound),mode+" preserves equal-valued old owner identities")
	check(is_same(far_envelopes,far.render_dependents) and far_envelopes.is_empty(),mode+" leaves untouched support arrays unchanged")
	check(owners_match(data,near) and owners_match(data,side),mode+" aligns IDs and original group-bound owners")
	var invalidated:Array=[]
	for value:Dictionary in result.affected_existing_specs:invalidated.append(value.uuid)
	check(invalidated==["ground_near","ground_side"],mode+" still invalidates only touched existing supports")
	equivalent(data,library,mode+" append-only")
	# New ground must rebind old groups and their existing support envelopes.
	var patch:=ground("later_ground",Vector2i(0,0),Vector2i(8,0))
	var mixed:Array=[patch,house("mixed_wall","mixed_group",Vector2i(4,0))]
	result=Index.append(data,mixed);library.append_array(mixed)
	check(result.ok and first.render_bounds.chunk_max==Vector2i(8,0) and is_same(first.render_bounds,first_bound),mode+" later ground expands existing owner in place")
	check(is_same(old_ids,data.stream_append_state.dependents[near.uuid]) and is_same(old_envelopes,near.render_dependents) and owners_match(data,near) and owners_match(data,side) and owners_match(data,patch),mode+" new-ground fallback keeps dependency array identities and order")
	equivalent(data,library,mode+" new ground rebind")
	# Removing a middle group preserves the surviving parallel arrays. Return
	# under the same IDs must append at the new end after rank compaction.
	var retired:=Index.retire_owned(data,library,["z_roof","z_wall"])
	check(retired.ok,mode+" complete building unload succeeds")
	check(is_same(old_ids,data.stream_append_state.dependents[near.uuid]) and is_same(old_envelopes,near.render_dependents) and not old_ids.has("z_new") and owners_match(data,near),mode+" unload removes only retired edges and preserves owners")
	equivalent(data,library,mode+" unload")
	var returned:Array=[added[0],added[2]]
	result=Index.append(data,returned);library.append_array(returned)
	check(result.ok and old_ids[-1]=="z_new" and owners_match(data,near) and owners_match(data,side) and owners_match(data,patch),mode+" returned group appends after compacted surviving ranks")
	equivalent(data,library,mode+" return")

func non_ground_case()->void:
	var floor:=ground("ground",Vector2i.ZERO,Vector2i.ONE)
	var library:Array=[floor,house("existing","existing",Vector2i.ZERO)]
	var data:=Index.build(library)
	var ids:Array=data.stream_append_state.dependents.ground
	var envelopes:Array=floor.render_dependents
	var added:Array=[spec("road",Vector2i.ZERO,Vector2i.ONE,{"road_mesh":{}}),spec("prop",Vector2i.ZERO,Vector2i.ZERO),house("new","new",Vector2i.ZERO)]
	check(Index.append(data,added).ok,"non-ground landscape can accompany new complete building")
	library.append_array(added)
	check(is_same(ids,data.stream_append_state.dependents.ground) and is_same(envelopes,floor.render_dependents) and ids==["existing","new"] and owners_match(data,floor),"road/prop append retains support identity and exact new group edges")
	equivalent(data,library,"road/prop append")

func percentile(values:Array,ratio:float)->int:
	return int(values[clampi(int(ceil(values.size()*ratio))-1,0,values.size()-1)]) if not values.is_empty() else 0

func pressure_equivalent(data:Dictionary,library:Array)->bool:
	# Copy authored rows only. A deep copy would expand the shared ground's
	# N reverse edges through every one of its N dependent rows in the oracle.
	var authored:Array=[]
	for value:Dictionary in library:
		var copy:Dictionary=value.duplicate()
		for field:String in Preparation.DERIVED_FIELDS:copy.erase(field)
		authored.append(copy)
	var rebuilt:=Index.build(authored)
	if data.stream_index!=rebuilt.stream_index or data.stream_known!=rebuilt.stream_known or data.stream_append_state!=rebuilt.stream_append_state:return false
	if data.stream_building_count!=rebuilt.stream_building_count:return false
	for id:String in data.stream_by_id:
		var actual:Dictionary=data.stream_by_id[id];var expected:Dictionary=rebuilt.stream_by_id[id]
		if actual.get("render_bounds")!=expected.get("render_bounds") or actual.get("render_building")!=expected.get("render_building"):return false
		if actual.get("render_dependents",[])!=expected.get("render_dependents",[]):return false
		var actual_ids:Array=[];var expected_ids:Array=[]
		for value:Dictionary in actual.get("render_supports",[]):actual_ids.append(value.uuid)
		for value:Dictionary in expected.get("render_supports",[]):expected_ids.append(value.uuid)
		if actual_ids!=expected_ids:return false
	return true

func pressure(count:int)->Dictionary:
	var shared_mesh:=BoxMesh.new();shared_mesh.size=Vector3(2,2,2)
	var floor:=ground("pressure_ground",Vector2i.ZERO,Vector2i.ZERO)
	var library:Array=[floor];var data:=Index.build(library)
	var incoming:Array=[]
	for at:int in count:
		var value:=house("pressure_%d"%at,"building_%d"%at,Vector2i.ZERO);value.mesh=shared_mesh
		incoming.append([value])
	var durations:Array=[];var ok:=true
	Trace.start()
	var began:=Time.get_ticks_usec()
	for values:Array in incoming:
		var started:=Time.get_ticks_usec()
		var result:=Index.append(data,values)
		durations.append(Time.get_ticks_usec()-started)
		ok=ok and result.ok;library.append_array(values)
	var elapsed:=Time.get_ticks_usec()-began
	var traced:=Trace.stop();durations.sort()
	check(ok and data.stream_append_state.dependents.pressure_ground.size()==count and owners_match(data,floor),"pressure %d preserves every group edge and owner"%count)
	check(pressure_equivalent(data,library),"pressure %d equals a complete rebuild without expanding shared owners"%count)
	var phases:Dictionary={}
	for stat:Dictionary in traced.stats:phases[stat.label]={"count":stat.count,"total_us":stat.total_us,"max_us":stat.max_us}
	return {"groups":count,"append_calls":count,"total_us":elapsed,"append_p50_us":percentile(durations,.5),"append_p95_us":percentile(durations,.95),"append_max_us":durations[-1],"dependency_edges_required":count,"old_prefix_filter_rows_analytic":count*(count-1)/2,"old_rebound_rows_analytic":count*(count+1)/2,"phases":phases}

func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument=="--old":Index.append_dependency_delta_enabled=false
	for mode:String in ["direct","copied","owned","runtime_owned"]:semantic_case(mode)
	non_ground_case()
	var label:="candidate"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):label=argument.trim_prefix("--label=").validate_filename()
	var measurements:Array=[]
	for count:int in [256,512,1024,2048]:measurements.append(pressure(count))
	var report:={"label":label,"delta_enabled":Index.append_dependency_delta_enabled,"failures":failures,"source_sha256":FileAccess.get_sha256("res://scripts/world3d/stream_index.gd"),"measurements":measurements,"measurement_scope":"CPU-only index append; geometry, full-build oracle and resource destruction excluded. LoadTrace spans nest; phase totals are not exclusive CPU time. Analytic old work counts describe the known control loops, not measured RSS."}
	DirAccess.make_dir_recursive_absolute(OUT)
	FileAccess.open(OUT+"append_dependents_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAM_APPEND_DEPENDENTS_FINISHED failures=",failures," measurements=",JSON.stringify(measurements))
	quit(1 if failures else 0)
