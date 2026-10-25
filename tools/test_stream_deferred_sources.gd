extends SceneTree
## Repeated publications must not revisit already resolved resident meshes.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
class QuietBatch extends Batch:
	func request_residency_sync(_nodes:Array,_excluded:Array=[],_immutable_append:bool=false)->void:pass
class CountedCpu extends Cpu:
	var uploads:=0
	func restore()->Mesh:
		uploads+=1
		return BoxMesh.new()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func source(id:String,cpu:Cpu)->Dictionary:
	return {"uuid":id,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"transform":Transform3D.IDENTITY,"mesh":cpu,"material_override":null,"surface_overrides":[],"extras":{"rmmo_collision":"none"},"ground_batch_record":{"kind":"box","surface_id":"block"}}
func refresh(map:Node3D)->void:
	map.set_meta("stream_children",map.get_child_count(true))
	map.set_meta("stream_target",Vector2i.ZERO)
	map.remove_meta("stream_chunk")
	map.set_meta("stream_batch_revision",-1)
	Stream.sync(map,map,Vector3.ZERO,Stream.FRAME_BUDGET)
func run()->void:
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[]);map.set_meta("defer_source_upload",true)
	var batch:=QuietBatch.new();batch.name="GroundRenderBatches";map.add_child(batch);batch.set_process(false)
	var meshes:Dictionary={};map.set_meta("stream_meshes",meshes)
	for i:int in 4000:
		var visual:=MeshInstance3D.new();visual.name="resolved%d"%i;visual.set_meta("stream_instance",true);map.add_child(visual);meshes[str(visual.name)]=visual
	var trials:Array=[]
	for trial:int in 4:
		var started:=Time.get_ticks_usec()
		for publication:int in 100:refresh(map)
		trials.append(Time.get_ticks_usec()-started)
	check(meshes.size()==4000,"repeated empty publications preserve all resolved residents")
	var cpu:=CountedCpu.new();var row:=source("fallback",cpu)
	var near:=Stream._ring_at(Vector2i.ZERO,1);var bodies:Dictionary={}
	Stream._apply(map,map,row,near,near,meshes,bodies)
	check(meshes.fallback.has_meta("deferred_gpu") and cpu.uploads==0,"new eligible source starts without a standalone GPU upload")
	refresh(map)
	check(cpu.uploads==1 and not meshes.fallback.has_meta("deferred_gpu"),"unbatched source uploads once and clears its pending marker")
	refresh(map)
	check(cpu.uploads==1,"another publication never reuploads a resolved source")
	check(not map.has_meta("deferred_gpu_sources") and not map.has_meta("deferred_gpu_cursor"),"completed obligations release their node registry and cursor")
	var held:=CountedCpu.new();var held_row:=source("held",held)
	Stream._apply(map,map,held_row,near,near,meshes,bodies)
	batch._preparation={"waiting":true}
	check(not Stream._finish_loading_sources(map,batch,Time.get_ticks_usec()+100000) and held.uploads==0,"covered loading waits for batch membership before fallback")
	batch._preparation={};batch._member_groups.held="prepared_group"
	check(Stream._finish_loading_sources(map,batch,0) and held.uploads==0 and not meshes.held.has_meta("deferred_gpu"),"confirmed group member avoids a standalone upload")
	batch._member_groups.erase("held")
	var departed:=CountedCpu.new();var departed_row:=source("returned",departed)
	Stream._apply(map,map,departed_row,near,near,meshes,bodies)
	var away:=Stream._ring_at(Vector2i(100,100),1)
	Stream._apply(map,map,departed_row,away,away,meshes,bodies)
	check(departed.uploads==0 and not meshes.has("returned"),"departure can free an unresolved source without uploading it")
	var returned:=CountedCpu.new();var returned_row:=source("returned",returned)
	Stream._apply(map,map,returned_row,near,near,meshes,bodies)
	check(Stream._finish_loading_sources(map,batch,0) and departed.uploads==0 and returned.uploads==1,"return with the same UUID skips the freed node and resolves the new instance")
	var first:=CountedCpu.new();var second:=CountedCpu.new();var appended:=CountedCpu.new()
	Stream._apply(map,map,source("slice_first",first),near,near,meshes,bodies)
	Stream._apply(map,map,source("slice_second",second),near,near,meshes,bodies)
	check(not Stream._finish_loading_sources(map,batch,Time.get_ticks_usec()-1) and first.uploads==1 and second.uploads==0,"an expired deadline advances one obligation and preserves the tail")
	Stream._apply(map,map,source("slice_appended",appended),near,near,meshes,bodies)
	check(Stream._finish_loading_sources(map,batch,0) and first.uploads==1 and second.uploads==1 and appended.uploads==1,"a later publication extends the queue without revisiting its finished prefix")
	var interrupted:=CountedCpu.new()
	Stream._apply(map,map,source("interrupted",interrupted),near,near,meshes,bodies)
	batch._preparation={"waiting":true}
	map.set_meta("stream_children",map.get_child_count(true));map.set_meta("stream_target",Vector2i.ZERO);map.remove_meta("stream_chunk")
	Stream.sync(map,map,Vector3.ZERO,Stream.FRAME_BUDGET)
	check(interrupted.uploads==1 and not map.has_meta("deferred_gpu_sources"),"switching to interactive loading drains pending fallback even without a batch revision change")
	batch._preparation={}
	print("STREAM_DEFERRED_SOURCES ",JSON.stringify({"resident_count":4000,"publications_per_trial":100,"trials_us":trials,"failures":failures}))
	map.free();await process_frame
	quit(1 if failures else 0)
