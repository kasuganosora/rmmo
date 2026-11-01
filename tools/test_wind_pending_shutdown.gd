extends SceneTree
## Whole-process GPU shutdown with a dispatched wind task and a queued variant.
## The finite release task needs no main-thread callback. Exit code 0, rather
## than the markers alone, is required by the external background runner.
const Materials=preload("res://scripts/world3d/wind_material.gd")
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
func _initialize()->void:run.call_deferred()
static func release_after_delay(gate:Semaphore)->void:
	OS.delay_msec(1500)
	gate.post()
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,1,5);camera.look_at(Vector3.ZERO);camera.current=true
	var runtime:=Runtime.new();scene.add_child(runtime);runtime.camera=camera;runtime.cached_variants_only=true;runtime.set_physics_process(false)
	for at:int in 2:
		var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();var source:=StandardMaterial3D.new()
		source.cull_mode=BaseMaterial3D.CULL_BACK if at==0 else BaseMaterial3D.CULL_DISABLED
		source.texture_repeat=false;source.albedo_color=Color(.2+.5*at,.5,.8);mesh.material=source
		node.mesh=mesh;node.position.x=float(at)*2-1;scene.add_child(node)
		node.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}});Response.register(node)
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	var gate:=Semaphore.new();Materials.preparation_test_gate=gate
	runtime.refresh()
	var pending:Dictionary=Materials.background_profile()
	var valid:bool=pending.active==1 and pending.pending==2 and pending.completed==0
	print("WIND_SHUTDOWN_PENDING ",JSON.stringify(pending)," valid=",valid)
	Materials.preparation_test_gate=null
	WorkerThreadPool.add_task(release_after_delay.bind(gate),true,"finite wind shutdown gate release")
	quit(0 if valid else 1)
func _finalize()->void:
	print("WIND_SHUTDOWN_FINALIZED ",JSON.stringify(Materials.background_profile()))
