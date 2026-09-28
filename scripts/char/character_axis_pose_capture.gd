extends RefCounted
## Record the final modifier snapshot, including axis-angle branches.
## Skeleton3D may already have restored its input pose when this is called.
static func append(body:Node3D,animation:Animation,time:float,offset:Vector3)->void:
 var first:bool=animation.get_track_count()==0
 var track:=0
 for node:Dictionary in body.nodes:
  var i:int=node.skeleton_index;var parent:int=body.skeleton.get_bone_parent(i)
  var basis:Basis=body.get_solved_bone_pose(i).basis
  if parent>=0:basis=body.get_solved_bone_pose(parent).basis.inverse()*basis
  if first:
   var r:=animation.add_track(Animation.TYPE_ROTATION_3D);animation.track_set_path(r,NodePath("Skeleton3D:"+node.name))
   var a:=animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(a,NodePath("AxisAngles:"+node.name))
  animation.rotation_track_insert_key(track,time,basis.orthonormalized().get_rotation_quaternion())
  animation.track_insert_key(track+1,time,node.angles)
  track+=2
 if first:
  var root_track:=animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(root_track,NodePath("VisualRoot:position"))
 animation.position_track_insert_key(track,time,offset)
