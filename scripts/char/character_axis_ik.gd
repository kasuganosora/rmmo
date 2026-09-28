extends RefCounted
## Native paired-limb solver bridge. Caller submits the final animation/blend pose.
## Results are consumed in the modifier phase, before the frame is rendered.
signal pose_solved(revision:int)
var body:Node3D
var modifier:TwoBoneIK3D
var targets:Array[Node3D]=[]
var poles:Array[Node3D]=[]
var references:Dictionary={}
var revision:=0
var completed_revision:=0
var error:=""
var end_bones:Array[String]=[]
func configure(target:Node3D,chains:Array=[["lShldr","lForeArm","lHand"],["rShldr","rForeArm","rHand"]])->void:
 assert(chains.size()==2)
 body=target
 modifier=TwoBoneIK3D.new();modifier.name="WeaponArmIK";modifier.active=false
 body.skeleton.add_child(modifier);modifier.setting_count=2
 for i in 2:
  var chain:Array=chains[i];assert(chain.size()==3)
  end_bones.append(str(chain[2]))
  var point:=Node3D.new();body.add_child(point);targets.append(point)
  var pole:=Node3D.new();body.add_child(pole);poles.append(pole)
  modifier.set_root_bone_name(i,chain[0]);modifier.set_middle_bone_name(i,chain[1]);modifier.set_end_bone_name(i,chain[2])
  modifier.set_use_virtual_end(i,false)
  modifier.set_target_node(i,modifier.get_path_to(point));modifier.set_pole_node(i,modifier.get_path_to(pole))
 modifier.modification_processed.connect(_finish)
func submit(wrists:Array[Transform3D],elbows:Array[Vector3],angle_references:Dictionary)->bool:
 if wrists.size()!=2 or elbows.size()!=2:return false
 for i in 2:
  if not wrists[i].is_finite() or not elbows[i].is_finite():return false
 references=angle_references.duplicate();revision+=1;error=""
 for i in 2:
  targets[i].transform=wrists[i];poles[i].position=elbows[i]
 modifier.active=true
 body.skeleton.advance(0)
 return true
func cancel()->void:
 modifier.active=false;revision+=1;references.clear()
func _finish()->void:
 if not modifier.active:return
 # TwoBoneIK supplies positions; retain the requested end-bone orientation
 # for palm grips and planted feet alike.
 var sk:Skeleton3D=body.skeleton
 for i in 2:
  var index:int=sk.find_bone(end_bones[i])
  var parent:Basis=sk.get_bone_global_pose(sk.get_bone_parent(index)).basis.orthonormalized()
  var desired:Basis=(sk.global_transform.affine_inverse()*targets[i].global_transform).basis.orthonormalized()
  sk.set_bone_pose_rotation(index,(parent.inverse()*desired).get_rotation_quaternion())
 if not body.sync_final_pose(references):error=body.pose_sync_error;return
 completed_revision=revision
 pose_solved.emit(revision)
