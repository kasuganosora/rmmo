extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var heavy:bool="--heavy-carrier" in OS.get_cmdline_user_args()
 create_timer(240).timeout.connect(func():push_error("Continuous grip timeout");quit(2))
 var view=View.new();root.add_child(view)
 var gear={"WeaponMain":1,"WeaponMainItem":"great_club","WeaponStyle":"heavy","SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},gear);view.model.set_process(false)
 var rig=view.model.axis_rig;var trace:Array=[];var last:Transform3D;var has_last:=false
 var maximum:=0.0;var maximum_step:=0.0
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_twohand_continuous_03" if heavy else "character_3d/axis_twohand_continuous_04");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=3.2;view.camera.position=Vector3(0,1,4);view.camera.look_at(Vector3(0,1,0))
 for action:String in ["idle","walk","attack","idle"]:
  view.model.play(action,"front",true,"attack_club_body" if heavy and action=="attack" else "")
  var count:int=ceili(view.model.action_duration()*30) if action=="attack" else 15
  for frame in count:
   view.model._process(1.0/30)
   await RenderingServer.frame_post_draw
   var grip_error:=0.0
   for i in 2:grip_error=maxf(grip_error,rig.twohand.palm("l" if i==0 else "r").origin.distance_to(rig.twohand.palm_targets[i].origin))
   maximum=maxf(maximum,grip_error)
   assert(grip_error<.005 and rig.twohand.bridge.error.is_empty())
   var current:Transform3D=rig.weapon.transform
   var step:float=current.origin.distance_to(last.origin) if has_last else 0.0
   maximum_step=maxf(maximum_step,step);last=current;has_last=true
   trace.append({"action":action,"frame":frame,"elapsed":view.model.elapsed,"palm_error_m":grip_error,"grip_step_m":step,"requested_origin":[rig.twohand.requested_origin.x,rig.twohand.requested_origin.y,rig.twohand.requested_origin.z],"reach_correction":[rig.twohand.reach_correction.x,rig.twohand.reach_correction.y,rig.twohand.reach_correction.z]})
   if action=="attack" and frame%7==0:assert(view.viewport.get_texture().get_image().save_png(folder+"/attack_%02d.png"%frame)==OK)
   await process_frame
 gear.WeaponMain=0;gear.erase("WeaponMainItem");view.model.set_equipment(gear)
 assert(not rig.twohand.bridge.modifier.active)
 for frame in 4:
  view.model._process(1.0/30);await RenderingServer.frame_post_draw;assert(not rig.twohand.bridge.modifier.active);await process_frame
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"frames":trace.size(),"grip_passed":true,"continuous_visual_accepted":false,"max_grip_error_m":maximum,"max_frame_grip_step_m":maximum_step,"trace":trace,"scope":"Continuous idle/walk/attack/idle with model blend; grip assertions do not accept torso motion/garment contact"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("GRIP PASS; motion visual review still pending. Frames ",trace.size()," grip error ",maximum," max step ",maximum_step);quit()
