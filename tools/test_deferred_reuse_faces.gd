extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Fixture=preload("res://tools/test_deferred_reuse_admission.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Witness extends RefCounted:
	var references:Array=[]
	var released:=false
	var clear_before_release:=false
	func observe()->void:
		released=true;clear_before_release=references.all(func(value:WeakRef):return value.get_ref()==null)
class Admission extends "res://scripts/world3d/resource_admission.gd":
	var witness:Witness
	func release(key:String)->void:
		if witness!=null:witness.observe()
		super.release(key)
class Gate extends RefCounted:
	var semaphore:=Semaphore.new()
	func run()->Dictionary:semaphore.wait();return {}
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func template(capture:bool=true)->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,0,1])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var cpu:Mesh=Cpu.remember(mesh,[arrays]) if capture else null
	var holder:=Node3D.new();var visual:=MeshInstance3D.new();visual.mesh=mesh;holder.add_child(visual);visual.owner=holder
	var packed:=PackedScene.new();packed.pack(holder);holder.free()
	return {"packed":packed,"mesh":mesh,"cpu":cpu}
func worker(task:Callable)->Dictionary:
	var thread:=Thread.new();thread.start(task)
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var index:=preload("res://scripts/world3d/stream_index.gd").build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_library",[])
	var service:=Deferred.new();map.add_child(service);service._doc=Fixture.Document.new();service.activate(map);service.set_process(false)
	service._admission.byte_limit=96*1024*1024;service._admission.worker_limit=2
	return {"map":map,"service":service}
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var folder:=Paths.cache_directory("reuse_faces_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("resident.glb");var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3,4]));file.close()
	var digest:=FileAccess.get_sha256(path);var t:=template();var offer:=Deferred._reuse_face_offer(t.packed)
	check(offer.ok and offer.snapshots.size()==1 and t.cpu._collision_faces.is_empty(),"main offer only snapshots existing CPU arrays without expanding faces")
	check(offer.estimated_bytes>=36+12+36+65536,"reuse reservation includes pinned input arrays, expanded output and metadata")
	var token:=Deferred.Drainer.CancelToken.new()
	var prepared:=await worker(Deferred._prepare_job.bind(path,digest,token,{},true,folder,{},"",[],false,false,null,{"reuse_face_snapshots":offer.snapshots}))
	check(prepared.error.is_empty() and prepared.reused_model and not prepared.has("scene") and prepared.reuse_faces.size()==1,"real reuse worker expands faces without a parseable GLB or render import")
	check(t.cpu._collision_faces.is_empty(),"worker leaves the shared resident CPU capture untouched")
	var queue:=Deferred.new();var job:Dictionary={"reuse_face_owners":offer.owners}
	check(queue._accept_reused_faces(job,prepared) and t.cpu._collision_faces==PackedVector3Array([Vector3.FORWARD,Vector3.ZERO,Vector3.RIGHT]),"main acceptance installs the verified worker triangle order")
	check(Deferred._reuse_face_offer(t.packed).snapshots.is_empty(),"later instances reuse already completed faces without another expansion job")
	t.cpu._collision_faces=PackedVector3Array();t.mesh.remove_meta("ground_cpu_cache")
	check(not queue._accept_reused_faces(job,prepared) and t.cpu._collision_faces.is_empty(),"replaced or invalidated source CPU cache rejects all installation")
	t.mesh.set_meta("ground_cpu_cache",t.cpu);var slots:Array=t.cpu.surfaces;t.cpu.surfaces=slots.duplicate()
	check(not queue._accept_reused_faces(job,prepared),"replaced CPU surface container cannot borrow an old worker packet")
	t.cpu.surfaces=slots
	var changed:=FileAccess.open(path,FileAccess.WRITE);changed.store_buffer(PackedByteArray([4,3,2,1]));changed.close()
	var rejected:=await worker(Deferred._prepare_job.bind(path,digest,token,{},true,folder,{},"",[],false,false,null,{"reuse_face_snapshots":offer.snapshots}))
	check(not rejected.error.is_empty() and not rejected.get("reused_model",false),"final source SHA still rejects changed bytes after CPU preparation")
	file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3,4]));file.close()
	token.cancel();rejected=await worker(Deferred._prepare_job.bind(path,digest,token,{},true,folder,{},"",[],false,false,null,{"reuse_face_snapshots":offer.snapshots}))
	check(rejected.get("cancelled",false) and not rejected.get("reused_model",false),"cancellation cannot return a publishable face reuse result")
	queue.free();job.clear();offer.clear();prepared.clear();t.clear();slots=[]
	var helper:=Fixture.new();var old:=Deferred.collision_first_enabled;Deferred.collision_first_enabled=true
	t=template();Assets.cache_packed(path,t.packed,digest)
	var f:=fixture();queue=f.service;var item:Dictionary=helper.item(path,digest,"collision",0);item.record.collision="block"
	queue.pending=[item];queue.source_signatures[path]=digest;queue._prepared_paths[path]=true;queue.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));queue.set_process(false)
	queue._process(0)
	check(queue._jobs.has(path) and queue._jobs[path].stage=="reuse_reference" and queue._jobs[path].estimate.reuse_face_bytes>0 and queue._jobs[path].token.has_meta("reuse_face_owners"),"actual dispatch admits extra face bytes and leases their owners with the same reuse job")
	var deadline:=Time.get_ticks_msec()+3000
	while queue._jobs.has(path) and Time.get_ticks_msec()<deadline:queue._process(0);await process_frame
	check(queue.profile.get("reuse_face_jobs",0)==1 and queue.profile.get("reuse_face_prepared_meshes",0)==1 and not t.cpu._collision_faces.is_empty() and queue._admission.reserved_bytes==0,"actual main acceptance publishes prepared faces then releases the consumed job")
	f.map.free();Assets.evict_cached_scene(path);t.clear()
	t=template(false);Assets.cache_packed(path,t.packed,digest);f=fixture();queue=f.service;item=helper.item(path,digest,"uncaptured",0);item.record.collision="block"
	queue.pending=[item];queue.source_signatures[path]=digest;queue._prepared_paths[path]=true;queue.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));queue.set_process(false)
	queue._admission.reserve("sibling",{"estimated_bytes":80*1024*1024,"exclusive":false})
	queue._process(0)
	check(queue.profile.get("reuse_face_fallbacks",0)==1 and not queue._prepared_paths.has(path) and not queue._jobs.has(path) and queue._admission.reserved_bytes==80*1024*1024,"missing CPU capture waits for the full model reservation rather than fitting into the remaining small reuse allowance")
	queue._admission.release("sibling")
	f.map.free();Assets.evict_cached_scene(path);t.clear()
	# Both the normal and abandoned-worker paths must release strongly owned
	# templates/captures before the ledger announces their bytes as reusable.
	for abandoned in [false,true]:
		var witness:=Witness.new();t=template();witness.references=[weakref(t.packed),weakref(t.cpu)]
		token=Deferred.Drainer.CancelToken.new();token.set_meta("reuse_template_owner",t.packed);token.set_meta("reuse_face_owners",{"mesh":t.mesh,"cpu":t.cpu})
		if abandoned:
			var gate:=Gate.new();var thread:=Thread.new();thread.start(gate.run)
			token.set_meta("admission_owner",witness);token.set_meta("admission_release",witness.observe)
			var drainer:=Deferred.Drainer.for_tree(self);drainer.watch(thread,token);t.clear();drainer.abandon(thread)
			check(witness.references[0].get_ref()!=null and not witness.released,"abandoned active worker retains face/template owners and charge until its join")
			gate.semaphore.post();deadline=Time.get_ticks_msec()+3000
			while not witness.released and Time.get_ticks_msec()<deadline:await process_frame
		else:
			queue=Deferred.new();var admission:=Admission.new();admission.witness=witness;queue._admission=admission
			queue._jobs[path]={"token":token,"result":{},"reuse_template_owner":t.packed,"reuse_face_owners":{"mesh":t.mesh,"cpu":t.cpu}}
			t.clear();queue._discard_job(path);queue.free()
		check(witness.released and witness.clear_before_release,"%s drops face and template owners before returning admission"%("abandoned worker" if abandoned else "normal discard"))
	Deferred.collision_first_enabled=old;helper.free();token=null
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_REUSE_FACES passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
