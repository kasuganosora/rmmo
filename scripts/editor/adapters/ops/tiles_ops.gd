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


