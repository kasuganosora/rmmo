extends RefCounted
## Sample the leading half of the capsule as well as the next landing point.
## A single ray beyond the capsule can skip a narrow kerb completely.
static func rise(body:CharacterBody3D,feet:Vector3,wish:Vector3,delta:float,reach:float,mask:int,min_normal_y:float,skin:float,contact:KinematicCollision3D=null)->float:
	var result:=0.0
	for distance:float in [reach+wish.length()*delta,reach,reach*.75,reach*.5]:
		var ahead:=feet+wish.normalized()*distance
		var query:=PhysicsRayQueryParameters3D.create(ahead+Vector3.UP*.4,ahead-Vector3.UP*.04,mask)
		query.exclude=[body.get_rid()]
		var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<min_normal_y:continue
		var height:float=hit.position.y-feet.y+skin
		if height>.01 and height<=.4:result=maxf(result,height)
	if result>0:return result
	return _contact_rise(body,feet,wish,contact,mask,min_normal_y,skin,reach+wish.length()*delta+skin)

static func _contact_rise(body:CharacterBody3D,feet:Vector3,wish:Vector3,contact:KinematicCollision3D,mask:int,min_normal_y:float,skin:float,contact_reach:float)->float:
	# A capsule's leading side can hit a step corner while all four centre-line
	# rays pass outside it. The current forward test supplies the real contact;
	# its sloping capsule normal is NOT evidence of a walkable step or ramp.
	if contact==null or wish.length_squared()<.000001:return 0.
	for index in contact.get_collision_count():
		var obstacle:=contact.get_collider(index)
		if not obstacle is StaticBody3D:continue
		var point:=contact.get_position(index);var normal:=contact.get_normal(index)
		if not point.is_finite() or not normal.is_finite() or point.y-feet.y<=.01 or point.y-feet.y>.4:continue
		if Vector2(point.x-feet.x,point.z-feet.z).length()>contact_reach:continue
		var outward:=Vector3(normal.x,0,normal.z)
		if outward.length_squared()<.000001:continue
		outward=outward.normalized()
		if outward.dot(wish.normalized())>=-.01:continue
		# Probe just inside the hit surface, at the existing maximum step height.
		# Only an actual flat tread on this same static obstacle can supply rise.
		var at:=point-outward*.025
		var query:=PhysicsRayQueryParameters3D.create(Vector3(at.x,feet.y+.4,at.z),Vector3(at.x,feet.y-.04,at.z),mask,[body.get_rid()])
		var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider!=obstacle or hit.normal.y<min_normal_y:continue
		var height:float=hit.position.y-feet.y+skin
		if height>.01 and height<=.4:return height
	return 0.
