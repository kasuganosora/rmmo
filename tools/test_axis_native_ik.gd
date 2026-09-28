extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(90).timeout.connect(func():push_error("Native IK timeout");quit(2))
 var model=Model.new();model.body_type="female";model.appearance={"body_model":"female_base_v2"};root.add_child(model);model.set_process(false)
 model.play("idle","front",true);model._from_rotations.clear();model.pose_at(.2)
 var body=model.axis_rig.body;var sk:Skeleton3D=body.skeleton
 sk.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
 var target:=Node3D.new();body.add_child(target)
 var pole:=Node3D.new();body.add_child(pole)
 var ik:=TwoBoneIK3D.new();sk.add_child(ik);ik.setting_count=1
 ik.set_root_bone_name(0,"lShldr");ik.set_middle_bone_name(0,"lForeArm");ik.set_end_bone_name(0,"lHand");ik.set_use_virtual_end(0,false)
 ik.set_target_node(0,ik.get_path_to(target));ik.set_pole_node(0,ik.get_path_to(pole))
 var solved:Dictionary={}
 ik.modification_processed.connect(func():
  for bone:String in ["lShldr","lForeArm","lHand"]:solved[bone]=sk.get_bone_pose_rotation(sk.find_bone(bone)))
 var maximum:=0.0
 for offset:Vector3 in [Vector3(.1,.1,.12),Vector3(.16,.18,.18),Vector3(.07,.15,.25)]:
  model.pose_at(.2)
  var hand:Vector3=body.get_solved_bone_pose(sk.find_bone("lHand")).origin
  target.position=hand+offset
  pole.position=body.get_solved_bone_pose(sk.find_bone("lForeArm")).origin+Vector3(-.2,0,-.1)
  var references:Dictionary={}
  for node:Dictionary in body.nodes:references[node.name]=node.angles
  sk.advance(0)
  for frame in 2:await process_frame
  assert(solved.size()==3,"Built-in modifier did not emit final pose")
  for bone:String in solved:sk.set_bone_pose_rotation(sk.find_bone(bone),solved[bone])
  assert(body.sync_final_pose(references),body.pose_sync_error)
  var error:float=body.get_solved_bone_pose(sk.find_bone("lHand")).origin.distance_to(target.position)
  maximum=maxf(maximum,error);assert(error<.001,"Native IK missed target: "+str(error))
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_twohand_01");DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder+"/native_ik_probe.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"max_error_m":maximum,"targets":3,"scope":"Built-in solver to axis body bridge only; not natural two-hand weapon grip"},"  "));file.close()
 model.free()
 for frame in 3:await process_frame
 print("PASS native TwoBoneIK3D axis bridge, max error ",maximum);quit()
