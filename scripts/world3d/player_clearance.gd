extends RefCounted
## Actor origins remain 0.9 m above feet for network/save compatibility. Shape
## centres move instead, so a taller capsule never lifts the feet off the floor.
const ORIGIN_HEIGHT:=.9
const HEAD_MARGIN:=.08
const NAV_HEIGHT:=2.1

static func standing_height(model:Node3D)->float:
	if model.get("axis_rig")!=null:
		var low:=INF;var high:=-INF
		for point:Vector3 in model.axis_rig.body.rest_points:
			low=minf(low,point.y);high=maxf(high,point.y)
		return clampf(high-low+HEAD_MARGIN,1.8,NAV_HEIGHT)
	return 1.9

static func apply(body:CharacterBody3D,model:Node3D)->float:
	var height:=standing_height(model)
	var collider:=body.get_node("CollisionShape3D") as CollisionShape3D
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=height
	collider.shape=capsule;collider.position.y=height/2-ORIGIN_HEIGHT
	body.set_meta("standing_height",height)
	return height

static func begin_capsule_motion(body:CharacterBody3D)->Variant:
	# A centred, upright capsule is invariant under actor yaw. Query it with
	# exact world axes, avoiding rotated support-map roundoff at concave edges.
	# The caller restores the actor's basis before publishing/rendering its pose.
	var collider:=body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D:return null
	if collider.position.x!=0 or collider.position.z!=0 or collider.basis!=Basis.IDENTITY:return null
	var owners:=body.get_shape_owners()
	if owners.size()!=1 or body.shape_owner_get_shape_count(owners[0])!=1:return null
	if body.shape_owner_get_owner(owners[0])!=collider:return null
	var original:=body.global_basis
	if original==Basis.IDENTITY or not original.y.is_equal_approx(Vector3.UP) or not original.get_scale().is_equal_approx(Vector3.ONE):return null
	body.global_basis=Basis.IDENTITY
	return original

static func end_capsule_motion(body:CharacterBody3D,original:Variant)->void:
	if original is Basis:body.global_basis=original
