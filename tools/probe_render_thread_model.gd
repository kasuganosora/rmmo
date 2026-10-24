extends Node
## Reports the render thread model of an ordinary game run (a scene, not --script).
func _ready()->void:
	await get_tree().process_frame
	var report:={
		"feature":OS.has_feature("rmmo_game_render_thread"),
		"separate":not RenderingServer.is_on_render_thread(),
		"thread_model_setting":ProjectSettings.get_setting_with_override("rendering/driver/threads/thread_model"),
		"engine":Engine.get_version_info().string,
		"executable":OS.get_executable_path(),
	}
	print("RENDER_THREAD_MODEL ",JSON.stringify(report))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	get_tree().quit()
