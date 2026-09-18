extends SceneTree
## Layer hide, palette stamp, choice-command branches.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")
	var TilePalette = load("res://scripts/editor/interface/tile_palette.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")

	var field: Node2D = MapField.new()
	field.edit_mode = true
	failed += _expect(field.is_layer_drawn_z(0), "z0 drawn by default")
	failed += _expect(field.is_layer_drawn_ext("roof"), "ext roof drawn by default")
	field.set_layer_hidden_z(2, true)
	failed += _expect(not field.is_layer_drawn_z(2), "z2 hidden")
	failed += _expect(field.is_layer_drawn_z(0), "z0 still drawn")
	field.set_layer_hidden_z(2, false)
	failed += _expect(field.is_layer_drawn_z(2), "z2 shown again")
	field.set_layer_hidden_ext("roof", true)
	failed += _expect(not field.is_layer_drawn_ext("roof"), "roof hidden")
	field.edit_mode = false
	failed += _expect(field.is_layer_drawn_z(2), "play mode ignores hide")
	field.free()

	var id_a: int = TilePalette.a_cell_to_id(0, 16)
	var id_b: int = TilePalette.a_cell_to_id(1, 16)
	failed += _expect(id_a > 0 and id_b > 0 and id_a != id_b, "A5 neighbor ids")
	var pack = ContentPack.new()
	pack.new_blank("stamp_pack", "stamp", 12, 12)
	var doc = pack.get_map("Map001")
	var paint = PaintTools.new()
	paint.layer_z = 0
	var tiles := PackedInt32Array([id_a, id_b, id_a, id_b])
	paint.set_stamp(2, 2, tiles)
	failed += _expect(paint.has_stamp(), "has 2x2 stamp")
	var dirty: Array = paint.apply_stamp(doc, Vector2i(3, 3))
	failed += _expect(dirty.size() >= 4, "stamp writes 4 cells")
	failed += _expect(int(doc.tile(3, 3, 0)) == id_a, "stamp tl")
	failed += _expect(int(doc.tile(4, 3, 0)) == id_b, "stamp tr")
	failed += _expect(int(doc.tile(3, 4, 0)) == id_a, "stamp bl")
	failed += _expect(int(doc.tile(4, 4, 0)) == id_b, "stamp br")
	paint.begin_stroke()
	paint.apply_cell(doc, Vector2i(6, 6))
	failed += _expect(int(doc.tile(6, 6, 0)) == id_a, "pencil stamp block tl")
	failed += _expect(int(doc.tile(7, 6, 0)) == id_b, "pencil stamp block tr")
	paint.apply_cell(doc, Vector2i(8, 6))
	failed += _expect(int(doc.tile(8, 6, 0)) == id_a, "drag tiled stamp")
	var rect_d: Array = paint.apply_rect(doc, Vector2i(0, 8), Vector2i(3, 9), false)
	failed += _expect(rect_d.size() >= 8, "rect stamp 4x2")
	failed += _expect(int(doc.tile(0, 8, 0)) == id_a, "rect stamp origin")
	failed += _expect(int(doc.tile(1, 8, 0)) == id_b, "rect stamp tile")

	var ch: Dictionary = EventCommands.default_command("choices")
	failed += _expect(EventCommands.options_of(ch).size() == 2, "default two options")
	EventCommands.set_option_label(ch, 0, "拿药水")
	EventCommands.set_option_label(ch, 1, "离开")
	var b0: Array = EventCommands.option_commands(ch, 0)
	b0.append(EventCommands.default_command("give_item"))
	(b0[0] as Dictionary)["item_id"] = "potion_hp_small"
	(b0[0] as Dictionary)["qty"] = 3
	var b1: Array = EventCommands.option_commands(ch, 1)
	b1.append({"op": "text", "text": "下次再来。"})
	failed += _expect(EventCommands.summarize_option(EventCommands.options_of(ch)[0]).find("1") >= 0, "option summary count")
	EventCommands.add_option(ch, "旁观")
	failed += _expect(EventCommands.options_of(ch).size() == 3, "add option")
	EventCommands.remove_option(ch, 2)
	failed += _expect(EventCommands.options_of(ch).size() == 2, "remove option")

	var ev: Dictionary = EventCommands.make_event(Vector2i(2, 2), "hi")
	var pages: Array = EventCommands.ensure_pages(ev)
	pages[0]["commands"] = [ch]
	var rt = EventRuntime.new()
	rt.load_events_array([ev], "Map001")
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var inv = Inventory.new()
	inv.set_catalog(cat)
	inv.clear()
	inv.grant_starter()
	var pot0: int = inv.get_qty("potion_hp_small")
	var acts: Array = rt.run_event(str(ev.get("id", "")), {"inventory": inv, "npc_name": "村民"})
	var has_choice := false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and bool(a.get("event_choice", false)):
			has_choice = true
	failed += _expect(has_choice, "choices prompt")
	var branch: Array = rt.try_event_choice("opt_0")
	failed += _expect(inv.get_qty("potion_hp_small") == pot0 + 3, "branch give_item ×3")
	var has_inv := false
	for a2 in branch:
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "inventory_update":
			has_inv = true
	failed += _expect(has_inv, "branch inventory_update")

	var ts_id := str(doc.tileset_id)
	failed += _expect(pack.init_slot_passage(ts_id, 7, 1), "init D slot ×")
	var ts: Dictionary = pack.tilesets[ts_id]
	var fl: Array = ts.get("flags", [])
	var TileId = load("res://scripts/map/tile_id.gd")
	var dr: Vector2i = TileId.slot_range(7)
	failed += _expect(dr.x == 512 and dr.y == 768, "D range 512-768")
	var sample: int = int(fl[512]) if fl.size() > 512 else -1
	failed += _expect(TileId.passage_kind(sample) == TileId.PASS_X, "imported D default ×")
	failed += _expect(pack.init_slot_passage(ts_id, 4), "init A5 default ○")
	var fl2: Array = pack.tilesets[ts_id].get("flags", [])
	var a5: int = int(fl2[1536]) if fl2.size() > 1536 else -1
	failed += _expect(TileId.passage_kind(a5) == TileId.PASS_O, "A5 default ○")

	var MapExt = load("res://scripts/map/map_ext.gd")
	doc.far_scroll = Vector2(0.25, -0.1)
	doc.water_through = true
	doc.set_ext_tile("meta", 2, 3, MapExt.META_INDOOR | MapExt.META_WATER)
	doc.set_ext_tile("settings", 4, 4, MapExt.pack_settings(2, 0, 0))
	doc.set_tile(1, 1, 4, 5)
	doc.set_tile(1, 2, 5, 7)
	failed += _expect(pack.save_dir(), "save spec layers")
	failed += _expect(pack.reload_map("Map001"), "reload spec map")
	var doc3 = pack.get_map("Map001")
	failed += _expect(is_equal_approx(doc3.far_scroll.x, 0.25), "far_scroll x")
	failed += _expect(bool(doc3.water_through), "water_through saved")
	failed += _expect((int(doc3.ext_tile("meta", 2, 3)) & MapExt.META_INDOOR) != 0, "meta indoor")
	failed += _expect((int(doc3.ext_tile("meta", 2, 3)) & MapExt.META_WATER) != 0, "meta water")
	failed += _expect(MapExt.settings_light(int(doc3.ext_tile("settings", 4, 4))) == 2, "settings light 2")
	failed += _expect((int(doc3.tile(1, 1, 4)) & 0x0f) == 5, "shadow bits")
	failed += _expect(int(doc3.tile(1, 2, 5)) == 7, "region id")
	failed += _expect(str(MapExt.layer_label("roof")) == "屋顶", "layer label")
	var day_c: Color = MapExt.light_modulate(0)
	var night_c: Color = MapExt.light_modulate(2)
	failed += _expect(day_c.r > 0.95 and day_c.g > 0.95, "day light near white")
	failed += _expect(night_c.r < day_c.r and night_c.b > night_c.r * 0.9, "night light cooler/dimmer")
	doc.light_preset = 2
	failed += _expect(pack.save_dir(), "save light_preset")
	failed += _expect(pack.reload_map("Map001"), "reload light_preset map")
	var doc4 = pack.get_map("Map001")
	failed += _expect(int(doc4.light_preset) == 2, "map.json light_preset 2")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var loaded_light = TilemapPack.load_pack(pack.root, "Map001")
	failed += _expect(int(loaded_light.light_preset) == 2, "play pack loads light_preset")
	doc4.light_fx_color = Color(1.0, 0.35, 0.12, 0.9)
	failed += _expect(pack.save_dir(), "save light_fx_color")
	failed += _expect(pack.reload_map("Map001"), "reload light_fx_color map")
	var doc5 = pack.get_map("Map001")
	failed += _expect(doc5.light_fx_color.is_equal_approx(Color(1.0, 0.35, 0.12, 0.9)), "map ext light fx color")
	var loaded_fx = TilemapPack.load_pack(pack.root, "Map001")
	failed += _expect(loaded_fx.light_fx_color.is_equal_approx(Color(1.0, 0.35, 0.12, 0.9)), "play pack loads light_fx_color")
	failed += _expect(not loaded_fx.light_fx_color.is_equal_approx(MapExt.light_modulate(2)), "fx color independent of 光照")

	var Editor = load("res://scripts/editor/content_editor.gd")
	var ed = Editor.new()
	ed._hscroll = HScrollBar.new()
	ed._vscroll = VScrollBar.new()
	ed._hscroll.min_value = 0
	ed._hscroll.max_value = 4000
	ed._hscroll.page = 400
	ed._hscroll.value = 800
	ed._vscroll.min_value = 0
	ed._vscroll.max_value = 4000
	ed._vscroll.page = 400
	ed._vscroll.value = 800
	var hx0: float = ed._hscroll.value
	var hy0: float = ed._vscroll.value
	var wheel_right := InputEventMouseButton.new()
	wheel_right.button_index = MOUSE_BUTTON_WHEEL_RIGHT
	wheel_right.pressed = true
	ed._on_canvas_input(wheel_right)
	failed += _expect(ed._hscroll.value > hx0, "canvas wheel right pans x")
	failed += _expect(is_equal_approx(ed._vscroll.value, hy0), "canvas wheel right keeps y")
	var hx1: float = ed._hscroll.value
	var wheel_left := InputEventMouseButton.new()
	wheel_left.button_index = MOUSE_BUTTON_WHEEL_LEFT
	wheel_left.pressed = true
	ed._on_canvas_input(wheel_left)
	failed += _expect(ed._hscroll.value < hx1, "canvas wheel left pans x back")
	var shift_up := InputEventMouseButton.new()
	shift_up.button_index = MOUSE_BUTTON_WHEEL_UP
	shift_up.pressed = true
	shift_up.shift_pressed = true
	var hx2: float = ed._hscroll.value
	ed._on_canvas_input(shift_up)
	failed += _expect(ed._hscroll.value < hx2, "shift+wheel up pans x")
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(40, 0)
	var hx3: float = ed._hscroll.value
	ed._on_canvas_input(pan)
	failed += _expect(ed._hscroll.value > hx3, "canvas pan gesture pans x")
	ed.free()

	var pal = TilePalette.new()
	root.add_child(pal)
	failed += _expect(pal._scroll != null, "palette scroll")
	failed += _expect(pal._scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "palette allows h-scroll")
	failed += _expect(pal._scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_NEVER, "palette shows h-scroll")
	if pal._host:
		pal._host.custom_minimum_size = Vector2(960, 640)
	var hbar: ScrollBar = pal._scroll.get_h_scroll_bar()
	if hbar:
		hbar.min_value = 0
		hbar.max_value = 2000
		hbar.page = 200
	pal._scroll.scroll_horizontal = 80
	var pal_h0: int = pal._scroll.scroll_horizontal
	var pal_right := InputEventMouseButton.new()
	pal_right.button_index = MOUSE_BUTTON_WHEEL_RIGHT
	pal_right.pressed = true
	pal._on_view_input(pal_right)
	failed += _expect(pal._scroll.scroll_horizontal > pal_h0, "palette wheel right pans x")
	pal.free()

	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
