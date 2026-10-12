extends SceneTree
## Scheduling and real NavigationServer handoff, no Recast bake or GPU upload.
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Player=preload("res://scripts/world3d/world_player.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const START:=Vector3(321.2,0,160.3)
const GOAL:=Vector3(292.9,0,151.4)
const LOCAL:=AABB(Vector3(307.2,-2,146.3),Vector3(44.8,8,45.7))
class Probe extends "res://scripts/world3d/world_navigation.gd":
	func near_surface(_point:Vector3,_horizontal:float=.18,_vertical:float=.4)->bool:return false
class EmptyNearby extends RefCounted:
	var mesh:=NavigationMesh.new()
	var source:=NavigationMeshSourceGeometryData3D.new()
	var clip:=AABB()
	var baking:=false
	var complete:=true
	var started_ms:=0
	func step(_owner:Node,_budget:int)->void:pass
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func make_nav(state:Dictionary)->Node:
	var nav:=Probe.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	nav.initial_geometry_clip=LOCAL
	nav.configure_streaming_geometry(func(area:AABB)->Variant:
		state.clips.append(area)
		return {"ok":state.ready,"error":state.failure} if state.has("failure") else state.ready,
		func():state.released+=1)
	nav._bounds=AABB(Vector3(0,-1,0),Vector3(800,42,800));nav._has_bounds=true
	nav.ready_for_queries=true;nav._staged=true;nav._local_clip=LOCAL
	return nav
func release(nav:Node)->void:
	nav._nearby=null;nav._nearby_request=null;nav.free()
func fake_complete(nav:Node,empty:bool=false)->void:
	if empty:
		nav._nearby_request=null;nav._nearby=EmptyNearby.new();nav._nearby.clip=nav._foreground_clip
		nav._nearby_generation=nav._request_generation;nav._step_nearby()
	else:
		nav._local_clip=nav._foreground_clip;nav._nearby_request=null;nav._foreground_waiting=false;nav.version+=1
func scheduling()->void:
	var state:={"clips":[],"ready":false,"released":0}
	var nav:=make_nav(state)
	check(nav.find_foreground_path(START,GOAL).reason=="pending","problem-town short click waits for actual geometry")
	var first:AABB=nav._nearby_request;var generation:int=nav._request_generation
	check(is_equal_approx(first.size.x,60.3) and is_equal_approx(first.size.z,40.9) and first.size.x*first.size.z<2500,"30m route demands about 2466 square metres, not 36864")
	check(first.has_point(START) and first.has_point(GOAL),"corridor includes both endpoints and a 16m detour halo")
	for i in 20:nav.find_foreground_path(START,GOAL);nav.follow(START)
	check(nav._request_generation==generation and nav._foreground_level==0 and nav._nearby_request==first and state.released==1,"same pending goal and per-frame idle follow do not restart or enlarge demand")
	for i in 10:
		nav.find_path(START,START+Vector3(1,0,1))
		nav.find_path(START,START+Vector3(80,0,20))
	check(nav._request_generation==generation and nav._foreground_goal==GOAL and nav._nearby_request==first and state.released==1,"interleaved NPC local and remote queries cannot cancel or replace player corridor")
	check(nav._nearby==null,"incomplete all-height provider cannot start a bake")
	state.ready=true;nav._try_nearby_request()
	check(nav._nearby!=null and nav._nearby.clip.end.y>=43,"complete provider preserves appended upper-storey bounds")
	var obsolete:RefCounted=nav._nearby
	state.ready=false;var changed:=GOAL+Vector3(0,0,12)
	nav.find_foreground_path(START,changed)
	check(nav._request_generation>generation and state.released==2 and nav._foreground_goal==changed,"new goal revokes the old provider demand and changes generation")
	nav._step_nearby()
	check(nav._nearby==null and obsolete.cursor==0 and nav._nearby_request==nav._foreground_clip,"obsolete source scan is discarded without advancing it or publishing old clip")
	check(not nav.cancel_foreground_request(GOAL) and nav._foreground_goal==changed,"an old actor goal cannot cancel a replacement request")
	check(nav.cancel_foreground_request(changed) and nav._nearby_request==null and nav._foreground_goal==null and state.released==3,"explicit cancellation clears the request and releases its dependency ticket")
	nav.find_foreground_path(START,GOAL)
	var ceiling:AABB=nav._legacy_follow_area(START,GOAL)
	for level in 4:
		check(nav._foreground_level==level and ceiling.encloses(nav._foreground_clip),"expansion level "+str(level)+" stays inside the legacy maximum")
		generation=nav._request_generation
		for i in 5:nav.find_foreground_path(START,GOAL)
		check(nav._request_generation==generation,"pending level "+str(level)+" cannot expand once per repeated query")
		fake_complete(nav)
		var result:Dictionary=nav.find_foreground_path(START,GOAL)
		check(result.reason==("pending" if level<3 else "unreachable"),"only a complete current clip no-route result advances level "+str(level))
	check(nav._foreground_level==3 and nav._foreground_clip==ceiling and nav._foreground_no_path,"final fallback covers the original detour footprint and terminates")
	nav.cancel_foreground_request();nav._local_clip=LOCAL
	var count:int=state.clips.size()
	check(nav.find_foreground_path(START,START+Vector3(300,0,0)).reason=="pending" and state.clips.size()==count,"distant goal preserves legacy pending behavior without a new rejection or map-wide box")
	nav.find_foreground_path(START,GOAL);fake_complete(nav,true)
	check(nav._foreground_level==1 and nav._foreground_waiting and nav._nearby_request!=null,"complete empty bake expands without replacing usable resident mesh")
	nav.cancel_foreground_request();nav._local_clip=LOCAL
	nav.follow(Vector3(351,0,170));var manual:AABB=nav._nearby_request;generation=nav._request_generation
	nav.follow(Vector3(351.1,0,170))
	check(manual.size.x==32. and nav._nearby_request==manual and nav._request_generation==generation,"manual edge prefetch stays compact and stable under sub-metre movement")
	var report:Dictionary=nav.capability_status()
	check(report.has("foreground_generation") and report.has("geometry_wait_reason") and not JSON.stringify(report).is_empty(),"query and geometry diagnostics are serializable")
	nav.cancel_foreground_request();nav.find_path(START,GOAL)
	check(nav._nearby_request==nav._legacy_follow_area(START,GOAL) and nav._foreground_goal==null,"passive actor retains legacy detour scope without owning player foreground slot")
	release(nav)

func server_handoff()->void:
	var state:={"clips":[],"ready":false,"released":0};var nav:=make_nav(state)
	nav.map=NavigationServer3D.map_create();NavigationServer3D.map_set_active(nav.map,true)
	nav.region=NavigationServer3D.region_create();NavigationServer3D.region_set_map(nav.region,nav.map)
	nav.find_foreground_path(START,GOAL)
	var old_generation:int=nav._request_generation
	var old_clip:AABB=nav._foreground_clip
	var nearby:=EmptyNearby.new();nearby.clip=old_clip
	nearby.mesh.set_vertices(PackedVector3Array([Vector3(290,0,145),Vector3(330,0,145),Vector3(330,0,170),Vector3(290,0,170)]))
	nearby.mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	nav._nearby_request=null;nav._nearby=nearby;nav._nearby_generation=old_generation;nav._step_nearby()
	check(nav._nearby_publish_wait>0 and nav._foreground_waiting,"submitting a mesh is not readiness before server synchronization")
	var replacement:=Vector3(370,0,170);nav.find_foreground_path(START,replacement)
	check(nav._request_generation!=old_generation and nav._foreground_waiting,"new target during submitted server update remains pending")
	for i in 120:
		await physics_frame;nav._step_publication()
		if nav._nearby_publish_wait==0:break
	check(nav._nearby_publish_wait==0 and nav._local_clip==old_clip and nav._foreground_waiting,"old submitted map settles to factual old clip without completing new-generation target")
	check(nav.find_foreground_path(START,replacement).reason=="pending" and nav._foreground_level==0,"old map cannot bypass replacement geometry proof")
	var player:=Player.new();var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player);player.set_physics_process(false)
	player.global_position=START+Vector3.UP*.9;player.navigation=nav
	player.set_click_target(replacement,"ground");var generation:int=nav._request_generation
	player.set_click_target(replacement,"ground")
	check(player._pending_click==replacement and nav._foreground_goal==replacement and nav._request_generation==generation,"Player internal null while pending preserves idempotent foreground request")
	player.click_target=null
	check(player._pending_click==null and nav._foreground_goal==null and nav._nearby_request==null,"ordinary Player clear cancels demand as well as delayed movement")
	player.set_click_target(replacement,"ground");state.failure="missing_destination_asset"
	nav._try_nearby_request();var revision:int=nav.version
	check(nav.capability_status().geometry_error==state.failure and nav.geometry_error.is_empty() and nav.ready_for_queries,"provider resource failure is scoped to requested clip while old map remains usable")
	player._refresh_navigation_request()
	check(player._pending_click==null and player.path_status.reason=="geometry_error" and nav._foreground_goal==null and nav._nearby_request==null and nav.version==revision,"failed Player request releases its matching demand and terminates without a fake nav revision")
	state.failure="";player.set_click_target(replacement,"ground")
	check(player.path_status.reason=="pending" and player._pending_click==replacement and nav._query_geometry_error().is_empty(),"same target can retry after its resource is repaired; old scoped error never blocks provider")
	player.set_click_target(replacement,"ground");var synchronized_version:int=nav.version
	nav.set_geometry_error("foreground_resource_failed");player._refresh_navigation_request()
	check(player._pending_click==null and player.path_status.reason=="geometry_error" and nav._foreground_goal==null and nav.version==synchronized_version and nav.ready_for_queries,"asynchronous global geometry error terminates Player pending without inventing a synchronized revision or disabling resident mesh")
	player.free();release(nav)
	state={"clips":[],"ready":false,"released":0,"failure":"initial_asset_failure"};nav=make_nav(state);nav.ready_for_queries=false
	check(not nav._ensure_geometry(LOCAL) and nav.geometry_error==state.failure and nav.capability_status().state=="failed","failed initial geometry with no resident mesh remains an explicit global capability failure")
	release(nav)

func request_deadline()->void:
	var state:={"clips":[],"ready":false,"released":0};var nav:=make_nav(state)
	check(nav.foreground_timeout_msec==180000,"foreground default deadline is independently bounded to 180 seconds")
	var player:=Player.new();var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player);player.set_physics_process(false)
	player.global_position=START+Vector3.UP*.9;player.navigation=nav
	player.set_click_target(GOAL,"ground")
	var deadline:int=nav._foreground_deadline_msec;var generation:int=nav._request_generation
	for i in 10:player.set_click_target(GOAL,"ground")
	check(nav._foreground_deadline_msec==deadline and nav._request_generation==generation,"repeated active clicks while still pending cannot extend the deadline")
	fake_complete(nav);player._refresh_navigation_request()
	check(nav._foreground_level==1 and nav._foreground_deadline_msec==deadline,"complete no-route expansion keeps the first attempt deadline")
	var version:int=nav.version;var releases:int=state.released
	nav._poll_foreground_deadline(deadline)
	check(nav._foreground_timed_out and not nav._foreground_waiting and nav._nearby_request==null and state.released==releases+1,"deadline expires without sleeping and releases the exact dependency ticket")
	check(nav.ready_for_queries and nav.version==version and nav.capability_status().foreground_terminal_reason=="navigation_timeout","timeout preserves resident mesh and synchronized revision, with explicit foreground terminal status")
	generation=nav._request_generation;var calls:int=state.clips.size()
	var all_terminal:=true
	for i in 10:all_terminal=all_terminal and nav.find_foreground_path(START,GOAL,.65,false).reason=="navigation_timeout"
	check(all_terminal and nav._request_generation==generation and state.clips.size()==calls,"automatic polls cannot clear timeout or restart resource preparation")
	player._refresh_navigation_request()
	check(player._pending_click==null and player.path_status.reason=="navigation_timeout" and nav._foreground_goal==null and nav._foreground_deadline_msec<0,"Player automatic refresh consumes timeout once and clears its delayed movement")
	generation=nav._request_generation
	for i in 10:player._refresh_navigation_request()
	check(nav._request_generation==generation and player.path_status.reason=="navigation_timeout","subsequent Player ticks do not silently retry a timed-out click")
	player.set_click_target(GOAL,"ground")
	check(player._pending_click==GOAL and player.path_status.reason=="pending" and nav._foreground_deadline_msec>=Time.get_ticks_msec() and not nav._foreground_timed_out,"a new user click starts a fresh attempt after terminal consumption")
	nav._poll_foreground_deadline(nav._foreground_deadline_msec)
	check(nav.find_foreground_path(START,GOAL,.65).reason=="pending" and not nav._foreground_timed_out,"explicit user retry can also replace an unconsumed terminal receipt")
	state.ready=true;nav._try_nearby_request();check(nav._nearby!=null,"late-source fixture owns a prepared current-generation source")
	version=nav.version;nav._poll_foreground_deadline(nav._foreground_deadline_msec);nav._step_nearby()
	check(nav._nearby==null and nav.version==version,"late source after timeout drains without publication or fake readiness")
	state.ready=false;player.set_click_target(GOAL,"ground")
	var previous_budget:bool=FrameBudget.enabled;FrameBudget.enabled=true;FrameBudget._shared=null
	FrameBudget.shared().record(Engine.get_process_frames(),"navigation",500)
	nav._foreground_deadline_msec=Time.get_ticks_msec()-1;nav._process(0)
	check(nav._foreground_timed_out and nav._nearby_request==null,"exhausted production budget does not hide timeout observation or lease release")
	FrameBudget.enabled=previous_budget;FrameBudget._shared=null
	player.click_target=null
	check(nav._foreground_deadline_msec<0 and not nav._foreground_timed_out,"explicit cancellation clears deadline and terminal receipt")
	player.set_click_target(START+Vector3(300,0,0),"ground");nav._poll_foreground_deadline(nav._foreground_deadline_msec);player._refresh_navigation_request()
	check(player.path_status.reason=="navigation_timeout" and player._pending_click==null,"legacy distant pending query also terminates without a map-wide preload")
	player.free();release(nav)
func run()->void:
	create_timer(30).timeout.connect(func():print("NAV_CORRIDOR_TIMEOUT");quit(2))
	scheduling();await server_handoff();request_deadline()
	print("NAVIGATION_CORRIDOR passed=",passed," failures=",failures);quit(1 if failures else 0)
