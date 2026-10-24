extends SceneTree
## A real in-flight terrain extraction must not stall independent, ready work.
## The semaphore controls scheduling only; production stream/body code is used.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
const Retirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
const Bvh=preload("res://scripts/world3d/collision_bvh_preparation.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
class Gate extends RefCounted:
	var semaphore:=Semaphore.new()
	func extract(faces:PackedVector3Array)->Dictionary:
		semaphore.wait()
		return Bvh.packet(faces)
var failures:=0
var passed:=0
var gates:Array[Gate]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func box(id:String,position:Vector3=Vector3.ZERO,collision:String="block")->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position),"position":position,"rotation":Vector3.ZERO,"chunk":Stream.chunk_key(position),"chunk_min":Stream.chunk_key(position),"chunk_max":Stream.chunk_key(position),"extras":{"rmmo_collision":collision},"surface_overrides":[],"material_override":null,"cast_shadow":0}
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var preparer:=Preparer.new();preparer.name="StreamCollisionPreparer";map.add_child(preparer)
	var batcher:=Stream.GroundBatcher.new();batcher.name="GroundRenderBatches";map.add_child(batcher);batcher.set_process(false)
	var fort:=Stream.FortCollision.new();map.add_child(fort)
	var head:=box("held_complex_source")
	var vertices:=PackedVector3Array()
	for i:int in 2048:vertices.append_array(PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var cpu:=Cpu.new();cpu.surfaces=[arrays];cpu.materials=[null];cpu.bounds=AABB(Vector3.ZERO,Vector3.ONE);cpu._collision_faces=vertices;head.mesh=cpu
	var ready:=box("ready_box",Vector3(2,0,0))
	var visual:=box("ready_visual",Vector3(3,0,0),"none")
	var building:=box("dependent_building",Vector3(4,0,0),"none")
	var ground:=box("ground_departure",Vector3(3000,0,3000),"none");ground.ground_batch_record={"terrain_mesh":{}}
	var stale:=box("old_monolithic_shape",Vector3(8,0,0));stale.mesh=cpu;stale.shape=BoxShape3D.new()
	var suspended:=box("suspended_building",Vector3(9,0,0),"none")
	var specs:Array=[head,ready,visual,building,ground,stale,suspended]
	map.set_meta("stream_library",specs)
	var indexed:Dictionary=Index.build(specs)
	for field:String in indexed:map.set_meta(field,indexed[field])
	# A missing explicit support is deliberately not a queued source. It proves
	# the bypass checks live dependencies rather than trusting priority alone.
	building.render_building="pending_support_group";building.render_supports=[box("missing_support")]
	suspended.render_building="pending_support_group";suspended.render_supports=building.render_supports
	var terrain:RefCounted=preparer._terrain
	terrain._spec=head;terrain._mesh=cpu;terrain._request_pose=head.transform
	terrain._faces=vertices;terrain._cursor=1
	var first:=ConcavePolygonShape3D.new();first.set_faces(vertices.slice(0,terrain.SLICE_VERTICES));terrain._shapes=[first]
	var body:=Stream._body_shell(head);body.collision_layer=0;body.collision_mask=0;map.add_child(body)
	var shape:=CollisionShape3D.new();shape.shape=first;body.add_child(shape);terrain._body=body
	var gate:=Gate.new();gates.append(gate)
	terrain._thread=Thread.new();terrain._retirement=Retirement.watch(terrain._thread,self,[cpu,vertices])
	check(terrain._thread.start(gate.extract.bind(vertices))==OK,"fixture starts a genuinely blocked extraction worker")
	var old_visual:=Stream._spawn(ground,false,false);map.add_child(old_visual)
	var suspended_node:=Stream._spawn(suspended,false,false);map.add_child(suspended_node);suspended_node.set_meta(Stream.GroundBatcher.SUSPENDED_DRAW,true)
	map.set_meta("stream_meshes",{ground.uuid:old_visual,suspended.uuid:suspended_node});map.set_meta("stream_bodies",{})
	map.set_meta("stream_jobs",specs.duplicate());map.set_meta("stream_cursor",0)
	map.set_meta("stream_target",Vector2i.ZERO);map.set_meta("stream_collision_priority_origin",Vector3.ZERO)
	var ids:Dictionary={}
	for spec:Dictionary in specs:ids[spec.uuid]=true
	map.set_meta("stream_job_catalog",{"jobs":map.get_meta("stream_jobs"),"ids":ids,"cursor":0,"size":specs.size()})
	map.set_meta("stream_collision_priority_partition",{"sentinel":"old untouched tail"})
	map.set_meta("stream_children",map.get_child_count(true))
	return {"map":map,"preparer":preparer,"head":head,"ready":ready,"visual":visual,"building":building,"ground":ground,"stale":stale,"suspended":suspended,"body":body,"gate":gate,"specs":specs}
func turn(f:Dictionary,count:int=1,deadline:int=0,slice_usec:int=100000)->void:
	Stream._sync_work(f.map,f.map,Vector3.ZERO,count,deadline,slice_usec)
func run()->void:
	var previous_prefetch:=Preparer.prefetch_enabled;Preparer.prefetch_enabled=false
	var previous_white:=Controls.white_materials;var previous_discard:=Controls.discard_map_textures
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	create_timer(30).timeout.connect(func():
		for gate:Gate in gates:gate.semaphore.post()
		push_error("ready stream bypass timed out");quit(2)
	)
	var f:=fixture();var map:Node3D=f.map;var terrain:RefCounted=f.preparer._terrain
	Controls.white_materials=false;turn(f)
	check(not map.get_meta("stream_meshes").has(f.ready.uuid),"ordinary textured execution retains its existing serial scheduling")
	Controls.white_materials=true
	Stream.ready_collision_bypass_enabled=false;turn(f)
	check(not map.get_meta("stream_meshes").has(f.ready.uuid),"same-code diagnostic control restores the former scheduling")
	Stream.ready_collision_bypass_enabled=true
	turn(f)
	var meshes:Dictionary=map.get_meta("stream_meshes");var bodies:Dictionary=map.get_meta("stream_bodies")
	check(meshes.has(f.ready.uuid) and bodies.has(f.ready.uuid),"a later primitive publishes while the head extraction is pending")
	check(not meshes.has(f.visual.uuid),"explicit one-item count budget still permits only one successful apply")
	check(is_same(terrain._spec,f.head) and terrain._body==f.body and terrain._cursor==1 and terrain._thread.is_alive(),"ready bypass preserves the blocked terrain cursor, body and worker")
	check(not map.has_meta("stream_collision_priority_partition"),"moving a ready member invalidates the old priority ranges")
	turn(f)
	check(meshes.has(f.visual.uuid) and not bodies.has(f.visual.uuid),"a later collision-free visual also progresses without shape work")
	var jobs:Array=map.get_meta("stream_jobs");var cursor:int=map.get_meta("stream_cursor")
	check(cursor==2 and is_same(jobs[cursor],f.head),"stable movement retains the exact blocked source at the next cursor")
	check(not meshes.has(f.building.uuid) and meshes.has(f.ground.uuid),"missing building support and ground departure cannot bypass the head")
	check(not meshes.has(f.stale.uuid) and is_same(terrain._spec,f.head),"an old monolithic shape cannot bypass or cancel a required sliced terrain preparation")
	var catalog:Dictionary=map.get_meta("stream_job_catalog")
	check(not catalog.ids.has(f.ready.uuid) and not catalog.ids.has(f.visual.uuid) and catalog.ids.has(f.head.uuid) and catalog.cursor==cursor,"only applied UUIDs leave the current job catalog")
	map.set_meta("stream_append_pending",[f.ready,f.ready,f.visual])
	turn(f)
	check(jobs.count(f.ready)==1 and jobs.count(f.visual)==1 and map.get_meta("stream_cursor")==cursor,"same UUID append does not recreate already applied residency work")
	check(meshes[f.suspended.uuid].has_meta(Stream.GroundBatcher.SUSPENDED_DRAW),"a suspended building cannot restore while its exact support is missing")
	var extra:=box("budget_guard",Vector3(6,0,0),"none");jobs.append(extra);catalog.ids[extra.uuid]=true;catalog.size=jobs.size()
	turn(f,1,Time.get_ticks_usec()-1,1)
	check(not meshes.has(extra.uuid),"an expired frame deadline never admits a ready bypass")
	turn(f)
	check(meshes.has(extra.uuid),"the same ready source progresses when the next turn has budget")
	# More than one scan window must eventually be considered. All intervening
	# buildings are independently blocked by their explicit missing support.
	for i:int in 80:
		var blocked:=box("blocked_%d"%i,Vector3.ZERO,"none");blocked.render_building="blocked_group";blocked.render_supports=f.building.render_supports
		jobs.append(blocked);catalog.ids[blocked.uuid]=true
	var distant:=box("ready_beyond_window",Vector3.ZERO,"none");jobs.append(distant);catalog.ids[distant.uuid]=true;catalog.size=jobs.size()
	for i:int in 8:
		turn(f)
		if meshes.has(distant.uuid):break
	check(meshes.has(distant.uuid),"bounded scans continue beyond 64 blocked members without restarting their prefix")
	var support:Dictionary=f.building.render_supports[0]
	var support_node:=Stream._spawn(support,false,false);map.add_child(support_node);meshes[support.uuid]=support_node
	support_node.set_meta(Stream.GroundBatcher.SUSPENDED_DRAW,true)
	map.set_meta("stream_children",map.get_child_count(true))
	for i:int in 4:turn(f)
	check(not meshes.has(f.building.uuid) and meshes[f.suspended.uuid].has_meta(Stream.GroundBatcher.SUSPENDED_DRAW),"an existing but suspended support cannot unlock building creation or restoration")
	Stream.GroundBatcher.restore(support_node)
	for i:int in 8:
		turn(f)
		if meshes.has(f.building.uuid) and not meshes[f.suspended.uuid].has_meta(Stream.GroundBatcher.SUSPENDED_DRAW):break
	check(meshes.has(f.building.uuid) and not meshes[f.suspended.uuid].has_meta(Stream.GroundBatcher.SUSPENDED_DRAW) and terrain._thread.is_alive(),"creation and restoration progress once their exact support is restored")
	f.gate.semaphore.post()
	var stop:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<stop:
		turn(f,12)
		if map.get_meta("stream_jobs",[]).is_empty():break
		await process_frame
	check(map.get_meta("stream_jobs",[]).is_empty() and map.get_meta("stream_chunk",null)==Vector2i.ZERO,"opening the producer gate completes the ordinary plan")
	check(bodies.has(f.head.uuid) and bodies[f.head.uuid].get_child_count()==2 and bodies[f.head.uuid].collision_layer==1,"the original partial terrain becomes one exact enabled two-slice body")
	check(bodies.has(f.stale.uuid) and not f.stale.has("shape") and bodies[f.stale.uuid].get_child_count()==2,"retained monolithic shape is replaced through the original terrain route")
	check(terrain._thread==null and terrain._spec.is_empty() and terrain._body==null and terrain._retirement.is_empty() and not map.has_meta("stream_ready_bypass_scan"),"completion releases worker, private cursor and bypass owner")
	var profile:Dictionary={}
	for field:String in ["applied","scanned","scan_us","max_scan_us"]:profile[field]=map.get_meta("stream_ready_bypass_"+field,0)
	map.free();await process_frame;await process_frame
	f=fixture();map=f.map;terrain=f.preparer._terrain
	f.head.ground_batch_record={"terrain_mesh":{}}
	var held_ground:=Stream._spawn(f.head,true,false);map.add_child(held_ground);held_ground.set_meta(Stream.GroundBatcher.SUSPENDED_DRAW,true)
	map.get_meta("stream_meshes")[f.head.uuid]=held_ground;map.set_meta("stream_children",map.get_child_count(true))
	turn(f)
	check(not map.get_meta("stream_meshes").has(f.ready.uuid) and held_ground.has_meta(Stream.GroundBatcher.SUSPENDED_DRAW),"a suspended ground head still blocks unbound new props")
	var began:=Time.get_ticks_usec()
	Stream._sync_work(map,map,Vector3(3000,0,3000),12,0,100000)
	check(Time.get_ticks_usec()-began<100000 and terrain._spec.is_empty() and not is_instance_valid(f.body),"target change cancels the unpublished body without joining the blocked worker")
	f.gate.semaphore.post()
	stop=Time.get_ticks_msec()+10000
	while terrain._thread!=null and terrain._thread.is_alive() and Time.get_ticks_msec()<stop:await process_frame
	check(terrain._thread!=null and not terrain._thread.is_alive(),"cancelled extraction finishes independently after its gate opens")
	map.free();await process_frame;await process_frame
	Preparer.prefetch_enabled=previous_prefetch
	Controls.white_materials=previous_white;Controls.discard_map_textures=previous_discard
	print("STREAM_READY_BYPASS ",JSON.stringify({"passed":passed,"failures":failures,"profile":profile}))
	quit(1 if failures else 0)
