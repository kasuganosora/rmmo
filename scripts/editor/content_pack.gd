extends RefCounted
## Content pack: map tree + tilesets + per-map documents + pack-local assets.

const MapDocument = preload("res://scripts/editor/map_document.gd")

const FORMAT := "content_pack_v1"
const USER_PACKS := "user://content/packs"

var pack_id: String = "untitled"
var pack_name: String = "未命名"
var root: String = ""
var start_map: String = "Map001"
var tile_size: int = 48
## [{id, name, parent, tileset}]
var map_tree: Array = []
var tilesets: Dictionary = {} ## id -> {flags, tilesetNames}
var maps: Dictionary = {} ## id -> MapDocument
var dirty: bool = false


static func user_packs_root() -> String:
	return USER_PACKS


static func pack_dir_for(id: String) -> String:
	return "%s/%s" % [USER_PACKS, id]


func is_legacy_flat() -> bool:
	return not map_tree.is_empty() and FileAccess.file_exists("%s/map.json" % root) and not DirAccess.dir_exists_absolute(_abs("%s/maps" % root))


func new_blank(p_id: String, p_name: String, w: int = 20, h: int = 15) -> void:
	pack_id = _slug(p_id)
	pack_name = p_name
	root = pack_dir_for(pack_id)
	start_map = "Map001"
	tile_size = 48
	map_tree = [{"id": "Map001", "name": "地图1", "parent": "", "tileset": "default"}]
	tilesets = {"default": _default_tileset()}
	var doc: RefCounted = MapDocument.new()
	doc.setup_blank("Map001", "地图1", w, h, tile_size)
	maps = {"Map001": doc}
	dirty = true


func load_dir(dir: String) -> bool:
	dir = dir.rstrip("/").rstrip("\\")
	root = dir
	var pack: Dictionary = _read_json("%s/pack.json" % dir)
	if pack.is_empty():
		return false
	pack_id = str(pack.get("id", dir.get_file()))
	pack_name = str(pack.get("name", pack_id))
	tile_size = int(pack.get("tile_size", 48))
	start_map = str(pack.get("start_map", "Map001"))
	var tree_v: Variant = pack.get("map_tree", [])
	maps.clear()
	tilesets.clear()
	if typeof(tree_v) == TYPE_ARRAY and not (tree_v as Array).is_empty():
		map_tree = (tree_v as Array).duplicate(true)
		_load_tilesets_dir()
		for item in map_tree:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var mid := str(item.get("id", "")).strip_edges()
			if mid.is_empty():
				continue
			var doc: RefCounted = MapDocument.new()
			doc.map_id = mid
			doc.display_name = str(item.get("name", mid))
			doc.parent_id = str(item.get("parent", ""))
			doc.tileset_id = str(item.get("tileset", "default"))
			var mdir := "%s/maps/%s" % [dir, mid]
			if not doc.load_dir(mdir):
				doc.setup_blank(mid, doc.display_name, 20, 15, tile_size)
			maps[mid] = doc
	else:
		# Flattened legacy pack (demo_map/map.json at root).
		var doc2: RefCounted = MapDocument.new()
		doc2.map_id = pack_id
		if not doc2.load_dir(dir):
			return false
		map_tree = [{"id": pack_id, "name": doc2.display_name, "parent": "", "tileset": "default"}]
		start_map = pack_id
		maps[pack_id] = doc2
		var ts: Dictionary = _read_json("%s/tileset.json" % dir)
		if ts.is_empty():
			tilesets["default"] = _default_tileset()
		else:
			tilesets["default"] = ts
	if start_map.is_empty() or not maps.has(start_map):
		start_map = str(map_tree[0]["id"]) if not map_tree.is_empty() else ""
	dirty = false
	return not maps.is_empty()


func save_dir(dir: String = "") -> bool:
	if dir.strip_edges() != "":
		root = dir.rstrip("/").rstrip("\\")
	if root.is_empty():
		root = pack_dir_for(pack_id)
	if not _ensure_dir(root):
		return false
	if not _ensure_dir("%s/maps" % root):
		return false
	if not _ensure_dir("%s/tilesets" % root):
		return false
	if not _ensure_dir("%s/assets/tilesheet" % root):
		return false
	if not _ensure_dir("%s/assets/charset" % root):
		return false
	if not _ensure_dir("%s/assets/audio" % root):
		return false
	var pack_obj := {
		"format": FORMAT,
		"id": pack_id,
		"name": pack_name,
		"tile_size": tile_size,
		"start_map": start_map,
		"map_tree": map_tree,
		"deps": [],
	}
	if not _write_json("%s/pack.json" % root, pack_obj):
		return false
	for ts_id in tilesets.keys():
		_write_json("%s/tilesets/%s.json" % [root, str(ts_id)], tilesets[ts_id])
	for mid in maps.keys():
		var doc: RefCounted = maps[mid]
		var mdir := "%s/maps/%s" % [root, mid]
		if not doc.save_dir(mdir):
			return false
	dirty = false
	return true


func get_map(id: String) -> RefCounted:
	return maps.get(id, null)


func add_map(id: String, name: String, parent: String = "", w: int = 20, h: int = 15) -> bool:
	id = id.strip_edges()
	if id.is_empty() or maps.has(id):
		return false
	var doc: RefCounted = MapDocument.new()
	doc.setup_blank(id, name, w, h, tile_size)
	doc.parent_id = parent
	maps[id] = doc
	map_tree.append({"id": id, "name": name, "parent": parent, "tileset": "default"})
	dirty = true
	return true


func remove_map(id: String) -> bool:
	if not maps.has(id):
		return false
	# Keep children, reparent to this node's parent.
	var parent := ""
	for item in map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			parent = str(item.get("parent", ""))
			break
	var next_tree: Array = []
	for item2 in map_tree:
		if typeof(item2) != TYPE_DICTIONARY:
			continue
		var mid := str(item2.get("id", ""))
		if mid == id:
			continue
		if str(item2.get("parent", "")) == id:
			item2["parent"] = parent
			var child: RefCounted = maps.get(mid)
			if child:
				child.parent_id = parent
		next_tree.append(item2)
	map_tree = next_tree
	maps.erase(id)
	if start_map == id:
		start_map = str(map_tree[0]["id"]) if not map_tree.is_empty() else ""
	dirty = true
	return true


func set_parent(id: String, parent: String) -> bool:
	if id == parent:
		return false
	if parent != "" and not maps.has(parent):
		return false
	# Prevent cycles.
	var walk := parent
	while walk != "":
		if walk == id:
			return false
		walk = _parent_of(walk)
	for item in map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			item["parent"] = parent
			var doc: RefCounted = maps.get(id)
			if doc:
				doc.parent_id = parent
			dirty = true
			return true
	return false


func rename_map(id: String, new_name: String) -> void:
	for item in map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			item["name"] = new_name
			var doc: RefCounted = maps.get(id)
			if doc:
				doc.display_name = new_name
			dirty = true
			return


func _parent_of(id: String) -> String:
	for item in map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			return str(item.get("parent", ""))
	return ""


func _load_tilesets_dir() -> void:
	var tdir := "%s/tilesets" % root
	var abs_t := _abs(tdir)
	if DirAccess.dir_exists_absolute(abs_t):
		var da := DirAccess.open(abs_t)
		if da:
			da.list_dir_begin()
			var fn := da.get_next()
			while fn != "":
				if not da.current_is_dir() and fn.ends_with(".json"):
					var tid := fn.get_basename()
					var ts: Dictionary = _read_json("%s/%s" % [tdir, fn])
					if not ts.is_empty():
						tilesets[tid] = ts
				fn = da.get_next()
	if tilesets.is_empty():
		var legacy: Dictionary = _read_json("%s/tileset.json" % root)
		if not legacy.is_empty():
			tilesets["default"] = legacy
		else:
			tilesets["default"] = _default_tileset()


func _default_tileset() -> Dictionary:
	var demo: Dictionary = _read_json("res://demo_map/tileset.json")
	if not demo.is_empty():
		return demo
	return {"id": 1, "name": "default", "mode": 1, "flags": [], "tilesetNames": ["", "", "", "", "", "", "", "", ""]}


func _slug(s: String) -> String:
	var t := s.strip_edges().to_lower()
	t = t.replace(" ", "_")
	var out := ""
	for i in range(t.length()):
		var ch := t.substr(i, 1)
		if ch >= "a" and ch <= "z":
			out += ch
		elif ch >= "0" and ch <= "9":
			out += ch
		elif ch == "_" or ch == "-":
			out += ch
	return out if out != "" else "map"


func _read_json(path: String) -> Dictionary:
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


func _write_json(path: String, obj: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(obj, "\t"))
	return true


func _ensure_dir(path: String) -> bool:
	var abs_path := _abs(path)
	if DirAccess.dir_exists_absolute(abs_path):
		return true
	return DirAccess.make_dir_recursive_absolute(abs_path) == OK


func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
