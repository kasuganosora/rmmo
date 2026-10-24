extends SceneTree
## A publication arriving during an unfinished move must retain its delta base.
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
	var cpu:=Cpu.capture(BoxMesh.new());var library:Array=[]
	for i:int in 3000:
		var at:=Vector3(100000+i*4,0,100000)
		if i==3:at=Vector3(-30*Stream.CHUNK_M,0,0)
		if i==4:at=Vector3(35*Stream.CHUNK_M,0,0)
		library.append({"uuid":"unit%d"%i,"mesh":cpu,"transform":Transform3D(Basis.IDENTITY,at),"position":at,"rotation":Vector3.ZERO,"chunk":Stream.chunk_key(at),"chunk_min":Stream.chunk_key(at),"chunk_max":Stream.chunk_key(at),"extras":{"rmmo_collision":"none","building":{"id":"building%d"%i}}})
	map.set_meta("stream_library",library)
	var indexed:=Index.build(library)
	for key:String in indexed:map.set_meta(key,indexed[key])
	var from:=Vector2i(2,0);var to:=Vector2i(3,0)
	map.set_meta("stream_target",from)
	map.set_meta("stream_jobs",[library[0],library[1]])
	map.set_meta("stream_cursor",1)
	map.set_meta("stream_append_pending",[library[2]])
	map.set_meta("stream_children",map.get_child_count(true))
	var began:=Time.get_ticks_usec()
	Stream.sync(map,map,Vector3(to.x*Stream.CHUNK_M,0,0),Stream.FRAME_BUDGET)
	var elapsed:=Time.get_ticks_usec()-began
	var work:Variant=map.get_meta("stream_candidate_work") if map.has_meta("stream_candidate_work") else null
	check(work!=null,"arrival during an unfinished turn uses the bounded delta selector")
	if work!=null:
		check(work.previous==from,"delta starts from the previous in-flight target")
		check(work.unfinished.size()==2 and work.unfinished.has(library[1]) and work.unfinished.has(library[2]) and not work.unfinished.has(library[0]),"new publication and unapplied old tail are each carried once")
		while not work.advance(12000):pass
		check(work.selected.keys().size()==4 and work.selected.has("unit1") and work.selected.has("unit2") and work.selected.has("unit3") and work.selected.has("unit4"),"changed render boundaries and unfinished records survive; unrelated groups do not re-enter")
	var older:=Vector2i(1,0)
	map.set_meta("stream_candidate_work",preload("res://scripts/world3d/stream_candidate_plan.gd").new(map,older,from,[library[2]],Stream))
	map.set_meta("stream_target",from);map.set_meta("stream_jobs",[library[0],library[1]]);map.set_meta("stream_cursor",1)
	map.set_meta("stream_append_pending",[library[5]])
	Stream.sync(map,map,Vector3(to.x*Stream.CHUNK_M,0,0),Stream.FRAME_BUDGET)
	work=map.get_meta("stream_candidate_work") if map.has_meta("stream_candidate_work") else null
	check(work!=null and work.previous==older,"interrupting candidate selection retains its earlier base instead of its unapplied target")
	if work!=null:
		while not work.advance(12000):pass
		check(work.selected.has("unit1") and work.selected.has("unit2") and work.selected.has("unit5"),"interrupted selection carries both outstanding publication generations")
	map.set_meta("stream_source_revision",1);map.set_meta("stream_append_pending",[library[6]])
	Stream.sync(map,map,Vector3(to.x*Stream.CHUNK_M,0,0),Stream.FRAME_BUDGET)
	check(not map.has_meta("stream_candidate_work") and map.get_meta("stream_applied_source_revision")==1,"a real residency-source revision still invalidates the previous delta base")
	print("STREAM_APPEND_TURN ",JSON.stringify({"groups":3000,"sync_us":elapsed,"failures":failures}))
	map.free();await process_frame;quit(1 if failures else 0)
