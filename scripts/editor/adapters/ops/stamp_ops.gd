extends RefCounted
## Domain ops: stamps (set/paint/from_tileset/save/apply_named/list).

var ctrl
func _init(c):
	ctrl = c

const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")
const TilePalette = preload("res://scripts/editor/interface/tile_palette.gd")

func set_stamp(args: Dictionary) -> Dictionary:
	var w = maxi(int(args.get("w", 1)), 1)
	var h = maxi(int(args.get("h", 1)), 1)
	var tiles_v: Variant = args.get("tiles", [])
	var tiles = PackedInt32Array()
	if typeof(tiles_v) == TYPE_PACKED_INT32_ARRAY:
		tiles = tiles_v
	elif typeof(tiles_v) == TYPE_ARRAY:
		for v in tiles_v:
			tiles.append(int(v))
	if tiles.size() < w * h:
		return ctrl.mcp._err("tiles length < w*h")
	ctrl._ensure_paint().set_stamp(w, h, tiles)
	return ctrl.mcp._ok({"w": w, "h": h, "tile_id": int(ctrl._ensure_paint().tile_id)})



func paint_stamp(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	if not paint.has_stamp():
		return ctrl.mcp._err("no stamp")
	paint.tool = PaintTools.Tool.PENCIL
	var c: Vector2i = ctrl.mcp._cell(args)
	var dirty: Array[Vector2i] = paint.apply_stamp(d, c)
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"painted": dirty.size(), "x": c.x, "y": c.y})



func stamp_from_tileset(args: Dictionary) -> Dictionary:
	var tab = str(args.get("tab", "B")).to_upper()
	var col = int(args.get("col", 0))
	var row = int(args.get("row", 0))
	var w = clampi(int(args.get("w", 1)), 1, 8)
	var h = clampi(int(args.get("h", 1)), 1, 8)
	var tiles = PackedInt32Array()
	tiles.resize(w * h)
	var i = 0
	for y in range(h):
		for x in range(w):
			if tab == "A":
				tiles[i] = TilePalette.a_cell_to_id(col + x, row + y)
			else:
				tiles[i] = TilePalette.sheet_cell_to_id(col + x, row + y, ctrl._tab_base(tab))
			i += 1
	ctrl._ensure_paint().set_stamp(w, h, tiles)
	return ctrl.mcp._ok({"w": w, "h": h, "tile_id": int(tiles[0]) if tiles.size() > 0 else 0, "tiles": Array(tiles)})



func save_stamp(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	var paint = ctrl._ensure_paint()
	if p == null or paint == null:
		return ctrl.mcp._err("no pack")
	if not ("stamps" in p):
		p.stamps = {}
	var name = str(args.get("name", "")).strip_edges()
	if name == "":
		return ctrl.mcp._err("name required")
	var tiles: Array = []
	for t in paint.stamp_tiles:
		tiles.append(int(t))
	if tiles.is_empty():
		tiles.append(int(paint.tile_id))
	p.stamps[name] = {
		"w": int(paint.stamp_w),
		"h": int(paint.stamp_h),
		"tiles": tiles,
		"z": int(paint.layer_z),
		"ext": str(paint.ext_layer),
	}
	p.dirty = true
	return ctrl.mcp._ok({"name": name, "w": int(paint.stamp_w), "h": int(paint.stamp_h)})



func list_stamps() -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var stamps: Dictionary = p.stamps if "stamps" in p else {}
	var names: Array = stamps.keys()
	names.sort()
	return ctrl.mcp._ok({"stamps": names})



func apply_stamp_named(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null or not ("stamps" in p):
		return ctrl.mcp._err("no stamps")
	var name = str(args.get("name", ""))
	var st: Variant = p.stamps.get(name, {})
	if typeof(st) != TYPE_DICTIONARY or (st as Dictionary).is_empty():
		return ctrl.mcp._err("unknown stamp")
	var tiles = PackedInt32Array()
	for v in st.get("tiles", []):
		tiles.append(int(v))
	ctrl._ensure_paint().set_stamp(int(st.get("w", 1)), int(st.get("h", 1)), tiles)
	return paint_stamp(args)


