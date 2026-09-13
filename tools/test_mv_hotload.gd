extends SceneTree
## Headless: MV img root discovery + charset/tilesheet hot-load from external mv_img (not res://).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return

	# Ensure Linux mock fixture tree exists for CI/box (real Luna uses junction).
	var mock_root := "/workspace/rmmo_runtime/mv_img"
	var mock_charset := "%s/characters/__mv_hotload_only.png" % mock_root
	var mock_tile := "%s/tilesets/commu_floor.png" % mock_root
	var mock_tile_only := "%s/tilesets/__mv_tile_only.png" % mock_root
	failed += _expect(DirAccess.dir_exists_absolute(mock_root) or DirAccess.dir_exists_absolute(str(am.mv_img_root())), "mv_img fixture or discovered root exists")
	if not FileAccess.file_exists(mock_charset):
		push_warning("test_mv_hotload: missing charset fixture %s" % mock_charset)
	if not FileAccess.file_exists(mock_tile):
		push_warning("test_mv_hotload: missing tileset fixture %s" % mock_tile)

	# --- mv_img_root discovery ---
	var mv_root: String = str(am.mv_img_root()).strip_edges()
	print("mv_img_root=", mv_root)
	failed += _expect(mv_root != "", "mv_img_root non-empty when junction/mock present")
	failed += _expect(
		mv_root.find("mv_img") >= 0 or mv_root.find("www/img") >= 0 or mv_root.find("www\\img") >= 0,
		"mv_img_root looks like MV img path"
	)

	# --- charset only under mv_img/characters ---
	var charset_id := "__mv_hotload_only"
	var charset_ref := "content://charset/%s" % charset_id
	var charset_path: String = str(am.path(charset_ref))
	print("charset path=", charset_path, " exists=", FileAccess.file_exists(charset_path))
	failed += _expect(FileAccess.file_exists(charset_path), "resolve charset that exists only under mv_img/characters")
	failed += _expect(
		charset_path.replace("\\", "/").find("/characters/__mv_hotload_only.png") >= 0
		or charset_path.replace("\\", "/").ends_with("characters/__mv_hotload_only.png"),
		"charset path under characters/"
	)
	failed += _expect(charset_path.replace("\\", "/").find("/workspace/rmmo/") < 0 or charset_path.find("res://") < 0, "charset not under project res tree")
	# Stronger: must not be inside Godot project assets
	var proj := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	failed += _expect(not charset_path.replace("\\", "/").begins_with(proj + "/"), "charset outside project tree")
	failed += _expect(am.ensure(charset_ref) == OK, "ensure mv charset OK")
	var cimg: Image = am.load_image(charset_ref)
	failed += _expect(cimg != null and cimg.get_width() > 0, "load_image mv charset")

	# charset_sheet fallback path
	var CharsetSheet = load("res://scripts/char/charset_sheet.gd")
	var sheet_path: String = str(CharsetSheet.resolve_sheet_path(charset_id))
	print("charset_sheet path=", sheet_path)
	failed += _expect(FileAccess.file_exists(sheet_path), "charset_sheet resolves mv-only sheet")

	# --- tilesheet via content://tilesheet/commu_floor ---
	var tile_ref := "content://tilesheet/commu_floor"
	var tile_path: String = str(am.path(tile_ref))
	print("tilesheet path=", tile_path, " exists=", FileAccess.file_exists(tile_path))
	failed += _expect(FileAccess.file_exists(tile_path), "resolve tilesheet commu_floor from mv_img/tilesets")
	failed += _expect(
		tile_path.replace("\\", "/").find("tilesets/commu_floor.png") >= 0
		or tile_path.replace("\\", "/").find("assets/tilesheet/commu_floor.png") >= 0,
		"tilesheet under tilesets or assets/tilesheet"
	)
	failed += _expect(not tile_path.replace("\\", "/").begins_with(proj + "/"), "tilesheet outside project tree")
	var timg: Image = am.load_image(tile_ref)
	failed += _expect(timg != null and timg.get_width() > 0, "load_image tilesheet commu_floor")

	# Unique tile only under mv_img
	var only_ref := "content://tilesheet/__mv_tile_only"
	var only_path: String = str(am.path(only_ref))
	print("tile_only path=", only_path)
	failed += _expect(FileAccess.file_exists(only_path), "resolve __mv_tile_only from mv_img")
	failed += _expect(am.load_image(only_ref) != null, "load_image __mv_tile_only")

	# Soft-miss still soft
	failed += _expect(am._is_soft_ref("content://tilesheet/nope"), "tilesheet soft ref")
	failed += _expect(am.ensure("content://tilesheet/__definitely_missing_xyz") != OK, "missing tilesheet ensure fails")

	# --- tilemap_pack falls back when pack-local tile missing ---
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	# demo_map often has no tiles/ on box — pack load should still pull sheets via AM when names match
	var pack = TilemapPack.load_pack("res://demo_map")
	failed += _expect(pack != null and int(pack.width) > 0, "load demo_map pack")
	if pack != null:
		var found_floor := false
		for i in range(pack.sheets.size()):
			var sheet = pack.sheets[i]
			if sheet != null and sheet is Image:
				var nm := ""
				if i < pack.tileset_names.size():
					nm = str(pack.tileset_names[i])
				print("sheet[", i, "]=", nm, " size=", (sheet as Image).get_width(), "x", (sheet as Image).get_height())
				if nm == "commu_floor":
					found_floor = true
					failed += _expect((sheet as Image).get_width() > 0, "commu_floor sheet loaded via MV fallback")
		# If tilesetNames includes commu_floor, we must have loaded it from mv_img when pack tiles absent
		var names_has_floor := false
		for n in pack.tileset_names:
			if str(n) == "commu_floor":
				names_has_floor = true
				break
		if names_has_floor:
			failed += _expect(found_floor, "demo_map commu_floor sheet non-null via hot-load")
		else:
			print("SKIP demo_map commu_floor name check (not in tilesetNames)")

	# Direct unit: _load_tilesheet_via_asset_manager path through a fresh pack instance
	var probe = TilemapPack.new()
	probe.pack_dir = "res://demo_map"
	if probe.has_method("_load_sheet_image"):
		var via: Image = probe._load_sheet_image("__mv_tile_only", "tiles")
		failed += _expect(via != null and via.get_width() > 0, "tilemap_pack _load_sheet_image MV-only tile")
	else:
		failed += _expect(false, "tilemap_pack has _load_sheet_image")

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS: ", label)
		return 0
	print("FAIL: ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
	else:
		print("FAILED count=", failed)
	quit(0 if failed == 0 else 1)
