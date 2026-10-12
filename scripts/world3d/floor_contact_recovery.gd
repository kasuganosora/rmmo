extends RefCounted
## Godot's capsule/concave sweep can report a separating floor contact at
## zero travel repeatedly. Resolve only a verified, unoccupied 2 mm upward
## separation. Never skip an obstacle, substitute a box, or whitelist an asset.
const SEPARATION:=.002
static func recover(body:CharacterBody3D)->bool:
	if not body.is_on_floor():return false
	var collider:=body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D:return false
	var contact:=KinematicCollision3D.new()
	if not body.test_move(body.global_transform,Vector3.UP*SEPARATION,contact,body.safe_margin,false,8):return false
	if contact.get_collision_count()==0 or contact.get_travel().length()>SEPARATION:return false
	var center:=collider.global_position
	for i in contact.get_collision_count():
		if contact.get_normal(i).dot(Vector3.UP)<cos(body.floor_max_angle):return false
		if contact.get_position(i).y>=center.y:return false
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=collider.shape;query.transform=collider.global_transform;query.transform.origin.y+=SEPARATION
	query.exclude=[body.get_rid()];query.collision_mask=body.collision_mask;query.collide_with_areas=false
	# Query the complete capsule at the destination: even a different collider
	# forming a low ceiling or a wall forbids this recovery.
	if not body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	body.global_position+=Vector3.UP*SEPARATION
	return true
