extends "res://tools/test_collision_first_loading_gpu.gd"
## Actual MapLoader native core template -> Deferred reference reuse -> exact
## collision promotion. One GLB is shared by a required core placement and a
## collision-first placement. No source/cache geometry is injected by the test.
const CompiledCache=preload("res://scripts/world3d/compiled_asset_cache.gd")
const AssetLibrary=preload("res://scripts/world_editor/asset_library.gd")

func run()->void:
	create_timer(120).timeout.connect(func():push_error("core collision reuse GPU timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	_old_collision_first=Deferred.collision_first_enabled;Deferred.collision_first_enabled=true
	files=Base.Files.new();files.content_root=Paths.external_root();files.folder=Paths.cache_directory("collision_core_reuse_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("shared_core.glb");write_glb(path);files.created.append(path)
	var estimate:=Builder.estimate(path,files.content_root);var ledger:=Admission.new()
	if not check(not estimate.is_empty() and ledger.reserve("build",estimate),"offline collision producer has full resource admission"):finish(errors);return
	var built:=await worker(Builder.build.bind(path,files.content_root,estimate.estimated_bytes));ledger.park("build")
	var built_ok:bool=built.get("ok",false);check(built_ok,"shared real GLB has an exact source collision sidecar")
	Drainer.dispose_result(built);ledger.release("build")
	if not built_ok:finish(errors);return
	var native:=CompiledCache.build(path)
	if not check(native.get("ok",false),"shared core source has a real compiled native product"):print(native);finish(errors);return
	await reuse_case(path)
	AssetLibrary.evict_cached_scene(path)
	finish(errors)

func template_faces(packed:PackedScene)->Dictionary:
	var state:=packed.get_state();var seen:Dictionary={};var result:Dictionary={"meshes":0,"cpu_meshes":0,"surface_meshes":0,"empty_faces":0,"faces":0}
	for at:int in state.get_node_count():
		for property:int in state.get_node_property_count(at):
			if state.get_node_property_name(at,property)!=&"mesh":continue
			var mesh:Variant=state.get_node_property_value(at,property)
			if not mesh is Mesh or seen.has(mesh.get_instance_id()):continue
			seen[mesh.get_instance_id()]=true;result.meshes+=1
			var cpu:Variant=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
			if not cpu is Cpu:continue
			result.cpu_meshes+=1
			if not cpu.surfaces.is_empty():result.surface_meshes+=1
			if cpu._collision_faces.is_empty():result.empty_faces+=1
			result.faces+=cpu._collision_faces.size()
	return result

func reuse_case(path:String)->void:
	var records:Array=[ground(),model("required_core",path,Vector3(4,0,4)),model("reuse_prop",path,Vector3(16,0,12))]
	var context:=await load_map(records,"native_core_reuse")
	if context.is_empty():return
	var map:Node=context.map;var world:Node=context.world;var deferred:Node=context.deferred
	var profile:Dictionary=map.get_meta("load_profile",{})
	print_case("returned_source_tree",context,path)
	# Imported core assets leave MapLoader as genuine Nodes. Actual entry uses
	# Stream.sync to adopt these into its index; that existing operation captures
	# CPU surfaces. Inspecting the template before adoption tests the wrong phase.
	Stream.sync(map,world,ORIGIN,Stream.LOAD_BUDGET)
	print_case("after_real_core_adoption",context,path)
	check(profile.get("collision_first_core_deferred",0)==1 and profile.get("initial_asset_paths",0)==1,"one shared GLB remains an initial dependency while its independent second placement is deferred")
	check(namespace_count(map,"required_core")==2 and namespace_count(map,"reuse_prop")==0,"actual initial instance is complete and collision-first instance has no render placeholder")
	var owner:PackedScene=AssetLibrary._scenes.get(path)
	if not check(owner!=null and deferred._prepared_paths.has(path),"MapLoader registers its actual verified core PackedScene for reuse"):await close_case(context);return
	var before:=template_faces(owner)
	print("CORE_REUSE_BEFORE ",JSON.stringify(before))
	check(before.surface_meshes>0 and before.empty_faces>0 and before.faces==0,"ordinary core collection leaves real CPU surfaces but does not expand template collision faces")
	var cover:=Cover.new();world.add_child(cover);await cover.wait_until_drawn();begin_gate(context,cover)
	deferred._active=false;deferred.set_process(false)
	var deadline:=Time.get_ticks_msec()+30000
	while not context.gate_done and Time.get_ticks_msec()<deadline:await process_frame
	if not check(context.gate_done and context.gate_error.is_empty(),"real entry gate installs independent collision before reused visual publication"):dump_loading_state("reuse_gate_failed",context,null);await close_case(context);return
	var store:Node=map.get_node_or_null("CollisionInstanceResidency")
	var body:StaticBody3D=store.body_for("reuse_prop__Fixture__Solid") if store!=null else null
	print_case("entry_collision_ready",context,path)
	if not check(body!=null and namespace_count(map,"reuse_prop")==0,"verified collision body exists while the shared core render template still awaits reuse"):dump_loading_state("missing_independent_body",context,null);await close_case(context);return
	var id:=body.get_instance_id();var rid:=body.get_rid();var stamp:int=body.get_meta("stream_physics_published_frame")
	world._ready_for_play=true
	deferred.end_entry_loading(AABB(Vector3(ORIGIN.x-2,-100000,ORIGIN.z-2),Vector3(4,200000,4)))
	var clip:AABB=map.get_meta("entry_plan").safety_clip
	deferred.ensure_geometry(clip,"fixture_reuse");deferred.activate(world)
	deadline=Time.get_ticks_msec()+30000
	while not deferred.geometry_published(clip) and deferred.error.is_empty() and Time.get_ticks_msec()<deadline:
		Stream.sync(map,world,ORIGIN,Stream.LOAD_BUDGET);await process_frame
	if not deferred.geometry_published(clip):dump_loading_state("core_reuse_publication_failed",context,null)
	check(deferred.geometry_published(clip) and deferred.instance_errors.is_empty() and deferred.path_errors.is_empty(),"actual Deferred reuse publishes the complete namespace without geometry rejection")
	var after:=template_faces(owner)
	print("CORE_REUSE_AFTER ",JSON.stringify({"template":after,"profile":deferred.profile}))
	check(int(deferred.profile.get("reuse_reference_jobs",0))>0 and int(deferred.profile.get("reuse_face_jobs",0))>0 and int(deferred.profile.get("reuse_face_prepared_meshes",0))>0 and int(deferred.profile.get("reuse_face_fallbacks",0))==0,"real reuse transaction fills faces on a charged CPU worker without full-import fallback")
	check(is_same(AssetLibrary._scenes.get(path),owner) and after.faces>0,"successful receipt updates the same still-current core template")
	var promoted:Variant=map.get_meta("stream_bodies",{}).get("reuse_prop__Fixture__Solid")
	check(promoted==body and body.get_instance_id()==id and body.get_rid()==rid and int(body.get_meta("stream_physics_published_frame"))==stamp,"strict source validation promotes the same collision body, RID and physics watermark")
	await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(13,1,10),Vector3(13,1,14),1)
	var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==body and namespace_count(map,"reuse_prop")==2,"real collision remains continuous after shared-template visual handoff")
	await close_case(context)

func print_case(label:String,context:Dictionary,path:String)->void:
	var map:Node=context.map;var tree_meshes:Array=[];var nodes:Array[Node]=[map];var owned:Array=[]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if node is MeshInstance3D:tree_meshes.append({"path":str(map.get_path_to(node)),"uuid":node.get_meta("extras",{}).get("uuid",""),"mesh_id":node.mesh.get_instance_id() if node.mesh!=null else 0,"cpu_capture":node.mesh!=null and node.mesh.has_meta("ground_cpu_cache")})
		if node is StaticBody3D:owned.append({"path":str(map.get_path_to(node)),"uuid":node.get_meta("uuid",""),"id":node.get_instance_id(),"layer":node.collision_layer})
	var service:Node=map.get_node_or_null("CollisionDependencyLoader");var store:Node=map.get_node_or_null("CollisionInstanceResidency")
	var packed:Variant=AssetLibrary._scenes.get(path)
	print("CORE_REUSE_STATE ",JSON.stringify({"label":label,"path":path,"initial_ids":map.get_meta("stream_by_id",{}).keys(),"ordinary_body_ids":map.get_meta("stream_bodies",{}).keys(),"tree_meshes":tree_meshes,"all_bodies":owned,"template":template_faces(packed) if packed is PackedScene else {},"store":store.debug_snapshot() if store!=null else {},"service":service.snapshot() if service!=null else {},"instance":service.status("reuse_prop") if service!=null else {}}))

func finish(errors:RefCounted)->void:
	print("COLLISION_CORE_REUSE_GPU checks_before_log_check=",checks," failures=",failures)
	super.finish(errors)
