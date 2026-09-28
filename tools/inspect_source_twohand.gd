extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var doc:=GLTFDocument.new();var state:=GLTFState.new()
 var first:bool="--ual1" in OS.get_cmdline_user_args()
 var source_path:String="characters/source_models/universal_animation_library/UAL1_Standard.glb" if first else "characters/source_models/universal_animation_library_2/UAL2_Standard.glb"
 assert(doc.append_from_file(preload("res://scripts/asset/art_paths.gd").path(source_path),state)==OK)
 var source=doc.generate_scene(state);root.add_child(source)
 var sk:Skeleton3D=source.find_children("*","Skeleton3D",true,false)[0]
 var player:AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0];player.active=false
 print("CLIPS ",player.get_animation_list())
 for name:String in (["Sword_Idle","Sword_Attack"] if first else ["Sword_Heavy_Combo","Sword_Regular_A","TreeChopping_Loop","Walk_Carry_Loop"]):
  var clip:Animation=player.get_animation(name)
  var distances:Array=[]
  for fraction:float in [0.0,.2,.4,.6,.8,1.0]:
   sk.reset_bone_poses()
   for track in clip.get_track_count():
    var path:NodePath=clip.track_get_path(track)
    if path.get_subname_count()!=1:continue
    var bone:int=sk.find_bone(path.get_subname(0))
    if bone<0:continue
    if clip.track_get_type(track)==Animation.TYPE_ROTATION_3D:sk.set_bone_pose_rotation(bone,clip.rotation_track_interpolate(track,clip.length*fraction))
    elif clip.track_get_type(track)==Animation.TYPE_POSITION_3D:sk.set_bone_pose_position(bone,clip.position_track_interpolate(track,clip.length*fraction))
   distances.append((sk.global_transform*sk.get_bone_global_pose(sk.find_bone("hand_l"))).origin.distance_to((sk.global_transform*sk.get_bone_global_pose(sk.find_bone("hand_r"))).origin))
  print(name," hand separation ",distances)
 source.free();quit()


