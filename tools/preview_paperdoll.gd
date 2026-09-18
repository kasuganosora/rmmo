extends SceneTree
## Save male / female / geared standing paperdolls for visual QA.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var Look = load("res://scripts/char/paperdoll_look.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var eq := [
		{"slot": "chest", "item_id": "leather_vest", "name": "皮背心"},
		{"slot": "legs", "item_id": "leather_pants", "name": "皮裤"},
		{"slot": "necklace", "item_id": "bone_necklace", "name": "骨项链"},
	]
	var jobs := [
		["female_bare", {"gender": "female"}, []],
		["male_bare", {"gender": "male"}, []],
		["female_gear", {"gender": "female"}, eq],
		["male_gear", {"gender": "male"}, eq],
	]
	var out_dir := "D:/code/rmmo/_l2_inspect"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for job in jobs:
		var tex: Texture2D = Look.standing_texture(job[1], job[2], cat)
		failed_save(tex, "%s/%s.png" % [out_dir, job[0]])
	print("paperdoll previews in ", out_dir)
	quit(0)


func failed_save(tex: Texture2D, path: String) -> void:
	if tex == null:
		print("FAIL no tex ", path)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("FAIL no image ", path)
		return
	## Upscale nearest so we can actually see 48px cells.
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(path)
	print("saved ", path, " err=", err, " ", img.get_width(), "x", img.get_height())
