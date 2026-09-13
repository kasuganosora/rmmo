extends RefCounted
## .rmpack zip import/export for content packs.

const SKIP_PREFIXES := ["mv_img/", "www/img/"]


static func export_zip(src_dir: String, zip_path: String) -> bool:
	src_dir = src_dir.rstrip("/").rstrip("\\")
	var abs_src := _abs(src_dir)
	if not DirAccess.dir_exists_absolute(abs_src):
		return false
	var abs_zip := _abs(zip_path)
	var parent := abs_zip.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var zp := ZIPPacker.new()
	if zp.open(abs_zip) != OK:
		return false
	var ok := _add_dir(zp, abs_src, "")
	zp.close()
	return ok


static func import_zip(zip_path: String, dest_dir: String) -> Dictionary:
	## Returns {ok, pack_id, root, error}.
	var abs_zip := _abs(zip_path)
	if not FileAccess.file_exists(abs_zip):
		return {"ok": false, "error": "找不到文件"}
	var zr := ZIPReader.new()
	if zr.open(abs_zip) != OK:
		return {"ok": false, "error": "无法打开 zip"}
	var files: PackedStringArray = zr.get_files()
	var has_pack := false
	for f in files:
		if f.ends_with("pack.json") or f == "pack.json":
			has_pack = true
			break
	if not has_pack:
		zr.close()
		return {"ok": false, "error": "包内没有 pack.json"}
	var abs_dest := _abs(dest_dir)
	if DirAccess.dir_exists_absolute(abs_dest):
		_remove_dir(abs_dest)
	DirAccess.make_dir_recursive_absolute(abs_dest)
	for f2 in files:
		if f2.ends_with("/"):
			continue
		var lower := f2.replace("\\", "/").to_lower()
		var skip := false
		for pref in SKIP_PREFIXES:
			if lower.find(pref) >= 0:
				skip = true
				break
		if skip:
			continue
		var data: PackedByteArray = zr.read_file(f2)
		var out_path := "%s/%s" % [abs_dest, f2]
		var out_dir := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(out_dir)
		var wf := FileAccess.open(out_path, FileAccess.WRITE)
		if wf == null:
			zr.close()
			return {"ok": false, "error": "写入失败 %s" % f2}
		wf.store_buffer(data)
	zr.close()
	var pack_txt := FileAccess.get_file_as_string("%s/pack.json" % abs_dest)
	var parsed: Variant = JSON.parse_string(pack_txt)
	var pid := dest_dir.get_file()
	if typeof(parsed) == TYPE_DICTIONARY:
		pid = str(parsed.get("id", pid))
	return {"ok": true, "pack_id": pid, "root": dest_dir, "error": ""}


static func _add_dir(zp: ZIPPacker, abs_dir: String, rel: String) -> bool:
	var da := DirAccess.open(abs_dir)
	if da == null:
		return false
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var child_abs := "%s/%s" % [abs_dir, name]
		var child_rel := name if rel == "" else "%s/%s" % [rel, name]
		var low := child_rel.replace("\\", "/").to_lower()
		var skip := false
		for pref in SKIP_PREFIXES:
			if low.find(pref) >= 0:
				skip = true
				break
		if skip:
			name = da.get_next()
			continue
		if da.current_is_dir():
			if not _add_dir(zp, child_abs, child_rel):
				return false
		else:
			var bytes := FileAccess.get_file_as_bytes(child_abs)
			if zp.start_file(child_rel) != OK:
				return false
			if zp.write_file(bytes) != OK:
				return false
			zp.close_file()
		name = da.get_next()
	return true


static func _remove_dir(abs_path: String) -> void:
	var da := DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := "%s/%s" % [abs_path, n]
			if da.current_is_dir():
				_remove_dir(p)
			else:
				DirAccess.remove_absolute(p)
		n = da.get_next()
	DirAccess.remove_absolute(abs_path)


static func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
