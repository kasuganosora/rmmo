extends SceneTree
## Headless: vendor shop buyback — ring list, try_shop_buyback, BoP never enters,
## Chinese msgs, clear on close/map transfer, HUD「回购」tab.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_server()
	failed += _test_hud_source()

	if failed == 0:
		print("test_shop_buyback: PASS")
		quit(0)
	else:
		print("test_shop_buyback: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _has_msg(result: Dictionary, needle: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _has_type(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _test_server() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_shop_buyback: FAIL no MockServer")
		return 1
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.item_catalog == null:
		print("test_shop_buyback: FAIL combat layers missing")
		return 1

	failed += _expect(srv.has_method("try_shop_buyback"), "has try_shop_buyback")
	failed += _expect(srv.has_method("snapshot_shop_buyback"), "has snapshot_shop_buyback")
	failed += _expect(srv.has_method("try_shop_close"), "has try_shop_close")
	var bb_max: int = int(srv.get("BUYBACK_MAX")) if "BUYBACK_MAX" in srv else 0
	# Const may not reflect via get — fall back to script const via source.
	if bb_max <= 0:
		var src := FileAccess.get_file_as_string("res://scripts/net/mock_server.gd")
		var m := RegEx.new()
		m.compile("const BUYBACK_MAX\\s*:=\\s*(\\d+)")
		var mr := m.search(src)
		if mr:
			bb_max = int(mr.get_string(1))
	failed += _expect(bb_max >= 5 and bb_max <= 10, "BUYBACK_MAX in 5–10 (got %d)" % bb_max)

	# --- empty buyback ---
	if srv.has_method("_clear_shop_session_buyback"):
		srv._clear_shop_session_buyback()
	else:
		srv._shop_buyback.clear()
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	var empty_bb: Dictionary = srv.try_shop_buyback(0)
	failed += _expect(not bool(empty_bb.get("ok", true)), "empty buyback fails")
	failed += _expect(_has_msg(empty_bb, "没有可回购的物品。"), "msg 没有可回购的物品")

	# --- sell → list → buyback ---
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.add_item("potion_hp_small", 2)
	var sell: Dictionary = srv.try_shop_sell("potion_hp_small", 2)
	failed += _expect(bool(sell.get("ok", false)), "sell ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 0, "sold out of bag")
	failed += _expect(srv.inventory.get_gold() == 10, "gold +10 (5*2)")
	var listed: Array = srv.snapshot_shop_buyback()
	failed += _expect(listed.size() == 1, "buyback size 1")
	if listed.size() >= 1 and typeof(listed[0]) == TYPE_DICTIONARY:
		var row: Dictionary = listed[0]
		failed += _expect(str(row.get("item_id", "")) == "potion_hp_small", "row item_id")
		failed += _expect(int(row.get("qty", 0)) == 2, "row qty 2")
		failed += _expect(int(row.get("unit_price", 0)) == 5, "unit_price = sell")
		failed += _expect(int(row.get("price", 0)) == 10, "price = sell total")
	failed += _expect(_has_type(sell, "shop_buyback"), "sell emits shop_buyback")

	# insufficient gold
	srv.inventory.add_gold(-srv.inventory.get_gold())  # wipe to 0
	# inventory may not allow negative — force spend down
	while srv.inventory.get_gold() > 0:
		srv.inventory.try_spend_gold(srv.inventory.get_gold())
	failed += _expect(srv.inventory.get_gold() == 0, "gold wiped")
	var no_gold: Dictionary = srv.try_shop_buyback(0)
	failed += _expect(not bool(no_gold.get("ok", true)), "no gold fails")
	failed += _expect(_has_msg(no_gold, "金币不足。"), "msg 金币不足")
	failed += _expect(srv.snapshot_shop_buyback().size() == 1, "list kept on fail")

	# success buyback
	srv.inventory.add_gold(10)
	var ok_bb: Dictionary = srv.try_shop_buyback(0)
	failed += _expect(bool(ok_bb.get("ok", false)), "buyback ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 2, "restored qty 2")
	failed += _expect(srv.inventory.get_gold() == 0, "gold spent to 0")
	failed += _expect(srv.snapshot_shop_buyback().is_empty(), "list cleared after buyback")
	failed += _expect(_has_msg(ok_bb, "已回购：小型生命药水"), "msg 已回购")
	failed += _expect(_has_type(ok_bb, "inventory_update"), "inventory_update")
	failed += _expect(_has_type(ok_bb, "shop_buyback"), "shop_buyback action")

	# --- BoP bound never enters buyback ---
	if srv.has_method("_clear_shop_session_buyback"):
		srv._clear_shop_session_buyback()
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	# bone_necklace is bind-on-pickup
	if srv.inventory.has_method("try_add_item"):
		srv.inventory.try_add_item("bone_necklace", 1, true)
	else:
		srv.inventory.add_item("bone_necklace", 1, true)
	var sell_bop: Dictionary = srv.try_shop_sell("bone_necklace", 1)
	failed += _expect(not bool(sell_bop.get("ok", true)), "BoP sell blocked")
	failed += _expect(_has_msg(sell_bop, "已绑定，无法出售。"), "BoP msg")
	failed += _expect(srv.snapshot_shop_buyback().is_empty(), "BoP not in buyback")
	failed += _expect(srv.inventory.get_qty("bone_necklace") == 1, "BoP still in bag")

	# --- ring buffer overwrites oldest ---
	if srv.has_method("_clear_shop_session_buyback"):
		srv._clear_shop_session_buyback()
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.add_item("slime_jelly", 20)
	srv.inventory.add_item("torn_cloth", 20)
	srv.inventory.add_item("wild_herb", 20)
	# Sell one-at-a-time stacks beyond BUYBACK_MAX
	var sells := 0
	for i in range(bb_max + 3):
		var iid := "slime_jelly" if i % 3 == 0 else ("torn_cloth" if i % 3 == 1 else "wild_herb")
		if srv.inventory.get_qty(iid) < 1:
			break
		var r: Dictionary = srv.try_shop_sell(iid, 1)
		if bool(r.get("ok", false)):
			sells += 1
	failed += _expect(sells >= bb_max, "sold enough for ring (%d)" % sells)
	failed += _expect(srv.snapshot_shop_buyback().size() == bb_max, "ring capped at %d" % bb_max)

	# --- keep buyback on shop close (clear only on map transfer) ---
	failed += _expect(srv.snapshot_shop_buyback().size() > 0, "pre-close has rows")
	var closed: Dictionary = srv.try_shop_close()
	failed += _expect(bool(closed.get("ok", false)), "try_shop_close ok")
	failed += _expect(srv.snapshot_shop_buyback().size() > 0, "kept on close")

	# --- clear on map transfer extras ---
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 1)
	srv.try_shop_sell("potion_hp_small", 1)
	# Close no longer clears the ring — size stays >=1 (may still be capped at BUYBACK_MAX).
	failed += _expect(srv.snapshot_shop_buyback().size() >= 1, "pre-transfer has row")
	if srv.has_method("_transfer_result_extras"):
		srv._transfer_result_extras()
		failed += _expect(srv.snapshot_shop_buyback().is_empty(), "cleared on map transfer")
	elif srv.has_method("_clear_shop_session_buyback"):
		srv._clear_shop_session_buyback()
		failed += _expect(srv.snapshot_shop_buyback().is_empty(), "cleared via helper")

	# snapshot_shop includes buyback
	srv.inventory.add_item("potion_mp_small", 1)
	srv.try_shop_sell("potion_mp_small", 1)
	var snap: Dictionary = srv.snapshot_shop("starter_goods")
	failed += _expect(typeof(snap.get("buyback", null)) == TYPE_ARRAY, "snapshot_shop.buyback")
	failed += _expect((snap.get("buyback", []) as Array).size() >= 1, "snapshot buyback non-empty")

	return failed


func _test_hud_source() -> int:
	var failed := 0
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect(not hud_src.is_empty(), "hud source readable")
	failed += _expect('["回购", "buyback"]' in hud_src or '"回购"' in hud_src, "回购 tab label")
	failed += _expect("BuybackPage" in hud_src, "BuybackPage")
	failed += _expect("func apply_shop_buyback" in hud_src, "apply_shop_buyback")
	failed += _expect("try_shop_buyback" in hud_src or "request_shop_buyback" in hud_src, "buyback request path")
	failed += _expect("try_shop_close" in hud_src or "request_shop_close" in hud_src, "close path exists")
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect("func request_shop_buyback" in world_src, "world request_shop_buyback")
	failed += _expect("func request_shop_close" in world_src, "world request_shop_close")
	return failed
