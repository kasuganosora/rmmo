extends SceneTree
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Cache=preload("res://scripts/world3d/navigation_cache.gd")
var failures:=0
var provider_ready:=false
var provider_calls:=0
var cache_paths:Array[String]=[]

class ProbeNavigation extends "res://scripts/world3d/world_navigation.gd":
	var submissions:=0
	func _add_source(_target:NavigationMeshSourceGeometryData3D,_spec:Dictionary)->bool:return true
	func _submit_bake()->void:submissions+=1

func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if not value:failures+=1
func spec(id:String,x:float=0.0,door:bool=false)->Dictionary:
	var shape:=BoxMesh.new();shape.size=Vector3(12,.2,12)
	var extra:Dictionary={"rmmo_collision":"walk"}
	if door:extra.fixture={"kind":"door","id":"door","open":0.0}
	return {"uuid":id,"mesh":shape,"transform":Transform3D(Basis.IDENTITY,Vector3(x,-.1,0)),"extras":extra}
func provide(_clip:AABB)->bool:
	provider_calls+=1;return provider_ready
func run()->void:
	create_timer(60).timeout.connect(func():print("DEFERRED_NAV_TIMEOUT");quit(2))
	var invalid:=Navigation.new();root.add_child(invalid);invalid.set_geometry_pending(true)
	invalid.build([spec("initial")])
	check(not invalid.map.is_valid() and not invalid.geometry_error.is_empty(),"pending build requires a finite spawn origin")
	check(invalid.find_path(Vector3.ZERO,Vector3.ONE).reason=="geometry_error","initial load failure is explicit to path callers")
	check(not invalid.append_specs([spec("early")]).ok,"prebuild append cannot be silently discarded by build")
	invalid.free()
	var nav:=ProbeNavigation.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	nav.runtime_geometry_key="deferred_probe_%d"%Time.get_ticks_usec()
	nav.set_geometry_pending(true);nav.configure_geometry_provider(provide)
	var initial:=spec("initial");var shared:Array=[initial]
	nav.build(shared,Vector3.ZERO)
	var node_id:=nav.get_instance_id();var map_id:=nav.map
	check(not is_same(shared,nav._specs) and is_same(initial,nav._specs[0]),"build owns array but preserves mutable spec references")
	shared.append(spec("caller_late"))
	check(nav._specs.size()==1,"stream library array additions do not duplicate navigation appends")
	nav._step_background()
	check(nav._staged and nav._clip.size.x==160 and nav._phase=="waiting_initial_geometry","pending small maps also wait for complete 160m initial geometry")
	check(nav.submissions==0 and nav._cache_key.is_empty() and nav._initial_cache_key.is_empty(),"pending build neither submits incomplete initial bake nor reads navigation caches")
	check(nav.find_path(Vector3.ZERO,Vector3.ONE).reason=="pending","initial incomplete geometry has pending path status")
	var added:=spec("late",100,true)
	check(nav.append_specs([added]).ok and nav._specs.size()==2 and shared.size()==2,"append modifies navigation array only")
	check(is_same(nav._doors[0],added),"append retains live door identity without baking moving door leaf")
	check(nav.append_specs([spec("far_static",120)]).ok and nav._bounds.end.x>=126,"static additions expand navigation bounds")
	var count:=nav._specs.size()
	check(not nav.append_specs([spec("safe"),spec("late")]).ok and nav._specs.size()==count,"existing duplicate rejects whole batch atomically")
	check(not nav.append_specs([spec("twice"),spec("twice")]).ok and nav._specs.size()==count,"duplicate inside batch rejects atomically")
	check(not nav.append_specs([spec("safe"),{"uuid":"bad"}]).ok and nav._specs.size()==count,"malformed late item cannot partially append")
	var nonfinite:=spec("nonfinite");nonfinite.transform.origin.x=INF
	check(not nav.append_specs([nonfinite]).ok,"nonfinite source transform is rejected")
	provider_ready=true;nav._step_background()
	check(nav.submissions==1,"complete initial geometry permits one initial bake")
	# Simulate publication; actual Recast/server publication is exercised below.
	nav.ready_for_queries=true;nav._local_clip=nav._clip;nav._start_full_bake()
	check(nav._phase=="waiting_geometry" and nav._full_mesh==null and not nav.fully_ready,"initial publication pauses full bake while catalog is pending")
	provider_ready=false;nav.follow(Vector3(78,0,0),Vector3(100,0,0))
	check(nav._nearby==null and nav._nearby_request is AABB,"nearby refresh waits for its geometry provider")
	check(nav.find_path(Vector3.ZERO,Vector3(100,0,0)).reason=="pending","remote path cannot use nearest-point projection on incomplete mesh")
	nav.set_geometry_error("source_failed")
	check(not nav.set_geometry_pending(false) and nav.geometry_pending,"failure cannot mark catalog complete")
	check(nav.find_path(Vector3.ZERO,Vector3(100,0,0)).reason=="geometry_error","remote failure remains visible while existing local navigation survives")
	nav.set_geometry_error("");provider_ready=true;nav._try_nearby_request()
	check(nav._nearby!=null and nav._nearby_request==null,"provider readiness releases queued nearby bake")
	nav._nearby=null
	check(nav.set_geometry_pending(false) and nav._full_started and nav._full_mesh!=null,"catalog completion starts full bake")
	var full_mesh_id:=nav._full_mesh.get_instance_id();nav.set_geometry_pending(false)
	check(nav._full_mesh.get_instance_id()==full_mesh_id and nav.get_instance_id()==node_id and nav.map==map_id,"completion is idempotent and preserves navigation Node and map")
	check(is_equal_approx(nav._full_mesh.cell_size,.1) and is_equal_approx(nav._full_mesh.cell_height,.1) and is_equal_approx(nav._full_mesh.agent_max_climb,.4),"deferred full bake retains existing geometry precision")
	check(not nav.set_geometry_pending(true) and not nav.append_specs([spec("too_late")]).ok,"completed catalog cannot reopen or append silently")
	nav.free()
	check_deferred_height()
	await integration()
	for path in cache_paths:DirAccess.remove_absolute(path)
	print("DEFERRED_NAVIGATION_FINISHED failures=",failures);quit(1 if failures else 0)

func check_deferred_height()->void:
	provider_ready=false
	var nav:=ProbeNavigation.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	nav.set_geometry_pending(true);nav.configure_geometry_provider(provide)
	nav.build([spec("base")],Vector3.ZERO);nav._step_background()
	var old_clip:AABB=nav._clip
	var high:=spec("upper_initial");high.transform.origin.y=40
	check(nav.append_specs([high]).ok,"initial provider can supply upper-floor geometry")
	provider_ready=true;nav._step_background()
	check(nav._clip.end.y>40 and nav.mesh.filter_baking_aabb==nav._clip and nav._local_clip==nav._clip,"initial readiness expands vertical bake bounds after geometry append")
	check(nav._clip.position.x==old_clip.position.x and nav._clip.position.z==old_clip.position.z and nav._clip.size.x==160 and nav._clip.size.z==160,"initial height expansion preserves exact X/Z closure")
	nav.ready_for_queries=true;nav._start_full_bake();provider_ready=false
	nav.follow(Vector3(78,0,0),Vector3(100,0,0))
	var request:AABB=nav._nearby_request
	var lower:=spec("lower_nearby",100);lower.transform.origin.y=-40
	check(nav.append_specs([lower]).ok,"pending nearby provider can supply a lower floor")
	provider_ready=true;var calls:=provider_calls;nav._try_nearby_request()
	check(nav._nearby!=null and nav._nearby.clip.position.y< -40 and nav._nearby.clip.end.y==request.end.y,"nearby request expands lower bound without losing existing upper floors")
	check(nav._nearby.clip.position.x==request.position.x and nav._nearby.clip.position.z==request.position.z and nav._nearby.clip.size.x==request.size.x and nav._nearby.clip.size.z==request.size.z and provider_calls==calls+1,"height expansion needs one X/Z completeness query and preserves horizontal footprint")
	nav._nearby=null;nav.free()

func integration()->void:
	provider_ready=false
	var nav:=Navigation.new();root.add_child(nav)
	nav.runtime_geometry_key="deferred_real_%d"%Time.get_ticks_usec()
	nav.set_geometry_pending(true);nav.configure_geometry_provider(provide)
	nav.build([spec("floor")],Vector3.ZERO)
	for i in 4:await process_frame
	check(not nav.ready_for_queries and nav._bake_pending.is_empty(),"real server waits before initial source collection")
	provider_ready=true
	while not nav.ready_for_queries:await process_frame
	check(not nav.fully_ready and nav._phase=="waiting_geometry" and nav._full_mesh==null,"real initial region publishes while full bake remains paused")
	check(nav.find_path(Vector3(-2,.05,0),Vector3(2,.05,0)).ok,"complete spawn region supports local gameplay during remote loading")
	check(nav._cache_writer==null and nav._initial_cache_key.is_empty(),"real partial navigation writes no cache while geometry pending")
	check(nav.append_specs([spec("remote",100)]).ok,"real remote geometry appends after initial publication")
	check(nav.set_geometry_pending(false),"real catalog can complete after all additions")
	while not nav.fully_ready:await process_frame
	check(nav.mesh.get_polygon_count()>0 and nav.find_path(Vector3(98,.05,0),Vector3(102,.05,0)).ok,"full publication includes appended remote floor")
	cache_paths.append(Cache.path(nav._cache_key))
	var identity:String=nav.runtime_geometry_key
	nav.free()
	var warm:=Navigation.new();root.add_child(warm);warm.runtime_geometry_key=identity
	warm.set_geometry_pending(true);warm.configure_geometry_provider(provide)
	warm.build([spec("floor")],Vector3.ZERO)
	while not warm.ready_for_queries:await process_frame
	check(not warm._cache_hit and warm._cache_key.is_empty() and not warm.fully_ready,"existing full cache remains unread while catalog is incomplete")
	warm.append_specs([spec("remote",100)]);warm.set_geometry_pending(false)
	while not warm.fully_ready:await process_frame
	check(warm._cache_hit and warm.find_path(Vector3(98,.05,0),Vector3(102,.05,0)).ok,"complete catalog safely enables full-cache restoration")
	warm.free()
