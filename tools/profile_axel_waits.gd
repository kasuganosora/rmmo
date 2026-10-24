extends "res://tools/profile_axel_worker_official.gd"
## Opt-in watchdog adapter. Existing normal probe and production stay unchanged.
const Heartbeat=preload("res://tools/frame_wait_heartbeat.gd")
var heartbeat:RefCounted

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--frame-heartbeat-port="):
			heartbeat=Heartbeat.new()
			var result:Error=heartbeat.start(arg.trim_prefix("--frame-heartbeat-port=").to_int())
			if result!=OK:push_error("Frame heartbeat startup failed: "+str(result))
			RenderingServer.frame_pre_draw.connect(_heartbeat_pre_draw)
			RenderingServer.frame_post_draw.connect(_heartbeat_post_draw)
	super._initialize()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":
		for path:String in ["res://tools/profile_axel_waits.gd","res://tools/frame_wait_heartbeat.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _heartbeat_pre_draw()->void:
	if heartbeat!=null:heartbeat.mark(Heartbeat.PRE_DRAW,phase,began)

func _heartbeat_post_draw()->void:
	if heartbeat!=null:heartbeat.mark(Heartbeat.POST_DRAW,phase,began)

func observe()->void:
	if heartbeat!=null:heartbeat.mark(Heartbeat.OBSERVE_BEGIN,phase,began)
	super.observe()
	if heartbeat!=null:heartbeat.mark(Heartbeat.OBSERVE_END,phase,began)

func tick_geometry()->void:
	if heartbeat!=null:heartbeat.mark(Heartbeat.GEOMETRY_BEGIN,phase,began)
	super.tick_geometry()
	if heartbeat!=null:heartbeat.mark(Heartbeat.GEOMETRY_END,phase,began)

func save()->void:
	if heartbeat!=null:
		report.frame_heartbeat={"profile":heartbeat.profile.duplicate(),"transport":"64 byte loopback UDP; no disk writes; sender cost included in diagnostic frames","stages":{"1":"observe_begin","2":"observe_end","3":"geometry_begin","4":"geometry_end","5":"pre_draw_signal","6":"post_draw_signal","7":"stop"},"phases":{"0":"unarmed","1":"white_origin_steady","2":"white_native_reload","3":"white_native_return","4":"white_return_steady","5":"white_stream_origin"}}
	super.save()

func finish(code:int)->void:
	# The first finish starts the asynchronous unload/return route in the base
	# probe. Keep observing until it completes and requests SceneTree shutdown.
	await super.finish(code)
	if heartbeat!=null:
		if RenderingServer.frame_pre_draw.is_connected(_heartbeat_pre_draw):RenderingServer.frame_pre_draw.disconnect(_heartbeat_pre_draw)
		if RenderingServer.frame_post_draw.is_connected(_heartbeat_post_draw):RenderingServer.frame_post_draw.disconnect(_heartbeat_post_draw)
		heartbeat.stop(began)
