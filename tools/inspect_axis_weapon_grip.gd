extends SceneTree
func _initialize()->void:
 var lib=load(preload("res://scripts/asset/art_paths.gd").path("characters/animations/female_base_v2_combat.res"))
 var clip=lib.get_animation("attack_sword_a")
 for i in clip.get_track_count():
  if String(clip.track_get_path(i)) in ["AxisAngles:lMid1","AxisAngles:lMid2","AxisAngles:lMid3","AxisAngles:lThumb1","AxisAngles:lThumb2","AxisAngles:lThumb3"]:print(clip.track_get_path(i)," ",clip.value_track_interpolate(i,.0)," / ",clip.value_track_interpolate(i,.2))
 quit()
