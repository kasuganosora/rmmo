extends RefCounted
## Extra content-editor MCP tools: inspect, paint shapes, maps, tilesets, entities.

const TileId = preload("res://scripts/map/tile_id.gd")
const TileBlit = preload("res://scripts/map/tile_blit.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")
const TilePalette = preload("res://scripts/editor/interface/tile_palette.gd")
const Rtp = preload("res://scripts/editor/infrastructure/rtp.gd")
const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const MapShapes = preload("res://scripts/editor/domain/map_shapes.gd")
const TileLabels = preload("res://scripts/editor/domain/tile_labels.gd")

const PAINT_CELLS_MAX := 16384
const TILES_RECT_MAX := 80
const MAP_MAX_SIDE := 16384
const MV_LAYER_NAMES := ["下层", "中层", "上层", "顶层", "阴影", "区域"]
const EntityOps = preload("res://scripts/editor/adapters/ops/entity_ops.gd")
const AssetOps = preload("res://scripts/editor/adapters/ops/asset_ops.gd")
const HistoryOps = preload("res://scripts/editor/adapters/ops/history_ops.gd")
const MapCrudOps = preload("res://scripts/editor/adapters/ops/map_crud_ops.gd")
const StampOps = preload("res://scripts/editor/adapters/ops/stamp_ops.gd")
const TilesOps = preload("res://scripts/editor/adapters/ops/tiles_ops.gd")
const PaintOps = preload("res://scripts/editor/adapters/ops/paint_ops.gd")
const MapSettingsOps = preload("res://scripts/editor/adapters/ops/map_settings_ops.gd")
const InspectOps = preload("res://scripts/editor/adapters/ops/inspect_ops.gd")
var _inspect_ops_logic: InspectOps = InspectOps.new(self)
var _map_settings_ops_logic: MapSettingsOps = MapSettingsOps.new(self)
var _paint_ops_logic: PaintOps = PaintOps.new(self)
var _tiles_ops_logic: TilesOps = TilesOps.new(self)
var _stamp_ops_logic: StampOps = StampOps.new(self)
var _map_crud_ops_logic: MapCrudOps = MapCrudOps.new(self)
var _history_ops_logic: HistoryOps = HistoryOps.new(self)
var _asset_ops_logic: AssetOps = AssetOps.new(self)
var _entity_ops_logic: EntityOps = EntityOps.new(self)

var mcp: Node = null

func tools_list() -> Array:
	if _op_modules.is_empty():
		_build_op_registry()
	var out: Array = []
	for m in _op_modules:
		out.append_array(m.tools())
	return out

var _op_modules: Array = []
var _op_registry: Dictionary = {}

func _build_op_registry() -> void:
	if _op_modules.is_empty():
		_op_modules = [
			_inspect_ops_logic, _map_settings_ops_logic, _paint_ops_logic,
			_tiles_ops_logic, _stamp_ops_logic, _map_crud_ops_logic,
			_history_ops_logic, _asset_ops_logic, _entity_ops_logic,
		]
	_op_registry = {}
	for m in _op_modules:
		for op in m.op_names():
			_op_registry[op] = m

func dispatch(name: String, args: Dictionary) -> Dictionary:
	if _op_registry.is_empty():
		_build_op_registry()
	var m: RefCounted = _op_registry.get(name)
	if m == null:
		return {"ok": false, "error": "unknown tool: %s" % name}
	return m.call(name, args)

func ed():
	return mcp.editor if mcp else null

func doc():
	return mcp._doc() if mcp else null

func pack():
	var e = ed()
	return e.pack if e else null

func list_assets_merged(kind: String) -> Array:
	var out: Array = []
	var seen := {}
	var p = pack()
	if p and p.has_method("list_assets"):
		for it in p.list_assets(kind):
			if typeof(it) == TYPE_DICTIONARY:
				var iid := str(it.get("id", ""))
				if iid != "" and not seen.has(iid):
					seen[iid] = true
					out.append(it)
	var folder := "tilesheet"
	if p and p.has_method("asset_folder"):
		folder = p.asset_folder(kind)
	var dirs: Array = ["%s/assets/%s" % [Rtp.content_root(), folder]]
	if kind == "charset":
		dirs.append(CharsetSheet.charset_root())
		dirs.append("%s/characters" % Rtp.content_root())
		dirs.append("%s/assets/charset" % Rtp.content_root())
	for dir in dirs:
		_scan_asset_dir(str(dir), kind, seen, out)
	out.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return out

func state_extra() -> Dictionary:
	var paint = _ensure_paint()
	var d = doc()
	var extra := {
		"layer_z": int(paint.layer_z) if paint else 0,
		"ext_layer": str(paint.ext_layer) if paint else "",
		"tile_id": int(paint.tile_id) if paint else 0,
		"tileset_id": str(d.tileset_id) if d else "",
		"start": {"x": int(d.start_cell.x), "y": int(d.start_cell.y)} if d else {"x": 0, "y": 0},
		"bgm": str(d.bgm) if d else "",
		"light_preset": int(d.light_preset) if d else 0,
		"has_stamp": bool(paint.has_stamp()) if paint else false,
		"environment": MapExt.normalize_environment(d.environment) if d and "environment" in d else MapExt.ENV_OUTDOOR,
		"indoor": d != null and "environment" in d and MapExt.normalize_environment(d.environment) == MapExt.ENV_INDOOR,
	}
	return extra

func paint_one(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	_apply_layer(args)
	var paint = _ensure_paint()
	paint.tool = PaintTools.Tool.PENCIL
	paint.exact_autotile = bool(args.get("exact", false))
	if args.has("tile_id") or args.has("id"):
		paint.tile_id = int(args.get("tile_id", args.get("id", 0)))
	var c: Vector2i = mcp._cell(args)
	var dirty: Array[Vector2i] = paint.apply_cell(d, c, bool(args.get("erase", false)))
	_touch(dirty)
	return mcp._ok({
		"x": c.x, "y": c.y, "z": paint.layer_z, "ext": str(paint.ext_layer),
		"tile_id": int(paint._read_cell(d, c)), "painted": dirty.size(),
	})

func set_meta_batch(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var bit := int(args.get("bit", 0))
	if bit <= 0:
		return mcp._err("bit required")
	var erase := bool(args.get("erase", false))
	var cells: Array[Vector2i] = []
	if typeof(args.get("cells", null)) == TYPE_ARRAY:
		for item in args.get("cells", []):
			if typeof(item) == TYPE_DICTIONARY:
				cells.append(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))))
			elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
				cells.append(Vector2i(int(item[0]), int(item[1])))
	elif args.has("w") or args.has("h") or args.has("x2") or args.has("y2"):
		var r: Dictionary = _clamp_rect(args, int(d.width), int(d.height), 256)
		if bool(r.get("error", false)):
			return mcp._err(str(r.get("msg", "bad rect")))
		for y in range(int(r.y), int(r.y) + int(r.h)):
			for x in range(int(r.x), int(r.x) + int(r.w)):
				cells.append(Vector2i(x, y))
	else:
		cells.append(mcp._cell(args))
	d.begin_undo_batch()
	var last := 0
	for c in cells:
		var cur: int = int(d.ext_tile("meta", c.x, c.y))
		var nxt := cur
		if erase:
			nxt = cur & ~bit
		else:
			nxt = cur | bit
			if bit == MapExt.META_FORCE_BLOCK:
				nxt &= ~MapExt.META_FORCE_PASS
			elif bit == MapExt.META_FORCE_PASS:
				nxt &= ~MapExt.META_FORCE_BLOCK
		d.set_ext_tile("meta", c.x, c.y, nxt)
		last = nxt
	d.end_undo_batch()
	_touch(cells)
	return mcp._ok({"updated": cells.size(), "bit": bit, "meta": last})

func _color_hex(v: Variant) -> String:
	var c := Color(1, 1, 1, 1)
	if typeof(v) == TYPE_COLOR:
		c = v
	return "#%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]

func _persist() -> void:
	var p = pack()
	if p != null and p.has_method("save_dir") and str(p.root).strip_edges() != "":
		p.save_dir()

func _ensure_paint():
	var e = ed()
	if e == null:
		return null
	if e.paint == null:
		e.paint = PaintTools.new()
		e.paint.tile_id = TileId.TILE_ID_A2
	return e.paint

func _apply_layer(args: Dictionary) -> void:
	var paint = _ensure_paint()
	if paint == null:
		return
	if args.has("ext") and str(args.get("ext", "")).strip_edges() != "":
		paint.layer_z = -1
		paint.ext_layer = str(args.get("ext", "")).strip_edges()
	elif args.has("z"):
		paint.layer_z = clampi(int(args.get("z", 0)), 0, 5)
		paint.ext_layer = ""

func _touch(cells: Array) -> void:
	var e = ed()
	if e == null:
		return
	if e.has_method("_refresh_dirty"):
		e._refresh_dirty(cells)
	elif e.get("map_field") != null and e.map_field.has_method("rebuild_dirty_cells"):
		e.map_field.rebuild_dirty_cells(cells)

func _switch_map(mid: String) -> void:
	var e = ed()
	if e == null:
		return
	if e.get("_tree") != null and e.has_method("_do_select_map"):
		e._do_select_map(mid)
		return
	e.current_map_id = mid
	if pack() != null:
		e.doc = pack().get_map(mid)

func _clamp_rect(args: Dictionary, gw: int, gh: int, max_side: int) -> Dictionary:
	var x0 := int(args.get("x", 0))
	var y0 := int(args.get("y", 0))
	var x1: int
	var y1: int
	if args.has("x2") or args.has("y2"):
		x1 = int(args.get("x2", x0))
		y1 = int(args.get("y2", y0))
	else:
		var w := maxi(int(args.get("w", 1)), 1)
		var h := maxi(int(args.get("h", 1)), 1)
		x1 = x0 + w - 1
		y1 = y0 + h - 1
	if x1 < x0:
		var t := x0
		x0 = x1
		x1 = t
	if y1 < y0:
		var t2 := y0
		y0 = y1
		y1 = t2
	x0 = clampi(x0, 0, gw - 1)
	y0 = clampi(y0, 0, gh - 1)
	x1 = clampi(x1, 0, gw - 1)
	y1 = clampi(y1, 0, gh - 1)
	var w2 := x1 - x0 + 1
	var h2 := y1 - y0 + 1
	if w2 > max_side or h2 > max_side:
		return {"error": true, "msg": "rect too large (max %d)" % max_side}
	return {"x": x0, "y": y0, "w": w2, "h": h2}

func _line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return cells

func _thicken(cells: Array[Vector2i], width: int) -> Array[Vector2i]:
	if width <= 1:
		return cells
	var r: int = int(width) / 2
	var seen := {}
	var out: Array[Vector2i] = []
	for c in cells:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := Vector2i(c.x + dx, c.y + dy)
				var k := "%d,%d" % [n.x, n.y]
				if seen.has(k):
					continue
				seen[k] = true
				out.append(n)
	return out

func _ellipse_cells(cx: int, cy: int, rx: int, ry: int, fill: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rx < 0:
		rx = 0
	if ry < 0:
		ry = 0
	var filled: Array[Vector2i] = []
	var rr := maxi(ry * ry, 1)
	for y in range(-ry, ry + 1):
		var span := int(floor(float(rx) * sqrt(maxf(0.0, 1.0 - float(y * y) / float(rr)))))
		for x in range(-span, span + 1):
			filled.append(Vector2i(cx + x, cy + y))
	if fill:
		return filled
	var inner: Array[Vector2i] = _ellipse_cells(cx, cy, maxi(rx - 1, 0), maxi(ry - 1, 0), true)
	var drop := {}
	for c in inner:
		drop["%d,%d" % [c.x, c.y]] = true
	for c2 in filled:
		if not drop.has("%d,%d" % [c2.x, c2.y]):
			out.append(c2)
	return out

func _flags() -> PackedInt32Array:
	var d = doc()
	if d == null or pack() == null:
		return PackedInt32Array()
	var ts: Dictionary = pack().tilesets.get(str(d.tileset_id), {})
	return _flags_of(ts)

func _flags_of(ts: Dictionary) -> PackedInt32Array:
	var flags := PackedInt32Array()
	var fv: Variant = ts.get("flags", [])
	if typeof(fv) == TYPE_ARRAY:
		var arr: Array = fv
		flags.resize(arr.size())
		for i in range(arr.size()):
			flags[i] = int(arr[i])
	elif typeof(fv) == TYPE_PACKED_INT32_ARRAY:
		flags = fv
	return flags

func _load_sheets(ts: Dictionary) -> Array:
	var sheets: Array = []
	sheets.resize(9)
	var names_v: Variant = ts.get("tilesetNames", [])
	var names: Array = names_v if typeof(names_v) == TYPE_ARRAY else []
	var am = Engine.get_main_loop().root.get_node_or_null("/root/AssetManager") if Engine.get_main_loop() else null
	for i in range(9):
		var n := str(names[i]) if i < names.size() else ""
		if n.strip_edges() == "":
			sheets[i] = null
			continue
		sheets[i] = _load_sheet(am, n)
	return sheets

func _load_sheet(am, sheet_name: String) -> Image:
	if am != null and am.has_method("path"):
		var cref := "content://tilesheet/%s" % sheet_name
		var resolved := str(am.path(cref)).strip_edges()
		if resolved != "" and FileAccess.file_exists(resolved):
			if am.has_method("load_image"):
				var via = am.load_image(cref)
				if via != null:
					return _rgba(via as Image)
			var img := Image.new()
			if img.load(resolved) == OK:
				return _rgba(img)
	var fallback := "%s/assets/tilesheet/%s.png" % [Rtp.content_root(), sheet_name]
	if FileAccess.file_exists(fallback):
		var img2 := Image.new()
		if img2.load(fallback) == OK:
			return _rgba(img2)
	return null

func _rgba(img: Image) -> Image:
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _compose_a(sheets: Array, flags: PackedInt32Array, tile_px: int) -> Image:
	var img := Image.create(8 * tile_px, 32 * tile_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.13, 1))
	TileBlit.ensure_tables()
	for row in range(16):
		for col in range(8):
			var id: int = TilePalette.a_cell_to_id(col, row)
			var preview := id
			if TileId.is_autotile(id):
				var kind := TileId.autotile_kind(id)
				var base: int = TileId.TILE_ID_A1 + kind * 48
				if TileId.is_waterfall_kind(kind) or TileId.is_wall_autotile(base):
					preview = base
				else:
					preview = mini(base + 46, TileId.TILE_ID_MAX - 1)
			TileBlit.blit_tile(img, preview, col * tile_px, row * tile_px, sheets, tile_px, tile_px, flags, 0)
	var a5 = sheets[4] if sheets.size() > 4 else null
	if a5 != null:
		var w := mini(a5.get_width(), 8 * tile_px)
		var h := mini(a5.get_height(), 16 * tile_px)
		img.blit_rect(a5, Rect2i(0, 0, w, h), Vector2i(0, 16 * tile_px))
	else:
		for row2 in range(16, 32):
			for col2 in range(8):
				var id5: int = TilePalette.a_cell_to_id(col2, row2)
				TileBlit.blit_tile(img, id5, col2 * tile_px, row2 * tile_px, sheets, tile_px, tile_px, flags, 0)
	return img

func _sheet_index(tab: String) -> int:
	match tab:
		"B":
			return 5
		"C":
			return 6
		"D":
			return 7
		"E":
			return 8
		_:
			return 4

func _tab_base(tab: String) -> int:
	match tab:
		"C":
			return TileId.TILE_ID_C
		"D":
			return TileId.TILE_ID_D
		"E":
			return TileId.TILE_ID_E
		_:
			return TileId.TILE_ID_B

func _a_sheet_name(id: int) -> String:
	if TileId.is_tile_a1(id):
		return "A1"
	if TileId.is_tile_a2(id):
		return "A2"
	if TileId.is_tile_a3(id):
		return "A3"
	if TileId.is_tile_a4(id):
		return "A4"
	if TileId.is_tile_a5(id):
		return "A5"
	return "A"

func _grid_image(img: Image, ts: int) -> void:
	if img == null or ts <= 0:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mix := 0.22
	var col := Color(1, 1, 1, 1)
	var gx := 0
	while gx < w:
		var px := mini(gx, w - 1)
		for y in range(h):
			var d: Color = img.get_pixel(px, y)
			img.set_pixel(px, y, d.lerp(col, mix))
		gx += ts
	var gy := 0
	while gy < h:
		var py := mini(gy, h - 1)
		for x in range(w):
			var d2: Color = img.get_pixel(x, py)
			img.set_pixel(x, py, d2.lerp(col, mix))
		gy += ts

func _png_payload(img: Image, extra: Dictionary, args: Dictionary, default_path: String) -> Dictionary:
	if img == null:
		return mcp._err("render failed")
	var max_px: int = int(args.get("max_px", 1280))
	if max_px <= 0:
		max_px = 1280
	extra["src_px_w"] = img.get_width()
	extra["src_px_h"] = img.get_height()
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > max_px:
		var sc := float(max_px) / float(longest)
		img.resize(maxi(1, int(img.get_width() * sc)), maxi(1, int(img.get_height() * sc)), Image.INTERPOLATE_NEAREST)
	var save_path := str(args.get("path", "")).strip_edges()
	if save_path == "":
		save_path = ProjectSettings.globalize_path(default_path)
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var save_err := img.save_png(save_path)
	var png: PackedByteArray = img.save_png_to_buffer()
	if png.is_empty():
		return mcp._err("png encode failed")
	extra["px_w"] = img.get_width()
	extra["px_h"] = img.get_height()
	extra["path"] = save_path
	extra["saved"] = save_err == OK
	extra["png_base64"] = Marshalls.raw_to_base64(png)
	return mcp._ok(extra)

func _parse_color(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_STRING:
		var s := str(v).strip_edges()
		if s.begins_with("#"):
			return Color.html(s)
		var parts := s.split(",")
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), 1.0)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return Color(float(d.get("r", 1)), float(d.get("g", 1)), float(d.get("b", 1)), float(d.get("a", 1)))
	return fallback

func _pass_kind(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), 0, 2)
	match str(v).strip_edges().to_lower():
		"x", "block", "wall", "×":
			return TileId.PASS_X
		"star", "upper", "★", "*":
			return TileId.PASS_STAR
		_:
			return TileId.PASS_O

func _scan_asset_dir(dir: String, kind: String, seen: Dictionary, out: Array) -> void:
	var abs_d := dir
	if dir.begins_with("res://") or dir.begins_with("user://"):
		abs_d = ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_d):
		return
	var da := DirAccess.open(abs_d)
	if da == null:
		return
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and not fn.begins_with("."):
			var iid := fn.get_basename()
			if iid != "" and not seen.has(iid):
				seen[iid] = true
				out.append({"id": iid, "file": fn, "path": "%s/%s" % [dir.replace("\\", "/"), fn], "abs": "%s/%s" % [abs_d.replace("\\", "/"), fn], "source": "rtp"})
		fn = da.get_next()
