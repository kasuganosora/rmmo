extends SceneTree
## Run on the private GPU desktop. Raw arm reproduces redundant native setters.
const Frames=preload("res://scripts/util/frame_presentation.gd")
var checks:=0
var failures:=0
var output:=""
var guarded:=false
var updater:Script
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func apply_vsync(mode:DisplayServer.VSyncMode,window:int)->bool:
	if guarded:return updater.call("set_vsync_mode",mode,window)
	DisplayServer.window_set_vsync_mode(mode,window)
	return true
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--guarded":guarded=true
	if DisplayServer.get_name()=="headless" or output.is_empty():push_error("Private GPU desktop and external --output required");quit(2);return
	check(not FileAccess.file_exists(output),"new evidence path")
	if guarded:updater=load("res://scripts/util/display_state.gd")
	Engine.max_fps=0
	root.size=Vector2i(640,480)
	var color:=ColorRect.new();color.color=Color(.15,.25,.4);color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(color)
	var window:=root.get_window_id()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,window)
	for i:int in 12:await Frames.drawn()
	var rows:Array=[];var submits:=0
	for i:int in 12:
		await process_frame
		var before:=DisplayServer.window_get_vsync_mode(window)
		var began:=Time.get_ticks_usec()
		var changed:=apply_vsync(DisplayServer.VSYNC_DISABLED,window)
		if changed:submits+=1
		await Frames.drawn()
		rows.append({"us":Time.get_ticks_usec()-began,"before":before,"after":DisplayServer.window_get_vsync_mode(window),"submitted":changed})
		check(before==DisplayServer.VSYNC_DISABLED and DisplayServer.window_get_vsync_mode(window)==before,"same-value request preserves actual presentation mode")
		for settle:int in 3:await Frames.drawn()
	check(submits==(0 if guarded else 12),"only raw arm submits redundant native changes")
	if guarded:
		check(apply_vsync(DisplayServer.VSYNC_ENABLED,window),"real enabled transition submitted")
		await Frames.drawn()
		check(DisplayServer.window_get_vsync_mode(window)==DisplayServer.VSYNC_ENABLED,"enabled transition applied")
		check(not apply_vsync(DisplayServer.VSYNC_ENABLED,window),"same enabled transition skipped")
		check(apply_vsync(DisplayServer.VSYNC_DISABLED,window),"real disabled transition submitted")
		await Frames.drawn()
		check(DisplayServer.window_get_vsync_mode(window)==DisplayServer.VSYNC_DISABLED,"disabled transition applied")
	# Keep GPU readback outside the measured setter intervals.
	var image:=root.get_texture().get_image()
	check(image!=null and image.get_width()==640 and image.get_height()==480,"frame remains rendered at the requested dimensions")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"guarded":guarded,"native_submissions":submits,"samples":rows,"engine":OS.get_executable_path(),"contract":"Same presentation mode and scene. Wall time through the next submitted draw, including required render waits. Not a map performance result."},"\t"));file.close()
	print("DISPLAY_STATE_GPU checks=",checks," failures=",failures," submits=",submits)
	quit(1 if failures else 0)
