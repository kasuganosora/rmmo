extends SceneTree
## Private-desktop GPU: frozen structures remain complete spatial transactions.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Plan=preload("res://scripts/world3d/entry_plan.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Source=preload("res://tools/structure_dependency_fixture.gd")
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
	else:passed+=1
func wait_target(map:Node,host:Node3D,queue:Node,at:Vector3)->void:
	var plan:=Plan.create(at)
	queue.set_demand("target",plan.safety_clip,-2)
	queue.set_demand_scope(["target"])
	Stream.set_entry_scope(map,plan.safety_clip)
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(map,host,at,Stream.LOAD_BUDGET)
		await process_frame
		if queue.is_idle() and Stream.entry_scope_ready(map):break
	check(queue.is_idle() and Stream.entry_scope_ready(map),"target waits for complete draw and collision readiness at "+str(at.x))
	check(queue.error.is_empty() and queue.path_errors.is_empty() and queue.instance_errors.is_empty(),"target publication has no resource or instance failures")
func ray(host:Node3D,at:Vector3)->Dictionary:
	await physics_frame;await physics_frame;await process_frame
	return host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3(0,6,0),at-Vector3(0,6,0),1))
func run()->void:
	create_timer(100).timeout.connect(func():quit(2))
	var folder:=Paths.cache_directory("native_structure_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("map.gltf");var doc:=Doc.new()
	doc.records=Source.records(Paths.external_root())
	doc.records.append(Source.wall("out_of_view",1600,"remote_ring"))
	doc.map_meta=Source.metadata(doc.records)
	check(doc.save(path)==OK,"save disposable complete frozen structure definitions")
	var sha:=FileAccess.get_sha256(path)
	var index:=Index.build(path,Paths.external_root(),doc.records,sha)
	check(index.ok,"build actual source-bound frozen structure directory")
	if not index.ok:quit(1);return
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader);loader.start(path,Vector3(0,.9,4))
	var loaded:Array=await loader.finished
	var map:Node=loaded[0]
	check(map!=null,"real loader prepares only the near frozen module")
	if map==null:quit(1);return
	var host:=Node3D.new();root.add_child(host);host.add_child(map)
	var queue:Node=map.get_node("DeferredAssets")
	check(queue._reference_proof!=null and queue._reference_index.is_read_only(),"real loader hands the sealed directory and proof to deferred workers")
	check(queue.pending.size()==6 and map.get_meta("stream_library").size()==1,"far walls, gate leaves and bridge stay compact at initial handoff")
	queue.activate(host);queue.prioritize(Vector3.ZERO);queue.set_process(false);queue._refresh_demanded()
	check(queue._demanded_by_id.has("whole_bridge") and queue._demanded_by_id.has("far_wall") and not queue._demanded_by_id.has("out_of_view"),"structure background demand preserves landscape distance without loading the whole map")
	queue.set_demand_scope(["building_render"]);queue._refresh_demanded()
	check(queue._demanded.is_empty(),"building-only demand cannot accidentally widen to fortification groups")
	queue.set_demand_scope(["structure_render"])
	var residency:=preload("res://scripts/world3d/asset_residency.gd").new()
	residency._deferred=queue;residency._host=host
	check(not residency._needed({"bounds":AABB(Vector3(900,0,0),Vector3.ONE)}),"structure-only visual ticket does not pin unrelated distant models")
	residency.free()
	var groups:Array=[]
	queue.published.connect(func(specs:Array):
		var ids:Array=[]
		for spec:Dictionary in specs:ids.append(str(spec.uuid).get_slice("__",0))
		groups.append(ids))
	await wait_target(map,host,queue,Vector3(520,.9,4))
	var gates:=Fixtures.list_runtime(map,"fortification:test_ring")
	check(gates.size()==1 and gates[0].members.size()==2,"both leaves of one gate publish as a complete runtime namespace")
	var atomic:=false
	for ids:Array in groups:
		if ids.has("gate_left") or ids.has("gate_right"):
			atomic=ids.has("gate_left") and ids.has("gate_right")
	check(atomic,"published signal exposes both gate leaves in the same transaction")
	check(Fixtures.list_runtime(map,"fortification:other_ring").is_empty(),"same fixture id in another owner remains deferred")
	check(not (await ray(host,Vector3(512,2,0))).is_empty(),"deferred wall creates real nearby physics")
	check(Fixtures.set_runtime(map,"fortification:test_ring","main_gate",1.,0.).ok,"deferred complete gate still accepts runtime open interaction")
	var opened:=true
	for spec:Dictionary in map.get_meta("stream_library"):
		if spec.extras.get("fixture",{}).get("id","")=="main_gate":opened=opened and is_equal_approx(float(spec.extras.fixture.open),1.)
	check(opened,"both leaves receive the same open state")
	await wait_target(map,host,queue,Vector3(900,.9,0))
	check(not (await ray(host,Vector3(900,0,0))).is_empty(),"deferred frozen bridge supports real destination collision")
	check(not map.get_meta("stream_by_id").has("out_of_view") and queue.pending.size()==2,"target request leaves the unrelated gate and out-of-view wall deferred")
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"complete namespace publication releases all worker charges")
	check(int(queue.profile.get("reference_proof_jobs",0))>=3 and int(queue.profile.get("reference_full_scan_jobs",0))==0,"actual gate, wall and bridge jobs reuse ownership proof without full-map rescans")
	check(FileAccess.get_sha256(path)==sha,"streaming and gate interaction never rewrite author map")
	await queue.quiesce();host.free()
	for i in 3:await process_frame
	print("DEFERRED_STRUCTURE_GPU_FINISHED passed=",passed," failures=",failures)
	quit(1 if failures else 0)
