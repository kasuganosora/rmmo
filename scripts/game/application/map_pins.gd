extends RefCounted
## Application layer: map pin bookmarks and server POI sync.

const Net = preload("res://scripts/net/net.gd")
const RadarPoi = preload("res://scripts/ui/radar_poi.gd")

static func _map_poi_label_at(ctrl, cell: Vector2i) -> String:
	var markers: Array = ctrl.get_radar_poi_markers() if ctrl.has_method("get_radar_poi_markers") else []
	var hit: Dictionary = RadarPoi.marker_at_cell(markers, cell)
	if hit.is_empty():
		return ""
	return RadarPoi.marker_nav_label(hit)

static func toggle_map_pin(ctrl, cell: Vector2i, short_name: String = "") -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_map_pin_toggle"):
		var mid = str(srv.map_pack_id) if "map_pack_id" in srv else ""
		var result: Dictionary = srv.try_map_pin_toggle(cell.x, cell.y, mid, short_name)
		var actions_v: Variant = result.get("actions", [])
		if typeof(actions_v) == TYPE_ARRAY:
			ctrl._apply_server_actions(actions_v)
		ctrl._sync_map_pins_from_server(result.get("map_pins", {}))
		ctrl._radar_blips_ready = false
		return
	# Legacy single-pin fallback (no MockServer).
	if ctrl._map_pin == cell:
		ctrl._map_pin = Vector2i(-9999, -9999)
		if ctrl.hud != null and ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system("已清除地图标记")
	else:
		ctrl._map_pin = cell
		if ctrl.hud != null and ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system("标记 (%d, %d)" % [cell.x, cell.y])
	if ctrl.hud != null and ctrl.hud.has_method("set_map_pin"):
		ctrl.hud.set_map_pin(ctrl._map_pin)

static func clear_map_pins(ctrl) -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_map_pin_clear"):
		var result: Dictionary = srv.try_map_pin_clear()
		var actions_v: Variant = result.get("actions", [])
		if typeof(actions_v) == TYPE_ARRAY:
			ctrl._apply_server_actions(actions_v)
		ctrl._sync_map_pins_from_server(result.get("map_pins", {}))
		ctrl._radar_blips_ready = false
		return
	ctrl._map_pin = Vector2i(-9999, -9999)
	if ctrl.hud != null and ctrl.hud.has_method("set_map_pin"):
		ctrl.hud.set_map_pin(ctrl._map_pin)
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("已清除全部标记")

static func _sync_map_pins_from_server(ctrl, snap: Variant) -> void:
	var pins: Array = []
	if typeof(snap) == TYPE_DICTIONARY:
		var pv: Variant = snap.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			pins = pv
	elif typeof(snap) == TYPE_ARRAY:
		pins = snap
	# Legacy first-pin cell for shell/HUD set_pin_cell.
	ctrl._map_pin = Vector2i(-9999, -9999)
	for p in pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var cell_v: Variant = p.get("cell", {})
		if typeof(cell_v) == TYPE_VECTOR2I:
			ctrl._map_pin = cell_v
		elif typeof(cell_v) == TYPE_DICTIONARY:
			ctrl._map_pin = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
		break
	if ctrl.hud != null and ctrl.hud.has_method("apply_map_pins_update"):
		ctrl.hud.apply_map_pins_update({"type": "map_pins_update", "map_pins": {"pins": pins, "count": pins.size()}})
	elif ctrl.hud != null and ctrl.hud.has_method("set_map_pin"):
		ctrl.hud.set_map_pin(ctrl._map_pin)

static func map_pin_cell(ctrl) -> Vector2i:
	return ctrl._map_pin

static func map_pins_snapshot(ctrl) -> Array:
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_map_pins"):
		var snap: Dictionary = srv.snapshot_map_pins()
		var pv: Variant = snap.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			return pv
	return []

