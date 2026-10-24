extends SceneTree
const Probe=preload("res://tools/cpu_retirement_batch_probe.gd")
const Size=preload("res://scripts/world3d/cpu_geometry_size.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var surfaces:Array=[];var lods:Array=[]
	for i:int in 16:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(i,0,0),Vector3.RIGHT,Vector3.BACK])
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2]);surfaces.append(arrays);lods.append({1.:PackedInt32Array([0,1,2])})
	var faces:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]);var before:=var_to_bytes([surfaces,lods,faces])
	var expected:int=Size.new().measure(surfaces,lods)+faces.size()*12
	var reports:Array=[]
	for keyed:bool in [false,true]:
		for background:bool in [false,true,true,false]:
			var sizes:=Size.new();var queue:=Probe.new();var began:=Time.get_ticks_usec();var total:=0
			for i:int in 8192:
				var key:String="geometry%d"%(i%8) if keyed else ""
				if background:queue.append(surfaces,lods,faces,key)
				else:total+=sizes.measure(surfaces,lods,key)+faces.size()*12
			var main_us:=Time.get_ticks_usec()-began;var maximum:=0;var worker_us:=0;var released:=0
			if background:
				for batch:Array in queue.batches:
					var worker:=Thread.new();var started:=Time.get_ticks_usec()
					check(worker.start(Probe.release.bind(batch,sizes))==OK,"batch starts")
					var scheduling:=Time.get_ticks_usec()-started
					while worker.is_alive():await process_frame
					started=Time.get_ticks_usec();var result:Dictionary=worker.wait_to_finish();scheduling+=Time.get_ticks_usec()-started
					maximum=maxi(maximum,scheduling);main_us+=scheduling;worker_us+=result.us;total+=result.bytes
					released+=result.count
					check(batch.is_empty() and result.thread!=OS.get_main_thread_id(),"typed roots release on worker")
			check((released==8192 if background else total==expected*8192) and var_to_bytes([surfaces,lods,faces])==before,"fixed workload and exact borrowed channels survive")
			reports.append({"keyed":keyed,"background":background,"main_us":main_us,"worker_us":worker_us,"maximum_schedule_us":maximum,"wall_us":Time.get_ticks_usec()-began,"scans":sizes.scans,"channels":sizes.channels,"batches":queue.batches.size()})
	var report:={"trials":reports,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CPU_RETIREMENT_BATCH ",JSON.stringify(report));quit(1 if failures else 0)
