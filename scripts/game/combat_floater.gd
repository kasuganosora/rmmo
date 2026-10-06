extends RefCounted
## Thin world-space combat floating numbers (Label only). Damage / heal / miss / crit.
## Cap concurrent floaters per target_key so spam does not freeze the client.

const MAX_PER_TARGET := 8
const DURATION_SEC := 1.0
const RISE_PX := 40.0
## Base offset of the first floater above the target, then fan-out for concurrent ones.
const BASE_OFFSET := Vector2(-12, -48)
const FAN_STEP_X := 16.0  ## horizontal spread per tier
const FAN_STEP_Y := 9.0   ## vertical stagger per concurrent floater

const COLOR_DAMAGE := Color(1.0, 0.38, 0.32, 1.0)
const COLOR_DAMAGE_OUT := Color(1.0, 0.95, 0.92, 1.0)  ## outgoing / NPC hit — pale white-red
const COLOR_HEAL := Color(0.45, 0.95, 0.55, 1.0)
const COLOR_MISS := Color(0.72, 0.72, 0.76, 1.0)
const COLOR_CRIT := Color(1.0, 0.98, 0.88, 1.0)

## target_key -> Array of Label (live floaters)
static var _by_target: Dictionary = {}


static func color_for(kind: String, crit: bool = false) -> Color:
	kind = kind.strip_edges().to_lower()
	if crit and kind != "miss" and kind != "heal":
		return COLOR_CRIT
	match kind:
		"heal":
			return COLOR_HEAL
		"miss":
			return COLOR_MISS
		"damage_out", "outgoing":
			return COLOR_DAMAGE_OUT
		_:
			return COLOR_DAMAGE


## Spread concurrent floaters on the same target so they don't stack on one spot.
## index 0 = centered; higher indices fan out horizontally (alternating) and stagger up.
static func fan_offset(index: int) -> Vector2:
	index = maxi(index, 0)
	var side := 1 if (index % 2 == 0) else -1
	var tier := (index + 1) / 2  # 0,1,1,2,2,3,3,...
	return BASE_OFFSET + Vector2(side * tier * FAN_STEP_X, -index * FAN_STEP_Y)


static func text_for(kind: String, amount: int = 0, crit: bool = false) -> String:
	kind = kind.strip_edges().to_lower()
	if kind == "miss":
		return "未命中"
	if kind == "heal":
		return "+%d" % maxi(amount, 0)
	var body := str(maxi(amount, 0))
	if crit:
		return "%s!" % body
	return body


static func spawn(
	parent: Node,
	world_pos: Vector2,
	text: String,
	kind: String = "damage",
	target_key: String = "default",
	crit: bool = false
) -> Label:
	## Spawn a rising Label under parent. Returns the Label (or null if skipped).
	if parent == null or not is_instance_valid(parent):
		return null
	text = text.strip_edges()
	if text.is_empty():
		return null
	var key := str(target_key).strip_edges()
	if key.is_empty():
		key = "default"
	_prune(key)
	var bucket: Array = _by_target.get(key, [])
	while bucket.size() >= MAX_PER_TARGET:
		var old = bucket.pop_front()
		_free_floater(old)
	# Fan-out index = how many live floaters this target already has.
	var fan_index := bucket.size()
	var col := color_for(kind, crit)
	var lab := Label.new()
	lab.text = text
	lab.z_index = 80
	lab.z_as_relative = false
	lab.modulate = col
	lab.add_theme_font_size_override("font_size", 16 if not crit else 18)
	lab.add_theme_color_override("font_color", col)
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.position = world_pos + fan_offset(fan_index)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.set_meta("combat_floater_key", key)
	parent.add_child(lab)
	bucket.append(lab)
	_by_target[key] = bucket
	var tw: Tween = parent.create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "position", lab.position + Vector2(0, -RISE_PX), DURATION_SEC)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, DURATION_SEC)
	lab.set_meta("combat_floater_tween", tw)
	tw.finished.connect(_on_floater_finished.bind(key, lab))
	return lab


static func _on_floater_finished(key: String, lab: Label) -> void:
	_forget(key, lab)
	if lab != null and is_instance_valid(lab):
		lab.queue_free()


static func _free_floater(lab) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	if lab.has_meta("combat_floater_tween"):
		var tw = lab.get_meta("combat_floater_tween")
		if tw is Tween and is_instance_valid(tw):
			tw.kill()
	lab.queue_free()


static func active_count(target_key: String = "") -> int:
	_prune_all()
	if target_key.strip_edges() != "":
		var b: Array = _by_target.get(target_key, [])
		return b.size()
	var n := 0
	for k in _by_target.keys():
		n += (_by_target[k] as Array).size()
	return n


static func clear_all() -> void:
	for k in _by_target.keys():
		var bucket: Array = _by_target[k]
		for lab in bucket:
			_free_floater(lab)
	_by_target.clear()


static func _forget(key: String, lab: Label) -> void:
	if not _by_target.has(key):
		return
	var bucket: Array = _by_target[key]
	bucket.erase(lab)
	if bucket.is_empty():
		_by_target.erase(key)
	else:
		_by_target[key] = bucket


static func _prune(key: String) -> void:
	if not _by_target.has(key):
		return
	var bucket: Array = _by_target[key]
	var kept: Array = []
	for lab in bucket:
		if lab != null and is_instance_valid(lab):
			kept.append(lab)
	if kept.is_empty():
		_by_target.erase(key)
	else:
		_by_target[key] = kept


static func _prune_all() -> void:
	for k in _by_target.keys().duplicate():
		_prune(str(k))
