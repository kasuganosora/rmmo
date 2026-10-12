extends "res://tools/test_model_collision_requirements.gd"
## Focused main-thread acceptance/publication regression. The joined worker
## result is injected; template packing, cache replacement, document instances
## and Stream adoption use production code. No GPU or formal assets are used.
class HeldPublication extends "res://scripts/world3d/deferred_asset_loader.gd":
	var hold_publication:=true
	func _publish_ready(began:int,budget_usec:int=INTERACTIVE_BUDGET_US)->Dictionary:
		if hold_publication:return {"units":0,"unit_us":0,"max_unit_us":0}
		return super._publish_ready(began,budget_usec)
class ActualDocument extends "res://scripts/world3d/world_document.gd":
	var calls:=0
	func _asset(value:Dictionary,prepared:Dictionary={})->Node3D:
		calls+=1
		return super._asset(value,prepared)

func source_scene(captured:bool)->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3(0,1,.5)])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if captured:Cpu.remember(mesh,[arrays]).collision_faces()
	var holder:=Node3D.new();var mesh_node:=visual(mesh,"none");mesh_node.name="geometry"
	holder.add_child(mesh_node);mesh_node.owner=holder
	return {"scene":holder,"mesh":mesh}

func accepted_fixture(path:String,digest:String,ids:Array[String])->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var index:Dictionary=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var queue:=HeldPublication.new();map.add_child(queue)
	var document:=ActualDocument.new();queue._doc=document;queue.activate(map);queue.set_process(false)
	queue._admission.byte_limit=96*1024*1024
	for id:String in ids:
		var value:Dictionary={"uuid":id,"kind":"asset","asset_path":path,"collision":"block","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.]}
		queue.pending.append({"path":path,"digest":digest,"record":value,"bounds":AABB(Vector3.ZERO,Vector3.ONE),"memory":{"estimated_bytes":1024*1024,"exclusive":false,"known":true}})
	queue.source_signatures[path]=digest
	queue.set_demand("publication",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));queue.set_process(false)
	queue._refresh_demanded()
	var original:=source_scene(true)
	var estimate:Dictionary={"estimated_bytes":1024*1024,"exclusive":false}
	check(queue._admission.reserve(path,estimate),"joined result keeps its real admission lease")
	queue._admission.park(path);queue._admission.worker_limit=0
	queue._jobs[path]={"token":Deferred.Drainer.CancelToken.new(),"stage":"raw_import","native":false,"estimate":estimate,"publication_ids":ids.duplicate(),"result":{"error":"","scene":original.scene,"source_digest":digest,"collision_geometry_mode":Requirements.ALL}}
	original.scene=null
	queue._process(0)
	check(queue._jobs.has(path) and queue._jobs[path].get("accepted",false) and Assets.has_cached_scene(path,digest),"production acceptance packs the prepared exact geometry while publication is held")
	check(document.calls==0 and queue._admission.reserved_bytes==1024*1024,"held publication retains its full reservation and performs no instance adoption")
	return {"map":map,"queue":queue,"document":document,"original_mesh":original.mesh}

func replace_template(path:String,digest:String)->Mesh:
	var replacement:=source_scene(false)
	check(Assets.cache_scene(path,replacement.scene,digest),"independent transaction replaces same-path same-SHA template")
	check(not replacement.mesh.has_meta("ground_cpu_cache"),"replacement really lacks optional CPU collision capture")
	return replacement.mesh

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var previous:=Requirements.enabled;Requirements.enabled=true
	var frame_budget=preload("res://scripts/world3d/frame_work_budget.gd")
	var previous_budget:bool=frame_budget.enabled;frame_budget.enabled=false
	var folder:=Paths.cache_directory("collision_publication_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("cached.glb");var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1,2,3,4]));file.close();var digest:=FileAccess.get_sha256(path)
	# Replacement between frames must be rejected before any document work.
	var f:=accepted_fixture(path,digest,["first"])
	var original_owner:WeakRef=weakref(Assets._scenes[path])
	var replacement:=replace_template(path,digest)
	check(original_owner.get_ref()!=null and f.queue._admission.reserved_bytes==1024*1024,"replaced prepared template stays owned while its task remains charged")
	f.queue.hold_publication=false;f.queue._process(0)
	check(f.document.calls==0 and not replacement.has_meta("ground_cpu_cache"),"same-SHA replacement cannot silently recapture collision geometry on main")
	check(f.queue._jobs.is_empty() and f.queue._admission.reserved_bytes==0 and not f.queue._prepared_paths.has(path),"stale normal job retires before full preparation can be re-admitted")
	check(f.queue.pending.size()==1 and not f.queue.pending[0].get("model_verified",false),"unpublished instance remains pending without a borrowed verification flag")
	check(original_owner.get_ref()==null,"discard removes the replaced template owner before returning the task lease")
	f.map.free();Assets.evict_cached_scene(path)
	# A publication listener can legally load another template in the same frame;
	# the next sibling needs its own owner check, not merely the frame-start gate.
	f=accepted_fixture(path,digest,["first","second"])
	var replacement_box:Dictionary={}
	f.queue.published.connect(func(_specs:Array)->void:
		if replacement_box.is_empty():replacement_box.mesh=replace_template(path,digest))
	f.queue.hold_publication=false;f.queue._publish_ready(Time.get_ticks_usec(),1000000)
	check(f.document.calls==1 and f.queue.profile.instances==1,"same-frame template swap cannot instantiate the next sibling through a weaker cache")
	check(not replacement_box.is_empty() and not replacement_box.mesh.has_meta("ground_cpu_cache"),"publication callback replacement stays untouched by main-thread capture")
	check(f.queue._jobs.is_empty() and f.queue._admission.reserved_bytes==0 and f.queue.pending.size()==1,"same-frame rejection releases old charge while preserving the remaining demand")
	f.map.free();Assets.evict_cached_scene(path)
	# The normal disabled route must still publish from its accepted allocation;
	# its precomputed exact collision capture remains shared by both instances.
	Requirements.enabled=false
	f=accepted_fixture(path,digest,["unchanged_first","unchanged_second"])
	f.queue.hold_publication=false;f.queue._publish_ready(Time.get_ticks_usec(),1000000);f.queue._process(0)
	check(f.document.calls==2 and f.queue.profile.instances==2 and f.queue.pending.is_empty(),"unchanged template publishes all siblings with the geometry candidate disabled")
	var specs:Array=f.map.get_meta("stream_library",[])
	check(specs.size()==2 and specs[0].collision_mesh==specs[1].collision_mesh and specs[0].collision_mesh==f.original_mesh.get_meta("ground_cpu_cache"),"normal publication keeps the original exact prepared collision identity")
	check(f.queue._jobs.is_empty() and f.queue._admission.reserved_bytes==0,"normal completed publication releases its full task lease")
	f.map.free();Assets.evict_cached_scene(path)
	check(FileAccess.get_sha256(path)==digest,"replacement and retry leave the source identity unchanged")
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	frame_budget.enabled=previous_budget;Requirements.enabled=previous
	check(logger.errors.is_empty(),"no script or engine errors in the publication ownership regression")
	OS.remove_logger(logger)
	print("MODEL_COLLISION_PUBLICATION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
