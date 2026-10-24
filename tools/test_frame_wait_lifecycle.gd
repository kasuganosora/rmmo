extends "res://tools/profile_axel_waits.gd"
## Exercise the real inherited finish chain without loading a map or renderer.
var completed_phases:=0
func _initialize()->void:
	run_lifecycle.call_deferred()

func source_snapshot(_folder:String="res://scripts")->Dictionary:
	return {"res://tools/profile_axel_game_pipeline.gd":FileAccess.get_sha256("res://tools/profile_axel_game_pipeline.gd")}

func save()->void:
	check(completed_phases==2,"final save follows both asynchronous phases")
	check(heartbeat.active,"heartbeat remains active through final save")
	print("FRAME_WAIT_LIFECYCLE failures=",report.failures.size())

func run_lifecycle()->void:
	began=Time.get_ticks_usec()
	heartbeat=Heartbeat.new()
	var port:=19879
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--frame-heartbeat-port="):port=arg.trim_prefix("--frame-heartbeat-port=").to_int()
	check(heartbeat.start(port)==OK,"heartbeat starts")
	report.map_sha=FileAccess.get_sha256(MAP)
	report.sources=source_snapshot()
	mesh_map=Node3D.new()
	root.add_child(mesh_map)
	# Match the real entry call, which starts the asynchronous route without
	# waiting on the SceneTree that the route itself will shut down.
	finish(0)

func traverse()->void:
	for phase_name:String in ["white_origin_steady","white_native_reload"]:
		await create_timer(0.01).timeout
		var before:int=heartbeat.sequence
		heartbeat.mark(Heartbeat.OBSERVE_BEGIN,phase_name,began)
		check(heartbeat.active and heartbeat.sequence==before+1,"armed heartbeat survives entry finish: "+phase_name)
		completed_phases+=1
	mesh_map.free()
	mesh_map=null
