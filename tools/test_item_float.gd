extends SceneTree
## Headless: item-gain floats 「获得：野草 ×2」 + coalesce + cap + inventory delta wiring.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		_finish(failed)
		return

	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("show_item_gain_float"), "show_item_gain_float API")
	failed += _expect(hud.has_method("hide_item_gain_floats"), "hide_item_gain_floats API")
	failed += _expect(hud.has_method("is_item_gain_float_visible"), "is_item_gain_float_visible API")
	failed += _expect(hud.has_method("get_item_gain_float_texts"), "get_item_gain_float_texts API")
	failed += _expect(hud.has_method("get_item_gain_float_count"), "get_item_gain_float_count API")
	failed += _expect(hud.has_method("get_item_gain_float_qty"), "get_item_gain_float_qty API")

	hud.show_item_gain_float("wild_herb", 2, "野草")
	await process_frame
	failed += _expect(hud.is_item_gain_float_visible(), "visible after show")
	failed += _expect(hud.get_item_gain_float_count() == 1, "one line")
	var texts0: Array = hud.get_item_gain_float_texts()
	failed += _expect(texts0.size() == 1, "one text")
	if texts0.size() >= 1:
		var t0 := str(texts0[0])
		failed += _expect(t0.find("获得") >= 0, "Chinese 获得 in float")
		failed += _expect(t0.find("野草") >= 0, "野草 in float")
		failed += _expect(t0.find("×2") >= 0 or t0.find("x2") >= 0, "×2 in float")
	failed += _expect(hud.get_item_gain_float_qty("wild_herb") == 2, "qty 2")

	var host: Control = hud.get_node_or_null("ItemGainFloats")
	failed += _expect(host != null, "ItemGainFloats node exists")
	if host != null:
		failed += _expect(host.mouse_filter == Control.MOUSE_FILTER_IGNORE, "host mouse_filter IGNORE")

	# Coalesce same item id
	hud.show_item_gain_float("wild_herb", 3, "野草")
	await process_frame
	failed += _expect(hud.get_item_gain_float_count() == 1, "still one line after coalesce")
	failed += _expect(hud.get_item_gain_float_qty("wild_herb") == 5, "coalesce 2+3=5")
	var texts1: Array = hud.get_item_gain_float_texts()
	if texts1.size() >= 1:
		failed += _expect(str(texts1[0]).find("×5") >= 0, "text shows ×5")

	# Second distinct item
	hud.show_item_gain_float("iron_ore", 1, "铁矿")
	await process_frame
	failed += _expect(hud.get_item_gain_float_count() == 2, "two concurrent lines")

	# Cap at 3
	hud.show_item_gain_float("fish_raw", 4, "生鱼")
	hud.show_item_gain_float("scrap_metal", 1, "废铁")  # should be dropped by cap
	await process_frame
	failed += _expect(hud.get_item_gain_float_count() == 3, "capped at 3 lines")
	failed += _expect(hud.get_item_gain_float_qty("scrap_metal") == 0, "4th unique ignored by cap")
	# Coalesce still works while at cap
	hud.show_item_gain_float("iron_ore", 2, "铁矿")
	await process_frame
	failed += _expect(hud.get_item_gain_float_qty("iron_ore") == 3, "coalesce at cap 1+2=3")
	failed += _expect(hud.get_item_gain_float_count() == 3, "still 3 after coalesce")

	hud.hide_item_gain_floats()
	await process_frame
	failed += _expect(not hud.is_item_gain_float_visible(), "hidden after hide")
	failed += _expect(hud.get_item_gain_float_count() == 0, "count cleared")

	# Ignore non-positive / empty
	hud.show_item_gain_float("wild_herb", 0, "野草")
	hud.show_item_gain_float("wild_herb", -2, "野草")
	hud.show_item_gain_float("", 5, "空")
	await process_frame
	failed += _expect(not hud.is_item_gain_float_visible(), "no show for <=0 or empty id")

	# Auto-hide after ~1.2s
	hud.show_item_gain_float("wild_herb", 1, "野草")
	await process_frame
	if hud.has_method("_tick_item_floats"):
		hud._tick_item_floats(1.25)
	else:
		hud._process(1.25)
	await process_frame
	failed += _expect(not hud.is_item_gain_float_visible(), "auto-hide after ~1.2s")

	# Independent of gold/exp floats
	hud.show_exp_gain_float(10)
	hud.show_gold_gain_float(25)
	hud.show_item_gain_float("wild_herb", 2, "野草")
	await process_frame
	failed += _expect(hud.is_exp_gain_float_visible(), "exp float independent")
	failed += _expect(hud.is_gold_gain_float_visible(), "gold float independent")
	failed += _expect(hud.is_item_gain_float_visible(), "item float alongside")

	# inventory_update path: seed then gain via apply_inventory_snapshot
	hud.hide_item_gain_floats()
	hud.hide_gold_gain_float()
	hud.hide_exp_gain_float()
	hud.apply_inventory_snapshot([{"id": "wild_herb", "qty": 1}], 0)  # seed — no float
	await process_frame
	failed += _expect(not hud.is_item_gain_float_visible(), "seed snapshot no float")
	hud.apply_inventory_snapshot([{"id": "wild_herb", "qty": 3}], 0)  # +2
	await process_frame
	failed += _expect(hud.is_item_gain_float_visible(), "gain after seed shows float")
	failed += _expect(hud.get_item_gain_float_qty("wild_herb") == 2, "delta 2 from inventory")
	var texts2: Array = hud.get_item_gain_float_texts()
	if texts2.size() >= 1:
		failed += _expect(str(texts2[0]).find("获得") >= 0, "inventory path 获得")
		failed += _expect(str(texts2[0]).find("×2") >= 0, "inventory path ×2")

	# Removals ignored
	hud.hide_item_gain_floats()
	hud.apply_inventory_snapshot([{"id": "wild_herb", "qty": 1}], 0)
	await process_frame
	failed += _expect(not hud.is_item_gain_float_visible(), "decrease ignored")

	# New item id counts as full qty gain
	hud.apply_inventory_snapshot([{"id": "wild_herb", "qty": 1}, {"id": "iron_ore", "qty": 4}], 0)
	await process_frame
	failed += _expect(hud.get_item_gain_float_qty("iron_ore") == 4, "new item full qty")

	# loot_all style: many gains, capped
	hud.hide_item_gain_floats()
	hud.apply_inventory_snapshot([
		{"id": "a", "qty": 1},
		{"id": "b", "qty": 5},
		{"id": "c", "qty": 3},
		{"id": "d", "qty": 2},
		{"id": "e", "qty": 9},
	], 0)
	await process_frame
	failed += _expect(hud.get_item_gain_float_count() <= 3, "loot_all capped <=3")
	# Largest stacks preferred (e=9, b=5, c=3)
	failed += _expect(hud.get_item_gain_float_qty("e") == 9, "largest e kept")
	failed += _expect(hud.get_item_gain_float_qty("b") == 5, "b kept")
	failed += _expect(hud.get_item_gain_float_qty("c") == 3, "c kept")
	failed += _expect(hud.get_item_gain_float_qty("a") == 0, "small a dropped by cap")

	# Settings flag present
	var gs_src := FileAccess.get_file_as_string("res://scripts/game/game_settings.gd")
	failed += _expect(gs_src.find("show_item_floats") >= 0, "settings show_item_floats")

	# World routes inventory_update → apply_inventory_snapshot
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find("apply_inventory_snapshot") >= 0, "world calls apply_inventory_snapshot")

	hud.queue_free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
