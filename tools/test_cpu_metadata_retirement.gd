extends "res://tools/test_private_geometry_retirement.gd"
## Native-destruction smoke only. Reuses service/drain/error contracts; no maps.
## No timing threshold: report exact nested resource deaths and their threads.
var checks:=0
class WatchedShape extends ConcavePolygonShape3D:
	var receipt:Dictionary={}
	var label:=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.events.append({"label":label,"type":"shape","thread":OS.get_thread_caller_id()})
class WatchedShadow extends ArrayMesh:
	var receipt:Dictionary={}
	var label:=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.events.append({"label":label,"type":"shadow","thread":OS.get_thread_caller_id()})

func check(ok:bool,label:String)->void:
	checks+=1;super.check(ok,label)
func triangle()->PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
func cpu_owner()->Mesh:
	var value:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=triangle();value.surfaces=[arrays];value.lods=[{}]
	value._collision_faces=arrays[Mesh.ARRAY_VERTEX];value.materials=[null]
	return value
func shape(label:String,receipt:Dictionary)->ConcavePolygonShape3D:
	var value:=WatchedShape.new();value.label=label;value.receipt=receipt
	value.set_faces(triangle());return value
func shadow(label:String,receipt:Dictionary)->ArrayMesh:
	var value:=WatchedShadow.new();value.label=label;value.receipt=receipt
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=triangle()
	value.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return value
func prepare_terrain()->Dictionary:
	var receipt:={"events":[]};var owner:Mesh=cpu_owner();var shapes:Array=[];var watches:Array=[]
	for i in 4:
		var child:ConcavePolygonShape3D=shape("terrain_"+str(i),receipt)
		shapes.append(child);watches.append(weakref(child))
	owner.set_meta("runtime_terrain_shapes",shapes)
	return {"owner":owner,"owner_watch":weakref(owner),"receipt":receipt,"children":watches,"expected":4}
func prepare_basis()->Dictionary:
	var receipt:={"events":[]};var owner:Mesh=cpu_owner()
	var shared:ConcavePolygonShape3D=shape("basis_shared",receipt)
	var a:ConcavePolygonShape3D=shape("basis_a",receipt)
	var b:ConcavePolygonShape3D=shape("basis_b",receipt)
	var shapes_a:Array=[shared,a];var shapes_b:Array=[shared,b]
	owner.set_meta("runtime_terrain_basis_shapes",{"entries":{"basis_a":{"shapes":shapes_a,"stamp":1},"basis_b":{"shapes":shapes_b,"stamp":2}},"serial":2})
	var body:=StaticBody3D.new();root.add_child(body)
	var collision:=CollisionShape3D.new();collision.shape=shared;body.add_child(collision)
	return {"owner":owner,"owner_watch":weakref(owner),"receipt":receipt,"children":[weakref(shared),weakref(a),weakref(b)],"borrowed":shapes_b,"body":body,"expected":3,"before":var_to_bytes(triangle())}
func prepare_shadow()->Dictionary:
	var receipt:={"events":[]};var owner:Mesh=cpu_owner()
	var a:ArrayMesh=shadow("shadow_borrowed",receipt);var b:ArrayMesh=shadow("shadow_private",receipt)
	owner.set_meta("opaque_shadow_"+str([0,0]).sha256_text(),a)
	owner.set_meta("opaque_shadow_"+str([0,2]).sha256_text(),b)
	var visual:=MeshInstance3D.new();visual.mesh=a;root.add_child(visual)
	return {"owner":owner,"owner_watch":weakref(owner),"receipt":receipt,"children":[weakref(a),weakref(b)],"body":visual,"expected":2,"before":var_to_bytes(triangle())}
func owner_identity(state:Dictionary)->Dictionary:
	var value:Mesh=state.owner
	return {"id":value.get_instance_id(),"script":value.get_script().resource_path}
func take_owner(state:Dictionary)->Array:
	# This helper fully unwinds before _drop_private_value: no VM temporary may
	# keep the CPU owner alive across the unit being exercised.
	var values:Array=[state.owner];state.owner=null;return values
func release_borrowed(state:Dictionary)->void:
	state.borrowed=[] # Drop this ref; do not clear a shared child Array.
func release_body(state:Dictionary)->void:
	var body:Node=state.body;state.body=null;body.free()
func verify_borrowed_basis(state:Dictionary)->void:
	check(state.borrowed.size()==2 and state.borrowed[0]==state.children[0].get_ref() and state.borrowed[1]==state.children[2].get_ref(),"basis borrower retains exact shared Shape resources")
	for child:ConcavePolygonShape3D in state.borrowed:
		check(var_to_bytes(child.get_faces())==state.before,"basis borrower faces remain byte exact")
func verify_borrowed_shadow(state:Dictionary)->void:
	var visual:MeshInstance3D=state.body
	check(visual.mesh==state.children[0].get_ref(),"shadow instance keeps its exact ArrayMesh")
	check(var_to_bytes(visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])==state.before,"shadow borrower keeps exact GPU vertex channel")
func alive(watch:WeakRef)->bool:
	# The strong result of get_ref must die before the caller releases borrowers.
	return watch.get_ref()!=null
func run_case(kind:String)->Dictionary:
	var target:Node=service()
	var state:Dictionary=prepare_terrain() if kind=="terrain" else (prepare_basis() if kind=="basis" else prepare_shadow())
	check(state.receipt.events.is_empty(),kind+" construction creates no destruction events")
	var identity:Dictionary=owner_identity(state)
	check(identity.script=="res://scripts/world3d/ground_cpu_mesh.gd",kind+" root uses the exact production CPU script")
	var values:Array=take_owner(state)
	check(Retirement.defer_private_array(values,true),kind+" enters the actual private retirement queue")
	target.set_process(false)
	var private_ticket:Dictionary=target.pending[0]
	print("CPU_METADATA_RETIREMENT_BEGIN case=",kind," pid=",OS.get_process_id()," root_id=",identity.id)
	var private_done:bool=target._advance_private_array(private_ticket,1)
	check(private_done and target.profile.private_values==1,kind+" one queued private unit is advanced")
	if private_done:target._finish_front()
	target.set_process(false)
	var at_owner_death:int=state.receipt.events.size()
	check(values.is_empty() and not alive(state.owner_watch),kind+" one actual private unit releases CPU owner")
	check(at_owner_death==(4 if kind=="terrain" else 1),kind+" current metadata graph has the exact nested destruction count")
	check(target.pending.size()==1 and target.pending[0].kind=="cpu_geometry",kind+" CPU owner still donates only packed geometry")
	if kind=="basis":
		check(alive(state.children[0]) and not alive(state.children[1]) and alive(state.children[2]),"basis metadata frees private child while both borrowers survive")
		verify_borrowed_basis(state)
		release_borrowed(state)
		check(state.receipt.events.size()==2 and alive(state.children[0]) and not alive(state.children[2]),"dropping borrowed array releases only its unshared shape")
		release_body(state)
	elif kind=="shadow":
		check(alive(state.children[0]) and not alive(state.children[1]),"shadow metadata frees private mesh while instance borrower survives")
		verify_borrowed_shadow(state);release_body(state)
	check(state.children.all(func(w):return not alive(w)) and state.receipt.events.size()==state.expected,kind+" each unique nested resource eventually dies exactly once")
	check(state.receipt.events.all(func(event):return event.thread==OS.get_main_thread_id()),kind+" Shape and ArrayMesh PREDELETE remains on main")
	await drain(target)
	check(target.pending.is_empty() and target.known.is_empty(),kind+" all geometry retirement jobs drain")
	check(target.profile.get("geometry_unmeasured_owners",0)==1 and target.profile.get("geometry_last_thread_id",OS.get_main_thread_id())!=OS.get_main_thread_id(),kind+" pure CPU geometry processing remains on its worker")
	var report:={"case":kind,"nested_deaths_at_one_cpu_unit":at_owner_death,"unique_resource_deaths":state.receipt.events.size(),"events":state.receipt.events,"cpu_owners":target.profile.get("geometry_unmeasured_owners",0),"cpu_worker_thread":target.profile.get("geometry_last_thread_id",0)}
	print("CPU_METADATA_RETIREMENT_END ",JSON.stringify(report));target.free();return report
func run()->void:
	create_timer(30).timeout.connect(func():push_error("metadata retirement smoke deadline");quit(2))
	Retirement.background_geometry_release_enabled=true;Retirement.batched_geometry_release_enabled=true
	var errors:=Errors.new();OS.add_logger(errors)
	if "--gdb-witness" in OS.get_cmdline_user_args():
		print("CPU_METADATA_RETIREMENT_READY pid=",OS.get_process_id());await create_timer(15).timeout
	var reports:Array=[]
	for kind:String in ["terrain","basis","shadow"]:reports.append(await run_case(kind))
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("CPU_METADATA_RETIREMENT_FINISHED ",JSON.stringify({"checks":checks,"failures":failures,"reports":reports,"performance_sample":false}))
	quit(1 if failures else 0)
