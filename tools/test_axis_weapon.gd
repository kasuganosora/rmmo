extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(150).timeout.connect(func():push_error("Axis weapon timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var equipment={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,equipment);view.model.set_process(false)
 var body=view.model.axis_rig.body;var weapon=view.model.axis_rig.weapon
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 var unarmed:PackedVector3Array=body.posed_points.duplicate();var id:int=body.get_instance_id()
 equipment.WeaponMain=1;equipment.WeaponMainItem="wooden_sword";equipment.WeaponStyle="sword";view.model.set_equipment(equipment)
 assert(weapon.enabled and weapon.visible and weapon.grip_rotations.size()==15)
 assert(weapon.item_id=="wooden_sword" and weapon.pieces[2].material_override.albedo_color==Color("ba8d59"))
 var folder:String=Art.review_path("character_3d/axis_weapon_03");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800)
 var variants:Array=[]
 for action:String in ["idle","attack","attack","attack"]:
  view.model.play(action,"front",true);view.model._from_rotations.clear();view.model.pose_at(.4 if action=="attack" else .2)
  assert(body.pose_sync_error.is_empty() and body.get_instance_id()==id)
  variants.append(view.model.animation_clip)
  if action=="attack":
   var clip:String=view.model.animation_clip
   var sequence:int=view.model.axis_rig.attack_sequence
   view.model.elapsed=.4
   view.model.play("attack","front")
   assert(view.model.animation_clip==clip and view.model.axis_rig.attack_sequence==sequence and view.model.elapsed==.4,"Repeated attack state restarts or advances the combo")
   view.model.play("attack","left")
   assert(view.model.animation_clip==clip and view.model.axis_rig.attack_sequence==sequence,"Turning advances the combo")
   view.model._from_rotations.clear();view.model.pose_at(.4)
  assert(weapon.position.distance_to(weapon.point("lHand")+body.root_offset)<.16,"Weapon floats away from gripping hand")
  assert(absf(weapon.basis.determinant()-1)<.0001)
  view.camera.size=3.3 if action=="attack" else 2.3;view.camera.position=Vector3(0,1,4);view.camera.look_at(Vector3(0,1,0))
  for frame in 5:await process_frame
  await RenderingServer.frame_post_draw
  assert(view.viewport.get_texture().get_image().save_png(folder+"/%s.png"%view.model.animation_clip)==OK)
  if action=="idle":
   var center:Vector3=weapon.global_position
   view.camera.size=.32;view.camera.position=center+Vector3(-1,.3,2);view.camera.look_at(center)
   for frame in 4:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/idle_grip.png")==OK)
 assert(variants==["idle","attack_sword_a","attack_sword_b","attack_sword_c"])
 var max_socket_distance:=0.0
 for height:float in [-1.0,1.0,0.0]:
  recipe.body_shapes={"height":height};view.model.configure("female",recipe,equipment)
  for action:String in ["idle","walk","attack"]:
   view.model.play(action,"front",true)
   for frame in 12:
    view.model._process(1.0/60)
    assert(body.get_instance_id()==id and body.pose_sync_error.is_empty())
    var distance:float=weapon.position.distance_to(weapon.point("lHand")+body.root_offset)
    max_socket_distance=maxf(max_socket_distance,distance)
    assert(distance<.16 and absf(weapon.basis.determinant()-1)<.0001)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 equipment.WeaponMain=0;view.model.set_equipment(equipment)
 var reset_error:=0.0
 for i in unarmed.size():reset_error=maxf(reset_error,unarmed[i].distance_to(body.posed_points[i]))
 assert(reset_error<.00001 and not weapon.visible,"Unequip leaves a forced fist")
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"variants":variants,"grip_bones":weapon.grip_rotations.size(),"unequip_body_error_m":reset_error,"max_socket_to_wrist_m":max_socket_distance,"repeat_and_turn_preserve_clip":true,"height_blend_samples":108,"scope":"Prototype sword visual, single hand; sampled height/motion blends, not full combat acceptance"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS source sword grip, adaptive socket, three clip selection, unchanged body instance, unequip restoration ",reset_error)
 quit()
