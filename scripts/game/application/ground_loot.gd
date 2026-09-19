extends RefCounted
## Application layer: ground loot bags (spawn marker, icon resolve, tooltip, hover).

const Net = preload("res://scripts/net/net.gd")

static func _clear_ground_markers(ctrl) -> void:
	ctrl._hovered_ground_bag_id = ""
	if ctrl.hud != null and ctrl.hud.has_method("hide_ground_tip"):
		ctrl.hud.hide_ground_tip()
	for bid in ctrl._ground_markers.keys():
		var n = ctrl._ground_markers[bid]
		if n != null and is_instance_valid(n):
			n.queue_free()
	ctrl._ground_markers.clear()
	if ctrl._ground_layer != null and is_instance_valid(ctrl._ground_layer):
		for c in ctrl._ground_layer.get_children():
			c.queue_free()

static func _ensure_ground_layer(ctrl) -> Node2D:
	if ctrl._ground_layer != null and is_instance_valid(ctrl._ground_layer):
		return ctrl._ground_layer
	ctrl._ground_layer = ctrl.get_node_or_null("GroundBagLayer") as Node2D
	if ctrl._ground_layer == null:
		ctrl._ground_layer = Node2D.new()
		ctrl._ground_layer.name = "GroundBagLayer"
		ctrl._ground_layer.z_index = 4
		ctrl._ground_layer.z_as_relative = false
		ctrl.add_child(ctrl._ground_layer)
		if ctrl.map_field != null:
			ctrl.move_child(ctrl._ground_layer, ctrl.map_field.get_index() + 1)
	return ctrl._ground_layer

static func _upsert_ground_marker(ctrl, bag: Dictionary) -> void:
	var bag_id = str(bag.get("id", "")).strip_edges()
	if bag_id.is_empty():
		return
	var items_v: Variant = bag.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		ctrl._apply_ground_despawn({"bag_id": bag_id})
		return
	var cell_v: Variant = bag.get("cell", {"x": 0, "y": 0})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var layer = ctrl._ensure_ground_layer()
	var marker: Node2D = null
	if ctrl._ground_markers.has(bag_id) and is_instance_valid(ctrl._ground_markers[bag_id]):
		marker = ctrl._ground_markers[bag_id]
	else:
		marker = Node2D.new()
		marker.name = "GroundBag_%s" % bag_id
		marker.set_meta("bag_id", bag_id)
		marker.set_meta("cell", cell)
		layer.add_child(marker)
		# Small footprint: dim square + Sprite2D icon (letter fallback).
		var poly = Polygon2D.new()
		poly.name = "Mark"
		poly.polygon = PackedVector2Array([
			Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)
		])
		poly.color = Color(0.12, 0.10, 0.08, 0.72)
		marker.add_child(poly)
		var spr = Sprite2D.new()
		spr.name = "Icon"
		spr.centered = true
		spr.position = Vector2(0, 0)
		spr.visible = false
		marker.add_child(spr)
		var lab = Label.new()
		lab.name = "Letter"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 14)
		lab.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		lab.position = Vector2(-12, -10)
		lab.size = Vector2(24, 20)
		marker.add_child(lab)
		ctrl._ground_markers[bag_id] = marker
	marker.set_meta("bag_id", bag_id)
	marker.set_meta("cell", cell)
	if marker.get_node_or_null("Icon") == null:
		var spr_ensure = Sprite2D.new()
		spr_ensure.name = "Icon"
		spr_ensure.centered = true
		spr_ensure.visible = false
		marker.add_child(spr_ensure)
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		var wp: Vector2 = ctrl.map_field.cell_to_world(cell)
		# Sit near tile center / feet.
		marker.global_position = Vector2(wp.x, wp.y - float(ctrl.map_field.tile_size) * 0.35)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var letter = "物"
	var icon_tex: Texture2D = null
	if items.size() > 1:
		letter = "袋"
	else:
		var it0: Dictionary = items[0]
		var nm = str(it0.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = str(it0.get("item_id", "")).strip_edges()
		if not nm.is_empty():
			letter = nm.substr(0, 1)
		icon_tex = ctrl._resolve_ground_item_icon(it0)
	var spr2 = marker.get_node_or_null("Icon") as Sprite2D
	var lab2 = marker.get_node_or_null("Letter") as Label
	if icon_tex != null and spr2 != null:
		spr2.texture = icon_tex
		# Fit ~18px footprint over the square.
		var tw = float(icon_tex.get_width())
		var th = float(icon_tex.get_height())
		var sc = 18.0 / maxf(maxf(tw, th), 1.0)
		spr2.scale = Vector2(sc, sc)
		spr2.visible = true
		if lab2 != null:
			lab2.visible = false
			lab2.text = ""
	else:
		if spr2 != null:
			spr2.texture = null
			spr2.visible = false
		if lab2 != null:
			lab2.visible = true
			lab2.text = letter
	marker.set_meta("items", items.duplicate(true))
	marker.set_meta("tip_text", ctrl._ground_bag_tip_text(items))
	if ctrl._hovered_ground_bag_id == bag_id and ctrl.hud != null and ctrl.hud.has_method("show_ground_tip"):
		ctrl.hud.show_ground_tip(str(marker.get_meta("tip_text", "")), ctrl.get_viewport().get_mouse_position())

static func _resolve_ground_item_icon(ctrl, it: Dictionary) -> Texture2D:
	var iix = int(it.get("icon_index", -1))
	var iref = str(it.get("icon_ref", "")).strip_edges()
	if iref.is_empty():
		var ic = str(it.get("icon", "")).strip_edges()
		if not ic.is_empty():
			iref = ic if ic.begins_with("content:") else ("content://icon/%s" % ic)
	if iix < 0 or iref.is_empty():
		var iid = str(it.get("item_id", "")).strip_edges()
		if not iid.is_empty():
			var srv = Net.server()
			if srv != null and srv.get("item_catalog") != null:
				var cat = srv.item_catalog
				if iix < 0 and cat.has_method("icon_index_of"):
					iix = int(cat.icon_index_of(iid))
				elif iix < 0 and cat.has_method("get_item"):
					iix = int(cat.get_item(iid).get("icon_index", -1))
				if iref.is_empty() and cat.has_method("icon_ref_of"):
					iref = str(cat.icon_ref_of(iid)).strip_edges()
				elif iref.is_empty() and cat.has_method("get_item"):
					var def: Dictionary = cat.get_item(iid)
					iref = str(def.get("icon_ref", "")).strip_edges()
					if iref.is_empty():
						var ic2 = str(def.get("icon", "")).strip_edges()
						if not ic2.is_empty():
							iref = "content://icon/%s" % ic2
	var am: Node = ctrl._asset_mgr
	if am == null:
		return null
	if am.has_method("resolve_slot_icon_texture"):
		return am.resolve_slot_icon_texture(iix, iref)
	if iix >= 0 and am.has_method("load_mv_icon_texture"):
		return am.load_mv_icon_texture(iix)
	return null

static func _ground_bag_tip_text(ctrl, items: Array) -> String:
	## Inventory-like tip: name + id (+ qty); multi-item bags list stacks.
	var lines: PackedStringArray = PackedStringArray()
	if items.size() == 1 and typeof(items[0]) == TYPE_DICTIONARY:
		var it: Dictionary = items[0]
		var iid = str(it.get("item_id", "")).strip_edges()
		var nm = str(it.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = iid if not iid.is_empty() else "物品"
		var q: int = maxi(int(it.get("qty", 1)), 1)
		lines.append(nm)
		if not iid.is_empty():
			lines.append(iid)
		if q > 1:
			lines.append("×%d" % q)
		return "\n".join(lines)
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var iid2 = str(d.get("item_id", "")).strip_edges()
		var nm2 = str(d.get("name", "")).strip_edges()
		if nm2.is_empty():
			nm2 = iid2 if not iid2.is_empty() else "物品"
		var q2: int = maxi(int(d.get("qty", 1)), 1)
		if not iid2.is_empty():
			lines.append("%s\n%s ×%d" % [nm2, iid2, q2])
		else:
			lines.append("%s ×%d" % [nm2, q2])
	if lines.is_empty():
		return "地面物品"
	return "\n".join(lines)

static func _tick_ground_hover(ctrl) -> void:
	if ctrl.hud == null:
		return
	var mouse_world: Vector2 = ctrl.get_global_mouse_position()
	var best_id = ""
	var best_d = 22.0
	for bid in ctrl._ground_markers.keys():
		var n = ctrl._ground_markers[bid]
		if n == null or not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(mouse_world)
		if d < best_d:
			best_d = d
			best_id = str(bid)
	var screen_pos: Vector2 = ctrl.get_viewport().get_mouse_position()
	if best_id != ctrl._hovered_ground_bag_id:
		ctrl._hovered_ground_bag_id = best_id
		if best_id.is_empty():
			if ctrl.hud.has_method("hide_ground_tip"):
				ctrl.hud.hide_ground_tip()
		else:
			var tip = ""
			var mk = ctrl._ground_markers.get(best_id)
			if mk != null and is_instance_valid(mk):
				tip = str(mk.get_meta("tip_text", ""))
			if tip.is_empty():
				tip = "地面物品"
			if ctrl.hud.has_method("show_ground_tip"):
				ctrl.hud.show_ground_tip(tip, screen_pos)
	elif not best_id.is_empty():
		if ctrl.hud.has_method("move_ground_tip"):
			ctrl.hud.move_ground_tip(screen_pos)

static func _find_ground_bag_at(ctrl, cell: Vector2i) -> String:
	for bid in ctrl._ground_markers.keys():
		var n = ctrl._ground_markers[bid]
		if n == null or not is_instance_valid(n):
			continue
		var c_v: Variant = n.get_meta("cell", Vector2i(-9999, -9999))
		if typeof(c_v) == TYPE_VECTOR2I and (c_v as Vector2i) == cell:
			return str(bid)
		if typeof(c_v) == TYPE_DICTIONARY:
			if int(c_v.get("x", -9999)) == cell.x and int(c_v.get("y", -9999)) == cell.y:
				return str(bid)
	# Fallback: ask server authority.
	var srv = Net.server()
	if srv != null and srv.has_method("find_ground_bag_at"):
		return str(srv.find_ground_bag_at(cell.x, cell.y))
	return ""

