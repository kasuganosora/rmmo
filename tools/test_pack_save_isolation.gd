extends SceneTree
## Save isolation: demo_map copy to user://, bad zip, no res:// write when map_editor_dev off.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var PackZip = load("res://scripts/editor/infrastructure/pack_zip.gd")
	ProjectSettings.set_setting("rmmo/map_editor_dev", false)
	var am: Node = root.get_node_or_null("AssetManager")
	var demo_dir := str(am.resolve_map_pack_path("demo_map")) if am != null else ""
	var demo_json := "%s/pack.json" % demo_dir
	failed += _expect(FileAccess.file_exists(demo_json), "external demo pack.json")
	var before := FileAccess.get_modified_time(demo_json)
	var before_txt := FileAccess.get_file_as_string(demo_json)
	var pack = ContentPack.new()
	failed += _expect(pack.load_dir(demo_dir), "load demo_map")
	var dest_id := "demo_user_copy_plan"
	_wipe("user://content/packs/" + dest_id)
	failed += _expect(pack.adopt_as_user_pack(dest_id, "demo copy"), "adopt user copy")
	var after := FileAccess.get_modified_time(demo_json)
	var after_txt := FileAccess.get_file_as_string(demo_json)
	failed += _expect(after == before, "demo_map mtime unchanged")
	failed += _expect(after_txt == before_txt, "demo_map pack.json bytes unchanged")
	failed += _expect(str(pack.root).find("user://") >= 0 or ProjectSettings.globalize_path(pack.root).find("app_userdata") >= 0 or str(pack.root).find("content/packs") >= 0, "save root not res://")
	failed += _expect(not str(pack.root).begins_with("res://"), "root is not res://")
	failed += _expect(not ContentPack.allow_write_root("res://demo_map"), "allow_write_root res:// false")
	failed += _expect(not pack.save_dir("res://demo_map"), "save_dir res:// refused")
	var bad_zip := "user://content/packs/_bad_no_pack.zip"
	var zp := ZIPPacker.new()
	zp.open(ProjectSettings.globalize_path(bad_zip))
	zp.start_file("readme.txt")
	zp.write_file("no pack here".to_utf8_buffer())
	zp.close_file()
	zp.close()
	var bad_dest := "user://content/packs/_bad_import_dest"
	_wipe(bad_dest)
	var imp: Dictionary = PackZip.import_zip(bad_zip, bad_dest)
	failed += _expect(not bool(imp.get("ok", false)), "zip without pack.json fails")
	var dest_abs := ProjectSettings.globalize_path(bad_dest)
	var usable := FileAccess.file_exists(bad_dest + "/pack.json") or FileAccess.file_exists(dest_abs + "/pack.json")
	failed += _expect(not usable, "no usable pack.json created")
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _wipe(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var da := DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := "%s/%s" % [abs_path, n]
			if da.current_is_dir():
				_wipe(p if p.begins_with("user://") else p)
				DirAccess.remove_absolute(p)
			else:
				DirAccess.remove_absolute(p)
		n = da.get_next()
	DirAccess.remove_absolute(abs_path)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
