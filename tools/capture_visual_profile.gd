extends SceneTree
## Loopback receiver for Godot 4.7's native visual profiler. Diagnostic only.
## Start headless, then launch the owned test with --remote-debug tcp://127.0.0.1:6069.
## Protocol: core/debugger/remote_debugger.cpp, servers/debugger/servers_debugger.cpp.
var server:=TCPServer.new()
var stream:StreamPeerTCP
var packets:=PacketPeerStream.new()
var frames:Array=[]
var hardware:Array=[]
var errors:Array=[]
var enabled:=false
var output:=""
var started:=0
func _initialize()->void:
	Engine.max_fps=120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or server.listen(6069,"127.0.0.1")!=OK:
		push_error("Provide --output and an unused loopback port 6069");quit(1);return
	started=Time.get_ticks_msec();packets.input_buffer_max_size=8<<20
	print("VISUAL_PROFILE_LISTENING 127.0.0.1:6069")
func _process(_delta:float)->bool:
	if Time.get_ticks_msec()-started>900000:finish(2);return false
	if stream==null:
		if not server.is_connection_available():return false
		stream=server.take_connection();stream.set_no_delay(true);packets.stream_peer=stream
	stream.poll()
	while packets.get_available_packet_count()>0:
		var message:Variant=packets.get_var(false)
		if not message is Array or message.size()!=3:continue
		if not enabled:
			# Reply to the actual emitting thread; no script execution or breakpoints.
			packets.put_var(["profiler:visual",message[1],[true]])
			enabled=true
		match str(message[0]):
			"visual:profile_frame":frames.append(message[2])
			"visual:hardware_info":hardware=message[2]
			"error":errors.append(message[2])
	if stream.get_status()!=StreamPeerTCP.STATUS_CONNECTED:finish(0)
	return false
func finish(code:int)->void:
	server.stop()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify({"hardware":hardware,"frames":frames,"errors":errors}))
	print("VISUAL_PROFILE_CAPTURE frames=",frames.size()," diagnostics=",errors.size())
	quit(code if not frames.is_empty() else 1)
