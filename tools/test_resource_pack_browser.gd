extends SceneTree
const Catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
var failed := 0
var chosen := ""

func _init() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", text])
	if not ok: failed += 1

func make_pack(base: String, name: String) -> String:
	var path := base.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	var file := FileAccess.open(path.path_join("metadata.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": name, "name": name, "version": "1.0", "settings": {"start_map": "城镇", "custom_setting": true}}))
	file.close()
	return path

func run() -> void:
	var base: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("pack_browser_%d" % Time.get_ticks_usec())
	var a := make_pack(base, "A")
	var b := make_pack(base, "B")
	var shared := make_pack(base, "默认")
	var doc = Doc.new()
	doc.add_box("ground", Vector3.ZERO, Vector3(4, 0.2, 4))
	var local_map := a.path_join("maps/城镇/map.gltf")
	var shared_map := shared.path_join("maps/城镇/map.gltf")
	check(doc.save(local_map) == OK, "create local map")
	# Each new document gets its own disk revision.
	check(Doc.new().save(shared_map) == OK, "create globally available map")
	check(Doc.new().save(b.path_join("maps/森林/map.gltf")) == OK, "create second pack map")
	var catalog = Catalog.new(base)
	# Neither old manifests, map folders nor malformed metadata register a pack.
	for fixture in ["old_manifest", "maps_only", "invalid_metadata", "array_metadata"]:
		var directory := base.path_join(fixture)
		DirAccess.make_dir_recursive_absolute(directory.path_join("maps"))
		if fixture == "maps_only": continue
		var file := FileAccess.open(directory.path_join("pack.json" if fixture == "old_manifest" else "metadata.json"), FileAccess.WRITE)
		file.store_string("{\"id\":\"old\"}" if fixture == "old_manifest" else ("[]" if fixture == "array_metadata" else "{broken"))
		file.close()
	var packs: Array[Dictionary] = catalog.packs()
	check(packs.size() == 3 and packs[0].shared, "only valid metadata.json objects register packs; default first")
	check(packs[0].version == "1.0" and packs[0].metadata.settings.custom_setting == true, "metadata version and custom pack settings are preserved")
	var ai: int = catalog.owner_of(local_map, packs)
	var bi: int = catalog.owner_of(b.path_join("maps/森林/map.gltf"), packs)
	var visible: Array[Dictionary] = catalog.available_maps(packs[ai], packs)
	check(visible.size() == 2 and visible[0].path != visible[1].path, "same-name local and shared maps retain separate ownership")
	var other: Array[Dictionary] = catalog.available_maps(packs[bi], packs)
	check(other.size() == 2 and not other.any(func(map): return map.path == local_map), "other pack includes default but excludes A's private map")
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = Doc.open_file(local_map)
	session.world3d_editor_path = local_map
	var editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._open_pack_maps()
	var dialog = editor._pack_map_dialog
	dialog.hide()
	dialog.catalog = catalog
	dialog.show_maps(local_map)
	await process_frame
	check(dialog.visible and not dialog.get_ok_button().disabled, "picker opens and selects current map")
	check(dialog._map_list.get_root().get_child_count() == 2, "picker shows pack and global maps")
	dialog._search.text = "不存在"
	dialog._search.text_changed.emit(dialog._search.text)
	check(dialog.get_ok_button().disabled and dialog._map_list.get_root().get_child_count() == 0, "empty search disables open")
	dialog._search.clear()
	dialog._fill_maps()
	if DisplayServer.get_name() != "headless":
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var path := preload("res://scripts/asset/art_paths.gd").review_path("resource_pack_maps.png")
		root.get_texture().get_image().save_png(path)
		print("capture=" + path)
	editor._dirty = true
	dialog._map_list.get_root().get_child(1).select(0)
	dialog._open_selected()
	check(not dialog.visible and editor._path == local_map, "picker closes before unsaved-change confirmation, document preserved")
	var prompt: ConfirmationDialog
	for child in editor.get_children():
		if child is ConfirmationDialog and child != dialog: prompt = child
	check(prompt != null and prompt.visible, "switching map preserves unsaved-change prompt")
	if prompt:
		prompt.hide()
		prompt.custom_action.emit("discard")
	check(editor._path == shared_map, "opening global map uses its real owning pack path")
	var legacy_map := base.path_join("maps/medieval_river_town/map.gltf")
	check(Doc.new().save(legacy_map)==OK,"create root-level authored map")
	var before := FileAccess.get_sha256(legacy_map)
	check(catalog.owner_of(legacy_map,packs)==0,"root-level authored map belongs to shared browser entry")
	check(catalog.available_maps(packs[bi],packs).any(func(row):return row.path==legacy_map),"root-level authored map visible from every pack at original path")
	dialog.show_maps(legacy_map)
	check(dialog._map_list.get_selected().get_metadata(0)==legacy_map,"root-level current map is selected in picker")
	dialog._search.text="medieval_river_town";dialog._fill_maps()
	check(dialog._map_list.get_root().get_child_count()==1,"root-level map searchable by directory name")
	check(FileAccess.get_sha256(legacy_map)==before,"map discovery never rewrites map contents")
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	# Versioned legacy pack layout is read without moving any files.
	make_pack(base.path_join("packs/map_pack/legacy"), "0.1.0")
	check(catalog.packs().size() == 4, "versioned resource packs require metadata.json too")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(base)
	print("test_resource_pack_browser: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
