extends SceneTree
## Headless: vendor reputation — buy/sell gain, discount tiers, snapshot_shop, HUD 声望.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_server()
	failed += await _test_hud()

	if failed == 0:
		print("test_vendor_rep: PASS")
		quit(0)
	else:
		print("test_vendor_rep: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _has_msg(actions: Array, needle: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _find_type(actions: Array, t: String) -> Dictionary:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return a
	return {}


func _listing_price(listings: Array, item_id: String) -> int:
	for row in listings:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("item_id", "")) == item_id:
			return int(row.get("buy_price", -1))
	return -1


func _test_server() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_vendor_rep: FAIL no MockServer")
		return 1
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.shop_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("snapshot_shop"), "has snapshot_shop")
	failed += _expect(srv.has_method("get_vendor_rep"), "has get_vendor_rep")
	failed += _expect(srv.has_method("set_vendor_rep"), "has set_vendor_rep")
	failed += _expect(srv.has_method("try_shop_buy"), "has try_shop_buy")
	failed += _expect("vendor_rep" in srv, "vendor_rep property")

	srv.set_vendor_rep("starter_goods", 0)
	failed += _expect(int(srv.vendor_rep) == 0, "default vendor_rep 0")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 0, "get 0")

	var snap0: Dictionary = srv.snapshot_shop("starter_goods")
	failed += _expect(int(snap0.get("vendor_rep", -1)) == 0, "snapshot rep 0")
	failed += _expect(int(snap0.get("discount_pct", -1)) == 0, "discount 0 at rep0")
	failed += _expect(_listing_price(snap0.get("listings", []), "potion_hp_small") == 10, "potion 10 at rep0")

	# Discount tiers (force rep)
	srv.set_vendor_rep("starter_goods", 100)
	var snap100: Dictionary = srv.snapshot_shop("starter_goods")
	failed += _expect(int(snap100.get("discount_pct", -1)) == 5, "5% at 100")
	failed += _expect(_listing_price(snap100.get("listings", []), "potion_hp_small") == 9, "potion 9 at 5%")

	srv.set_vendor_rep("starter_goods", 300)
	var snap300: Dictionary = srv.snapshot_shop("starter_goods")
	failed += _expect(int(snap300.get("discount_pct", -1)) == 10, "10% at 300")
	failed += _expect(_listing_price(snap300.get("listings", []), "potion_hp_small") == 9, "potion 9 at 10%")

	srv.set_vendor_rep("starter_goods", 600)
	var snap600: Dictionary = srv.snapshot_shop("starter_goods")
	failed += _expect(int(snap600.get("discount_pct", -1)) == 15, "15% at 600")
	failed += _expect(_listing_price(snap600.get("listings", []), "potion_hp_small") == 8, "potion 8 at 15%")

	# Floor gold >= 1
	failed += _expect(srv._discounted_buy_price(1, 15) == 1, "floor price 1")

	# Buy: +1 rep per purchase, discounted spend
	srv.set_vendor_rep("starter_goods", 0)
	srv.inventory.clear()
	srv.inventory.add_gold(500)
	var gold_before: int = srv.inventory.get_gold()
	var buy: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(bool(buy.get("ok", false)), "buy ok")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 1, "rep +1 after buy")
	failed += _expect(srv.inventory.get_gold() == gold_before - 10, "paid base 10 at rep0")
	failed += _expect(not _has_msg(buy.get("actions", []), "声望提升"), "no threshold msg at 1")

	# Qty 3 still +1 (per purchase)
	var buy3: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 3)
	failed += _expect(bool(buy3.get("ok", false)), "buy qty3 ok")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 2, "rep +1 for multi qty")

	# Cross 100 → 声望提升 + 5% next buy
	srv.set_vendor_rep("starter_goods", 99)
	var gold99: int = srv.inventory.get_gold()
	var cross: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(bool(cross.get("ok", false)), "cross buy ok")
	# Paid at rep 99 → still 0% for this purchase
	failed += _expect(srv.inventory.get_gold() == gold99 - 10, "paid 10 before threshold applies")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 100, "rep 100")
	failed += _expect(_has_msg(cross.get("actions", []), "声望提升"), "threshold msg at 100")
	var open_a: Dictionary = _find_type(cross.get("actions", []), "open_shop")
	failed += _expect(int(open_a.get("vendor_rep", -1)) == 100, "open_shop vendor_rep 100")
	failed += _expect(_listing_price(open_a.get("listings", []), "potion_hp_small") == 9, "listings 5% after cross")

	# Next buy uses 5%
	var gold100: int = srv.inventory.get_gold()
	var buy_disc: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(bool(buy_disc.get("ok", false)), "discounted buy ok")
	failed += _expect(srv.inventory.get_gold() == gold100 - 9, "paid 9 at 5%")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 101, "rep 101")

	# Cross 300 / 600 messages
	srv.set_vendor_rep("starter_goods", 299)
	var c300: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(_has_msg(c300.get("actions", []), "声望提升"), "msg at 300")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 300, "rep 300")

	srv.set_vendor_rep("starter_goods", 599)
	var c600: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(_has_msg(c600.get("actions", []), "声望提升"), "msg at 600")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 600, "rep 600")

	# Cap 1000
	srv.set_vendor_rep("starter_goods", 1000)
	var gold_cap: int = srv.inventory.get_gold()
	var buy_cap: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(bool(buy_cap.get("ok", false)), "buy at cap ok")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 1000, "rep capped 1000")
	failed += _expect(srv.inventory.get_gold() == gold_cap - 8, "15% at cap (8)")

	# Sell +1 when shop active
	srv.set_vendor_rep("starter_goods", 50)
	srv._try_open_shop_action("starter_goods")
	srv.inventory.add_item("slime_jelly", 2)
	var sell: Dictionary = srv.try_shop_sell("slime_jelly", 1)
	failed += _expect(bool(sell.get("ok", false)), "sell ok")
	failed += _expect(srv.get_vendor_rep("starter_goods") == 51, "sell +1 rep")

	# Open shop payload includes vendor_rep
	srv.set_vendor_rep("starter_goods", 42)
	var opened: Dictionary = srv._try_open_shop_action("starter_goods")
	failed += _expect(bool(opened.get("ok", false)), "open ok")
	var oa: Dictionary = _find_type(opened.get("actions", []), "open_shop")
	failed += _expect(int(oa.get("vendor_rep", -1)) == 42, "open vendor_rep 42")

	return failed


func _test_hud() -> int:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	if packed == null:
		# Fallback path used by other tests
		packed = load("res://scenes/game_hud.tscn")
	if packed == null:
		failed += _expect(false, "game_hud.tscn loads")
		return failed
	failed += _expect(true, "game_hud.tscn loads")
	var hud: Node = packed.instantiate()
	root.add_child(hud)
	await process_frame
	failed += _expect(hud.has_method("show_shop"), "show_shop API")
	hud.show_shop("starter_goods", "杂货商人", [
		{"item_id": "potion_hp_small", "name": "小红药", "buy_price": 9, "sell_price": 5},
	], 100, 100)
	await process_frame
	var title_l: Label = hud.find_child("ShopTitle", true, false) as Label
	var rep_l: Label = hud.find_child("ShopRep", true, false) as Label
	var footer: Label = hud.find_child("ShopRepFooter", true, false) as Label
	var title_ok := title_l != null and str(title_l.text).find("声望 100") >= 0
	var rep_ok := rep_l != null and str(rep_l.text).find("声望 100") >= 0
	var foot_ok := footer != null and str(footer.text).find("声望 100") >= 0
	failed += _expect(title_ok or rep_ok or foot_ok, "HUD shows 声望 100")
	if title_l != null:
		failed += _expect(str(title_l.text).find("声望") >= 0, "title has 声望")
	hud.queue_free()
	await process_frame
	return failed
