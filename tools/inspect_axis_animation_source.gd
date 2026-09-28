extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var d=GLTFDocument.new();var st=GLTFState.new()
 assert(d.append_from_file(Art.path("characters/source_models/universal_animation_library/UAL1_Standard.glb"),st)==OK)
 var n=d.generate_scene(st);root.add_child(n)
 var sk=n.find_children("*","Skeleton3D",true,false)[0]
 for key in ["pelvis","upperarm_l","upperarm_r","foot_l","Head"]:
  var i=sk.find_bone(key);print(key," ",sk.global_transform*sk.get_bone_global_rest(i))
 n.free();quit()
