extends Node2D
## Grid + start marker drawn above map chunks.


func _process(_delta: float) -> void:
	var f := get_parent()
	if f != null and bool(f.get("edit_mode")) and bool(f.get("show_grid")):
		queue_redraw()


func _draw() -> void:
	var f := get_parent()
	if f == null or not bool(f.get("edit_mode")) or not bool(f.get("show_grid")):
		return
	var tile_size: int = int(f.get("tile_size"))
	var grid_width: int = int(f.get("grid_width"))
	var grid_height: int = int(f.get("grid_height"))
	if tile_size <= 0:
		return
	var ts := float(tile_size)
	var vp := get_viewport()
	var x0 := 0
	var y0 := 0
	var x1 := grid_width
	var y1 := grid_height
	if vp:
		var vis: Rect2 = vp.get_visible_rect()
		var inv: Transform2D = vp.get_canvas_transform().affine_inverse()
		var a: Vector2 = inv * vis.position
		var b: Vector2 = inv * (vis.position + vis.size)
		x0 = clampi(int(floor(minf(a.x, b.x) / ts)) - 1, 0, grid_width)
		y0 = clampi(int(floor(minf(a.y, b.y) / ts)) - 1, 0, grid_height)
		x1 = clampi(int(ceil(maxf(a.x, b.x) / ts)) + 1, 0, grid_width)
		y1 = clampi(int(ceil(maxf(a.y, b.y) / ts)) + 1, 0, grid_height)
	var col := Color(1, 1, 1, 0.18)
	var y_px0 := float(y0) * ts
	var y_px1 := float(y1) * ts
	for x in range(x0, x1 + 1):
		var xpx := float(x) * ts
		draw_line(Vector2(xpx, y_px0), Vector2(xpx, y_px1), col, 1.0)
	var x_px0 := float(x0) * ts
	var x_px1 := float(x1) * ts
	for y in range(y0, y1 + 1):
		var ypx := float(y) * ts
		draw_line(Vector2(x_px0, ypx), Vector2(x_px1, ypx), col, 1.0)
	if bool(f.get("edit_show_passage")) and f.has_method("edit_cell_passable"):
		for y in range(y0, y1):
			for x in range(x0, x1):
				var st: int = int(f.edit_cell_passable(x, y))
				var c := Vector2((float(x) + 0.5) * ts, (float(y) + 0.5) * ts)
				var rad := ts * 0.28
				match st:
					0:
						draw_arc(c, rad, 0.0, TAU, 16, Color(0.2, 1.0, 0.35, 0.85), 2.0, true)
					1:
						var o := rad * 0.75
						var red := Color(1.0, 0.22, 0.18, 0.85)
						draw_line(c + Vector2(-o, -o), c + Vector2(o, o), red, 2.0, true)
						draw_line(c + Vector2(o, -o), c + Vector2(-o, o), red, 2.0, true)
					2:
						draw_arc(c, rad, 0.0, TAU, 16, Color(0.35, 0.75, 1.0, 0.95), 2.0, true)
					3:
						var o2 := rad * 0.75
						var mag := Color(1.0, 0.45, 0.1, 0.95)
						draw_line(c + Vector2(-o2, -o2), c + Vector2(o2, o2), mag, 2.5, true)
						draw_line(c + Vector2(o2, -o2), c + Vector2(-o2, o2), mag, 2.5, true)
	var ra: Vector2i = f.get("edit_rect_a")
	var rb: Vector2i = f.get("edit_rect_b")
	if ra.x >= 0 and rb.x >= 0:
		var rx0 := mini(ra.x, rb.x)
		var ry0 := mini(ra.y, rb.y)
		var rx1 := maxi(ra.x, rb.x) + 1
		var ry1 := maxi(ra.y, rb.y) + 1
		var rr := Rect2(Vector2(rx0, ry0) * ts, Vector2(rx1 - rx0, ry1 - ry0) * ts)
		draw_rect(rr, Color(0.3, 0.75, 1.0, 0.18), true)
		draw_rect(rr, Color(0.45, 0.85, 1.0, 0.9), false, 1.5)
	var edoc = f.get("edit_doc")
	if edoc != null:
		_draw_entities(edoc, ts)
	var hover: Vector2i = f.get("edit_hover_cell")
	if hover.x >= 0 and hover.y >= 0:
		var hr := Rect2(Vector2(hover) * ts, Vector2(ts, ts))
		draw_rect(hr, Color(1.0, 1.0, 1.0, 0.12), true)
		draw_rect(hr, Color(1.0, 1.0, 1.0, 0.85), false, 1.5)
	var start: Vector2i = f.get("edit_start_cell")
	if start.x >= 0 and start.y >= 0:
		var r := Rect2(Vector2(start) * ts, Vector2(ts, ts))
		draw_rect(r, Color(1.0, 0.28, 0.12, 0.45), true)
		draw_rect(r, Color(1.0, 0.92, 0.25, 1), false, 2.0)
		var pin := Vector2(r.position.x + ts * 0.5, r.position.y + ts * 0.22)
		draw_circle(pin, ts * 0.16, Color(1, 0.95, 0.4, 1))


func _draw_entities(edoc, ts: float) -> void:
	if "events" in edoc:
		for ev in edoc.events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var c: Variant = ev.get("cell", {})
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var p := Vector2((float(c.get("x", 0)) + 0.5) * ts, (float(c.get("y", 0)) + 0.5) * ts)
			draw_circle(p, ts * 0.18, Color(0.95, 0.85, 0.2, 0.9))
	if "npcs" in edoc:
		for n in edoc.npcs:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var c2: Variant = n.get("cell", {})
			if typeof(c2) != TYPE_DICTIONARY:
				continue
			var p2 := Vector2((float(c2.get("x", 0)) + 0.5) * ts, (float(c2.get("y", 0)) + 0.5) * ts)
			draw_circle(p2, ts * 0.18, Color(0.3, 0.7, 1.0, 0.9))
	if "warps" in edoc:
		for w in edoc.warps:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var c3: Variant = w.get("from_cell", {})
			if typeof(c3) != TYPE_DICTIONARY:
				continue
			var p3 := Vector2((float(c3.get("x", 0)) + 0.5) * ts, (float(c3.get("y", 0)) + 0.5) * ts)
			draw_rect(Rect2(p3 - Vector2(ts * 0.2, ts * 0.2), Vector2(ts * 0.4, ts * 0.4)), Color(0.9, 0.4, 1.0, 0.85), false, 2.0)
