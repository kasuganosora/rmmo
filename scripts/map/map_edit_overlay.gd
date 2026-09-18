extends Node2D
## Grid + start marker drawn above map chunks.

const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")

var _gfx_cache: Dictionary = {}


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
	var cc := 16
	if f.get("CHUNK_CELLS") != null:
		cc = maxi(int(f.CHUNK_CELLS), 1)
	if grid_width * grid_height > 65536 or (f.has_method("_uses_radar_window") and bool(f._uses_radar_window())):
		var ch_col := Color(0.35, 0.85, 1.0, 0.55)
		var cx0 := (x0 / cc) * cc
		var cy0 := (y0 / cc) * cc
		for x in range(cx0, x1 + 1, cc):
			var xpx := float(x) * ts
			draw_line(Vector2(xpx, y_px0), Vector2(xpx, y_px1), ch_col, 2.0)
		for y in range(cy0, y1 + 1, cc):
			var ypx2 := float(y) * ts
			draw_line(Vector2(x_px0, ypx2), Vector2(x_px1, ypx2), ch_col, 2.0)
		if f.has_method("current_chunk_rect"):
			var cr: Rect2i = f.current_chunk_rect()
			var rr := Rect2(Vector2(cr.position) * ts, Vector2(cr.size) * ts)
			draw_rect(rr, Color(1.0, 0.82, 0.2, 0.12), true)
			draw_rect(rr, Color(1.0, 0.82, 0.2, 0.9), false, 2.0)
	var show_pass := bool(f.get("edit_show_passage")) or bool(f.get("edit_passage_overlay"))
	if show_pass and f.has_method("edit_cell_passable"):
		var overlay := bool(f.get("edit_passage_overlay")) and not bool(f.get("edit_show_passage"))
		var fa := 0.45 if overlay else 0.85
		for y in range(y0, y1):
			for x in range(x0, x1):
				var st: int = int(f.edit_cell_passable(x, y))
				var c := Vector2((float(x) + 0.5) * ts, (float(y) + 0.5) * ts)
				var rad := ts * 0.28
				match st:
					0:
						draw_arc(c, rad, 0.0, TAU, 16, Color(0.2, 1.0, 0.35, fa), 2.0, true)
					1:
						var o := rad * 0.75
						var red := Color(1.0, 0.22, 0.18, fa)
						draw_line(c + Vector2(-o, -o), c + Vector2(o, o), red, 2.0, true)
						draw_line(c + Vector2(o, -o), c + Vector2(-o, o), red, 2.0, true)
					2:
						draw_arc(c, rad, 0.0, TAU, 16, Color(0.35, 0.75, 1.0, fa + 0.1), 2.0, true)
					3:
						var o2 := rad * 0.75
						var mag := Color(1.0, 0.45, 0.1, fa + 0.1)
						draw_line(c + Vector2(-o2, -o2), c + Vector2(o2, o2), mag, 2.5, true)
						draw_line(c + Vector2(o2, -o2), c + Vector2(-o2, o2), mag, 2.5, true)
	var spec := str(f.edit_spec_kind) if "edit_spec_kind" in f else ""
	if spec != "" and f.get("edit_doc") != null:
		_draw_spec(f.get("edit_doc"), spec, ts, x0, y0, x1, y1)
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
		var regs_v: Variant = edoc.get("regions") if typeof(edoc) == TYPE_OBJECT else []
		if typeof(regs_v) == TYPE_ARRAY:
			for rv in regs_v:
				if typeof(rv) != TYPE_DICTIONARY:
					continue
				var reg_r := Rect2(Vector2(int(rv.get("x", 0)), int(rv.get("y", 0))) * ts, Vector2(int(rv.get("w", 1)), int(rv.get("h", 1))) * ts)
				draw_rect(reg_r, Color(0.3, 0.7, 1.0, 0.12), true)
				draw_rect(reg_r, Color(0.4, 0.8, 1.0, 0.7), false, 1.0)
	var cursor: Vector2i = f.get("edit_cursor_cell")
	if cursor.x >= 0 and cursor.y >= 0:
		var cr := Rect2(Vector2(cursor) * ts, Vector2(ts, ts))
		draw_rect(cr, Color(1.0, 0.85, 0.2, 0.16), true)
		draw_rect(cr, Color(1.0, 0.82, 0.15, 0.95), false, 2.0)
	var hover: Vector2i = f.get("edit_hover_cell")
	if hover.x >= 0 and hover.y >= 0:
		var stamp: Vector2i = f.get("edit_stamp_size") if f.get("edit_stamp_size") != null else Vector2i(1, 1)
		var sw := maxi(int(stamp.x), 1)
		var sh := maxi(int(stamp.y), 1)
		var hr := Rect2(Vector2(hover) * ts, Vector2(ts * sw, ts * sh))
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
	var font: Font = ThemeDB.fallback_font
	var fs := maxi(int(ts * 0.32), 10)
	if "events" in edoc:
		for ev in edoc.events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var c: Variant = ev.get("cell", {})
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var cell := Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
			var pages_v: Variant = ev.get("pages", [])
			var page: Dictionary = {}
			if typeof(pages_v) == TYPE_ARRAY and not (pages_v as Array).is_empty() and typeof((pages_v as Array)[0]) == TYPE_DICTIONARY:
				page = (pages_v as Array)[0]
			var g: Dictionary = EventCommands.page_graphic(page)
			var pack_dir := ""
			var f := get_parent()
			if f != null and f.get("pack") != null:
				if "pack_dir" in f.pack:
					pack_dir = str(f.pack.pack_dir)
				elif "root" in f.pack:
					pack_dir = str(f.pack.root)
			if not _draw_charset(cell, ts, str(g.get("charset", "")), int(g.get("index", 0)), int(g.get("direction", 2)), pack_dir):
				_entity_mark(cell, ts, Color(0.95, 0.78, 0.12, 0.92), "E", font, fs)
	if "npcs" in edoc:
		for n in edoc.npcs:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var c2: Variant = n.get("cell", {})
			if typeof(c2) != TYPE_DICTIONARY:
				continue
			var ncell := Vector2i(int(c2.get("x", 0)), int(c2.get("y", 0)))
			var pack_dir2 := ""
			var f2 := get_parent()
			if f2 != null and f2.get("pack") != null and "pack_dir" in f2.pack:
				pack_dir2 = str(f2.pack.pack_dir)
			elif f2 != null and f2.get("pack") != null and "root" in f2.pack:
				pack_dir2 = str(f2.pack.root)
			var drawn := _draw_charset(ncell, ts, str(n.get("charset", "")), int(n.get("index", 0)), int(n.get("direction", 2)), pack_dir2)
			if not drawn:
				var mark := "M" if bool(n.get("hostile", false)) else "N"
				var col := Color(0.92, 0.28, 0.22, 0.92) if bool(n.get("hostile", false)) else Color(0.25, 0.62, 0.95, 0.92)
				_entity_mark(ncell, ts, col, mark, font, fs)
			elif bool(n.get("hostile", false)):
				var rr := Rect2(Vector2(ncell) * ts, Vector2(ts, ts))
				draw_rect(rr, Color(1.0, 0.2, 0.12, 0.9), false, 2.0)
	if "warps" in edoc:
		for w in edoc.warps:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var c3: Variant = w.get("from_cell", {})
			if typeof(c3) != TYPE_DICTIONARY:
				continue
			_entity_mark(Vector2i(int(c3.get("x", 0)), int(c3.get("y", 0))), ts, Color(0.78, 0.35, 0.95, 0.92), "W", font, fs)


func _draw_charset(cell: Vector2i, ts: float, charset: String, index: int, direction: int, pack_dir: String) -> bool:
	charset = charset.strip_edges()
	if charset == "":
		return false
	var key := "%s|%d|%d|%s" % [charset, index, direction, pack_dir]
	var tex: Texture2D = _gfx_cache.get(key)
	if tex == null and not _gfx_cache.has(key):
		var path: String = CharsetSheet.resolve_sheet_path(charset, pack_dir)
		var img: Image = CharsetSheet.load_image(path)
		tex = CharsetSheet.make_frame_texture(img, charset, index, direction, 1)
		_gfx_cache[key] = tex
	if tex == null:
		return false
	var r := Rect2(Vector2(cell) * ts, Vector2(ts, ts))
	draw_texture_rect(tex, r, false)
	return true


func _entity_mark(cell: Vector2i, ts: float, col: Color, letter: String, font: Font, fs: int) -> void:
	var r := Rect2(Vector2(cell) * ts + Vector2(ts * 0.12, ts * 0.12), Vector2(ts * 0.76, ts * 0.76))
	draw_rect(r, col, true)
	draw_rect(r, Color(0, 0, 0, 0.55), false, 1.2)
	if font:
		var sz := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, r.position + Vector2((r.size.x - sz.x) * 0.5, (r.size.y + sz.y) * 0.5 - 2.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.08, 0.1, 1))


func _draw_spec(edoc, kind: String, ts: float, x0: int, y0: int, x1: int, y1: int) -> void:
	var MapExt = load("res://scripts/map/map_ext.gd")
	for y in range(y0, y1):
		for x in range(x0, x1):
			var r := Rect2(Vector2(x, y) * ts, Vector2(ts, ts))
			match kind:
				"meta":
					if not edoc.has_method("ext_tile"):
						continue
					var m: int = int(edoc.ext_tile("meta", x, y))
					if m == 0:
						continue
					if (m & MapExt.META_INDOOR) != 0:
						draw_rect(r, Color(0.95, 0.75, 0.2, 0.28), true)
					if (m & MapExt.META_WATER) != 0:
						draw_rect(r, Color(0.2, 0.45, 1.0, 0.28), true)
					if (m & MapExt.META_NO_DASH) != 0:
						draw_rect(r, Color(1.0, 0.45, 0.1, 0.22), true)
					if (m & MapExt.META_FORCE_BLOCK) != 0:
						draw_rect(r, Color(1.0, 0.15, 0.1, 0.22), true)
					if (m & MapExt.META_FORCE_PASS) != 0:
						draw_rect(r, Color(0.2, 1.0, 0.35, 0.18), true)
				"settings":
					if not edoc.has_method("ext_tile"):
						continue
					var s: int = int(edoc.ext_tile("settings", x, y))
					if s == 0:
						continue
					var light: int = s & 0xff
					var col := Color(1.0, 0.85, 0.4, 0.22)
					if light == 2:
						col = Color(0.35, 0.45, 0.95, 0.32)
					elif light == 1:
						col = Color(1.0, 0.55, 0.25, 0.28)
					draw_rect(r, col, true)
				"shadow":
					var bits: int = int(edoc.tile(x, y, 4)) & 0x0f
					if bits == 0:
						continue
					var hw := ts * 0.5
					for i in range(4):
						if (bits & (1 << i)) == 0:
							continue
						var sr := Rect2(r.position + Vector2((i % 2) * hw, int(i / 2) * hw), Vector2(hw, hw))
						draw_rect(sr, Color(0, 0, 0, 0.35), true)
				"region":
					var rid: int = int(edoc.tile(x, y, 5))
					if rid <= 0:
						continue
					var hue := fmod(float(rid) * 0.17, 1.0)
					draw_rect(r, Color.from_hsv(hue, 0.55, 0.9, 0.28), true)
