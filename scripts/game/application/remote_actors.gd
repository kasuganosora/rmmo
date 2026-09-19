extends RefCounted
## Application layer: remote players and pet markers (AOI, look, nameplates).

const Net = preload("res://scripts/net/net.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const NameplateUtil = preload("res://scripts/game/nameplate_util.gd")
const PaperdollLook = preload("res://scripts/char/paperdoll_look.gd")

static func _apply_remote_look(ctrl, marker: Node2D, gender: String, look_id: String, equipment: Variant) -> void:
	var anim = marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim == null:
		return
	var LookCatalog = load("res://scripts/char/look_catalog.gd")
	var MV = load("res://scripts/char/mv_generator.gd")
	gender = LookCatalog.normalize_gender(gender) if LookCatalog != null else gender
	var frames: SpriteFrames = null
	var eq: Array = equipment if typeof(equipment) == TYPE_ARRAY else []
	if MV != null and MV.has_method("compose_frames"):
		var parts: Dictionary = MV.default_parts(gender) if MV.has_method("default_parts") else {}
		if PaperdollLook != null and not eq.is_empty():
			var catalog = null
			var srv = Net.server()
			if srv != null:
				catalog = srv.get("item_catalog")
			var overlay: Dictionary = PaperdollLook.equipment_to_mv_parts(gender, eq, catalog)
			parts = MV.apply_equipment(parts, overlay)
			parts = MV.validate_parts(gender, parts)
		frames = MV.compose_frames(gender, parts, {})
	if frames == null and LookCatalog != null and LookCatalog.has_method("build_walk_frames"):
		frames = LookCatalog.build_walk_frames(look_id if look_id != "" else "1", gender)
	if frames == null:
		if marker.get_node_or_null("Body") == null:
			var body = Polygon2D.new()
			body.name = "Body"
			body.polygon = PackedVector2Array([
				Vector2(-8, -20), Vector2(8, -20), Vector2(10, 4), Vector2(-10, 4)
			])
			body.color = Color(0.35, 0.55, 0.95, 0.9)
			marker.add_child(body)
		return
	var legacy = marker.get_node_or_null("Body")
	if legacy != null:
		legacy.queue_free()
	anim.sprite_frames = frames
	anim.scale = Vector2(1.35, 1.35)
	if frames.has_animation("idle_front"):
		anim.play("idle_front")
	elif frames.has_animation("idle_Front"):
		anim.play("idle_Front")

static func _clear_remote_selection(ctrl) -> void:
	if ctrl._selected_remote_id.is_empty():
		return
	if ctrl._remote_markers.has(ctrl._selected_remote_id):
		var mk = ctrl._remote_markers[ctrl._selected_remote_id]
		if mk != null and is_instance_valid(mk):
			var body = mk.get_node_or_null("Body") as Polygon2D
			if body != null:
				body.color = Color(0.35, 0.55, 0.95, 0.9)
	ctrl._selected_remote_id = ""

static func _select_remote(ctrl, marker: Node2D) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	var pid = str(marker.get_meta("player_id", "")).strip_edges()
	if pid.is_empty():
		return
	ctrl._clear_npc_selection()
	if ctrl._selected_remote_id != pid:
		ctrl._clear_remote_selection()
		ctrl._selected_remote_id = pid
		var body = marker.get_node_or_null("Body") as Polygon2D
		if body != null:
			body.color = Color(0.55, 0.75, 1.0, 1.0)
	var display_name = str(marker.get_meta("display_name", pid)).strip_edges()
	if display_name.is_empty():
		display_name = pid
	if ctrl.hud != null and ctrl.hud.has_method("show_target"):
		ctrl.hud.show_target(display_name, 1.0, marker.global_position, false)
	ctrl._refresh_remote_nameplates()

static func _tick_remote_aoi(ctrl) -> void:
	## Show/hide fake players by Chebyshev ring (same radii as AssetManager AOI).
	if ctrl.player == null or ctrl._remote_markers.is_empty():
		return
	var pc: Vector2i = ctrl.player.cell if "cell" in ctrl.player else Vector2i.ZERO
	var view_r = ctrl.aoi_view_radius_cells
	var cold_r = ctrl.aoi_prefetch_radius_cells
	for rid in ctrl._remote_markers.keys():
		var mk = ctrl._remote_markers[rid]
		if mk == null or not is_instance_valid(mk):
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var cell = Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			cell = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		var dist: int = maxi(absi(pc.x - cell.x), absi(pc.y - cell.y))
		# COLD: hide; PREFETCH/AOI/VIEW: show (simple polygon needs no stream).
		var show = dist <= cold_r
		if mk.visible != show:
			mk.visible = show
			ctrl._radar_blips_ready = false
		# Dim beyond VIEW
		var body = mk.get_node_or_null("Body") as CanvasItem
		if body != null:
			body.modulate = Color(1, 1, 1, 1) if dist <= view_r else Color(1, 1, 1, 0.55)
		# Nameplate draw distance (selected always shows).
		var lab = mk.get_node_or_null("Name") as Label
		if lab != null:
			var show_p = GameSettingsScript.flag("show_player_names", true)
			var max_d = ctrl._nameplate_max_dist()
			var is_sel = str(rid) == ctrl._selected_remote_id
			lab.visible = show_p and NameplateUtil.should_show(dist, max_d, is_sel)

static func _ensure_remote_layer(ctrl) -> Node2D:
	var layer = ctrl.get_node_or_null("RemotePlayerLayer") as Node2D
	if layer != null and is_instance_valid(layer):
		return layer
	layer = Node2D.new()
	layer.name = "RemotePlayerLayer"
	layer.z_index = 6
	layer.z_as_relative = false
	ctrl.add_child(layer)
	return layer

static func _upsert_remote_marker(ctrl, data: Dictionary) -> void:
	var pid = str(data.get("id", "")).strip_edges()
	if pid.is_empty():
		return
	var cell_v: Variant = data.get("cell", {"x": 0, "y": 0})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var display_name = str(data.get("name", pid)).strip_edges()
	if display_name.is_empty():
		display_name = pid
	var layer = ctrl._ensure_remote_layer()
	var marker: Node2D = null
	if ctrl._remote_markers.has(pid) and is_instance_valid(ctrl._remote_markers[pid]):
		marker = ctrl._remote_markers[pid]
	else:
		marker = Node2D.new()
		marker.name = "Remote_%s" % pid
		layer.add_child(marker)
		var anim = AnimatedSprite2D.new()
		anim.name = "Anim"
		anim.centered = true
		anim.offset = Vector2(0, -32)
		anim.z_index = 5
		marker.add_child(anim)
		var lab = Label.new()
		lab.name = "Name"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 2)
		lab.position = Vector2(-48, -40)
		lab.size = Vector2(96, 18)
		marker.add_child(lab)
		ctrl._remote_markers[pid] = marker
	marker.set_meta("player_id", pid)
	marker.set_meta("cell", cell)
	marker.set_meta("display_name", display_name)
	var gender = str(data.get("gender", "female"))
	var look_id = str(data.get("look_id", "1"))
	marker.set_meta("gender", gender)
	marker.set_meta("look_id", look_id)
	marker.set_meta("level", int(data.get("level", 1)))
	ctrl._apply_remote_look(marker, gender, look_id, data.get("equipment", []))
	var lab2 = marker.get_node_or_null("Name") as Label
	if lab2 != null:
		lab2.text = display_name
		var show_p = GameSettingsScript.flag("show_player_names", true)
		var pc: Vector2i = ctrl.player.cell if ctrl.player != null and "cell" in ctrl.player else Vector2i.ZERO
		var dist = NameplateUtil.chebyshev(pc, cell)
		var is_sel = pid == ctrl._selected_remote_id
		lab2.visible = show_p and NameplateUtil.should_show(dist, ctrl._nameplate_max_dist(), is_sel)
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		var wp: Vector2 = ctrl.map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(ctrl.map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)

static func _clear_remote_markers(ctrl) -> void:
	for pid in ctrl._remote_markers.keys():
		var n = ctrl._remote_markers[pid]
		if n != null and is_instance_valid(n):
			n.queue_free()
	ctrl._remote_markers.clear()
	ctrl._selected_remote_id = ""
	ctrl._close_player_context_menu()

static func _remove_remote_marker(ctrl, player_id: String) -> void:
	player_id = player_id.strip_edges()
	if player_id.is_empty():
		return
	if ctrl.is_following() and ctrl.get_follow_id() == player_id:
		ctrl.stop_follow()
	if player_id == ctrl._selected_remote_id:
		ctrl._selected_remote_id = ""
	if ctrl._remote_markers.has(player_id):
		var n = ctrl._remote_markers[player_id]
		ctrl._remote_markers.erase(player_id)
		if n != null and is_instance_valid(n):
			n.queue_free()

static func _upsert_pet_marker(ctrl, data: Dictionary) -> void:
	if not bool(data.get("active", true)):
		ctrl._remove_pet_marker()
		return
	var cell_v: Variant = data.get("cell", {"x": int(data.get("x", 0)), "y": int(data.get("y", 0))})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var display_name = str(data.get("name", "宠物")).strip_edges()
	if display_name.is_empty():
		display_name = "宠物"
	var layer = ctrl._ensure_remote_layer()
	var marker: Node2D = ctrl._pet_marker
	if marker == null or not is_instance_valid(marker):
		marker = Node2D.new()
		marker.name = "PetCompanion"
		layer.add_child(marker)
		var anim = AnimatedSprite2D.new()
		anim.name = "Anim"
		anim.centered = true
		anim.offset = Vector2(0, -32)
		anim.z_index = 5
		marker.add_child(anim)
		var lab = Label.new()
		lab.name = "Name"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		# Gold nameplate to distinguish from remote players.
		lab.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 2)
		lab.position = Vector2(-48, -40)
		lab.size = Vector2(96, 18)
		marker.add_child(lab)
		ctrl._pet_marker = marker
	marker.set_meta("kind", "pet")
	marker.set_meta("pet_id", str(data.get("id", "default")))
	marker.set_meta("cell", cell)
	marker.set_meta("display_name", display_name)
	var look_id = str(data.get("look_id", "1"))
	marker.set_meta("look_id", look_id)
	# Reuse remote look pipeline with a fixed gender (no new art).
	if ctrl.has_method("_apply_remote_look"):
		ctrl._apply_remote_look(marker, "female", look_id, [])
	var lab2 = marker.get_node_or_null("Name") as Label
	if lab2 != null:
		lab2.text = display_name
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		var wp: Vector2 = ctrl.map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(ctrl.map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)

static func _remove_pet_marker(ctrl) -> void:
	if ctrl._pet_marker != null and is_instance_valid(ctrl._pet_marker):
		ctrl._pet_marker.queue_free()
	ctrl._pet_marker = null

static func inspect_remote(ctrl, player_id: String) -> Dictionary:
	player_id = player_id.strip_edges()
	var out = {"id": player_id, "name": player_id, "level": 1, "gender": "female", "equipment": []}
	if ctrl._remote_markers.has(player_id):
		var mk = ctrl._remote_markers[player_id]
		if mk != null and is_instance_valid(mk):
			out["name"] = str(mk.get_meta("display_name", player_id))
			out["level"] = int(mk.get_meta("level", 1))
			out["gender"] = str(mk.get_meta("gender", "female"))
	var srv = Net.server()
	if srv != null and srv.has_method("get_remote_player"):
		var rd: Dictionary = srv.get_remote_player(player_id)
		if not rd.is_empty():
			if str(rd.get("name", "")) != "":
				out["name"] = str(rd.get("name"))
			if rd.has("level"):
				out["level"] = int(rd.get("level", 1))
			if rd.has("gender"):
				out["gender"] = str(rd.get("gender"))
			if typeof(rd.get("equipment", null)) == TYPE_ARRAY:
				out["equipment"] = rd.get("equipment")
	return out

