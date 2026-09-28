extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(150).timeout.connect(func():push_error("IK lifecycle timeout");quit(2))
 var model=Model.new();model.body_type="female";model.appearance={"body_model":"female_base_v2"};root.add_child(model);model.set_process(false)
 var body=model.axis_rig.body;var sk:Skeleton3D=body.skeleton
 var bridge=preload("res://scripts/char/character_axis_ik.gd").new();bridge.configure(body)
 var notified:Array=[];bridge.pose_solved.connect(func(revision:int):notified.append(revision))
 var maximum:=0.0;var orientation_error:=0.0
 for frame in 6:
  model.play("idle","front",true);model._from_rotations.clear();model.pose_at(.2)
  var frames:Array[Transform3D]=[];var elbows:Array[Vector3]=[];var refs:Dictionary={}
  for node:Dictionary in body.nodes:refs[node.name]=node.angles
  for side:String in ["l","r"]:
   var wrist:Transform3D=body.get_solved_bone_pose(sk.find_bone(side+"Hand"))
   var sign_x:float=-1.0 if side=="l" else 1.0
   wrist.origin+=Vector3(-sign_x*.10,.12+frame*.005,.14)
   wrist.basis=Basis(Vector3.UP,sign_x*.1)*wrist.basis
   frames.append(wrist)
   elbows.append(body.get_solved_bone_pose(sk.find_bone(side+"ForeArm")).origin+Vector3(sign_x*.2,0,-.1))
  assert(bridge.submit(frames,elbows,refs))
  # Observe the frame that actually renders, not an arbitrary two-frame delay.
  await RenderingServer.frame_post_draw
  assert(bridge.completed_revision==bridge.revision and bridge.error.is_empty(),"IK final pose not ready for render")
  for i in 2:
   var pose:Transform3D=body.get_solved_bone_pose(sk.find_bone("lHand" if i==0 else "rHand"))
   maximum=maxf(maximum,pose.origin.distance_to(frames[i].origin))
   orientation_error=maxf(orientation_error,pose.basis.get_rotation_quaternion().angle_to(frames[i].basis.get_rotation_quaternion()))
  assert(maximum<.001 and orientation_error<.001,"Final body uses stale IK wrist")
  await process_frame
 bridge.cancel();var completed:int=bridge.completed_revision
 model.play("idle","front",true);model._from_rotations.clear();model.pose_at(.2)
 var unarmed:PackedVector3Array=body.posed_points.duplicate()
 await RenderingServer.frame_post_draw
 assert(bridge.completed_revision==completed and body.posed_points==unarmed,"Canceled solver changes body")
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_twohand_02");DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder+"/lifecycle.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"frames":6,"wrist_error_m":maximum,"orientation_error_rad":orientation_error,"cancel_unchanged":true,"scope":"Both wrists finalized before frame_post_draw; not final weapon grip or cloth ordering"},"  "));file.close()
 model.free()
 for frame in 3:await process_frame
 print("PASS native IK final-frame bridge ",maximum," orientation ",orientation_error);quit()
