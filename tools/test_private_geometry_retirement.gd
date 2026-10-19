extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var failures:=0
class WatchedMaterial extends StandardMaterial3D:
	var receipt:Dictionary={}
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.thread=OS.get_thread_caller_id()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func mesh()->Mesh:
	var result:=Cpu.new()
	# Same ownership shape as a retired prefab: a tiny dictionary owns two CPU
	# meshes, each retaining packed triangle and vertex buffers through arrays.
	result._collision_faces.resize(8388608);result._collision_faces.fill(Vector3.ONE)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(4194304);vertices.fill(Vector3.ONE)
	arrays[Mesh.ARRAY_VERTEX]=vertices;result.surfaces=[arrays];result.lods=[{}]
	result.materials=[StandardMaterial3D.new()]
	return result
func service()->Node:
	var result:Node=Retirement.new();result.name=Retirement.NODE_NAME;root.add_child(result);result.set_process(false);return result
func drain(target:Node)->int:
	var maximum:=0
	while not target.pending.is_empty():
		var start:=Time.get_ticks_usec();var done:bool=target._advance(target.pending[0],1000)
		maximum=maxi(maximum,Time.get_ticks_usec()-start)
		if done:target._finish_front()
		else:await process_frame
	return maximum
func trial(background:bool)->Dictionary:
	Retirement.background_geometry_release_enabled=background
	var target:=service()
	var packet:Dictionary={"mesh":mesh(),"source":mesh()}
	var receipt:Dictionary={};var material:=WatchedMaterial.new();material.receipt=receipt;packet.mesh.materials[0]=material;material=null
	var watches:Array=[weakref(packet.mesh),weakref(packet.source),weakref(packet.mesh.materials[0])]
	var ticket:Dictionary={"kind":"private_array","source_id":"test","values":[packet]}
	packet={};target.pending.append(ticket);target.known.test=true
	var began:=Time.get_ticks_usec();var maximum:int=await drain(target)
	var result:Dictionary={"background":background,"main_max_us":maximum,"wall_us":Time.get_ticks_usec()-began,"profile":target.profile.duplicate(true)}
	check(watches.all(func(w):return w.get_ref()==null),"mesh and material owners are released")
	check(receipt.thread==OS.get_main_thread_id(),"GPU material final destructor remains on main")
	if background:
		check(target.profile.geometry_batches==2 and target.profile.geometry_logical_bytes==288*1024*1024,"two typed CPU owners transfer the exact logical geometry bytes")
		check(target.profile.geometry_last_thread_id!=OS.get_main_thread_id(),"CPU geometry final release runs on a different thread")
	check(target.pending.is_empty() and target.known.is_empty(),"all transfer tickets complete")
	target.free();return result
func borrowers_and_exit()->void:
	Retirement.background_geometry_release_enabled=true
	var target:=service();var original:Mesh=mesh();var borrower:=Cpu.new()
	borrower.surfaces=original.surfaces;borrower.lods=original.lods;borrower._collision_faces=original._collision_faces
	original=null;await drain(target)
	check(borrower._collision_faces.size()==8388608 and borrower._collision_faces[-1]==Vector3.ONE and borrower.surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ONE,"background release leaves another mesh's shared buffers intact")
	var changed:PackedVector3Array=borrower._collision_faces.duplicate();changed[0]=Vector3.ZERO
	check(borrower._collision_faces[0]==Vector3.ONE,"explicit editing copy remains independent")
	changed=PackedVector3Array();borrower=null
	check(target.pending.size()==1,"final borrower contributes its own CPU transfer")
	target._advance(target.pending[0],1)
	var ticket:Dictionary=target.pending[0]
	target.free()
	check(ticket.worker==null and ticket.values.is_empty(),"exit joins active geometry work and leaves no live thread")
func admitted_model()->void:
	var target:=service();var owners:=preload("res://scripts/world3d/model_resource_owners.gd").new()
	owners.visuals.append(mesh());owners.visuals.append(mesh())
	var receipt:Dictionary={"done":false}
	var owner:=RefCounted.new();var watch:WeakRef=weakref(owner)
	check(Retirement.defer_model_packet({"resource_owners":owners},func():receipt.done=true,owner),"typed model admission accepts CPU mesh owners")
	owner=null
	var parent:Dictionary=target.pending[0]
	while not target._advance(parent,1000):await process_frame
	target._finish_front()
	check(not receipt.done and watch.get_ref()!=null and target.pending.size()==2,"model completion transfers admission to its final geometry child")
	await drain(target)
	check(receipt.done and watch.get_ref()==null,"callback and admission owner release only after all geometry workers join")
	target.free()
func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	Trace.enabled=true
	if "--gdb-witness" in OS.get_cmdline_user_args():
		print("PRIVATE_GEOMETRY_WITNESS_READY pid=",OS.get_process_id());await create_timer(15).timeout
	var reports:Array=[]
	for background:bool in [false,true,true,false]:reports.append(await trial(background))
	await borrowers_and_exit()
	await admitted_model()
	Retirement.background_geometry_release_enabled=true
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	print("PRIVATE_GEOMETRY_RETIREMENT ",JSON.stringify({"trials":reports,"failures":failures}))
	quit(1 if failures else 0)
