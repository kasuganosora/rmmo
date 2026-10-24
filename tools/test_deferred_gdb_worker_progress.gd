extends SceneTree
## Real native rmres/prefab preparation, real Deferred admission/publication.
## The two semaphores only establish a lock-free debugger boundary. The runner
## must suspend A with GDB/WinAPI, then release BOTH semaphores before checking
## B/C/D progress. Semaphore waiting alone is never the pause assertion.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Fixture=preload("res://tools/test_map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Queue extends Deferred:
	var a_gate:=Semaphore.new()
	var b_gate:=Semaphore.new()
	var starts:Array=[]
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,faces:bool,content_root:String,requests:Array,native:bool,need_model:bool)->Callable:
		var task:=super._make_prepare_task(path,digest,token,item,faces,content_root,requests,native,need_model)
		var label:=path.right(1);starts.append(label)
		return actual_work.bind(task,label,a_gate,b_gate)
	static func actual_work(task:Callable,label:String,a:Semaphore,b:Semaphore)->Dictionary:
		OS.set_thread_name("RMMO_GDB_"+label)
		print("GDB_WORKER_STARTED ",label," godot_id=",OS.get_thread_caller_id())
		if label=="B":
			print("GDB_BOUNDARY_B before_actual_prepare")
			b.wait()
		var result:Dictionary=task.call()
		print("GDB_REAL_PREPARED ",label," records=",result.get("records",[]).size()," prefab_cpu=",result.get("prefab_cpu",{}).size()," reads=",result.get("read_profile",{}).get("reads_started",0)," error=",result.get("error",""))
		if label=="A":
			# The complete production call returned: no decoder/cache lock is held.
			print("GDB_BOUNDARY_A after_actual_prepare_before_return")
			a.wait()
		print("GDB_WORKER_RETURN ",label)
		return result

var passed:=0
var failed:=0
var output:=""
var observed:Array=[]
var published_counts:Dictionary={}
var atomic:=true
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func save(name_:String,data:Dictionary)->void:
	var file:=FileAccess.open(output.path_join(name_),FileAccess.WRITE)
	file.store_string(JSON.stringify(data));file.close()
func published(specs:Array)->void:
	var ids:Array=[]
	for spec:Dictionary in specs:
		ids.append(spec.uuid);published_counts[spec.uuid]=int(published_counts.get(spec.uuid,0))+1
	atomic=atomic and ids.size()==2 and str(ids[0]).left(1)==str(ids[1]).left(1)
	observed.append(ids)
	print("GDB_PUBLICATION ",JSON.stringify(ids))
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty():push_error("--output external directory is required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var logger:=Errors.new();OS.add_logger(logger)
	preload("res://scripts/world3d/runtime_probe_controls.gd").enable_white_materials()
	preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures=true
	var helper:=Fixture.new();helper.folder=output.path_join("resources");helper.content_root=Paths.external_root()
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var records:Array=[];var buildings:Dictionary={}
	for number:int in 4:
		var label:=String.chr(65+number);var owner:="gdb_"+label
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,0,-1),Vector3(1+number*.1,0,-1),Vector3(0,2,1)])
		var data:Dictionary={"materials":[{"null":true}],"meshes":[{"bounds":AABB(Vector3(-1,0,-1),Vector3(2+number*.1,2,2)),"box_size":Vector3.ZERO,"surfaces":[arrays],"materials":[0]}],"entries":[[[0],[0,0]]],"specs":[]}
		var bytes:=var_to_bytes(data)
		for part:String in ["shell","roof"]:
			var record:=helper.box(label+"_"+part,float(number*20))
			record.house_prefab={"version":1,"sha256":Fixture.Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
			record.prefab_locked=true;record.prefab_materials=[]
			record.building={"id":owner,"part":part,"role":"shell" if part=="shell" else "roof_tiles","floor":0,"floor_y":0}
			if part=="roof":record.position[1]=5
			records.append(record)
		buildings[owner]={"version":Directory.Blueprint.VERSION,"parameters":Directory.Blueprint.defaults(),"position":[number*20,0,0],"yaw":0,"parts":{"shell":label+"_shell","roof":label+"_roof"},"signatures":{"shell":"s","roof":"r"},"baked":true}
	var stored:Dictionary=helper.fixture("map",records,{"building_instances":buildings})
	var directory:=Directory.build(stored.path,helper.content_root,records)
	check(directory.ok,"real external native resource directory builds")
	if not directory.ok:print(directory);helper.free();quit(1);return
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var resident_index:=Index.build([])
	for key:String in resident_index:map.set_meta(key,resident_index[key])
	var queue:=Queue.new();map.add_child(queue)
	queue.configure_references(directory,stored.path,helper.content_root)
	for at:int in directory.rows.size():
		var row:Dictionary=directory.rows[at]
		var entry:Dictionary={"record_index":at,"compact_record":directory.extras.rmmo_records[at],"bounds":directory.groups[row.group_id].bounds,"group_id":row.group_id,"asset_path":row.asset_path,"memory_bytes":row.memory_bytes}
		queue.pending.append({"record":entry.compact_record,"path":Deferred.reference_path(entry),"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":1048576,"exclusive":false,"known":true},"draw_order":at*65536,"reference_entry":entry,"reference_prepared":false,"native_reference":true,"group_id":entry.group_id})
	queue.activate(map);queue.ready_job_limit=2;queue._admission.worker_limit=2;queue._admission.byte_limit=512*1024*1024
	queue.published.connect(published)
	queue.set_demand("all",AABB(Vector3(-100,-100,-100),Vector3(200,200,200)),10)
	queue.set_process(false)
	var released:=false;var proof_saved:=false;var deadline:=Time.get_ticks_msec()+240000
	while Time.get_ticks_msec()<deadline:
		queue.set_process(false);queue._process(0)
		if not released and FileAccess.file_exists(output.path_join("continue.flag")):
			queue.a_gate.post();queue.b_gate.post();released=true
			print("GDB_BOTH_GATES_RELEASED")
		if released and not proof_saved and published_counts.has("B_shell") and published_counts.has("C_shell") and published_counts.has("D_shell"):
			var held:Dictionary=queue._jobs.get("reference:building:gdb_A",{})
			var suspended_pending:bool=held.has("worker") and held.worker.is_alive() and not held.get("accepted",false) and not published_counts.has("A_shell")
			check(suspended_pending,"A remains unreturned after both gates posted while B/C/D publish")
			check(queue.starts==["A","B","C","D"],"B/C/D continuously reuse the second slot in original demand order")
			check(queue._jobs.size()==1 and queue._admission.active_workers()==1,"three completed followers release their jobs and leases while A retains exactly one")
			save("progress.json",{"pid":OS.get_process_id(),"suspended_pending":suspended_pending,"gates_released":released,"starts":queue.starts,"publications":observed,"jobs":queue._jobs.size(),"admission":queue._admission.snapshot(),"profile":queue.profile})
			proof_saved=true;print("GDB_FOLLOWERS_COMPLETE")
		if queue.is_complete():break
		await process_frame
	check(proof_saved and queue.is_complete(),"GDB restores A and all four real preparations complete")
	check(atomic and observed.size()==4 and published_counts.size()==8 and published_counts.values().all(func(n):return n==1),"all four two-component buildings publish atomically exactly once")
	check(queue.starts==["A","B","C","D"] and int(queue.profile.get("reference_records",0))==8 and int(queue.profile.get("reference_reads_started",0))>=4,"real resource hydration runs once per source without dummy work or cancellation/readmission")
	check(int(queue.profile.get("max_total_jobs",0))<=2 and queue._admission.peak_workers<=2 and queue._admission.reserved_bytes==0 and queue._admission.count()==0,"fixed two-job two-worker capacity ends with every lease and byte released")
	var summary:Dictionary={"passed":passed,"failed":failed,"atomic":atomic,"starts":queue.starts,"publications":observed,"published_counts":published_counts,"profile":queue.profile,"admission":queue._admission.snapshot(),"engine_errors":logger.errors}
	await queue.quiesce();map.free();helper.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"no engine/script errors")
	summary.passed=passed;summary.failed=failed;save("result.json",summary)
	print("DEFERRED_GDB_REAL_WORKER_PROGRESS passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
