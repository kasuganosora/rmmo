extends RefCounted
## Two-grip club controller; native IK owns arm solving, source grip owns fingers.
var body:Node3D
var weapon:Node3D
var bridge=preload("res://scripts/char/character_axis_ik.gd").new()
var palm_targets:Array[Transform3D]=[]
var input_rotations:Array[Quaternion]=[]
var input_references:Dictionary={}
var reach_correction:=Vector3.ZERO
var requested_origin:=Vector3.ZERO
func configure(target:Node3D,held:Node3D)->void:
 body=target;weapon=held;bridge.configure(body)
func point(name:String)->Vector3:return body.get_solved_bone_pose(body.skeleton.find_bone(name)).origin
func palm(side:String)->Transform3D:
 var along:Vector3=(point(side+"Mid1")-point(side+"Hand")).normalized()
 var across:Vector3=(point(side+"Index1")-point(side+"Pinky1")).normalized()
 var normal:Vector3=across.cross(along).normalized();across=along.cross(normal).normalized()
 var center:=Vector3.ZERO
 for finger:String in ["Index","Mid","Ring","Pinky"]:center+=(point(side+finger+"1")+point(side+finger+"2"))*.125
 return Transform3D(Basis(-along,across,normal),center)
func cancel(restore_pose:bool=false)->void:
 if not bridge.modifier.active:return
 bridge.cancel()
 if restore_pose and not input_rotations.is_empty():
  for index in input_rotations.size():body.skeleton.set_bone_pose_rotation(index,input_rotations[index])
  body.sync_final_pose(input_references)
func prepare(action:String,time:float,duration:float)->bool:
 if weapon.item_id!="great_club" or not weapon.enabled or action not in ["idle","walk","dash","attack"]:
  cancel();return false
 var sk:Skeleton3D=body.skeleton
 var refs:Dictionary={}
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 input_references=refs.duplicate();input_rotations.clear()
 for index in sk.get_bone_count():input_rotations.append(sk.get_bone_pose_rotation(index))
 var reflection:=Basis(Vector3(-1,0,0),Vector3.UP,Vector3.BACK)
 for left:String in weapon.grip_rotations:
  var right:String="r"+left.substr(1);var li:int=sk.find_bone(left);var ri:int=sk.find_bone(right)
  var conversion:Basis=sk.get_bone_global_rest(ri).basis.inverse()*reflection*sk.get_bone_global_rest(li).basis
  var delta:Basis=sk.get_bone_rest(li).basis.inverse()*Basis(weapon.grip_rotations[left])
  sk.set_bone_pose_rotation(ri,(sk.get_bone_rest(ri).basis*conversion*delta*conversion.inverse()).get_rotation_quaternion())
 if not body.sync_final_pose(refs):return false
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 var chest_index:int=sk.find_bone("chest")
 var chest:Transform3D=body.get_solved_bone_pose(chest_index)
 var rotation:Basis=chest.basis*body.rests.chest.basis.inverse()
 var reach:float=point("lForeArm").distance_to(point("lHand"))
 var axis:=Vector3(.4,.85,.3).normalized()
 var offset:=Vector3(-.35,-.55,1.1)
 if action=="attack":
  # A club-specific windup/strike/recovery in torso space, not a renamed
  # one-handed sword track. All targets still go through anatomical arm IK.
  var phase:float=clampf(time/maxf(duration,.001),0,1)
  var times:Array[float]=[0.0,.22,.5,.72,1.0]
  var axes:Array[Vector3]=[axis,Vector3(.2,.98,-.05),Vector3(.15,-.35,1),Vector3(.2,-.65,.7),axis]
  var offsets:Array[Vector3]=[offset,Vector3(-.25,.55,.9),Vector3(-.25,-.4,1.25),Vector3(-.3,-.7,1.05),offset]
  for i in 4:
   if phase<=times[i+1]:
    var weight:float=smoothstep(times[i],times[i+1],phase)
    axis=axes[i].normalized().slerp(axes[i+1].normalized(),weight);offset=offsets[i].lerp(offsets[i+1],weight);break
 var normal:Vector3=Vector3.RIGHT.cross(axis).normalized()
 var basis:Basis=rotation*Basis(axis.cross(normal),axis,normal)
 var origin:Vector3=chest.origin+rotation*(offset*reach)
 requested_origin=origin;reach_correction=Vector3.ZERO
 palm_targets=[Transform3D(basis,origin),Transform3D(basis*Basis(Vector3.UP,PI),origin+basis.y*.13)]
 var frames:Array[Transform3D]=[];var elbows:Array[Vector3]=[]
 for i in 2:
  var side:String="l" if i==0 else "r"
  var hand:Transform3D=body.get_solved_bone_pose(sk.find_bone(side+"Hand"))
  frames.append(palm_targets[i]*(hand.affine_inverse()*palm(side)).affine_inverse())
  elbows.append(point(side+"Shldr")+rotation*Vector3(-reach if i==0 else reach,-reach*.6,-reach*.35))
 # Translate the whole held object into both arms' reachable region. Never
 # stretch bones or separate the two fixed grip sockets to satisfy a target.
 for iteration in 8:
  for i in 2:
   var side:String="l" if i==0 else "r"
   var shoulder:Vector3=point(side+"Shldr")
   var length:float=(shoulder.distance_to(point(side+"ForeArm"))+point(side+"ForeArm").distance_to(point(side+"Hand")))*.97
   var displacement:Vector3=frames[i].origin-shoulder
   if displacement.length()>length:
    var correction:Vector3=displacement.normalized()*(length-displacement.length())
    reach_correction+=correction
    for j in 2:
     frames[j].origin+=correction;palm_targets[j].origin+=correction
 return bridge.submit(frames,elbows,refs)
