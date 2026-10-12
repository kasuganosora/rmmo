extends SceneTree
## Headless physics-only fixtures: no map files, imported assets or GPU work.
const Traversal=preload("res://scripts/world3d/physical_traversal.gd")
const Authority=preload("res://scripts/world3d/world_authority.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
class Body extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface()->void:pass
class NavStub extends Node:
	var ready_for_queries:=false
	var calls:=0
	func near_surface(_point:Vector3,_horizontal:float,_vertical:float)->bool:calls+=1;return false
var passed:=0
var failures:=0
var host:Node3D
var body:Body
var sequence:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func box(size_:Vector3,at:Vector3,rotation_:Vector3=Vector3.ZERO)->StaticBody3D:
	var node:=StaticBody3D.new();var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size_;collider.shape=shape;node.add_child(collider)
	host.add_child(node);node.position=at;node.rotation=rotation_;return node
func move(authority:RefCounted,wish:Vector3=Vector3.RIGHT,jump:bool=false)->Dictionary:
	await physics_frame;sequence+=1
	return authority.move_intent(sequence,wish,2.5,jump)
func settle(authority:RefCounted)->void:
	for i in 5:await move(authority,Vector3.ZERO)
func run()->void:
	create_timer(40).timeout.connect(func():print("PHYSICAL_TRAVERSAL_TIMEOUT");quit(2))
	check(Traversal.readiness({},10).reason=="geometry_pending","missing geometry receipt fails closed")
	check(Traversal.readiness({"ok":true},10).reason=="physics_receipt_missing","geometry flag alone cannot prove physics synchronization")
	check(Traversal.readiness({"ok":true,"physics_published_frame":10},10).reason=="physics_pending","publication tick is not a subsequent physics synchronization")
	check(Traversal.readiness({"ok":true,"physics_published_frame":9},10).ok,"only a later physics tick accepts the receipt")
	check(Traversal.readiness({"ok":false,"reason":"obsolete_epoch","physics_published_frame":0},10).reason=="obsolete_epoch","map/epoch failure is preserved without querying physics")
	host=Node3D.new();root.add_child(host)
	box(Vector3(8,.2,8),Vector3(0,-.1,0))
	box(Vector3(.2,3,8),Vector3(2,1.5,0))
	box(Vector3(2,.2,2),Vector3(10,0,0),Vector3(0,0,deg_to_rad(55)))
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.position=Vector3(0,.9,0);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,"test/map")
	var published:=Engine.get_physics_frames();var receipt:={"ok":true,"physics_published_frame":published};var seen:={"bounds":AABB()}
	check(not authority.move_intent(0,Vector3.RIGHT,2.5).ok,"legacy consumers stay locked before navigation is ready")
	authority.traversal_guard=func(bounds:AABB)->Dictionary:seen.bounds=bounds;return receipt
	check(authority.move_intent(0,Vector3.RIGHT,2.5).reason=="physics_pending","manual authority cannot move on the collision publication tick")
	await physics_frame;await physics_frame
	await settle(authority)
	var initial:=body.position;var result:=await move(authority)
	check(result.ok and body.position.x>initial.x and nav.calls==0,"pending navigation permits authority movement through actual physical support")
	check(seen.bounds.has_point(initial) and seen.bounds.end.x>body.position.x+.3,"residency guard receives the real swept capsule and support margin")
	check(not authority.move_intent(sequence+1,Vector3.RIGHT,2.5).ok,"duplicate physics-tick intents remain rejected")
	var immutable:=body.position;receipt.ok=false;receipt.reason="unloaded_boundary"
	result=await move(authority)
	check(not result.ok and result.reason=="unloaded_boundary" and body.position==immutable,"unloaded swept boundary rejects before position or gravity changes")
	receipt.ok=true;receipt.erase("reason");nav.ready_for_queries=true
	result=await move(authority)
	check(result.ok and body.position.x>immutable.x and nav.calls==0,"ready navigation retains identical independent physical traversal rules")
	receipt.ok=false;receipt.reason="stale_geometry";immutable=body.position;result=await move(authority)
	check(not result.ok and body.position==immutable,"ready navigation never bypasses failed residency evidence")
	receipt.ok=true;receipt.erase("reason");nav.ready_for_queries=false
	await settle(authority);var y:=body.position.y;result=await move(authority,Vector3.ZERO,true)
	check(result.ok and body.position.y>y and body.velocity.y>0,"jump remains an authoritative physical move before navigation readiness")
	body.position=Vector3(1.3,.9,0);body.velocity=Vector3.ZERO;await settle(authority)
	for i in 35:await move(authority)
	check(body.position.x<1.7,"physical capsule cannot cross a wall while navigation is pending")
	body.position=Vector3(-3.4,.9,0);body.velocity=Vector3.ZERO;await settle(authority)
	for i in 30:await move(authority,Vector3.LEFT)
	check(body.position.x> -4 and body.position.y>.8,"missing support preserves edge protection without a nav polygon")
	var space:=host.get_world_3d().direct_space_state
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,.9,0))
	check(Traversal.landing(space,Vector3.ZERO,capsule,pose,1,[body.get_rid()],receipt).ok,"teleport landing accepts real synchronized support and free capsule space")
	check(Traversal.landing(space,Vector3(30,0,0),capsule,Transform3D(Basis.IDENTITY,Vector3(30,.9,0)),1,[body.get_rid()],receipt).reason=="unsupported","teleport cannot project an unsupported point onto remote ground")
	check(Traversal.landing(space,Vector3(2,0,0),capsule,Transform3D(Basis.IDENTITY,Vector3(2,.9,0)),1,[body.get_rid()],receipt).reason=="occupied","teleport rejects a capsule blocked by an actual wall")
	check(Traversal.support(space,Vector3(10,0,0),Vector3.RIGHT,0,1,[body.get_rid()]).is_empty(),"continuous steep slope remains invalid support")
	var obstacle:=CharacterBody3D.new();var actor_shape:=CollisionShape3D.new();actor_shape.shape=capsule;obstacle.add_child(actor_shape);host.add_child(obstacle);obstacle.position=Vector3(0,.9,0)
	await physics_frame;await physics_frame
	check(Traversal.landing(space,Vector3.ZERO,capsule,pose,1,[body.get_rid()],receipt).reason=="occupied","live actor occupancy is preserved by the same landing query")
	check(Traversal.support(space,Vector3(0,1.8,0),Vector3.RIGHT,1.8,1,[body.get_rid()]).is_empty(),"actor heads cannot replace map support")
	receipt.physics_published_frame=Engine.get_physics_frames()
	check(Traversal.landing(space,Vector3.ZERO,capsule,pose,1,[body.get_rid()],receipt).reason=="physics_pending","teleport cannot use a newly replaced collider before a later physics tick")
	authority.release();check(not authority.traversal_guard.is_valid() and authority.snapshot.is_empty(),"authority release removes old map guard and pose")
	host.free()
	print("PHYSICAL_TRAVERSAL passed=",passed," failures=",failures);quit(0 if failures==0 else 1)
