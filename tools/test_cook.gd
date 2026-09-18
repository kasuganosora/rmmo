extends SceneTree
## Headless: cooking recipes via try_craft (grilled fish / herb soup / fish feast).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_cook: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("recipe_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_craft"), "has try_craft")
	failed += _expect(srv.get("recipe_catalog") != null, "recipe_catalog loaded")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_grilled_fish"), "item food_grilled_fish")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_herb_soup"), "item food_herb_soup")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_fish_feast"), "item food_fish_feast")
	failed += _expect(srv.recipe_catalog.has_recipe("cook_grilled_fish"), "recipe cook_grilled_fish")
	failed += _expect(srv.recipe_catalog.has_recipe("cook_herb_soup"), "recipe cook_herb_soup")
	failed += _expect(srv.recipe_catalog.has_recipe("cook_fish_feast"), "recipe cook_fish_feast")

	# grilled fish: fish_small×1 → food_grilled_fish (gold 1)
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("fish_small", 1)
	var g: Dictionary = srv.try_craft("cook_grilled_fish", 1)
	failed += _expect(bool(g.get("ok", false)), "cook grilled fish ok")
	failed += _expect(srv.inventory.get_qty("fish_small") == 0, "fish_small consumed")
	failed += _expect(srv.inventory.get_qty("food_grilled_fish") == 1, "grilled fish granted")
	failed += _expect(srv.inventory.get_gold() == 49, "grilled gold cost 1")

	# herb soup: wild_herb×1 + fish_small×1 → food_herb_soup (gold 2)
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("wild_herb", 1)
	srv.inventory.add_item("fish_small", 1)
	var s: Dictionary = srv.try_craft("cook_herb_soup", 1)
	failed += _expect(bool(s.get("ok", false)), "cook herb soup ok")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 0, "herb consumed")
	failed += _expect(srv.inventory.get_qty("fish_small") == 0, "soup fish consumed")
	failed += _expect(srv.inventory.get_qty("food_herb_soup") == 1, "herb soup granted")
	failed += _expect(srv.inventory.get_gold() == 48, "soup gold cost 2")

	# shiny grill: fish_shiny×1 → food_fish_feast (gold 3)
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("fish_shiny", 1)
	var f: Dictionary = srv.try_craft("cook_fish_feast", 1)
	failed += _expect(bool(f.get("ok", false)), "cook fish feast ok")
	failed += _expect(srv.inventory.get_qty("fish_shiny") == 0, "shiny consumed")
	failed += _expect(srv.inventory.get_qty("food_fish_feast") == 1, "feast granted")
	failed += _expect(srv.inventory.get_gold() == 47, "feast gold cost 3")

	# existing potion recipe still works
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv.inventory.add_item("wild_herb", 2)
	var p: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(bool(p.get("ok", false)), "existing craft_hp_potion ok")

	# missing mats for cook
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	var miss: Dictionary = srv.try_craft("cook_grilled_fish", 1)
	failed += _expect(not bool(miss.get("ok", true)), "cook missing mats fails")
	failed += _expect(str(miss.get("reason", "")) == "missing_mats", "reason missing_mats")

	if failed == 0:
		print("test_cook: PASS")
		quit(0)
		return
	print("test_cook: FAIL count=%d" % failed)
	quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
