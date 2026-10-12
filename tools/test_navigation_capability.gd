extends SceneTree
## CPU/server synchronization only. No Recast bake, imported model or GPU scene.
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Player=preload("res://scripts/world3d/world_player.gd")
const Combat=preload("res://scripts/world3d/world_combat.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
class Probe extends "res://scripts/world3d/world_navigation.gd":
	var work_calls:=0
	func _step_background()->void:work_calls+=1
class WorldStub extends Node3D:
	var _navigation:Node
	var actions:Array=[]
	func apply_actions(value:Array)->void:actions.append_array(value)
class RouteStub extends Node:
	var ready_for_queries:=false
	var version:=0
	var state:="pending"
	var calls:=0
	func capability_status()->Dictionary:return {"ok":state=="ready","state":state,"reason":state,"version":version}
	func find_path(start:Vector3,goal:Vector3,_tolerance:float)->Dictionary:
		calls+=1
		return {"ok":true,"reason":"","path":PackedVector3Array([start,goal]),"version":version} if state=="ready" else {"ok":false,"reason":"pending" if state=="pending" else "navigation_failed","path":PackedVector3Array()}
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func mounted(script:GDScript=Navigation)->Node:
	var nav:Node=script.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false);return nav
func run()->void:
	create_timer(30).timeout.connect(func():print("NAVIGATION_CAPABILITY_TIMEOUT");quit(2))
	var nav:=mounted()
	check(nav.find_path(Vector3.ZERO,Vector3.ONE).reason=="pending" and nav.capability_status().state=="pending" and nav.version==0,"unpublished navigation returns explicit pending without granting a version")
	nav.set_geometry_error("bad_geometry")
	check(nav.find_path(Vector3.ZERO,Vector3.ONE).reason=="geometry_error" and nav.capability_status().state=="failed","geometry failure remains a capability-local terminal query result")
	nav.free();nav=mounted();nav.cancel_background("transfer_cancelled");nav._baked();nav._publish();nav._step_publication()
	check(nav.capability_status().state=="cancelled" and not nav.ready_for_queries and nav.version==0 and not nav.region.is_valid(),"cancelled queued bake/publication cannot allocate or grant navigation readiness")
	nav.free();nav=mounted();nav.publication_guard=func()->bool:return false
	nav.build([],Vector3.ZERO);nav._baked();nav._publish();nav._step_publication()
	check(nav.capability_status().reason=="obsolete" and nav.version==0 and not nav.map.is_valid(),"obsolete map/transaction guard prevents old results from publishing")
	nav.free();nav=mounted();nav._baked()
	check(nav.capability_status().state=="failed" and not nav.ready_for_queries and nav.version==0,"empty initial navigation fails without fake readiness")
	nav.free();var timed:=mounted(Probe);timed._preparation_started_msec=Time.get_ticks_msec()-10;timed.preparation_timeout_msec=1;timed._process(0)
	check(timed.capability_status().reason=="navigation_timeout" and timed.work_calls==0,"initial capability timeout is finite and stops new work")
	timed.free()
	var previous_enabled:bool=FrameBudget.enabled;FrameBudget.enabled=true
	FrameBudget._shared=null
	var budgeted:=mounted(Probe);budgeted._process(0)
	check(budgeted.work_calls==1,"navigation source work obtains and charges its frame lane")
	FrameBudget.shared().record(Engine.get_process_frames(),"navigation",500)
	budgeted._process(0)
	check(budgeted.work_calls==1 and budgeted.capability_status().state=="pending","exhausted frame budget defers work without hiding pending capability")
	budgeted.cancel_background();budgeted._process(0)
	check(budgeted.capability_status().state=="cancelled","cancellation remains observable when preparation lane is exhausted")
	budgeted.free()
	# Submit an already-computed mesh, then observe genuine region+map server
	# iteration changes on later physics ticks. Never force-update the server.
	nav=mounted();nav.build([],Vector3.ZERO)
	nav.mesh.set_vertices(PackedVector3Array([Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)]))
	nav.mesh.add_polygon(PackedInt32Array([0,1,2,3]));nav._baked()
	check(not nav.ready_for_queries and nav.version==0,"bake completion alone does not imply synchronized navigation queries")
	for i in 120:
		await physics_frame;nav._step_publication()
		if nav.ready_for_queries:break
	check(nav.ready_for_queries and nav.version==1 and NavigationServer3D.map_get_iteration_id(nav.map)>0 and NavigationServer3D.region_get_iteration_id(nav.region)>0,"independent physics polling publishes only after actual map and region synchronization")
	var version:int=nav.version;nav.cancel_background("replaced");nav._publish();nav._step_publication()
	check(not nav.ready_for_queries and nav.version==version and nav.find_path(Vector3.ZERO,Vector3.ONE).reason=="navigation_cancelled","late old publication cannot increment synchronized revision after cancellation")
	nav.free();FrameBudget.enabled=previous_enabled;FrameBudget._shared=null
	var player:=Player.new();var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player);player.set_physics_process(false)
	var route:=RouteStub.new();root.add_child(route);player.navigation=route
	var result:Dictionary=player.set_click_target(Vector3(2,0,0),"ground")
	check(not result.ok and result.reason=="pending" and player._pending_click==Vector3(2,0,0) and player.click_target==null,"click queues an explicit pending intent without inventing a straight route")
	route.state="ready";route.ready_for_queries=true;route.version=1;player._refresh_navigation_request()
	check(player.path_status.ok and player.click_target==Vector3(2,0,0) and route.calls==2,"same navigation instance retries click only after its published revision changes")
	route.version=2;player._refresh_navigation_request()
	check(route.calls==3 and player._route_version==2,"an existing automatic route revalidates against a newer navigation revision")
	var other:=RouteStub.new();root.add_child(other);other.state="ready";other.ready_for_queries=true;other.version=2;player.navigation=other;player._refresh_navigation_request()
	check(player.click_target==null and player.path_status.reason=="navigation_replaced" and other.calls==0,"navigation replacement cancels old automatic movement instead of replaying it in a new map")
	player.navigation=route;route.state="pending";route.ready_for_queries=false;player.set_click_target(Vector3.ONE,"ground");route.state="failed";player._refresh_navigation_request()
	check(player._pending_click==null and player.path_status.reason=="navigation_failed","failed delayed navigation terminates pending click instead of retrying forever")
	player.set_click_target(Vector3.ONE,"ground");player.click_target=null
	check(player._pending_click==null,"ordinary movement cancellation also clears delayed click state")
	player.free();route.free();other.free()
	var world:=WorldStub.new();root.add_child(world);var pending:=mounted();world._navigation=pending
	var combat:=Combat.new();combat.world=world
	check(not combat.navigation_status().ok and combat.charge("missing",{},true).contains("准备中") and combat.revive_error("missing").contains("准备中"),"charge and revive reject explicitly before mutating gameplay while navigation prepares")
	var rejected:Dictionary=combat._navigation_rejected()
	check(not rejected.ok and rejected.reason=="navigation_pending" and world.actions.size()==1,"capability rejection emits a clear message without invoking combat consumption")
	pending.cancel_background("failed fixture")
	check(combat.navigation_message().contains("暂不可用") and not combat.valid_ground(10),"failed navigation disables only dependent ground actions with explicit status")
	# Never mounted, so no combat hooks or map state need releasing.
	combat.world=null;combat.free();pending.free();world.free()
	var retiring_host:=Node.new();root.add_child(retiring_host)
	var retired:=Navigation.new();retiring_host.add_child(retired);retired.set_process(false);retired.set_physics_process(false)
	retired._face_worker=Thread.new();retired._face_worker.start(func():OS.delay_msec(80);return PackedVector3Array())
	var began:=Time.get_ticks_usec();var accepted:bool=retired.retire_background("test_transfer")
	check(accepted and retired.get_parent()==root and Time.get_ticks_usec()-began<50000 and retired._face_worker.is_alive(),"retirement returns while a real worker is alive and moves its owner out of the old world")
	retiring_host.free();await process_frame
	check(is_instance_valid(retired) and retired.capability_status().state=="cancelled" and not retired._disposed,"old world destruction cannot release the retiring worker owner early")
	var deadline:=Time.get_ticks_msec()+3000
	while is_instance_valid(retired) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(retired),"retirement polls and frees only after the real worker has completed")
	print("NAVIGATION_CAPABILITY passed=",passed," failures=",failures);quit(0 if failures==0 else 1)
