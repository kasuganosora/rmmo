extends RefCounted
## UI panel: spell cast bar and progress.

var ctrl
func _init(c):
	ctrl = c

func _ensure_cast_bar() -> void:
	## Deprecated: center cast bar removed — hide/free any leftover node.
	var existing = ctrl.get_node_or_null("CastBarRoot") as Control
	if existing != null and is_instance_valid(existing):
		existing.visible = false
		existing.queue_free()
	ctrl._cast_root = null
	ctrl._cast_bar = null
	ctrl._cast_label = null



func _style_cast_bar_mode(mode: String) -> void:
	if ctrl._cast_bar == null:
		return
	if mode == "channel":
		ctrl._style_status_bar(ctrl._cast_bar, Color(0.95, 0.55, 0.2, 1.0))
	else:
		ctrl._style_status_bar(ctrl._cast_bar, Color(0.55, 0.72, 1.0, 1.0))
	ctrl._cast_bar.custom_minimum_size = Vector2(0, 22)



func _tick_cast_bar_visual(delta: float) -> void:
	if not ctrl._cast_active:
		return
	if ctrl._cast_duration <= 0.0:
		return
	ctrl._cast_elapsed = minf(ctrl._cast_elapsed + maxf(delta, 0.0), ctrl._cast_duration)
	var frac: float = clampf(ctrl._cast_elapsed / ctrl._cast_duration, 0.0, 1.0)
	ctrl._sync_skill_cast_overlays()



func apply_cast_start(action: Dictionary) -> void:
	# Center cast bar removed — progress lives on skill-cell CdChrome only.
	ctrl._cast_active = true
	ctrl._cast_mode = str(action.get("mode", "cast"))
	ctrl._cast_duration = maxf(float(action.get("duration", 0.0)), 0.05)
	ctrl._cast_elapsed = float(action.get("elapsed", 0.0))
	ctrl._cast_skill_id = str(action.get("skill_id", "")).strip_edges()
	ctrl._cast_skill_name = str(action.get("name", action.get("skill_id", "技能")))
	if ctrl._cast_root != null and is_instance_valid(ctrl._cast_root):
		ctrl._cast_root.visible = false
	ctrl._sync_skill_cast_overlays()



func apply_cast_update(action: Dictionary) -> void:
	if not ctrl._cast_active:
		apply_cast_start(action)
		return
	ctrl._cast_elapsed = float(action.get("elapsed", ctrl._cast_elapsed))
	ctrl._cast_duration = maxf(float(action.get("duration", ctrl._cast_duration)), 0.05)
	var sid = str(action.get("skill_id", "")).strip_edges()
	if sid != "":
		ctrl._cast_skill_id = sid
	var nm = str(action.get("name", "")).strip_edges()
	if nm != "":
		ctrl._cast_skill_name = nm
	if ctrl._cast_root != null and is_instance_valid(ctrl._cast_root):
		ctrl._cast_root.visible = false
	ctrl._sync_skill_cast_overlays()



func apply_cast_end(action: Dictionary) -> void:
	ctrl._cast_active = false
	ctrl._cast_elapsed = 0.0
	ctrl._cast_duration = 0.0
	ctrl._cast_skill_id = ""
	if ctrl._cast_root != null and is_instance_valid(ctrl._cast_root):
		ctrl._cast_root.visible = false
	ctrl._sync_skill_cast_overlays()
	var _ok = bool(action.get("ok", false))
	var _cancelled = bool(action.get("cancelled", false))
	if _cancelled:
		pass



func _apply_cast_to_container(host: Node, frac: float) -> void:
	if host == null:
		return
	for cell in ctrl._iter_skill_cells(host):
		if not cell.has_method("set_cast_progress"):
			continue
		var bid = ctrl._cell_bound_id(cell)
		if frac >= 0.0 and bid == ctrl._cast_skill_id and not bid.is_empty():
			cell.set_cast_progress(frac)
		else:
			cell.set_cast_progress(-1.0)


