extends SceneTree
## Loopback collector for Godot's built-in script/native and visual profilers.
## GPU client still runs through run_godot_background.py, without editor focus.
var server:=TCPServer.new()
var client:StreamPeerTCP
var packets:=PacketPeerStream.new()
var output:=""
var port:=6019
var connected:=false
var messages:Array=[]
var counts:Dictionary={}
var began:=0
var finished:=false
var scripts:=false
var minimum_render_ms:=0.
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--port="):port=arg.trim_prefix("--port=").to_int()
		elif arg=="--scripts":scripts=true
		elif arg.begins_with("--minimum-render-ms="):minimum_render_ms=arg.trim_prefix("--minimum-render-ms=").to_float()
	if output.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(output,"D:/code/rmmo_runtime/review_artifacts"):quit(2);return
	if server.listen(port,"127.0.0.1")!=OK:quit(2);return
	packets.input_buffer_max_size=16*1024*1024;packets.output_buffer_max_size=1024*1024
	Engine.max_fps=120;began=Time.get_ticks_usec()
	print("GODOT_PROFILER_LISTENING ",port)
	create_timer(440).timeout.connect(func():finish(2))
func _process(_delta:float)->bool:
	if finished:return false
	if client==null:
		if not server.is_connection_available():return false
		client=server.take_connection();packets.stream_peer=client;connected=true
		packets.put_var(["core:set_ignore_error_breaks",1,[true]])
		if scripts:packets.put_var(["profiler:servers",1,[true,[128,false]]])
		packets.put_var(["profiler:visual",1,[true,[]]])
	client.poll()
	while packets.get_available_packet_count()>0:
		var message:Variant=packets.get_var(false)
		if not message is Array or message.size()!=3:continue
		var name:String=str(message[0]);counts[name]=int(counts.get(name,0))+1
		if name=="visual:profile_frame" and minimum_render_ms>0:
			var data:Array=message[2]
			if data.size()>=5 and float(data[-2])<minimum_render_ms and float(data[-1])<minimum_render_ms:continue
		if name.begins_with("servers:") or name.begins_with("visual:") or name=="error":
			if messages.size()<100000:messages.append({"at_us":Time.get_ticks_usec()-began,"name":name,"thread":message[1],"data":message[2]})
	if connected and client.get_status()!=StreamPeerTCP.STATUS_CONNECTED:finish(0)
	return false
func finish(code:int)->void:
	finished=true;server.stop()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"counts":counts,"messages":messages,"limits":"Built-in profiling run is diagnostic; its overhead is excluded from unprofiled benefit claims. Script total times nest; visual profiles contain CPU/GPU timestamp areas."},"\t"));file.close()
	print("GODOT_PROFILER_CAPTURED ",counts);quit(code)
