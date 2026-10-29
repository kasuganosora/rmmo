extends "res://tools/test_collision_instance_residency_gpu.gd"
## Real MapLoader -> Deferred collision coordinator -> World entry gate.
## Private desktop only; every map and GLB is a temporary test-owned resource.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const GameWorld=preload("res://scripts/world3d/world_3d.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Cover=preload("res://scripts/world3d/transfer_loading.gd")
const ORIGIN:=Vector3(4,.9,4)
var _old_collision_first:=false

class GuardWorld extends GameWorld:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
	func _loading_stage(stage:String,done:int=0,total:int=0)->void:
		loading_state={"stage":stage,"done":done,"total":total}

func ground()->Dictionary:
	return {"uuid":"real_floor","kind":"box","position":[64,-.25,16],"rotation":[0,0,0],"size":[160,.5,64],"surface_id":"ground","collision":"walk"}

func model(id:String,path:String,position:Vector3)->Dictionary:
	return {"uuid":id,"kind":"asset","asset_path":path,"position":[position.x,position.y,position.z],"rotation":[0,0,0],"size":[1,1,1],"collision":""}

func load_map(records:Array,label:String)->Dictionary:
	var author:Dictionary=files.fixture(label,records,{"spawn":[ORIGIN.x,ORIGIN.y,ORIGIN.z]})
	if not check(not author.is_empty() and Index.build(author.path,files.content_root,records).ok,"real temporary reference directory builds: "+label):return {}
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader);loader.start(author.path,ORIGIN)
	var loaded:Array=await loader.finished
	if not check(loaded[0] is Node3D,"real MapLoader completes: "+label):print(loaded[2]);return {}
	var map:Node3D=loaded[0]
	var prefetched:Node=map.get_node_or_null("CollisionDependencyLoader")
	var prefetch_id:int=prefetched.get_instance_id() if prefetched!=null else 0
	var prefetch_snapshot:Dictionary=prefetched.snapshot() if prefetched!=null else {}
	var off_tree_store:bool=map.get_node_or_null("CollisionInstanceResidency")!=null
	var world:=GuardWorld.new();root.add_child(world)
	world.add_child(map);world._map_root=map;world._map_path=author.path
	return {"world":world,"map":map,"path":author.path,"deferred":map.get_node_or_null("DeferredAssets"),"gate_done":false,"gate_error":"","prefetch_id":prefetch_id,"prefetch_snapshot":prefetch_snapshot,"off_tree_store":off_tree_store}

func begin_gate(context:Dictionary,cover:CanvasLayer)->void:
	context.gate_error=await context.world._prepare_entry_geometry(context.map,context.world,ORIGIN,cover)
	context.gate_done=true

func namespace_count(map:Node,id:String)->int:
	var count:=0
	for uuid:String in map.get_meta("stream_by_id",{}):
		if uuid.begins_with(id+"__"):count+=1
	return count

func dump_loading_state(label:String,context:Dictionary,navigation:Node)->void:
	var deferred:Node=context.deferred;var jobs:Array=[];var pending:Array=[]
	for path:String in deferred._jobs:
		var job:Dictionary=deferred._jobs[path];var result:Dictionary=job.get("result",{})
		jobs.append({"path":path,"stage":job.get("stage",""),"accepted":job.get("accepted",false),"cancelled":job.token.is_cancelled(),"worker_alive":job.worker.is_alive() if job.has("worker") else false,"result_keys":result.keys(),"error":result.get("error",""),"waiting_pixels":result.get("waiting_pixels",false),"publication_ids":job.get("publication_ids",[]),"collision_staged":job.get("collision_staged",{}).keys()})
	for item:Dictionary in deferred.pending:
		pending.append({"uuid":item.record.uuid,"path":item.path,"published":item.get("published",false),"reference_prepared":item.get("reference_prepared",false),"model_verified":item.get("model_verified",false),"demanded":deferred._demanded_by_id.has(item.record.uuid)})
	var service:Node=context.map.get_node_or_null("CollisionDependencyLoader")
	print("COLLISION_FIRST_DIAGNOSTIC ",JSON.stringify({"label":label,"host_ready":context.world._ready_for_play,"active":deferred._active,"processing":deferred.is_processing(),"entry_allowed":deferred._entry_loading_allowed(),"scope":deferred.get_demand_scope(),"demands":deferred._demands,"error":deferred.error,"path_errors":deferred.path_errors,"instance_errors":deferred.instance_errors,"profile":deferred.profile,"admission":deferred._admission.snapshot(),"prepared_paths":deferred._prepared_paths.keys(),"pending":pending,"jobs":jobs,"collision":service.snapshot() if service!=null else {},"navigation":navigation.capability_status() if navigation!=null else {}}))

func close_case(context:Dictionary)->void:
	if context.is_empty():return
	var deferred:Node=context.deferred
	if is_instance_valid(deferred):await deferred.quiesce()
	var service:Node=context.map.get_node_or_null("CollisionDependencyLoader")
	if service!=null:service.cancel("fixture_complete")
	if is_instance_valid(context.world._navigation):
		if not context.world._navigation.retire_background("fixture_complete"):context.world._navigation.queue_free()
	context.world.queue_free()
	await process_frame;await process_frame

func run()->void:
	create_timer(180).timeout.connect(func():push_error("collision-first loading GPU timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	_old_collision_first=Deferred.collision_first_enabled;Deferred.collision_first_enabled=true
	files=Base.Files.new();files.content_root=Paths.external_root();files.folder=Paths.cache_directory("collision_first_loading_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var cached_path:String=files.folder.path_join("cached_openings.glb");write_glb(cached_path);files.created.append(cached_path)
	var missing_path:String=files.folder.path_join("uncached_openings.glb");write_glb(missing_path);files.created.append(missing_path)
	var estimate:=Builder.estimate(cached_path,files.content_root);var ledger:=Admission.new()
	if not check(not estimate.is_empty() and ledger.reserve("build",estimate),"offline fixture sidecar has full resource admission"):finish(errors);return
	var built:=await worker(Builder.build.bind(cached_path,files.content_root,estimate.estimated_bytes));ledger.park("build")
	var built_ok:bool=built.get("ok",false);check(built_ok,"exact collision sidecar generated from real GLB")
	Drainer.dispose_result(built);ledger.release("build")
	if not built_ok:finish(errors);return
	await collision_first_case(cached_path,missing_path)
	await conservative_core_case(missing_path,Vector3(16,0,12),"missing_sidecar")
	await conservative_core_case(cached_path,Vector3(4,0,4),"landing_support")
	finish(errors)

func collision_first_case(cached_path:String,missing_path:String)->void:
	var records:Array=[ground(),model("early_prop",cached_path,Vector3(16,0,12)),model("far_fallback",missing_path,Vector3(80,0,12))]
	var context:=await load_map(records,"collision_first")
	if context.is_empty():return
	var map:Node=context.map;var world:Node=context.world;var deferred:Node=context.deferred
	var profile:Dictionary=map.get_meta("load_profile",{})
	check(profile.get("collision_first_core_deferred",0)==1 and profile.get("initial_asset_paths",-1)==0,"eligible core GLB leaves initial model preparation while real floor stays initial")
	check(namespace_count(map,"early_prop")==0 and deferred!=null,"MapLoader preserves pending author record without a dummy render namespace")
	var dispatch:int=context.prefetch_snapshot.get("prefetch_first_dispatch_us",0)
	check(context.prefetch_id>0 and dispatch>0 and dispatch<int(profile.get("core_resources_ready_us",0)),"real MapLoader dispatches independent collision CPU work before core resource preparation finishes")
	check(not context.off_tree_store and map.get_node_or_null("CollisionInstanceResidency")==null and context.prefetch_snapshot.get("phase","")=="handoff","CPU prefetch hands off without installing any physics Store before the entry gate")
	if deferred==null:await close_case(context);return
	var cover:=Cover.new();world.add_child(cover);await cover.wait_until_drawn()
	check(cover.drawn_frame>=0 and DisplayServer.get_name()!="headless","real loading cover is drawn before entry preparation")
	deferred.set_demand_scope(["fixture_prior_scope"])
	begin_gate(context,cover)
	# Hold only the existing render queue. Requests and the independent collision
	# service still run normally; no injected readiness or fabricated Batch.
	deferred._active=false;deferred.set_process(false)
	var deadline:=Time.get_ticks_msec()+30000
	while not context.gate_done and Time.get_ticks_msec()<deadline:await process_frame
	check(context.gate_done and context.gate_error.is_empty(),"actual World entry geometry gate completes while render publication is deliberately held")
	if not context.gate_done or not context.gate_error.is_empty():print(context);await close_case(context);return
	var plan:Dictionary=map.get_meta("entry_plan");var clip:AABB=plan.safety_clip
	check(deferred.ensure_collision(clip,"entry_safety") and not deferred.geometry_published(clip) and namespace_count(map,"early_prop")==0,"exact collision closure is ready before full visual geometry")
	var store:Node=map.get_node_or_null("CollisionInstanceResidency")
	var service:Node=map.get_node_or_null("CollisionDependencyLoader")
	if not check(store!=null and service!=null and service.status("early_prop").ok,"real worker coordinator installed the selected authored instance"):await close_case(context);return
	var stores:=0
	for child:Node in map.get_children():
		if child.get_script()==Residency:stores+=1
	check(service.get_instance_id()==context.prefetch_id and service.snapshot().phase=="adopted" and stores==1,"entry gate adopts the same prefetched coordinator and creates exactly one collision Store")
	var early:StaticBody3D
	for child:Node in map.get_children():
		if child is StaticBody3D and str(child.get_meta("uuid","")).begins_with("early_prop__") and str(child.get_meta("uuid","")).ends_with("__Solid"):
			early=child;break
	if not check(early!=null,"real imported node UUID identifies the independently resident body"):await close_case(context);return
	var body_id:=early.get_instance_id();var body_rid:=early.get_rid();var body_uuid:String=early.get_meta("uuid")
	var query:=PhysicsRayQueryParameters3D.create(Vector3(13,1,10),Vector3(13,1,14),1)
	var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==early,"ray hits the actual sidecar wall before any render node exists")
	# Exit the real entry phase while the independent wall still has no render
	# namespace. A restricted previous scope must not drop the only owning lease.
	# Real World.activate_entry_neighbours runs only after this host state is
	# true. Once the cover lease ends, a never-playable host correctly blocks
	# ordinary Deferred publication even if activate() is called again.
	world._ready_for_play=true
	deferred.end_entry_loading(AABB(Vector3(ORIGIN.x-2,-100000,ORIGIN.z-2),Vector3(4,200000,4)))
	var scope:Array=deferred.get_demand_scope()
	check(scope.has("fixture_prior_scope") and scope.has("player_collision") and not scope.has("entry_safety"),"restricted entry scope explicitly transfers to the player and camera ticket")
	check(is_instance_valid(early) and early.get_instance_id()==body_id and early.get_rid()==body_rid and early.collision_layer==1 and service.status("early_prop").ok,"real entry-to-player transfer retains the exact installed body and physics RID")
	await physics_frame;await process_frame
	hit=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==early and namespace_count(map,"early_prop")==0,"collision remains present after the next physics tick with visuals still withheld")
	# The rest of this fixture exercises ordinary navigation and independent
	# region requests outside that intentionally restricted prior-owner scope.
	deferred.set_demand_scope([])
	deferred.allow_demand_in_scope("fixture_manual")
	check(world._map_traversal_receipt(map,clip,"fixture_manual").ok,"normal World traversal receipt accepts exact collision coverage while visuals remain pending")
	var policy_world:=GameWorld.new()
	var original_background:bool=GameWorld.navigation_background_enabled;GameWorld.navigation_background_enabled=false
	check(policy_world._navigation_async(map),"collision-first map uses effective asynchronous navigation without claiming navigation ready")
	GameWorld.navigation_background_enabled=original_background
	policy_world.free()
	var navigation:=Navigation.new();world.add_child(navigation);world._navigation=navigation
	navigation.initial_geometry_clip=plan.navigation_clip
	world._bind_deferred_geometry(map,navigation);world._bind_navigation_lifetime(navigation,map)
	navigation.build(map.get_meta("stream_library",[]),ORIGIN)
	# Provider demand changes may re-enable _process only when _active is true.
	for i in 4:await process_frame
	check(not navigation.ready_for_queries and not deferred.geometry_published(clip),"ordinary navigation stays pending behind its complete geometry provider")
	var far_clip:=AABB(Vector3(73,-100000,7),Vector3(38,200000,10))
	deferred.allow_demand_in_scope("fixture_missing")
	check(not deferred.ensure_collision(far_clip,"fixture_missing"),"uncached remote GLB cannot borrow another instance's collision readiness")
	deadline=Time.get_ticks_msec()+10000
	while service.status("far_fallback").state not in ["fallback","failed"] and Time.get_ticks_msec()<deadline:
		deferred.ensure_collision(far_clip,"fixture_missing");await process_frame
	check(service.status("far_fallback").state=="fallback" and not deferred.ensure_collision(far_clip,"fixture_missing") and namespace_count(map,"far_fallback")==0,"missing sidecar requires ordinary full publication and does not fake readiness")
	deferred.release_demand("fixture_missing")
	check(service.status("far_fallback").state=="unrequested" and service.status("early_prop").ok,"withdrawing another region's ticket preserves still-required core collision")
	deferred.ensure_geometry(far_clip,"fixture_missing");deferred.allow_demand_in_scope("fixture_missing")
	deferred.activate(world)
	deadline=Time.get_ticks_msec()+30000
	while (not deferred.geometry_published(clip) or not deferred.geometry_published(far_clip)) and Time.get_ticks_msec()<deadline:
		Stream.sync(map,world,ORIGIN,Stream.LOAD_BUDGET);await process_frame
	if not deferred.geometry_published(clip) or not deferred.geometry_published(far_clip):dump_loading_state("visual_resume_timeout",context,navigation)
	check(deferred.geometry_published(clip) and deferred.geometry_published(far_clip),"restored ordinary queue completes both promoted and fallback visuals")
	Stream.sync(map,world,ORIGIN,Stream.LOAD_BUDGET)
	var body:Variant=map.get_meta("stream_bodies",{}).get(body_uuid)
	check(is_instance_valid(body) and body.get_instance_id()==body_id and body.get_rid()==body_rid and namespace_count(map,"early_prop")==2,"real Deferred publication hands off the same exact body under the complete UUID namespace")
	check(deferred.ensure_collision(far_clip,"fixture_missing") and namespace_count(map,"far_fallback")==2,"uncached instance becomes dependency-ready only after normal complete render publication")
	deadline=Time.get_ticks_msec()+15000
	while not navigation.ready_for_queries and navigation.capability_status().state=="pending" and Time.get_ticks_msec()<deadline:await process_frame
	if not navigation.ready_for_queries:dump_loading_state("navigation_not_ready",context,navigation)
	check(navigation.ready_for_queries,"navigation eventually becomes genuinely queryable after complete geometry arrives")
	await physics_frame;await process_frame
	hit=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==body,"collision remains continuous after the actual render promotion")
	await close_case(context)

func conservative_core_case(path:String,position:Vector3,label:String)->void:
	var context:=await load_map([ground(),model("required_prop",path,position)],label)
	if context.is_empty():return
	var profile:Dictionary=context.map.get_meta("load_profile",{})
	check(profile.get("collision_first_core_deferred",0)==0 and profile.get("initial_asset_paths",0)==1,"conservative core import is retained: "+label)
	var cover:=Cover.new();context.world.add_child(cover);await cover.wait_until_drawn()
	var error:String=await context.world._prepare_entry_geometry(context.map,context.world,ORIGIN,cover)
	check(error.is_empty() and namespace_count(context.map,"required_prop")==2,"conservative case finishes through ordinary full geometry: "+label)
	# An empty coordinator may retain the camera/movement ticket interface even
	# when all relevant records already followed the ordinary core path. The
	# invariant is no extra preparation or collision ownership, not node absence.
	var service:Node=context.map.get_node_or_null("CollisionDependencyLoader")
	var snapshot:Dictionary=service.snapshot() if service!=null else {}
	var store:Dictionary=snapshot.get("store",{})
	check(int(snapshot.get("plan_jobs",0))==0 and int(snapshot.get("prepare_jobs",0))==0 and int(snapshot.get("accepted",0))==0 and int(snapshot.get("pending",0))==0 and int(store.get("instances",0))==0 and int(store.get("owned_bodies",0))==0,"conservative core starts no duplicate collision jobs or ownership: "+label)
	await close_case(context)

func finish(errors:RefCounted)->void:
	Deferred.collision_first_enabled=_old_collision_first
	if files!=null:files.free();files=null
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_FIRST_LOADING_GPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
