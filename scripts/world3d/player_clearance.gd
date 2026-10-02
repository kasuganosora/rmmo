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
