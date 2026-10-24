extends "res://tools/profile_axel_worker_capacity.gd"
## The same capacity experiment with official profiler frame correlation.
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_worker_official.gd"]=FileAccess.get_sha256("res://tools/profile_axel_worker_official.gd")
	return result
func observe()->void:
	super.observe()
	if sampling and not frames.is_empty():frames.back().engine_frame=Engine.get_process_frames()
