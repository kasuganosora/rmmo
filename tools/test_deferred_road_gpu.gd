extends SceneTree
## Private-desktop GPU only; real native reference, worker, render and collision.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Plan=preload("res://scripts/world3d/entry_plan.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var folder:=Paths.cache_directory("native_road_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("map.gltf");var doc:=Doc.new();var ids:Array=[]
	for x:float in [0.,500.,1600.]:
		ids.append(doc.add_box("ground",Vector3(x,-.1,0),Vector3(8,.2,8)))
		doc.records[-1].road_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[x,0,0],"grade":[.02,0.]}
	check(doc.save(path)==OK,"save disposable native road map")
	var sha:=FileAccess.get_sha256(path)
	var index:=Index.build(path,Paths.external_root(),doc.records,sha)
	check(index.ok,"build actual source-bound road dependency index")
	if not index.ok:quit(1);return
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader);loader.start(path,Vector3(0,.9,0))
	var loaded:Array=await loader.finished
	var map:Node=loaded[0]
	check(map!=null,"real loader prepares only the initial road")
	if map==null:quit(1);return
	var host:=Node3D.new();root.add_child(host);host.add_child(map)
	var queue:Node=map.get_node("DeferredAssets")
	check(queue.pending.size()==2 and map.get_meta("stream_library").size()==1,"distant roads remain references at initial handoff")
	queue.activate(host);queue.prioritize(Vector3.ZERO);queue.set_process(false);queue._refresh_demanded()
	check(queue._demanded_by_id.has(ids[1]) and not queue._demanded_by_id.has(ids[2]),"background road demand restores former landscape distance without loading all roads")
	var residency:=preload("res://scripts/world3d/asset_residency.gd").new()
	residency._deferred=queue;residency._host=host
	var distant_model:={"bounds":AABB(Vector3(499,-1,-1),Vector3(2,2,2))}
	check(not residency._needed(distant_model),"road-only landscape demand does not pin unrelated distant model resources")
	queue.set_demand("probe",Plan.create(Vector3(500,.9,0)).safety_clip,-2)
	check(residency._needed(distant_model),"ordinary target demand still retains required models at the same location")
	residency.free()
	queue.set_demand_scope(["probe"])
	Stream.set_entry_scope(map,Plan.create(Vector3(500,.9,0)).safety_clip)
	var deadline:=Time.get_ticks_msec()+30000
	while not queue.is_idle() and Time.get_ticks_msec()<deadline:
		Stream.sync(map,host,Vector3(500,.9,0),Stream.LOAD_BUDGET)
		await process_frame
	check(queue.error.is_empty() and queue.path_errors.is_empty() and queue.instance_errors.is_empty(),"native road worker and publication complete without errors")
	check(int(queue.profile.get("native_surface_records",0))==1,"road surface arrays were prepared on the reference worker")
	check(queue.pending.size()==1 and queue.pending[0].record.uuid==ids[2],"scoped road request leaves unrelated native geometry deferred")
	while not Stream.entry_scope_ready(map) and Time.get_ticks_msec()<deadline:
		Stream.sync(map,host,Vector3(500,.9,0),Stream.LOAD_BUDGET);await process_frame
	check(Stream.entry_scope_ready(map) and Stream.nearby_collision_ready(map,Vector3(500,.9,0)),"native road has real GPU draw and local collision before readiness")
	var spec:Dictionary=map.get_meta("stream_by_id").get(ids[1],{})
	var expected:MeshInstance3D=doc._mesh(doc.records[1])
	# Compare the retained authoring arrays on both sides. Reading the ordinary
	# ArrayMesh back from the GPU quantizes normals/tangents, unlike CPU specs.
	var cpu_expected:Mesh=preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(expected.mesh)
	var equal:bool=not spec.is_empty() and spec.mesh.get_surface_count()==cpu_expected.get_surface_count()
	if equal:
		for slot in cpu_expected.get_surface_count():
			equal=equal and var_to_bytes(spec.mesh.surface_get_arrays(slot))==var_to_bytes(cpu_expected.surface_get_arrays(slot))
	check(equal,"published worker geometry exactly matches ordinary authored road generation")
	expected.free()
	await physics_frame;await physics_frame;await process_frame
	var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(500,3,0),Vector3(500,-3,0),1))
	check(not hit.is_empty(),"published native road supports a real physics ray")
	check(queue._doc.load_surface_arrays.is_empty() and queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"publication releases temporary arrays and admission ownership")
	check(FileAccess.get_sha256(path)==sha,"loading never rewrites authored road map")
	await queue.quiesce();host.free()
	for i in 3:await process_frame
	print("DEFERRED_ROAD_GPU_FINISHED failures=",failures)
	quit(1 if failures else 0)
