extends SceneTree
## Headless: paperdoll standing texture is gender-split and changes with chest gear.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Look = load("res://scripts/char/paperdoll_look.gd")
	failed += _expect(Look != null, "paperdoll_look loads")
	if Look == null:
		_finish(failed)
		return
	var female: Texture2D = Look.standing_texture({"gender": "female", "look_id": "1"}, [])
	var male: Texture2D = Look.standing_texture({"gender": "male", "look_id": "1"}, [])
	failed += _expect(female != null, "female standing tex")
	failed += _expect(male != null, "male standing tex")
	if female != null and male != null:
		var same := false
		if female == male:
			same = true
		else:
			var ia := female.get_image()
			var ib := male.get_image()
			if ia != null and ib != null and ia.get_width() == ib.get_width() and ia.get_height() == ib.get_height():
				same = ia.get_data() == ib.get_data()
		failed += _expect(not same, "male and female paperdoll differ")
	var cat = load("res://scripts/net/combat/item_catalog.gd")
	var catalog = null
	if cat != null:
		catalog = cat.new()
		if catalog.has_method("load_catalog"):
			catalog.load_catalog()
	var eq := [{"slot": "chest", "item_id": "leather_vest", "name": "皮背心"}]
	var parts_empty: Dictionary = Look.equipment_to_mv_parts("female", [], catalog)
	var parts_vest: Dictionary = Look.equipment_to_mv_parts("female", eq, catalog)
	failed += _expect(parts_empty.is_empty(), "no gear -> no mv overlay")
	failed += _expect(parts_vest.has("Clothing1"), "chest vest maps Clothing1")
	var bare: Texture2D = Look.standing_texture({"gender": "female"}, [])
	var geared: Texture2D = Look.standing_texture({"gender": "female"}, eq, catalog)
	if bare != null and geared != null:
		var ia2 := bare.get_image()
		var ib2 := geared.get_image()
		var same2 := false
		if ia2 != null and ib2 != null and ia2.get_width() == ib2.get_width() and ia2.get_height() == ib2.get_height():
			same2 = ia2.get_data() == ib2.get_data()
		failed += _expect(not same2, "chest gear changes standing pixels")
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	if packed != null:
		var hud: Control = packed.instantiate()
		root.add_child(hud)
		await process_frame
		hud._character = {"name": "Demo", "gender": "female", "class_id": "adventurer", "level": 3}
		hud._server_equipment = eq
		hud._fill_window("character")
		await process_frame
		var sil := hud._windows["character"].find_child("Silhouette", true, false) as TextureRect
		failed += _expect(sil != null and sil.texture != null, "HUD silhouette uses live texture")
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_paperdoll_look: ALL PASS")
		quit(0)
	else:
		print("test_paperdoll_look: FAIL count=", failed)
		quit(1)
