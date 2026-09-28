extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Identity capture timed out");quit(2))
 var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var equipment={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,equipment);view.model.set_process(false)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.3)
 view.viewport.size=Vector2i(640,800);view.viewport.msaa_3d=Viewport.MSAA_4X
 view.camera.size=2.25
 var profiles={"baseline":{},"minimum":{"hip_size":-.75,"waist_width":-1.0,"nose_width":-.75},"maximum":{"bust_size":1.0,"hip_size":1.0,"waist_width":1.0,"nose_width":1.0},"moderate":{"bust_size":.3,"hip_size":.2,"waist_width":-.2,"nose_width":.2}}
 profiles["tall"]={"height":-1.0};profiles["short"]={"height":1.0}
 var folder:String=Art.review_path("character_3d/body_identity_03");DirAccess.make_dir_recursive_absolute(folder)
 for label:String in profiles:
  recipe.body_shapes=profiles[label];view.model.configure("female",recipe,equipment)
  assert(view.model.axis_rig.body.shape_values==profiles[label])
  for side in 2:
   view.camera.position=Vector3(0 if side==0 else 4,1.0,4 if side==0 else 0)
   view.camera.look_at(Vector3(0,1.0,0))
   for frame in 8:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_side%s.png"%[label,side])==OK)
 view.free()
 for frame in 3:await process_frame
 print("WROTE native shape baseline/minimum/maximum/moderate with existing underlayers, front/side; inspect before UI range acceptance")
 quit()
