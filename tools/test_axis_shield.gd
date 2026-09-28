extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Shield timeout");quit(2))
 var server=root.get_node("MockServer")
 server.login("shield_review","test","local");await server.login_finished
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 server.create_character("Shield","warrior","1","female",recipe)
 var created:Array=await server.character_created;server.enter_world3d(created[2].id);await server.enter_world_ready
 server.inventory.add_item("wood_shield",1);server.inventory.add_item("great_club",1)
 for id:String in ["wooden_sword","wood_shield","underwear_lace_bra_white","underwear_lace_briefs_white"]:assert(server.try_equip_item(id).ok)
 var parts:Dictionary=View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
 var view=View.new();root.add_child(view);view.configure("female",recipe,parts);view.model.set_process(false)
 var body=view.model.axis_rig.body;var shield=view.model.axis_rig.shield
 assert(shield.visible and shield.item_id=="wood_shield" and view.model.axis_rig.weapon.enabled)
 var npc=View.Model.create_npc({"gender":"female","customization":recipe,"equipment":parts});root.add_child(npc);npc.set_process(false)
 assert(npc.axis_rig.shield.visible and npc.axis_rig.shield!=shield and npc.axis_rig.shield.board.material_override!=shield.board.material_override)
 npc.set_equipment({});assert(shield.visible and not npc.axis_rig.shield.visible,"NPC unequip affects player shield")
 npc.free()
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_shield_01");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=2.4
 var id:int=body.get_instance_id();var samples:=0
 for height:float in [-1.0,1.0,0.0]:
  recipe.body_shapes={"height":height};view.model.configure("female",recipe,parts)
  for action:String in ["idle","walk","attack"]:
   view.model.play(action,"front",true)
   for frame in 12:
    view.model._process(1.0/60);samples+=1
    assert(body.get_instance_id()==id and body.pose_sync_error.is_empty())
    assert(absf(shield.basis.determinant()-1)<.0001)
    assert(shield.position.distance_to(shield.point("rForeArm").lerp(shield.point("rHand"),.6)+body.root_offset)<.00001)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 for side in 3:
  view.camera.position=[Vector3(0,1,4),Vector3(4,1,0),Vector3(0,1,-4)][side];view.camera.look_at(Vector3(0,1,0))
  for frame in 4:await process_frame
  await RenderingServer.frame_post_draw
  assert(view.viewport.get_texture().get_image().save_png(folder+"/idle_%d.png"%side)==OK)
 view.model.play("attack","front",true);view.model._from_rotations.clear();view.model.pose_at(.4)
 view.camera.size=3.3;view.camera.position=Vector3(0,1,4);view.camera.look_at(Vector3(0,1,0))
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 assert(view.viewport.get_texture().get_image().save_png(folder+"/attack.png")==OK)
 var unchanged:PackedVector3Array=body.posed_points.duplicate()
 assert(server.try_unequip_item("weapon_off").ok)
 view.model.set_equipment(View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog))
 assert(not shield.visible and shield.item_id.is_empty() and body.posed_points==unchanged,"Shield removal changes body pose")
 assert(server.try_equip_item("wood_shield").ok)
 assert(server.try_equip_item("great_club").ok)
 var both:Dictionary=View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
 view.model.set_equipment(both)
 assert(not shield.visible and not both.has("WeaponOffItem"),"Two-hand item leaves a stale shield")
 assert(view.model.axis_rig.weapon.club.visible and not view.model.axis_rig.weapon.pieces[0].visible,"Great club renders a sword")
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 assert(view.viewport.get_texture().get_image().save_png(folder+"/club_singlehand_unaccepted.png")==OK)
 assert(not server.try_equip_item("wood_shield").ok,"Server permits shield with two-hand weapon")
 assert(server.try_equip_item("wooden_sword").ok)
 view.model.set_equipment(View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog))
 assert(not view.model.axis_rig.weapon.club.visible and view.model.axis_rig.weapon.pieces[0].visible,"Switching back leaves club geometry")
 var report={"samples":samples,"body_reused":true,"unequip_pose_unchanged":true,"two_hand_exclusion":true,"scope":"Strapped whitebox shield and actual mocker mapping; inspect fit, not block/attack contact acceptance"}
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS shield actual equipment, height/final blend attachment, unload and two-hand exclusion")
 quit()
