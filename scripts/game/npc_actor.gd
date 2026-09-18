extends Node2D
## Map NPC spawned from pack npcs.json; charset loaded at runtime.
## Movement is server-authored only (apply_server_move from npc_move actions).
## Nameplates: kind monster|normal only; object/event never. Selection foot ring on click.

const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const NameplateUtil = preload("res://scripts/game/nameplate_util.gd")
const HurtFlash = preload("res://scripts/game/hurt_flash.gd")

signal interacted(npc: Node2D)

var npc_id: String = ""
var npc_name: String = ""
var cell: Vector2i = Vector2i.ZERO
var charset: String = ""
var char_index: int = 0
var direction: int = 2
var through: bool = false
## Display / pack flag only — idle roam is MockServer AI (wander_radius), not a client Timer.
var wander: bool = false
var hostile: bool = false
## Base 主动; false = 被动 (server may enrage after damage).
var aggressive: bool = false
## Optional combat display (MockServer is authoritative).
var hp: int = 0
var hp_max: int = 0
var mp: int = 0
var mp_max: int = 0
var level: int = 1
## null = default visibility; bool = explicit radar override
var radar_opt: Variant = null
## Display kind: monster | normal | object (object/event never get nameplates).
var kind: String = "object"
var interact_text: String = ""
## Soft service flags from pack (radar POI + dialogue).
var inn_rest: bool = false
var blacksmith: bool = false
## Client selection highlight (world click / engage).
var selected: bool = false

@export var step_duration: float = 0.32

var _anim: AnimatedSprite2D
var _map_field: Node2D = null
var _facing: String = "front"
var moving: bool = false
var _frame_size: Vector2i = Vector2i(48, 48)

var _plate: Node2D = null
var _title_lbl: Label = null
var _info_lbl: Label = null
var _hp_bg: ColorRect = null
var _hp_fg: ColorRect = null
var _mp_bg: ColorRect = null
var _mp_fg: ColorRect = null
var _select_ring: Line2D = null
var _hurt_flash = HurtFlash.new()


## Outgoing-hit feedback when this NPC takes damage. World calls only on real hits (not miss).
func flash_hurt() -> void:
	_ensure_anim()
	_hurt_flash.trigger(_anim)


func is_hurt_flashing() -> bool:
	return _hurt_flash.is_active()


func _process(delta: float) -> void:
	_hurt_flash.tick(delta)


func setup(data: Dictionary, map_field: Node2D, pack_dir: String = "") -> void:
	npc_id = str(data.get("id", ""))
	npc_name = str(data.get("name", npc_id))
	var cell_v: Variant = data.get("cell", {})
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	charset = str(data.get("charset", ""))
	char_index = int(data.get("index", 0))
	direction = int(data.get("direction", 2))
	through = bool(data.get("through", false))
	hostile = bool(data.get("hostile", false))
	aggressive = bool(data.get("aggressive", false))
	wander = bool(data.get("wander", false))
	level = maxi(int(data.get("level", 0)), 0)
	if data.has("radar"):
		radar_opt = bool(data.get("radar"))
	else:
		radar_opt = null
	interact_text = str(data.get("interact_text", ""))
	inn_rest = bool(data.get("inn_rest", false))
	blacksmith = bool(data.get("blacksmith", data.get("repair", false)))
	kind = _resolve_kind(data)
	_map_field = map_field
	_facing = CharsetSheet.facing_from_dir(direction)
	name = "Npc_%s" % (npc_id if npc_id != "" else str(get_instance_id()))
	z_index = 5
	z_as_relative = false
	y_sort_enabled = false
	_ensure_anim()
	_anim.sprite_frames = CharsetSheet.build_sprite_frames(charset, char_index, pack_dir)
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim.centered = true
	_frame_size = Vector2i(48, 48)
	var frames_ok := _sprite_frames_ready(_anim.sprite_frames)
	if not frames_ok:
		_on_charset_missing()
	if _anim.sprite_frames != null:
		var idle := "idle_%s" % _facing
		if _anim.sprite_frames.has_animation(idle) and _anim.sprite_frames.get_frame_count(idle) > 0:
			var tex: Texture2D = _anim.sprite_frames.get_frame_texture(idle, 0)
			if tex:
				_frame_size = Vector2i(tex.get_width(), tex.get_height())
	_anim.offset = Vector2(0, -float(_frame_size.y) * 0.5)
	_ensure_nameplate()
	_ensure_select_ring()
	_play_idle()
	_place()
	_refresh_nameplate()


func apply_graphic(p_charset: String, p_index: int, p_dir: int, pack_dir: String = "") -> void:
	charset = p_charset.strip_edges()
	char_index = p_index
	direction = p_dir if p_dir in [1, 2, 3, 4, 6, 7, 8, 9] else 2
	_facing = CharsetSheet.facing_from_dir(direction)
	_ensure_anim()
	if charset == "":
		_anim.visible = false
		return
	_anim.visible = true
	_anim.sprite_frames = CharsetSheet.build_sprite_frames(charset, char_index, pack_dir)
	if not _sprite_frames_ready(_anim.sprite_frames):
		_on_charset_missing()
	_play_idle()




func _sprite_frames_ready(frames: SpriteFrames) -> bool:
	if frames == null:
		return false
	var idle := "idle_%s" % _facing
	if not frames.has_animation(idle):
		return false
	return frames.get_frame_count(idle) > 0


func _asset_manager() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("AssetManager")
	return null


func _on_charset_missing() -> void:
	## Placeholder only — World AOI driver owns enqueue priority by ring (VIEW/AOI/PREFETCH).
	var am: Node = _asset_manager()
	if am != null and am.has_method("make_letter_sprite_frames"):
		_anim.sprite_frames = am.make_letter_sprite_frames(npc_name if npc_name != "" else charset, 48)
		return
	# Fallback without AssetManager
	var PlaceholderTex = load("res://scripts/asset/placeholder_tex.gd")
	if PlaceholderTex != null:
		_anim.sprite_frames = PlaceholderTex.make_letter_sprite_frames(npc_name if npc_name != "" else charset, 48)

## Sync HP / level from MockServer combat_stats blob (render-only).
func apply_combat_display(st: Dictionary) -> void:
	if st.is_empty():
		return
	if st.has("hp") and int(st.get("hp", -1)) >= 0:
		hp = int(st.get("hp", hp))
	if st.has("hp_max") and int(st.get("hp_max", -1)) >= 0:
		hp_max = int(st.get("hp_max", hp_max))
	if st.has("mp") and int(st.get("mp", -1)) >= 0:
		mp = int(st.get("mp", mp))
	if st.has("mp_max") and int(st.get("mp_max", -1)) >= 0:
		mp_max = int(st.get("mp_max", mp_max))
	if st.has("level"):
		level = maxi(int(st.get("level", level)), 1)
	elif level <= 0:
		level = 1
	if st.has("hostile"):
		hostile = bool(st.get("hostile", hostile))
	_refresh_nameplate()


func set_selected(on: bool) -> void:
	selected = on
	if _select_ring != null:
		_select_ring.visible = on
	_refresh_nameplate()
	queue_redraw()


func _resolve_kind(data: Dictionary) -> String:
	## Explicit map-pack taxonomy only:
	##   monster — 怪物（名牌+血条）
	##   normal  — 普通 NPC（名牌，任务对象）
	##   object  — 物件 / 事件（无名牌）
	## Aliases accepted: mob/enemy→monster; npc/character→normal; prop/event/item→object.
	## Fallback: hostile→monster, else object (never guess "humanoid" from charset).
	if hostile:
		return "monster"
	var k := str(data.get("kind", "")).strip_edges().to_lower()
	if k in ["monster", "mob", "enemy"]:
		return "monster"
	if k in ["normal", "npc", "character", "person", "human", "quest"]:
		return "normal"
	if k in ["object", "prop", "event", "item", "furniture"]:
		return "object"
	if data.has("nameplate"):
		# Legacy bool: true→normal, false→object
		return "normal" if bool(data.get("nameplate")) else "object"
	return "object"


func shows_nameplate() -> bool:
	if kind != "monster" and kind != "normal":
		return false
	if not GameSettingsScript.flag("show_npc_names", true):
		return false
	return true


func _nameplate_max_dist() -> int:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return 12
	return NameplateUtil.clamp_distance(int(gs.nameplate_distance))


func _local_player_cell() -> Vector2i:
	var n: Node = get_parent()
	while n != null:
		if "player" in n:
			var p = n.player
			if p != null and is_instance_valid(p) and "cell" in p:
				return p.cell
		n = n.get_parent()
	# Unknown player → treat as adjacent so plates still show.
	return cell


func _ensure_anim() -> void:
	_anim = get_node_or_null("Anim") as AnimatedSprite2D
	if _anim == null:
		_anim = AnimatedSprite2D.new()
		_anim.name = "Anim"
		add_child(_anim)


func _ensure_nameplate() -> void:
	_plate = get_node_or_null("Nameplate") as Node2D
	if _plate != null:
		_title_lbl = _plate.get_node_or_null("Title") as Label
		_info_lbl = _plate.get_node_or_null("Info") as Label
		_hp_bg = _plate.get_node_or_null("HpBg") as ColorRect
		_hp_fg = _plate.get_node_or_null("HpFg") as ColorRect
		_mp_bg = _plate.get_node_or_null("MpBg") as ColorRect
		_mp_fg = _plate.get_node_or_null("MpFg") as ColorRect
		if _mp_bg == null:
			_make_mp_bars()
		return
	_plate = Node2D.new()
	_plate.name = "Nameplate"
	_plate.z_index = 20
	_plate.z_as_relative = false
	add_child(_plate)

	_title_lbl = Label.new()
	_title_lbl.name = "Title"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 12)
	_title_lbl.add_theme_constant_override("outline_size", 4)
	_title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_lbl.size = Vector2(160, 16)
	_title_lbl.position = Vector2(-80, 0)
	_plate.add_child(_title_lbl)

	_info_lbl = Label.new()
	_info_lbl.name = "Info"
	_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_lbl.add_theme_font_size_override("font_size", 10)
	_info_lbl.add_theme_constant_override("outline_size", 3)
	_info_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_lbl.size = Vector2(160, 14)
	_info_lbl.position = Vector2(-80, 14)
	_plate.add_child(_info_lbl)

	_hp_bg = ColorRect.new()
	_hp_bg.name = "HpBg"
	_hp_bg.color = Color(0.1, 0.1, 0.12, 0.75)
	_hp_bg.size = Vector2(48, 4)
	_hp_bg.position = Vector2(-24, 30)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_hp_bg)

	_hp_fg = ColorRect.new()
	_hp_fg.name = "HpFg"
	_hp_fg.color = Color(0.85, 0.25, 0.22, 0.95)
	_hp_fg.size = Vector2(48, 4)
	_hp_fg.position = Vector2(-24, 30)
	_hp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_hp_fg)
	_make_mp_bars()


func _make_mp_bars() -> void:
	if _plate == null or _mp_bg != null:
		return
	_mp_bg = ColorRect.new()
	_mp_bg.name = "MpBg"
	_mp_bg.color = Color(0.08, 0.1, 0.16, 0.75)
	_mp_bg.size = Vector2(48, 3)
	_mp_bg.position = Vector2(-24, 35)
	_mp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_mp_bg)
	_mp_fg = ColorRect.new()
	_mp_fg.name = "MpFg"
	_mp_fg.color = Color(0.3, 0.5, 0.95, 0.95)
	_mp_fg.size = Vector2(48, 3)
	_mp_fg.position = Vector2(-24, 35)
	_mp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_mp_fg)


func _ensure_select_ring() -> void:
	_select_ring = get_node_or_null("SelectRing") as Line2D
	if _select_ring != null:
		return
	_select_ring = Line2D.new()
	_select_ring.name = "SelectRing"
	_select_ring.width = 2.0
	_select_ring.default_color = Color(1.0, 0.82, 0.2, 0.95)
	_select_ring.z_index = 4
	_select_ring.z_as_relative = false
	_select_ring.closed = true
	_select_ring.visible = false
	# Ellipse at feet (screen y+ down).
	var pts := PackedVector2Array()
	var rx := 16.0
	var ry := 8.0
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry - 2.0))
	_select_ring.points = pts
	add_child(_select_ring)


func _refresh_nameplate() -> void:
	if _plate == null:
		return
	# Plate sits above sprite top.
	var top_y: float = -float(_frame_size.y) - 6.0
	_plate.position = Vector2(0, top_y)

	# monster + normal show plates; object/event never (too dense).
	var show_plate := shows_nameplate()
	if show_plate:
		var max_d := _nameplate_max_dist()
		var dist := NameplateUtil.chebyshev(_local_player_cell(), cell)
		if not NameplateUtil.should_show(dist, max_d, selected):
			show_plate = false
	_plate.visible = show_plate
	if not show_plate:
		return

	var title := npc_name if not npc_name.is_empty() else npc_id
	_title_lbl.text = title
	if kind == "monster" or hostile:
		_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45, 1.0) if selected else Color(1.0, 0.72, 0.55, 1.0))
	else:
		# Friendly / quest humanoid.
		_title_lbl.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0) if selected else Color(0.85, 0.92, 1.0, 1.0))

	# No chrome tags (NPC / 主动 / 被动) — keep plate lean: title + HP bar only.
	var info := ""
	if (kind == "monster" or hostile) and hp_max > 0:
		info = "HP %d/%d" % [clampi(hp, 0, hp_max), maxi(hp_max, 1)]
	_info_lbl.text = info
	_info_lbl.visible = not info.is_empty()
	_info_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))

	var show_hp := (kind == "monster" or hostile) and hp_max > 0
	if not GameSettingsScript.flag("show_hp_bars", true):
		show_hp = false
	_hp_bg.visible = show_hp
	_hp_fg.visible = show_hp
	# Tuck HP bar up when no info line (normal NPCs: title only).
	if show_hp:
		_hp_bg.position = Vector2(-24, 16.0 if info.is_empty() else 30.0)
		_hp_fg.position = _hp_bg.position
	if show_hp:
		var ratio := clampf(float(hp) / float(maxi(hp_max, 1)), 0.0, 1.0)
		_hp_fg.size = Vector2(48.0 * ratio, 4.0)
		if ratio > 0.5:
			_hp_fg.color = Color(0.35, 0.85, 0.35, 0.95)
		elif ratio > 0.25:
			_hp_fg.color = Color(0.95, 0.75, 0.25, 0.95)
		else:
			_hp_fg.color = Color(0.9, 0.25, 0.22, 0.95)
	var show_mp := show_hp and mp_max > 0
	if _mp_bg == null:
		_make_mp_bars()
	if _mp_bg != null:
		_mp_bg.visible = show_mp
		_mp_fg.visible = show_mp
	if show_mp and _mp_fg != null:
		var mp_y: float = _hp_bg.position.y + 5.0
		_mp_bg.position = Vector2(-24, mp_y)
		_mp_fg.position = Vector2(-24, mp_y)
		var mr := clampf(float(mp) / float(maxi(mp_max, 1)), 0.0, 1.0)
		_mp_fg.size = Vector2(48.0 * mr, 3.0)

	if _select_ring != null:
		_select_ring.default_color = Color(1.0, 0.35, 0.25, 0.95) if hostile else Color(1.0, 0.82, 0.2, 0.95)


func _place() -> void:
	if _map_field != null and _map_field.has_method("cell_to_world"):
		global_position = _map_field.cell_to_world(cell)
	else:
		global_position = Vector2(float(cell.x) * 48.0 + 24.0, float(cell.y) * 48.0 + 48.0)


func face_dir(d: int) -> void:
	direction = d
	_facing = CharsetSheet.facing_from_dir(d)
	_play_idle()


func face_toward_cell(other: Vector2i) -> void:
	var dx: int = other.x - cell.x
	var dy: int = other.y - cell.y
	if absi(dx) > absi(dy):
		face_dir(6 if dx > 0 else 4)
	elif dy != 0:
		face_dir(2 if dy > 0 else 8)


func _play_idle() -> void:
	if _anim == null or _anim.sprite_frames == null:
		return
	var idle := "idle_%s" % _facing
	if _anim.sprite_frames.has_animation(idle):
		_anim.play(idle)


func _play_walk() -> void:
	if _anim == null or _anim.sprite_frames == null:
		return
	var walk := "walk_%s" % _facing
	if _anim.sprite_frames.has_animation(walk):
		# Fit one 0-1-2-1 cycle into step_duration so the step is visibly animated.
		var fc: int = maxi(_anim.sprite_frames.get_frame_count(walk), 1)
		_anim.sprite_frames.set_animation_speed(walk, float(fc) / maxf(step_duration, 0.05))
		_anim.stop()
		_anim.play(walk)
	else:
		_play_idle()


## Apply authoritative npc_move from MockServer (does not call try_npc_move).
func apply_server_move(nx: int, ny: int, facing: int = -1) -> void:
	if facing in [1, 2, 3, 4, 6, 7, 8, 9]:
		direction = facing
		_facing = CharsetSheet.facing_from_dir(facing)
	var next := Vector2i(nx, ny)
	if next == cell:
		_play_idle()
		return
	if moving:
		# Snap if a new server step arrives mid-tween.
		_place()
		moving = false
	cell = next
	var target: Vector2 = global_position
	if _map_field != null and _map_field.has_method("cell_to_world"):
		target = _map_field.cell_to_world(cell)
	else:
		var ts: float = 48.0
		target = Vector2(float(nx) * ts + ts * 0.5, float(ny) * ts + ts * 0.5)
	moving = true
	_play_walk()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(self, "global_position", target, step_duration)
	tw.finished.connect(_on_server_step_finished, CONNECT_ONE_SHOT)


func _on_server_step_finished() -> void:
	moving = false
	_play_idle()


## Local cosmetic only (face player). Dialogue authority is server show_npc_dialogue.
func try_interact(player_cell: Vector2i) -> String:
	face_toward_cell(player_cell)
	interacted.emit(self)
	return ""


func is_adjacent_to(other: Vector2i) -> bool:
	return maxi(absi(other.x - cell.x), absi(other.y - cell.y)) == 1


func contains_cell(c: Vector2i) -> bool:
	return c == cell
