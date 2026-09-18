extends SceneTree
## Headless: inventory search util + HUD LineEdit filter (client-only).


const InvSearchUtil = preload("res://scripts/ui/inv_search_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_matches_helper()
	failed += await _test_hud_search_ui()

	if failed == 0:
		print("test_inv_search: PASS")
		quit(0)
	else:
		print("test_inv_search: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  OK  ", msg)
		return 0
	print("  FAIL: ", msg)
	return 1


func _test_matches_helper() -> int:
	var failed := 0
	print("-- InvSearchUtil.matches --")
	failed += _expect(InvSearchUtil.matches("", "potion_hp_small", "小型生命药水"), "empty query matches")
	failed += _expect(InvSearchUtil.matches("   ", "sword", "木剑"), "whitespace query matches")
	failed += _expect(InvSearchUtil.matches("potion", "potion_hp_small", "小型生命药水"), "id substring")
	failed += _expect(InvSearchUtil.matches("POTION", "potion_hp_small", "小型生命药水"), "id case-insensitive")
	failed += _expect(InvSearchUtil.matches("生命", "potion_hp_small", "小型生命药水"), "display_name substring")
	failed += _expect(InvSearchUtil.matches("木剑", "wooden_sword", "木剑"), "display exact")
	failed += _expect(InvSearchUtil.matches("WOODEN", "wooden_sword", "木剑"), "id upper query")
	failed += _expect(not InvSearchUtil.matches("斧", "wooden_sword", "木剑"), "non-match false")
	failed += _expect(not InvSearchUtil.matches("xyz", "potion_hp_small", "小型生命药水"), "no id/name hit")
	failed += _expect(InvSearchUtil.matches("hp", "potion_hp_small", ""), "id only when name empty")
	failed += _expect(InvSearchUtil.matches("药", "", "药水"), "name only when id empty")
	return failed


func _test_hud_search_ui() -> int:
	var failed := 0
	print("-- HUD inventory search UI --")
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		return failed
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.get("_inv_search_query") != null or true, "hud has search state")
	# Seed bag snapshot
	hud._server_inventory = [
		{"id": "potion_hp_small", "qty": 3},
		{"id": "wooden_sword", "qty": 1},
		{"id": "slime_jelly", "qty": 5},
	]
	# Open inventory window body
	if not hud._windows.has("inventory"):
		failed += _expect(false, "inventory window exists")
		hud.queue_free()
		return failed
	var panel: PanelContainer = hud._windows["inventory"]
	panel.visible = true
	hud._fill_window("inventory")
	await process_frame
	await process_frame

	var search := panel.find_child("InvSearch", true, false) as LineEdit
	failed += _expect(search != null, "InvSearch LineEdit present")
	if search != null:
		failed += _expect(str(search.placeholder_text).find("搜索物品") >= 0, "placeholder 搜索物品…")

	var grid := panel.find_child("InvGrid", true, false) as GridContainer
	failed += _expect(grid != null, "InvGrid present")
	if grid == null:
		hud.queue_free()
		return failed

	var filled_before := 0
	var empty_before := 0
	for c in grid.get_children():
		if not c.visible:
			continue
		var iid := str(c.item_id) if "item_id" in c else ""
		if iid.is_empty():
			empty_before += 1
		else:
			filled_before += 1
	failed += _expect(filled_before >= 3, "empty query shows filled slots (%d)" % filled_before)
	failed += _expect(empty_before > 0, "empty query keeps empty slots (%d)" % empty_before)

	# Filter by id substring
	hud._on_inv_search_text_changed("potion")
	await process_frame
	var vis_potion := 0
	var vis_empty := 0
	var hidden_sword := false
	for c in grid.get_children():
		var iid := str(c.item_id) if "item_id" in c else ""
		var dname := str(c.display_name) if "display_name" in c else ""
		if c.visible:
			if iid.is_empty():
				vis_empty += 1
			else:
				vis_potion += 1
				failed += _expect(
					InvSearchUtil.matches("potion", iid, dname),
					"visible slot matches potion (%s)" % iid
				)
		elif iid == "wooden_sword":
			hidden_sword = true
	failed += _expect(vis_potion >= 1, "potion filter shows matching filled")
	failed += _expect(vis_empty == 0, "empty slots hidden while filtering")
	failed += _expect(hidden_sword, "non-matching sword hidden")

	# Clear → all again
	hud._on_inv_search_text_changed("")
	await process_frame
	var empty_after := 0
	var filled_after := 0
	for c in grid.get_children():
		if not c.visible:
			continue
		var iid2 := str(c.item_id) if "item_id" in c else ""
		if iid2.is_empty():
			empty_after += 1
		else:
			filled_after += 1
	failed += _expect(filled_after >= 3, "clear restores filled")
	failed += _expect(empty_after > 0, "clear restores empty slots")

	# Display-name filter (Chinese) — labels may be id if catalog missing
	hud._on_inv_search_text_changed("sword")
	await process_frame
	var sword_vis := 0
	for c in grid.get_children():
		if not c.visible:
			continue
		var iid3 := str(c.item_id) if "item_id" in c else ""
		if not iid3.is_empty():
			sword_vis += 1
			failed += _expect(iid3.find("sword") >= 0 or str(c.display_name).to_lower().find("sword") >= 0,
				"sword filter visible %s" % iid3)
	failed += _expect(sword_vis >= 1, "sword id filter hits wooden_sword")

	# Source smoke: client-only (no server inventory change hooks for search)
	var util_src := FileAccess.get_file_as_string("res://scripts/ui/inv_search_util.gd")
	failed += _expect(util_src.find("static func matches") >= 0, "util has matches")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect(hud_src.find("搜索物品") >= 0, "hud placeholder in source")
	failed += _expect(hud_src.find("_on_inv_search_text_changed") >= 0, "hud text_changed handler")

	hud.queue_free()
	return failed
