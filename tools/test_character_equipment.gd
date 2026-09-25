extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
const Starter = preload("res://scripts/char/starter_equipment.gd")
const Paperdoll = preload("res://scripts/char/paperdoll_look.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for path in ["res://scripts/game/player.gd", "res://scripts/game/application/action_apply.gd", "res://scripts/net/server/session_module.gd"]:
		assert(load(path).can_instantiate(), path)
	var review := Image.create(576,384,false,Image.FORMAT_RGBA8)
	review.fill(Color("252936"))
	var type_idx := 0
	var catalog = load("res://scripts/net/combat/item_catalog.gd").new()
	catalog.load_catalog()
	var bag = load("res://scripts/net/combat/inventory.gd").new()
	bag.set_catalog(catalog)
	var equipment = load("res://scripts/net/combat/equipment.gd").new()
	equipment.set_catalog(catalog)
	equipment.clear()
	for item in Starter.ITEMS:
		assert(bag.add_item(item.id,1) == 1)
		var result: Dictionary = equipment.try_equip_from_bag(bag,item.id)
		assert(result.get("ok",false),str(result))
		assert(equipment.get_item_in(item.equip_slot) == item.id)
	for gender in ["male","female","young_male","young_female"]:
		var parts := MV.default_parts(gender)
		assert(parts.has("Body"))
		for cat in MV.EQUIPMENT_CATS:
			assert(not parts.has(cat))
		var overlays := Paperdoll.equipment_to_mv_parts(gender,equipment.snapshot(),catalog)
		assert(overlays == Starter.PARTS)
		var original: Image = MV._render("Motion",gender,parts)
		review.blend_rect(original,Rect2i(0,0,96,96),Vector2i(0,type_idx*96))
		var dressed := MV.compose_frames(gender,MV.apply_equipment(parts,overlays))
		var full: Image = MV._render("Motion",gender,MV.apply_equipment(parts,overlays))
		review.blend_rect(full,Rect2i(0,0,96,96),Vector2i(480,type_idx*96))
		for action in MV.ACTIONS:
			for direction in MV.DIRECTIONS:
				var name: String = action + "_" + direction
				assert(dressed.has_animation(name),name)
				assert(dressed.get_frame_count(name) == (1 if action == "idle" else 4))
		var cat_idx := 1
		for cat in Starter.PARTS:
			var single := MV.apply_equipment(parts,{cat:1})
			var image: Image = MV._render("Motion",gender,single)
			assert(image.get_data() != original.get_data(),gender+cat)
			review.blend_rect(image,Rect2i(0,0,96,96),Vector2i(cat_idx*96,type_idx*96))
			cat_idx += 1
			var undressed: Image = MV._render("Motion",gender,MV.apply_equipment(single,{cat:null}))
			assert(undressed.get_data() == original.get_data(),"Unequip did not restore body")
		print("PASS ",gender,": 64 animations, four independently removable garments")
		type_idx += 1
	for item in Starter.ITEMS:
		var result: Dictionary = equipment.try_unequip_to_bag(bag,item.equip_slot)
		assert(result.get("ok",false),str(result))
		assert(equipment.is_empty(item.equip_slot))
	assert(Paperdoll.equipment_to_mv_parts("male",equipment.snapshot(),catalog).is_empty())
	print("PASS inventory -> equipment -> inventory; body remains unchanged")
	review.resize(1728,1152,Image.INTERPOLATE_NEAREST)
	review.save_png(ArtPaths.path("character_creator/layer_separation_review.png"))
	quit()
