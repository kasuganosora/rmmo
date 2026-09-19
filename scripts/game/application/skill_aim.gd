extends RefCounted
## Application layer: skill aiming (begin/cancel/preview, aim overlay, fx node).

const Net = preload("res://scripts/net/net.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const SkillFxScript = preload("res://scripts/game/skill_fx.gd")
const SkillAimOverlay = preload("res://scripts/game/skill_aim_overlay.gd")

static func is_skill_aiming(ctrl) -> bool:
	return not ctrl._skill_aim_id.is_empty()

static func begin_skill_aim(ctrl, skill_id: String) -> void:
	ctrl._skill_aim_id = skill_id.strip_edges()
	ctrl._ensure_skill_aim()
	ctrl._skill_aim_hover = Vector2i(-9999, -9999)
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("选择释放地点（右键取消）")
	ctrl._update_skill_aim_preview()

static func cancel_skill_aim(ctrl) -> void:
	ctrl._skill_aim_id = ""
	if ctrl._skill_aim_overlay != null and ctrl._skill_aim_overlay.has_method("clear_preview"):
		ctrl._skill_aim_overlay.clear_preview()

static func _ensure_skill_aim(ctrl) -> void:
	if ctrl._skill_aim_overlay != null and is_instance_valid(ctrl._skill_aim_overlay):
		return
	ctrl._skill_aim_overlay = Node2D.new()
	ctrl._skill_aim_overlay.set_script(SkillAimOverlay)
	ctrl.add_child(ctrl._skill_aim_overlay)
	if ctrl._skill_aim_overlay.has_method("setup"):
		ctrl._skill_aim_overlay.setup(ctrl.map_field)

static func _ensure_skill_fx(ctrl) -> void:
	if ctrl._skill_fx != null and is_instance_valid(ctrl._skill_fx):
		return
	ctrl._skill_fx = Node2D.new()
	ctrl._skill_fx.set_script(SkillFxScript)
	ctrl.add_child(ctrl._skill_fx)

static func _skill_aim_def(ctrl) -> Dictionary:
	var srv = Net.server()
	if srv == null or not srv.has_method("skill_def") or ctrl._skill_aim_id.is_empty():
		return {}
	return srv.skill_def(ctrl._skill_aim_id)

static func _update_skill_aim_preview(ctrl) -> void:
	if ctrl._skill_aim_id.is_empty() or ctrl.player == null or ctrl.map_field == null:
		return
	ctrl._ensure_skill_aim()
	var hover: Vector2i = ctrl.map_field.world_to_cell(ctrl.get_global_mouse_position())
	ctrl._skill_aim_hover = hover
	var def: Dictionary = ctrl._skill_aim_def()
	var radius: int = int(def.get("aoe_radius", 0))
	var shape = str(def.get("aoe_shape", "circle"))
	var rng: int = int(def.get("range", 1))
	var facing: int = 2
	if ctrl.player.has_method("get_facing"):
		facing = CharsetSheet.dir_from_facing(str(ctrl.player.get_facing()))
	var engine = null
	var srv = Net.server()
	if srv != null:
		engine = srv.get("combat_engine")
	var cells: Array[Vector2i] = []
	if engine != null and engine.has_method("aoe_cells"):
		for c_v in engine.aoe_cells(hover, radius, shape, facing):
			if typeof(c_v) == TYPE_VECTOR2I:
				cells.append(c_v)
	else:
		for y in range(hover.y - radius, hover.y + radius + 1):
			for x in range(hover.x - radius, hover.x + radius + 1):
				if maxi(absi(x - hover.x), absi(y - hover.y)) <= radius:
					cells.append(Vector2i(x, y))
	var in_range = maxi(absi(hover.x - ctrl.player.cell.x), absi(hover.y - ctrl.player.cell.y)) <= rng
	if rng <= 0:
		in_range = true
	ctrl._skill_aim_overlay.set_preview(hover, cells, in_range)

