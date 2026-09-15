extends SceneTree
## Far scroll, no-dash, settings pack, procedural sfx.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MapExt = load("res://scripts/map/map_ext.gd")
	var MapSfx = load("res://scripts/map/map_sfx.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MockServer = load("res://scripts/net/mock_server.gd")

	var packed: int = MapExt.pack_settings(2, 3, 1)
	failed += _expect(MapExt.settings_light(packed) == 2, "pack light")
	failed += _expect(MapExt.settings_sound(packed) == 3, "pack sound")
	failed += _expect(MapExt.settings_footstep(packed) == 1, "pack footstep")

	var step = MapSfx.footstep(1)
	failed += _expect(step != null and step.data.size() > 100, "footstep wav")
	failed += _expect(int(step.format) == AudioStreamWAV.FORMAT_16_BITS, "footstep signed 16-bit")
	var s0: int = MapSfx.sample_s16(step, 0)
	failed += _expect(absi(s0) < 2500, "footstep starts near silence (not unsigned-8 DC)")
	var peak := 0
	var sum := 0
	var n16: int = int(step.data.size() / 2)
	var take: int = mini(n16, 400)
	for si in range(take):
		var sv16: int = MapSfx.sample_s16(step, si)
		sum += sv16
		if absi(sv16) > peak:
			peak = absi(sv16)
	failed += _expect(absi(sum / maxi(take, 1)) < 4000, "footstep no unsigned-8 DC bias")
	failed += _expect(peak < 28000, "footstep not full-scale hash")
	var amb = MapSfx.ambient("wind")
	failed += _expect(amb != null and amb.loop_mode != 0, "ambient loops")
	failed += _expect(int(amb.format) == AudioStreamWAV.FORMAT_16_BITS, "ambient signed 16-bit")
	failed += _expect(absi(MapSfx.sample_s16(amb, 0)) < 8000, "ambient not unsigned-8 blast")

	var MapDocument = load("res://scripts/editor/map_document.gd")
	var field: Node2D = MapField.new()
	field.edit_mode = true
	var edoc = MapDocument.new()
	edoc.setup_blank("M", "m", 8, 8, 48)
	edoc.far_scroll = Vector2(0.25, -0.1)
	field.edit_doc = edoc
	failed += _expect(is_equal_approx(field.far_scroll_vec().x, 0.25), "field far_scroll from edit_doc")
	field.free()

	var pack = ContentPack.new()
	pack.new_blank("rt_pack", "runtime", 12, 12)
	var doc = pack.get_map("Map001")
	doc.set_tile(4, 5, 0, 2816, false)
	doc.set_tile(5, 5, 0, 2816, false)
	doc.set_tile(6, 5, 0, 2816, false)
	doc.set_ext_tile("meta", 5, 5, MapExt.META_NO_DASH)
	doc.set_ext_tile("settings", 5, 5, MapExt.pack_settings(1, 2, 3))
	doc.far_scroll = Vector2(0.4, 0.0)
	doc.bgm = "Town"
	failed += _expect(pack.save_dir(), "save runtime pack")
	var sv = MockServer.new()
	get_root().add_child(sv)
	failed += _expect(bool(sv.load_world_pack(pack.root, "Map001", Vector2i(4, 5))), "load pack")
	failed += _expect(sv.map_collision != null, "collision")
	failed += _expect(sv.map_collision.no_dash_at(5, 5), "no_dash_at dest")
	failed += _expect(not sv.map_collision.no_dash_at(4, 5), "start allows dash")
	failed += _expect(sv.map_collision.ext != null and is_equal_approx(sv.map_collision.ext.far_scroll.x, 0.4), "ext far_scroll on collision")
	var mv: Dictionary = sv.try_move(4, 5, 6)
	failed += _expect(bool(mv.get("ok", false)), "try_move ok")
	failed += _expect(bool(mv.get("no_dash", false)), "try_move no_dash")
	var packed2: int = int(sv.map_collision.settings_at(5, 5))
	failed += _expect(MapExt.settings_footstep(packed2) == 3, "settings footstep on cell")
	failed += _expect(MapExt.settings_sound(packed2) == 2, "settings sound on cell")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var loaded = TilemapPack.load_pack(pack.root, "Map001")
	failed += _expect(str(loaded.bgm) == "Town", "pack bgm from map.json")
	sv.queue_free()

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
