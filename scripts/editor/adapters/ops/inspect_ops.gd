extends RefCounted
## Domain ops: inspect/query (get_tile(s), list entities/layers/tilesets, map settings, find, previews, weather).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")
const TilePalette = preload("res://scripts/editor/interface/tile_palette.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const TileLabels = preload("res://scripts/editor/domain/tile_labels.gd")
const TILES_RECT_MAX := 80
const MV_LAYER_NAMES := ["下层", "中层", "上层", "顶层", "阴影", "区域"]

func get_tile(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var c: Vector2i = ctrl.mcp._cell(args)
	var z_tiles: Array = []
	for z in range(6):
		z_tiles.append(int(d.tile(c.x, c.y, z)))
	var ext = {}
	for id in MapExt.LAYER_IDS:
		ext[id] = int(d.ext_tile(id, c.x, c.y))
	var pass_st = -1
	var field = ctrl.ed().get("map_field") if ctrl.ed() and "map_field" in ctrl.ed() else null
	if field != null and field.has_method("edit_cell_passable"):
		pass_st = int(field.edit_cell_passable(c.x, c.y))
	var flags: PackedInt32Array = ctrl._flags()
	var t0: int = z_tiles[0]
	var flag0: int = int(flags[t0]) if t0 >= 0 and t0 < flags.size() else 0
	return ctrl.mcp._ok({
		"x": c.x, "y": c.y,
		"z": z_tiles,
		"ext": ext,
		"meta": int(ext.get("meta", 0)),
		"entity": d.entity_at(c),
		"pass": pass_st,
		"flag0": flag0,
	})



func get_tiles_rect(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var r: Dictionary = ctrl._clamp_rect(args, int(d.width), int(d.height), TILES_RECT_MAX)
	if bool(r.get("error", false)):
		return ctrl.mcp._err(str(r.get("msg", "bad rect")))
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	var rows: Array = []
	for y in range(int(r.y), int(r.y) + int(r.h)):
		var row: Array = []
		for x in range(int(r.x), int(r.x) + int(r.w)):
			row.append(int(paint._read_cell(d, Vector2i(x, y))))
		rows.append(row)
	return ctrl.mcp._ok({
		"x": int(r.x), "y": int(r.y), "w": int(r.w), "h": int(r.h),
		"z": int(paint.layer_z), "ext": str(paint.ext_layer),
		"tiles": rows,
	})



func list_entities(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var filter = str(args.get("kind", "")).strip_edges().to_lower()
	var has_box = args.has("w") or args.has("h") or args.has("x") or args.has("y")
	var x0 = int(args.get("x", 0))
	var y0 = int(args.get("y", 0))
	var x1 = x0 + int(args.get("w", d.width)) - 1
	var y1 = y0 + int(args.get("h", d.height)) - 1
	var out: Array = []
	if filter == "" or filter == "event":
		for ev in d.events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var cell: Vector2i = ctrl.mcp._entity_cell(ev.get("cell", {}))
			if has_box and (cell.x < x0 or cell.y < y0 or cell.x > x1 or cell.y > y1):
				continue
			out.append({"kind": "event", "x": cell.x, "y": cell.y, "id": str(ev.get("id", "")), "trigger": str(ev.get("trigger", ""))})
	if filter == "" or filter == "npc":
		for n in d.npcs:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var cell2: Vector2i = ctrl.mcp._entity_cell(n.get("cell", {}))
			if has_box and (cell2.x < x0 or cell2.y < y0 or cell2.x > x1 or cell2.y > y1):
				continue
			out.append({
				"kind": "npc", "x": cell2.x, "y": cell2.y,
				"id": str(n.get("id", "")), "name": str(n.get("name", "")),
				"hostile": bool(n.get("hostile", false)), "npc_kind": str(n.get("kind", "")),
			})
	if filter == "" or filter == "warp":
		for w in d.warps:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var cell3: Vector2i = ctrl.mcp._entity_cell(w.get("from_cell", {}))
			if has_box and (cell3.x < x0 or cell3.y < y0 or cell3.x > x1 or cell3.y > y1):
				continue
			out.append({
				"kind": "warp", "x": cell3.x, "y": cell3.y,
				"to_map": str(w.get("to_map", w.get("to_map_id", ""))),
			})
	return ctrl.mcp._ok({"count": out.size(), "entities": out})



func list_layers(_args := {}) -> Dictionary:
	var paint = ctrl._ensure_paint()
	var rows: Array = []
	for z in range(6):
		rows.append({
			"id": "z%d" % z, "z": z, "name": MV_LAYER_NAMES[z] if z < MV_LAYER_NAMES.size() else str(z),
			"current": paint.layer_z == z and str(paint.ext_layer) == "",
		})
	for id in MapExt.LAYER_IDS:
		rows.append({
			"id": id, "ext": id, "name": MapExt.layer_label(id),
			"current": paint.layer_z < 0 and str(paint.ext_layer) == id,
		})
	return ctrl.mcp._ok({"layers": rows, "z": paint.layer_z, "ext": str(paint.ext_layer)})



func list_tilesets(_args := {}) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var out: Array = []
	var keys: Array = p.tilesets.keys()
	keys.sort()
	var cur = ""
	var d = ctrl.doc()
	if d != null:
		cur = str(d.tileset_id)
	for k in keys:
		var ts: Dictionary = p.tilesets[k] if typeof(p.tilesets[k]) == TYPE_DICTIONARY else {}
		out.append({
			"id": str(k),
			"name": p.tileset_label(str(k)) if p.has_method("tileset_label") else str(ts.get("name", k)),
			"sheets": ts.get("tilesetNames", []),
			"current": str(k) == cur,
		})
	return ctrl.mcp._ok({"tilesets": out, "current": cur})



func get_map_settings(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	var p = ctrl.pack()
	if d == null:
		return ctrl.mcp._err("no map")
	var fx: Color = d.light_fx_color if "light_fx_color" in d else Color(1, 1, 1, 1)
	return ctrl.mcp._ok({
		"map_id": str(d.map_id),
		"name": str(d.display_name),
		"width": int(d.width),
		"height": int(d.height),
		"tile_size": int(d.tile_size),
		"tileset_id": str(d.tileset_id),
		"start": {"x": int(d.start_cell.x), "y": int(d.start_cell.y)},
		"bgm": str(d.bgm),
		"light_preset": int(d.light_preset),
		"light_fx_color": "#%02x%02x%02x" % [int(fx.r * 255.0), int(fx.g * 255.0), int(fx.b * 255.0)],
		"water_through": bool(d.water_through) if "water_through" in d else false,
		"far_scroll": {"x": d.far_scroll.x, "y": d.far_scroll.y} if "far_scroll" in d else {"x": 0, "y": 0},
		"start_map": str(p.start_map) if p else "",
		"parent": str(d.parent_id) if "parent_id" in d else "",
		"environment": MapExt.normalize_environment(d.environment) if "environment" in d else MapExt.ENV_OUTDOOR,
		"indoor": MapExt.normalize_environment(d.environment if "environment" in d else "") == MapExt.ENV_INDOOR,
	})



func preview_tileset(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var ts_id = str(args.get("tileset_id", "")).strip_edges()
	if ts_id == "" and ctrl.doc() != null:
		ts_id = str(ctrl.doc().tileset_id)
	if ts_id == "" or not p.tilesets.has(ts_id):
		return ctrl.mcp._err("no tileset")
	var tab = str(args.get("tab", "A")).strip_edges().to_upper()
	if tab == "":
		tab = "A"
	var ts: Dictionary = p.tilesets[ts_id] if typeof(p.tilesets[ts_id]) == TYPE_DICTIONARY else {}
	var sheets: Array = ctrl._load_sheets(ts)
	var flags = ctrl._flags_of(ts)
	var tile_px = 48
	if ctrl.doc() != null:
		tile_px = maxi(int(ctrl.doc().tile_size), 1)
	var img: Image
	var catalog: Array = []
	if tab == "A":
		img = ctrl._compose_a(sheets, flags, tile_px)
		for row in range(32):
			for col in range(8):
				var id: int = TilePalette.a_cell_to_id(col, row)
				catalog.append({"col": col, "row": row, "tile_id": id, "sheet": ctrl._a_sheet_name(id), "label": TileLabels.label_of(id)})
				if bool(args.get("ids", true)):
					TileLabels.blit_number(img, id, col * tile_px + 1, row * tile_px + 1)
	else:
		var si: int = ctrl._sheet_index(tab)
		var src: Image = sheets[si] if si >= 0 and si < sheets.size() else null
		if src == null:
			img = Image.create(tile_px * 8, tile_px * 2, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.15, 0.08, 0.08, 1))
		else:
			img = src.duplicate()
		var base: int = ctrl._tab_base(tab)
		var cols = maxi(1, img.get_width() / tile_px)
		var rows = maxi(1, img.get_height() / tile_px)
		for row2 in range(rows):
			for col2 in range(cols):
				var idb: int = TilePalette.sheet_cell_to_id(col2, row2, base)
				catalog.append({"col": col2, "row": row2, "tile_id": idb, "sheet": tab, "label": TileLabels.label_of(idb)})
				if bool(args.get("ids", true)):
					TileLabels.blit_number(img, idb, col2 * tile_px + 1, row2 * tile_px + 1)
	ctrl._grid_image(img, tile_px)
	var extra = {
		"tileset_id": ts_id,
		"tab": tab,
		"tile_size": tile_px,
		"catalog": catalog,
		"count": catalog.size(),
	}
	return ctrl._png_payload(img, extra, args, "res://.grok/mcp_tileset.png")



func preview_charset(args: Dictionary) -> Dictionary:
	var cs = str(args.get("charset", "")).strip_edges()
	if cs == "":
		return ctrl.mcp._err("charset required")
	var index = int(args.get("index", 0))
	var pack_dir = str(ctrl.pack().root) if ctrl.pack() else ""
	var dirs: Array = [2, 4, 6, 8]
	if args.has("direction"):
		dirs = [int(args.get("direction", 2))]
	var ts = 48
	var img = Image.create(ts * dirs.size(), ts, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.12, 0.14, 1))
	var drawn = 0
	for i in range(dirs.size()):
		var r = Rect2i(i * ts, 0, ts, ts)
		if CharsetSheet.blit_idle_frame(img, r, cs, index, int(dirs[i]), pack_dir):
			drawn += 1
	if drawn == 0:
		return ctrl.mcp._err("charset not found")
	return ctrl._png_payload(img, {"charset": cs, "index": index, "frames": dirs.size(), "drawn": drawn}, args, "res://.grok/mcp_charset.png")



func pick_tileset(args: Dictionary) -> Dictionary:
	var tab = str(args.get("tab", "A")).strip_edges().to_upper()
	if tab == "":
		tab = "A"
	var col = int(args.get("col", -1))
	var row = int(args.get("row", -1))
	if args.has("px") or args.has("py"):
		var ts = 48
		col = int(args.get("px", 0)) / ts
		row = int(args.get("py", 0)) / ts
	var id = 0
	if tab == "A":
		id = TilePalette.a_cell_to_id(col, row)
	else:
		id = TilePalette.sheet_cell_to_id(col, row, ctrl._tab_base(tab))
	return ctrl.mcp._ok({"tab": tab, "col": col, "row": row, "tile_id": id, "label": TileLabels.label_of(id)})



func find_tiles(args: Dictionary) -> Dictionary:
	var q = str(args.get("query", ""))
	var ts: Dictionary = {}
	if ctrl.pack() and ctrl.doc() != null:
		ts = ctrl.pack().tilesets.get(str(ctrl.doc().tileset_id), {})
	return ctrl.mcp._ok({"query": q, "matches": TileLabels.search(q, ts)})



func get_weather(_args := {}) -> Dictionary:
	var e = ctrl.ed()
	var kind = "clear"
	var inten = 0.0
	if e:
		kind = str(e.get("_preview_weather")) if "_preview_weather" in e else "clear"
		inten = float(e.get("_preview_weather_i")) if "_preview_weather_i" in e else 0.0
	var field = e.get("map_field") if e else null
	var atm: Dictionary = {}
	if field != null and "last_atmosphere" in field:
		atm = field.last_atmosphere
	return ctrl.mcp._ok({
		"kind": kind,
		"intensity": inten,
		"indoor": field.map_is_indoor() if field != null and field.has_method("map_is_indoor") else false,
		"modulate": ctrl._color_hex(atm.get("modulate", Color(1, 1, 1, 1))),
		"label": str(atm.get("label", "")),
	})

func op_names() -> Array:
	return ["get_tile", "get_tiles_rect", "list_entities", "list_layers", "list_tilesets", "get_map_settings", "find_tiles", "pick_tileset", "get_weather", "preview_tileset", "preview_charset"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("get_tile", "读一格：z0-5、ext、meta、通行。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		ctrl.mcp._tool("get_tiles_rect", "读矩形一层的 tile_id。默认当前层，最大 80×80。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		ctrl.mcp._tool("list_entities", "列出地图实体。kind: npc|event|warp；可加范围。", {
			"kind": {"type": "string"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}),
		ctrl.mcp._tool("list_layers", "图层列表与当前层。", {}),
		ctrl.mcp._tool("list_tilesets", "包内图块套。", {}),
		ctrl.mcp._tool("get_map_settings", "地图设置：尺寸、起点、BGM、光照、室内/室外。", {}),
		ctrl.mcp._tool("find_tiles", "按用途搜 tile_id。query: 草|水|沙|墙|树|屋顶…", {
			"query": {"type": "string"},
		}, ["query"]),
		ctrl.mcp._tool("pick_tileset", "从图块套格子取 tile_id。tab + col/row，或 px/py 相对预览图。", {
			"tab": {"type": "string"}, "col": {"type": "integer"}, "row": {"type": "integer"},
			"px": {"type": "integer"}, "py": {"type": "integer"},
		}),
		ctrl.mcp._tool("get_weather", "当前预览天气（与光照叠乘）。", {}),
		ctrl.mcp._tool("preview_tileset", "渲当前图块套 A/B/C/D/E，返回 PNG + id 目录。", {
			"tab": {"type": "string", "description": "A|B|C|D|E"},
			"tileset_id": {"type": "string"},
			"max_px": {"type": "integer"},
			"path": {"type": "string"},
		}),
		ctrl.mcp._tool("preview_charset", "渲行走图四向（或指定朝向）。", {
			"charset": {"type": "string"}, "index": {"type": "integer"},
			"direction": {"type": "integer"}, "max_px": {"type": "integer"},
			"path": {"type": "string"},
		}, ["charset"]),
	]
