extends SceneTree
## Receive the official editor debugger protocol unchanged. No game-side
## timing hooks: servers/visual packets come from Godot's built-in profilers.
## Run with an empty external --path to avoid this project's autoloads.
var server:=TCPServer.new()
var tcp:StreamPeerTCP
var packets:=PacketPeerStream.new()
var file:FileAccess
var port:=16229
var deadline:=0
var count:=0
var frame_count:=0
var configured:=false
var profiling:=false
var phase_log:=""
var wait_marker:=""
var next_gate_msec:=0
func _initialize()->void:
	Engine.max_fps=120
	var output:=""
	var timeout_seconds:=360
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
		elif arg.begins_with("--phase-log="):phase_log=arg.trim_prefix("--phase-log=")
		elif arg.begins_with("--wait-marker="):wait_marker=arg.trim_prefix("--wait-marker=")
		elif arg.begins_with("--timeout-seconds="):timeout_seconds=clampi(int(arg.trim_prefix("--timeout-seconds=")),30,900)
	if output.is_empty():push_error("--output is required");quit(2);return
	if not wait_marker.is_empty() and phase_log.is_empty():push_error("--wait-marker requires --phase-log");quit(2);return
	file=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot open profiler recording");quit(2);return
	packets.input_buffer_max_size=16<<20;packets.output_buffer_max_size=1<<20
	if server.listen(port,"127.0.0.1")!=OK:push_error("Profiler loopback port is occupied");quit(2);return
	deadline=Time.get_ticks_msec()+timeout_seconds*1000
	print("OFFICIAL_PROFILER_LISTENING port=",port)
func _process(_delta:float)->bool:
	if Time.get_ticks_msec()>deadline:finish("timeout");return true
	if tcp==null:
		if not server.is_connection_available():return false
		tcp=server.take_connection();tcp.set_no_delay(true);packets.stream_peer=tcp
		packets.put_var(["core:set_ignore_error_breaks",1,[true]])
		configured=true;print("OFFICIAL_PROFILER_CONNECTED")
	tcp.poll()
	if not profiling and Time.get_ticks_msec()>=next_gate_msec:
		next_gate_msec=Time.get_ticks_msec()+250
		if wait_marker.is_empty() or (FileAccess.file_exists(phase_log) and FileAccess.get_file_as_string(phase_log).contains(wait_marker)):
			# Same commands as the editor; gating happens in this external receiver.
			# Include native script API calls and 512 functions for attribution.
			packets.put_var(["profiler:servers",1,[true,[512,true]]])
			packets.put_var(["profiler:visual",1,[true]])
			profiling=true;print("OFFICIAL_PROFILER_ENABLED marker=",wait_marker)
	while packets.get_available_packet_count()>0:
		var message:Variant=packets.get_var(false)
		if packets.get_packet_error()!=OK:push_error("Invalid official debugger packet");finish("packet_error");return true
		if not message is Array or message.size()!=3:push_error("Invalid official debugger message");finish("message_error");return true
		file.store_var(message,false);count+=1
		if message[0]=="servers:profile_frame":frame_count+=1
	if tcp.get_status()!=StreamPeerTCP.STATUS_CONNECTED:finish("disconnected");return true
	return false
func finish(reason:String)->void:
	if file!=null:file.flush();file.close();file=null
	server.stop()
	print("OFFICIAL_PROFILER_SAVED reason=",reason," packets=",count," frames=",frame_count)
	quit(0 if reason=="disconnected" and frame_count>0 else 1)
