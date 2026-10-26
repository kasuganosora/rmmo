extends SceneTree
## Read one authored road, keep its arrays immutable, stress bounded concurrent
## native uploads. Deliberately extreme diagnostic; not a game timing result.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Upload=preload("res://scripts/world3d/prepared_cpu_upload.gd")
const Heartbeat=preload("res://tools/frame_wait_heartbeat.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const TARGET="pavement_1e991a89db78392fc875"
class StopToken extends RefCounted:
	var mutex:=Mutex.new()
	var stopped:=false
	var claimed:=0
	var limit:=4096
	func stop()->void:
		mutex.lock();stopped=true;mutex.unlock()
	func take()->bool:
		mutex.lock();var value:=not stopped and claimed<limit
		if value:claimed+=1
		mutex.unlock();return value
var failures:=0
var beat:RefCounted
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
static func make_native(arrays:Array,bulk:bool)->ArrayMesh:
	var mesh:=ArrayMesh.new()
	if bulk:
		var packed:Array=[]
		for surface:Array in arrays:packed.append(RenderingServer.call(&"mesh_prepare_surface_from_arrays",Mesh.PRIMITIVE_TRIANGLES,surface,[],{},0))
		mesh.set("_surfaces",packed)
	else:
		for surface:Array in arrays:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
	return mesh
static func worker(arrays:Array,token:StopToken,gate:Semaphore,bulk:bool)->Dictionary:
	gate.wait()
	var retained:Array=[];var cursor:=0;var calls:=0;var elapsed:=0;var peak:=0
	while token.take():
		var began:=Time.get_ticks_usec();var mesh:=make_native(arrays,bulk)
		var duration:=Time.get_ticks_usec()-began;elapsed+=duration;peak=maxi(peak,duration);calls+=1
		# Only a bounded ring of GPU resources survives; retirement occurs on
		# its producer. Never share a live mutable Mesh across worker threads.
		if retained.size()<16:retained.append(mesh)
		else:retained[cursor]=mesh;cursor=(cursor+1)%16
	return {"calls":calls,"us":elapsed,"max_us":peak,"peak_retained_meshes":retained.size()}
func run()->void:
	var output:="";var count:=60;var selected:=-1;var bulk:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--samples="):count=clampi(arg.trim_prefix("--samples=").to_int(),10,300)
		elif arg.begins_with("--workers="):selected=arg.trim_prefix("--workers=").to_int()
		elif arg=="--bulk":bulk=true
		elif arg.begins_with("--frame-heartbeat-port="):
			beat=Heartbeat.new();check(beat.start(arg.trim_prefix("--frame-heartbeat-port=").to_int())==OK,"diagnostic heartbeat bound")
	if output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name()=="headless" or selected>12 or selected< -1:
		push_error("Require private GPU desktop, new output and 0..12 workers");quit(2);return
	var before:=FileAccess.get_sha256(MAP)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var compact:Array=[]
	for record:Dictionary in document.nodes[0].extras.rmmo_records:
		if record.uuid==TARGET:compact.append(record);break
	var result:=Store.read_records(compact,MAP,"D:/code/rmmo_runtime",null,1,true)
	check(compact.size()==1 and result.get("ok",false),"authored road reference read without modifying map")
	if not result.get("ok",false):quit(1);return
	var record:Dictionary=result.records[0];var arrays:=Road.arrays(record);var original:=var_to_bytes(arrays)
	var box:=Bounds.bounds(arrays);var materials:Array=[];var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for surface:Array in arrays:materials.append(material)
	var counts:Array=[]
	for surface:Array in arrays:counts.append({"vertices":surface[Mesh.ARRAY_VERTEX].size(),"indices":surface[Mesh.ARRAY_INDEX].size() if surface[Mesh.ARRAY_INDEX]!=null else 0})
	check(RenderingServer.has_method(&"mesh_prepare_surface_from_arrays"),"bulk comparison requires CPU-only packing API")
	if failures:quit(1);return
	# Both controls execute the same oracle before timing; validation must not
	# warm only one side of the comparison. The measured workload is unchanged.
	var control:=make_native(arrays,false);var candidate:=make_native(arrays,true)
	check(control.get("_surfaces")==candidate.get("_surfaces") and control.get_aabb()==candidate.get_aabb(),"bulk and per-surface uploads preserve exact native surface bytes and bounds")
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,20,20);camera.look_at(Vector3.ZERO);camera.current=true
	var visual:=MeshInstance3D.new();root.add_child(visual)
	Engine.max_fps=60;root.size=Vector2i(640,480)
	preload("res://scripts/util/display_state.gd").set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	Cpu.profile_enabled=true;Upload.profile_enabled=true
	var cases:Array=[];var origin:=Time.get_ticks_usec()
	for concurrency:int in ([0,3,12,0] if selected<0 else [selected]):
		var token:=StopToken.new();var gate:=Semaphore.new();var threads:Array=[]
		for i:int in concurrency:
			var thread:=Thread.new();thread.start(worker.bind(arrays,token,gate,bulk));threads.append(thread)
		var case_started:=Time.get_ticks_usec();var last_frame:=case_started
		for i:int in concurrency:gate.post()
		var rows:Array=[]
		print("UPLOAD_STRESS_ACTIVE workers=",concurrency)
		var sample_index:=0
		while sample_index<count or (sample_index<300 and threads.any(func(thread:Thread)->bool:return thread.is_alive())):
			var cpu:Mesh=Bounds.make_cpu(arrays,materials,box)
			var alive_before:=threads.filter(func(thread:Thread)->bool:return thread.is_alive()).size()
			if beat!=null:beat.mark(Heartbeat.GEOMETRY_BEGIN,"white_native_reload",origin)
			var began:=Time.get_ticks_usec();var mesh:Mesh=Upload.restore(cpu,TARGET)
			var ended:=Time.get_ticks_usec()
			if beat!=null:beat.mark(Heartbeat.GEOMETRY_END,"white_native_reload",origin)
			rows.append({"at_us":began,"end_us":ended,"elapsed_us":ended-began,"cpu_id":cpu.get_instance_id(),"frame":Engine.get_process_frames(),"workers_alive_before":alive_before,"workers_alive_after":threads.filter(func(thread:Thread)->bool:return thread.is_alive()).size()})
			visual.mesh=mesh
			sample_index+=1
			await process_frame
			var now:=Time.get_ticks_usec();rows[-1].frame_us=now-last_frame;last_frame=now
		token.stop();var retired:=Time.get_ticks_usec()
		while threads.any(func(thread:Thread)->bool:return thread.is_alive()):await process_frame
		var workers:Array=[]
		for thread:Thread in threads:workers.append(thread.wait_to_finish())
		var completed:=0
		for row:Dictionary in workers:completed+=int(row.calls)
		check(completed==4096 if concurrency>0 else completed==0,"fixed background upload workload completes with %d workers"%concurrency)
		cases.append({"workers":concurrency,"bulk":bulk,"rows":rows,"worker_work":workers,"drain_us":Time.get_ticks_usec()-retired,"total_us":Time.get_ticks_usec()-case_started})
	check(original==var_to_bytes(arrays),"concurrent uploads leave authored geometry arrays unchanged")
	check(before==FileAccess.get_sha256(MAP),"map bytes unchanged")
	if beat!=null:beat.stop(origin)
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"scope":"Bounded artificial native-upload contention; same authored geometry, shared unshaded material. Not full map performance or authored-material validation.","surfaces":counts,"cases":cases,"cpu":Cpu.profile_rows,"uploads":Upload.profile_rows,"heartbeat":beat.profile if beat!=null else {}},"\t"));file.close()
	visual.free();camera.free();await process_frame
	print("UPLOAD_STRESS_DONE failures=",failures);quit(1 if failures else 0)
