extends Control
## Draws ○ / × / ★ over a tile palette or map grid.

var kinds: PackedByteArray = PackedByteArray()
var cols: int = 8
var tile_px: int = 48


func set_grid(p_cols: int, p_tile_px: int, p_kinds: PackedByteArray) -> void:
	cols = maxi(p_cols, 1)
	tile_px = maxi(p_tile_px, 8)
	kinds = p_kinds
	queue_redraw()


func _draw() -> void:
	if kinds.is_empty() or tile_px <= 0:
		return
	var n := kinds.size()
	for i in range(n):
		var k := int(kinds[i])
		if k > 2:
			continue
		var col := i % cols
		var row := int(i / cols)
		var c := Vector2((float(col) + 0.5) * float(tile_px), (float(row) + 0.5) * float(tile_px))
		var r := float(tile_px) * 0.32
		match k:
			0:
				draw_arc(c, r, 0.0, TAU, 20, Color(0.25, 0.95, 0.4, 0.95), 2.0, true)
			1:
				var o := r * 0.75
				var red := Color(1.0, 0.25, 0.2, 0.95)
				draw_line(c + Vector2(-o, -o), c + Vector2(o, o), red, 2.0, true)
				draw_line(c + Vector2(o, -o), c + Vector2(-o, o), red, 2.0, true)
			2:
				draw_colored_polygon(
					PackedVector2Array([
						c + Vector2(0, -r),
						c + Vector2(r * 0.35, -r * 0.2),
						c + Vector2(r, -r * 0.15),
						c + Vector2(r * 0.4, r * 0.2),
						c + Vector2(r * 0.6, r),
						c + Vector2(0, r * 0.45),
						c + Vector2(-r * 0.6, r),
						c + Vector2(-r * 0.4, r * 0.2),
						c + Vector2(-r, -r * 0.15),
						c + Vector2(-r * 0.35, -r * 0.2),
					]),
					Color(1.0, 0.92, 0.25, 0.9)
				)
