extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Gear session test timeout");quit(2))
 var server=root.get_node("MockServer")
 server.login("gear_roundtrip","test","local");await server.login_finished
 var ids:Array=[]
 for name:String in ["A","B"]:
  server.create_character(name,"warrior","1","female",{"body_model":"female_base_v2","body_shapes":{"height":-.3}})
  var result:Array=await server.character_created;assert(result[0]);ids.append(result[2].id)
 server.enter_world3d(ids[0]);var entered:Array=await server.enter_world_ready;assert(entered[0])
 assert(server.try_equip_item("underwear_lace_bra_white").ok)
 assert(server.try_equip_item("underwear_lace_briefs_white").ok)
 server.equipment._durability["chest"]=37
 server.equipment._bound["chest"]=true
 server.equipment._enhance["chest"]=2
 server.inventory.add_gold(123)
 var expected_bag:Dictionary=server.inventory.capture_session_state()
 var expected_gear:Dictionary=server.equipment.capture_session_state()
 server.fetch_characters();var listed:Array=await server.characters_ready
 var converted:Dictionary=preload("res://scripts/char/character_view_3d.gd").equipment_parts("female",listed[0].equipment,server.item_catalog)
 assert(converted.SurfaceEquipment.size()==2,"Selection snapshot loses underwear slots")
 # The real selection handler must consume the same authoritative snapshot.
 var ui=load("res://scenes/character_select.tscn").instantiate();root.add_child(ui)
 await server.characters_ready
 assert(ui._icon_views[0].model.equipment.SurfaceEquipment==converted.SurfaceEquipment)
 assert(ui._icon_views[1].model.equipment.SurfaceEquipment.is_empty(),"Second character inherited first gear")
 ui.free()
 assert(server.try_trade_open("gear switch escrow").ok)
 assert(server.try_trade_put_item("potion_hp_small",1).ok)
 assert(server.try_trade_set_gold(10).ok)
 server.enter_world3d(ids[1]);await server.enter_world_ready
 assert(not server.in_trade(),"Character switch retained previous trade")
 assert(server.equipment.is_empty("underwear_top") and server.equipment.is_empty("underwear_bottom"))
 server.inventory.add_gold(9)
 server.enter_world3d(ids[0]);await server.enter_world_ready
 assert(server.equipment.capture_session_state()==expected_gear,"Equipment metadata changed on switch")
 assert(server.inventory.capture_session_state()==expected_bag,"Bag or gold duplicated/lost on switch")
 assert(server.try_unequip_item("underwear_top").ok)
 var removed:Dictionary=server.equipment.capture_session_state()
 server.logout()
 server.login("gear_other_account","test","local");await server.login_finished
 server.fetch_characters();var other:Array=await server.characters_ready;assert(other.is_empty())
 server.logout();server.login("gear_roundtrip","test","local");await server.login_finished
 server.enter_world3d(ids[0]);await server.enter_world_ready
 assert(server.equipment.capture_session_state()==removed,"Logout/relogin restored removed underwear")
 assert(server.equipment.is_empty("underwear_top") and not server.equipment.is_empty("underwear_bottom"))
 print("PASS mocker selection/equip/unequip/character switch/account isolation/relogin; bag gold and equipment metadata preserved")
 quit()


