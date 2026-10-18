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
func _initialize()->void:
	Engine.max_fps=120
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
	if output.is_empty():push_error("--output is required");quit(2);return
	file=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot open profiler recording");quit(2);return
	packets.input_buffer_max_size=16<<20;packets.output_buffer_max_size=1<<20
	if server.listen(port,"127.0.0.1")!=OK:push_error("Profiler loopback port is occupied");quit(2);return
	deadline=Time.get_ticks_msec()+360000
	print("OFFICIAL_PROFILER_LISTENING port=",port)
func _process(_delta:float)->bool:
	if Time.get_ticks_msec()>deadline:finish("timeout");return true
	if tcp==null:
		if not server.is_connection_available():return false
		tcp=server.take_connection();tcp.set_no_delay(true);packets.stream_peer=tcp
		# Same enable commands as the editor. Include native script API calls,
		# and retain more than the default 16 functions for attribution.
		packets.put_var(["profiler:servers",1,[true,[512,true]]])
		packets.put_var(["profiler:visual",1,[true]])
		packets.put_var(["core:set_ignore_error_breaks",1,[true]])
		configured=true;print("OFFICIAL_PROFILER_CONNECTED")
	tcp.poll()
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
