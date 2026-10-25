extends SceneTree
## Reproduce a service child forcing full adoption and residency selection.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture(count:int)->Node3D:
	var map:=Node3D.new();root.add_child(map)
	var cpu:=Cpu.capture(BoxMesh.new());var library:Array=[];var meshes:Dictionary={}
	for i:int in count:
		var id:="existing%d"%i
		var spec:={"uuid":id,"mesh":cpu,"transform":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"extras":{"rmmo_collision":"none","building":{"id":id}},"native_visual":true}
		library.append(spec)
		var mesh:=MeshInstance3D.new();mesh.name=id;mesh.set_meta("stream_instance",true);map.add_child(mesh);meshes[id]=mesh
	map.set_meta("stream_library",library);map.set_meta("stream_meshes",meshes)
	var data:=Index.build(library)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_target",Vector2i.ZERO);map.set_meta("stream_chunk",Vector2i.ZERO)
	map.set_meta("stream_children",map.get_child_count(true))
	return map
func reset_settled(map:Node)->void:
	for key:String in ["stream_candidates","stream_candidate_work","stream_plan_bins","stream_job_catalog"]:map.remove_meta(key)
	map.set_meta("stream_jobs",[]);map.set_meta("stream_cursor",0)
	map.set_meta("stream_chunk",Vector2i.ZERO);map.set_meta("stream_target",Vector2i.ZERO)
	map.set_meta("stream_children",map.get_child_count(true))
func tick(map:Node)->void:Stream._sync_work(map,map,Vector3.ZERO,Stream.FRAME_BUDGET,Time.get_ticks_usec()+1,3000)
func source(id:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=id;node.mesh=BoxMesh.new()
	node.set_meta("extras",{"uuid":id,"rmmo_collision":"none","building":{"id":"new_building","floor":2},"fixture":{"id":"door","kind":"door","pivot":[0,0,0],"angle":90,"open":0.4}})
	return node
func correctness()->void:
	Stream.incremental_adoption_enabled=true
	var map:=fixture(2);tick(map)
	var branch:=Node3D.new();branch.position=Vector3(3,4,5);branch.rotation.y=.7
	var a:=source("new_a");a.position=Vector3(2,1,0);branch.add_child(a)
	var b:=source("new_b");b.position=Vector3(-2,0,0);branch.add_child(b);map.add_child(branch)
	var expected_pose:=a.global_transform;var expected_mesh:=a.mesh;var expected_extras:Dictionary=a.get_meta("extras")
	tick(map)
	var by_id:Dictionary=map.get_meta("stream_by_id")
	check(by_id.has("new_a") and by_id.has("new_b") and map.get_meta("stream_library").size()==4,"new nested sources are adopted exactly once")
	var adopted:Dictionary=by_id.get("new_a",{})
	check(adopted.get("transform",Transform3D.IDENTITY).is_equal_approx(expected_pose) and adopted.get("mesh")==expected_mesh and adopted.get("extras")==expected_extras,"world pose, mesh, floor and active door metadata are preserved")
	check(map.get_meta("stream_adoption_profile").delta_roots==1 and map.get_meta("stream_adoption_profile").full_scans==0,"nested source arrival visits only its new subtree")
	reset_settled(map)
	var deleted:=source("removed_before_adopt");map.add_child(deleted);deleted.free();tick(map)
	check(not by_id.has("removed_before_adopt"),"an arrival removed before adoption adds no spec")
	var internal:=source("internal");map.add_child(internal,false,Node.INTERNAL_MODE_BACK);tick(map)
	check(not by_id.has("internal"),"internal children remain excluded like the legacy collector")
	reset_settled(map)
	var old_count:=map.get_child_count(true)
	root.remove_child(map);map.remove_child(branch);branch.free()
	var offline:=source("offline");map.add_child(offline);root.add_child(map)
	check(map.get_child_count(true)==old_count,"offline remove/add fixture preserves the direct count")
	tick(map)
	check(by_id.has("offline"),"leaving and reentering the tree reconciles offline changes at equal count")
	reset_settled(map)
	var explicit_source:=source("explicit_nested");var holder:=Node3D.new();map.add_child(holder);tick(map);holder.add_child(explicit_source)
	map.set_meta("stream_children",-1);tick(map)
	check(map.get_meta("stream_by_id").has("explicit_nested"),"explicit invalidation still discovers changes below existing roots")
	var watch:WeakRef=weakref(map.get_meta("runtime_adoption_changes"));map.free()
	check(watch.get_ref()==null,"change tracker and weak roots do not retain a destroyed map")
	map=fixture(2);tick(map)
	var meshes:Dictionary=map.get_meta("stream_meshes")
	Stream._drop(meshes,"existing0",meshes.existing0);tick(map)
	check(map.has_meta("stream_candidates") or not map.has_meta("stream_chunk"),"dropping an owner whose spec remains keeps the legacy repair plan")
	reset_settled(map);meshes.existing1.free();tick(map)
	check(map.has_meta("stream_candidates") or not map.has_meta("stream_chunk"),"foreign deletion of a registered owner still requests repair")
	map.free()
	map=fixture(3500);tick(map);map.set_meta("stream_children",-1);tick(map)
	check(map.has_meta("stream_candidates") and map.get_meta("stream_candidates").size()==3500,"explicit invalidation rebuilds residency even without new source nodes")
	map.free()
	map=fixture(3500);tick(map)
	var candidates:Array=map.get_meta("stream_library").duplicate()
	map.remove_meta("stream_chunk");map.set_meta("stream_candidates",candidates);map.set_meta("stream_plan_cursor",20);map.set_meta("stream_plan_bins",[[],[],[],[],[]]);map.set_meta("stream_plan_ids",{})
	var helper:=Node.new();helper.set_meta("stream_instance",true);map.add_child(helper);tick(map)
	check(map.has_meta("stream_candidates") and is_same(map.get_meta("stream_candidates"),candidates) and int(map.get_meta("stream_plan_cursor"))>20,"service arrival preserves the active candidate array and advances its cursor")
	map.free()
func benchmark()->Array:
	var trials:Array=[]
	for enabled:bool in [false,true,true,false]:
		Stream.incremental_adoption_enabled=enabled
		var map:=fixture(3500);map.set_meta("native_graph_prepared",true);tick(map)
		var spans:Array=[];var selected:=0;var transaction_us:=0
		for i:int in 20:
			reset_settled(map)
			var begin_transaction:=Time.get_ticks_usec()
			var helper:=Node.new();helper.set_meta("stream_instance",true);map.add_child(helper)
			var began:=Time.get_ticks_usec();tick(map);spans.append(Time.get_ticks_usec()-began)
			selected+=map.get_meta("stream_candidates",[]).size()
			helper.free();transaction_us+=Time.get_ticks_usec()-begin_transaction
		var profile:Dictionary=map.get_meta("stream_adoption_profile",{}).duplicate()
		var cleanup:=Time.get_ticks_usec();map.free();cleanup=Time.get_ticks_usec()-cleanup
		var total:=0
		for span:int in spans:total+=span
		spans.sort()
		trials.append({"incremental":enabled,"rounds":20,"sync_us":total,"max_us":spans[-1],"selected":selected,"transaction_us":transaction_us,"cleanup_us":cleanup,"profile":profile})
		check(selected==0 if enabled else selected==70000,"service churn has the expected candidate work in diagnostic mode "+str(enabled))
	return trials
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var baseline:bool="--expect-baseline" in OS.get_cmdline_user_args()
	Stream.incremental_adoption_enabled=not baseline
	var map:=fixture(3500)
	Stream._sync_work(map,map,Vector3.ZERO,Stream.FRAME_BUDGET)
	var helper:=Node.new();helper.name="NewService";helper.set_meta("stream_instance",true);map.add_child(helper)
	var began:=Time.get_ticks_usec()
	Stream._sync_work(map,map,Vector3.ZERO,Stream.FRAME_BUDGET,Time.get_ticks_usec()+1,3000)
	var elapsed:=Time.get_ticks_usec()-began
	var selected:int=map.get_meta("stream_candidates",[]).size()
	var preserved:bool=map.has_meta("stream_chunk") and map.get_meta("stream_chunk")==Vector2i.ZERO and not map.has_meta("stream_candidates")
	check(not preserved if baseline else preserved,"service-only arrival "+("reproduces full replan" if baseline else "keeps settled residency without candidates"))
	var report:={"baseline":baseline,"children":3500,"helper_sync_us":elapsed,"selected":selected,"adopt":map.get_meta("stream_adopt_ms",{}),"profile":map.get_meta("stream_adoption_profile",{})}
	map.free()
	if not baseline:
		correctness();report.trials=benchmark()
	report.checks=checks;report.failures=failures
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAM_CHILD_ADOPTION ",JSON.stringify(report))
	quit(1 if failures else 0)
