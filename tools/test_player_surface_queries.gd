extends SceneTree
const Net=preload("res://scripts/net/net.gd")
class ProbePlayer:
	extends "res://scripts/world3d/world_player.gd"
	var senses:=0
	var stick:=Vector2.ZERO
	func _sense_surface()->void:
		senses+=1;super._sense_surface()
	func _stick()->Vector2:return stick
	func _camera_yaw()->float:return 0.
class Model extends Node3D:
	var action:="idle"
	var locomotion_rate:=0.
	func play(value:String,_direction:String,_restart:bool=false)->void:action=value
class Navigation extends Node:
	var ready_for_queries:=true
	func near_surface(_point:Vector3,_horizontal:float,_vertical:float)->bool:return true
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func run()->void:
	create_timer(45).timeout.connect(func():quit(2))
	var host:=Node3D.new();root.add_child(host)
	for i in 2:
		var floor_:=StaticBody3D.new();floor_.position=Vector3(i*4,-.1,0);floor_.set_meta("surface_id","floor_%d"%i)
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,.2,6);shape.shape=box;floor_.add_child(shape);host.add_child(floor_)
	var player:=ProbePlayer.new();player.name="Player";player.position=Vector3(0,.9,0);player.set_physics_process(false)
	var model:=Model.new();model.name="CharacterModel3D";player.add_child(model)
	var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;player.add_child(collider)
	host.add_child(player);player.set_physics_process(false);player.input_locked=false
	var nav:=Navigation.new();host.add_child(nav)
	var authority=Net.server().world3d_authority;authority.mount(player,nav,"test/surface")
	await physics_frame;await physics_frame
	player._step(1./60.)
	check(player.senses==1 and player.surface_id=="floor_0","accepted idle tick senses once")
	check(authority.snapshot.get("surface_id")=="floor_0","authority publishes final sensed surface")
	# A same-tick duplicate still refreshes surface despite authority rejection.
	player.surface_id="stale";player.senses=0;player._step(1./60.)
	check(player.senses==1 and player.surface_id=="floor_0","duplicate tick rejection preserves local sensing")
	for reason in ["not_ready","movement_locked","invalid_intent"]:
		await physics_frame
		nav.ready_for_queries=reason!="not_ready"
		authority.movement_allowed=func():return reason!="movement_locked"
		if reason=="invalid_intent":authority._sequence=player._sequence+10
		player.surface_id="stale";player.senses=0;var before:=player.global_position
		player._step(1./60.)
		check(player.senses==1 and player.surface_id=="floor_0" and player.global_position==before,"rejection senses once without movement: "+reason)
		authority._sequence=-1
	nav.ready_for_queries=true;authority.movement_allowed=Callable()
	player.position=Vector3(1.99,.9,0);player.stick=Vector2.RIGHT
	await physics_frame;await physics_frame
	player.senses=0;player._step(1./60.)
	check(player.global_position.x>2 and player.senses==1 and player.surface_id=="floor_1","accepted crossing senses new surface after movement")
	check(authority.snapshot.get("surface_id")=="floor_1","published surface matches accepted new pose")
	authority.release();host.free();print("PLAYER_SURFACE_QUERIES_FAILED=",failed);quit(1 if failed else 0)
