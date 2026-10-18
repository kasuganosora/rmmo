extends RefCounted
## Actor origins remain 0.9 m above feet for network/save compatibility. Shape
## centres move instead, so a taller capsule never lifts the feet off the floor.
const ORIGIN_HEIGHT:=.9
const HEAD_MARGIN:=.08
const NAV_HEIGHT:=2.1
const RADIUS:=.3

static func standing_height(model:Node3D)->float:
	if model.get("axis_rig")!=null:
		var low:=INF;var high:=-INF
		for point:Vector3 in model.axis_rig.body.rest_points:
			low=minf(low,point.y);high=maxf(high,point.y)
		return clampf(high-low+HEAD_MARGIN,1.8,NAV_HEIGHT)
	return 1.9

static func apply(body:CharacterBody3D,model:Node3D)->float:
	if body.has_meta("server_body_profile"):
		var profile:Dictionary=body.get_meta("server_body_profile")
		return apply_server(body,float(profile.radius),float(profile.height))
	var height:=standing_height(model)
	var collider:=body.get_node("CollisionShape3D") as CollisionShape3D
	var capsule:=CapsuleShape3D.new();capsule.radius=RADIUS;capsule.height=height
	collider.shape=capsule;collider.position.y=height/2-ORIGIN_HEIGHT
	body.set_meta("standing_height",height)
	return height

static func apply_server(body:CharacterBody3D,radius:float,height:float)->float:
	if not is_finite(radius) or not is_finite(height) or radius<.1 or radius>2 or height<.5 or height>5 or height<radius*2:return -1.0
	var collider:=body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null:return -1.0
	var current:=collider.shape as CapsuleShape3D
	if current!=null and is_equal_approx(current.radius,radius) and is_equal_approx(current.height,height):
		collider.position.y=height*.5-ORIGIN_HEIGHT
		body.set_meta("standing_height",height)
		body.set_meta("server_body_profile",{"radius":radius,"height":height})
		return height
	var capsule:=CapsuleShape3D.new();capsule.radius=radius;capsule.height=height
	collider.shape=capsule;collider.position.y=height*.5-ORIGIN_HEIGHT
	body.set_meta("standing_height",height)
	body.set_meta("server_body_profile",{"radius":radius,"height":height})
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
	# Setting/restoring a Basis decomposes scale on every turn. Float roundoff
	# accumulated until the unit-scale guard stopped accepting the live player.
	# Preserve Node3D's rotation/scale components instead. A rotated/scaled parent
	# needs a different coordinate conversion and stays on the original path.
	var parent:=body.get_parent_node_3d()
	if parent!=null and parent.global_basis!=Basis.IDENTITY:return null
	var original:=body.rotation
	if original==Vector3.ZERO or original.x!=0 or original.z!=0 or body.scale!=Vector3.ONE:return null
	body.rotation=Vector3.ZERO
	return original

static func end_capsule_motion(body:CharacterBody3D,original:Variant)->void:
	if original is Vector3:body.rotation=original
