extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(150).timeout.connect(func():push_error("Equipment preview timeout");quit(2))
 var server=root.get_node("MockServer");server.inventory.clear();server.equipment.clear()
 var recipe={"body_model":"female_base_v2","body_shapes":{"height":-.4,"hip_size":.2},"part_ids":{"FrontHair1":202}}
 var hud=load("res://scenes/ui/game_hud.tscn").instantiate()
 hud._character={"id":44,"name":"Preview","gender":"female","customization":recipe}
 root.add_child(hud);hud._windows.character.visible=true;hud._fill_window("character")
 for frame in 3:await process_frame
 var panel=hud._equipment_panel_logic;var view=panel._character_view
 var body=view.model.axis_rig.body
 var model_id:int=view.model.get_instance_id();var body_id:int=body.get_instance_id()
 view.model.set_process(false);view.model.play("walk","front",true);view.model._from_rotations.clear();view.model.pose_at(.35)
 var points:PackedVector3Array=body.posed_points.duplicate()
 for id:String in ["underwear_lace_bra_white","underwear_lace_briefs_white"]:
  server.inventory.add_item(id,1);assert(server.try_equip_item(id).ok)
  server.equipment._bound["underwear_top"]=true;server.equipment._enhance["underwear_top"]=2
  hud.apply_equipment_snapshot(server.equipment.snapshot(),server.equipment.total_bonuses())
  for frame in 3:await process_frame
  assert(panel._character_view==view and view.model.get_instance_id()==model_id)
  assert(view.model.axis_rig.body.get_instance_id()==body_id)
  assert(view.model.appearance==recipe and view.model.action=="walk")
  assert(body.posed_points==points,"Equipment UI refresh changed current pose")
 assert(view.model.axis_rig.wardrobe.slots.size()==2)
 await RenderingServer.frame_post_draw
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/equipment_preview_02")
 DirAccess.make_dir_recursive_absolute(folder)
 var rendered:Image=view.viewport.get_texture().get_image()
 var covered:=0
 for y in rendered.get_height():
  for x in rendered.get_width():
   if rendered.get_pixel(x,y).a>.2:covered+=1
 assert(covered>500,"Preview actor exists but viewport is blank")
 assert(rendered.save_png(folder+"/actual_preview.png")==OK)
 assert(root.get_texture().get_image().save_png(folder+"/actual_hud.png")==OK)

 var map:Dictionary=panel._equipment_map();assert(map.underwear_top.bound and map.underwear_top.enhance==2)
 assert(server.try_unequip_item("underwear_top").ok)
 hud.apply_equipment_snapshot(server.equipment.snapshot(),server.equipment.total_bonuses())
 for frame in 3:await process_frame
 assert(not view.model.axis_rig.wardrobe.slots.has("UnderwearTop"))
 assert(view.model.axis_rig.wardrobe.slots.has("UnderwearBottom"))
 hud._windows.character.visible=false;hud._windows.character.visible=true;hud._fill_window("character")
 for frame in 3:await process_frame
 assert(panel._character_view==view and view.model.get_instance_id()==model_id)
 server.inventory.add_item("great_club",1);assert(server.try_equip_item("great_club").ok)
 hud.apply_equipment_snapshot(server.equipment.snapshot(),server.equipment.total_bonuses())
 view.model._process(1.0/30)
 await RenderingServer.frame_post_draw
 assert(view.model.get_instance_id()==model_id and body.get_instance_id()==body_id)
 assert(view.model.axis_rig.twohand.bridge.modifier.active and view.model.axis_rig.weapon.club.visible)
 for i in 2:
  assert(view.model.axis_rig.twohand.palm("l" if i==0 else "r").origin.distance_to(view.model.axis_rig.twohand.palm_targets[i].origin)<.005)
 assert(view.viewport.get_texture().get_image().save_png(folder+"/actual_club_preview.png")==OK)
 assert(server.try_unequip_item("weapon_main").ok)
 hud.apply_equipment_snapshot(server.equipment.snapshot(),server.equipment.total_bonuses())
 assert(not view.model.axis_rig.twohand.bridge.modifier.active and not view.model.axis_rig.weapon.visible)
 view.model.set_process(true)
 for cycle in 3:
  hud._windows.character.hide()
  var paused_time:float=view.model.elapsed
  for frame in 4:await process_frame
  assert(view.model.elapsed==paused_time and not view.model.can_process(),"Hidden preview keeps animating")
  assert(view.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED)
  hud._windows.character.show()
  for frame in 4:await process_frame
  assert(view.model.elapsed>paused_time and view.model.can_process(),"Reopened preview did not resume")
  assert(view.model.get_instance_id()==model_id and body.get_instance_id()==body_id)
 view.model.set_process(false)
 view.hide()
 assert(not view.model.can_process())
 view.show()
 assert(not view.model.is_processing(),"Visibility overwrote caller's manual pause")
 var disposable_owner:=Control.new();root.add_child(disposable_owner)
 view.set_activity_owner(disposable_owner);disposable_owner.free()
 for frame in 3:await process_frame
 assert(not view.model.can_process(),"Freed presentation owner leaves preview active")
 hud.free()
 for frame in 3:await process_frame
 assert(not is_instance_valid(view),"HUD preview actor leaked on close")
 print("PASS actual equipment HUD refresh/reopen preserves model/body/identity/pose; independent underwear removal; binding/enhance metadata; HUD cleanup")
 quit()
