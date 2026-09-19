extends RefCounted
## Domain ops: paint (rect/fill/cells/polyline/ellipse/ring/arc/scatter, passage, autotiles).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")
const MapShapes = preload("res://scripts/editor/domain/map_shapes.gd")
const PAINT_CELLS_MAX := 16384

func paint_rect(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var r: Dictionary = ctrl._clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return ctrl.mcp._err(str(r.get("msg", "bad rect")))
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	paint.tool = PaintTools.Tool.RECT
	paint.exact_autotile = bool(args.get("exact", false))
	if args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id", 0))
	var a = Vector2i(int(r.x), int(r.y))
	var b = Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1)
	var dirty: Array[Vector2i] = paint.apply_rect(d, a, b, bool(args.get("erase", false)))
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"painted": dirty.size(), "x": a.x, "y": a.y, "w": int(r.w), "h": int(r.h), "z": paint.layer_z, "ext": str(paint.ext_layer)})



func paint_fill(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	paint.tool = PaintTools.Tool.FILL
	paint.exact_autotile = false
	if args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id", 0))
	var c: Vector2i = ctrl.mcp._cell(args)
	var dirty: Array[Vector2i] = paint.apply_cell(d, c, bool(args.get("erase", false)))
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"painted": dirty.size(), "x": c.x, "y": c.y, "z": paint.layer_z, "ext": str(paint.ext_layer)})



func paint_cells(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var raw: Variant = args.get("cells", [])
	if typeof(raw) != TYPE_ARRAY:
		return ctrl.mcp._err("cells array required")
	var arr: Array = raw
	if arr.size() > PAINT_CELLS_MAX:
		return ctrl.mcp._err("too many cells (max %d)" % PAINT_CELLS_MAX)
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	paint.tool = PaintTools.Tool.PENCIL
	paint.exact_autotile = bool(args.get("exact", false))
	var default_id = int(args.get("tile_id", paint.tile_id))
	var erase = bool(args.get("erase", false))
	var dirty: Array[Vector2i] = []
	var seeds: Array[Vector2i] = []
	paint._begin_batch(d)
	for item in arr:
		var cell = Vector2i.ZERO
		var id = default_id
		if typeof(item) == TYPE_VECTOR2I:
			cell = item
		elif typeof(item) == TYPE_DICTIONARY:
			cell = Vector2i(int(item.get("x", 0)), int(item.get("y", 0)))
			if item.has("tile_id"):
				id = int(item.get("tile_id"))
			if item.has("z") or item.has("ext"):
				ctrl._apply_layer(item)
				paint = ctrl._ensure_paint()
		elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
			cell = Vector2i(int(item[0]), int(item[1]))
			if (item as Array).size() >= 3:
				id = int(item[2])
		else:
			continue
		if cell.x < 0 or cell.y < 0 or cell.x >= int(d.width) or cell.y >= int(d.height):
			continue
		var write_id = 0 if erase else id
		if (not erase) and TileId.is_autotile(write_id) and not paint.exact_autotile:
			write_id = TileId.make_autotile_id(TileId.autotile_kind(write_id), 0)
		paint._write_cell(d, cell, write_id)
		dirty.append(cell)
		seeds.append(cell)
	if not paint.exact_autotile:
		paint._refresh_autotiles(d, seeds, dirty)
	paint._end_batch(d)
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"painted": dirty.size(), "z": paint.layer_z, "ext": str(paint.ext_layer)})



func paint_polyline(args: Dictionary) -> Dictionary:
	var pts_v: Variant = args.get("points", [])
	if typeof(pts_v) != TYPE_ARRAY or (pts_v as Array).is_empty():
		return ctrl.mcp._err("points required")
	var pts: Array[Vector2i] = []
	for item in pts_v:
		if typeof(item) == TYPE_DICTIONARY:
			pts.append(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))))
		elif typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
			pts.append(Vector2i(int(item[0]), int(item[1])))
	if pts.size() < 1:
		return ctrl.mcp._err("points required")
	var cells: Array[Vector2i] = []
	if pts.size() == 1:
		cells.append(pts[0])
	else:
		for i in range(pts.size() - 1):
			cells.append_array(ctrl._line_cells(pts[i], pts[i + 1]))
	cells = MapShapes.thicken(cells, maxi(int(args.get("width", 1)), 1))
	if args.has("bit"):
		args = args.duplicate()
		args["cells"] = cells
		return ctrl.set_meta_batch(args)
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)



func paint_ellipse(args: Dictionary) -> Dictionary:
	var cx = int(args.get("x", 0))
	var cy = int(args.get("y", 0))
	var rx = maxi(int(args.get("rx", 0)), 0)
	var ry = maxi(int(args.get("ry", rx)), 0)
	var fill = bool(args.get("fill", true))
	var cells: Array[Vector2i] = MapShapes.ellipse_cells(cx, cy, rx, ry, fill)
	if args.has("inner_rx") or args.has("inner_ry"):
		var irx = maxi(int(args.get("inner_rx", 0)), 0)
		var iry = maxi(int(args.get("inner_ry", irx)), 0)
		var inner: Array[Vector2i] = MapShapes.ellipse_cells(cx, cy, irx, iry, true)
		var drop = {}
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
	var r = maxi(int(args.get("r", args.get("rx", 0))), 0)
	var rx = maxi(int(args.get("rx", r)), 0)
	var ry = maxi(int(args.get("ry", r)), 0)
	var thick = maxi(int(args.get("thickness", 1)), 1)
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
		var a = args.duplicate()
		a["cells"] = cells
		return ctrl.set_meta_batch(a)
	args = args.duplicate()
	args["cells"] = cells
	return paint_cells(args)



func refresh_autotiles(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var n: int = int(ctrl._ensure_paint().refresh_all_floor_autotiles(d))
	if ctrl.ed() and ctrl.ed().has_method("_reload_field"):
		ctrl.ed()._reload_field()
	return ctrl.mcp._ok({"updated": n})



func set_passage(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	var d = ctrl.doc()
	if p == null or d == null:
		return ctrl.mcp._err("no map")
	var tid = int(args.get("tile_id", 0))
	if tid <= 0:
		return ctrl.mcp._err("tile_id required")
	var ts_id = str(d.tileset_id)
	if not p.tilesets.has(ts_id):
		return ctrl.mcp._err("no tileset")
	var ts: Dictionary = p.tilesets[ts_id]
	var flags = ctrl._flags_of(ts)
	if flags.size() < TileId.TILE_ID_MAX:
		var old = flags.size()
		flags.resize(TileId.TILE_ID_MAX)
		for i in range(old, flags.size()):
			flags[i] = 0
	var cur: int = int(flags[tid]) if tid < flags.size() else 0
	if args.has("kind"):
		cur = TileId.with_passage_kind(cur, ctrl._pass_kind(args.get("kind")))
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
	var pal = ctrl.ed().get("_palette") if ctrl.ed() else null
	if pal != null and pal.has_method("_write_flag"):
		pal._flags = flags
		pal.tileset = ts
	if ctrl.ed() and ctrl.ed().has_method("_apply_palette_flags"):
		ctrl.ed()._apply_palette_flags(flags)
	elif ctrl.ed() and ctrl.ed().get("map_field") and ctrl.ed().map_field.has_method("set_edit_flags"):
		ctrl.ed().map_field.set_edit_flags(flags)
	return ctrl.mcp._ok({
		"tile_id": tid,
		"flag": cur,
		"kind": TileId.passage_kind(cur),
		"tileset_id": ts_id,
	})



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
	var along = str(args.get("along", "polyline")).strip_edges().to_lower()
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
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	if args.has("stamp_w") or args.has("tiles"):
		var tiles = PackedInt32Array()
		var tv: Variant = args.get("tiles", [])
		if typeof(tv) == TYPE_ARRAY:
			for v in tv:
				tiles.append(int(v))
		paint.set_stamp(maxi(int(args.get("stamp_w", 1)), 1), maxi(int(args.get("stamp_h", 1)), 1), tiles)
	elif args.has("tile_id"):
		paint.tile_id = int(args.get("tile_id"))
		paint.set_stamp(1, 1, PackedInt32Array([paint.tile_id]))
	var dirty: Array[Vector2i] = []
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	for spot in spots:
		var cell: Vector2i = spot
		if paint.has_stamp():
			dirty.append_array(paint.apply_stamp(d, cell))
		else:
			dirty.append_array(paint.apply_cell(d, cell, false))
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"scattered": spots.size(), "painted": dirty.size()})

func op_names() -> Array:
	return ["paint_rect", "paint_fill", "paint_cells", "paint_polyline", "paint_ellipse", "paint_ring", "paint_arc", "scatter", "set_passage", "refresh_autotiles"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("paint_rect", "矩形铺/擦，走自动图块。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"tile_id": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y"]),
		ctrl.mcp._tool("paint_fill", "同色填充，走自动图块。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"tile_id": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"},
		}, ["x", "y"]),
		ctrl.mcp._tool("paint_cells", "批量写格子。cells: [{x,y,tile_id?,z?,ext?}] 最多 16384。", {
			"cells": {"type": "array"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["cells"]),
		ctrl.mcp._tool("paint_polyline", "折线（河、路、墙）。points: [{x,y},…]，width 线宽。", {
			"points": {"type": "array"}, "tile_id": {"type": "integer"},
			"width": {"type": "integer"}, "z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["points", "tile_id"]),
		ctrl.mcp._tool("paint_ellipse", "椭圆。fill 默认 true；给 inner_rx/inner_ry 则成环。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"rx": {"type": "integer"}, "ry": {"type": "integer"},
			"tile_id": {"type": "integer"}, "fill": {"type": "boolean"},
			"inner_rx": {"type": "integer"}, "inner_ry": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y", "rx", "tile_id"]),
		ctrl.mcp._tool("paint_ring", "圆环/椭圆环。r 或 rx/ry，thickness 默认 1。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"r": {"type": "integer"}, "rx": {"type": "integer"}, "ry": {"type": "integer"},
			"thickness": {"type": "integer"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
			"erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}, ["x", "y", "tile_id"]),
		ctrl.mcp._tool("paint_arc", "圆弧。from_deg/to_deg，0=东 90=南（y 向下）。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"rx": {"type": "integer"}, "ry": {"type": "integer"},
			"from_deg": {"type": "number"}, "to_deg": {"type": "number"},
			"width": {"type": "integer"}, "tile_id": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y", "rx", "tile_id"]),
		ctrl.mcp._tool("scatter", "沿线/环按间距盖图章。along: polyline|ring。", {
			"along": {"type": "string"},
			"points": {"type": "array"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"r": {"type": "integer"}, "rx": {"type": "integer"}, "ry": {"type": "integer"},
			"spacing": {"type": "integer"},
			"tile_id": {"type": "integer"},
			"stamp_w": {"type": "integer"}, "stamp_h": {"type": "integer"}, "tiles": {"type": "array"},
			"z": {"type": "integer"},
		}),
		ctrl.mcp._tool("set_passage", "图块通行。kind: o|x|star；dirs: up,down,left,right 阻挡。", {
			"tile_id": {"type": "integer"},
			"kind": {"type": "string"},
			"up": {"type": "boolean"}, "down": {"type": "boolean"},
			"left": {"type": "boolean"}, "right": {"type": "boolean"},
		}, ["tile_id"]),
		ctrl.mcp._tool("refresh_autotiles", "重算整张地面自动图块接缝。", {}),
	]
