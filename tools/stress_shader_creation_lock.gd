extends SceneTree
## Fixed captured-input workload against the same global RD lock seen in GDB.
## Run with the private-desktop runner; never a headless performance sample.
var checks:=0
var failures:Array[String]=[]
var rd:RenderingDevice
var packets:Array[PackedByteArray]=[]
var start_gate:=Semaphore.new()
var workers:Array[Thread]=[]
var rounds:=8
var output:=""
var inputs_dir:=""
var gate_file:=""
var progress_prefix:=""

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--inputs-dir="):inputs_dir=arg.trim_prefix("--inputs-dir=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--rounds="):rounds=int(arg.trim_prefix("--rounds="))
		elif arg.begins_with("--gate-file="):gate_file=arg.trim_prefix("--gate-file=")
		elif arg.begins_with("--progress-prefix="):progress_prefix=arg.trim_prefix("--progress-prefix=")
	call_deferred("run")

func stage_of(bytes:PackedByteArray)->int:
	var offset:=20
	while offset+4<=bytes.size():
		var instruction:=bytes.decode_u32(offset)
		var count:=instruction>>16
		if count==0:return -1
		if instruction&65535==15:
			match bytes.decode_u32(offset+4):
				0:return RenderingDevice.SHADER_STAGE_VERTEX
				4:return RenderingDevice.SHADER_STAGE_FRAGMENT
				5:return RenderingDevice.SHADER_STAGE_COMPUTE
			return -1
		offset+=count*4
	return -1

func work(worker:int)->Dictionary:
	start_gate.wait()
	var owned:Array[RID]=[]
	var elapsed_us:=0
	var invalid:=0
	for round_index in rounds:
		for i in range(worker,packets.size(),workers.size()):
			var began:=Time.get_ticks_usec()
			var shader:=rd.shader_create_from_bytecode(packets[i])
			elapsed_us+=Time.get_ticks_usec()-began
			if shader.is_valid():owned.append(shader)
			else:invalid+=1
	if not progress_prefix.is_empty():
		var file:=FileAccess.open(progress_prefix+".worker%d.json"%worker,FileAccess.WRITE)
		file.store_string(JSON.stringify({"worker":worker,"created":owned.size(),"invalid":invalid,"unix":Time.get_unix_time_from_system()}));file.close()
	return {"owned":owned,"elapsed_us":elapsed_us,"invalid":invalid}

func run()->void:
	rd=RenderingServer.get_rendering_device()
	check(rd!=null,"global RenderingDevice available")
	check(not inputs_dir.is_empty() and not output.is_empty() and rounds>0,"explicit external inputs/output and positive rounds")
	if not failures.is_empty():quit(1);return
	var files:Array[Dictionary]=[]
	for filename in DirAccess.get_files_at(inputs_dir):
		if filename.ends_with(".spv"):
			var path:=inputs_dir.path_join(filename)
			var bytes:=FileAccess.get_file_as_bytes(path)
			files.append({"name":filename,"data":bytes})
	files.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.data.size()>b.data.size() if a.data.size()!=b.data.size() else a.name<b.name)
	files.resize(mini(files.size(),16))
	var manifest:Array=[]
	for item in files:
		var bytes:PackedByteArray=item.data
		var stage:=stage_of(bytes)
		check(stage>=0,"recognized captured SPIR-V stage")
		if stage<0:continue
		var spirv:=RDShaderSPIRV.new()
		spirv.set_stage_bytecode(stage,bytes)
		var binary:=rd.shader_compile_binary_from_spirv(spirv,"RmmoLockProbe_"+item.name)
		check(not binary.is_empty(),"captured stage converted once to a native container")
		packets.append(binary)
		manifest.append({"name":item.name,"input_bytes":bytes.size(),"container_bytes":binary.size(),"stage":stage})
	check(packets.size()==16,"fixed sixteen largest captured inputs")
	if not failures.is_empty():quit(1);return
	packets.make_read_only()
	var rect:=ColorRect.new();rect.color=Color.DARK_SLATE_BLUE;rect.size=Vector2(128,128);root.add_child(rect)
	for i in 3:await process_frame
	if not gate_file.is_empty():
		print("SHADER_LOCK_READY")
		var deadline:=Time.get_ticks_msec()+120000
		while not FileAccess.file_exists(gate_file) and Time.get_ticks_msec()<deadline:await process_frame
		check(FileAccess.file_exists(gate_file),"owned debugger gate released")
		if not failures.is_empty():quit(1);return
	for i in 2:
		var worker:=Thread.new();workers.append(worker)
	for i in workers.size():check(workers[i].start(work.bind(i))==OK,"worker starts")
	var began:=Time.get_ticks_usec()
	for i in workers.size():start_gate.post()
	var probe_us:Array[int]=[]
	var frame_us:Array[int]=[]
	var last:=began
	var last_progress:=0
	while true:
		var sample:=Time.get_ticks_usec()
		check(not rd.uniform_set_is_valid(RID()),"main RD ownership query remains valid")
		probe_us.append(Time.get_ticks_usec()-sample)
		if not progress_prefix.is_empty() and Time.get_ticks_msec()-last_progress>=100:
			var progress:=FileAccess.open(progress_prefix+".main.json",FileAccess.WRITE)
			progress.store_string(JSON.stringify({"samples":probe_us.size(),"unix":Time.get_unix_time_from_system()}));progress.close()
			last_progress=Time.get_ticks_msec()
		var busy:=false
		for worker in workers:busy=busy or worker.is_alive()
		if not busy:break
		await process_frame
		var now:=Time.get_ticks_usec();frame_us.append(now-last);last=now
	var wall_us:=Time.get_ticks_usec()-began
	var results:Array=[]
	var created:=0
	var freed:=0
	for worker in workers:
		var result:Dictionary=worker.wait_to_finish()
		var owned:Array=result.owned
		created+=owned.size()
		check(result.invalid==0,"all native shaders created")
		for shader:RID in owned:rd.free_rid(shader);freed+=1
		result.erase("owned");results.append(result)
	check(created==packets.size()*rounds and freed==created,"fixed work count and all created RIDs released")
	RenderingServer.force_sync()
	for i in 3:await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"inputs":manifest,"rounds":rounds,"workers":workers.size(),"created":created,"freed":freed,"worker_results":results,"wall_us":wall_us,"main_probe_us":probe_us,"frame_us":frame_us,"not_map_performance":true}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SHADER_LOCK_STRESS ",JSON.stringify({"checks":checks,"failures":failures,"created":created,"wall_us":wall_us,"max_probe_us":probe_us.max(),"max_frame_us":frame_us.max() if not frame_us.is_empty() else 0}))
	quit(0 if failures.is_empty() else 1)
