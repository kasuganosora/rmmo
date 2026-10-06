extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Source outfit integration timed out");quit(2))
 var server=root.get_node("MockServer")
 server.login("source_outfits","test","local");await server.login_finished
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 server.create_character("Wardrobe","warrior","1","female",recipe)
 var created:Array=await server.character_created;server.enter_world3d(created[2].id);await server.enter_world_ready
 var view=View.new();root.add_child(view);view.configure("female",recipe,{})
 view.model.set_process(false);view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 var body=view.model.axis_rig.body;var body_id:int=body.get_instance_id();var posed:PackedVector3Array=body.posed_points.duplicate()
 for id:String in ["underwear_lace_bra_white","underwear_lace_briefs_white","native_maid_top","native_maid_skirt","native_maid_headpiece"]:
  assert(server.inventory.get_qty(id)==1,"Missing source garment starter")
  assert(server.try_equip_item(id).ok)
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/source_outfit_entries_01");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=2.2
 for outfit:String in ["separate","classic"]:
  if outfit=="classic":assert(server.try_equip_item("native_maid_dress").ok)
  var parts:Dictionary=View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
  view.model.set_equipment(parts)
  assert(body.get_instance_id()==body_id and body.posed_points==posed)
  assert(view.model.axis_rig.wardrobe.slots.size()==(5 if outfit=="separate" else 4))
  assert(parts.SurfaceEquipment.has("UnderwearTop") and parts.SurfaceEquipment.has("UnderwearBottom"))
  var npc=Model.create_npc({"gender":"female","customization":recipe,"equipment":parts});root.add_child(npc);npc.set_process(false)
  assert(npc.axis_rig.wardrobe.slots==view.model.axis_rig.wardrobe.slots)
  assert(npc.axis_rig.wardrobe.garments.Clothing1!=view.model.axis_rig.wardrobe.garments.Clothing1)
  npc.free()
  for side in 2:
   view.camera.position=Vector3(0 if side==0 else 4,1,4 if side==0 else 0);view.camera.look_at(Vector3(0,1,0))
   for frame in 5:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_%d.png"%[outfit,side])==OK)
 assert(server.try_unequip_item("chest").ok)
 var restored:Dictionary=View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
 assert(restored.SurfaceEquipment.has("Clothing2") and not restored.SurfaceEquipment.has("Clothing1"))
 server.create_character("Legacy","warrior","1","female",{})
 var legacy:Array=await server.character_created;server.enter_world3d(legacy[2].id);await server.enter_world_ready
 server.inventory.add_item("native_maid_dress",1)
 assert(server.try_equip_item("native_maid_dress").reason=="incompatible_body")
 assert(server.inventory.get_qty("native_maid_dress")==1)
 view.free()
 for frame in 3:await process_frame
 print("PASS source outfit inventory->snapshot->shared view/NPC, same pose/body, independent garment instances, dress masking/skirt restore, incompatible body rejection; visual contact review required")
 quit()
