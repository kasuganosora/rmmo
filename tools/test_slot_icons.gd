extends SceneTree
## Headless: MV IconSet crop + standalone content://icon file + InvSlot TextureRect.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload")
	if am == null:
		_finish(failed)
		return

	var root_path: String = str(am.content_root())
	print("content_root=", root_path)
	failed += _expect(root_path != "", "content_root non-empty")
	# Prefer runtime fallback on CI box.
	failed += _expect(
		root_path.find("rmmo_runtime") >= 0 or root_path.find("user://") >= 0 or root_path.find("content") >= 0,
		"content_root looks sane"
	)

	DirAccess.make_dir_recursive_absolute("%s/assets/system" % root_path)
	DirAccess.make_dir_recursive_absolute("%s/assets/icon" % root_path)

	var atlas_path := "%s/assets/system/IconSet.png" % root_path
	if not FileAccess.file_exists(atlas_path):
		_write_test_iconset(atlas_path)
		print("wrote test IconSet at ", atlas_path)
	failed += _expect(FileAccess.file_exists(atlas_path), "IconSet.png exists")

	# path() for system atlas
	var sys_ref := "content://system/IconSet"
	var resolved: String = str(am.path(sys_ref))
	print("IconSet path=", resolved)
	failed += _expect(resolved.ends_with("IconSet.png") or resolved.ends_with("IconSet"), "path ends with IconSet(.png)")
	failed += _expect(bool(am.has(sys_ref)), "has content://system/IconSet")

	# MV crop: index 32 = col 0 row 2
	var crop: Image = am.load_mv_icon(32)
	failed += _expect(crop != null, "load_mv_icon(32) non-null")
	if crop != null:
		failed += _expect(crop.get_width() == 32 and crop.get_height() == 32, "crop 32x32")
		# Test atlas paints index 32 as pure red-ish
		var px: Color = crop.get_pixel(16, 16)
		failed += _expect(px.r > 0.8 and px.g < 0.3, "index 32 center is red")

	var tex: ImageTexture = am.load_mv_icon_texture(32)
	failed += _expect(tex != null and tex.get_width() == 32, "load_mv_icon_texture")

	# Standalone file icon
	var file_id := "potion_hp_small"
	var file_path := "%s/assets/icon/%s.png" % [root_path, file_id]
	if not FileAccess.file_exists(file_path):
		_write_solid_png(file_path, Color(0.1, 0.85, 0.2, 1.0))
		print("wrote standalone icon ", file_path)
	var file_ref := "content://icon/%s" % file_id
	var fpath: String = str(am.path(file_ref))
	print("icon file path=", fpath)
	failed += _expect(fpath.ends_with("%s.png" % file_id) or fpath.ends_with(file_id), "icon path has id.png")
	failed += _expect(bool(am.has(file_ref)), "has content://icon/potion_hp_small")
	var fimg: Image = am.load_image(file_ref)
	failed += _expect(fimg != null and fimg.get_width() == 32, "load_image standalone icon")

	# resolve_slot_icon_texture: index wins over file
	var t1: ImageTexture = am.resolve_slot_icon_texture(32, file_id)
	failed += _expect(t1 != null, "resolve prefers atlas when index>=0")
	# file-only path
	var t2: ImageTexture = am.resolve_slot_icon_texture(-1, file_id)
	failed += _expect(t2 != null, "resolve file when index=-1")
	# miss → null
	var t3: ImageTexture = am.resolve_slot_icon_texture(-1, "")
	failed += _expect(t3 == null, "resolve miss → null")

	# Catalog fields
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var def: Dictionary = cat.get_item("potion_hp_small")
	failed += _expect(int(def.get("icon_index", -1)) == 32, "item icon_index 32")
	failed += _expect(str(def.get("icon", "")) == "potion_hp_small", "item icon id")
	failed += _expect(str(def.get("icon_ref", "")).begins_with("content://icon/"), "item icon_ref")

	var SkillCatalog = load("res://scripts/net/combat/skill_catalog.gd")
	var scat = SkillCatalog.new()
	scat.load_catalog()
	var sdef: Dictionary = scat.get_skill("basic_attack")
	failed += _expect(int(sdef.get("icon_index", -1)) == 76, "skill icon_index 76")

	# InvSlot shows TextureRect when atlas present
	var InvSlot = load("res://scripts/ui/inv_slot.gd")
	var host := Control.new()
	root.add_child(host)
	var cell := PanelContainer.new()
	cell.set_script(InvSlot)
	host.add_child(cell)
	await process_frame
	cell.setup("potion_hp_small", 3, "小型生命药水", 0, 32, "")
	await process_frame
	var icon_node = cell.get_node_or_null("Inner/Icon")
	failed += _expect(icon_node != null, "InvSlot has Icon TextureRect")
	if icon_node != null:
		failed += _expect(icon_node.visible == true, "Icon visible with atlas")
		failed += _expect(icon_node.texture != null, "Icon has texture")
	var avatar = cell.get_node_or_null("Inner/Avatar")
	if avatar != null:
		failed += _expect(avatar.visible == false, "letter hidden when icon shown")

	# File-only: icon_index -1
	cell.setup("potion_hp_small", 1, "小型生命药水", 1, -1, "content://icon/potion_hp_small")
	await process_frame
	if icon_node != null:
		failed += _expect(icon_node.visible == true and icon_node.texture != null, "file icon shown")

	# Miss → letter
	cell.setup("no_such_item", 1, "无图标", 2, -1, "")
	await process_frame
	if icon_node != null:
		failed += _expect(icon_node.visible == false, "icon hidden on miss")
	if avatar != null:
		failed += _expect(avatar.visible == true and str(avatar.text) != "", "letter on miss")

	# Drag preview helper: TextureRect child when atlas exists
	failed += _expect(am.has_method("make_drag_preview"), "AssetManager.make_drag_preview")
	if am.has_method("make_drag_preview"):
		var prev: Control = am.make_drag_preview("小型生命药水", 32, "", Vector2(40, 40))
		failed += _expect(prev != null, "drag preview non-null")
		if prev != null:
			var prev_icon = prev.get_node_or_null("Icon")
			failed += _expect(prev_icon != null and prev_icon is TextureRect, "drag preview has TextureRect Icon")
			if prev_icon != null:
				failed += _expect(prev_icon.texture != null, "drag preview Icon has texture")
			var prev_letter = prev.get_node_or_null("Letter")
			failed += _expect(prev_letter == null, "drag preview no Letter when atlas ok")
			prev.queue_free()
		# Miss → Letter child
		var prev2: Control = am.make_drag_preview("无图标", -1, "", Vector2(40, 40))
		if prev2 != null:
			var pl = prev2.get_node_or_null("Letter")
			failed += _expect(pl != null and pl is Label, "drag preview Letter on miss")
			prev2.queue_free()

	# IconPreview static wrapper
	var IconPreview = load("res://scripts/ui/icon_preview.gd")
	failed += _expect(IconPreview != null, "icon_preview.gd loads")
	if IconPreview != null:
		var wrap: Control = IconPreview.make_drag_preview("药水", 32, "")
		failed += _expect(wrap != null and wrap.get_node_or_null("Icon") != null, "IconPreview wrapper TextureRect")
		if wrap != null:
			wrap.queue_free()

	# Bag snapshot items include icon_index (init combat layers only — skip map pack)
	var MockServer = load("res://scripts/net/mock_server.gd")
	var srv = MockServer.new()
	if srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.has_method("_item_icon_fields"):
		var fields: Dictionary = srv._item_icon_fields("potion_hp_small")
		failed += _expect(int(fields.get("icon_index", -1)) == 32, "bag icon fields icon_index 32")
	if srv.item_catalog != null:
		failed += _expect(int(srv.item_catalog.icon_index_of("potion_hp_small")) == 32, "catalog icon for bag item")
	if srv.has_method("_bag_items_dup"):
		srv._ground_bags["test_bag"] = {
			"cell": {"x": 1, "y": 1},
			"items": [{"item_id": "potion_hp_small", "qty": 2}],
			"source": "test",
		}
		var items: Array = srv._bag_items_dup("test_bag")
		failed += _expect(items.size() == 1, "bag snapshot one item")
		if items.size() == 1 and typeof(items[0]) == TYPE_DICTIONARY:
			failed += _expect(int(items[0].get("icon_index", -1)) == 32, "bag snapshot item has icon_index")
		srv._ground_bags.erase("test_bag")

	# Skill catalog snapshot includes icon_index
	if srv.has_method("snapshot_skill_catalog"):
		var skills: Array = srv.snapshot_skill_catalog()
		var found_basic := false
		for s in skills:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			if str(s.get("id", "")) == "basic_attack":
				found_basic = true
				failed += _expect(int(s.get("icon_index", -1)) == 76, "snapshot_skill_catalog icon_index")
				break
		failed += _expect(found_basic, "snapshot has basic_attack")

	srv.free()
	_finish(failed)


func _write_test_iconset(path: String) -> void:
	## 16 cols × 12 rows = 512×384; paint each cell with a unique color; index 32 = red.
	var cols := 16
	var rows := 12
	var cell := 32
	var img := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.15, 0.15, 0.18, 1))
	for idx in range(cols * rows):
		var col := idx % cols
		var row := int(idx / cols)
		var c: Color
		if idx == 32:
			c = Color(1, 0, 0, 1)
		elif idx == 76:
			c = Color(0, 0.4, 1, 1)
		else:
			c = Color(float((idx * 37) % 255) / 255.0, float((idx * 17) % 255) / 255.0, float((idx * 53) % 255) / 255.0, 1)
		for y in range(cell):
			for x in range(cell):
				img.set_pixel(col * cell + x, row * cell + y, c)
	img.save_png(path)


func _write_solid_png(path: String, color: Color) -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.save_png(path)


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
