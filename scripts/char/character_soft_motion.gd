extends RefCounted
## Shared player/NPC secondary bones. Each character owns its own spring state.
var skeleton:Skeleton3D
var indices:Array[int]=[]
var parent_bases:Array[Basis]=[]
var rest_rotations:Array[Quaternion]=[]
var offsets:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var velocities:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var size:=.5

func install(model:Node3D)->void:
	skeleton=model.skeleton
	size=Customization.valid_bust_size(model.appearance.get("bust_size",.5))
	if model.body_type!="female":return
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*skeleton.global_transform
	for side in ["Left","Right"]:
		var index:=skeleton.find_bone("SecondaryBreast"+side)
		if index<0:
			indices.clear();return
		indices.append(index)
		var parent:=skeleton.get_bone_parent(index)
		parent_bases.append((relative*skeleton.get_bone_global_rest(parent)).basis.orthonormalized().inverse())
		rest_rotations.append(skeleton.get_bone_rest(index).basis.get_rotation_quaternion())

func update(action:String,time:float,delta:float,cycle:float)->void:
	if indices.size()!=2 or delta<=0:return
	var omega:float=TAU*lerpf(4.2,3.1,size)*(1.3 if action=="dash" else 1.0)
	for side in range(2):
		var target:=Vector3.ZERO
		if action in ["walk","dash"]:
			var phase:=time/cycle*TAU
			var lag:float=.09 if side==0 else -.09
			var amplitude:float=(.035 if action=="walk" else .052)*lerpf(.55,1.35,size)
			target=Vector3(sin(phase+lag-.5)*amplitude*.16,sin(phase*2+lag-.65)*amplitude,cos(phase*2+lag-.95)*amplitude*.34)
		var remaining:=minf(delta,.1)
		while remaining>0:
			var step:=minf(remaining,1.0/120.0);remaining-=step
			velocities[side]+=((target-offsets[side])*omega*omega-velocities[side]*(2*.40*omega))*step
			offsets[side]+=velocities[side]*step
			for axis in range(3):
				var limit:float=[.025,.085,.050][axis]
				if absf(offsets[side][axis])>limit:
					offsets[side][axis]=clampf(offsets[side][axis],-limit,limit);velocities[side][axis]=0
		var index:int=indices[side]
		skeleton.set_bone_pose_position(index,skeleton.get_bone_rest(index).origin+parent_bases[side]*offsets[side])
		# A small tip follows the translation; most movement comes from the weighted bones.
		var tilt:=Quaternion(parent_bases[side]*Vector3.RIGHT,-offsets[side].y*.8)
		skeleton.set_bone_pose_rotation(index,tilt*rest_rotations[side])
