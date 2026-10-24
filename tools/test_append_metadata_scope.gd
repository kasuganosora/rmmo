extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var map:=Node3D.new();root.add_child(map)
	var library:Array=[];map.set_meta("stream_library",library)
	var indexed:=Index.build(library)
	for key:String in indexed:map.set_meta(key,indexed[key])
	var sentinels:Array=[]
	for i:int in 64:
		var owner:={"cursor":i,"items":[1,2,3]};sentinels.append(owner);map.set_meta("stream_observer%d"%i,owner)
	var jobs:Array=[{"uuid":"existing_plan"}];map.set_meta("stream_jobs",jobs);map.set_meta("stream_cursor",1)
	var cpu:=Cpu.capture(BoxMesh.new());var last:Dictionary={};var fields:=0
	var started:=Time.get_ticks_usec()
	for i:int in 512:
		last={"uuid":"obj%d"%i,"mesh":cpu,"transform":Transform3D.IDENTITY,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"extras":{"rmmo_collision":"none"}}
		var result:=Stream.append_specs(map,[last]);fields+=result.data.size()
		if not result.ok:failures+=1
	var elapsed:=Time.get_ticks_usec()-started
	check(library.size()==512 and map.get_meta("stream_building_count")==512 and map.get_meta("stream_collision_revision")==513,"append commits membership and both scalar counters")
	check(is_same(indexed.stream_by_id,map.get_meta("stream_by_id")) and is_same(indexed.stream_by_id[last.uuid],last),"index and spec owners are preserved")
	check(is_same(jobs,map.get_meta("stream_jobs")) and map.get_meta("stream_cursor")==1,"active residency cursor and jobs are untouched")
	var same:=true
	for i:int in 64:same=same and is_same(sentinels[i],map.get_meta("stream_observer%d"%i))
	check(same,"unrelated metadata retains exact ownership")
	var cache:Dictionary=map.get_meta("stream_collision_candidate_cache");cache.test=true
	var rejected:=Stream.append_specs(map,[last])
	check(not rejected.ok and library.size()==512 and map.get_meta("stream_collision_revision")==513 and cache.has("test"),"rejected duplicate has no mutation, including collision cache")
	print("APPEND_METADATA_SCOPE ",JSON.stringify({"us":elapsed,"transferred_fields":fields,"failures":failures}))
	map.free();quit(1 if failures else 0)
