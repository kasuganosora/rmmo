extends RefCounted
## Content pack: map tree + tilesets + per-map documents + pack-local assets.

const MapDocument = preload("res://scripts/editor/map_document.gd")
const Rtp = preload("res://scripts/editor/rtp.gd")

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


static func map_editor_dev() -> bool:
	return bool(ProjectSettings.get_setting("rmmo/map_editor_dev", false))


static func allow_write_root(path: String) -> bool:
	var abs_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	abs_path = abs_path.replace("\\", "/").rstrip("/")
	var res_abs := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if abs_path == res_abs or abs_path.begins_with(res_abs + "/"):
		return map_editor_dev()
	return true


static func list_user_packs() -> Array:
	var out: Array = []
	var root := USER_PACKS
	var abs_root := ProjectSettings.globalize_path(root)
	if not DirAccess.dir_exists_absolute(abs_root):
		return out
	var da := DirAccess.open(abs_root)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and not name.begins_with("."):
			var pjson := "%s/%s/pack.json" % [root, name]
			if FileAccess.file_exists(pjson) or FileAccess.file_exists(ProjectSettings.globalize_path(pjson)):
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pjson if FileAccess.file_exists(pjson) else ProjectSettings.globalize_path(pjson)))
				var pid := name
				var pname := name
				if typeof(parsed) == TYPE_DICTIONARY:
					pid = str(parsed.get("id", name))
					pname = str(parsed.get("name", pid))
				out.append({"id": pid, "name": pname, "root": "%s/%s" % [root, name]})
		name = da.get_next()
	return out


func is_legacy_flat() -> bool:
	return not map_tree.is_empty() and FileAccess.file_exists("%s/map.json" % root) and not DirAccess.dir_exists_absolute(_abs("%s/maps" % root))


func new_blank(p_id: String, p_name: String, w: int = 20, h: int = 15) -> void:
	pack_id = _slug(p_id)
	pack_name = p_name
	root = pack_dir_for(pack_id)
	start_map = "Map001"
	tile_size = 48
	tilesets = Rtp.load_tilesets()
	var ts_id := Rtp.default_tileset_id()
	if tilesets.is_empty():
		tilesets = {"default": _default_tileset()}
		ts_id = "default"
	elif not tilesets.has(ts_id):
		ts_id = str(tilesets.keys()[0])
	map_tree = [{"id": "Map001", "name": "地图1", "parent": "", "tileset": ts_id}]
	var doc: RefCounted = MapDocument.new()
	doc.setup_blank("Map001", "地图1", w, h, tile_size)
	doc.tileset_id = ts_id
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
	if Rtp.merge_into(tilesets):
		dirty = true
	else:
		dirty = false
	return not maps.is_empty()


func save_as(new_id: String, new_name: String = "") -> bool:
	var old_root := root
	pack_id = _slug(new_id)
	if new_name.strip_edges() != "":
		pack_name = new_name.strip_edges()
	root = pack_dir_for(pack_id)
	if not save_dir(root):
		return false
	if old_root != "" and _abs(old_root) != _abs(root):
		_copy_tree("%s/assets" % old_root, "%s/assets" % root)
	return true


func map_is_dirty(map_id: String) -> bool:
	var d: RefCounted = maps.get(map_id)
	return d != null and bool(d.dirty)


func asset_folder(kind: String) -> String:
	match kind:
		"charset":
			return "charset"
		"faces":
			return "faces"
		"parallax":
			return "parallax"
		"audio":
			return "audio"
		"audio/bgm", "bgm":
			return "audio/bgm"
		"audio/bgs", "bgs":
			return "audio/bgs"
		"audio/me", "me":
			return "audio/me"
		"audio/se", "se":
			return "audio/se"
		_:
			if kind.begins_with("audio/"):
				return kind
			return "tilesheet"


func import_asset_file(src_path: String, kind: String) -> String:
	var sub := asset_folder(kind)
	var ext := src_path.get_extension().to_lower()
	var id := src_path.get_file().get_basename()
	if id.strip_edges() == "":
		return ""
	if root.is_empty():
		root = pack_dir_for(pack_id)
	var dest := "%s/assets/%s/%s.%s" % [root, sub, id, ext if ext != "" else "png"]
	var abs_dest := _abs(dest)
	DirAccess.make_dir_recursive_absolute(abs_dest.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty() and not FileAccess.file_exists(src_path):
		var glob := ProjectSettings.globalize_path(src_path)
		bytes = FileAccess.get_file_as_bytes(glob)
	var f := FileAccess.open(abs_dest, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	dirty = true
	return id


func list_assets(kind: String) -> Array:
	var out: Array = []
	if root.is_empty():
		return out
	var dir := "%s/assets/%s" % [root, asset_folder(kind)]
	var abs_d := _abs(dir)
	if not DirAccess.dir_exists_absolute(abs_d):
		return out
	var da := DirAccess.open(abs_d)
	if da == null:
		return out
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and not fn.begins_with("."):
			out.append({
				"id": fn.get_basename(),
				"file": fn,
				"path": "%s/%s" % [dir, fn],
				"abs": "%s/%s" % [abs_d, fn],
			})
		fn = da.get_next()
	out.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return out


func delete_asset(kind: String, file_name: String) -> bool:
	if root.is_empty() or file_name.strip_edges() == "":
		return false
	var path := _abs("%s/assets/%s/%s" % [root, asset_folder(kind), file_name])
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err == OK:
		dirty = true
		return true
	return false


func set_tileset_slot(ts_id: String, slot: int, sheet_name: String) -> bool:
	if not tilesets.has(ts_id) or slot < 0 or slot > 8:
		return false
	var ts: Dictionary = tilesets[ts_id]
	var names_v: Variant = ts.get("tilesetNames", [])
	var arr: Array = names_v if typeof(names_v) == TYPE_ARRAY else []
	while arr.size() < 9:
		arr.append("")
	arr[slot] = sheet_name
	ts["tilesetNames"] = arr
	tilesets[ts_id] = ts
	dirty = true
	return true


func adopt_as_user_pack(new_id: String, new_name: String = "") -> bool:
	## After load_dir(res://demo_map), write a nested copy under user:// without touching the source.
	pack_id = _slug(new_id)
	if new_name.strip_edges() != "":
		pack_name = new_name.strip_edges()
	root = pack_dir_for(pack_id)
	dirty = true
	return save_dir(root)


func save_dir(dir: String = "") -> bool:
	if dir.strip_edges() != "":
		root = dir.rstrip("/").rstrip("\\")
	if root.is_empty():
		root = pack_dir_for(pack_id)
	if not allow_write_root(root):
		push_warning("content_pack: refuse save to res:// (map_editor_dev off)")
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


func next_map_id() -> String:
	var n := 1
	while maps.has("Map%03d" % n):
		n += 1
	return "Map%03d" % n


func duplicate_map(src_id: String) -> String:
	var src: RefCounted = maps.get(src_id)
	if src == null or not src.has_method("clone"):
		return ""
	var nid := next_map_id()
	var parent := _parent_of(src_id)
	var d: RefCounted = src.clone(nid, str(src.display_name) + " 复制")
	d.parent_id = parent
	maps[nid] = d
	map_tree.append({"id": nid, "name": d.display_name, "parent": parent, "tileset": str(d.tileset_id)})
	dirty = true
	return nid


func add_map(id: String, name: String, parent: String = "", w: int = 20, h: int = 15, tileset: String = "") -> bool:
	id = id.strip_edges()
	if id.is_empty() or maps.has(id):
		return false
	var doc: RefCounted = MapDocument.new()
	doc.setup_blank(id, name, w, h, tile_size)
	doc.parent_id = parent
	maps[id] = doc
	var ts_id := tileset
	if ts_id == "" or not tilesets.has(ts_id):
		ts_id = Rtp.default_tileset_id() if tilesets.has(Rtp.default_tileset_id()) else (str(tilesets.keys()[0]) if not tilesets.is_empty() else "default")
	doc.tileset_id = ts_id
	map_tree.append({"id": id, "name": name, "parent": parent, "tileset": ts_id})
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


func set_map_tileset(map_id: String, ts_id: String) -> bool:
	if not maps.has(map_id) or not tilesets.has(ts_id):
		return false
	for item in map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == map_id:
			item["tileset"] = ts_id
			var doc: RefCounted = maps.get(map_id)
			if doc:
				doc.tileset_id = ts_id
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


func _copy_tree(from_dir: String, to_dir: String) -> void:
	var abs_from := _abs(from_dir)
	if not DirAccess.dir_exists_absolute(abs_from):
		return
	DirAccess.make_dir_recursive_absolute(_abs(to_dir))
	var da := DirAccess.open(abs_from)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n.begins_with("."):
			n = da.get_next()
			continue
		var src := "%s/%s" % [abs_from, n]
		var dst := "%s/%s" % [_abs(to_dir), n]
		if da.current_is_dir():
			_copy_tree(src, dst)
		else:
			DirAccess.copy_absolute(src, dst)
		n = da.get_next()


func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
