extends SceneTree
## Stream specs can own CPU geometry while live instances alone own restored
## ArrayMeshes. Permanent map deletion must retire those actual draw owners.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class TrackedMesh extends ArrayMesh:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
var failures:Array=[]
var checks:=0
var baseline:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture(journal:Journal)->Node3D:
	var map:=Node3D.new();var sources:Dictionary={};var specs:Array=[]
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.4,0,-.4),Vector3(.4,0,-.4),Vector3(0,0,.4)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	for i:int in 384:
		var draw:=TrackedMesh.new();draw.journal=journal
		draw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var cpu:=Cpu.remember(draw,[arrays])
		# Source reference is weak: a spec is not ownership of the actual draw.
		specs.append({"uuid":str(i),"mesh":cpu})
		for placement:int in 4:
			var node:=MeshInstance3D.new();node.name="mesh_%d_%d"%[i,placement];node.mesh=draw
			node.position=Vector3(i%24,0,i/24)+Vector3(0,placement*.02,0)
			map.add_child(node);sources[str(node.name)]=node
	map.set_meta("stream_meshes",sources);map.set_meta("stream_library",specs)
	return map
func run()->void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:Node=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var map:=fixture(journal);root.add_child(map)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(12,28,17);camera.look_at(Vector3(12,0,8));camera.current=true
	for i:int in 4:await process_frame
	var live:MeshInstance3D=map.get_meta("stream_meshes").mesh_0_0
	var borrower:Mesh=live.mesh;var weak_map:WeakRef=weakref(map);var weak_node:WeakRef=weakref(live)
	# Temporary detach must not start retirement or mutate source ownership.
	root.remove_child(map);root.add_child(map)
	check(service.pending.is_empty() and journal.freed==0,"temporary map handoff preserves every draw owner")
	var exit_seen:Array=[]
	map.tree_exiting.connect(func():exit_seen.append(map.get_meta("stream_meshes").size()))
	var started:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self)
	var prepare_us:=Time.get_ticks_usec()-started;service.set_process(false)
	var tickets:int=service.pending.size();Stream.prepare_map_disposal(map,self);service.set_process(false)
	check(service.pending.size()==tickets,"repeated permanent preparation creates no extra tickets")
	check(live.mesh==borrower and journal.freed==0,"preparation leaves live source resources intact")
	if not baseline:
		check(tickets==1 and service.pending[0].values.size()==384,"one flat retirement ticket deduplicates 1536 instances into 384 draw owners")
	started=Time.get_ticks_usec();map.free();map=null;live=null
	var destroy_us:=Time.get_ticks_usec()-started;service.set_process(false)
	check(weak_map.get_ref()==null and weak_node.get_ref()==null,"map and source nodes are immediately destroyed")
	check(exit_seen==[1536],"exit observers still see the original source directory")
	var synchronous_releases:=journal.freed
	if not baseline:check(synchronous_releases==0,"map deletion does not synchronously release the restored draw meshes")
	var slices:=0;var maximum:=0;var total:=0;var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		started=Time.get_ticks_usec();service._process(0.);var elapsed:=Time.get_ticks_usec()-started
		total+=elapsed;maximum=maxi(maximum,elapsed);slices+=1
		await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"retirement completely drains")
	check(journal.freed==383 and journal.off_main==0,"unborrowed draw meshes release exactly once on main")
	check(borrower.get_surface_count()==1,"external borrower remains usable and unmodified")
	borrower=null
	check(journal.freed==384 and journal.off_main==0,"last borrowed owner releases normally")
	var report:={"checks":checks,"failures":failures,"baseline":baseline,"prepare_us":prepare_us,"destroy_us":destroy_us,"synchronous_releases":synchronous_releases,"retirement_us":total,"slices":slices,"max_slice_us":maximum,"display":DisplayServer.get_name()}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_RENDER_MESH_RETIREMENT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
