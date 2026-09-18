extends SceneTree
## Headless: MockServer auction list / buy / cancel + NPC stubs + fail paths.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_auction: FAIL no MockServer")
		quit(1)
		return
	if srv.auction == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.auction == null:
		print("test_auction: FAIL no auction after init")
		quit(1)
		return

	srv._session_character_id = "1"
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_auction_list"), "has try_auction_list")
	failed += _expect(srv.has_method("try_auction_buy"), "has try_auction_buy")
	failed += _expect(srv.has_method("try_auction_cancel"), "has try_auction_cancel")
	failed += _expect(srv.has_method("snapshot_auction"), "has snapshot_auction")

	# Fresh state + NPC stubs (enter_world style)
	srv.auction.clear()
	if srv.has_method("_auction_seed_npc_stubs"):
		srv._auction_seed_npc_stubs()
	var snap0: Dictionary = srv.snapshot_auction()
	failed += _expect(typeof(snap0.get("listings", null)) == TYPE_ARRAY, "snap listings array")
	var stubs: Array = snap0.get("listings", [])
	failed += _expect(stubs.size() >= 3, "npc stubs >= 3")
	failed += _expect(stubs.size() <= 5, "npc stubs <= 5")
	failed += _expect(int(snap0.get("max_listings", 0)) >= 50, "cap >= 50")
	if stubs.size() > 0 and typeof(stubs[0]) == TYPE_DICTIONARY:
		var s0: Dictionary = stubs[0]
		for k in ["id", "seller_id", "seller_name", "item_id", "item_name", "qty", "price_gold", "created_at"]:
			failed += _expect(s0.has(k), "stub has %s" % k)

	# Buy NPC stub
	srv.inventory.clear()
	srv.inventory.add_gold(500)
	var gold0: int = srv.inventory.get_gold()
	var stub_id := ""
	var stub_item := ""
	var stub_qty := 0
	var stub_price := 0
	for e in stubs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("seller_id", "")).begins_with("npc_"):
			stub_id = str(e.get("id", ""))
			stub_item = str(e.get("item_id", ""))
			stub_qty = int(e.get("qty", 0))
			stub_price = int(e.get("price_gold", 0))
			break
	failed += _expect(stub_id != "", "found npc stub")
	var buy1: Dictionary = srv.try_auction_buy(stub_id)
	failed += _expect(bool(buy1.get("ok", false)), "buy npc ok")
	failed += _expect(_has(buy1, "auction_update"), "buy auction_update")
	failed += _expect(_has(buy1, "inventory_update"), "buy inventory_update")
	failed += _expect(_has(buy1, "system_message"), "buy system_message")
	failed += _expect(srv.inventory.get_gold() == gold0 - stub_price, "gold spent")
	failed += _expect(srv.inventory.get_qty(stub_item) >= stub_qty, "item received")
	failed += _expect(srv.auction.find_index(stub_id) < 0, "listing removed")

	# List from bag
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("potion_hp_small", 5)
	var list1: Dictionary = srv.try_auction_list("potion_hp_small", 2, 40)
	failed += _expect(bool(list1.get("ok", false)), "list ok")
	failed += _expect(_has(list1, "auction_update"), "list auction_update")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 3, "bag deducted")
	var my_id := ""
	for e2 in srv.snapshot_auction().get("listings", []):
		if typeof(e2) != TYPE_DICTIONARY:
			continue
		if str(e2.get("seller_id", "")) == "1" or str(e2.get("seller_id", "")) == "player":
			my_id = str(e2.get("id", ""))
			failed += _expect(int(e2.get("price_gold", 0)) == 40, "list price")
			failed += _expect(int(e2.get("qty", 0)) == 2, "list qty")
			break
	# seller may be session id "1"
	if my_id == "":
		for e3 in srv.snapshot_auction().get("listings", []):
			if typeof(e3) != TYPE_DICTIONARY:
				continue
			if str(e3.get("item_id", "")) == "potion_hp_small" and int(e3.get("price_gold", 0)) == 40:
				my_id = str(e3.get("id", ""))
				break
	failed += _expect(my_id != "", "own listing id")

	# Cannot buy own
	var buy_own: Dictionary = srv.try_auction_buy(my_id)
	failed += _expect(not bool(buy_own.get("ok", true)), "reject buy own")
	failed += _expect(str(buy_own.get("reason", "")) == "own_listing", "reason own_listing")

	# Cancel returns item
	var qty_before: int = srv.inventory.get_qty("potion_hp_small")
	var cancel1: Dictionary = srv.try_auction_cancel(my_id)
	failed += _expect(bool(cancel1.get("ok", false)), "cancel ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == qty_before + 2, "item returned")
	failed += _expect(srv.auction.find_index(my_id) < 0, "listing gone")

	# Fail: no item
	var bad_item: Dictionary = srv.try_auction_list("potion_hp_small", 99, 10)
	failed += _expect(not bool(bad_item.get("ok", true)), "reject no item")
	failed += _expect(str(bad_item.get("reason", "")) == "no_item", "reason no_item")

	# Fail: bad price
	srv.inventory.add_item("potion_hp_small", 1)
	var bad_price: Dictionary = srv.try_auction_list("potion_hp_small", 1, 0)
	failed += _expect(not bool(bad_price.get("ok", true)), "reject bad price")
	failed += _expect(str(bad_price.get("reason", "")) == "bad_price", "reason bad_price")

	# Fail: no gold on buy
	srv.auction.clear()
	srv._auction_seed_npc_stubs()
	srv.inventory.clear()
	srv.inventory.add_gold(1)
	var nid2 := ""
	var price2 := 0
	for e4 in srv.snapshot_auction().get("listings", []):
		if typeof(e4) == TYPE_DICTIONARY and str(e4.get("seller_id", "")).begins_with("npc_"):
			nid2 = str(e4.get("id", ""))
			price2 = int(e4.get("price_gold", 0))
			if price2 > 1:
				break
	var buy_poor: Dictionary = srv.try_auction_buy(nid2)
	failed += _expect(not bool(buy_poor.get("ok", true)), "reject no gold")
	failed += _expect(str(buy_poor.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(_first_text(buy_poor).find("金币") >= 0, "no gold chinese")

	# Fail: bag full on buy
	srv.auction.clear()
	srv._auction_seed_npc_stubs()
	srv.inventory.clear()
	srv.inventory.add_gold(9999)
	var old_max: int = int(srv.inventory.max_slots)
	srv.inventory.max_slots = 1
	srv.inventory.add_item("potion_mp_small", 1)
	var nid3 := ""
	var iitem := ""
	for e5 in srv.snapshot_auction().get("listings", []):
		if typeof(e5) != TYPE_DICTIONARY:
			continue
		if not str(e5.get("seller_id", "")).begins_with("npc_"):
			continue
		var cand := str(e5.get("item_id", ""))
		if cand != "potion_mp_small":
			nid3 = str(e5.get("id", ""))
			iitem = cand
			break
	if nid3 != "":
		var buy_full: Dictionary = srv.try_auction_buy(nid3)
		failed += _expect(not bool(buy_full.get("ok", true)), "reject bag full")
		failed += _expect(str(buy_full.get("reason", "")) == "bag_full", "reason bag_full")
		failed += _expect(_first_text(buy_full).find("背包") >= 0, "bag full chinese")
	else:
		print("  SKIP bag-full (no suitable stub)")
	srv.inventory.max_slots = old_max

	# Cancel non-owned
	srv.auction.clear()
	srv._auction_seed_npc_stubs()
	var npc_lid := ""
	for e6 in srv.snapshot_auction().get("listings", []):
		if typeof(e6) == TYPE_DICTIONARY and str(e6.get("seller_id", "")).begins_with("npc_"):
			npc_lid = str(e6.get("id", ""))
			break
	var cancel_npc: Dictionary = srv.try_auction_cancel(npc_lid)
	failed += _expect(not bool(cancel_npc.get("ok", true)), "reject cancel npc")
	failed += _expect(str(cancel_npc.get("reason", "")) == "not_owner", "reason not_owner")

	# enter_world-style reset clears player listings, re-seeds stubs
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 3)
	srv.try_auction_list("potion_hp_small", 1, 15)
	var before_clear: int = srv.auction.count()
	failed += _expect(before_clear > 5 or before_clear >= 4, "has player+stubs before clear")
	srv.auction.clear()
	srv._auction_seed_npc_stubs()
	var after: Dictionary = srv.snapshot_auction()
	failed += _expect(int(after.get("count", 0)) >= 3 and int(after.get("count", 0)) <= 5, "reseed stubs only")
	var has_player := false
	for e7 in after.get("listings", []):
		if typeof(e7) == TYPE_DICTIONARY and not str(e7.get("seller_id", "")).begins_with("npc_"):
			has_player = true
	failed += _expect(not has_player, "no player listings after reseed")

	if failed == 0:
		print("test_auction: PASS")
		quit(0)
		return
	print("test_auction: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first_text(result: Dictionary) -> String:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			return str(a.get("text", ""))
	return ""


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
