extends RefCounted
## Cell geometry for paint tools and MCP (polyline, ellipse, ring gaps, scatter).


static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
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


static func polyline_cells(pts: Array[Vector2i], width: int = 1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if pts.is_empty():
		return cells
	if pts.size() == 1:
		cells.append(pts[0])
		return thicken(cells, width)
	for i in range(pts.size() - 1):
		cells.append_array(line_cells(pts[i], pts[i + 1]))
	return thicken(cells, width)


static func thicken(cells: Array[Vector2i], width: int) -> Array[Vector2i]:
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


static func ellipse_cells(cx: int, cy: int, rx: int, ry: int, fill: bool = true) -> Array[Vector2i]:
	var filled: Array[Vector2i] = []
	rx = maxi(rx, 0)
	ry = maxi(ry, 0)
	var rr := maxi(ry * ry, 1)
	for y in range(-ry, ry + 1):
		var span := int(floor(float(rx) * sqrt(maxf(0.0, 1.0 - float(y * y) / float(rr)))))
		for x in range(-span, span + 1):
			filled.append(Vector2i(cx + x, cy + y))
	if fill:
		return filled
	var inner: Array[Vector2i] = ellipse_cells(cx, cy, maxi(rx - 1, 0), maxi(ry - 1, 0), true)
	var drop := {}
	for c in inner:
		drop["%d,%d" % [c.x, c.y]] = true
	var out: Array[Vector2i] = []
	for c2 in filled:
		if not drop.has("%d,%d" % [c2.x, c2.y]):
			out.append(c2)
	return out


static func ring_cells(cx: int, cy: int, rx: int, ry: int, thickness: int = 1, openings: Array = []) -> Array[Vector2i]:
	rx = maxi(rx, 0)
	ry = maxi(ry, rx if ry <= 0 else ry)
	var thick := maxi(thickness, 1)
	var outer: Array[Vector2i] = ellipse_cells(cx, cy, rx, ry, true)
	var irx := maxi(rx - thick, -1)
	var iry := maxi(ry - thick, -1)
	var ring: Array[Vector2i] = []
	if irx < 0:
		ring = outer
	else:
		var inner: Array[Vector2i] = ellipse_cells(cx, cy, irx, iry, true)
		var drop := {}
		for c in inner:
			drop["%d,%d" % [c.x, c.y]] = true
		for c2 in outer:
			if not drop.has("%d,%d" % [c2.x, c2.y]):
				ring.append(c2)
	if openings.is_empty():
		return ring
	var keep: Array[Vector2i] = []
	for c3 in ring:
		if not _in_opening(cx, cy, c3, openings):
			keep.append(c3)
	return keep


static func arc_cells(cx: int, cy: int, rx: int, ry: int, from_deg: float, to_deg: float, width: int = 1) -> Array[Vector2i]:
	var ring: Array[Vector2i] = ring_cells(cx, cy, rx, ry, maxi(width, 1), [])
	var a0 := deg_to_rad(from_deg)
	var a1 := deg_to_rad(to_deg)
	var out: Array[Vector2i] = []
	for c in ring:
		var ang := atan2(float(c.y - cy), float(c.x - cx))
		if _angle_in(ang, a0, a1):
			out.append(c)
	return out


static func scatter_along(path: Array[Vector2i], spacing: int) -> Array[Vector2i]:
	spacing = maxi(spacing, 1)
	var out: Array[Vector2i] = []
	var seen := {}
	var acc := 0
	var prev := Vector2i(2147483647, 2147483647)
	for c in path:
		var k := "%d,%d" % [c.x, c.y]
		if seen.has(k):
			continue
		seen[k] = true
		if prev.x != 2147483647:
			acc += maxi(absi(c.x - prev.x) + absi(c.y - prev.y), 1)
		if out.is_empty() or acc >= spacing:
			out.append(c)
			acc = 0
		prev = c
	return out


static func unique(cells: Array[Vector2i]) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for c in cells:
		var k := "%d,%d" % [c.x, c.y]
		if seen.has(k):
			continue
		seen[k] = true
		out.append(c)
	return out


static func _in_opening(cx: int, cy: int, c: Vector2i, openings: Array) -> bool:
	var ang := atan2(float(c.y - cy), float(c.x - cx))
	for item in openings:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var mid := deg_to_rad(float(d.get("deg", d.get("from_deg", 0))))
		var half := deg_to_rad(float(d.get("width_deg", d.get("arc", 24))) * 0.5)
		if d.has("from_deg") and d.has("to_deg"):
			if _angle_in(ang, deg_to_rad(float(d.get("from_deg"))), deg_to_rad(float(d.get("to_deg")))):
				return true
			continue
		if absf(_angle_delta(ang, mid)) <= half:
			return true
	return false


static func _angle_in(ang: float, a0: float, a1: float) -> bool:
	var d := _angle_delta(a1, a0)
	if d < 0.0:
		d += TAU
	var t := _angle_delta(ang, a0)
	if t < 0.0:
		t += TAU
	return t <= d + 0.001


static func _angle_delta(a: float, b: float) -> float:
	var d := a - b
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return d
