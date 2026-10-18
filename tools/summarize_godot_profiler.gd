extends SceneTree
## Offline decoder for unchanged Godot 4.7 editor profiler messages.
## Protocol: servers/debugger/servers_debugger.cpp at ed1daf0bf.
var names:Dictionary={}
var totals:Dictionary={}
var frames:Array=[]
var slowest:Array=[]
var visuals:Array=[]
var visual_frames:Array=[]
var gpu_peaks:Array=[]
var messages:Dictionary={}
func _initialize()->void:run.call_deferred()
func run()->void:
	var input:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):input=arg.trim_prefix("--input=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var file:=FileAccess.open(input,FileAccess.READ)
	if file==null or output.is_empty():push_error("--input and --output required");quit(2);return
	while file.get_position()<file.get_length():
		var message:Variant=file.get_var(false)
		if file.get_error()!=OK or not message is Array or message.size()!=3:push_error("Malformed recording");quit(2);return
		var label:String=message[0];var data:Array=message[2]
		messages[label]=int(messages.get(label,0))+1
		if label=="servers:function_signature":names[data[1]]=data[0]
		elif label=="servers:profile_frame":frame(data)
		elif label=="servers:profile_total":pass
		elif label=="visual:profile_frame":visual(data)
		elif label=="error" and not bool(data[9]):print("OFFICIAL_PROFILER_ERROR ",data.slice(4,10))
	file.close()
	var ranked:Array=totals.values();ranked.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.self_ms>b.self_ms)
	var out:=FileAccess.open(output,FileAccess.WRITE)
	if out==null:push_error("Cannot write summary");quit(2);return
	out.store_string(JSON.stringify({"source":input,"engine_commit":"ed1daf0bf","note":"Official profiler observations, not uninstrumented timings. self/total/internal are preserved separately; inclusive scopes and native internal rows can overlap.","messages":messages,"signatures":names,"frames":frames,"slowest_frames":slowest,"function_totals":ranked,"visual_peaks":visuals,"visual_frames":visual_frames,"gpu_peaks":gpu_peaks},"\t"));out.close()
	print("OFFICIAL_PROFILER_SUMMARY frames=",frames.size()," signatures=",names.size()," output=",output);quit(0)
func frame(data:Array)->void:
	var row:Dictionary={"frame":data[0],"frame_ms":float(data[1])*1000.,"process_ms":float(data[2])*1000.,"physics_ms":float(data[3])*1000.,"script_ms":float(data[5])*1000.}
	frames.append(row.duplicate())
	var at:=7
	for server_index:int in int(data[6]):at+=2+int(data[at+1])
	var count:int=data[at];at+=1
	var functions:Array=[]
	for offset:int in range(at,at+count,5):
		var id:int=data[offset];var signature:String=names.get(id,"unknown:"+str(id))
		var function:Dictionary={"signature":signature,"calls":data[offset+1],"self_ms":float(data[offset+2])*1000.,"total_ms":float(data[offset+3])*1000.,"internal_ms":float(data[offset+4])*1000.}
		functions.append(function)
		if not totals.has(signature):totals[signature]={"signature":signature,"calls":0,"self_ms":0.,"total_ms":0.,"internal_ms":0.,"max_self_ms":0.,"max_self_frame":0,"max_total_ms":0.,"max_total_frame":0}
		var aggregate:Dictionary=totals[signature]
		aggregate.calls+=int(function.calls);aggregate.self_ms+=function.self_ms;aggregate.total_ms+=function.total_ms;aggregate.internal_ms+=function.internal_ms
		if function.self_ms>aggregate.max_self_ms:aggregate.max_self_ms=function.self_ms;aggregate.max_self_frame=row.frame
		if function.total_ms>aggregate.max_total_ms:aggregate.max_total_ms=function.total_ms;aggregate.max_total_frame=row.frame
	if slowest.size()<25 or row.frame_ms>float(slowest.back().frame_ms):
		functions.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.self_ms>b.self_ms)
		row.functions=functions;slowest.append(row);slowest.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.frame_ms>b.frame_ms)
		if slowest.size()>25:slowest.resize(25)
func visual(data:Array)->void:
	var cpu:=0.;var gpu:=0.
	for at:int in range(2,data.size(),3):cpu=maxf(cpu,float(data[at+1]));gpu=maxf(gpu,float(data[at+2]))
	var row:Dictionary={"frame":data[0],"max_cpu_timestamp_ms":cpu,"max_gpu_timestamp_ms":gpu,"raw_areas":data.slice(2)}
	visual_frames.append({"frame":data[0],"max_cpu_timestamp_ms":cpu,"max_gpu_timestamp_ms":gpu})
	visuals.append(row);visuals.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.max_cpu_timestamp_ms>b.max_cpu_timestamp_ms)
	if visuals.size()>25:visuals.resize(25)
	gpu_peaks.append(row);gpu_peaks.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.max_gpu_timestamp_ms>b.max_gpu_timestamp_ms)
	if gpu_peaks.size()>25:gpu_peaks.resize(25)
