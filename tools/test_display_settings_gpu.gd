extends SceneTree
## Real display reapplication, with detached, non-persistent game settings.
const Frames=preload("res://scripts/util/frame_presentation.gd")
const Settings=preload("res://scripts/game/game_settings.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()=="headless" or output.is_empty():push_error("Private GPU desktop and external --output required");quit(2);return
	check(not FileAccess.file_exists(output),"new artifact")
	var settings:=Settings.new();settings.persist_enabled=false
	settings.window_mode="windowed";settings.resolution=Vector2i(1280,720);settings.vsync=false;settings.max_fps=0
	settings.apply_display()
	var color:=ColorRect.new();color.color=Color(.15,.25,.4);color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(color)
	for i:int in 12:await Frames.drawn()
	var rows:Array=[]
	for i:int in 8:
		await process_frame
		var began:=Time.get_ticks_usec()
		settings.apply_display()
		await Frames.drawn()
		rows.append(Time.get_ticks_usec()-began)
		check(DisplayServer.window_get_size()==settings.resolution and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"reapplication preserves actual window and presentation state")
		for settle:int in 3:await Frames.drawn()
	settings.resolution=Vector2i(1600,900);settings.apply_display()
	for i:int in 3:await Frames.drawn()
	check(DisplayServer.window_get_size()==Vector2i(1600,900),"real supported resolution change applies")
	settings.vsync=true;settings.apply_display();await Frames.drawn()
	check(DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_ENABLED,"real settings VSync change applies")
	# Changes outside this settings owner must be reconciled from actual state,
	# not hidden by a cache of the last requested preference.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	settings.apply_display();await Frames.drawn()
	check(DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_ENABLED,"external presentation change is restored from preference")
	settings.vsync=false;settings.resolution=Vector2i(1280,720);settings.max_fps=144;settings.apply_display();await Frames.drawn()
	check(Engine.max_fps==144 and DisplayServer.window_get_size()==Vector2i(1280,720) and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"FPS cap, resolution and VSync changes remain independent")
	settings.window_mode="borderless";settings.apply_display()
	for i:int in 3:await Frames.drawn()
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"real borderless mode change applies")
	settings.window_mode="windowed";settings.apply_display()
	for i:int in 3:await Frames.drawn()
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size()==settings.resolution,"return from fullscreen restores windowed resolution")
	settings.free()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"reapply_us":rows,"settings_sha256":FileAccess.get_sha256("res://scripts/game/game_settings.gd"),"contract":"Actual game apply_display; detached settings, no persistence, private desktop; wall interval through next submitted draw."},"\t"));file.close()
	print("DISPLAY_SETTINGS_GPU checks=",checks," failures=",failures)
	quit(1 if failures else 0)
