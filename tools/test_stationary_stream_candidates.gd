extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Plan=preload("res://scripts/world3d/stream_candidate_plan.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func ids(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append(row.uuid)
	result.sort();return result
func run()->void:
	var map:=Node3D.new();var groups:Dictionary={};var landscape:Array=[]
	for i:int in 3000:
		var row:={"uuid":"row%d"%i,"chunk":Vector2i(i%100,i/100),"chunk_min":Vector2i(i%100,i/100),"chunk_max":Vector2i(i%100,i/100)}
		if i<1000:groups[row.uuid]=[row]
		else:landscape.append(row)
	map.set_meta("stream_building_groups",groups);map.set_meta("stream_landscape",landscape)
	var a:={"uuid":"new_a"};var b:={"uuid":"new_b"};var pending:Array=[a,b,a]
	var began:=Time.get_ticks_usec();var visited:=0;var equal:=true
	for i:int in 24:
		var work:=Plan.new(map,Vector2i.ZERO,Vector2i.ZERO,pending,Stream)
		visited+=work.groups.size()+work.landscape.size()
		while not work.advance(2000):pass
		equal=equal and ids(work.selected.values())==["new_a","new_b"] and is_same(work.selected.new_a,a)
	var elapsed:=Time.get_ticks_usec()-began
	check(equal,"stationary publication selects only pending records with exact owners and deduplication")
	if "--expect-scan" not in OS.get_cmdline_user_args():check(visited==0,"identical residency rings inspect no old buildings or landscape")
	for target:Vector2i in [Vector2i(1,0),Vector2i(-1,2),Vector2i(80,10)]:
		var work:=Plan.new(map,Vector2i.ZERO,target,pending,Stream)
		while not work.advance(2000):pass
		check(ids(work.selected.values())==ids(Stream._changed_candidates(map,Vector2i.ZERO,target,pending)),"actual crossing keeps exact entering/leaving candidates "+str(target))
	map.free();print("STATIONARY_STREAM_CANDIDATES ",JSON.stringify({"us":elapsed,"old_rows":visited,"failures":failures}));quit(1 if failures else 0)
