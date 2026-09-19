extends SceneTree

func _init() -> void:
	var bad := 0
	var RngUtil = load("res://scripts/util/rng_util.gd")
	if RngUtil == null:
		print("FAIL load rng_util"); quit(); return
	if not RngUtil.weighted_pick([]).is_empty():
		print("FAIL empty rows"); bad += 1
	if not RngUtil.weighted_pick([{"id": "z", "weight": 0}]).is_empty():
		print("FAIL zero weight"); bad += 1
	var one: Dictionary = RngUtil.weighted_pick([{"id": "a", "weight": 1.0}])
	if str(one.get("id", "")) != "a":
		print("FAIL single"); bad += 1
	var rows: Array = [{"id": "a", "weight": 1.0}, {"id": "b", "weight": 1.0}]
	var first: Dictionary = RngUtil.weighted_pick(rows, "weight", func() -> float: return 0.0)
	if str(first.get("id", "")) != "a":
		print("FAIL roll 0 -> first"); bad += 1
	var second: Dictionary = RngUtil.weighted_pick(rows, "weight", func() -> float: return 0.6)
	if str(second.get("id", "")) != "b":
		print("FAIL roll 0.6 -> second"); bad += 1
	var Fish = load("res://scripts/net/combat/fish_catalog.gd")
	var Gather = load("res://scripts/net/combat/gather_catalog.gd")
	if Fish == null or Gather == null:
		print("FAIL load catalogs"); bad += 1
	else:
		var f = Fish.new()
		var g = Gather.new()
		f.load_catalog()
		g.load_catalog()
		var fy: Dictionary = f.pick_yield(f.get_spot("fish_pond_a"))
		if fy.is_empty() or str(fy.get("item_id", "")).is_empty():
			print("FAIL fish pick_yield"); bad += 1
		var gy: Dictionary = g.pick_yield(g.get_node("herb_a"))
		if gy.is_empty() or str(gy.get("item_id", "")) != "wild_herb":
			print("FAIL gather pick_yield"); bad += 1
	print("RNG_OK=", bad == 0, " bad=", bad)
	quit()
