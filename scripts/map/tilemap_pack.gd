extends RefCounted
## Loads a tilemap_pack_v1 folder (pack.json + map + tileset + tile sheets).

const MapCollision = preload("res://scripts/map/map_collision.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")

var pack_dir: String = ""
var tile_size: int = 48
var width: int = 0
var height: int = 0
var data: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var tileset_names: PackedStringArray = PackedStringArray()
## Array of 9 Image (may contain nulls)
var sheets: Array = []
var collision: RefCounted = null
var map_id: String = ""
## Warp entries from pack.json (from_cell -> to_pack/to_cell/facing).
var warps: Array = []
## NPC placements from npcs.json (or pack.json "npcs").
var npcs: Array = []
## Map events from events.json (or pack.json "events" / events_file). MV-inspired subset.
var events: Array = []
## Optional charset_root override from pack.json.
var charset_root: String = ""
## Extra layers (MapXXX.ext.json). Empty object if file missing.
var ext: RefCounted = null
## Nested content pack: which map id to load (empty = start_map / flat map.json).
var load_map_id: String = ""
var bgm: String = ""
var light_preset: int = 0
var light_fx_color: Color = Color(1, 1, 1, 1)
var environment: String = MapExt.ENV_OUTDOOR
var streaming: bool = false
var chunk_map_dir: String = ""
var chunk_dir: String = ""
var overview_path: String = ""


static func load_pack(p_pack_dir: String, p_map_id: String = "") -> RefCounted:
	var pack := new()
	pack.pack_dir = p_pack_dir.rstrip("/")
	pack.load_map_id = p_map_id
	if not pack._load():
		push_error("tilemap_pack: failed to load %s" % p_pack_dir)
	return pack


func _load() -> bool:
	var pack_path := "%s/pack.json" % pack_dir
	var pack_data: Dictionary = _read_json(pack_path)
	if pack_data.is_empty():
		return false
	tile_size = int(pack_data.get("tile_size", 48))
	map_id = pack_dir.get_file()
	var map_rel: String = str(pack_data.get("map", "map.json"))
	var tileset_rel: String = str(pack_data.get("tileset", "tileset.json"))
	var tiles_rel: String = str(pack_data.get("tiles_dir", "tiles"))
	var nested := _is_nested_pack(pack_data)
	if nested:
		var mid := load_map_id.strip_edges()
		if mid.is_empty():
			mid = str(pack_data.get("start_map", "")).strip_edges()
		if mid.is_empty():
			var tree_v: Variant = pack_data.get("map_tree", [])
			if typeof(tree_v) == TYPE_ARRAY and not (tree_v as Array).is_empty():
				var first: Variant = (tree_v as Array)[0]
				if typeof(first) == TYPE_DICTIONARY:
					mid = str(first.get("id", ""))
		map_id = mid if mid != "" else map_id
		map_rel = "maps/%s/map.json" % map_id
		var ts_id := "default"
		var tree2: Variant = pack_data.get("map_tree", [])
		if typeof(tree2) == TYPE_ARRAY:
			for item in tree2:
				if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == map_id:
					ts_id = str(item.get("tileset", "default"))
					break
		tileset_rel = "tilesets/%s.json" % ts_id
		if not FileAccess.file_exists("%s/%s" % [pack_dir, tileset_rel]):
			tileset_rel = "tileset.json"
		tiles_rel = "assets/tilesheet"
		pack_data["npcs_file"] = "maps/%s/npcs.json" % map_id
		pack_data["events_file"] = "maps/%s/events.json" % map_id

	var map_data: Dictionary = _read_json("%s/%s" % [pack_dir, map_rel])
	var tileset_data: Dictionary = _read_json("%s/%s" % [pack_dir, tileset_rel])
	if map_data.is_empty() or tileset_data.is_empty():
		return false

	width = int(map_data.get("width", 0))
	height = int(map_data.get("height", 0))
	var map_abs_dir := "%s/%s" % [pack_dir, map_rel.get_base_dir()]
	if map_rel.get_base_dir() == "" or map_rel.get_base_dir() == ".":
		map_abs_dir = pack_dir
	chunk_map_dir = map_abs_dir
	chunk_dir = MapChunkStore.chunks_dir(map_abs_dir)
	overview_path = MapChunkStore.overview_path(map_abs_dir)
	var chunks_on_disk := DirAccess.dir_exists_absolute(chunk_dir) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(chunk_dir))
	streaming = str(map_data.get("dataEncoding", "")) == "chunks" or chunks_on_disk
	if streaming:
		data = PackedInt32Array()
	else:
		data = _to_int32_array(map_data.get("data", []))
		var bin_path := "%s/%s" % [pack_dir, map_rel.get_basename() + ".data.bin"]
		if FileAccess.file_exists(bin_path):
			data = _load_data_bin(bin_path, width * height * 6)
		var need: int = width * height * 6
		if need > 0 and data.size() < need:
			data.resize(need)
	flags = _to_int32_array(tileset_data.get("flags", []))
	tileset_names = PackedStringArray()
	var names_v: Variant = tileset_data.get("tilesetNames", [])
	if typeof(names_v) == TYPE_ARRAY:
		for n in names_v:
			tileset_names.append(str(n))

	sheets.clear()
	sheets.resize(9)
	for i in range(mini(9, tileset_names.size())):
		var name: String = tileset_names[i]
		if name.is_empty():
			sheets[i] = null
			continue
		sheets[i] = _load_sheet_image(name, tiles_rel)

	var ext_rel := MapExt.ext_path_for(map_rel)
	ext = MapExt.load_file("%s/%s" % [pack_dir, ext_rel], width, height)
	var col = MapCollision.new()
	if streaming:
		col.setup_streaming(width, height, flags, int(map_data.get("chunkCells", MapChunkStore.CHUNK_CELLS)))
	else:
		col.setup(width, height, data, flags)
	if col.has_method("set_ext"):
		col.set_ext(ext)
	collision = col
	var map_dir := map_rel.get_base_dir()
	var map_warps_path := "%s/warps.json" % pack_dir
	if map_dir != "" and map_dir != ".":
		map_warps_path = "%s/%s/warps.json" % [pack_dir, map_dir]
	var wrd: Dictionary = {}
	if FileAccess.file_exists(map_warps_path) or FileAccess.file_exists(ProjectSettings.globalize_path(map_warps_path)):
		wrd = _read_json(map_warps_path)
	if typeof(wrd) == TYPE_DICTIONARY and typeof(wrd.get("warps")) == TYPE_ARRAY:
		warps = _parse_warps(wrd.get("warps", []))
	else:
		warps = _parse_warps(pack_data.get("warps", []))
	charset_root = str(pack_data.get("charset_root", "")).strip_edges()
	bgm = str(map_data.get("bgm", "")).strip_edges()
	light_preset = int(map_data.get("light_preset", 0))
	if map_data.has("environment"):
		environment = MapExt.normalize_environment(map_data.get("environment"))
	elif map_data.has("indoor"):
		environment = MapExt.normalize_environment(map_data.get("indoor"))
	else:
		environment = MapExt.ENV_OUTDOOR
	if ext != null and "light_color" in ext:
		light_fx_color = ext.light_color
	npcs = _load_npcs(pack_data)
	events = _load_events(pack_data)
	if collision != null and collision.has_method("apply_npc_blocks"):
		collision.apply_npc_blocks(npcs)
		collision.apply_npc_blocks(_event_block_entries())
	return width > 0 and height > 0


func load_chunk_data(cx: int, cy: int) -> PackedInt32Array:
	if chunk_map_dir == "":
		return PackedInt32Array()
	return MapChunkStore.load_chunk(chunk_map_dir, cx, cy)


func _is_nested_pack(pack_data: Dictionary) -> bool:
	if str(pack_data.get("format", "")) == "content_pack_v1":
		return true
	var maps_dir := "%s/maps" % pack_dir
	if DirAccess.dir_exists_absolute(maps_dir):
		return true
	var glob := ProjectSettings.globalize_path(maps_dir)
	return glob != maps_dir and DirAccess.dir_exists_absolute(glob)




func _load_npcs(pack_data: Dictionary) -> Array:
	var raw: Variant = pack_data.get("npcs", null)
	if typeof(raw) == TYPE_ARRAY:
		return _parse_npcs(raw)
	var npcs_rel: String = str(pack_data.get("npcs_file", "npcs.json"))
	var npcs_path := "%s/%s" % [pack_dir, npcs_rel]
	if not FileAccess.file_exists(npcs_path):
		var abs_path := ProjectSettings.globalize_path(npcs_path)
		if not FileAccess.file_exists(abs_path):
			return []
		npcs_path = abs_path
	var npcs_data: Dictionary = _read_json(npcs_path)
	if npcs_data.is_empty():
		return []
	return _parse_npcs(npcs_data.get("npcs", []))


static func _parse_npcs(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for item in v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = item
		var cell_v: Variant = n.get("cell", {})
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = cell_v
		var charset: String = str(n.get("charset", "")).strip_edges()
		if charset.is_empty():
			continue
		var entry := {
			"id": str(n.get("id", "")),
			"name": str(n.get("name", "")),
			"cell": {"x": int(c.get("x", 0)), "y": int(c.get("y", 0))},
			"charset": charset,
			"index": int(n.get("index", 0)),
			"direction": int(n.get("direction", 2)),
			"through": bool(n.get("through", false)),
			"wander": bool(n.get("wander", false)),
			"interact_text": str(n.get("interact_text", "")),
			"hostile": bool(n.get("hostile", false)),
			# Default false = 被动; street_map sets aggressive:true for 主动 hostiles.
			"aggressive": bool(n.get("aggressive", false)),
			# Idle roam radius (cells) from home; 0 = stand still. Hostiles use server AI.
			"wander_radius": maxi(int(n.get("wander_radius", 0)), 0),
			# 0 = solo; same non-zero = pack assist on hit.
			"group_id": int(n.get("group_id", 0)),
			# Nameplate taxonomy: monster | normal | object (required for non-hostile plates).
			"kind": str(n.get("kind", "")).strip_edges(),
		}
		# Optional radar override (false = force-hide). Preserve when present.
		if n.has("radar"):
			entry["radar"] = bool(n.get("radar"))
		if n.has("nameplate"):
			entry["nameplate"] = bool(n.get("nameplate"))
		if n.has("level"):
			entry["level"] = maxi(int(n.get("level", 1)), 1)
		# Vendor shop id (MockServer try_interact → open_shop).
		if n.has("shop_id"):
			var sid := str(n.get("shop_id", "")).strip_edges()
			if sid != "":
				entry["shop_id"] = sid
		# Inline MV event shortcut (EventRuntime merges by id).
		if n.has("event") and typeof(n.get("event")) == TYPE_DICTIONARY:
			entry["event"] = (n.get("event") as Dictionary).duplicate(true)
		if n.has("leash_radius"):
			entry["leash_radius"] = int(n.get("leash_radius"))
		if n.has("respawn_sec"):
			entry["respawn_sec"] = float(n.get("respawn_sec"))
		out.append(entry)
	return out

func _event_block_entries() -> Array:
	var out: Array = []
	for item in events:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = item
		if bool(e.get("through", true)):
			continue
		out.append(e)
	return out


func _load_events(pack_data: Dictionary) -> Array:
	var raw: Variant = pack_data.get("events", null)
	if typeof(raw) == TYPE_ARRAY:
		return _parse_events(raw)
	var events_rel: String = str(pack_data.get("events_file", "events.json")).strip_edges()
	if events_rel.is_empty():
		events_rel = "events.json"
	var events_path := "%s/%s" % [pack_dir, events_rel]
	if not FileAccess.file_exists(events_path):
		var abs_path := ProjectSettings.globalize_path(events_path)
		if not FileAccess.file_exists(abs_path):
			return []
		events_path = abs_path
	var events_data: Dictionary = _read_json(events_path)
	if events_data.is_empty():
		return []
	return _parse_events(events_data.get("events", []))


static func _parse_events(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for item in v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = item
		var eid := str(e.get("id", "")).strip_edges()
		if eid.is_empty():
			continue
		var entry: Dictionary = e.duplicate(true)
		entry["id"] = eid
		var cell_v: Variant = e.get("cell", null)
		if typeof(cell_v) == TYPE_DICTIONARY:
			var c: Dictionary = cell_v
			entry["cell"] = {"x": int(c.get("x", 0)), "y": int(c.get("y", 0))}
		var trig := str(e.get("trigger", "action")).strip_edges()
		entry["trigger"] = trig
		entry["through"] = bool(e.get("through", false))
		var pages_v: Variant = e.get("pages", [])
		entry["pages"] = pages_v if typeof(pages_v) == TYPE_ARRAY else []
		out.append(entry)
	return out


static func _parse_warps(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for item in v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var w: Dictionary = item
		var from_v: Variant = w.get("from_cell", {})
		var to_v: Variant = w.get("to_cell", {})
		if typeof(from_v) != TYPE_DICTIONARY or typeof(to_v) != TYPE_DICTIONARY:
			continue
		var from_c: Dictionary = from_v
		var to_c: Dictionary = to_v
		var to_map := str(w.get("to_map", w.get("to_map_id", "")))
		out.append({
			"from_cell": {"x": int(from_c.get("x", 0)), "y": int(from_c.get("y", 0))},
			"to_pack": str(w.get("to_pack", "")),
			"to_map": to_map,
			"to_map_id": to_map,
			"to_cell": {"x": int(to_c.get("x", 0)), "y": int(to_c.get("y", 0))},
			"facing": int(w.get("facing", 2)),
			"message": str(w.get("message", "")),
		})
	return out


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("tilemap_pack: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("tilemap_pack: invalid JSON %s" % path)
		return {}
	return parsed


static func _to_int32_array(v: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if typeof(v) != TYPE_ARRAY:
		return out
	var arr: Array = v
	out.resize(arr.size())
	for i in range(arr.size()):
		out[i] = int(arr[i])
	return out


## Pack-local tiles/ first (offline packs), then AssetManager content://tilesheet/{name} (MV hot-load).
func _load_sheet_image(sheet_name: String, tiles_rel: String) -> Image:
	var candidates: Array[String] = [
		"%s/%s/%s.png" % [pack_dir, tiles_rel, sheet_name],
		"%s/tiles/%s.png" % [pack_dir, sheet_name],
		"%s/assets/tilesheet/%s.png" % [pack_dir, sheet_name],
	]
	for img_path in candidates:
		if _pack_tile_exists(img_path):
			var local_img := _load_image(img_path, false)
			if local_img != null:
				return local_img
	var via_am := _load_tilesheet_via_asset_manager(sheet_name)
	if via_am != null:
		return via_am
	# Soft-miss: null sheet (map still loads); avoid Image.load ERROR spam.
	push_warning("tilemap_pack: missing tilesheet '%s' (pack + mv_img)" % sheet_name)
	return null


func _pack_tile_exists(path: String) -> bool:
	if ResourceLoader.exists(path):
		return true
	if FileAccess.file_exists(path):
		return true
	var abs_path := ProjectSettings.globalize_path(path)
	return abs_path != path and FileAccess.file_exists(abs_path)


func _load_data_bin(path: String, need: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if need > 0:
		out.resize(need)
		out.fill(0)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var n := int(f.get_32())
	var count := mini(n, need)
	for i in range(count):
		if f.eof_reached():
			break
		out[i] = f.get_32()
	return out


func _load_tilesheet_via_asset_manager(sheet_name: String) -> Image:
	var am := _asset_manager()
	if am == null:
		return null
	var cref := "content://tilesheet/%s" % sheet_name
	# Resolve path first — only load when file exists (avoids ensure() miss warnings).
	if am.has_method("path"):
		var resolved: String = str(am.path(cref)).strip_edges()
		if resolved != "" and FileAccess.file_exists(resolved):
			if am.has_method("load_image"):
				var img: Image = am.load_image(cref)
				if img != null:
					return img
			return _load_image(resolved, false)
		var alt := resolved.replace("\\", "/")
		if alt != resolved and FileAccess.file_exists(alt):
			return _load_image(alt, false)
	return null


func _asset_manager() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var tree := loop as SceneTree
		return tree.root.get_node_or_null("AssetManager")
	return null


static func _load_image(path: String, warn_missing: bool = true) -> Image:
	# Prefer imported Texture2D when available; fall back to raw file load.
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			var tex := res as Texture2D
			var img: Image = tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				return img
	var img2 := Image.new()
	var err: Error = img2.load(path)
	if err != OK:
		# Try absolute path via globalize
		var abs_path := ProjectSettings.globalize_path(path)
		err = img2.load(abs_path)
	if err != OK:
		if warn_missing:
			push_error("tilemap_pack: cannot load image %s (%s)" % [path, error_string(err)])
		return null
	if img2.is_compressed():
		img2.decompress()
	if img2.get_format() != Image.FORMAT_RGBA8:
		img2.convert(Image.FORMAT_RGBA8)
	return img2
