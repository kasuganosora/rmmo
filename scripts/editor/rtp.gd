extends RefCounted
## RPG Maker MV default RTP: tileset defs in res://data/rtp, images in content_root.

const MANIFEST := "res://data/rtp/manifest.json"
const RTP_DIR := "res://data/rtp"
const STEAM_NEWDATA := "D:/SteamLibrary/steamapps/common/RPG Maker MV/NewData"
const DEFAULT_PACK_ID := "default"

const DISPLAY_NAMES := {
	"overworld": "世界地图",
	"outside": "室外",
	"inside": "室内",
	"dungeon": "迷宫",
	"sf_outside": "科幻室外",
	"sf_inside": "科幻室内",
}


static func default_tileset_id() -> String:
	var man: Dictionary = _read_json(MANIFEST)
	var d := str(man.get("default", "outside"))
	return d if d != "" else "outside"


static func display_name(tileset_id: String) -> String:
	if DISPLAY_NAMES.has(tileset_id):
		return str(DISPLAY_NAMES[tileset_id])
	return tileset_id


static func load_tilesets() -> Dictionary:
	var out := {}
	var man: Dictionary = _read_json(MANIFEST)
	var ids_v: Variant = man.get("ids", ["overworld", "outside", "inside", "dungeon", "sf_outside", "sf_inside"])
	if typeof(ids_v) != TYPE_ARRAY:
		return out
	for id in ids_v:
		var sid := str(id)
		var ts: Dictionary = _read_json("%s/%s.json" % [RTP_DIR, sid])
		if not ts.is_empty():
			out[sid] = ts
	return out


static func merge_into(tilesets: Dictionary) -> bool:
	var rtp: Dictionary = load_tilesets()
	if rtp.is_empty():
		return false
	var added := false
	for k in rtp.keys():
		if not tilesets.has(k):
			tilesets[k] = rtp[k]
			added = true
	return added


static func content_root() -> String:
	return _content_root()


static func ensure_runtime_assets() -> bool:
	var root := _content_root()
	var probe := "%s/assets/tilesheet/Outside_A1.png" % root
	if FileAccess.file_exists(probe):
		return true
	return _copy_from_steam(root)


static func _content_root() -> String:
	var am = Engine.get_main_loop().root.get_node_or_null("/root/AssetManager")
	if am != null and am.has_method("content_root"):
		var r := str(am.content_root()).strip_edges()
		if r != "":
			return r.rstrip("/").rstrip("\\")
	if DirAccess.dir_exists_absolute("D:/code/rmmo_runtime"):
		return "D:/code/rmmo_runtime"
	if DirAccess.dir_exists_absolute("/workspace/rmmo_runtime"):
		return "/workspace/rmmo_runtime"
	return ProjectSettings.globalize_path("user://content")


static func _copy_from_steam(root: String) -> bool:
	var src := STEAM_NEWDATA
	if not DirAccess.dir_exists_absolute("%s/img/tilesets" % src):
		push_warning("rtp: MV NewData not found at %s" % src)
		return false
	_copy_pngs("%s/img/tilesets" % src, "%s/assets/tilesheet" % root)
	_copy_pngs("%s/img/characters" % src, "%s/assets/charset" % root)
	_copy_pngs("%s/img/characters" % src, "%s/characters" % root)
	_copy_pngs("%s/img/faces" % src, "%s/assets/faces" % root)
	_copy_pngs("%s/img/system" % src, "%s/assets/system" % root)
	_copy_pngs("%s/img/parallaxes" % src, "%s/assets/parallax" % root)
	return FileAccess.file_exists("%s/assets/tilesheet/Outside_A1.png" % root)


static func _copy_pngs(from_dir: String, to_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(from_dir):
		return
	DirAccess.make_dir_recursive_absolute(to_dir)
	var da := DirAccess.open(from_dir)
	if da == null:
		return
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.to_lower().ends_with(".png"):
			var dest := "%s/%s" % [to_dir, fn]
			if not FileAccess.file_exists(dest):
				DirAccess.copy_absolute("%s/%s" % [from_dir, fn], dest)
		fn = da.get_next()


static func _read_json(path: String) -> Dictionary:
	var p := path
	if not FileAccess.file_exists(p):
		var abs_path := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_path):
			p = abs_path
		else:
			return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
