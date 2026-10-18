extends SceneTree
## Run in an empty external project with the official remote profiler receiver
## and native-call profiling enabled. No map, renderer or imported assets.
var released:=0
func _initialize()->void:run.call_deferred()
func run()->void:
	Engine.max_fps=120
	print("PROFILE_FREE_BEGIN")
	await create_timer(35. if "--gdb-witness" in OS.get_cmdline_user_args() else 2.).timeout
	for frame:int in 240:
		for i:int in 256:
			var node:Node=Node3D.new()
			node.add_child(MeshInstance3D.new())
			node.set_meta("fixture",{"serial":released,"values":[1,2,3,4]})
			node.free()
			released+=1
		await process_frame
	print("PROFILE_FREE_COMPLETE released=",released)
	quit(0 if released==61440 else 1)
