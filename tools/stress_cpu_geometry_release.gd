extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Size=preload("res://scripts/world3d/cpu_geometry_size.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func release(surfaces:Array,lods:Array,faces:PackedVector3Array,key:String)->void:
	var mesh:=Cpu.new();mesh.surfaces=surfaces;mesh.lods=lods;mesh._collision_faces=faces
	if not key.is_empty():mesh.set_geometry_key(key)
func run()->void:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	var surfaces:Array=[];var lods:Array=[]
	for i:int in 16:surfaces.append(arrays);lods.append({1.:PackedInt32Array([0,1,2])})
	var faces:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var before:=var_to_bytes([surfaces,lods,faces]);var reports:Array=[]
	for keyed:bool in [false,true]:
		for batch:bool in [false,true,true,false]:
			Retirement.batched_geometry_release_enabled=batch;Retirement._geometry_sizes=Size.new()
			var service:Node=Retirement._service();service.set_process(false)
			var began:=Time.get_ticks_usec()
			for i:int in 8192:release(surfaces,lods,faces,"geometry%d"%(i%8) if keyed else "")
			var enqueue_us:=Time.get_ticks_usec()-began;var maximum:=0;var drain_main:=0
			service.set_process(false)
			while not service.pending.is_empty():
				var start:=Time.get_ticks_usec();var done:bool=service._advance(service.pending[0],1000)
				if done:service._finish_front()
				var elapsed:=Time.get_ticks_usec()-start;maximum=maxi(maximum,elapsed);drain_main+=elapsed
				if not done:await process_frame
			check(var_to_bytes([surfaces,lods,faces])==before and service.known.is_empty(),"borrowers intact and all production tickets released")
			if batch:check(service.profile.geometry_unmeasured_owners==8192 and Retirement._geometry_sizes.channels==0,"all 8192 owners transferred with zero threshold scans")
			reports.append({"keyed":keyed,"batch":batch,"enqueue_us":enqueue_us,"drain_main_us":drain_main,"max_drain_us":maximum,"wall_us":Time.get_ticks_usec()-began,"scans":Retirement._geometry_sizes.scans,"channels":Retirement._geometry_sizes.channels,"profile":service.profile.duplicate()})
			service.free()
	var report:={"trials":reports,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CPU_GEOMETRY_RELEASE ",JSON.stringify(report));quit(1 if failures else 0)
