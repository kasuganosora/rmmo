extends RefCounted
## Domain ops: tiles clipboard/transform (copy/cut/paste/replace/rotate/flip).

var ctrl
func _init(c):
	ctrl = c

func copy_tiles(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var r: Dictionary = ctrl._clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return ctrl.mcp._err(str(r.get("msg", "bad rect")))
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	var clip: Dictionary = paint.copy_rect(d, Vector2i(int(r.x), int(r.y)), Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1))
	return ctrl.mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0)), "z": paint.layer_z, "ext": str(paint.ext_layer)})



func cut_tiles(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var r: Dictionary = ctrl._clamp_rect(args, int(d.width), int(d.height), 256)
	if bool(r.get("error", false)):
		return ctrl.mcp._err(str(r.get("msg", "bad rect")))
	ctrl._apply_layer(args)
	var paint = ctrl._ensure_paint()
	var dirty: Array[Vector2i] = paint.cut_rect(d, Vector2i(int(r.x), int(r.y)), Vector2i(int(r.x) + int(r.w) - 1, int(r.y) + int(r.h) - 1))
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"cut": dirty.size(), "w": int(r.w), "h": int(r.h)})



func paste_tiles(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var paint = ctrl._ensure_paint()
	if paint.clipboard.is_empty():
		return ctrl.mcp._err("tile clipboard empty")
	var c: Vector2i = ctrl.mcp._cell(args)
	var dirty: Array[Vector2i] = paint.paste_at(d, c)
	if not paint.exact_autotile:
		paint.refresh_autotiles(d, dirty, dirty)
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"pasted": dirty.size(), "x": c.x, "y": c.y})



func replace_tiles(args: Dictionary) -> Dictionary:
	ctrl._apply_layer(args)
	var dirty: Array[Vector2i] = ctrl._ensure_paint().replace_id(
		ctrl.doc(), int(args.get("old_id", 0)), int(args.get("new_id", 0)), bool(args.get("kind_match", true))
	)
	ctrl._touch(dirty)
	return ctrl.mcp._ok({"replaced": dirty.size()})



func rotate_tiles(args: Dictionary) -> Dictionary:
	var clip: Dictionary = ctrl._ensure_paint().rotate_clipboard(bool(args.get("cw", true)))
	return ctrl.mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0))})



func flip_tiles(args: Dictionary) -> Dictionary:
	var clip: Dictionary = ctrl._ensure_paint().flip_clipboard(bool(args.get("horizontal", true)))
	return ctrl.mcp._ok({"w": int(clip.get("w", 0)), "h": int(clip.get("h", 0))})

func op_names() -> Array:
	return ["copy_tiles", "cut_tiles", "paste_tiles", "replace_tiles", "rotate_tiles", "flip_tiles"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("copy_tiles", "复制当前层矩形到图块剪贴板。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		ctrl.mcp._tool("cut_tiles", "剪切当前层矩形。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}, ["x", "y"]),
		ctrl.mcp._tool("paste_tiles", "把图块剪贴板贴到目标格。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		ctrl.mcp._tool("replace_tiles", "整层替换 tile（自动图块比 kind）。", {
			"old_id": {"type": "integer"}, "new_id": {"type": "integer"},
			"z": {"type": "integer"}, "kind_match": {"type": "boolean"},
		}, ["old_id", "new_id"]),
		ctrl.mcp._tool("rotate_tiles", "旋转图块剪贴板。cw 默认 true。", {"cw": {"type": "boolean"}}),
		ctrl.mcp._tool("flip_tiles", "翻转图块剪贴板。horizontal 默认 true。", {"horizontal": {"type": "boolean"}}),
	]
