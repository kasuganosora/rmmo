extends RefCounted
## Follow a low tread with the real capsule sweep. A rounded foot can contact
## a sharp tread edge at a wall-like normal, which native floor snap rejects.
## Never replace collision geometry or turn a steep slope into walkable floor.
const MAX_DROP:=.4 # Same envelope as step-up and PhysicalTraversal.motion_bounds.
var _contact:=KinematicCollision3D.new()
var _frame:=-1
var _position:=Vector3.ZERO
var _body:WeakRef
# Last sparse contact-query result for traversal diagnostics; no per-frame log.
var last_probe_reason:=""

func reject(reason:String)->bool:
	last_probe_reason=reason;return false

func clear()->void:
	_frame=-1;_body=null

func supported(body:CharacterBody3D)->bool:
	if _body==null or _body.get_ref()!=body or Engine.get_physics_frames()!=_frame+1:return false
	if body.global_position.distance_to(_position)>.002:return false
	# Recheck current collision, including a removed/moved supporting collider.
	return _probe(body,.008)

func follow(body:CharacterBody3D,was_supported:bool,jumped:bool)->bool:
	clear()
	if not was_supported or jumped or body.velocity.y>0 or body.is_on_floor() or body.floor_snap_length<=0:return false
	if not _probe(body,MAX_DROP):return false
	# Test first, then move through exactly the same sweep. No destination warp,
	# capsule substitution, extra horizontal move or second move_and_slide.
	var contact:=body.move_and_collide(Vector3.DOWN*MAX_DROP,false,body.safe_margin,false,8)
	if contact==null:return false
	body.velocity.y=0
	body.apply_floor_snap()
	_frame=Engine.get_physics_frames();_position=body.global_position;_body=weakref(body)
	return true

func _probe(body:CharacterBody3D,distance:float)->bool:
	var collider:=body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D or body.up_direction!=Vector3.UP:return reject("capsule")
	# Yaw decomposition after a map transfer can leave micrometre-scale drift.
	# Reject actual scaling, not a nominal unit capsule's float32 roundoff.
	if body.motion_mode!=CharacterBody3D.MOTION_MODE_GROUNDED or not body.scale.is_equal_approx(Vector3.ONE):return reject("upright_body")
	if not collider.global_basis.y.is_equal_approx(Vector3.UP) or not collider.global_basis.get_scale().is_equal_approx(Vector3.ONE):return reject("upright_collider")
	var capsule:CapsuleShape3D=collider.shape
	var feet:=collider.global_position-Vector3.UP*capsule.height*.5
	var space:=body.get_world_3d().direct_space_state
	var floor_query:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.015,feet-Vector3.UP*MAX_DROP,body.collision_mask,[body.get_rid()])
	var floor_hit:=space.intersect_ray(floor_query)
	if floor_hit.is_empty() or not floor_hit.collider is StaticBody3D or floor_hit.normal.y<cos(body.floor_max_angle):return reject("support_ray")
	if not body.test_move(body.global_transform,Vector3.DOWN*distance,_contact,body.safe_margin,false,8):return reject("sweep_missing")
	if _contact.get_collision_count()==0:return reject("contacts_missing")
	var travel:=_contact.get_travel()
	if not travel.is_finite() or travel.y>.002 or travel.y< -distance-.002 or Vector2(travel.x,travel.z).length()>.002:return reject("travel")
	var foot_after:=feet+travel
	for i in _contact.get_collision_count():
		var object:=_contact.get_collider(i);var point:=_contact.get_position(i);var normal:=_contact.get_normal(i)
		if not object is StaticBody3D or not point.is_finite() or not normal.is_finite() or normal.y<=.01:return reject("static_upward_contact")
		# Only the spherical foot may supply support, never a wall at body height.
		if point.y<foot_after.y-.01 or point.y>foot_after.y+capsule.radius+.01:return reject("foot_height")
		var radial:=Vector2(point.x-foot_after.x,point.z-foot_after.z).length()
		if radial>capsule.radius+.01:return reject("foot_radius")
		if normal.y>=cos(body.floor_max_angle):continue
		# A steep capsule contact is acceptable only at a real flat tread edge
		# of that same collider. Continuous steep faces do not pass this ray.
		var horizontal:=Vector3(normal.x,0,normal.z)
		if horizontal.length_squared()<.000001:return reject("edge_direction")
		var inside:=point-horizontal.normalized()*.015
		var edge_query:=PhysicsRayQueryParameters3D.create(inside+Vector3.UP*.025,inside-Vector3.UP*.025,body.collision_mask,[body.get_rid()])
		var edge:=space.intersect_ray(edge_query)
		if edge.is_empty() or edge.collider!=object or edge.normal.y<.99:return reject("flat_edge")
	last_probe_reason="supported";return true
