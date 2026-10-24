extends SceneTree
## Independent fixed-work stress fixture. CPU mode needs no project, GPU or map.
## GPU mode compares the original upload path and prepared native surface bytes.
## --cpu-only --workers=1,3,12 --jobs=48 --vertices=60000 --repeats=3 --output=...
const METHOD:=&"mesh_prepare_surface_from_arrays"
var failures:=0
var jobs:=48
var vertices:=60000
var repeats:=3
var worker_counts:Array[int]=[1,3,12]
var cpu_only:=false
var output:=""
var report:Dictionary={}

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--cpu-only":cpu_only=true
		elif arg.begins_with("--jobs="):jobs=clampi(arg.get_slice("=",1).to_int(),1,512)
		elif arg.begins_with("--vertices="):vertices=clampi(arg.get_slice("=",1).to_int(),3,300000)
		elif arg.begins_with("--repeats="):repeats=clampi(arg.get_slice("=",1).to_int(),1,10)
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--workers="):
			worker_counts.clear()
			for value:String in arg.get_slice("=",1).split(","):worker_counts.append(clampi(value.to_int(),1,32))
	run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

static func surface(count:int)->Array:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var points:=PackedVector3Array();points.resize(count)
	var normals:=PackedVector3Array();normals.resize(count);normals.fill(Vector3.UP)
	var tangent:=PackedFloat32Array();tangent.resize(count*4)
	var uv:=PackedVector2Array();uv.resize(count)
	var indices:=PackedInt32Array();indices.resize(count-count%3)
	for i:int in count:
		points[i]=Vector3(i%251,float(i%13)*.125,i/251)
		tangent[i*4]=1.;tangent[i*4+3]=1.
		uv[i]=Vector2(float(i%17)/16.,float(i%23)/22.)
		if i<indices.size():indices[i]=i
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TANGENT]=tangent;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

static func prepare(arrays:Array,flags:int=0,lods:Dictionary={},blends:Array=[])->Dictionary:
	return RenderingServer.call(METHOD,Mesh.PRIMITIVE_TRIANGLES,arrays,blends,lods,flags)

static func worker(arrays:Array,lods:Dictionary,flags:int,expected:Dictionary,count:int,ready:Semaphore,start:Semaphore)->Dictionary:
	ready.post();start.wait()
	var pack_us:=0;var max_pack_us:=0;var exact:=0;var bytes:=0
	for i:int in count:
		var began:=Time.get_ticks_usec()
		var packet:=prepare(arrays,flags,lods)
		var elapsed:=Time.get_ticks_usec()-began
		pack_us+=elapsed;max_pack_us=maxi(max_pack_us,elapsed)
		if packet==expected:exact+=1
		for channel:String in ["vertex_data","attribute_data","skin_data","index_data"]:
			bytes+=packet.get(channel,PackedByteArray()).size()
	return {"jobs":count,"pack_us":pack_us,"max_pack_us":max_pack_us,"exact":exact,"bytes":bytes,"thread":OS.get_thread_caller_id()}

func run()->void:
	report={"engine":Engine.get_version_info(),"jobs":jobs,"vertices":vertices,"repeats":repeats,"cpu_only":cpu_only,"runs":[],"gpu":[]}
	check(RenderingServer.has_method(METHOD),"pure CPU native surface preparation API exists")
	if failures:finish();return
	var arrays:=surface(vertices);var before:=var_to_bytes(arrays)
	var lods:Dictionary={8.:arrays[Mesh.ARRAY_INDEX].slice(0,mini(30,vertices-vertices%3))}
	var flags:=Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	var expected:=prepare(arrays,flags,lods)
	check(not expected.is_empty() and expected.vertex_count==vertices,"complete fixed input prepared")
	for trial:int in repeats:
		var order:Array[int]=worker_counts.duplicate()
		if trial%2:order.reverse()
		for count:int in order:
			var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array[Thread]=[]
			for at:int in count:
				var task_count:=jobs/count+(1 if at<jobs%count else 0)
				var thread:=Thread.new()
				thread.start(worker.bind(arrays.duplicate(),lods.duplicate(),flags,expected,task_count,ready,start))
				threads.append(thread)
			for thread:Thread in threads:ready.wait()
			var began:=Time.get_ticks_usec()
			for thread:Thread in threads:start.post()
			var rows:Array=[];var exact:=0;var completed:=0;var packed_bytes:=0
			for thread:Thread in threads:
				var row:Dictionary=thread.wait_to_finish();rows.append(row)
				exact+=row.exact;completed+=row.jobs;packed_bytes+=row.bytes
			var elapsed:=Time.get_ticks_usec()-began
			check(exact==jobs and completed==jobs,"fixed %d jobs exact with %d workers trial %d"%[jobs,count,trial])
			var result:={"workers":count,"trial":trial,"wall_us":elapsed,"jobs":completed,"exact":exact,"packed_bytes":packed_bytes,"tasks":rows}
			report.runs.append(result);print("SURFACE_STRESS ",JSON.stringify(result))
	check(var_to_bytes(arrays)==before,"all shared input channels remain unchanged")
	if not cpu_only:
		check(DisplayServer.get_name()!="headless","GPU verification uses a real renderer")
		if failures==0:
			await verify_gpu(arrays,lods,flags,expected)
			check(report.gpu.size()==repeats*2,"all legacy/prepared GPU timing pairs completed")
	finish()

func verify_gpu(arrays:Array,lods:Dictionary,flags:int,expected:Dictionary)->void:
	# Compare original engine output against prepacked output, including exact
	# compressed vertex bytes and LOD indices; no custom packing implementation.
	var cases:Array=[
		{"arrays":arrays,"lods":lods,"flags":flags,"blends":[]},
		{"arrays":surface(70002),"lods":{3.:PackedInt32Array([0,1,2])},"flags":0,"blends":[]},
		{"arrays":surface(9),"lods":{},"flags":0,"blends":[]},
	]
	cases[2].arrays[Mesh.ARRAY_INDEX]=null
	var custom:=surface(12);var layer:=PackedFloat32Array();layer.resize(12);layer.fill(3.)
	custom[Mesh.ARRAY_CUSTOM0]=layer
	cases.append({"arrays":custom,"lods":{},"flags":Mesh.ARRAY_CUSTOM_R_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT,"blends":[]})
	var animated:=surface(12);var blend:Array=[];blend.resize(Mesh.ARRAY_MAX)
	blend[Mesh.ARRAY_VERTEX]=animated[Mesh.ARRAY_VERTEX];blend[Mesh.ARRAY_NORMAL]=animated[Mesh.ARRAY_NORMAL];blend[Mesh.ARRAY_TANGENT]=animated[Mesh.ARRAY_TANGENT]
	cases.append({"arrays":animated,"lods":{},"flags":0,"blends":[blend]})
	for at:int in cases.size():
		var item:Dictionary=cases[at];var legacy:=ArrayMesh.new();var prepared:=ArrayMesh.new()
		for i:int in item.blends.size():legacy.add_blend_shape(str(i));prepared.add_blend_shape(str(i))
		legacy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,item.arrays,item.blends,item.lods,item.flags)
		prepared.set("_surfaces",[prepare(item.arrays,item.flags,item.lods,item.blends)])
		check(legacy.get("_surfaces")==prepared.get("_surfaces"),"native packed bytes/AABB/LOD/blend data match original case %d"%at)
		check(legacy.surface_get_arrays(0)==prepared.surface_get_arrays(0),"decoded GPU channels match original case %d"%at)
		check(legacy.get_aabb()==prepared.get_aabb(),"mesh bounds match case %d"%at)
	await process_frame
	for trial:int in repeats:
		var modes:Array=[false,true] if trial%2==0 else [true,false]
		for packed:bool in modes:
			var owners:Array=[];var durations:Array=[];var total:=0
			for job:int in jobs:
				var mesh:=ArrayMesh.new();var began:=Time.get_ticks_usec()
				if packed:mesh.set("_surfaces",[expected])
				else:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods,flags)
				var elapsed:=Time.get_ticks_usec()-began
				durations.append(elapsed);total+=elapsed;owners.append(mesh)
			durations.sort()
			report.gpu.append({"prepared":packed,"trial":trial,"jobs":jobs,"main_submit_us":total,"max_unit_us":durations.back(),"p95_unit_us":durations[int((durations.size()-1)*.95)]})
			await process_frame;await process_frame
			owners.clear()
			await process_frame

func finish()->void:
	report.failures=failures
	report.scope="Fixed total jobs. Worker wall includes exact-byte comparisons and joins; summed task time is not CPU time. GPU timing is main-thread submission, not GPU completion."
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file==null:failures+=1
		else:file.store_string(JSON.stringify(report,"\t"))
	print("SURFACE_STRESS_COMPLETE ",JSON.stringify({"failures":failures,"runs":report.runs.size(),"gpu":report.gpu}))
	quit(1 if failures else 0)
