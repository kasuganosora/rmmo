extends SceneTree
## Run in the external empty profiler fixture, with native call capture on.
## Each worker owns its own SurfaceTool; only the script/function is shared.
const WORKERS:=4
const VERTICES:=50000
var workers:Array[Thread]=[]
func _initialize()->void:run.call_deferred()
static func emit_vertex(surface:SurfaceTool,i:int)->void:
	surface.set_normal(Vector3.UP)
	surface.set_uv(Vector2(i%17,i%11))
	surface.add_vertex(Vector3(i%23,0,i%31))
static func prepare()->int:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i:int in VERTICES:emit_vertex(surface,i)
	return VERTICES
func run()->void:
	Engine.max_fps=240
	print("PROFILE_THREADED_BEGIN")
	await create_timer(35. if "--gdb-witness" in OS.get_cmdline_user_args() else 2.).timeout
	for i:int in WORKERS:
		var worker:=Thread.new();workers.append(worker)
		if worker.start(prepare)!=OK:quit(1);return
	while workers.any(func(worker:Thread):return worker.is_alive()):await process_frame
	var count:=0
	for worker:Thread in workers:count+=int(worker.wait_to_finish())
	await create_timer(.5).timeout
	print("PROFILE_THREADED_COMPLETE vertices=",count)
	quit(0 if count==WORKERS*VERTICES else 1)
