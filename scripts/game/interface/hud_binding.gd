extends RefCounted
## Interface layer: bind HUD signals to world use cases.

const Net = preload("res://scripts/net/net.gd")

static func _bind_hud(ctrl, ch: Dictionary, spawn: Dictionary) -> void:
	if ctrl.hud == null:
		ctrl.hud = ctrl.get_node_or_null("CanvasLayer/GameHud")
	if ctrl.hud == null:
		return
	if ctrl.hud.has_method("bind_character"):
		ctrl.hud.bind_character(ch)
	var map_id := str(spawn.get("map_id", "demo_map"))
	if ctrl.hud.has_method("bind_radar"):
		ctrl.hud.bind_radar(ctrl.map_field, ctrl.player, map_id, ctrl)
	elif ctrl.hud.has_method("set_minimap_hint"):
		ctrl.hud.set_minimap_hint("%s\n%s" % [map_id, Net.session().server_address])
	if ctrl.hud.has_method("apply_combat_stats"):
		var combat_v: Variant = spawn.get("combat", {})
		if typeof(combat_v) == TYPE_DICTIONARY and not (combat_v as Dictionary).is_empty():
			ctrl.hud.apply_combat_stats(combat_v)
		elif Net.server() != null and Net.server().get("combat_stats") != null:
			ctrl.hud.apply_combat_stats(Net.server().combat_stats.snapshot_player_stats())
	if ctrl.hud.has_method("apply_inventory_snapshot"):
		var inv_v: Variant = spawn.get("inventory", [])
		var gold_v: int = int(spawn.get("gold", -1))
		if typeof(inv_v) == TYPE_ARRAY:
			ctrl.hud.apply_inventory_snapshot(inv_v, gold_v)
	if ctrl.hud.has_method("apply_equipment_snapshot"):
		var eq_v: Variant = spawn.get("equipment", [])
		var bon_v: Variant = spawn.get("equipment_bonuses", {})
		if typeof(eq_v) == TYPE_ARRAY:
			var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
			ctrl.hud.apply_equipment_snapshot(eq_v, bons)
	if ctrl.hud.has_method("apply_skill_catalog"):
		var srv_skills = Net.server()
		if srv_skills != null and srv_skills.has_method("snapshot_skill_catalog"):
			ctrl.hud.apply_skill_catalog(srv_skills.snapshot_skill_catalog())
	if ctrl.hud.has_method("apply_skill_book"):
		var book_v: Variant = spawn.get("skill_book", {})
		if typeof(book_v) == TYPE_DICTIONARY and not (book_v as Dictionary).is_empty():
			ctrl.hud.apply_skill_book(book_v)
		else:
			var srv_book = Net.server()
			if srv_book != null and srv_book.has_method("snapshot_skill_book"):
				ctrl.hud.apply_skill_book(srv_book.snapshot_skill_book())
	if ctrl.hud.has_method("apply_quest_snapshot"):
		var quests_v: Variant = spawn.get("quests", [])
		if typeof(quests_v) == TYPE_ARRAY and not (quests_v as Array).is_empty():
			ctrl.hud.apply_quest_snapshot(quests_v)
		else:
			var srv_q = Net.server()
			if srv_q != null and srv_q.has_method("get_quest_list"):
				ctrl.hud.apply_quest_snapshot(srv_q.get_quest_list())
	if ctrl.hud.has_method("apply_daily_board"):
		ctrl.hud.apply_daily_board(spawn)
	if ctrl.hud.has_method("apply_party_update"):
		var party_v: Variant = spawn.get("party", {})
		if typeof(party_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_party_update({"type": "party_update", "party": party_v})
		elif Net.server() != null and Net.server().has_method("snapshot_party"):
			ctrl.hud.apply_party_update({"type": "party_update", "party": Net.server().snapshot_party()})
	if ctrl.hud.has_method("apply_trade_update"):
		var trade_v: Variant = spawn.get("trade", {})
		if typeof(trade_v) == TYPE_DICTIONARY and bool(trade_v.get("active", false)):
			ctrl.hud.apply_trade_update({"type": "trade_update", "trade": trade_v})
	if ctrl.hud.has_method("apply_duel_update"):
		var duel_v: Variant = spawn.get("duel", {})
		if typeof(duel_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_duel_update({"type": "duel_update", "duel": duel_v})
		elif Net.server() != null and Net.server().has_method("snapshot_duel"):
			ctrl.hud.apply_duel_update({"type": "duel_update", "duel": Net.server().snapshot_duel()})
	if ctrl.hud.has_method("apply_safe_zone"):
		var sz_v: Variant = spawn.get("safe_zone", {})
		if typeof(sz_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_safe_zone({"type": "safe_zone", "inside": bool(sz_v.get("inside", false))})
		elif Net.server() != null and Net.server().has_method("player_in_safe_zone"):
			ctrl.hud.apply_safe_zone({"type": "safe_zone", "inside": bool(Net.server().player_in_safe_zone())})
	if ctrl.hud.has_method("apply_dungeon_update"):
		var dg_v: Variant = spawn.get("dungeon", {})
		if typeof(dg_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_dungeon_update({"type": "dungeon_update", "dungeon": dg_v})
		elif Net.server() != null and Net.server().has_method("snapshot_dungeon"):
			ctrl.hud.apply_dungeon_update({"type": "dungeon_update", "dungeon": Net.server().snapshot_dungeon()})

	if ctrl.hud.has_method("apply_craft_update"):
		var craft_act := {
			"type": "craft_update",
			"craft_level": int(spawn.get("craft_level", 1)),
			"craft_xp": int(spawn.get("craft_xp", 0)),
			"craft_xp_to_next": int(spawn.get("craft_xp_to_next", 30)),
		}
		if Net.server() != null and Net.server().has_method("snapshot_craft"):
			var cs: Dictionary = Net.server().snapshot_craft()
			craft_act["craft_level"] = int(cs.get("craft_level", craft_act["craft_level"]))
			craft_act["craft_xp"] = int(cs.get("craft_xp", craft_act["craft_xp"]))
			craft_act["craft_xp_to_next"] = int(cs.get("craft_xp_to_next", craft_act["craft_xp_to_next"]))
		elif spawn.has("craft_level") or spawn.has("craft_xp"):
			pass
		ctrl.hud.apply_craft_update(craft_act)

	if ctrl.hud.has_method("apply_gather_update"):
		var gather_act := {
			"type": "gather_update",
			"gather_level": int(spawn.get("gather_level", 1)),
			"gather_xp": int(spawn.get("gather_xp", 0)),
			"gather_xp_to_next": int(spawn.get("gather_xp_to_next", 30)),
		}
		if Net.server() != null and Net.server().has_method("snapshot_gather"):
			var gs: Dictionary = Net.server().snapshot_gather()
			gather_act["gather_level"] = int(gs.get("gather_level", gather_act["gather_level"]))
			gather_act["gather_xp"] = int(gs.get("gather_xp", gather_act["gather_xp"]))
			gather_act["gather_xp_to_next"] = int(gs.get("gather_xp_to_next", gather_act["gather_xp_to_next"]))
		ctrl.hud.apply_gather_update(gather_act)

	if ctrl.hud.has_method("apply_warehouse_update"):
		var wh_v: Variant = spawn.get("warehouse", {})
		if typeof(wh_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_warehouse_update({"type": "warehouse_update", "warehouse": wh_v})
		elif Net.server() != null and Net.server().has_method("snapshot_warehouse"):
			ctrl.hud.apply_warehouse_update({"type": "warehouse_update", "warehouse": Net.server().snapshot_warehouse()})

	if ctrl.hud.has_method("apply_friends_update"):
		var fr_v: Variant = spawn.get("friends", {})
		if typeof(fr_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_friends_update({"type": "friends_update", "friends": fr_v})
		elif Net.server() != null and Net.server().has_method("snapshot_friends"):
			ctrl.hud.apply_friends_update({"type": "friends_update", "friends": Net.server().snapshot_friends()})

	if ctrl.hud.has_method("apply_guild_update"):
		var gu_v: Variant = spawn.get("guild", {})
		if typeof(gu_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_guild_update({"type": "guild_update", "guild": gu_v})
		elif Net.server() != null and Net.server().has_method("snapshot_guild"):
			ctrl.hud.apply_guild_update({"type": "guild_update", "guild": Net.server().snapshot_guild()})

	if ctrl.hud.has_method("apply_mail_update"):
		var mail_v: Variant = spawn.get("mail", {})
		if typeof(mail_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_mail_update({"type": "mail_update", "mail": mail_v})
		elif Net.server() != null and Net.server().has_method("snapshot_mail"):
			ctrl.hud.apply_mail_update({"type": "mail_update", "mail": Net.server().snapshot_mail()})

	if ctrl.hud.has_method("apply_auction_update"):
		var ah_v: Variant = spawn.get("auction", {})
		if typeof(ah_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_auction_update({"type": "auction_update", "auction": ah_v})
		elif Net.server() != null and Net.server().has_method("snapshot_auction"):
			ctrl.hud.apply_auction_update({"type": "auction_update", "auction": Net.server().snapshot_auction()})

	if ctrl.hud.has_method("apply_title_update"):
		var titles_v: Variant = spawn.get("titles", {})
		if typeof(titles_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_title_update({"type": "title_update", "titles": titles_v})
		elif Net.server() != null and Net.server().has_method("snapshot_titles"):
			ctrl.hud.apply_title_update({"type": "title_update", "titles": Net.server().snapshot_titles()})

	if ctrl.hud.has_method("apply_achievement_update"):
		var ach_v: Variant = spawn.get("achievements", {})
		if typeof(ach_v) == TYPE_DICTIONARY:
			ctrl.hud.apply_achievement_update({"type": "achievement_update", "achievements": ach_v})
		elif Net.server() != null and Net.server().has_method("snapshot_achievements"):
			ctrl.hud.apply_achievement_update({"type": "achievement_update", "achievements": Net.server().snapshot_achievements()})

	var remotes_v: Variant = spawn.get("remote_players", [])
	if typeof(remotes_v) == TYPE_ARRAY:
		for rp in remotes_v:
			if typeof(rp) == TYPE_DICTIONARY:
				ctrl._upsert_remote_marker(rp)
	var pet_v: Variant = spawn.get("pet", {})
	if typeof(pet_v) == TYPE_DICTIONARY and bool(pet_v.get("active", false)):
		ctrl._upsert_pet_marker(pet_v)
	elif Net.server() != null and Net.server().has_method("snapshot_pet"):
		var pet2: Dictionary = Net.server().snapshot_pet()
		if bool(pet2.get("active", false)):
			ctrl._upsert_pet_marker(pet2)
	elif Net.server() != null and Net.server().has_method("snapshot_remote_players"):
		for rp2 in Net.server().snapshot_remote_players():
			if typeof(rp2) == TYPE_DICTIONARY:
				ctrl._upsert_remote_marker(rp2)
	if ctrl.hud.has_method("bind_world_combat"):
		ctrl.hud.bind_world_combat(ctrl)
	var eq_bind: Variant = spawn.get("equipment", [])
	if typeof(eq_bind) == TYPE_ARRAY:
		ctrl._refresh_player_gear_look(eq_bind)
	ctrl._apply_camera_zoom()
	# Ground bags from spawn snapshot (map re-entry).
	var bags_v: Variant = spawn.get("ground_bags", [])
	if typeof(bags_v) == TYPE_ARRAY:
		for b in bags_v:
			if typeof(b) == TYPE_DICTIONARY:
				ctrl._upsert_ground_marker(b)
	elif Net.server() != null and Net.server().has_method("snapshot_ground_bags"):
		for b2 in Net.server().snapshot_ground_bags():
			if typeof(b2) == TYPE_DICTIONARY:
				ctrl._upsert_ground_marker(b2)
	if ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("进入角色：%s（Lv.%s）" % [str(ch.get("name", "?")), str(ch.get("level", 1))])
		var transfer_msg: String = str(spawn.get("transfer_message", "")).strip_edges()
		if transfer_msg != "":
			ctrl.hud.append_system(transfer_msg)
			var sd: Dictionary = Net.session().spawn_data
			if sd.has("transfer_message"):
				sd.erase("transfer_message")
				Net.session().spawn_data = sd

