extends RefCounted
## Rest-space garment envelopes are shared; visibility and pose stay per actor.
static var profiles:Dictionary={}

static func _profile(mesh:MeshInstance3D,model:Node3D)->Dictionary:
	var key:String=str(mesh.mesh.get_instance_id())+str(mesh.transform)
	if profiles.has(key):return profiles[key]
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform
	var binds:Array[Transform3D]=[]
	var arm_bindings:Dictionary={}
	if mesh.skin!=null:
		for i in mesh.skin.get_bind_count():
			var bone:int=model.skeleton.find_bone(mesh.skin.get_bind_name(i))
			if bone<0:bone=mesh.skin.get_bind_bone(i)
			binds.append(relative*model.skeleton.get_bone_global_rest(bone)*mesh.skin.get_bind_pose(i))
			var name:String=model.skeleton.get_bone_name(bone)
			if "Arm" in name or "Hand" in name:arm_bindings[i]=true
	var triangles:Array[PackedVector3Array]=[]
	var low:=Vector2(INF,INF);var high:=-low
	for surface in mesh.mesh.get_surface_count():
		var arrays:Array=mesh.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
		var stride:int=bones.size()/vertices.size() if bones!=null and not vertices.is_empty() else 0
		var points:=PackedVector3Array();var arms:=PackedFloat32Array()
		for i in vertices.size():
			var point:Vector3=mesh.transform*vertices[i]
			var arm_weight:float=0
			if not binds.is_empty() and stride>0:
				point=Vector3.ZERO
				for j in stride:
					point+=(binds[bones[i*stride+j]]*vertices[i])*weights[i*stride+j]
					if arm_bindings.has(bones[i*stride+j]):arm_weight+=weights[i*stride+j]
			points.append(point);arms.append(arm_weight)
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		for i in range(0,indices.size(),3):
			if maxf(arms[indices[i]],maxf(arms[indices[i+1]],arms[indices[i+2]]))>.15:continue
			var triangle:=PackedVector3Array([points[indices[i]],points[indices[i+1]],points[indices[i+2]]])
			triangles.append(triangle)
			for point in triangle:
				low=low.min(Vector2(point.y,point.z));high=high.max(Vector2(point.y,point.z))
	if triangles.is_empty():return {}
	# Retain depth: a bow behind the body must not push a hand in front
	# sideways. Rasterize face bounds, not just vertices (sparse meshes too).
	var step:Vector2=(high-low)/Vector2(127,63)
	step=step.max(Vector2(.0001,.0001))
	var widths:=PackedFloat32Array();widths.resize(128*64)
	for triangle in triangles:
		var lo:=Vector2(INF,INF);var hi:=-lo;var width:=0.0
		for point in triangle:
			lo=lo.min(Vector2(point.y,point.z));hi=hi.max(Vector2(point.y,point.z))
			width=maxf(width,absf(point.x))
		var start:Vector2i=Vector2i((lo-low)/step);var end:Vector2i=Vector2i((hi-low)/step)
		for y in range(clampi(start.x,0,127),clampi(end.x,0,127)+1):
			for z in range(clampi(start.y,0,63),clampi(end.y,0,63)+1):
				widths[y*64+z]=maxf(widths[y*64+z],width)
	var result:Dictionary={"low":low,"high":high,"step":step,"widths":widths}
	profiles[key]=result
	return result

static func _width(profile:Dictionary,low:float,high:float,front:float,back:float)->float:
	if profile.is_empty():return 0.0
	if high<profile.low.x or low>profile.high.x or back<profile.low.y or front>profile.high.y:return 0.0
	var start:=Vector2i((Vector2(low,front)-profile.low)/profile.step)
	var end:=Vector2i((Vector2(high,back)-profile.low)/profile.step)
	var width:=0.0
	for y in range(clampi(start.x,0,127),clampi(end.x,0,127)+1):
		for z in range(clampi(start.y,0,63),clampi(end.y,0,63)+1):
			width=maxf(width,profile.widths[y*64+z])
	return width

static func clear_hands(model:Node3D)->void:
	for side in ["L","R"]:_clear_hand(model,side)

static func _clear_hand(model:Node3D,side:String)->void:
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	var upper:int=model.bones["arm"+side];var lower:int=model.bones["forearm"+side];var hand:int=model.bones["hand"+side]
	var shoulder:Vector3=(relative*sk.get_bone_global_pose(upper)).origin
	var elbow:Vector3=(relative*sk.get_bone_global_pose(lower)).origin
	var wrist_pose:Transform3D=relative*sk.get_bone_global_pose(hand)
	# Include the full posed hand, not only a weapon socket or wrist point.
	# In particular, the fingertips hang lower into the widening apron.
	var hand_name:String=sk.get_bone_name(hand)
	var points:Array[Vector3]=[wrist_pose.origin]
	var hand_length:float=0
	for bone in sk.get_bone_count():
		if bone!=hand and sk.get_bone_name(bone).begins_with(hand_name):
			points.append((relative*sk.get_bone_global_pose(bone)).origin)
			hand_length=maxf(hand_length,sk.get_bone_global_rest(hand).origin.distance_to(sk.get_bone_global_rest(bone).origin))
	var padding:float=maxf(hand_length*.14,.005)
	var low:float=points[0].y-padding;var high:float=points[0].y+padding
	var inner:float=absf(points[0].x)-padding
	var front:float=points[0].z-padding;var back:float=points[0].z+padding
	for point in points:
		low=minf(low,point.y-padding);high=maxf(high,point.y+padding)
		inner=minf(inner,absf(point.x)-padding)
		front=minf(front,point.z-padding);back=maxf(back,point.z+padding)
	var weapon=model.equipment.get("WeaponMain")
	if side=="L" and weapon!=null and int(weapon)>0:
		var socket:MeshInstance3D=model.gear.WeaponMain[0]
		var palm:Vector3=(wrist_pose*socket.transform).origin
		var grip_radius:float=socket.mesh.get_aabb().size.length()*.5
		low=minf(low,palm.y-grip_radius);high=maxf(high,palm.y+grip_radius)
		inner=minf(inner,absf(palm.x)-grip_radius)
		front=minf(front,palm.z-grip_radius);back=maxf(back,palm.z+grip_radius)
	var width:float=0
	for category in ["Clothing1","Clothing2","Belt"]:
		for mesh:MeshInstance3D in model.gear[category]:
			if not mesh.visible:continue
			width=maxf(width,_width(_profile(mesh,model),low,high,front,back))
	var deficit:float=width-inner
	if width<=0 or deficit<=0:return
	var target:Vector3=wrist_pose.origin+Vector3(signf(shoulder.x)*deficit,0,0)
	var armed:bool=side=="L" and weapon!=null and int(weapon)>0
	if model.action=="idle" and not armed:
		# A relaxed hand may rest slightly in front of a flared skirt.
		# Choose the smallest local correction, penalizing lateral spread.
		var best:float=deficit*deficit*4.0
		var forearm_length:float=elbow.distance_to(wrist_pose.origin)
		for i in range(1,13):
			var dz:float=forearm_length*.75*float(i)/12.0
			var local_width:=0.0
			for category in ["Clothing1","Clothing2","Belt"]:
				for mesh:MeshInstance3D in model.gear[category]:
					if mesh.visible:local_width=maxf(local_width,_width(_profile(mesh,model),low,high,front+dz,back+dz))
			var dx:float=maxf(0,local_width-inner)
			var cost:float=dx*dx*4.0+dz*dz
			if cost<best:
				best=cost;target=wrist_pose.origin+Vector3(signf(shoulder.x)*dx,0,dz)
	var a:float=shoulder.distance_to(elbow);var b:float=elbow.distance_to(wrist_pose.origin)
	var reach:float=(a+b)*.98
	var horizontal:=Vector2(target.x-shoulder.x,target.z-shoulder.z)
	if horizontal.length()>reach:horizontal=horizontal.normalized()*reach*.98
	target.x=shoulder.x+horizontal.x;target.z=shoulder.z+horizontal.y
	target.y=maxf(target.y,shoulder.y-sqrt(maxf(0,reach*reach-horizontal.length_squared())))
	var axis:Vector3=(target-shoulder).normalized();var distance:float=target.distance_to(shoulder)
	var along:float=(a*a-b*b+distance*distance)/(2*distance)
	var bend:Vector3=elbow-shoulder-axis*(elbow-shoulder).dot(axis)
	if bend.length()<a*.05:bend=Vector3.BACK-axis*Vector3.BACK.dot(axis)
	var joint:Vector3=shoulder+axis*along+bend.normalized()*sqrt(maxf(0,a*a-along*along))
	_rotate_towards(sk,relative,upper,lower,joint)
	_rotate_towards(sk,relative,lower,hand,target)
	# Idle empty wrists follow the forearm naturally; preserve the authored
	# orientation for weapons and moving clips.
	var parent:Basis=(relative*sk.get_bone_global_pose(lower)).basis.orthonormalized()
	if armed or model.action!="idle":
		sk.set_bone_pose_rotation(hand,(parent.inverse()*wrist_pose.basis.orthonormalized()).get_rotation_quaternion())

static func _rotate_towards(sk:Skeleton3D,relative:Transform3D,bone:int,child:int,target:Vector3)->void:
	var pose:Transform3D=relative*sk.get_bone_global_pose(bone)
	var end:Vector3=(relative*sk.get_bone_global_pose(child)).origin
	var rotation:=Quaternion((end-pose.origin).normalized(),(target-pose.origin).normalized())
	var parent:Basis=(relative*sk.get_bone_global_pose(sk.get_bone_parent(bone))).basis.orthonormalized()
	sk.set_bone_pose_rotation(bone,(parent.inverse()*Basis(rotation)*pose.basis.orthonormalized()).get_rotation_quaternion())
