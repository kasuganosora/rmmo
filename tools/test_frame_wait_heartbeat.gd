extends SceneTree
## Actual sender/receiver timing fixture. Intentional stall is labelled, never
## included as evidence that the real map contains this wait.
const Heartbeat=preload("res://tools/frame_wait_heartbeat.gd")
func _initialize()->void:
	run.call_deferred()
func run()->void:
	var port:=0
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--frame-heartbeat-port="):port=arg.trim_prefix("--frame-heartbeat-port=").to_int()
	var beat:=Heartbeat.new();var origin:=Time.get_ticks_usec()
	if beat.start(port)!=OK:quit(1);return
	beat.mark(Heartbeat.OBSERVE_BEGIN,"loading",origin)
	beat.mark(Heartbeat.OBSERVE_END,"loading",origin)
	for i:int in 8:
		beat.mark(Heartbeat.OBSERVE_BEGIN,"white_origin_steady",origin)
		await create_timer(0.01).timeout
	beat.mark(Heartbeat.GEOMETRY_BEGIN,"white_origin_steady",origin)
	OS.delay_msec(150)
	beat.mark(Heartbeat.GEOMETRY_END,"white_origin_steady",origin)
	# Consecutive markers in return must not use the unarmed 100ms throttle.
	for i:int in 8:
		beat.mark(Heartbeat.OBSERVE_BEGIN,"white_native_return",origin)
	for i:int in 8:
		beat.mark(Heartbeat.OBSERVE_BEGIN,"white_return_steady",origin)
	for i:int in 8:
		beat.mark(Heartbeat.OBSERVE_BEGIN,"white_stream_origin",origin)
	for i:int in 8:
		await create_timer(0.01).timeout
		beat.mark(Heartbeat.OBSERVE_END,"white_native_reload",origin)
	beat.stop(origin)
	print("FRAME_HEARTBEAT_FIXTURE ",JSON.stringify(beat.profile))
	quit(0 if beat.profile.sent==44 and beat.profile.unarmed_skipped==1 and beat.profile.errors==0 and beat.profile.wrong_thread==0 else 1)
