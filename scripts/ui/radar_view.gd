extends Control
## L2-style circular radar: 1px/cell atlas via GPU region + circle shader.
## Walking only updates region uniforms — no Image crop/mask/update on the walk path.

signal cell_clicked(cell: Vector2i)
signal cell_pinned(cell: Vector2i)

@export var fixed_north: bool = true
@export var show_party_stubs: bool = false
@export var show_monster_stubs: bool = false
@export var view_radius_tiles: float = 11.0
@export var sample_size: int = 128
## Display pixels per world pixel (derived from atlas + view_radius).
@export var world_scale: float = 0.5

const RadarCircleShader = preload("res://scripts/ui/radar_circle.gdshader")
const RadarPoi = preload("res://scripts/ui/radar_poi.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

var _yaw: float = PI * 0.5
var _target_angle: float = -1.0
var _party_angles: Array = [2.1, 4.0]

var _map_field: Node2D = null
var _center_world: Vector2 = Vector2.ZERO
var _last_sample_origin: Vector2i = Vector2i(2147483647, 2147483647)
var _last_diam_px: int = -1
var _map_id: String = ""
var _pending_size_redraw: bool = false
## [{ "world": Vector2, "hostile": bool }, ...]
var _entity_blips: Array = []
var _entity_blips_src: Array = []

var _terrain: ColorRect = null
var _terrain_mat: ShaderMaterial = null
var _atlas_tex: Texture2D = null
var _atlas_scale: float = 0.5
var _atlas_w: int = 0
var _atlas_h: int = 0
var _pin_cell: Vector2i = Vector2i(-9999, -9999)
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
const CLICK_THRESH := 8.0
const POI_HIT_PX := 12.0
var _pending_nav_label: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = RadarPoi.legend_text()
	_ensure_terrain()
	refresh_view_radius_from_settings()
	queue_redraw()


func _ensure_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		return
	_terrain = ColorRect.new()
	_terrain.name = "Terrain"
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.show_behind_parent = true
	_terrain.color = Color(1, 1, 1, 1)
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = RadarCircleShader
	_terrain.material = _terrain_mat
	add_child(_terrain)
	_terrain.visible = false


func bind_map_field(field: Node2D, map_id: String = "") -> void:
	_map_field = field
	_map_id = map_id
	_last_sample_origin = Vector2i(2147483647, 2147483647)
	_entity_blips_src = []
	_pull_atlas_from_field()
	_sync_terrain_region(true)
	queue_redraw()


func set_yaw(radians: float) -> void:
	_yaw = radians
	queue_redraw()


func set_target_angle(radians: float) -> void:
	_target_angle = radians
	queue_redraw()


func clear_target_angle() -> void:
	_target_angle = -1.0
	queue_redraw()


## Set how many tiles the circular radar covers. Smaller = zoomed in.
func set_view_radius(radius_tiles: float) -> void:
	var r: float = maxf(float(radius_tiles), 1.0)
	if is_equal_approx(view_radius_tiles, r):
		return
	view_radius_tiles = r
	_last_sample_origin = Vector2i(2147483647, 2147483647)
	_sync_terrain_region(true)
	queue_redraw()


## Re-read GameSettings.radar_view_radius (or keep export default).
func refresh_view_radius_from_settings() -> void:
	var gs := GameSettingsScript.get_i()
	if gs != null and "radar_view_radius" in gs:
		set_view_radius(float(gs.radar_view_radius))


func set_party_angles(angles: Array) -> void:
	_party_angles = angles.duplicate()
	queue_redraw()


## Accept blips: each item { "world": Vector2, "hostile": bool } or { "cell": ..., "hostile": bool }.
func set_entity_blips(blips: Array) -> void:
	# World returns a cached Array while NPC cells are stable; skip rebuild/redraw.
	if blips == _entity_blips_src:
		return
	_entity_blips_src = blips
	_entity_blips.clear()
	if blips.is_empty():
		queue_redraw()
		return
	for item in blips:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var world: Vector2 = Vector2.ZERO
		var has_world := false
		if d.has("world") and typeof(d["world"]) == TYPE_VECTOR2:
			world = d["world"]
			has_world = true
		elif d.has("cell"):
			var cell_v: Variant = d["cell"]
			var cell := Vector2i.ZERO
			var ok_cell := false
			if typeof(cell_v) == TYPE_VECTOR2I:
				cell = cell_v
				ok_cell = true
			elif typeof(cell_v) == TYPE_DICTIONARY:
				cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
				ok_cell = true
			if ok_cell and _map_field != null and _map_field.has_method("cell_to_world"):
				world = _map_field.cell_to_world(cell)
				has_world = true
		if not has_world:
			continue
		var kind := str(d.get("kind", "")).strip_edges()
		_entity_blips.append({
			"world": world,
			"hostile": bool(d.get("hostile", false)),
			"kind": kind,
		})
	queue_redraw()


## Push player world center + facing; scrolls atlas window via shader uniforms only.
func update_view(center_world: Vector2, facing_radians: float) -> void:
	_center_world = center_world
	_yaw = facing_radians
	_sync_terrain_region(false)
	queue_redraw()


func set_pin_cell(cell: Vector2i) -> void:
	_pin_cell = cell
	queue_redraw()


func local_to_cell(local: Vector2) -> Vector2i:
	var c := size * 0.5
	var sc: float = world_scale
	if sc <= 0.001:
		sc = 0.5
	var world: Vector2 = _center_world + (local - c) / sc
	if _map_field != null and _map_field.has_method("world_to_cell"):
		return _map_field.world_to_cell(world)
	var ts := 48.0
	if _map_field != null and "tile_size" in _map_field:
		ts = float(maxi(int(_map_field.tile_size), 1))
	return Vector2i(int(floor(world.x / ts)), int(floor(world.y / ts)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				# Wheel up = zoom in (smaller radius); down = zoom out.
				var dir: int = -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				var gs := GameSettingsScript.get_i()
				if gs != null and gs.has_method("cycle_radar_view_radius"):
					gs.cycle_radar_view_radius(dir)
				elif gs != null and gs.has_method("set_radar_view_radius"):
					var cur: int = int(gs.radar_view_radius) if "radar_view_radius" in gs else int(view_radius_tiles)
					gs.set_radar_view_radius(cur + dir * 3)
				# Never let wheel scroll a parent ScrollContainer while over radar.
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
			else:
				if _pressing and mb.position.distance_to(_press_pos) <= CLICK_THRESH:
					var poi_hit: Dictionary = pick_poi_at(mb.position)
					var cell: Vector2i
					if poi_hit.is_empty():
						cell = local_to_cell(mb.position)
						_pending_nav_label = ""
					else:
						var bw: Vector2 = poi_hit.get("world", Vector2.ZERO)
						if _map_field != null and _map_field.has_method("world_to_cell"):
							cell = _map_field.world_to_cell(bw)
						else:
							var ts := 48.0
							if _map_field != null and "tile_size" in _map_field:
								ts = float(maxi(int(_map_field.tile_size), 1))
							cell = Vector2i(int(floor(bw.x / ts)), int(floor(bw.y / ts)))
						var name_s := str(poi_hit.get("name", "")).strip_edges()
						_pending_nav_label = name_s if name_s != "" else RadarPoi.label_for_kind(str(poi_hit.get("kind", "")))
					if mb.button_index == MOUSE_BUTTON_RIGHT or mb.shift_pressed:
						cell_pinned.emit(cell)
					else:
						cell_clicked.emit(cell)
				_pressing = false
			accept_event()


## Pop last click's POI label (empty if empty-cell click).
func consume_nav_label() -> String:
	var s := _pending_nav_label
	_pending_nav_label = ""
	return s


## Screen pos of a world point on the radar disc.
func _world_to_local(world: Vector2) -> Vector2:
	var c := size * 0.5
	var sc: float = world_scale
	if sc <= 0.001:
		sc = 0.5
	return c + (world - _center_world) * sc


## Nearest POI-kind blip within hit_px, or {}.
func pick_poi_at(local: Vector2, hit_px: float = POI_HIT_PX) -> Dictionary:
	if _entity_blips.is_empty() or hit_px <= 0.0:
		return {}
	var best: Dictionary = {}
	var best_d2: float = hit_px * hit_px
	for blip in _entity_blips:
		if typeof(blip) != TYPE_DICTIONARY:
			continue
		var kind := str(blip.get("kind", "")).strip_edges()
		if kind.is_empty():
			continue
		var bw: Vector2 = blip.get("world", Vector2.ZERO)
		var pos := _world_to_local(bw)
		var d2: float = local.distance_squared_to(pos)
		if d2 <= best_d2:
			best_d2 = d2
			best = blip
	return best


func resolve_nav_cell(local: Vector2, hit_px: float = POI_HIT_PX) -> Vector2i:
	var hit: Dictionary = pick_poi_at(local, hit_px)
	if hit.is_empty():
		return local_to_cell(local)
	var bw: Vector2 = hit.get("world", Vector2.ZERO)
	if _map_field != null and _map_field.has_method("world_to_cell"):
		return _map_field.world_to_cell(bw)
	var ts := 48.0
	if _map_field != null and "tile_size" in _map_field:
		ts = float(maxi(int(_map_field.tile_size), 1))
	return Vector2i(int(floor(bw.x / ts)), int(floor(bw.y / ts)))


func resolve_nav_label(local: Vector2, hit_px: float = POI_HIT_PX) -> String:
	var hit: Dictionary = pick_poi_at(local, hit_px)
	if hit.is_empty():
		return ""
	# Blips may only carry kind; use kind label when name absent.
	var name_s := str(hit.get("name", "")).strip_edges()
	if name_s != "":
		return name_s
	return RadarPoi.label_for_kind(str(hit.get("kind", "")))


func hint_text() -> String:
	if _map_field == null:
		return _map_id if _map_id != "" else "map"
	var cell: Vector2i = Vector2i.ZERO
	if _map_field.has_method("world_to_cell"):
		cell = _map_field.world_to_cell(_center_world)
	elif "tile_size" in _map_field:
		var ts: float = float(_map_field.tile_size)
		cell = Vector2i(int(floor(_center_world.x / ts)), int(floor(_center_world.y / ts)))
	var mid := _map_id
	if mid.is_empty() and "pack_path" in _map_field:
		mid = str(_map_field.pack_path).get_file()
	if mid.is_empty():
		mid = "map"
	return "%s\n(%d, %d)" % [mid, cell.x, cell.y]


## Odd display diameter (~92% of control). World coverage = diam / world_scale.
func _diam_px_from_size() -> int:
	var m: float = minf(size.x, size.y)
	var d: int = int(round(m * 0.92))
	if d < 8:
		return 0
	if (d & 1) == 0:
		d -= 1
	return maxi(d, 9)


func _pull_atlas_from_field() -> void:
	_atlas_tex = null
	_atlas_w = 0
	_atlas_h = 0
	_atlas_scale = world_scale if world_scale > 0.001 else 0.5
	if _map_field == null:
		return
	if _map_field.has_method("get_radar_atlas_scale"):
		var sc: float = float(_map_field.get_radar_atlas_scale())
		if sc > 0.001:
			_atlas_scale = sc
	if _map_field.has_method("get_radar_atlas_texture"):
		_atlas_tex = _map_field.get_radar_atlas_texture()
	if _atlas_tex != null:
		_atlas_w = _atlas_tex.get_width()
		_atlas_h = _atlas_tex.get_height()


func _radar_world_side() -> float:
	var ts := 48.0
	if _map_field != null and "tile_size" in _map_field:
		ts = float(maxi(int(_map_field.tile_size), 1))
	return maxf(view_radius_tiles, 1.0) * 2.0 * ts


func _sync_terrain_region(force: bool) -> void:
	_ensure_terrain()
	if _atlas_tex == null:
		_pull_atlas_from_field()
	var diam: int = _diam_px_from_size()
	if diam <= 0 or _atlas_tex == null or _atlas_w <= 0:
		_terrain.visible = false
		if diam <= 0 and not _pending_size_redraw:
			_pending_size_redraw = true
			call_deferred("queue_redraw")
		return
	_pending_size_redraw = false

	var sc: float = _atlas_scale
	if sc <= 0.001:
		sc = 0.5
	var world_side: float = _radar_world_side()
	var atlas_side: float = maxf(world_side * sc, 1.0)
	var origin_cell := Vector2i.ZERO
	if _map_field != null and _map_field.has_method("get_radar_origin_cell"):
		origin_cell = _map_field.get_radar_origin_cell()
	var acx: float = _center_world.x * sc - float(origin_cell.x)
	var acy: float = _center_world.y * sc - float(origin_cell.y)
	var origin := Vector2i(int(floor(acx - atlas_side * 0.5)), int(floor(acy - atlas_side * 0.5)))
	if not force and origin == _last_sample_origin and diam == _last_diam_px and _terrain.visible:
		return
	_last_sample_origin = origin
	_last_diam_px = diam
	world_scale = float(diam) / world_side

	var c := size * 0.5
	var r := float(diam) * 0.5
	_terrain.position = Vector2(floor(c.x - r), floor(c.y - r))
	_terrain.size = Vector2(diam, diam)
	_terrain.visible = true

	if _terrain_mat != null:
		_terrain_mat.set_shader_parameter("atlas_tex", _atlas_tex)
		_terrain_mat.set_shader_parameter("atlas_pixel_size", Vector2(_atlas_w, _atlas_h))
		_terrain_mat.set_shader_parameter("region_origin_px", Vector2(origin))
		_terrain_mat.set_shader_parameter("region_side_px", atlas_side)
		_terrain_mat.set_shader_parameter("fill_color", Color(0.08, 0.10, 0.09, 1.0))


func _draw() -> void:
	var diam: int = _diam_px_from_size()
	if diam <= 0:
		if not _pending_size_redraw:
			_pending_size_redraw = true
			call_deferred("queue_redraw")
		return

	# Size may become valid only after layout; sync GPU window if diam changed.
	if _map_field != null and (diam != _last_diam_px or not _terrain.visible):
		_sync_terrain_region(true)

	var c := size * 0.5
	var r := float(diam) * 0.5

	# Outer rim only — inner rings caused concentric moiré over scrolling terrain.
	draw_arc(c, r, 0.0, TAU, 64, Color(0.55, 0.55, 0.5, 0.9), 2.0, true)

	var north := -PI * 0.5
	if not fixed_north:
		north -= _yaw
	_draw_marker(c + Vector2(cos(north), sin(north)) * (r - 10.0), "N", Color(0.95, 0.9, 0.55))

	# NPC / entity blips (same scale as terrain sample: world_scale px per world unit).
	var blip_scale: float = world_scale
	if blip_scale <= 0.001:
		blip_scale = 0.5
	var r2: float = r * r
	var rim_r: float = maxf(r - 2.0, 1.0)
	var rim_blips: Array = []
	for blip in _entity_blips:
		if typeof(blip) != TYPE_DICTIONARY:
			continue
		var bw: Vector2 = blip.get("world", Vector2.ZERO)
		var offset: Vector2 = (bw - _center_world) * blip_scale
		var hostile := bool(blip.get("hostile", false))
		var kind := str(blip.get("kind", "")).strip_edges()
		if offset.length_squared() <= r2:
			draw_circle(c + offset, 3.0, _blip_color(hostile, kind))
		else:
			var dir := offset.normalized()
			if dir.length_squared() < 0.0001:
				continue
			rim_blips.append({ "pos": dir * rim_r, "hostile": hostile, "kind": kind })
	for merged in _merge_rim_blips(rim_blips, 10.0, rim_r):
		var mcol := _blip_color(bool(merged.get("hostile", false)), str(merged.get("kind", "")))
		draw_circle(c + merged["pos"], 3.5, mcol)

	# Gold self arrow: tip points along facing (screen +y down).
	var yaw := _yaw
	if not fixed_north:
		yaw = 0.0
	var tip := c + Vector2(cos(yaw), sin(yaw)) * 10.0
	var left := c + Vector2(cos(yaw + 2.45), sin(yaw + 2.45)) * 7.0
	var right := c + Vector2(cos(yaw - 2.45), sin(yaw - 2.45)) * 7.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.95, 0.78, 0.2))

	if _target_angle >= 0.0:
		var ta := _target_angle
		if not fixed_north:
			ta -= _yaw
		var tp := c + Vector2(cos(ta), sin(ta)) * (r * 0.72)
		draw_circle(tp, 4.0, Color(0.9, 0.2, 0.2))

	if show_party_stubs:
		for ang in _party_angles:
			var a := float(ang)
			if not fixed_north:
				a -= _yaw
			var pp := c + Vector2(cos(a), sin(a)) * (r * 0.55)
			draw_circle(pp, 3.0, Color(0.25, 0.85, 0.35))
	if show_monster_stubs:
		draw_circle(c + Vector2(18, -22), 2.5, Color(0.85, 0.55, 0.2))
		draw_circle(c + Vector2(-26, 12), 2.5, Color(0.85, 0.55, 0.2))

	if _pin_cell.x > -9990:
		var pin_world := Vector2(float(_pin_cell.x) + 0.5, float(_pin_cell.y) + 0.5) * 48.0
		if _map_field != null and _map_field.has_method("cell_to_world"):
			pin_world = _map_field.cell_to_world(_pin_cell)
		var poffset: Vector2 = (pin_world - _center_world) * blip_scale
		if poffset.length_squared() <= r2:
			var pp := c + poffset
			draw_circle(pp, 5.0, Color(0.2, 0.9, 0.95, 0.95))
			draw_arc(pp, 7.0, 0.0, TAU, 16, Color(0.85, 0.95, 1.0, 0.9), 1.5, true)


## Greedy-cluster rim blips within merge_dist; average pos, re-project onto circle. Hostile wins.
func _merge_rim_blips(rim_blips: Array, merge_dist: float, rim_r: float) -> Array:
	var result: Array = []
	var n: int = rim_blips.size()
	if n == 0:
		return result
	var claimed := PackedByteArray()
	claimed.resize(n)
	var merge_dist2: float = merge_dist * merge_dist
	for i in range(n):
		if claimed[i] != 0:
			continue
		claimed[i] = 1
		var seed: Dictionary = rim_blips[i]
		var seed_pos: Vector2 = seed.get("pos", Vector2.ZERO)
		var sum: Vector2 = seed_pos
		var count: int = 1
		var hostile := bool(seed.get("hostile", false))
		var kind := str(seed.get("kind", "")).strip_edges()
		for j in range(i + 1, n):
			if claimed[j] != 0:
				continue
			var other: Dictionary = rim_blips[j]
			var op: Vector2 = other.get("pos", Vector2.ZERO)
			if seed_pos.distance_squared_to(op) <= merge_dist2:
				claimed[j] = 1
				sum += op
				count += 1
				if bool(other.get("hostile", false)):
					hostile = true
				var okind := str(other.get("kind", "")).strip_edges()
				if kind.is_empty() and okind != "":
					kind = okind
		var avg: Vector2 = sum / float(count)
		var dir := avg.normalized()
		if dir.length_squared() < 0.0001:
			dir = seed_pos.normalized()
		if dir.length_squared() < 0.0001:
			continue
		result.append({ "pos": dir * rim_r, "hostile": hostile, "kind": kind })
	return result


func _blip_color(hostile: bool, kind: String) -> Color:
	if hostile:
		return Color(0.9, 0.2, 0.2)
	kind = kind.strip_edges()
	if kind != "":
		return RadarPoi.color_for_kind(kind)
	return Color(0.25, 0.85, 0.35)


func _draw_marker(pos: Vector2, text: String, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos + Vector2(-4, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)