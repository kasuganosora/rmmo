extends SceneTree
func _init():call_deferred("run")
func run():
	var pack=load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default","Axel256")
	var path=load("res://scripts/map/grid_path.gd")
	var goals=path._snap_candidates(pack.collision,Vector2i(134,150),6)
	var files: Array=["res://scripts/map/grid_path.gd"]
	# Optional historical script supplied after -- for an A/B run.
	for argument in OS.get_cmdline_user_args():files.push_front(argument)
	for file in files:
		var script=GDScript.new();script.source_code=FileAccess.get_file_as_string(file)
		if script.reload()!=OK:quit(1);return
		var began=Time.get_ticks_usec()
		var result=script._find_path_heap_any(pack.collision,Vector2i(112,119),goals,Vector2i(134,150))
		print(file," ms=",(Time.get_ticks_usec()-began)/1000.0," steps=",result.size()," goal=",result[-1])
	quit()
