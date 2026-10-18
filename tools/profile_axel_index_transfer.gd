extends "res://tools/profile_axel_game_pipeline.gd"
const Index=preload("res://scripts/world3d/stream_index.gd")
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
var benchmarked:=false
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_index_transfer.gd"]=FileAccess.get_sha256("res://tools/profile_axel_index_transfer.gd")
	return result
func finish(code:int)->void:
	if not benchmarked and code==0 and is_instance_valid(mesh_map):
		benchmarked=true
		await benchmark()
	await super.finish(code)
func projection(values:Array)->Array:
	var result:Array=[]
	for value:Dictionary in values:
		var spec:Dictionary=value.duplicate()
		for field:String in Preparation.DERIVED_FIELDS:spec.erase(field)
		result.append(spec)
	return result
func benchmark()->void:
	var source:Array=[];var surroundings:Array=[]
	for spec:Dictionary in mesh_map.get_meta("stream_library",[]):
		if str(spec.uuid).get_slice("__",0)=="obj_1033":source.append(spec)
		else:surroundings.append(spec)
	check(source.size()==2151,"fixed input is the actual 2151-part axel building")
	if source.size()!=2151:return
	report.index_transfer_benchmark={"specs":source.size(),"surroundings":surroundings.size(),"note":"same loaded immutable mesh owners; ABBA order; preparation and fresh baseline build excluded from atomic append timing","trials":[]}
	for turn:int in 16:
		var owned:bool=turn%4 in [1,2]
		var data:=Index.build(projection(surroundings));var incoming:=projection(source)
		var cursor:=Preparation.new()
		if owned:cursor.begin_owned(incoming)
		else:cursor.begin(incoming)
		while not cursor.advance(2000):await process_frame
		var started:=Time.get_ticks_usec();var appended:=Index.append(data,incoming,cursor);var elapsed:=Time.get_ticks_usec()-started
		var row:Dictionary={"owned":owned,"append_us":elapsed}
		report.index_transfer_benchmark.trials.append(row)
		check(appended.ok,"fixed input transfer succeeds: %d"%turn)
		cursor.dispose()
		if turn<2:
			var rebuilt:=Index.build(projection(surroundings+incoming))
			for key:String in data:
				if key not in ["stream_collision_revision","stream_collision_candidate_cache"]:check(data[key]==rebuilt[key],"fixed actual source preserves exact index "+key)
		var library:Array=data.stream_by_id.values();var ids:Array=[]
		for spec:Dictionary in incoming:ids.append(spec.uuid)
		Index.reuse_owned_retirement_plan_enabled=owned
		started=Time.get_ticks_usec();var retired:=Index.retire_owned(data,library,ids);row.retire_us=Time.get_ticks_usec()-started
		Index.reuse_owned_retirement_plan_enabled=true
		check(retired.ok and retired.removed==2151 and library.size()==surroundings.size(),"fixed input complete retirement succeeds: %d"%turn)
		if turn<2:
			var rebuilt:=Index.build(projection(library))
			for key:String in data:
				if key not in ["stream_collision_revision","stream_collision_candidate_cache"]:check(data[key]==rebuilt[key],"fixed actual retirement preserves exact index "+key)
		data={};incoming=[]
		await process_frame
	source=[];surroundings=[]
