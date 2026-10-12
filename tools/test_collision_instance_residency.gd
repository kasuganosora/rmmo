extends SceneTree
## Store lifecycle fixtures use a deliberately sealed in-memory Batch. Source /
## ownership authority is separately exercised by the real preparation tests.
const Residency=preload("res://scripts/world3d/collision_instance_residency.gd")
const Preparation=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const PATH="res://fixture/map.gltf"
var passed:=0
var failures:=0

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1

func _initialize()->void:call_deferred("run")

func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("source_map_sha256",SHA)
	var store:=Residency.new();map.add_child(store)
	check(store.configure(map,PATH,SHA,4).ok,"configure map-owned context")
	return {"map":map,"store":store}

func batch(id:String="prop",long_faces:bool=false)->Preparation.Batch:
	var faces:=PackedVector3Array()
	for i in 1025 if long_faces else 1:faces.append_array(PackedVector3Array([Vector3.ZERO,Vector3(0,0,1),Vector3(1,0,0)]))
	var pose:=Transform3D(Basis.from_euler(Vector3(0,.4,0)).scaled(Vector3(1.5,1,2)),Vector3(320,0,160))
	var rows:Array=[{"uuid":id+"__mesh","selector":"root/0","transform":pose,"collision":"block","kind":"faces","faces":faces,"box":Vector3.ZERO,"bounds":AABB(Vector3.ZERO,Vector3(1,0,1))},
		{"uuid":id+"__box","selector":"root/1","transform":Transform3D(Basis.IDENTITY,Vector3(321,0,161)),"collision":"walk","kind":"box","faces":PackedVector3Array(),"box":Vector3.ONE,"bounds":AABB(Vector3(-.5,-.5,-.5),Vector3.ONE)}]
	var value:=Preparation.Batch.new();value._path=PATH;value._sha=SHA;value._bytes=faces.size()*12+1024
	value._instances=[{"uuid":id,"record_index":0,"record_sha":SHA,"asset_path":"res://fixture/model.glb","source_sha":SHA,"pose":pose,"record_identity":{},"rows":rows}]
	value._sealed=true
	return value

func specs(value:Preparation.Batch)->Array:
	var result:Array=[]
	for instance:Dictionary in value.instances():
		for row:Dictionary in instance.rows:
			var cpu:=Cpu.new();cpu.bounds=row.bounds;cpu.box_size=row.box;cpu._collision_faces=row.faces
			result.append({"uuid":row.uuid,"mesh":cpu,"collision_mesh":cpu,"transform":row.transform,"extras":{"uuid":row.uuid,"rmmo_collision":row.collision}})
	return result

func install(store:Node)->void:
	for i in 24:
		if store.debug_snapshot().pending==0:return
		var status:Dictionary=store.step(1)
		check(status.ok and status.units>0,"positive tiny budget advances bounded work")
	check(false,"installation finishes in finite units")

func run()->void:
	var scene:=fixture();var store:Node=scene.store;var value:=batch("prop",true)
	check(store.instance_readiness("missing",4).state=="not_accepted" and not store.instance_readiness("missing",4).ok,"absent instance never borrows an empty-clip readiness success")
	check(not store.enqueue(value,3).ok,"stale epoch cannot enqueue")
	check(not store.enqueue({},4).ok and not store.enqueue(Preparation.Batch.new(),4).ok,"raw and unsealed handoffs rejected")
	check(store.enqueue(value,4).ok,"sealed batch accepted")
	check(store.instance_readiness("prop",4).state=="installing" and store.publication_status("prop").pending,"accepted pending instance exposes a render-publication wait")
	check(not store.enqueue(value,4).ok,"duplicate namespace rejected without side effects")
	check(store.step(0).units==0 and store.debug_snapshot().owned_bodies==0,"zero budget never constructs a shape")
	var clip:=AABB(Vector3(319,-2,159),Vector3(5,5,5))
	check(store.readiness(clip,4).reason=="collision_pending","prepared batch is not physics ready")
	store.step(1)
	var first:StaticBody3D=store.body_for("prop__mesh")
	check(first!=null and first.get_child_count()==1 and first.collision_layer==0,"first 3072-vertex slice stays disabled")
	check(not store.preflight_promotion(specs(value)).ok,"partially installed instance cannot promote")
	install(store)
	var second:StaticBody3D=store.body_for("prop__box")
	check(first.get_child_count()==2 and second!=null and first.collision_layer==1 and second.collision_layer==1,"all members activate only after all exact slices exist")
	check(first.get_meta("stream_physics_published_frame")==second.get_meta("stream_physics_published_frame"),"whole instance shares one publication watermark")
	check(store.readiness(clip,4).reason=="physics_sync_pending","publication is not a physics synchronization event")
	check(store.instance_readiness("prop",4).state=="physics_sync_pending" and not store.publication_status("prop").pending,"fully installed instance permits promotion before physics watermark becomes movement-ready")
	check(not scene.map.has_meta("stream_library") and not scene.map.has_meta("stream_known") and not scene.map.has_meta("stream_bodies"),"collision installation creates no render placeholders")
	var original:Dictionary=value.instances()[0].rows[0];var actual:=PackedVector3Array()
	for child:CollisionShape3D in first.get_children():actual.append_array(child.shape.get_faces())
	var expected:PackedVector3Array=original.faces.duplicate()
	for i in expected.size():expected[i]=original.transform.basis*expected[i]
	check(actual==expected and first.global_transform==Transform3D(Basis.IDENTITY,original.transform.origin),"slices preserve every exact triangle and bake nonuniform basis")
	await physics_frame;await process_frame
	check(store.readiness(clip,4).ok and not store.readiness(clip,4).map_closure,"subsequent real physics frame proves only accepted instance scope")
	check(store.instance_readiness("prop",4).ok and store.instance_readiness("prop",4).state=="ready","exact instance is ready only after real physical synchronization")
	check(store.readiness(clip,5).reason=="epoch_mismatch","different map epoch cannot reuse residency")
	var good:=specs(value);var changed:Array=good.duplicate(true)
	changed[0].transform.origin.x+=1
	check(not store.preflight_promotion(changed).ok,"changed render pose refuses handoff")
	changed=good.duplicate(true);changed[0].extras.rmmo_collision="none"
	check(not store.preflight_promotion(changed).ok,"changed collision mode refuses handoff")
	changed=good.duplicate(true);changed.pop_back()
	check(not store.preflight_promotion(changed).ok,"namespace must promote as a whole")
	changed=good.duplicate(true);var extra:Dictionary=good[0].duplicate(true);extra.uuid="prop__extra";changed.append(extra)
	check(not store.preflight_promotion(changed).ok,"unexpected namespace member refuses handoff")
	var wrong:=Cpu.new();wrong._collision_faces=PackedVector3Array([Vector3.ZERO,Vector3.UP,Vector3.RIGHT]);changed=good.duplicate(true);changed[0].collision_mesh=wrong
	check(not store.preflight_promotion(changed).ok,"same UUID cannot conceal different source geometry")
	wrong=Cpu.new();wrong.surfaces=[];changed=good.duplicate(true);changed[0].collision_mesh=wrong
	check(not store.preflight_promotion(changed).ok and wrong._collision_faces.is_empty(),"missing CPU triangles refuse without expansion or readback")
	first.get_child(0).disabled=true
	check(not store.readiness(clip,4).ok and not store.preflight_promotion(good).ok,"disabled live shape invalidates both readiness and promotion")
	check(store.instance_readiness("prop",4).state=="failed" and store.publication_status("prop").error=="collision_invalidated","instance and publication queries reject a disabled owned shape")
	first.get_child(0).disabled=false
	var plan:Dictionary=store.preflight_promotion(good);var parent:Node=first.get_parent();var rid:=first.get_rid();var stamp:int=first.get_meta("stream_physics_published_frame")
	check(plan.ok and plan.instances==1,"matching whole namespace preflight succeeds")
	store.commit_promotion(plan.token)
	check(scene.map.get_meta("stream_bodies")["prop__mesh"]==first and first.get_rid()==rid and first.get_parent()==parent and first.get_meta("stream_physics_published_frame")==stamp,"promotion reuses exact body without reparenting, reattaching or changing physics watermark")
	check(store.debug_snapshot().reserved_bytes==0 and store.debug_snapshot().owned_bodies==0,"promotion releases payload and store ownership")
	check(store.instance_readiness("prop",4).state=="promoted" and not store.instance_readiness("prop",4).ok and not store.publication_status("prop").owned,"promoted instance explicitly delegates fresh readiness proof to ordinary Stream")
	store.dispose();await process_frame
	check(is_instance_valid(first) and first.collision_layer==1,"store disposal never destroys transferred bodies")
	scene.map.queue_free();await process_frame
	await cancellation_and_capacity(clip)
	await map_transfer_and_disposal(clip)
	await visual_only_instance()
	await discard_precise_tickets()
	print("COLLISION_INSTANCE_RESIDENCY passed=",passed," failures=",failures)
	quit(1 if failures else 0)

func cancellation_and_capacity(clip:AABB)->void:
	var scene:=fixture();var store:Node=scene.store
	var oversized:=batch();oversized._bytes=Residency.MAX_RETAINED_BYTES
	check(store.enqueue(oversized,4).error=="memory_capacity" and store.debug_snapshot().instances==0,"memory admission rejects atomically")
	for i in 4:check(store.enqueue(batch("batch%d"%i),4).ok,"queue accepts bounded batch "+str(i))
	check(store.enqueue(batch("fifth"),4).error=="queue_capacity","fifth queued batch is rejected without evicting collision")
	store.step(1);var body:StaticBody3D=store.body_for("batch0__mesh")
	store.cancel()
	check(store.readiness(clip,4).reason=="cancelled" and body.collision_layer==0 and body.is_queued_for_deletion(),"cancel revokes proof and collision synchronously, defers safe destruction")
	check(not store.enqueue(batch("again"),4).ok,"cancelled generation cannot silently restart")
	var data:Dictionary=Index.build([])
	for key:String in data:scene.map.set_meta(key,data[key])
	scene.map.set_meta("stream_library",[])
	var fallback:=specs(batch("ordinary"))
	for spec:Dictionary in fallback:
		spec.chunk_min=Vector2i(10,5);spec.chunk_max=Vector2i(10,5);spec.chunk=Vector2i(10,5)
	check(Stream.append_specs(scene.map,fallback).ok,"cancelled empty store does not block the ordinary Stream append path")
	await process_frame
	check(not is_instance_valid(body),"cancelled owned body drains on scene deletion queue")
	scene.map.queue_free();await process_frame

func visual_only_instance()->void:
	var scene:=fixture();var store:Node=scene.store;var value:=batch("decor")
	for instance:Dictionary in value._instances:
		for row:Dictionary in instance.rows:row.collision="none"
	check(store.enqueue(value,4).ok and not store.instance_readiness("decor",4).ok,"pure visual instance is not ready merely because it has no solids")
	install(store)
	check(store.debug_snapshot().owned_bodies==0 and store.instance_readiness("decor",4).state=="physics_sync_pending","pure visual installation records explicit completion without dummy bodies")
	await physics_frame;await process_frame
	check(store.instance_readiness("decor",4).ok,"pure visual record has exact accepted-instance readiness")
	var rendered:=specs(value)
	for spec:Dictionary in rendered:spec.collision_mesh._collision_faces=PackedVector3Array()
	var plan:Dictionary=store.preflight_promotion(rendered)
	check(plan.ok,"pure visual promotion accepts render jobs that deliberately omit collision expansion")
	store.commit_promotion(plan.token)
	check(store.instance_readiness("decor",4).state=="promoted" and scene.map.get_meta("stream_bodies",{}).is_empty(),"pure visual promotion transfers namespace with zero collision bodies")
	scene.map.queue_free();await process_frame

func map_transfer_and_disposal(clip:AABB)->void:
	var scene:=fixture();var store:Node=scene.store;store.enqueue(batch(),4);install(store)
	await physics_frame;await process_frame
	var body:StaticBody3D=store.body_for("prop__mesh");var rid:=body.get_rid();var original_world:World3D=body.get_world_3d()
	var target:=SubViewport.new();target.own_world_3d=true;root.add_child(target)
	scene.map.reparent(target)
	check(store.has_instances() and store.body_for("prop__mesh")==body and body.get_rid()==rid and body.get_world_3d()!=original_world,"synchronous map reparent retains exact bodies in the destination World")
	check(store.readiness(clip,4).reason=="physics_sync_pending","changing physics World requires a fresh synchronization watermark")
	await physics_frame;await process_frame
	check(store.readiness(clip,4).ok and store.debug_snapshot().terminal.is_empty(),"map reparent resumes after physics registration instead of disposing store")
	store.free()
	check(body.collision_layer==0 and body.is_queued_for_deletion(),"explicit store deletion disables still-owned sibling bodies before deferred callbacks disappear")
	await process_frame
	check(not is_instance_valid(body),"explicit store deletion drains its unpromoted bodies")
	target.queue_free();await process_frame
	scene=fixture();store=scene.store;store.enqueue(batch(),4);install(store)
	await physics_frame;await process_frame
	store.body_for("prop__box").get_child(0).shape.size=Vector3(2,2,2)
	check(not store.readiness(clip,4).ok,"mutating the existing shape resource revokes residency proof")
	scene.map.set_meta("source_map_sha256","b".repeat(64))
	check(store.readiness(clip,4).reason=="map_source_changed" and not store.preflight_promotion(specs(batch())).ok,"changed map source cannot promote stale collision")
	scene.map.queue_free();await process_frame

func discard_precise_tickets()->void:
	var scene:=fixture();var store:Node=scene.store;var first:=batch("first",true);var other:=batch("other")
	first._instances.append(other._instances[0]);first._bytes+=other._bytes
	check(store.enqueue(first,4).ok,"one handoff may own several independently leased instances")
	store.step(1);var partial:StaticBody3D=store.body_for("first__mesh")
	check(not store.discard_instances(["first",42]).ok and store.instance_readiness("first",4).state=="installing","invalid discard list fails without partially withdrawing a valid instance")
	check(store.discard_instances(["first","first"]).removed==1 and partial.collision_layer==0 and partial.is_queued_for_deletion(),"withdrawal stops only the exact partial instance and disables its body")
	check(store.instance_readiness("first",4).state=="not_accepted" and store.instance_readiness("other",4).state=="installing" and store.debug_snapshot().reserved_bytes>=first._bytes,"other instance retains its shared handoff and pending work")
	install(store);await physics_frame;await process_frame
	var body:StaticBody3D=store.body_for("other__mesh")
	check(store.instance_readiness("other",4).ok and not is_instance_valid(partial),"unrelated accepted instance finishes after cancelled sibling drains")
	var plan:Dictionary=store.preflight_promotion(specs(other));store.commit_promotion(plan.token)
	check(store.discard_instances(["other","absent"]).removed==0 and is_instance_valid(body) and body.collision_layer==1,"withdrawing an already promoted UUID never touches ordinary Stream ownership")
	check(store.debug_snapshot().reserved_bytes==0,"last shared handoff releases all admission bytes after withdrawal plus promotion")
	check(store.enqueue(batch("again"),4).ok,"explicit per-ticket withdrawal leaves the live Store usable")
	install(store);var active:StaticBody3D=store.body_for("again__mesh")
	check(store.discard_instances(["again"]).removed==1 and active.collision_layer==0 and active.is_queued_for_deletion() and store.debug_snapshot().reserved_bytes==0,"last-ticket withdrawal retires an installed owned instance without implicit eviction")
	scene.map.queue_free();await process_frame
