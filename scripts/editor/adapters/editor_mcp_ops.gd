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
var _stamp_ops_logic: StampOps = StampOps.new(self)
var _map_crud_ops_logic: MapCrudOps = MapCrudOps.new(self)
var _history_ops_logic: HistoryOps = HistoryOps.new(self)
var _asset_ops_logic: AssetOps = AssetOps.new(self)
var _entity_ops_logic: EntityOps = EntityOps.new(self)

var mcp: Node = null


func tools_list() -> Array:
	return [
		mcp._tool("get_tile", "读一格：z0-5、ext、meta、通行。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		mcp._tool("get_tiles_rect", "读矩形一层的 tile_id。默认当前层，最大 80×80。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		mcp._tool("list_entities", "列出地图实体。kind: npc|event|warp；可加范围。", {
			"kind": {"type": "string"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}),
		mcp._tool("list_layers", "图层列表与当前层。", {}),
		mcp._tool("list_tilesets", "包内图块套。", {}),
		mcp._tool("get_map_settings", "地图设置：尺寸、起点、BGM、光照、室内/室外。", {}),
		mcp._tool("set_map_settings", "改地图设置。environment: outdoor|indoor；或 indoor: bool。", {
			"name": {"type": "string"}, "bgm": {"type": "string"},
			"light_preset": {"type": "integer"},
			"light_fx_color": {"type": "string", "description": "#rrggbb 或 r,g,b"},
			"start_x": {"type": "integer"}, "start_y": {"type": "integer"},
			"tileset_id": {"type": "string"}, "start_map": {"type": "boolean"},
			"water_through": {"type": "boolean"},
			"far_scroll_x": {"type": "number"}, "far_scroll_y": {"type": "number"},
			"environment": {"type": "string", "description": "outdoor|indoor"},
			"indoor": {"type": "boolean"},
		}),
		mcp._tool("create_map", "新建地图并切换过去。", {
			"map_id": {"type": "string"}, "name": {"type": "string"},
			"parent": {"type": "string"}, "w": {"type": "integer"}, "h": {"type": "integer"},
			"tileset": {"type": "string"},
		}),
		mcp._tool("delete_map", "删除地图。", {"map_id": {"type": "string"}}, ["map_id"]),
		mcp._tool("rename_map", "重命名地图。", {
			"map_id": {"type": "string"}, "name": {"type": "string"},
		}, ["map_id", "name"]),
		mcp._tool("duplicate_map", "复制地图。", {"map_id": {"type": "string"}}, ["map_id"]),
		mcp._tool("resize_map", "改变当前地图宽高（裁切/填空）。", {
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}, ["w", "h"]),
		mcp._tool("reparent_map", "把地图挂到另一个地图下。", {
			"map_id": {"type": "string"}, "parent": {"type": "string"},
		}, ["map_id"]),
		mcp._tool("set_map_tileset", "当前地图换图块套。", {"tileset_id": {"type": "string"}}, ["tileset_id"]),
		mcp._tool("set_layer", "当前绘制层。z: 0-5 或 ext: far|water|roof|light|…", {
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}),
		mcp._tool("set_layer_visible", "显示/隐藏图层（仅预览）。", {
			"z": {"type": "integer"}, "ext": {"type": "string"}, "visible": {"type": "boolean"},
		}),
		mcp._tool("paint_rect", "矩形铺/擦，走自动图块。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"tile_id": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y"]),
		mcp._tool("paint_fill", "同色填充，走自动图块。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"tile_id": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"},
		}, ["x", "y"]),
		mcp._tool("paint_cells", "批量写格子。cells: [{x,y,tile_id?,z?,ext?}] 最多 16384。", {
			"cells": {"type": "array"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["cells"]),
		mcp._tool("paint_polyline", "折线（河、路、墙）。points: [{x,y},…]，width 线宽。", {
			"points": {"type": "array"}, "tile_id": {"type": "integer"},
			"width": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["points", "tile_id"]),
		mcp._tool("paint_ellipse", "椭圆。fill 默认 true；给 inner_rx/inner_ry 则成环。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"rx": {"type": "integer"}, "ry": {"type": "integer"},
			"tile_id": {"type": "integer"}, "fill": {"type": "boolean"},
			"inner_rx": {"type": "integer"}, "inner_ry": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y", "rx", "tile_id"]),
		mcp._tool("paint_ring", "圆环/椭圆环。r 或 rx/ry，thickness 默认 1。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"r": {"type": "integer"}, "rx": {"type": "integer"}, "ry": {"type": "integer"},
			"thickness": {"type": "integer"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y", "tile_id"]),
		mcp._tool("copy_tiles", "复制当前层矩形到图块剪贴板。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		mcp._tool("cut_tiles", "剪切当前层矩形。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		mcp._tool("paste_tiles", "把图块剪贴板贴到目标格。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		mcp._tool("set_stamp", "设置多格图章。tiles 行优先。", {
			"w": {"type": "integer"}, "h": {"type": "integer"}, "tiles": {"type": "array"},
		}, ["w", "h", "tiles"]),
		mcp._tool("paint_stamp", "在原点盖图章。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		mcp._tool("undo", "撤销上次绘制/写入。", {}),
		mcp._tool("redo", "重做。", {}),
		mcp._tool("refresh_autotiles", "重算整张地面自动图块接缝。", {}),
		mcp._tool("preview_tileset", "渲当前图块套 A/B/C/D/E，返回 PNG + id 目录。", {
			"tab": {"type": "string", "description": "A|B|C|D|E"},
			"tileset_id": {"type": "string"},
			"max_px": {"type": "integer"},
			"path": {"type": "string"},
		}),
		mcp._tool("preview_charset", "渲行走图四向（或指定朝向）。", {
			"charset": {"type": "string"}, "index": {"type": "integer"},
			"direction": {"type": "integer"}, "max_px": {"type": "integer"},
			"path": {"type": "string"},
		}, ["charset"]),
		mcp._tool("set_passage", "图块通行。kind: o|x|star；dirs: up,down,left,right 阻挡。", {
			"tile_id": {"type": "integer"},
			"kind": {"type": "string"},
			"up": {"type": "boolean"}, "down": {"type": "boolean"},
			"left": {"type": "boolean"}, "right": {"type": "boolean"},
		}, ["tile_id"]),
		mcp._tool("update_entity", "改一格已有实体字段（不整格覆盖）。事件可带 commands/pages。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		mcp._tool("place_chest", "放置宝箱事件。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"item_id": {"type": "string"}, "qty": {"type": "integer"}, "gold": {"type": "integer"},
		}, ["x", "y"]),
		mcp._tool("import_asset", "导入素材文件。kind: charset|faces|tilesheet|audio/bgm|…", {
			"path": {"type": "string"}, "kind": {"type": "string"},
		}, ["path", "kind"]),
		mcp._tool("pick_tileset", "从图块套格子取 tile_id。tab + col/row，或 px/py 相对预览图。", {
			"tab": {"type": "string"}, "col": {"type": "integer"}, "row": {"type": "integer"},
			"px": {"type": "integer"}, "py": {"type": "integer"},
		}),
		mcp._tool("find_tiles", "按用途搜 tile_id。query: 草|水|沙|墙|树|屋顶…", {
			"query": {"type": "string"},
		}, ["query"]),
		mcp._tool("paint_arc", "圆弧。from_deg/to_deg，0=东 90=南（y 向下）。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"rx": {"type": "integer"}, "ry": {"type": "integer"},
			"from_deg": {"type": "number"}, "to_deg": {"type": "number"},
			"width": {"type": "integer"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y", "rx", "tile_id"]),
		mcp._tool("scatter", "沿线/环按间距盖图章。along: polyline|ring。", {
			"along": {"type": "string"},
			"points": {"type": "array"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"r": {"type": "integer"}, "rx": {"type": "integer"}, "ry": {"type": "integer"},
			"spacing": {"type": "integer"},
			"tile_id": {"type": "integer"},
			"stamp_w": {"type": "integer"}, "stamp_h": {"type": "integer"}, "tiles": {"type": "array"},
			"z": {"type": "integer"},
		}),
		mcp._tool("stamp_from_tileset", "从图块套矩形做成图章。", {
			"tab": {"type": "string"}, "col": {"type": "integer"}, "row": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}, ["col", "row"]),
		mcp._tool("replace_tiles", "整层替换 tile（自动图块比 kind）。", {
			"old_id": {"type": "integer"}, "new_id": {"type": "integer"},
			"z": {"type": "integer"}, "kind_match": {"type": "boolean"},
		}, ["old_id", "new_id"]),
		mcp._tool("rotate_tiles", "旋转图块剪贴板。cw 默认 true。", {"cw": {"type": "boolean"}}),
		mcp._tool("flip_tiles", "翻转图块剪贴板。horizontal 默认 true。", {"horizontal": {"type": "boolean"}}),
		mcp._tool("list_undo", "查看撤销栈。", {}),
		mcp._tool("add_bookmark", "书签。", {
			"name": {"type": "string"}, "x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["name"]),
		mcp._tool("list_bookmarks", "列出书签。", {}),
		mcp._tool("goto_bookmark", "跳到书签。", {"name": {"type": "string"}}, ["name"]),
		mcp._tool("add_region", "命名区域。", {
			"name": {"type": "string"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}, ["name", "x", "y"]),
		mcp._tool("list_regions", "列出区域。", {}),
		mcp._tool("set_reference", "参考图半透明叠在地图上。path 空则清除。", {
			"path": {"type": "string"}, "alpha": {"type": "number"},
		}),
		mcp._tool("set_layer_alpha", "预览桶透明度。bucket: Ground|Upper|Roof|Below|Fx", {
			"bucket": {"type": "string"}, "alpha": {"type": "number"},
		}, ["bucket"]),
		mcp._tool("save_stamp", "把当前图章存成命名图章。", {"name": {"type": "string"}}, ["name"]),
		mcp._tool("list_stamps", "列出命名图章。", {}),
		mcp._tool("apply_stamp", "在格子盖命名图章。", {
			"name": {"type": "string"}, "x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["name", "x", "y"]),
		mcp._tool("get_weather", "当前预览天气（与光照叠乘）。", {}),
		mcp._tool("set_weather", "预览天气。kind: clear|rain|storm|snow|fog。不写进地图。", {
			"kind": {"type": "string"}, "intensity": {"type": "number"},
		}, ["kind"]),
	]


func dispatch(name: String, args: Dictionary) -> Dictionary:
	match name:
		"get_tile":
			return get_tile(args)
		"get_tiles_rect":
			return get_tiles_rect(args)
		"list_entities":
			return list_entities(args)
		"list_layers":
			return list_layers()
		"list_tilesets":
			return list_tilesets()
		"get_map_settings":
			return get_map_settings()
		"set_map_settings":
			return set_map_settings(args)
		"create_map":
			return create_map(args)
		"delete_map":
			return delete_map(args)
		"rename_map":
			return rename_map(args)
		"duplicate_map":
			return duplicate_map(args)
		"resize_map":
			return resize_map(args)
		"reparent_map":
			return reparent_map(args)
		"set_map_tileset":
			return set_map_tileset(args)
		"set_layer":
			return set_layer(args)
		"set_layer_visible":
			return set_layer_visible(args)
		"paint_rect":
			return paint_rect(args)
		"paint_fill":
			return paint_fill(args)
		"paint_cells":
			return paint_cells(args)
		"paint_polyline":
			return paint_polyline(args)
		"paint_ellipse":
			return paint_ellipse(args)
		"paint_ring":
			return paint_ring(args)
		"copy_tiles":
			return copy_tiles(args)
		"cut_tiles":
			return cut_tiles(args)
		"paste_tiles":
			return paste_tiles(args)
		"set_stamp":
			return set_stamp(args)
		"paint_stamp":
			return paint_stamp(args)
		"undo":
			return undo()
		"redo":
			return redo()
		"refresh_autotiles":
			return refresh_autotiles()
		"preview_tileset":
			return preview_tileset(args)
		"preview_charset":
			return preview_charset(args)
		"set_passage":
			return set_passage(args)
		"update_entity":
			return update_entity(args)
		"place_chest":
			return place_chest(args)
		"import_asset":
			return import_asset(args)
		"pick_tileset":
			return pick_tileset(args)
		"find_tiles":
			return find_tiles(args)
		"paint_arc":
			return paint_arc(args)
		"scatter":
			return scatter(args)
		"stamp_from_tileset":
			return stamp_from_tileset(args)
		"replace_tiles":
			return replace_tiles(args)
		"rotate_tiles":
			return rotate_tiles(args)
		"flip_tiles":
			return flip_tiles(args)
		"list_undo":
			return list_undo()
		"add_bookmark":
			return add_bookmark(args)
		"list_bookmarks":
			return list_bookmarks()
		"goto_bookmark":
			return goto_bookmark(args)
		"add_region":
			return add_region(args)
		"list_regions":
			return list_regions()
		"set_reference":
			return set_reference(args)
		"set_layer_alpha":
			return set_layer_alpha(args)
		"save_stamp":
			return save_stamp(args)
		"list_stamps":
			return list_stamps()
		"apply_stamp":
			return apply_stamp_named(args)
		"get_weather":
			return get_weather()
		"set_weather":
			return set_weather_preview(args)
		_:
			return {}


func ed():
	return mcp.editor if mcp else null


func doc():
	return mcp._doc() if mcp else null


func pack():
	var e = ed()
	return e.pack if e else null


func get_tile(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var c: Vector2i = mcp._cell(args)
	var z_tiles: Array = []
	for z in range(6):
		z_tiles.append(int(d.tile(c.x, c.y, z)))
	var ext := {}
	for id in MapExt.LAYER_IDS:
		ext[id] = int(d.ext_tile(id, c.x, c.y))
	var pass_st := -1
	var field = ed().get("map_field") if ed() and "map_field" in ed() else null
	if field != null and field.has_method("edit_cell_passable"):
		pass_st = int(field.edit_cell_passable(c.x, c.y))
	var flags: PackedInt32Array = _flags()
	var t0: int = z_tiles[0]
	var flag0: int = int(flags[t0]) if t0 >= 0 and t0 < flags.size() else 0
	return mcp._ok({
		"x": c.x, "y": c.y,
		"z": z_tiles,
		"ext": ext,
		"meta": int(ext.get("meta", 0)),
		"entity": d.entity_at(c),
		"pass": pass_st,
		"flag0": flag0,
	})


func get_tiles_rect(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var r: Dictionary = _clamp_rect(args, int(d.width), int(d.height), TILES_RECT_MAX)
	if bool(r.get("error", false)):
		return mcp._err(str(r.get("msg", "bad rect")))
	_apply_layer(args)
	var paint = _ensure_paint()
	var rows: Array = []
	for y in range(int(r.y), int(r.y) + int(r.h)):
		var row: Array = []
		for x in range(int(r.x), int(r.x) + int(r.w)):
			row.append(int(paint._read_cell(d, Vector2i(x, y))))
		rows.append(row)
	return mcp._ok({
		"x": int(r.x), "y": int(r.y), "w": int(r.w), "h": int(r.h),
		"z": int(paint.layer_z), "ext": str(paint.ext_layer),
		"tiles": rows,
	})


func list_entities(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var filter := str(args.get("kind", "")).strip_edges().to_lower()
	var has_box := args.has("w") or args.has("h") or args.has("x") or args.has("y")
	var x0 := int(args.get("x", 0))
	var y0 := int(args.get("y", 0))
	var x1 := x0 + int(args.get("w", d.width)) - 1
	var y1 := y0 + int(args.get("h", d.height)) - 1
	var out: Array = []
	if filter == "" or filter == "event":
		for ev in d.events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var cell: Vector2i = mcp._entity_cell(ev.get("cell", {}))
			if has_box and (cell.x < x0 or cell.y < y0 or cell.x > x1 or cell.y > y1):
				continue
			out.append({"kind": "event", "x": cell.x, "y": cell.y, "id": str(ev.get("id", "")), "trigger": str(ev.get("trigger", ""))})
	if filter == "" or filter == "npc":
		for n in d.npcs:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var cell2: Vector2i = mcp._entity_cell(n.get("cell", {}))
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
			var cell3: Vector2i = mcp._entity_cell(w.get("from_cell", {}))
			if has_box and (cell3.x < x0 or cell3.y < y0 or cell3.x > x1 or cell3.y > y1):
				continue
			out.append({
				"kind": "warp", "x": cell3.x, "y": cell3.y,
				"to_map": str(w.get("to_map", w.get("to_map_id", ""))),
			})
	return mcp._ok({"count": out.size(), "entities": out})


func list_layers() -> Dictionary:
	var paint = _ensure_paint()
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
	return mcp._ok({"layers": rows, "z": paint.layer_z, "ext": str(paint.ext_layer)})


func list_tilesets() -> Dictionary:
	var p = pack()
	if p == null:
		return mcp._err("no pack")
	var out: Array = []
	var keys: Array = p.tilesets.keys()
	keys.sort()
	var cur := ""
	var d = doc()
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
	return mcp._ok({"tilesets": out, "current": cur})


func get_map_settings() -> Dictionary:
	var d = doc()
	var p = pack()
	if d == null:
		return mcp._err("no map")
	var fx: Color = d.light_fx_color if "light_fx_color" in d else Color(1, 1, 1, 1)
	return mcp._ok({
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


func set_map_settings(args: Dictionary) -> Dictionary:
	var d = doc()
	var p = pack()
	if d == null:
		return mcp._err("no map")
	if args.has("name"):
		var nm := str(args.get("name", "")).strip_edges()
		if nm != "" and p and p.has_method("rename_map"):
			p.rename_map(str(d.map_id), nm)
		elif nm != "":
			d.display_name = nm
			d.dirty = true
	if args.has("bgm"):
		d.bgm = str(args.get("bgm", ""))
		d.dirty = true
	if args.has("light_preset"):
		d.light_preset = int(args.get("light_preset", 0))
		d.dirty = true
		if ed() and ed().has_method("_apply_editor_light"):
			ed()._apply_editor_light()
			ed()._sync_light_controls()
	if args.has("light_fx_color"):
		d.light_fx_color = _parse_color(args.get("light_fx_color"), d.light_fx_color)
		d.dirty = true
		if ed() and ed().has_method("_apply_editor_fx_color"):
			ed()._apply_editor_fx_color()
			ed()._sync_fx_color_controls()
	if args.has("start_x") or args.has("start_y"):
		d.start_cell = Vector2i(
			clampi(int(args.get("start_x", d.start_cell.x)), 0, int(d.width) - 1),
			clampi(int(args.get("start_y", d.start_cell.y)), 0, int(d.height) - 1)
		)
		d.dirty = true
		if ed() and ed().get("map_field"):
			ed().map_field.edit_start_cell = d.start_cell
	if args.has("tileset_id"):
		set_map_tileset({"tileset_id": args.get("tileset_id")})
	if args.has("water_through"):
		d.water_through = bool(args.get("water_through"))
		d.dirty = true
	if args.has("environment") or args.has("indoor"):
		if args.has("environment"):
			d.environment = MapExt.normalize_environment(args.get("environment"))
		else:
			d.environment = MapExt.normalize_environment(args.get("indoor"))
		d.dirty = true
	if args.has("far_scroll_x") or args.has("far_scroll_y"):
		d.far_scroll = Vector2(float(args.get("far_scroll_x", d.far_scroll.x)), float(args.get("far_scroll_y", d.far_scroll.y)))
		d.dirty = true
	if bool(args.get("start_map", false)) and p:
		p.start_map = str(d.map_id)
		p.dirty = true
	if p:
		p.dirty = true
	_persist()
	return get_map_settings()


func create_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.create_map(args)
func delete_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.delete_map(args)
func rename_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.rename_map(args)
func duplicate_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.duplicate_map(args)
func resize_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.resize_map(args)
func reparent_map(args: Dictionary) -> Dictionary:
	return _map_crud_ops_logic.reparent_map(args)
func set_map_tileset(args: Dictionary) -> Dictionary:
	var p = pack()
	var d = doc()
	if p == null or d == null:
		return mcp._err("no map")
	var ts := str(args.get("tileset_id", args.get("tileset", ""))).strip_edges()
	if ts == "" or not p.tilesets.has(ts):
		return mcp._err("unknown tileset")
	p.set_map_tileset(str(d.map_id), ts)
	_persist()
	if ed() and ed().has_method("_sync_palette"):
		ed()._sync_palette()
	if ed() and ed().has_method("_reload_field"):
		ed()._reload_field()
	return mcp._ok({"tileset_id": ts, "map_id": str(d.map_id)})


func set_layer(args: Dictionary) -> Dictionary:
	var paint = _ensure_paint()
	if args.has("ext") and str(args.get("ext", "")).strip_edges() != "":
		var ext := str(args.get("ext", "")).strip_edges()
		if MapExt.LAYER_IDS.find(ext) < 0:
			return mcp._err("unknown ext layer")
		paint.layer_z = -1
		paint.ext_layer = ext
	elif args.has("z"):
		paint.layer_z = clampi(int(args.get("z", 0)), 0, 5)
		paint.ext_layer = ""
	else:
		return mcp._err("z or ext required")
	return mcp._ok({"z": paint.layer_z, "ext": str(paint.ext_layer)})


func set_layer_visible(args: Dictionary) -> Dictionary:
	var field = ed().get("map_field") if ed() else null
	if field == null:
		return mcp._err("no map field")
	var vis := bool(args.get("visible", true))
	if args.has("ext") and str(args.get("ext", "")) != "":
		field.set_layer_hidden_ext(str(args.get("ext")), not vis)
		return mcp._ok({"ext": str(args.get("ext")), "visible": vis})
	var z := int(args.get("z", 0))
	field.set_layer_hidden_z(z, not vis)
	return mcp._ok({"z": z, "visible": vis})


func paint_rect(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var r: Dictionary = _clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return mcp._err(str(r.get("msg", "bad rect")))
	_apply_layer(args)
	var paint = _ensure_paint()
	paint.tool = PaintTools.Tool.RECT
	paint.exact_autotile = bool(args.get("exact", false))
	if args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id", 0))
	var a := Vector2i(int(r.x), int(r.y))
	var b := Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1)
	var dirty: Array[Vector2i] = paint.apply_rect(d, a, b, bool(args.get("erase", false)))
	_touch(dirty)
	return mcp._ok({"painted": dirty.size(), "x": a.x, "y": a.y, "w": int(r.w), "h": int(r.h), "z": paint.layer_z, "ext": str(paint.ext_layer)})


func paint_fill(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	_apply_layer(args)
	var paint = _ensure_paint()
	paint.tool = PaintTools.Tool.FILL
	paint.exact_autotile = false
	if args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id", 0))
	var c: Vector2i = mcp._cell(args)
	var dirty: Array[Vector2i] = paint.apply_cell(d, c, bool(args.get("erase", false)))
	_touch(dirty)
	return mcp._ok({"painted": dirty.size(), "x": c.x, "y": c.y, "z": paint.layer_z, "ext": str(paint.ext_layer)})


func paint_cells(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var raw: Variant = args.get("cells", [])
	if typeof(raw) != TYPE_ARRAY:
		return mcp._err("cells array required")
	var arr: Array = raw
	if arr.size() > PAINT_CELLS_MAX:
		return mcp._err("too many cells (max %d)" % PAINT_CELLS_MAX)
	_apply_layer(args)
	var paint = _ensure_paint()
	paint.tool = PaintTools.Tool.PENCIL
	paint.exact_autotile = bool(args.get("exact", false))
	var default_id := int(args.get("tile_id", paint.tile_id))
	var erase := bool(args.get("erase", false))
	var dirty: Array[Vector2i] = []
	var seeds: Array[Vector2i] = []
	paint._begin_batch(d)
	for item in arr:
		var cell := Vector2i.ZERO
		var id := default_id
		if typeof(item) == TYPE_VECTOR2I:
			cell = item
		elif typeof(item) == TYPE_DICTIONARY:
			cell = Vector2i(int(item.get("x", 0)), int(item.get("y", 0)))
			if item.has("tile_id"):
				id = int(item.get("tile_id"))
			if item.has("z") or item.has("ext"):
				_apply_layer(item)
				paint = _ensure_paint()
		elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
			cell = Vector2i(int(item[0]), int(item[1]))
			if (item as Array).size() >= 3:
				id = int(item[2])
		else:
			continue
		if cell.x < 0 or cell.y < 0 or cell.x >= int(d.width) or cell.y >= int(d.height):
			continue
		var write_id := 0 if erase else id
		if (not erase) and TileId.is_autotile(write_id) and not paint.exact_autotile:
			write_id = TileId.make_autotile_id(TileId.autotile_kind(write_id), 0)
		paint._write_cell(d, cell, write_id)
		dirty.append(cell)
		seeds.append(cell)
	if not paint.exact_autotile:
		paint._refresh_autotiles(d, seeds, dirty)
	paint._end_batch(d)
	_touch(dirty)
	return mcp._ok({"painted": dirty.size(), "z": paint.layer_z, "ext": str(paint.ext_layer)})


func paint_polyline(args: Dictionary) -> Dictionary:
	var pts_v: Variant = args.get("points", [])
	if typeof(pts_v) != TYPE_ARRAY or (pts_v as Array).is_empty():
		return mcp._err("points required")
	var pts: Array[Vector2i] = []
	for item in pts_v:
		if typeof(item) == TYPE_DICTIONARY:
			pts.append(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))))
		elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
			pts.append(Vector2i(int(item[0]), int(item[1])))
	if pts.size() < 1:
		return mcp._err("points required")
	var cells: Array[Vector2i] = []
	if pts.size() == 1:
		cells.append(pts[0])
	else:
		for i in range(pts.size() - 1):
			cells.append_array(_line_cells(pts[i], pts[i + 1]))
	cells = MapShapes.thicken(cells, maxi(int(args.get("width", 1)), 1))
	if args.has("bit"):
		args = args.duplicate()
		args["cells"] = cells
		return set_meta_batch(args)
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)


func paint_ellipse(args: Dictionary) -> Dictionary:
	var cx := int(args.get("x", 0))
	var cy := int(args.get("y", 0))
	var rx := maxi(int(args.get("rx", 0)), 0)
	var ry := maxi(int(args.get("ry", rx)), 0)
	var fill := bool(args.get("fill", true))
	var cells: Array[Vector2i] = MapShapes.ellipse_cells(cx, cy, rx, ry, fill)
	if args.has("inner_rx") or args.has("inner_ry"):
		var irx := maxi(int(args.get("inner_rx", 0)), 0)
		var iry := maxi(int(args.get("inner_ry", irx)), 0)
		var inner: Array[Vector2i] = MapShapes.ellipse_cells(cx, cy, irx, iry, true)
		var drop := {}
		for c in inner:
			drop["%d,%d" % [c.x, c.y]] = true
		var ring: Array[Vector2i] = []
		for c2 in cells:
			if not drop.has("%d,%d" % [c2.x, c2.y]):
				ring.append(c2)
		cells = ring
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)


func paint_ring(args: Dictionary) -> Dictionary:
	var r := maxi(int(args.get("r", args.get("rx", 0))), 0)
	var rx := maxi(int(args.get("rx", r)), 0)
	var ry := maxi(int(args.get("ry", r)), 0)
	var thick := maxi(int(args.get("thickness", 1)), 1)
	var openings: Array = []
	if typeof(args.get("openings")) == TYPE_ARRAY:
		openings = args.get("openings")
	elif args.has("gap_deg"):
		openings.append({
			"deg": float(args.get("gap_deg", 90)),
			"width_deg": float(args.get("gap_width_deg", args.get("gap_arc", 24))),
		})
	var cells: Array[Vector2i] = MapShapes.ring_cells(int(args.get("x", 0)), int(args.get("y", 0)), rx, ry, thick, openings)
	if args.has("bit"):
		var a := args.duplicate()
		a["cells"] = cells
		return set_meta_batch(a)
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)


func copy_tiles(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var r: Dictionary = _clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return mcp._err(str(r.get("msg", "bad rect")))
	_apply_layer(args)
	var paint = _ensure_paint()
	var clip: Dictionary = paint.copy_rect(d, Vector2i(int(r.x), int(r.y)), Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1))
	return mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0)), "z": paint.layer_z, "ext": str(paint.ext_layer)})


func cut_tiles(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var r: Dictionary = _clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return mcp._err(str(r.get("msg", "bad rect")))
	_apply_layer(args)
	var paint = _ensure_paint()
	var dirty: Array[Vector2i] = paint.cut_rect(d, Vector2i(int(r.x), int(r.y)), Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1))
	_touch(dirty)
	return mcp._ok({"cut": dirty.size(), "w": int(r.w), "h": int(r.h)})


func paste_tiles(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var paint = _ensure_paint()
	if paint.clipboard.is_empty():
		return mcp._err("tile clipboard empty")
	var c: Vector2i = mcp._cell(args)
	var dirty: Array[Vector2i] = paint.paste_at(d, c)
	if not paint.exact_autotile:
		paint.refresh_autotiles(d, dirty, dirty)
	_touch(dirty)
	return mcp._ok({"pasted": dirty.size(), "x": c.x, "y": c.y})


func set_stamp(args: Dictionary) -> Dictionary:
	return _stamp_ops_logic.set_stamp(args)
func paint_stamp(args: Dictionary) -> Dictionary:
	return _stamp_ops_logic.paint_stamp(args)
func undo() -> Dictionary:
	return _history_ops_logic.undo()
func redo() -> Dictionary:
	return _history_ops_logic.redo()
func refresh_autotiles() -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var n: int = int(_ensure_paint().refresh_all_floor_autotiles(d))
	if ed() and ed().has_method("_reload_field"):
		ed()._reload_field()
	return mcp._ok({"updated": n})


func preview_tileset(args: Dictionary) -> Dictionary:
	var p = pack()
	if p == null:
		return mcp._err("no pack")
	var ts_id := str(args.get("tileset_id", "")).strip_edges()
	if ts_id == "" and doc() != null:
		ts_id = str(doc().tileset_id)
	if ts_id == "" or not p.tilesets.has(ts_id):
		return mcp._err("no tileset")
	var tab := str(args.get("tab", "A")).strip_edges().to_upper()
	if tab == "":
		tab = "A"
	var ts: Dictionary = p.tilesets[ts_id] if typeof(p.tilesets[ts_id]) == TYPE_DICTIONARY else {}
	var sheets: Array = _load_sheets(ts)
	var flags := _flags_of(ts)
	var tile_px := 48
	if doc() != null:
		tile_px = maxi(int(doc().tile_size), 1)
	var img: Image
	var catalog: Array = []
	if tab == "A":
		img = _compose_a(sheets, flags, tile_px)
		for row in range(32):
			for col in range(8):
				var id: int = TilePalette.a_cell_to_id(col, row)
				catalog.append({"col": col, "row": row, "tile_id": id, "sheet": _a_sheet_name(id), "label": TileLabels.label_of(id)})
				if bool(args.get("ids", true)):
					TileLabels.blit_number(img, id, col * tile_px + 1, row * tile_px + 1)
	else:
		var si: int = _sheet_index(tab)
		var src: Image = sheets[si] if si >= 0 and si < sheets.size() else null
		if src == null:
			img = Image.create(tile_px * 8, tile_px * 2, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.15, 0.08, 0.08, 1))
		else:
			img = src.duplicate()
		var base: int = _tab_base(tab)
		var cols := maxi(1, img.get_width() / tile_px)
		var rows := maxi(1, img.get_height() / tile_px)
		for row2 in range(rows):
			for col2 in range(cols):
				var idb: int = TilePalette.sheet_cell_to_id(col2, row2, base)
				catalog.append({"col": col2, "row": row2, "tile_id": idb, "sheet": tab, "label": TileLabels.label_of(idb)})
				if bool(args.get("ids", true)):
					TileLabels.blit_number(img, idb, col2 * tile_px + 1, row2 * tile_px + 1)
	_grid_image(img, tile_px)
	var extra := {
		"tileset_id": ts_id,
		"tab": tab,
		"tile_size": tile_px,
		"catalog": catalog,
		"count": catalog.size(),
	}
	return _png_payload(img, extra, args, "res://.grok/mcp_tileset.png")


func preview_charset(args: Dictionary) -> Dictionary:
	var cs := str(args.get("charset", "")).strip_edges()
	if cs == "":
		return mcp._err("charset required")
	var index := int(args.get("index", 0))
	var pack_dir := str(pack().root) if pack() else ""
	var dirs: Array = [2, 4, 6, 8]
	if args.has("direction"):
		dirs = [int(args.get("direction", 2))]
	var ts := 48
	var img := Image.create(ts * dirs.size(), ts, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.12, 0.14, 1))
	var drawn := 0
	for i in range(dirs.size()):
		var r := Rect2i(i * ts, 0, ts, ts)
		if CharsetSheet.blit_idle_frame(img, r, cs, index, int(dirs[i]), pack_dir):
			drawn += 1
	if drawn == 0:
		return mcp._err("charset not found")
	return _png_payload(img, {"charset": cs, "index": index, "frames": dirs.size(), "drawn": drawn}, args, "res://.grok/mcp_charset.png")


func set_passage(args: Dictionary) -> Dictionary:
	var p = pack()
	var d = doc()
	if p == null or d == null:
		return mcp._err("no map")
	var tid := int(args.get("tile_id", 0))
	if tid <= 0:
		return mcp._err("tile_id required")
	var ts_id := str(d.tileset_id)
	if not p.tilesets.has(ts_id):
		return mcp._err("no tileset")
	var ts: Dictionary = p.tilesets[ts_id]
	var flags := _flags_of(ts)
	if flags.size() < TileId.TILE_ID_MAX:
		var old := flags.size()
		flags.resize(TileId.TILE_ID_MAX)
		for i in range(old, flags.size()):
			flags[i] = 0
	var cur: int = int(flags[tid]) if tid < flags.size() else 0
	if args.has("kind"):
		cur = TileId.with_passage_kind(cur, _pass_kind(args.get("kind")))
	if args.has("up"):
		cur = TileId.with_dir_blocked(cur, TileId.FLAG_UP, bool(args.get("up")))
	if args.has("down"):
		cur = TileId.with_dir_blocked(cur, TileId.FLAG_DOWN, bool(args.get("down")))
	if args.has("left"):
		cur = TileId.with_dir_blocked(cur, TileId.FLAG_LEFT, bool(args.get("left")))
	if args.has("right"):
		cur = TileId.with_dir_blocked(cur, TileId.FLAG_RIGHT, bool(args.get("right")))
	var ids: PackedInt32Array = TileId.passage_ids_for(tid)
	for id in ids:
		if id >= 0 and id < flags.size():
			flags[id] = cur
	var arr: Array = []
	arr.resize(flags.size())
	for j in range(flags.size()):
		arr[j] = int(flags[j])
	ts["flags"] = arr
	p.tilesets[ts_id] = ts
	p.dirty = true
	var pal = ed().get("_palette") if ed() else null
	if pal != null and pal.has_method("_write_flag"):
		pal._flags = flags
		pal.tileset = ts
	if ed() and ed().has_method("_apply_palette_flags"):
		ed()._apply_palette_flags(flags)
	elif ed() and ed().get("map_field") and ed().map_field.has_method("set_edit_flags"):
		ed().map_field.set_edit_flags(flags)
	return mcp._ok({
		"tile_id": tid,
		"flag": cur,
		"kind": TileId.passage_kind(cur),
		"tileset_id": ts_id,
	})


func update_entity(args: Dictionary) -> Dictionary:
	return _entity_ops_logic.update_entity(args)
func place_chest(args: Dictionary) -> Dictionary:
	return _entity_ops_logic.place_chest(args)
func import_asset(args: Dictionary) -> Dictionary:
	return _asset_ops_logic.import_asset(args)
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


func pick_tileset(args: Dictionary) -> Dictionary:
	var tab := str(args.get("tab", "A")).strip_edges().to_upper()
	if tab == "":
		tab = "A"
	var col := int(args.get("col", -1))
	var row := int(args.get("row", -1))
	if args.has("px") or args.has("py"):
		var ts := 48
		col = int(args.get("px", 0)) / ts
		row = int(args.get("py", 0)) / ts
	var id := 0
	if tab == "A":
		id = TilePalette.a_cell_to_id(col, row)
	else:
		id = TilePalette.sheet_cell_to_id(col, row, _tab_base(tab))
	return mcp._ok({"tab": tab, "col": col, "row": row, "tile_id": id, "label": TileLabels.label_of(id)})


func find_tiles(args: Dictionary) -> Dictionary:
	var q := str(args.get("query", ""))
	var ts: Dictionary = {}
	if pack() and doc() != null:
		ts = pack().tilesets.get(str(doc().tileset_id), {})
	return mcp._ok({"query": q, "matches": TileLabels.search(q, ts)})


func paint_arc(args: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = MapShapes.arc_cells(
		int(args.get("x", 0)), int(args.get("y", 0)),
		maxi(int(args.get("rx", 0)), 0),
		maxi(int(args.get("ry", args.get("rx", 0))), 0),
		float(args.get("from_deg", 0)),
		float(args.get("to_deg", 90)),
		maxi(int(args.get("width", 1)), 1)
	)
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)


func scatter(args: Dictionary) -> Dictionary:
	var along := str(args.get("along", "polyline")).strip_edges().to_lower()
	var path: Array[Vector2i] = []
	if along == "ring":
		path = MapShapes.ring_cells(
			int(args.get("x", 0)), int(args.get("y", 0)),
			maxi(int(args.get("r", args.get("rx", 0))), 0),
			maxi(int(args.get("ry", args.get("r", 0))), 0),
			1, args.get("openings", []) if typeof(args.get("openings")) == TYPE_ARRAY else []
		)
	else:
		var pts_v: Variant = args.get("points", [])
		var pts: Array[Vector2i] = []
		if typeof(pts_v) == TYPE_ARRAY:
			for item in pts_v:
				if typeof(item) == TYPE_DICTIONARY:
					pts.append(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))))
				elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
					pts.append(Vector2i(int(item[0]), int(item[1])))
		path = MapShapes.polyline_cells(pts, 1)
	var spots: Array[Vector2i] = MapShapes.scatter_along(path, maxi(int(args.get("spacing", 3)), 1))
	_apply_layer(args)
	var paint = _ensure_paint()
	if args.has("stamp_w") or args.has("tiles"):
		var tiles := PackedInt32Array()
		var tv: Variant = args.get("tiles", [])
		if typeof(tv) == TYPE_ARRAY:
			for v in tv:
				tiles.append(int(v))
		paint.set_stamp(maxi(int(args.get("stamp_w", 1)), 1), maxi(int(args.get("stamp_h", 1)), 1), tiles)
	elif args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id"))
		paint.set_stamp(1, 1, PackedInt32Array([paint.tile_id]))
	var dirty: Array[Vector2i] = []
	var d = doc()
	if d == null:
		return mcp._err("no map")
	for spot in spots:
		var cell: Vector2i = spot
		if paint.has_stamp():
			dirty.append_array(paint.apply_stamp(d, cell))
		else:
			dirty.append_array(paint.apply_cell(d, cell, false))
	_touch(dirty)
	return mcp._ok({"scattered": spots.size(), "painted": dirty.size()})


func stamp_from_tileset(args: Dictionary) -> Dictionary:
	return _stamp_ops_logic.stamp_from_tileset(args)
func replace_tiles(args: Dictionary) -> Dictionary:
	_apply_layer(args)
	var dirty: Array[Vector2i] = _ensure_paint().replace_id(
		doc(), int(args.get("old_id", 0)), int(args.get("new_id", 0)), bool(args.get("kind_match", true))
	)
	_touch(dirty)
	return mcp._ok({"replaced": dirty.size()})


func rotate_tiles(args: Dictionary) -> Dictionary:
	var clip: Dictionary = _ensure_paint().rotate_clipboard(bool(args.get("cw", true)))
	return mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0))})


func flip_tiles(args: Dictionary) -> Dictionary:
	var clip: Dictionary = _ensure_paint().flip_clipboard(bool(args.get("horizontal", true)))
	return mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0))})


func list_undo() -> Dictionary:
	return _history_ops_logic.list_undo()
func add_bookmark(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	if not ("bookmarks" in d):
		d.bookmarks = []
	var c: Vector2i = mcp._cursor()
	var bm := {
		"name": str(args.get("name", "")).strip_edges(),
		"x": int(args.get("x", c.x)),
		"y": int(args.get("y", c.y)),
	}
	if str(bm["name"]) == "":
		return mcp._err("name required")
	d.bookmarks.append(bm)
	d.dirty = true
	return mcp._ok({"bookmark": bm})


func list_bookmarks() -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	var bms: Array = d.bookmarks if "bookmarks" in d else []
	return mcp._ok({"bookmarks": bms})


func goto_bookmark(args: Dictionary) -> Dictionary:
	var name := str(args.get("name", "")).strip_edges()
	for bm in list_bookmarks().get("bookmarks", []):
		if typeof(bm) == TYPE_DICTIONARY and str(bm.get("name", "")) == name:
			mcp.call_tool("set_cursor", {"x": int(bm.get("x", 0)), "y": int(bm.get("y", 0))})
			return mcp._ok({"bookmark": bm})
	return mcp._err("bookmark not found")


func add_region(args: Dictionary) -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	if not ("regions" in d):
		d.regions = []
	var r := {
		"name": str(args.get("name", "")).strip_edges(),
		"x": int(args.get("x", 0)),
		"y": int(args.get("y", 0)),
		"w": maxi(int(args.get("w", 1)), 1),
		"h": maxi(int(args.get("h", 1)), 1),
	}
	d.regions.append(r)
	d.dirty = true
	return mcp._ok({"region": r})


func list_regions() -> Dictionary:
	var d = doc()
	if d == null:
		return mcp._err("no map")
	return mcp._ok({"regions": d.regions if "regions" in d else []})


func set_reference(args: Dictionary) -> Dictionary:
	var field = ed().get("map_field") if ed() else null
	if field == null:
		return mcp._err("no map field")
	var path := str(args.get("path", "")).strip_edges()
	var alpha := clampf(float(args.get("alpha", 0.35)), 0.0, 1.0)
	if field.has_method("set_reference_image"):
		field.set_reference_image(path, alpha)
	return mcp._ok({"path": path, "alpha": alpha})


func set_layer_alpha(args: Dictionary) -> Dictionary:
	var field = ed().get("map_field") if ed() else null
	if field == null or not field.has_method("set_bucket_alpha"):
		return mcp._err("no map field")
	var a := clampf(float(args.get("alpha", 1)), 0.0, 1.0)
	field.set_bucket_alpha(str(args.get("bucket", "Ground")), a)
	return mcp._ok({"bucket": str(args.get("bucket")), "alpha": a})


func save_stamp(args: Dictionary) -> Dictionary:
	return _stamp_ops_logic.save_stamp(args)
func list_stamps() -> Dictionary:
	return _stamp_ops_logic.list_stamps()
func get_weather() -> Dictionary:
	var e = ed()
	var kind := "clear"
	var inten := 0.0
	if e:
		kind = str(e.get("_preview_weather")) if "_preview_weather" in e else "clear"
		inten = float(e.get("_preview_weather_i")) if "_preview_weather_i" in e else 0.0
	var field = e.get("map_field") if e else null
	var atm: Dictionary = {}
	if field != null and "last_atmosphere" in field:
		atm = field.last_atmosphere
	return mcp._ok({
		"kind": kind,
		"intensity": inten,
		"indoor": field.map_is_indoor() if field != null and field.has_method("map_is_indoor") else false,
		"modulate": _color_hex(atm.get("modulate", Color(1, 1, 1, 1))),
		"label": str(atm.get("label", "")),
	})


func set_weather_preview(args: Dictionary) -> Dictionary:
	var e = ed()
	if e == null:
		return mcp._err("no editor")
	var Weather = load("res://scripts/map/weather.gd")
	var kind: String = Weather.normalize(str(args.get("kind", "clear")))
	var inten := clampf(float(args.get("intensity", 0.8)), 0.0, 1.0)
	if kind == "clear":
		inten = 0.0
	e._preview_weather = kind
	e._preview_weather_i = inten
	if e.get("_weather_bar") != null:
		var bar: OptionButton = e._weather_bar
		for i in range(bar.item_count):
			if str(bar.get_item_metadata(i)) == kind:
				bar.select(i)
				break
	if e.has_method("_apply_editor_atmosphere"):
		e._apply_editor_atmosphere()
	elif e.has_method("_apply_editor_light"):
		e._apply_editor_light()
	return get_weather()


func _color_hex(v: Variant) -> String:
	var c := Color(1, 1, 1, 1)
	if typeof(v) == TYPE_COLOR:
		c = v
	return "#%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]


func apply_stamp_named(args: Dictionary) -> Dictionary:
	return _stamp_ops_logic.apply_stamp_named(args)
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
