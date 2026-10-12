extends "res://tools/test_collision_basis_preparation.gd"
## Real GLB -> derived collision -> verified map instance -> live physics ->
## ordinary visual publication. Run on the private desktop, never a user map.
const Adapter=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Residency=preload("res://scripts/world3d/collision_instance_residency.gd")
const Builder=preload("res://scripts/world3d/collision_asset_builder.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const StreamIndex=preload("res://scripts/world3d/stream_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
var files:SceneTree

func worker(callable:Callable)->Dictionary:
	var thread:=Thread.new();var code:int=thread.start(callable)
	if code!=OK:return {"ok":false,"reason":"test_thread"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()

func write_glb(path:String)->void:
	var faces:PackedVector3Array=source().collision_faces()
	# glTF is counterclockwise; Godot's importer restores clockwise winding.
	for at in range(0,faces.size(),3):
		var second:=faces[at+1];faces[at+1]=faces[at+2];faces[at+2]=second
	var binary:=faces.to_byte_array()
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
		"nodes":[{"name":"Fixture","children":[1,2]},
			{"name":"Solid","mesh":0,"extras":{"rmmo_collision":"block"}},
			{"name":"Decoration","mesh":0,"translation":[24,0,0],"extras":{"rmmo_collision":"none"}}],
		"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],
		"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":faces.size(),"min":[-6,0,-4],"max":[6,4,4]}],
		"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":binary.size()}],"buffers":[{"byteLength":binary.size()}]}
	var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var output:=FileAccess.open(path,FileAccess.WRITE)
	output.store_32(0x46546c67);output.store_32(2);output.store_32(28+json.size()+binary.size())
	output.store_32(json.size());output.store_32(0x4e4f534a);output.store_buffer(json)
	output.store_32(binary.size());output.store_32(0x004e4942);output.store_buffer(binary);output.close()

func initialize_index(host:Node3D)->void:
	host.set_meta("stream_library",[])
	var data:=StreamIndex.build([])
	for key:String in data:host.set_meta(key,data[key])

func run()->void:
	create_timer(120).timeout.connect(func():push_error("collision residency GPU timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	files=Base.Files.new();files.content_root=Paths.external_root();files.folder=Paths.cache_directory("collision_residency_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("openings.glb");write_glb(path)
	var estimate:=Builder.estimate(path,files.content_root);var ledger:=Admission.new()
	if not check(not estimate.is_empty() and ledger.reserve(path,estimate),"offline collision build has a real resource reservation"):finish(errors);return
	var built:=await worker(Builder.build.bind(path,files.content_root,estimate.estimated_bytes));ledger.park(path)
	check(built.get("ok",false),"real floor and doorway GLB builds independent exact collision asset")
	if not built.get("ok",false):print(built);Drainer.dispose_result(built);ledger.release(path);finish(errors);return
	Drainer.dispose_result(built);ledger.release(path)
	var record:Dictionary={"uuid":"entry_fixture","kind":"asset","asset_path":path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":""}
	await map_case(record,"identity",errors)
	record=record.duplicate(true);record.position=[12,1,-8];record.rotation=[0,36,0];record.size=[1.3,1.1,.85]
	await map_case(record,"transformed",errors)
	record=record.duplicate(true);record.collision="none"
	await map_case(record,"decoration",errors)
	finish(errors)

func map_case(record:Dictionary,label:String,errors:RefCounted)->void:
	print("CASE ",label)
	var ledger:=Admission.new()
	var fixture:Dictionary=files.fixture("entry_"+label,[record])
	check(Index.build(fixture.path,files.content_root,[record]).ok,"authoritative temporary map index builds")
	var issued:=Index.read_for_loading(fixture.path,files.content_root)
	if not check(issued.ok,"loading issues real map ownership proof"):return
	var requests:Array=Index.select(issued.index,[]).deferred_entries
	var plan:=await worker(Adapter.plan.bind(issued.index,requests,fixture.path,files.content_root,issued.proof))
	if not check(plan.get("ok",false),"worker plans verified collision-only instance closure"):print(plan);return
	# The adapter does not import or publish a visual scene.
	if not check(ledger.reserve("collision_batch",plan),"runtime collision batch receives full bounded admission"):return
	var packet:=await worker(Adapter.prepare.bind(plan,plan.estimated_bytes))
	ledger.park("collision_batch")
	if not check(packet.get("ok",false),"worker prepares typed instance batch without render import"):print(packet);ledger.release("collision_batch");return
	if record.collision=="none":await exercise_decoration(packet.batch,record,fixture.path)
	else:await exercise(packet.batch,record,fixture.path,errors)
	packet.clear();ledger.release("collision_batch")

func exercise(batch:RefCounted,record:Dictionary,map_path:String,_errors:RefCounted)->void:
	# Runtime assertions below intentionally use the public Store API.
	var pose:=Transform3D(Basis.from_euler(Index._vec(record.rotation)*PI/180.0).scaled_local(Index._vec(record.size)),Index._vec(record.position))
	var live:=world();initialize_index(live.host)
	var store:=Residency.new();live.host.add_child(store)
	store.configure(live.host,map_path,FileAccess.get_sha256(map_path),1)
	check(not store.enqueue(batch,2).ok,"stale transfer epoch cannot install collision")
	var queued:Dictionary=store.enqueue(batch,1)
	if not check(queued.ok,"map-owned store accepts verified current-epoch batch"):print(queued);live.viewport.free();return
	var clip:=pose*AABB(Vector3(-6,-2,-4),Vector3(12,8,8))
	check(not store.readiness(clip,1).ok,"queued CPU data is not physics ready")
	var deadline:=Time.get_ticks_msec()+10000
	var checked_stamp:=false
	while not store.readiness(clip,1).ok and Time.get_ticks_msec()<deadline:
		store.step(1500)
		if store.debug_snapshot().installed>0 and not checked_stamp:
			checked_stamp=true;check(not store.readiness(clip,1).ok,"same-frame publication cannot grant physics readiness")
		await physics_frame;await process_frame
	check(store.readiness(clip,1).ok,"complete collision becomes ready after physics synchronization")
	check(not store.readiness(clip,2).ok,"readiness receipt cannot cross transfer epochs")
	check(live.host.get_meta("stream_library").is_empty() and live.host.get_meta("stream_by_id").is_empty(),"collision-first stage publishes no dummy visual index entries")
	var before:=queries(live,pose)
	check(before.rays.floor.hit and not before.rays.hole.hit and not before.rays.door_front.hit and not before.rays.door_back.hit,"collision-only stage preserves actual floor hole and doorway")
	var body:StaticBody3D
	for child:Node in live.host.get_children():
		if child is StaticBody3D:body=child;break
	if not check(body!=null,"live collision is independently owned by the map"):live.viewport.free();return
	var body_id:=body.get_instance_id()
	geometry_equal(body,source(),pose,"collision-first exact basis")
	var baseline:=world();reference_body(baseline.host,source(),pose)
	var start:=pose*Vector3(-3,0,-2)+Vector3.UP*.902
	var a:=player(baseline.host,start);var b:=player(live.host,start)
	await physics_frame;await physics_frame
	var equal:=true;var grounded:=0
	for tick:int in 12:
		await physics_frame
		a.velocity=pose.basis*Vector3(.3,0,0)+Vector3.DOWN*.5;b.velocity=a.velocity
		a.move_and_slide();b.move_and_slide()
		equal=equal and a.is_on_floor()==b.is_on_floor() and a.global_position.distance_to(b.global_position)<.002
		if a.is_on_floor() and b.is_on_floor():grounded+=1
	check(equal and grounded>=11,"capsule keeps reference floor contact and trajectory before visual import")
	a.free();b.free();baseline.viewport.free()
	# Only now perform the ordinary expensive visual import.
	var prepared:=await worker(Deferred.prepare_scene.bind(record.asset_path,FileAccess.get_sha256(record.asset_path),null,{},true,files.content_root,true))
	if not check(prepared.get("scene") is Node3D,"ordinary deferred render import completes after physics is usable"):Drainer.dispose_result(prepared);live.viewport.free();return
	var doc:=Document.new();var holder:=doc._asset(record,prepared);prepared.erase("scene")
	var additions:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,additions)
	var partial:=Stream.append_specs(live.host,[additions[0]])
	check(not partial.ok and live.host.get_meta("stream_library").is_empty() and is_instance_valid(body),"partial namespace promotion has no publication or collision side effects")
	var wrong:Array=additions.duplicate(true);wrong[0].transform.origin.x+=1
	check(not Stream.append_specs(live.host,wrong).ok,"changed instance pose cannot reuse old collision")
	var changed:Array=additions.duplicate(true);changed[0].extras.rmmo_collision="none"
	check(not Stream.append_specs(live.host,changed).ok,"changed collision mode cannot reuse old body")
	var appended:=Stream.append_specs(live.host,additions)
	check(appended.ok,"ordinary visual namespace promotes exact existing collision")
	if not appended.ok:print(appended)
	var bodies:Dictionary=live.host.get_meta("stream_bodies",{})
	check(bodies.size()==1 and bodies.values()[0].get_instance_id()==body_id,"publication reuses the same body with no duplicate or detach")
	Stream.sync(live.host,live.host,pose.origin)
	check(not live.host.get_meta("stream_meshes",{}).is_empty() and bodies.values()[0].get_instance_id()==body_id,"normal stream displays real visuals and retains promoted body")
	store.free()
	check(is_instance_valid(body) and body.is_inside_tree() and body.collision_layer==1,"disposing collision store cannot free promoted body")
	await physics_frame;await process_frame
	var after:=queries(live,pose)
	check(before==after,"rays and sphere sweeps remain identical through promotion")
	holder.free();Drainer.dispose_result(prepared);live.viewport.free()
	var cancelled:=world();initialize_index(cancelled.host)
	var abandoned:=Residency.new();cancelled.host.add_child(abandoned)
	abandoned.configure(cancelled.host,map_path,FileAccess.get_sha256(map_path),3)
	check(abandoned.enqueue(batch,3).ok,"separate cancelled transfer owns its own collision installation")
	abandoned.step(1);abandoned.cancel()
	check(not abandoned.readiness(clip,3).ok,"cancelled partial installation never grants readiness")
	await process_frame;await process_frame
	var remaining:=0
	for child:Node in cancelled.host.get_children():
		if child is StaticBody3D:remaining+=1
	check(remaining==0,"cancel removes all unpromoted collision bodies")
	check(Stream.append_specs(cancelled.host,additions).ok,"cancelled empty optimization does not block ordinary visual publication")
	cancelled.viewport.free()

func exercise_decoration(batch:RefCounted,record:Dictionary,map_path:String)->void:
	var live:=world();initialize_index(live.host)
	var store:=Residency.new();live.host.add_child(store)
	store.configure(live.host,map_path,FileAccess.get_sha256(map_path),1)
	check(store.enqueue(batch,1).ok,"pure decoration retains its verified namespace")
	store.step(1500)
	var prepared:=await worker(Deferred.prepare_scene.bind(record.asset_path,FileAccess.get_sha256(record.asset_path),null,{},false,files.content_root,true))
	if not check(prepared.get("scene") is Node3D,"pure decoration uses ordinary import without collision-face expansion"):Drainer.dispose_result(prepared);live.viewport.free();return
	var doc:=Document.new();var holder:=doc._asset(record,prepared);prepared.erase("scene")
	var additions:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,additions)
	var no_faces:=true
	for addition:Dictionary in additions:
		var mesh:Mesh=addition.get("collision_mesh",addition.mesh)
		var cpu:Variant=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache",null)
		no_faces=no_faces and cpu is Cpu and cpu._collision_faces.is_empty()
	check(no_faces,"all decorative meshes keep collision face cache empty")
	var appended:=Stream.append_specs(live.host,additions)
	check(appended.ok and live.host.get_meta("stream_bodies",{}).is_empty(),"pure decoration promotes without useless collision expansion or bodies")
	if not appended.ok:print(appended)
	holder.free();Drainer.dispose_result(prepared);live.viewport.free()

func finish(errors:RefCounted)->void:
	if files!=null:files.free();files=null
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_INSTANCE_RESIDENCY_GPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
