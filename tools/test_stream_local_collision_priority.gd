extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func solid(id:String,position:Vector3,extra:Dictionary={})->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,1,2)
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position),"extras":extra}
func run()->void:
	var done:=solid("done",Vector3.ZERO);var current:=solid("in_progress",Vector3(200,0,0))
	current.prepared_body=StaticBody3D.new()
	var far:=solid("far",Vector3(200,0,0));var near:=solid("awning",Vector3(5,11,0))
	var ground:=solid("support",Vector3(0,-.5,0));ground.ground_batch_record={"terrain_mesh":{}}
	var glass:=solid("noncollision",Vector3.ZERO,{"rmmo_collision":"none"})
	var resident:=solid("resident",Vector3.ZERO);var npc:=solid("npc",Vector3.ZERO,{"ally":true})
	var native:=solid("native_visual",Vector3.ZERO);native.native_visual=true
	var jobs:Array=[done,current,far,near,glass,resident,npc,native,ground];var originals:=jobs.duplicate()
	Stream.prioritize_local_collisions(jobs,1,Vector3.ZERO,{"resident":true})
	check(jobs.map(func(s):return s.uuid)==["done","in_progress","support","awning","far","noncollision","resident","npc","native_visual"],"near support and real solids precede bulk; excluded members retain order")
	check(is_same(jobs[0],done) and is_same(jobs[1],current) and jobs[1].prepared_body==current.prepared_body,"completed prefix and active asynchronous job retain identity")
	check(jobs.size()==originals.size() and originals.all(func(s):return jobs.count(s)==1),"no source removed, duplicated or copied")
	var once:=jobs.duplicate();Stream.prioritize_local_collisions(jobs,1,Vector3.ZERO,{"resident":true})
	check(jobs==once,"stable ordering is idempotent")
	Stream.prioritize_local_collisions(jobs,jobs.size(),Vector3.ZERO,{})
	check(jobs==once,"completed plan is unchanged")
	current.prepared_body.free()
	var doc:=Doc.new();doc.load_immutable_records=true
	var water:={"uuid":"water_fixture","kind":"box","surface_id":"water","position":[300.,3.,0.],"rotation":[0.,0.,0.],"size":[8.,.02,8.],"color":[.13,.27,.31],"collision":"none","channel_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[300.,3.,0.]}}
	var node:MeshInstance3D=doc._mesh(water,false);var spec:=Stream._spec(node);node.free()
	check(not spec.has("ground_batch_record") and spec.extras.rmmo_collision=="none","water remains separate from opaque batching and physics")
	var index:=Index.build([spec]);var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1)}
	check(index.stream_landscape.size()==1 and Stream._draws(spec,draw),"native water is visible at town distance after full indexing")
	check(index.stream_prop_index.is_empty() and index.stream_collision_index.is_empty(),"far water adds no nearby prop or collision demand")
	var pending:=spec.duplicate(true)
	for key in ["render_bounds","render_dependents","render_supports"]:pending.erase(key)
	var appended:=Index.build([]);var result:=Index.append(appended,[pending])
	check(result.ok and appended.stream_landscape.size()==1 and Stream._draws(pending,draw),"incremental native publication preserves water residency")
	check(not Stream._draws(pending,{"low":Vector2i(-100,-100),"high":Vector2i(-98,-98)}),"water still unloads outside town draw distance")
	print("STREAM_LOCAL_COLLISION_AND_WATER failures=",failures);quit(1 if failures else 0)
