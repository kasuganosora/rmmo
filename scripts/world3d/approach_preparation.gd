extends RefCounted
## Low-priority complete-building preparation ahead of movement. This grants no
## rendering, collision, navigation or entry authority on its own.
static var enabled:=true
const DEMAND="building_approach"
var profile:Dictionary={"updates":0,"active":false}
func update(queue:Node,feet:Vector3,velocity:Vector3)->void:
	if queue==null:return
	var direction:=Vector3(velocity.x,0,velocity.z);var speed:=direction.length()
	if not enabled or queue._reference_index.is_empty() or speed<.25 or not feet.is_finite():release(queue);return
	var ahead:Vector3=feet+direction.normalized()*clampf(speed*6.,160.,256.)
	var cell:Vector2i=preload("res://scripts/world3d/world_stream.gd").chunk_key(ahead)
	var centre:=Vector3((cell.x+.5)*32.,0,(cell.y+.5)*32.)
	# Player/collision demands retain priority 0/-2. Existing distant visual
	# work is priority 10; only complete indexed building groups are promoted.
	queue.set_demand(DEMAND,AABB(centre-Vector3(48,100000,48),Vector3(96,200000,96)),2,"building")
	profile.active=true;profile.updates+=1;profile.cell=[cell.x,cell.y]
func release(queue:Node)->void:
	if is_instance_valid(queue):queue.release_demand(DEMAND)
	profile.active=false
