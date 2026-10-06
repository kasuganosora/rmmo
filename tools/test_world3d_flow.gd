extends SceneTree
var failed := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failed += 1

func run() -> void:
	create_timer(240).timeout.connect(func():push_error("World flow timeout");quit(2))
	var axis_body:bool=OS.get_cmdline_user_args().has("--axis-body")
	var server = root.get_node("MockServer")
	var session = root.get_node("GameSession")
	server.login("review3d", "test", "local")
	await server.login_finished
	var appearance:Dictionary={"hair_color":"#884433"}
	if axis_body:
		appearance["body_shapes"]={"bust_size":.3,"waist_width":-.2,"hip_size":.2,"nose_width":.15,"height":-.25}
	server.create_character("三维角色", "warrior", "1", "female", appearance)
	var created: Array = await server.character_created
	check(bool(created[0]), "create real account character")
	var ch: Dictionary = created[2]
	session.selected_character = ch
	session.world3d_map_path = ""
	session.world3d_spawn = Vector3(0, 0.9, 4)
	session.loading_mode = ""
	change_scene_to_file("res://scenes/loading.tscn")
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:
			break
	var world = current_scene
	check(world != null and world.has_method("is_world_ready"), "login Loading hands off to 3D world")
	if world == null or not world.has_method("is_world_ready"):
		quit(1)
		return
	check(world._player != null and not world._player.input_locked, "controls unlock after prepared world")
	check(world._player.get_node("CharacterModel3D").body_type == "female", "selected body type preserved")
	check(world._player.character.get("customization", {}) == ch.get("customization", {}), "customization preserved")
	check(not session.spawn_data.has("cell") and session.spawn_data.get("world_mode") == "world3d", "3D spawn does not carry integer grid coordinates")
	check(world._hud != null and not session.spawn_data.get("equipment", []).is_empty(), "shared HUD and starter equipment initialized")
	if axis_body:
		var actor:Node3D=world._player.get_node("CharacterModel3D")
		check(actor.axis_rig!=null,"created body version reaches actual 3D player")
		if actor.axis_rig==null:world.free();quit(1);return
		var body_id:int=actor.axis_rig.body.get_instance_id()
		var weapon_equip:Dictionary=server.try_equip_item("wooden_sword")
		check(bool(weapon_equip.get("ok",false)),"equip actual starter wooden sword")
		world.apply_actions(weapon_equip.get("actions",[]))
		check(actor.axis_rig.weapon.enabled and actor.axis_rig.weapon.item_id=="wooden_sword","main-hand item identity reaches actual player")
		check(actor.axis_rig.weapon.pieces[2].material_override.albedo_color==Color("ba8d59"),"wooden sword keeps wood blade material")
		actor.play("attack","front",true)
		check(actor.animation_clip.begins_with("attack_sword_"),"equipped player selects actual sword animation")
		var weapon_remove:Dictionary=server.try_unequip_item("weapon_main")
		world.apply_actions(weapon_remove.get("actions",[]))
		check(not actor.axis_rig.weapon.enabled and actor.axis_rig.weapon.item_id.is_empty(),"live main-hand unequip clears visual identity")
		actor.play("idle","front",true)
		server.inventory.add_item("great_club",1)
		var club_equip:Dictionary=server.try_equip_item("great_club")
		check(bool(club_equip.get("ok",false)),"equip actual two-hand club")
		world.apply_actions(club_equip.get("actions",[]))
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		check(actor.axis_rig.twohand.bridge.modifier.active and actor.axis_rig.weapon.club.visible,"world player activates native two-hand solver")
		var grip_error:=0.0
		for i in 2:
			grip_error=maxf(grip_error,actor.axis_rig.twohand.palm("l" if i==0 else "r").origin.distance_to(actor.axis_rig.twohand.palm_targets[i].origin))
		check(grip_error<.005,"world player final palms reach club grips")
		var club_remove:Dictionary=server.try_unequip_item("weapon_main")
		world.apply_actions(club_remove.get("actions",[]))
		check(not actor.axis_rig.twohand.bridge.modifier.active and not actor.axis_rig.weapon.visible,"live club removal cancels modifier immediately")
		check(actor.axis_rig.body.shape_values==appearance.body_shapes,"native identity recipe reaches actual 3D player")
		for id:String in ["underwear_lace_bra_white","underwear_lace_briefs_white"]:
			var equip:Dictionary=server.try_equip_item(id)
			check(bool(equip.get("ok",false)),"equip inventory item in live world: "+id)
			world.apply_actions(equip.get("actions",[]))
		check(actor.axis_rig.wardrobe.slots==preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE,"equipment_update reaches shared axis wardrobe")
		var remove:Dictionary=server.try_unequip_item("underwear_top")
		world.apply_actions(remove.get("actions",[]))
		check(not actor.axis_rig.wardrobe.slots.has("UnderwearTop") and actor.axis_rig.wardrobe.slots.has("UnderwearBottom"),"live underwear slots remain independent")
		check(actor.axis_rig.body.get_instance_id()==body_id,"live equipment updates preserve actor identity")
		check(actor.axis_rig.body.shape_values==appearance.body_shapes,"equipment updates preserve native identity weights")
		actor.set_process(false)
		check(world._player.request_rest("lie_down"),"world player accepts shared lying action")
		world._player._step(1.0/60)
		check(actor.action=="lie_down","locomotion does not overwrite resting transition")
		actor.elapsed=actor.action_duration();actor._process(.01)
		check(actor.action=="lie","lying transition completes into resting loop")
		world._player.click_target=world._player.global_position+Vector3(1,0,0)
		world._player._step(1.0/60)
		check(actor.action=="get_up","movement requests getting up before walking")
		actor.elapsed=actor.action_duration();actor._process(.01)
		check(actor.action=="idle","recovery completes into idle")
		world._player.click_target=null
		world.request_sit(true)
		check(world._sit_preparing and not server.sitting,"sit preparation does not preempt server state")
		var request_revision:int=world._sit_revision
		world.request_sit(true)
		check(world._sit_revision==request_revision,"duplicate explicit sit coalesces pending preparation")
		world.request_sit(false)
		while world._sit_preparing:await process_frame
		check(not server.sitting and actor.action=="idle","cancelled preparation cannot sit later")
		await world.request_sit(true)
		check(server.sitting and actor.action=="sit_down_ground","normal world request installs and applies authoritative sit")
		world._player._step(1.0/60)
		check(actor.action=="sit_down_ground","movement controller preserves ground entry")
		actor.elapsed=.7;actor._process(0)
		var reverse_phase:float=actor.action_duration()-actor.elapsed
		world._player.click_target=world._player.global_position+Vector3(1,0,0)
		world._player._step(1.0/60)
		check(not server.sitting and actor.action=="stand_up_ground" and absf(actor.elapsed-reverse_phase)<.0001,"move clears server sit and interrupts at matching reverse phase")
		actor.elapsed=actor.action_duration();actor._process(.01)
		check(actor.action=="idle","ground interruption completes into idle")
		world._player.click_target=null
		var sit_key:=InputEventKey.new();sit_key.pressed=true
		sit_key.keycode=preload("res://scripts/game/game_settings.gd").get_i().key_for("sit")
		world._hud._unhandled_input(sit_key)
		while world._sit_preparing:await process_frame
		check(server.sitting and actor.action=="sit_down_ground","HUD configured sit key reaches normal request")
		actor.elapsed=actor.action_duration();actor._process(.01)
		world._player._step(1.0/60)
		check(actor.action=="sit_ground","ground hold survives locomotion tick")
		world._player.click_target=world._player.global_position+Vector3(1,0,0)
		world._player._step(1.0/60)
		check(actor.action=="stand_up_ground","move requests ground recovery before walking")
		actor.elapsed=actor.action_duration();actor._process(.01)
		world._player.click_target=null
		await world.request_sit(true)
		var damage:Array=[]
		server.combat_engine._damage_player(1,damage,"",false)
		world._combat._apply({"actions":damage})
		check(not server.sitting and actor.action=="stand_up_ground","actual nonfatal damage interrupts authoritative sitting")
		actor.elapsed=actor.action_duration();actor._process(.01)
		world._player.click_target=null;actor.set_process(true)
		for id:String in ["native_maid_top","native_maid_skirt","native_maid_headpiece"]:
			var equip:Dictionary=server.try_equip_item(id)
			check(bool(equip.get("ok",false)),"source outfit live equip: "+id)
			world.apply_actions(equip.get("actions",[]))
		check(actor.axis_rig.wardrobe.slots.get("Clothing1")=="maid_separate/item_02" and actor.axis_rig.wardrobe.slots.get("Clothing2")=="maid_separate/item_01","live player resolves source top and skirt")
		check(actor.axis_rig.body.get_instance_id()==body_id and actor.axis_rig.body.shape_values==appearance.body_shapes,"source outfit preserves live identity")
	var events = server.world3d_events
	var money: int = server.inventory.get_gold()
	var spec := {"uuid": "reward", "position": Vector3.ZERO, "extras": {"kind": "npc", "event": {"pages": [
		{"commands": [{"op": "give_gold", "amount": 7}, {"op": "set_self_switch", "letter": "A"}]},
		{"when": {"self_switch": "A"}, "commands": [{"op": "text", "text": "已领取"}]},
	]}}}
	events.mount("test/one", [spec])
	world.apply_actions(events.runtime.run_event("reward", events.context()))
	check(server.inventory.get_gold() == money + 7, "event commands mutate real inventory")
	events.mount("test/two", [spec])
	check(not events.runtime.get_self_switch("reward", "A"), "self-switch is namespaced by map")
	events.mount("test/one", [spec])
	world.apply_actions(events.runtime.run_event("reward", events.context()))
	check(server.inventory.get_gold() == money + 7, "returning to map does not duplicate reward")
	check(world._status.text == "已领取", "event page conditions use persisted self-switch")
	var trigger_mesh := BoxMesh.new()
	trigger_mesh.size = Vector3(1, 0.2, 1)
	var trigger := {"uuid": "touch", "position": Vector3.ZERO, "transform": Transform3D.IDENTITY, "mesh": trigger_mesh, "extras": {"kind": "event", "event": {"pages": [{"trigger": "player_touch", "commands": [{"op": "give_gold", "amount": 3}]}]}}}
	events.mount("test/touch", [trigger])
	money = server.inventory.get_gold()
	events.touch_segment(Vector3(-2, 3, 0), Vector3(2, 3, 0))
	check(server.inventory.get_gold() == money, "touch event does not trigger across floors")
	events.touch_segment(Vector3(-2, 0, 0), Vector3.ZERO)
	events.touch_segment(Vector3.ZERO, Vector3(0.1, 0, 0))
	check(server.inventory.get_gold() == money + 3, "swept touch event triggers once per entry")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var path := preload("res://scripts/asset/art_paths.gd").review_path("world3d_axis_flow.png" if axis_body else "world3d_flow.png")
		root.get_texture().get_image().save_png(path)
		print("capture=" + path)
	world.free()
	await process_frame
	await process_frame
	print("test_world3d_flow: %s" % ("PASS" if failed == 0 else "FAIL %d" % failed))
	quit(0 if failed == 0 else 1)
