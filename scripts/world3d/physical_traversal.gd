extends RefCounted
## Physical manual traversal is independent of navigation publication. The
## caller owns map/epoch/coverage validation; this module additionally requires
## a later physics tick than the most recent affected collision publication.
# Physical standing is not constrained by the navigation bake's 40 degree
# slope. Match CharacterBody3D's default floor angle; callers pass overrides.
const FLOOR_NORMAL_Y:=0.7071067811865476

static func readiness(receipt:Variant,physics_frame:int)->Dictionary:
	if not receipt is Dictionary or not receipt.get("ok",false):
		return {"ok":false,"reason":str(receipt.get("reason","geometry_pending")) if receipt is Dictionary else "invalid_readiness"}
	var published:Variant=receipt.get("physics_published_frame")
	if not published is int or published<0:return {"ok":false,"reason":"physics_receipt_missing"}
	if physics_frame<=published:return {"ok":false,"reason":"physics_pending"}
	return {"ok":true,"reason":""}

static func motion_bounds(body:CharacterBody3D,wish:Vector3,dt:float,jump:bool)->AABB:
	var collider:=body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D or not wish.is_finite() or not is_finite(dt) or dt<=0:return AABB()
	var capsule:CapsuleShape3D=collider.shape
	var size:=Vector3(capsule.radius*2,capsule.height,capsule.radius*2)
	var bounds:=collider.global_transform*AABB(-size*.5,size)
	var vertical:float=(4.8 if jump and body.is_on_floor() else body.velocity.y)-9.8*dt
	var movement:=Vector3(wish.x,vertical,wish.z)*dt
	# Step-up and the leading support ray reach beyond this tick's centre.
	return bounds.merge(AABB(bounds.position+movement,bounds.size)).grow(.4)

static func support(space:PhysicsDirectSpaceState3D,point:Vector3,direction:Vector3,feet_y:float,mask:int,exclude:Array[RID],min_normal_y:float=FLOOR_NORMAL_Y)->Dictionary:
	if space==null or not point.is_finite() or not direction.is_finite():return {}
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*4096,mask,exclude)
	query.collide_with_areas=false
	var hit:=space.intersect_ray(query)
	if not _map_support(hit):return {}
	if hit.normal.y>=min_normal_y:return hit
	# Preserve the existing small bevel/kerb exception, but require a real flat
	# nearby tread. A continuous steep slope and actor heads are not support.
	if absf(hit.position.y-feet_y)>.4:return {}
	for offset in [-.06,.06]:
		var at:Vector3=hit.position+direction*offset
		var adjacent:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.08,at-Vector3.UP*.08,mask,exclude)
		adjacent.collide_with_areas=false
		var tread:=space.intersect_ray(adjacent)
		if _map_support(tread) and tread.normal.y>=min_normal_y:return tread
	return {}

static func _map_support(hit:Dictionary)->bool:
	# Streamed map geometry is static. Character/rigid bodies can obstruct the
	# capsule, but cannot create walkable ground in an otherwise unloaded void.
	return not hit.is_empty() and hit.get("collider") is StaticBody3D

static func landing(space:PhysicsDirectSpaceState3D,feet:Vector3,capsule:CapsuleShape3D,pose:Transform3D,mask:int,exclude:Array[RID],receipt:Dictionary)->Dictionary:
	var ready:=readiness(receipt,Engine.get_physics_frames())
	if not ready.ok:return ready
	if space==null or capsule==null or not feet.is_finite() or not pose.is_finite() or mask==0:return {"ok":false,"reason":"invalid_landing"}
	# No projection to another floor or to a distant navigation polygon.
	var ray:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.1,feet-Vector3.UP*.4,mask,exclude)
	ray.collide_with_areas=false
	var floor_hit:=space.intersect_ray(ray)
	if not _map_support(floor_hit):return {"ok":false,"reason":"unsupported"}
	if floor_hit.normal.y<FLOOR_NORMAL_Y:return {"ok":false,"reason":"slope"}
	var probe:=CapsuleShape3D.new()
	probe.radius=maxf(.01,capsule.radius-.01);probe.height=maxf(probe.radius*2,capsule.height-.02)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=probe;query.transform=pose;query.transform.origin.y+=.01
	query.exclude=exclude;query.collision_mask=mask;query.collide_with_areas=false
	if not space.intersect_shape(query,1).is_empty():return {"ok":false,"reason":"occupied"}
	return {"ok":true,"reason":"","support":floor_hit.position}
