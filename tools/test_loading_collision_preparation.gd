extends SceneTree
## Scene/physics regression; run only through run_godot_background.py.
## Temporary in-memory meshes. No user map or asset writes.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
const AT:=Vector3(16,.9,16)
const AWAY:=Vector3(512,.9,16)
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->bool:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok

func large(id:String)->Dictionary:
	# About 19k exact triangles, including an authored hole. No terrain record:
	# the imported ordinary-static eligibility path must also use the preparer.
	var faces:=PackedVector3Array()
	for z in 98:
		for x in 98:
			if x in range(12,16) and z in range(12,16):continue
			var a:=Vector3(x*.3,0,z*.3);var b:=a+Vector3(.3,0,0)
			var c:=a+Vector3(.3,0,.3);var d:=a+Vector3(0,0,.3)
			faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var mesh:=Cpu.new();mesh.surfaces=[arrays];mesh.materials=[null]
	mesh.bounds=AABB(Vector3.ZERO,Vector3(29.4,.01,29.4))
	return {"uuid":id,"mesh":mesh,"collision_mesh":mesh,"transform":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"native_visual":false,"extras":{"rmmo_collision":"walk","surface_id":"ground"}}

func small(id:String,position:Vector3)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
	var pose:=Transform3D(Basis.IDENTITY,position);var bounds:AABB=pose*mesh.get_aabb()
	return {"uuid":id,"mesh":mesh,"collision_mesh":mesh,"transform":pose,"position":position,"rotation":Vector3.ZERO,"chunk":Stream.chunk_key(position),"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end),"native_visual":false,"extras":{}}

func fixture(id:String)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var spec:=large(id);var specs:Array=[spec]
	map.set_meta("stream_library",specs)
	var index:=Index.build(specs)
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_children",map.get_child_count())
	return {"host":host,"map":map,"spec":spec}

func body(fixture_:Dictionary)->StaticBody3D:
	return fixture_.map.get_meta("stream_bodies",{}).get(fixture_.spec.uuid) as StaticBody3D

func unpublished_disabled(fixture_:Dictionary)->bool:
	for child:Node in fixture_.host.get_children():
		if child is StaticBody3D and str(child.get_meta("uuid",""))==str(fixture_.spec.uuid) and child!=body(fixture_):
			if child.collision_layer!=0 or child.collision_mask!=0:return false
	return true

func complete(fixture_:Dictionary,at:Vector3)->bool:
	return fixture_.map.get_meta("stream_chunk",Vector2i(2147483647,2147483647))==Stream.chunk_key(at) and fixture_.map.get_meta("stream_append_pending",[]).is_empty()

func settle(fixture_:Dictionary,at:Vector3,budget:int=Stream.LOAD_BUDGET)->bool:
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(fixture_.map,fixture_.host,at,budget)
		if complete(fixture_,at):return true
		await process_frame
	return false

func exact_body(fixture_:Dictionary,label:String)->void:
	var collider:=body(fixture_)
	if not check(is_instance_valid(collider),label+" publishes body"):return
	var faces:=PackedVector3Array();var shape_count:=0
	for child:Node in collider.get_children():
		if not child is CollisionShape3D:continue
		shape_count+=1
		if child.shape is ConcavePolygonShape3D:faces.append_array(child.shape.get_faces())
	check(shape_count>1,label+" uses exact multiple shapes rather than monolithic bypass")
	check(faces==fixture_.spec.mesh.collision_faces(),label+" preserves every triangle, winding and authored hole")
	check(collider.collision_layer==1 and collider.collision_mask==1 and collider.get_meta("uuid")==fixture_.spec.uuid,label+" publishes once with identity and layers")
	check(not fixture_.spec.has("prepared_body"),label+" consumes unpublished ownership")

func loading_continuation(alternate:bool)->void:
	var label:="12/512 continuation" if alternate else "512 continuation"
	var world:=fixture("alternating" if alternate else "loading")
	Stream.sync(world.map,world.host,AT,Stream.FRAME_BUDGET if alternate else Stream.LOAD_BUDGET)
	check(body(world)==null and not Stream.nearby_collision_ready(world.map,AT),label+" initial CPU preparation does not expose nearby readiness")
	var pending:=0;var hidden:=true;var progress:=false
	var deadline:=Time.get_ticks_msec()+20000
	for frame in 1200:
		if Time.get_ticks_msec()>deadline:break
		hidden=hidden and unpublished_disabled(world)
		if body(world)==null:
			pending+=1
			if Stream.nearby_collision_ready(world.map,AT):hidden=false
		if complete(world,AT):progress=true;break
		await process_frame
		var budget:int=Stream.FRAME_BUDGET if alternate and frame%2==0 else Stream.LOAD_BUDGET
		Stream.sync(world.map,world.host,AT,budget)
	check(pending>0 and hidden,label+" partial/unpublished bodies stay disabled and unready")
	check(progress,label+" reaches settled target without restarting worker/slices forever")
	if progress:exact_body(world,label)
	world.host.free()

func appends_do_not_starve()->void:
	var world:=fixture("loading_append")
	Stream.sync(world.map,world.host,AT,Stream.LOAD_BUDGET)
	var ready_frame:=-1;var valid:=true;var hidden:=true
	for frame in 48:
		var result:Dictionary=Stream.append_specs(world.map,[small("append_%d"%frame,Vector3(1500+frame*2,1,0))])
		valid=valid and result.ok
		Stream.sync(world.map,world.host,AT,Stream.LOAD_BUDGET)
		hidden=hidden and unpublished_disabled(world)
		if is_instance_valid(body(world)) and ready_frame<0:ready_frame=frame
		await process_frame
	check(valid,"continuous same-target appends remain valid")
	check(hidden and ready_frame>=0 and ready_frame<40,"512 completes original exact body before append stream ends (frame %d)"%ready_frame)
	var settled:=await settle(world,AT)
	check(settled and world.map.get_meta("stream_library",[]).size()==49 and world.map.get_meta("stream_by_id",{}).size()==49,"512 eventually absorbs all appends once and empties pending")
	if settled:exact_body(world,"512 append")
	world.host.free()

func target_cancel(prepared_waiting:bool)->void:
	var label:="prepared-waiting" if prepared_waiting else "worker-or-partial"
	var world:=fixture("cancel_ready" if prepared_waiting else "cancel_pending")
	Stream.sync(world.map,world.host,AT,Stream.LOAD_BUDGET)
	var preparer:Node=world.map.get_node_or_null("StreamCollisionPreparer")
	if not check(preparer!=null and body(world)==null,label+" fixture entered real loading preparer"):
		world.host.free();return
	if prepared_waiting:
		# Stop immediately before the production Stream._apply handoff. This
		# isolates cancellation of a fully prepared but still disabled body.
		var deadline:=Time.get_ticks_msec()+20000
		while not preparer.prepare(world.spec,world.host) and Time.get_ticks_msec()<deadline:await process_frame
		if not check(is_instance_valid(world.spec.get("prepared_body")),"fixture owns complete body awaiting publication"):
			world.host.free();return
		check(world.spec.prepared_body.collision_layer==0 and world.spec.prepared_body.collision_mask==0 and not Stream.nearby_collision_ready(world.map,AT),"complete unpublished body remains disabled/unready")
	var unpublished:Variant=world.spec.get("prepared_body",preparer._terrain._body)
	var previous_id:int=unpublished.get_instance_id() if is_instance_valid(unpublished) else 0
	Stream.sync(world.map,world.host,AWAY,Stream.LOAD_BUDGET)
	check(not world.spec.has("prepared_body") and preparer._terrain._body==null and preparer._terrain._spec.is_empty(),label+" target switch discards unpublished ownership")
	check(previous_id==0 or not is_instance_id_valid(previous_id),label+" target switch frees disabled body")
	check(body(world)==null,label+" cancelled source never becomes active collision")
	check(await settle(world,AWAY),label+" destination settles after cancellation")
	check(await settle(world,AT),label+" return can restart and finish cancelled source")
	if is_instance_valid(body(world)):exact_body(world,label+" return")
	world.host.free()

func synchronous_compatibility()->void:
	# The current optimization intentionally keeps budget=0's existing sync
	# route; no assertion requires slicing or new worker APIs for this route.
	for interrupt in [false,true]:
		var world:=fixture("sync_after_worker" if interrupt else "sync_direct")
		if interrupt:Stream.sync(world.map,world.host,AT,Stream.FRAME_BUDGET)
		Stream.sync(world.map,world.host,AT,0)
		check(complete(world,AT) and is_instance_valid(body(world)) and Stream.nearby_collision_ready(world.map,AT),"budget0 completes synchronously, interrupted=%s"%interrupt)
		check(not world.spec.has("prepared_body") and unpublished_disabled(world),"budget0 leaves no unpublished ownership, interrupted=%s"%interrupt)
		var active:=0
		for child:Node in world.host.get_children():
			if child is StaticBody3D and child.get_meta("uuid","")==world.spec.uuid:
				active+=1
		check(active==1,"budget0 has one physical body after handoff, interrupted=%s"%interrupt)
		world.host.free()

func run()->void:
	create_timer(150).timeout.connect(func():push_error("loading collision preparation test timeout");quit(2))
	var previous:=Preparer.terrain_slicing_enabled;Preparer.terrain_slicing_enabled=true
	await loading_continuation(false)
	await loading_continuation(true)
	await appends_do_not_starve()
	await target_cancel(false)
	await target_cancel(true)
	synchronous_compatibility()
	Preparer.terrain_slicing_enabled=previous
	await process_frame
	print("LOADING_COLLISION_PREPARATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
