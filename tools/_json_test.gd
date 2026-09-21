extends SceneTree

func _init() -> void:
	var bad := 0
	var JsonUtil = load("res://scripts/util/json_util.gd")
	if JsonUtil == null:
		print("FAIL load json_util"); quit(); return
	if JsonUtil.parse_data("combat/items.json") == null:
		print("FAIL parse_data items.json"); bad += 1
	if typeof(JsonUtil.parse_file("res://no/such.json")) != TYPE_NIL:
		print("FAIL parse_file missing"); bad += 1
	var first: Variant = JsonUtil.load_first([
		"res://no/such.json",
		"combat/items.json",
	])
	if typeof(first) != TYPE_DICTIONARY:
		print("FAIL load_first skip-missing"); bad += 1
	elif not (first as Dictionary).has("items"):
		print("FAIL load_first items key"); bad += 1
	if JsonUtil.load_first(["res://no/such.json"]) != null:
		print("FAIL load_first all-missing"); bad += 1
	# Remaining catalogs still load via JsonUtil.
	for path in [
		"res://scripts/net/combat/loot_catalog.gd",
		"res://scripts/net/combat/shop_catalog.gd",
		"res://scripts/net/combat/safe_zone_catalog.gd",
		"res://scripts/net/combat/quest_journal.gd",
	]:
		var sc = load(path)
		if sc == null:
			print("FAIL load ", path.get_file()); bad += 1; continue
		var c = sc.new()
		c.load_catalog()
		var empty := false
		if path.ends_with("loot_catalog.gd"):
			empty = c.get_entries("", "").is_empty()
		elif path.ends_with("shop_catalog.gd"):
			empty = c.all_ids().is_empty()
		elif path.ends_with("safe_zone_catalog.gd"):
			empty = c.zones_for_map("demo_map").is_empty()
		elif path.ends_with("quest_journal.gd"):
			empty = not c._catalog.has("starter_step")
		if empty:
			print("FAIL ", path.get_file(), " empty after load"); bad += 1
			continue
		print("OK    ", path.get_file())
	print("JSON_OK=", bad == 0, " bad=", bad)
	quit()
