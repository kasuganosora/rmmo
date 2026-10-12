extends SceneTree
## Actual headless physics contacts; flat floors, ledges, walls and clearances.
const Step=preload("res://scripts/world3d/step_support.gd")
const Authority=preload("res://scripts/world3d/world_authority.gd")
const DT:=1./60.
const START:=Vector3(.70,.9,-.70)
const WISH:=Vector3(.4,0,4)
const MIN_Y:=.766044443118978
class Body extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface()->void:pass
var host:Node3D
var body:Body
var ground:StaticBody3D
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func box(size:Vector3,at:Vector3,rotation:Vector3=Vector3.ZERO)->StaticBody3D:
	var node:=StaticBody3D.new();var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;node.add_child(collider)
	host.add_child(node);node.position=at;node.rotation=rotation;return node
func reset()->void:body.position=START;body.velocity=Vector3.ZERO
func contact(wish:Vector3=WISH)->KinematicCollision3D:
	var result:=KinematicCollision3D.new();body.test_move(body.global_transform,wish*DT,result);return result
func rise(hit:KinematicCollision3D,wish:Vector3=WISH)->float:
	return Step.rise(body,body.position-Vector3.UP*.9,wish,DT,.32,1,MIN_Y,.005,hit)
func run()->void:
	create_timer(25).timeout.connect(func():quit(2))
	host=Node3D.new();root.add_child(host);ground=box(Vector3(20,.2,20),Vector3(0,-.1,0))
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);reset()
	var step:=box(Vector3(1,.15,1),Vector3(0,.075,0));await physics_frame;await physics_frame
	var hit:=contact();check(hit.get_collision_count()>0,"capsule's leading side really contacts the low-step corner")
	check(is_zero_approx(rise(null)),"all centre-line samples miss this side contact")
	var amount:=rise(hit)
	check(amount>.15 and amount<.16,"real contact finds only the actual 15cm flat tread")
	check(is_zero_approx(rise(hit,-WISH)),"moving away cannot reuse the opposite-facing step contact")
	body.position+=Vector3(5,0,0);check(is_zero_approx(rise(hit)),"a contact outside the current footprint cannot supply a remote tread");reset()
	var authority:=Authority.new();var before:=body.position
	authority._step_up(body,before-Vector3.UP*.9,WISH,DT,hit)
	check(body.position.y-before.y>.15 and Vector2(body.position.x,body.position.z)==Vector2(before.x,before.z),"candidate uses the existing vertical and forward clearance gates")
	reset();var ceiling:=box(Vector3(3,.1,3),Vector3(0,1.87,0));await physics_frame;await physics_frame
	before=body.position;authority._step_up(body,before-Vector3.UP*.9,WISH,DT,contact())
	check(body.position==before,"low overhead clearance still forbids the step-up")
	ceiling.free();await physics_frame;reset();hit=contact()
	var front:=box(Vector3(3,.8,.02),Vector3(0,1.35,-.35));await physics_frame;await physics_frame
	before=body.position;authority._step_up(body,before-Vector3.UP*.9,WISH,DT,hit)
	check(body.position==before,"a blocked raised horizontal move cannot be replaced by a vertical teleport")
	front.free();ground.position.y=-10;await physics_frame;await physics_frame;reset();hit=contact()
	before=body.position;authority._step_up(body,before-Vector3.UP*.9,WISH,DT,hit)
	check(body.position==before,"without current ground support a corner cannot raise an airborne actor")
	ground.position.y=-.1;step.free();var wall:=box(Vector3(1,.8,1),Vector3(0,.4,0));await physics_frame;await physics_frame;reset();hit=contact()
	check(hit.get_collision_count()>0 and is_zero_approx(rise(hit)),"a wall higher than the 40cm climb limit has no false walkable tread")
	wall.free();var slope:=box(Vector3(2,.08,2),Vector3(0,.4,0),Vector3(0,0,deg_to_rad(55.)))
	body.position=Vector3(-.46,.9,0);await physics_frame;await physics_frame;hit=contact(Vector3(4,0,0))
	check(hit.get_collision_count()>0 and is_zero_approx(rise(hit,Vector3(4,0,0))),"continuous 55-degree slope remains unwalkable even with a real contact")
	slope.free();reset();await physics_frame;await physics_frame;hit=contact()
	check(hit.get_collision_count()==0 and is_zero_approx(rise(hit)),"flat unobstructed movement has no contact fallback candidate")
	host.free();print("STEP_CONTACT_SUPPORT passed=",passed," failures=",failures);quit(0 if failures==0 else 1)
