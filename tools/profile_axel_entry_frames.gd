extends "res://tools/profile_axel_game_pipeline.gd"
## Official profiler entry-only route, with the same production readiness guard.
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_entry_frames.gd"]=FileAccess.get_sha256("res://tools/profile_axel_entry_frames.gd")
	return result
func observe()->void:
	super.observe()
	if sampling and not frames.is_empty():frames.back().engine_frame=Engine.get_process_frames()
