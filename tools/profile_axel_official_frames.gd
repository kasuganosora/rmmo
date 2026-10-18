extends "res://tools/profile_axel_white_streaming.gd"
## Label built-in profiler frames by route phase. No new method timers.
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_official_frames.gd"]=FileAccess.get_sha256("res://tools/profile_axel_official_frames.gd")
	return result
func observe()->void:
	super.observe()
	if sampling and not frames.is_empty():frames.back().engine_frame=Engine.get_process_frames()
