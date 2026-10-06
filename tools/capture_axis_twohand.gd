extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func point(body:Node3D,name:String)->Vector3:return body.get_solved_bone_pose(body.skeleton.find_bone(name)).origin
func palm(body:Node3D,side:String)->Transform3D:
 var along:Vector3=(point(body,side+"Mid1")-point(body,side+"Hand")).normalized()
 var across:Vector3=(point(body,side+"Index1")-point(body,side+"Pinky1")).normalized()
 var normal:Vector3=across.cross(along).normalized();across=along.cross(normal).normalized()
 var center:=Vector3.ZERO
 for finger:String in ["Index","Mid","Ring","Pinky"]:
  center+=(point(body,side+finger+"1")+point(body,side+finger+"2"))*.125
 return Transform3D(Basis(-along,across,normal),center)
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Two hand capture timeout");quit(2))
 var view=View.new();root.add_child(view)
 var gear={"WeaponMain":1,"WeaponMainItem":"great_club","WeaponStyle":"heavy","SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},gear);view.model.set_process(false)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 var body=view.model.axis_rig.body;var sk:Skeleton3D=body.skeleton;var weapon=view.model.axis_rig.weapon
 var refs:Dictionary={}
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 var reflection:=Basis(Vector3(-1,0,0),Vector3.UP,Vector3.BACK)
 for left:String in weapon.grip_rotations:
  var right:String="r"+left.substr(1)
  var li:int=sk.find_bone(left);var ri:int=sk.find_bone(right)
  var conversion:Basis=sk.get_bone_global_rest(ri).basis.inverse()*reflection*sk.get_bone_global_rest(li).basis
  var delta:Basis=sk.get_bone_rest(li).basis.inverse()*Basis(weapon.grip_rotations[left])
  var mirrored:Basis=sk.get_bone_rest(ri).basis*conversion*delta*conversion.inverse()
  sk.set_bone_pose_rotation(ri,mirrored.get_rotation_quaternion())
 assert(body.sync_final_pose(refs))
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 var axis:=Vector3(.4,.85,.3).normalized();var normal:Vector3=Vector3.RIGHT.cross(axis).normalized()
 var basis:=Basis(axis.cross(normal),axis,normal)
 var chest:Vector3=point(body,"chest")
 var reach:float=point(body,"lForeArm").distance_to(point(body,"lHand"))
 var origin:Vector3=chest+Vector3(-reach*.35,-reach*.55,reach*1.1)
 var main:=Transform3D(basis,origin)
 var off:=Transform3D(basis*Basis(Vector3.UP,PI),origin+axis*.13)
 var frames:Array[Transform3D]=[];var elbows:Array[Vector3]=[]
 for i in 2:
  var side:String="l" if i==0 else "r"
  var hand:Transform3D=body.get_solved_bone_pose(sk.find_bone(side+"Hand"))
  var hand_to_palm:Transform3D=hand.affine_inverse()*palm(body,side)
  frames.append((main if i==0 else off)*hand_to_palm.affine_inverse())
  elbows.append(point(body,side+"ForeArm")+Vector3(-.2 if i==0 else .2,0,-.1))
 var bridge=preload("res://scripts/char/character_axis_ik.gd").new();bridge.configure(body)
 assert(bridge.submit(frames,elbows,refs))
 await RenderingServer.frame_post_draw
 assert(bridge.completed_revision==bridge.revision)
 var main_error:float=palm(body,"l").origin.distance_to(main.origin)
 var off_error:float=palm(body,"r").origin.distance_to(off.origin)
 assert(main_error<.001 and off_error<.001)
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_twohand_03");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=2.4
 for side in 2:
  view.camera.position=Vector3(0,1,4) if side==0 else Vector3(4,1,0);view.camera.look_at(Vector3(0,1,0))
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  view.viewport.get_texture().get_image().save_png(folder+"/idle_%d.png"%side)
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"main_palm_error_m":main_error,"off_palm_error_m":off_error,"scope":"Candidate stationary two-hand pose; inspect visual, no runtime activation or attack acceptance"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS two-palm position candidate ",main_error," ",off_error);quit()
