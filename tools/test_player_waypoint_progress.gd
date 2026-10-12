extends SceneTree
## Exercise the real route consumer against explicit authority outcomes. No
## meshes, asset loading or artificial mismatch with an engine physics delta.
const Net=preload("res://scripts/net/net.gd")
class Player extends "res://scripts/world3d/world_player.gd":
	var stick:=Vector2.ZERO
	func _stick()->Vector2:return stick
	func _camera_yaw()->float:return 0.
	func _sense_surface()->void:pass
class Model extends Node3D:
	var action:="idle"
	var locomotion_rate:=0.
	func play(value:String,_direction:String,_restart:bool=false)->void:action=value
class Nav extends Node:
	var ready_for_queries:=true
	var version:=1
	var cancelled:=0
	var queries:=0
	var answer:=PackedVector3Array()
	func near_surface(_point:Vector3,_horizontal:float,_vertical:float)->bool:return true
	func cancel_foreground_request(_goal:Variant=null)->bool:cancelled+=1;return true
	func find_foreground_path(_start:Vector3,_goal:Vector3,_tolerance:float,_retry:bool)->Dictionary:
		queries+=1;return {"ok":true,"reason":"","path":answer.duplicate(),"version":version}
class Server extends Node:
	var player:Node3D
	var delta:=1./60.
	var multiplier:=1.
	var fraction:=1.
	var reject:=false
	var intent:=Vector3.ZERO
	var authority:RefCounted
	func player_move_speed_mul()->float:return multiplier
	func try_move_world(_sequence:int,direction:Vector3,speed:float,_jump:bool=false)->Dictionary:
		intent=direction*speed*multiplier
		if authority!=null:return authority.move_intent(_sequence,direction,speed,_jump)
		if reject:return {"ok":false,"reason":"movement_locked"}
		player.global_position+=intent*delta*fraction
		return {"ok":true}
var passed:=0
var failures:=0
var player:Player
var nav:Nav
var server:Server
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func setup_route(first:Vector3,rest:Array[Vector3])->void:
	player.position=Vector3(0,.9,0);player.velocity=Vector3.ZERO;player.stick=Vector2.ZERO
	player._route_navigation_id=0;player._pending_click=null;player._route_goal=rest[-1] if not rest.is_empty() else first
	player.click_target=first;player._route=PackedVector3Array(rest)
	server.delta=1./60.;server.multiplier=1.;server.fraction=1.;server.reject=false;server.intent=Vector3.ZERO
	nav.cancelled=0;nav.queries=0
func tick(delta:float)->void:
	# This authority fixture integrates the exact supplied delta. A slow render
	# frame in the actual game still uses fixed physics ticks, not this delta.
	server.delta=delta;player._step(delta)
func physical_town_coordinates()->void:
	var ground:=StaticBody3D.new();var ground_collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.2,20)
	ground_collision.shape=box;ground.add_child(ground_collision);root.add_child(ground);ground.position=Vector3(320,-.1,160)
	var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;player.add_child(collider)
	setup_route(Vector3(320.04,0,160),[Vector3(320.04,0,160.12)]);player.position=Vector3(320,.9,160)
	# The original click can be projected by navigation; arrival concerns the
	# actual returned final waypoint rather than this off-mesh click location.
	player._route_goal=Vector3(320.2,0,160.3)
	server.authority=preload("res://scripts/world3d/world_authority.gd").new();server.authority.mount(player,nav,"test/waypoints")
	await physics_frame;await physics_frame
	for i in 30:
		await physics_frame;tick(player.get_physics_process_delta_time())
		if player.click_target==null:break
	var end:=Vector2(player.position.x,player.position.z)
	check(player.click_target==null and end.distance_to(Vector2(320.04,160.12))<=.002,"real capsule movement at 320m reaches the actual navigation goal without float32 oscillation")
	check(end.distance_to(Vector2(320.2,160.3))>.1,"route completion does not move to a different original click after projection")
	server.authority.release();server.authority=null;ground.free()
func run()->void:
	player=Player.new();var model:=Model.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player)
	player.set_physics_process(false);player.input_locked=false
	nav=Nav.new();root.add_child(nav);player.navigation=nav
	server=Server.new();server.player=player;root.add_child(server)
	var previous:Node=Net._server_override;Net._server_override=server
	var corner:=Vector3(.04,0,0);var goal:=Vector3(.04,0,1)
	setup_route(corner,[goal]);server.reject=true;tick(1./60.)
	check(player.position==Vector3(0,.9,0) and player.click_target==corner and player._route==PackedVector3Array([goal]),"rejected ordinary tick preserves its unvisited corner and remaining route")
	check(server.intent.z==0 and nav.cancelled==0,"a request toward one corner cannot turn or cancel before authority accepts motion")
	setup_route(Vector3(.8,0,0),[]);server.reject=true;tick(.25)
	check(player.click_target==Vector3(.8,0,0) and nav.cancelled==0,"rejected final approach never claims arrival or releases the foreground ticket")
	setup_route(corner,[goal]);server.fraction=0.;tick(1./60.)
	check(player.click_target==corner and player._route.size()==1,"authority ok with zero physical displacement does not consume a corner")
	setup_route(corner,[goal]);server.fraction=.5;tick(1./60.)
	check(player.position.distance_to(Vector3(.02,.9,0))<.000001 and player.click_target==corner and player._route.size()==1,"partially blocked displacement retains the current corner")
	setup_route(corner,[goal]);tick(1./60.)
	check(player.position.distance_to(Vector3(.04,.9,0))<.000001 and player.click_target==corner and player._route.size()==1,"one tick stops at the first physical waypoint without cutting its turn")
	tick(1./60.)
	check(player.click_target==goal and player._route.is_empty() and absf(player.position.x-.04)<.000001 and absf(player.position.z-4./60.)<.000001,"only the next tick consumes the actually reached corner and continues at normal speed")
	setup_route(Vector3(0,0,1),[Vector3(1,0,1),Vector3(1,0,0)]);tick(.75)
	check(player.position.distance_to(Vector3(0,.9,1))<.000001 and player._route.size()==2 and player.click_target==Vector3(0,0,1),"large delta cannot replace a U route by a straight segment across its obstacle")
	setup_route(Vector3.ZERO,[Vector3.ZERO,corner,goal]);tick(1./60.)
	check(player.position.distance_to(Vector3(.04,.9,0))<.000001 and player.click_target==corner and player._route.size()==1,"coincident waypoints are consumed without an idle frame or consuming the next unvisited point")
	setup_route(Vector3(.0015,0,0),[Vector3(1,0,0)]);tick(1./60.)
	check(player.click_target==Vector3(1,0,0) and absf(player.position.x-4./60.)<.000001,"two-millimetre arrival tolerance absorbs numeric recovery without a micro-waypoint stall")
	setup_route(Vector3(.003,0,0),[Vector3(1,0,0)]);server.reject=true;tick(1./60.)
	check(player.click_target==Vector3(.003,0,0),"arrival tolerance never discards a still-unvisited point three millimetres away")
	setup_route(Vector3(1,0,0),[]);server.multiplier=1.45;tick(1./60.)
	check(absf(player.position.x-4.*1.45/60.)<.000001,"server speed multiplier is applied exactly once")
	setup_route(corner,[goal]);server.multiplier=0.;tick(1./60.)
	check(player.position==Vector3(0,.9,0) and player.click_target==corner and player._route.size()==1,"zero speed does not consume an unvisited waypoint")
	setup_route(corner,[]);tick(1./60.)
	check(player.click_target==corner and nav.cancelled==0,"final waypoint remains owned until its movement actually finishes")
	tick(1./60.)
	check(player.click_target==null and player._route.is_empty() and nav.cancelled==1 and server.intent==Vector3.ZERO,"actual final arrival terminates once without oscillation")
	setup_route(corner,[goal]);player.stick=Vector2.RIGHT;tick(1./60.)
	check(player.click_target==null and player._route.is_empty() and nav.cancelled>0 and player.position.x>0,"manual movement still cancels the route and moves normally")
	setup_route(corner,[goal]);player._route_navigation_id=nav.get_instance_id();player._route_version=0
	nav.answer=PackedVector3Array([Vector3.ZERO,Vector3(0,0,.4),goal]);tick(1./60.)
	check(nav.queries==1 and player.click_target==Vector3(0,0,.4) and player.position.x==0 and player.position.z>0,"a synchronized navigation revision replaces the route before motion")
	await physical_town_coordinates()
	Net._server_override=previous;player.free();nav.free();server.free()
	print("PLAYER_WAYPOINT_PROGRESS passed=",passed," failures=",failures);quit(0 if failures==0 else 1)
