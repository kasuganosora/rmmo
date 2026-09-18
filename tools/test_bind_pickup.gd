extends SceneTree
## Headless: bind-on-pickup — ground loot / quest reward binds; trade/auction/mail blocked;
## vendor sell blocked「已绑定，无法出售。」; non-BoP unbound; BoE bound still sellable.


func _init() -> void:
	call_deferred("_run")


const EquipmentScript = preload("res://scripts/net/combat/equipment.gd")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_bind_pickup: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.equipment == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.item_catalog == null:
		print("test_bind_pickup: FAIL combat layers missing")
		quit(1)
		return

	failed += _expect(srv.item_catalog.has_item("bone_necklace"), "catalog bone_necklace")
	failed += _expect(srv.item_catalog.has_item("wooden_sword"), "catalog wooden_sword")
	failed += _expect(srv.item_catalog.has_item("slime_jelly"), "catalog slime_jelly")
	var bn: Dictionary = srv.item_catalog.get_item("bone_necklace")
	var ws: Dictionary = srv.item_catalog.get_item("wooden_sword")
	var sj: Dictionary = srv.item_catalog.get_item("slime_jelly")
	failed += _expect(EquipmentScript.is_bind_on_pickup(bn), "bone_necklace is BoP")
	failed += _expect(not EquipmentScript.is_bind_on_equip(bn), "bone_necklace not BoE")
	failed += _expect(EquipmentScript.is_bind_on_equip(ws), "wooden_sword is BoE")
	failed += _expect(not EquipmentScript.is_bind_on_pickup(ws), "wooden_sword not BoP")
	failed += _expect(not EquipmentScript.is_bind_on_pickup(sj), "slime_jelly not BoP")

	# --- Ground loot binds ---
	srv.inventory.clear()
	if srv.equipment != null:
		srv.equipment.clear()
	srv.inventory.add_gold(200)
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	if srv.has_method("set_player_cell"):
		srv.set_player_cell(5, 5)
	else:
		srv.player_cell = Vector2i(5, 5)

	var acts: Array = srv._add_items_to_ground(
		{"x": 5, "y": 5},
		[{"item_id": "bone_necklace", "qty": 1}],
		"monster",
		"bop_npc",
		""
	)
	failed += _expect(not acts.is_empty(), "spawn bag actions")
	var bag_id := ""
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "ground_spawn":
			var bag_v: Variant = a.get("bag", {})
			if typeof(bag_v) == TYPE_DICTIONARY:
				bag_id = str(bag_v.get("id", ""))
	if bag_id.is_empty() and not srv._ground_bags.is_empty():
		bag_id = str(srv._ground_bags.keys()[0])
	failed += _expect(not bag_id.is_empty(), "bag_id")

	var open_r: Dictionary = srv.try_open_ground_bag(bag_id)
	failed += _expect(bool(open_r.get("ok", false)), "open bag")
	var take: Dictionary = srv.try_loot_take("bone_necklace", 1)
	failed += _expect(bool(take.get("ok", false)), "loot take BoP ok")
	failed += _expect(srv.inventory.has_item("bone_necklace", 1), "BoP in bag")
	failed += _expect(srv.inventory.is_bound("bone_necklace"), "BoP bound on pickup")
	var snap_bound := false
	for row in srv.inventory.snapshot():
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == "bone_necklace":
			if bool(row.get("bound", false)):
				snap_bound = true
	failed += _expect(snap_bound, "snapshot bound flag")

	# --- Bound BoP: trade / auction / mail blocked ---
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	elif srv.in_trade():
		srv.try_trade_cancel()
	var op: Dictionary = srv.try_trade_open("拾取绑定测试商人")
	failed += _expect(bool(op.get("ok", false)), "trade open")
	var putb: Dictionary = srv.try_trade_put_item("bone_necklace", 1)
	failed += _expect(not bool(putb.get("ok", false)), "trade rejects BoP bound")
	failed += _expect(str(putb.get("reason", "")) == "bound", "trade reason bound")
	failed += _expect(srv.inventory.has_item("bone_necklace", 1), "trade did not consume")
	if srv.in_trade():
		srv.try_trade_cancel()

	if srv.auction != null and srv.auction.has_method("clear"):
		srv.auction.clear()
	var auc: Dictionary = srv.try_auction_list("bone_necklace", 1, 50)
	failed += _expect(not bool(auc.get("ok", false)), "auction rejects BoP")
	failed += _expect(str(auc.get("reason", "")) == "bound", "auction reason bound")

	var self_name := "你"
	if srv.has_method("_party_self_name"):
		self_name = str(srv._party_self_name())
	var mail: Dictionary = srv.try_mail_send(self_name, "绑测", "body", 0, "bone_necklace", 1)
	failed += _expect(not bool(mail.get("ok", false)), "mail rejects BoP")
	failed += _expect(str(mail.get("reason", "")) == "bound", "mail reason bound")

	# --- Vendor sell blocked for BoP bound ---
	var gold0: int = srv.inventory.get_gold()
	var sell: Dictionary = srv.try_shop_sell("bone_necklace", 1)
	failed += _expect(not bool(sell.get("ok", false)), "shop sell BoP blocked")
	failed += _expect(str(sell.get("reason", "")) == "bound", "sell reason bound")
	failed += _expect(_has_sys(sell, "已绑定，无法出售"), "sell msg 已绑定，无法出售。")
	failed += _expect(srv.inventory.has_item("bone_necklace", 1), "sell did not consume BoP")
	failed += _expect(srv.inventory.get_gold() == gold0, "gold unchanged")

	# --- Quest reward binds ---
	srv.inventory.clear()
	var grant_actions: Array = srv._grant_quest_reward({
		"exp": 0,
		"gold": 0,
		"items": [{"id": "bone_necklace", "qty": 1}],
	})
	failed += _expect(not grant_actions.is_empty(), "quest grant actions")
	failed += _expect(srv.inventory.has_item("bone_necklace", 1), "quest reward in bag")
	failed += _expect(srv.inventory.is_bound("bone_necklace"), "quest reward BoP bound")

	# --- Non-BoP loot stays unbound ---
	srv.inventory.clear()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	var acts2: Array = srv._add_items_to_ground(
		{"x": 5, "y": 5},
		[{"item_id": "slime_jelly", "qty": 1}],
		"monster",
		"",
		""
	)
	var bag2 := ""
	for a2 in acts2:
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "ground_spawn":
			var bv: Variant = a2.get("bag", {})
			if typeof(bv) == TYPE_DICTIONARY:
				bag2 = str(bv.get("id", ""))
	if bag2.is_empty() and not srv._ground_bags.is_empty():
		bag2 = str(srv._ground_bags.keys()[0])
	var open2: Dictionary = srv.try_open_ground_bag(bag2)
	failed += _expect(bool(open2.get("ok", false)), "open jelly bag")
	var take2: Dictionary = srv.try_loot_take("slime_jelly", 1)
	failed += _expect(bool(take2.get("ok", false)), "loot jelly ok")
	failed += _expect(not srv.inventory.is_bound("slime_jelly"), "jelly unbound")

	# --- BoE bound still vendor-sellable (regression) ---
	srv.inventory.clear()
	if srv.equipment != null:
		srv.equipment.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("wooden_sword", 1)
	var eq: Dictionary = srv.try_equip_item("wooden_sword")
	failed += _expect(bool(eq.get("ok", false)), "equip BoE ok")
	var slot := str(eq.get("slot", ""))
	if not slot.is_empty():
		srv.try_unequip_item(slot)
	failed += _expect(srv.inventory.is_bound("wooden_sword"), "BoE bound after equip")
	var sell_boe: Dictionary = srv.try_shop_sell("wooden_sword", 1)
	failed += _expect(bool(sell_boe.get("ok", false)), "BoE bound still sellable")

	if failed == 0:
		print("test_bind_pickup: PASS")
		quit(0)
		return
	print("test_bind_pickup: FAIL count=%d" % failed)
	quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _has_sys(result: Dictionary, needle: String) -> bool:
	var actions: Array = result.get("actions", [])
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		var txt := str(a.get("text", ""))
		if txt.find(needle) >= 0:
			return true
	return false
