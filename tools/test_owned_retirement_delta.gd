extends "res://tools/test_stream_index_retire.gd"
const Trace=preload("res://scripts/world3d/load_trace.gd")
func world()->Array:
	var result:Array=[]
	for i:int in 3:
		result.append(spec("ground%d"%i,Vector2i(i*5,0),Vector2i(i*5+4,4),{"kind":"box","surface_id":"ground","size":[160,1,160]}))
	for i:int in 6:
		var cell:=Vector2i((i/2)*5+1,1)
		for part:int in 3:
			var id:="house%d_part%d"%[i,part]
			var building:={"id":"house%d"%i,"floor":part,"part":id,"role":"roof" if part==2 else "wall"}
			result.append(spec(id,cell,cell,{"kind":"box","building":building}))
	result.append(spec("road",Vector2i(0,0),Vector2i(14,0),{"kind":"box","road_mesh":{}}))
	return result
func equivalent(data:Dictionary,library:Array,label:String)->void:
	var rebuilt:=Index.build(library.duplicate(true))
	check(same_contents(data,rebuilt),label+" matches a complete index rebuild")
	for members:Array in data.stream_building_groups.values():
		for support:Dictionary in members[0].render_supports:
			check(support.render_dependents.any(func(bounds):return is_same(bounds,members[0].render_bounds)),label+" retains exact live bounds identity")
func run()->void:
	var library:=world();var data:=Index.build(library)
	var original:Dictionary=data.stream_by_id.duplicate()
	Trace.methods_enabled=true;Trace.method_labels={"method.stream_index.build":true};Trace.start()
	var first:=Index.retire_owned(data,library,["house1_part0","house1_part1","house1_part2"])
	var trace:=Trace.stop()
	check(first.ok,"whole building retires incrementally")
	check(not trace.stats.any(func(row):return row.label=="method.stream_index.build"),"native retirement performs zero full index builds")
	Trace.methods_enabled=false;Trace.method_labels.clear()
	equivalent(data,library,"equal-bounds neighbor removal")
	for id:String in data.stream_by_id:check(is_same(data.stream_by_id[id],original[id]),"surviving source identity "+id)
	var snapshot:=data.duplicate(true);var before:=library.duplicate()
	check(not Index.retire_owned(data,library,["ground0"]).ok and data==snapshot and library==before,"surviving building still prevents support removal without side effects")
	var second:=Index.retire_owned(data,library,["house0_part0","house0_part1","house0_part2","ground0"])
	check(second.ok,"complete building and its last ground support retire together")
	equivalent(data,library,"building plus support removal")
	var removed:Array=[]
	for id:String in ["house0_part0","house0_part1","house0_part2","ground0"]:removed.append(original[id])
	var append:=Index.append(data,removed);library.append_array(removed)
	check(append.ok,"original UUIDs republish after incremental retirement")
	equivalent(data,library,"republished source ranks and support links")
	check(Index.retire_owned(data,library,["road"]).ok,"independent road retires without unrelated dependency changes")
	var combined:Array=["house4_part0","house4_part1","house4_part2","house5_part0","house5_part1","house5_part2","ground2"]
	check(Index.retire_owned(data,library,combined).ok,"two equal-bounds groups and their support retire as one unit")
	equivalent(data,library,"multiple groups and road removal")
	var broken:=data.duplicate(true);var copied:=library.duplicate(true);broken.stream_append_state.erase("group_cells")
	check(not Index.retire_owned(broken,copied,["house2_part0","house2_part1","house2_part2"]).ok,"malformed append bookkeeping fails before incremental mutation")
	print("OWNED_RETIREMENT_DELTA checks=",checks," failures=",failures);quit(1 if failures else 0)
