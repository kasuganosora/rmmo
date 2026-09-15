extends Control
## Lineage 2–inspired HUD: shell + toggle windows (inventory / status / skills / quest / system).

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Mock = preload("res://scripts/ui/l2_mock.gd")
const RadarView = preload("res://scripts/ui/radar_view.gd")
const MapOverview = preload("res://scripts/ui/map_overview.gd")
const InvSlot = preload("res://scripts/ui/inv_slot.gd")
const EquipSlot = preload("res://scripts/ui/equip_slot.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const HotbarSlot = preload("res://scripts/ui/hotbar_slot.gd")
const SkillSlot = preload("res://scripts/ui/skill_slot.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")

@onready var name_label: Label = %NameLabel
@onready var level_label: Label = %LevelLabel
@onready var cp_bar: ProgressBar = %CpBar
@onready var hp_bar: ProgressBar = %HpBar
@onready var mp_bar: ProgressBar = %MpBar
@onready var cp_text: Label = %CpText
@onready var hp_text: Label = %HpText
@onready var mp_text: Label = %MpText
@onready var target_panel: Control = %TargetPanel
@onready var target_name: Label = %TargetName
@onready var target_hp: ProgressBar = %TargetHp
@onready var minimap_label: Label = %MinimapLabel
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var hotbar: HBoxContainer = %Hotbar
@onready var menu_row: HBoxContainer = %MenuRow
@onready var chat_tabs: HBoxContainer = %ChatTabs
@onready var hotbar_page_label: Label = %HotbarPageLabel
@onready var minimap_view_host: Control = %MinimapView

var _hp_max: float = 100.0
var _mp_max: float = 80.0
var _cp_max: float = 100.0
var _hp: float = 100.0
var _mp: float = 80.0
var _cp: float = 100.0
var _character: Dictionary = {}
var _chat_channel: String = "all"
## [{channel, speaker, msg, color}]
var _chat_history: Array = []
const CHAT_HISTORY_MAX := 200
var _hotbar_page: int = 0
var _windows: Dictionary = {}
var _radar: Control
var _radar_player: Node2D
var _radar_map_field: Node2D
var _radar_map_id: String = ""
## Node with get_radar_blips() or Callable -> Array
var _radar_blip_source: Variant = null
var _target_world_pos: Variant = null
var _radar_hint_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _radar_blips_msec: int = 0
const RADAR_BLIPS_INTERVAL_MS: int = 100
## A/B hitch test: set true to re-enable radar/minimap.
const RADAR_ENABLED := true
var _map_overview: Control = null
var _map_info_label: Label = null
var _party_panel: PanelContainer
var _party_body: VBoxContainer = null
## Last party snapshot {party_id, leader, members:[{id,name,hp,hp_max,online}]}
var _party_state: Dictionary = {"party_id": "", "leader": "", "members": []}
var _trade_panel: PanelContainer = null
var _trade_body: VBoxContainer = null
var _trade_state: Dictionary = {"active": false}
var _trade_gold_spin: SpinBox = null
var _player_ctx_menu: PopupMenu = null
var _player_ctx_target_id: String = ""
var _player_ctx_target_name: String = ""
## L2-style NPC Chat dialogue (separate from toggle windows).
var _npc_chat: PanelContainer = null
var _npc_chat_name: Label = null
var _npc_chat_body: RichTextLabel = null
var _npc_chat_options: VBoxContainer = null
var _npc_chat_face: TextureRect = null
## World node for combat hotbar intents (request_use_skill / request_use_item).
var _world_combat: Node = null
## Last server inventory snapshot [{id, qty}, ...].
var _server_inventory: Array = []
## Wallet gold from MockServer (not a bag stack).
var _server_gold: int = 0
## Last server equipment snapshot [{slot, item_id, name}, ...].
var _server_equipment: Array = []
## Flat equipment bonuses from server ({p_atk, p_def, ...}).
var _server_equip_bonuses: Dictionary = {}
## Skill defs from MockServer skill_catalog (text labels).
var _server_skills: Array = []
## skill_id -> remaining cooldown hint (display only).
var _skill_cd_hint: Dictionary = {}
## Hotbar bindings mirrored to Net.session().hotbar_bindings so map transfer keeps them.
var _hotbar_bindings: Dictionary = {}
## Grid cells match hotbar slot size (42×42); column count fills fixed window width.
## Server soft cap is Inventory.MAX_SLOTS (40); cells beyond capacity render disabled gray.
const GRID_CELL := 42
const GRID_SEP := 4
const INV_ROWS := 10
## Skills UI: fixed columns (not fill-empty like bag); only real skills as cells.
const SKILL_COLS := 5
const SKILL_ROWS := 8  # unused for empty padding; kept for layout reference
const SKILL_TABS := [
	["物理", "physical"],
	["魔法", "magic"],
	["被动", "passive"],
]
## Active skills window tab: physical | magic | passive
var _skills_tab: String = "physical"
## Optional stub toggles for passive skills (UI only).
var _passive_toggles: Dictionary = {}
## Last server quest journal snapshot [{id,title,status,desc,objectives,rewards}, ...].
var _server_quests: Array = []
## Selected quest id; empty = side drawer collapsed.
var _selected_quest_id: String = ""
var _abandon_confirm_id: String = ""
## Quest list tab: active (正在进行) | completed (已完成)
var _quest_tab: String = "active"
## Side drawer panel (sibling of quest window, not internal split).
var _quest_drawer: PanelContainer = null
var _quest_drawer_body: VBoxContainer = null
var _quest_drawer_tween: Tween = null
## Authoritative combat blob cache from server (level/exp/hp/atk...).
var _server_combat: Dictionary = {}
## Active shop window state.
var _shop_panel: PanelContainer = null
var _shop_id: String = ""
var _shop_title: String = ""
var _shop_listings: Array = []
## Buy/sell selection carts: [{item_id, qty, unit_price, name}, ...]
var _shop_buy_cart: Array = []
var _shop_sell_cart: Array = []
## Compact loot confirm window (掉落确认).
var _loot_panel: PanelContainer = null
var _loot_session_id: String = ""
var _loot_npc_id: String = ""
var _loot_items: Array = []
var _ground_drop_zone: Control = null
var _ground_drop_armed: bool = false
var _ground_tip: PanelContainer = null
var _ground_tip_label: Label = null
var _drop_qty_panel: PanelContainer = null
var _drop_qty_spin: SpinBox = null
var _drop_qty_item_id: String = ""
var _drop_qty_label: Label = null
## Thin XP bar under MP in status panel (created in code).
var _xp_bar: ProgressBar = null
## Player status chips (buff/DoT text labels; no textures).
var _status_chip_row: HBoxContainer = null
var _player_statuses: Array = []
## Optional chips under target panel.
var _target_status_chip_row: HBoxContainer = null
## Center-bottom cast / channel bar (code-built ProgressBar + Label).
var _cast_root: Control = null
var _cast_bar: ProgressBar = null
var _cast_label: Label = null
var _cast_active: bool = false
var _cast_mode: String = "cast"
var _cast_duration: float = 0.0
var _cast_elapsed: float = 0.0
var _cast_skill_name: String = ""
var _cast_skill_id: String = ""
const QUEST_DRAWER_WIDTH := 320.0
const QUEST_TABS := [
	["正在进行", "active"],
	["已完成", "completed"],
]

## Page 0 = F1–F12; page 1 = ` 1–0 - = (top number row). Max 2 pages.
const HOTBAR_PAGES := [
	["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
	["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+"],
]

const CHAT_CHANNELS := [
	["全部", "all"],
	["附近", "nearby"],
	["私聊", "whisper"],
	["队伍", "party"],
	["血盟", "clan"],
	["交易", "trade"],
	["同盟", "alliance"],
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_ground_drop_zone()
	_ensure_ground_tip()
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.placeholder_text = "输入 · ~附近 !喊话 /w名 私聊 #队伍 @血盟 +交易"
	_setup_radar()
	_build_chat_tabs()
	var prev := get_node_or_null("%HotbarPrev")
	var next := get_node_or_null("%HotbarNext")
	# HotbarPrev/Next may lack unique names; resolve by path
	if prev == null:
		prev = find_child("HotbarPrev", true, false)
	if next == null:
		next = find_child("HotbarNext", true, false)
	if prev:
		prev.pressed.connect(hotbar_prev)
	if next:
		next.pressed.connect(hotbar_next)
	_layout_hotbar_side_nav(prev, next)
	_hotbar_page = clampi(_hotbar_page, 0, HOTBAR_PAGES.size() - 1)
	_restore_hotbar_from_session()
	_build_hotbar()
	_build_menu()
	_build_windows()
	_build_party_stub()
	_build_trade_panel()
	_build_player_context_menu()
	_ensure_target_chrome()
	_compact_status_panel()
	clear_target()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if _try_hotbar_key(k.keycode):
		get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_C:
			_toggle_window("character")
			get_viewport().set_input_as_handled()
		KEY_I, KEY_TAB:
			_toggle_window("inventory")
			get_viewport().set_input_as_handled()
		KEY_K:
			_toggle_window("skills")
			get_viewport().set_input_as_handled()
		KEY_L, KEY_U:
			_toggle_window("quest")
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_window("map")
			get_viewport().set_input_as_handled()
		KEY_X:
			_toggle_window("system")
			get_viewport().set_input_as_handled()
		KEY_P:
			_toggle_party_panel()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _close_top_window():
				get_viewport().set_input_as_handled()

func bind_character(ch: Dictionary) -> void:
	_character = ch.duplicate(true)
	if ch.is_empty():
		name_label.text = "???"
		level_label.text = "Lv.?"
		return
	var lv := int(ch.get("level", 1))
	var cname := str(ch.get("name", "")).strip_edges()
	if cname.is_empty():
		cname = "???"
	name_label.text = cname
	level_label.text = "Lv.%d" % lv
	_hp_max = 80.0 + lv * 20.0
	_mp_max = 40.0 + lv * 15.0
	_cp_max = _hp_max
	_hp = _hp_max
	_mp = _mp_max
	_cp = _cp_max
	_refresh_bars()
	_refresh_window_contents()
	if not bool(get_meta("_chat_seeded", false)):
		set_meta("_chat_seeded", true)
		_push_chat("party", "队伍", "这里是队伍频道（示例）")
		_push_chat("clan", "血盟", "这里是血盟频道（示例）")
		_push_chat("trade", "交易", "这里是交易频道（示例）")
		_push_chat("alliance", "同盟", "这里是同盟频道（示例）")

func _compact_status_panel() -> void:
	## Lean top-left status: value text overlaid on bars (white, high contrast).
	var panel := get_node_or_null("%StatusPanel") as PanelContainer
	if panel != null:
		panel.min_size = Vector2(160, 72)
		panel.default_size = Vector2(200, 88)
		panel.custom_minimum_size = Vector2(160, 72)
		panel.size = Vector2(200, 88)
	if name_label != null:
		name_label.add_theme_font_size_override("font_size", 12)
	if level_label != null:
		level_label.add_theme_font_size_override("font_size", 11)
	for lab in [cp_text, hp_text, mp_text]:
		if lab != null:
			lab.visible = false
	# Color the fill via StyleBox (not modulate) so overlay Labels stay white.
	_style_status_bar(cp_bar, Color(0.92, 0.78, 0.22, 1.0))
	_style_status_bar(hp_bar, Color(0.82, 0.22, 0.22, 1.0))
	_style_status_bar(mp_bar, Color(0.28, 0.42, 0.9, 1.0))
	_ensure_status_overlays()
	_ensure_xp_bar()
	_ensure_status_chip_row()
	_ensure_cast_bar()


func _style_status_bar(bar: ProgressBar, fill: Color) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(0, 12)
	bar.modulate = Color(1, 1, 1, 1)  # never tint children
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_corner_radius_all(3)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _ensure_status_overlays() -> void:
	_ensure_bar_overlay(cp_bar, "CpOverlay")
	_ensure_bar_overlay(hp_bar, "HpOverlay")
	_ensure_bar_overlay(mp_bar, "MpOverlay")


func _ensure_bar_overlay(bar: ProgressBar, oname: String) -> void:
	if bar == null:
		return
	var lab := bar.get_node_or_null(oname) as Label
	if lab == null:
		lab = Label.new()
		lab.name = oname
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.add_child(lab)
	# Always re-assert white + outline (survives bar theme changes).
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab.modulate = Color(1, 1, 1, 1)


func _ensure_xp_bar() -> void:
	## Thin EXP track under MP; created in code so tscn stays optional.
	if mp_bar == null:
		return
	var vbox := mp_bar.get_parent() as VBoxContainer
	if vbox == null:
		return
	if _xp_bar != null and is_instance_valid(_xp_bar):
		return
	var existing := vbox.get_node_or_null("XpBar") as ProgressBar
	if existing != null:
		_xp_bar = existing
	else:
		_xp_bar = ProgressBar.new()
		_xp_bar.name = "XpBar"
		_xp_bar.show_percentage = false
		_xp_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(_xp_bar)
		vbox.move_child(_xp_bar, mp_bar.get_index() + 1)
	_xp_bar.custom_minimum_size = Vector2(0, 5)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_status_bar(_xp_bar, Color(0.35, 0.78, 0.92, 1.0))
	_xp_bar.custom_minimum_size = Vector2(0, 5)


func _ensure_status_chip_row() -> void:
	var panel := get_node_or_null("%StatusPanel") as PanelContainer
	if panel == null:
		return
	if _status_chip_row != null and is_instance_valid(_status_chip_row):
		return
	var existing := panel.get_node_or_null("StatusChipRow") as HBoxContainer
	if existing != null:
		_status_chip_row = existing
		return
	var parent_ctl := panel.get_parent() as Control
	_status_chip_row = HBoxContainer.new()
	_status_chip_row.name = "StatusChipRow"
	_status_chip_row.add_theme_constant_override("separation", 4)
	_status_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_chip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent_ctl != null:
		parent_ctl.add_child(_status_chip_row)
		parent_ctl.move_child(_status_chip_row, panel.get_index() + 1)
	else:
		panel.add_child(_status_chip_row)
	_rebuild_status_chips(_status_chip_row, _player_statuses)


func _status_kind_color(kind: String) -> Color:
	match kind.strip_edges().to_lower():
		"buff":
			return Color(0.35, 0.85, 0.45, 1.0)
		"debuff":
			return Color(0.75, 0.4, 0.9, 1.0)
		"dot":
			return Color(0.95, 0.35, 0.3, 1.0)
		"hot":
			return Color(0.35, 0.8, 0.95, 1.0)
		_:
			return Color(0.75, 0.75, 0.8, 1.0)


func _rebuild_status_chips(row: HBoxContainer, statuses: Array) -> void:
	if row == null:
		return
	for c in row.get_children():
		c.queue_free()
	for s in statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		var n := str(d.get("name", d.get("id", "?"))).strip_edges()
		var rem: float = float(d.get("remaining_sec", 0.0))
		var txt := "%s %.0fs" % [n, rem] if rem >= 1.0 else "%s %.1fs" % [n, rem]
		var col := _status_kind_color(str(d.get("kind", "")))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.92)
		sb.set_border_width_all(1)
		sb.border_color = col
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", sb)
		var inner := Label.new()
		inner.text = txt
		inner.add_theme_font_size_override("font_size", 10)
		inner.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(inner)
		row.add_child(chip)


func apply_status_chips(statuses: Array) -> void:
	_player_statuses = statuses.duplicate(true)
	_ensure_status_chip_row()
	_rebuild_status_chips(_status_chip_row, _player_statuses)


func apply_target_status_chips(statuses: Array) -> void:
	if target_panel == null:
		return
	_ensure_target_chrome()
	if _target_status_chip_row == null or not is_instance_valid(_target_status_chip_row):
		var vbox := target_panel.find_child("TargetVBox", true, false) as VBoxContainer
		if vbox == null:
			return
		_target_status_chip_row = vbox.get_node_or_null("TargetStatusChips") as HBoxContainer
		if _target_status_chip_row == null:
			_target_status_chip_row = HBoxContainer.new()
			_target_status_chip_row.name = "TargetStatusChips"
			_target_status_chip_row.add_theme_constant_override("separation", 3)
			_target_status_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(_target_status_chip_row)
	_rebuild_status_chips(_target_status_chip_row, statuses)


func _ensure_cast_bar() -> void:
	## Deprecated: center cast bar removed — hide/free any leftover node.
	var existing := get_node_or_null("CastBarRoot") as Control
	if existing != null and is_instance_valid(existing):
		existing.visible = false
		existing.queue_free()
	_cast_root = null
	_cast_bar = null
	_cast_label = null


func _style_cast_bar_mode(mode: String) -> void:
	if _cast_bar == null:
		return
	if mode == "channel":
		_style_status_bar(_cast_bar, Color(0.95, 0.55, 0.2, 1.0))
	else:
		_style_status_bar(_cast_bar, Color(0.55, 0.72, 1.0, 1.0))
	_cast_bar.custom_minimum_size = Vector2(0, 22)


func _tick_cast_bar_visual(delta: float) -> void:
	if not _cast_active:
		return
	if _cast_duration <= 0.0:
		return
	_cast_elapsed = minf(_cast_elapsed + maxf(delta, 0.0), _cast_duration)
	var frac: float = clampf(_cast_elapsed / _cast_duration, 0.0, 1.0)
	_sync_skill_cast_overlays()


func apply_cast_start(action: Dictionary) -> void:
	# Center cast bar removed — progress lives on skill-cell CdChrome only.
	_cast_active = true
	_cast_mode = str(action.get("mode", "cast"))
	_cast_duration = maxf(float(action.get("duration", 0.0)), 0.05)
	_cast_elapsed = float(action.get("elapsed", 0.0))
	_cast_skill_id = str(action.get("skill_id", "")).strip_edges()
	_cast_skill_name = str(action.get("name", action.get("skill_id", "技能")))
	if _cast_root != null and is_instance_valid(_cast_root):
		_cast_root.visible = false
	_sync_skill_cast_overlays()


func apply_cast_update(action: Dictionary) -> void:
	if not _cast_active:
		apply_cast_start(action)
		return
	_cast_elapsed = float(action.get("elapsed", _cast_elapsed))
	_cast_duration = maxf(float(action.get("duration", _cast_duration)), 0.05)
	var sid := str(action.get("skill_id", "")).strip_edges()
	if sid != "":
		_cast_skill_id = sid
	var nm := str(action.get("name", "")).strip_edges()
	if nm != "":
		_cast_skill_name = nm
	if _cast_root != null and is_instance_valid(_cast_root):
		_cast_root.visible = false
	_sync_skill_cast_overlays()


func apply_cast_end(action: Dictionary) -> void:
	_cast_active = false
	_cast_elapsed = 0.0
	_cast_duration = 0.0
	_cast_skill_id = ""
	if _cast_root != null and is_instance_valid(_cast_root):
		_cast_root.visible = false
	_sync_skill_cast_overlays()
	var _ok := bool(action.get("ok", false))
	var _cancelled := bool(action.get("cancelled", false))
	if _cancelled:
		pass


func _refresh_xp_bar() -> void:
	_ensure_xp_bar()
	if _xp_bar == null:
		return
	var exp_cur: int = maxi(int(_server_combat.get("exp", 0)), 0)
	var exp_next: int = int(_server_combat.get("exp_to_next", 0))
	if exp_next <= 0:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_bar.tooltip_text = "经验 %d" % exp_cur
	else:
		_xp_bar.max_value = float(exp_next)
		_xp_bar.value = float(mini(exp_cur, exp_next))
		_xp_bar.tooltip_text = "经验 %d / %d" % [exp_cur, exp_next]


func _refresh_bars() -> void:
	cp_bar.max_value = _cp_max
	hp_bar.max_value = _hp_max
	mp_bar.max_value = _mp_max
	cp_bar.value = _cp
	hp_bar.value = _hp
	mp_bar.value = _mp
	var cp_s := "CP  %d / %d" % [int(_cp), int(_cp_max)]
	var hp_s := "HP  %d / %d" % [int(_hp), int(_hp_max)]
	var mp_s := "MP  %d / %d" % [int(_mp), int(_mp_max)]
	if cp_text != null:
		cp_text.text = cp_s
	if hp_text != null:
		hp_text.text = hp_s
	if mp_text != null:
		mp_text.text = mp_s
	_ensure_status_overlays()
	var cp_o := cp_bar.get_node_or_null("CpOverlay") as Label if cp_bar else null
	var hp_o := hp_bar.get_node_or_null("HpOverlay") as Label if hp_bar else null
	var mp_o := mp_bar.get_node_or_null("MpOverlay") as Label if mp_bar else null
	if cp_o:
		cp_o.text = cp_s
		cp_o.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	if hp_o:
		hp_o.text = hp_s
		hp_o.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	if mp_o:
		mp_o.text = mp_s
		mp_o.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_refresh_xp_bar()

func set_minimap_hint(text: String) -> void:
	minimap_label.text = text


func bind_radar(map_field: Node2D, player: Node2D, map_id: String = "", blip_source: Variant = null) -> void:
	_radar_map_field = map_field
	_radar_player = player
	_radar_map_id = map_id
	_radar_blip_source = blip_source
	if _radar and _radar.has_method("bind_map_field"):
		_radar.bind_map_field(map_field, map_id)
	_sync_radar(true)


func clear_target() -> void:
	target_panel.visible = false
	target_name.text = ""
	target_hp.value = 0
	target_hp.visible = false
	_target_world_pos = null
	if _target_status_chip_row != null and is_instance_valid(_target_status_chip_row):
		_rebuild_status_chips(_target_status_chip_row, [])
	if _radar and _radar.has_method("clear_target_angle"):
		_radar.clear_target_angle()


func _ensure_target_chrome() -> void:
	## Name + × close on one row; HP bar below (monster only).
	if target_panel == null:
		return
	var vbox := target_panel.find_child("TargetVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var head := vbox.get_node_or_null("TargetHead") as HBoxContainer
	if head == null:
		head = HBoxContainer.new()
		head.name = "TargetHead"
		head.add_theme_constant_override("separation", 6)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(head)
		vbox.move_child(head, 0)
		if target_name.get_parent() != head:
			target_name.reparent(head)
		target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var close_btn := Button.new()
		close_btn.name = "TargetClose"
		close_btn.text = "×"
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.custom_minimum_size = Vector2(28, 22)
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		close_btn.pressed.connect(_on_target_close_pressed)
		head.add_child(close_btn)
	# Keep HP under the head row.
	if target_hp.get_parent() == vbox:
		vbox.move_child(target_hp, mini(1, vbox.get_child_count() - 1))


func _on_target_close_pressed() -> void:
	## × clears HUD target and world selection / foot ring.
	if _world_combat != null and _world_combat.has_method("clear_target_selection"):
		_world_combat.clear_target_selection()
	else:
		clear_target()


func show_target(p_name: String, hp_ratio: float = 1.0, world_pos: Variant = null, show_hp_bar: bool = true) -> void:
	_ensure_target_chrome()
	target_panel.visible = true
	target_name.text = p_name
	target_hp.visible = show_hp_bar
	if show_hp_bar:
		target_hp.max_value = 100.0
		target_hp.value = clampf(hp_ratio, 0.0, 1.0) * 100.0
	else:
		target_hp.value = 0
	if typeof(world_pos) == TYPE_VECTOR2:
		_target_world_pos = world_pos
		_update_target_angle()
	else:
		_target_world_pos = null
		if _radar and _radar.has_method("clear_target_angle"):
			_radar.clear_target_angle()

func append_chat(speaker: String, msg: String) -> void:
	_push_chat(_chat_channel if _chat_channel != "all" else "all", speaker, msg)

func append_system(msg: String) -> void:
	_push_chat("system", "系统", msg)


func show_npc_dialogue(npc_name: String, body: String, options: Array = [], face: Dictionary = {}) -> void:
	## Open Lineage2-ish NPC Chat panel. options: Array of String or {label, id}.
	_ensure_npc_chat()
	var title_name := npc_name.strip_edges()
	if title_name == "":
		title_name = "NPC"
	_npc_chat_name.text = title_name
	_apply_dialogue_face(face)
	var body_text := body.strip_edges()
	if body_text == "":
		body_text = "helloworld"
	_npc_chat_body.clear()
	var safe := body_text.replace("[", "[lb]")
	_npc_chat_body.append_text("[center]%s[/center]" % safe)
	for c in _npc_chat_options.get_children():
		c.queue_free()
	for opt in options:
		var label := ""
		if typeof(opt) == TYPE_DICTIONARY:
			label = str(opt.get("label", opt.get("text", "")))
		else:
			label = str(opt)
		label = label.strip_edges()
		if label == "":
			continue
		var link := RichTextLabel.new()
		link.bbcode_enabled = true
		link.fit_content = true
		link.scroll_active = false
		link.mouse_filter = Control.MOUSE_FILTER_STOP
		link.add_theme_font_size_override("normal_font_size", 13)
		link.add_theme_color_override("default_color", Color(0.35, 0.55, 1.0))
		link.add_theme_color_override("font_url_color", Color(0.35, 0.55, 1.0))
		link.append_text("[center][url][u]%s[/u][/url][/center]" % label)
		var opt_id := ""
		var opt_idx := _npc_chat_options.get_child_count()
		if typeof(opt) == TYPE_DICTIONARY:
			opt_id = str(opt.get("id", "")).strip_edges()
		link.meta_clicked.connect(_make_dialogue_option_handler(opt_id, opt_idx, label))
		_npc_chat_options.add_child(link)
	_npc_chat.visible = true
	_npc_chat.move_to_front()
	var base: Vector2 = _npc_chat.get_meta("base_size", Vector2(320, 280))
	_npc_chat.size = base
	call_deferred("_place_npc_chat")


func _make_dialogue_option_handler(option_id: String, option_index: int, label: String) -> Callable:
	return func(_meta):
		hide_npc_dialogue()
		if _world_combat != null and _world_combat.has_method("request_event_choice"):
			_world_combat.request_event_choice(option_id, option_index)
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_event_choice"):
				srv.try_event_choice(option_id, option_index)
			append_system("对话选项：%s" % label)


func hide_npc_dialogue() -> void:
	if _npc_chat != null:
		_npc_chat.visible = false


func _ensure_npc_chat() -> void:
	if _npc_chat != null and is_instance_valid(_npc_chat):
		return
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.name = "NpcChat"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(260, 200)
	panel.default_size = Vector2(320, 280)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(260, 200)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.82)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.72, 0.58, 0.32, 1.0)  # bronze / gold
	sb.content_margin_left = 0
	sb.content_margin_top = 0
	sb.content_margin_right = 0
	sb.content_margin_bottom = 0
	# Double-line feel: outer gold + slightly inset dark fill
	sb.shadow_color = Color(0.35, 0.28, 0.15, 0.55)
	sb.shadow_size = 1
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 10)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	# Title bar: Chat + X
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.text = "Chat"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 13)
	title_l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 22)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	close_btn.pressed.connect(hide_npc_dialogue)
	head.add_child(close_btn)
	var sep1 := HSeparator.new()
	sep1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep1.add_theme_constant_override("separation", 2)
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = Color(0.55, 0.45, 0.28, 0.55)
	sep_sb.set_content_margin_all(0)
	sep1.add_theme_stylebox_override("separator", sep_sb)
	vbox.add_child(sep1)
	# NPC name centered
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_l)
	var face_tex := TextureRect.new()
	face_tex.name = "Face"
	face_tex.visible = false
	face_tex.custom_minimum_size = Vector2(96, 96)
	face_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(face_tex)
	var sep2 := HSeparator.new()
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_sb2 := StyleBoxFlat.new()
	sep_sb2.bg_color = Color(0.4, 0.35, 0.25, 0.4)
	sep_sb2.set_content_margin_all(0)
	sep2.add_theme_stylebox_override("separator", sep_sb2)
	vbox.add_child(sep2)
	# Body scroll
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var body_rtl := RichTextLabel.new()
	body_rtl.name = "Body"
	body_rtl.bbcode_enabled = true
	body_rtl.fit_content = true
	body_rtl.scroll_active = false
	body_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_rtl.add_theme_font_size_override("normal_font_size", 13)
	body_rtl.add_theme_color_override("default_color", Color(1, 1, 1))
	body_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body_rtl)
	# Option links
	var opts := VBoxContainer.new()
	opts.name = "Options"
	opts.add_theme_constant_override("separation", 4)
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(opts)
	# Theme blue underline for BBCode urls
	body_rtl.add_theme_color_override("font_url_color", Color(0.35, 0.55, 1.0))
	panel.set_meta("base_size", Vector2(320, 280))
	_npc_chat = panel
	_npc_chat_name = name_l
	_npc_chat_body = body_rtl
	_npc_chat_options = opts
	_npc_chat_face = face_tex


func _apply_dialogue_face(face: Dictionary) -> void:
	if _npc_chat_face == null:
		return
	var fid := str(face.get("id", face.get("face", ""))).strip_edges()
	if fid == "":
		_npc_chat_face.texture = null
		_npc_chat_face.visible = false
		return
	var tex: Texture2D = CharsetSheet.make_face_texture(fid, int(face.get("index", 0)), str(face.get("pack_dir", "")))
	_npc_chat_face.texture = tex
	_npc_chat_face.visible = tex != null


func _place_npc_chat() -> void:
	if _npc_chat == null or not _npc_chat.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var base: Vector2 = _npc_chat.get_meta("base_size", Vector2(320, 280))
	if _npc_chat.size.x < 64.0 or _npc_chat.size.y < 64.0:
		_npc_chat.size = base
	# Fixed left-ish like classic L2 Chat
	_npc_chat.global_position = Vector2(24, clampf((vp.y - _npc_chat.size.y) * 0.35, 48, vp.y - _npc_chat.size.y - 24))


func blocks_world_click(screen_pos: Vector2 = Vector2.INF) -> bool:
	## True when the pointer is over HUD chrome or a floating window (incl. map).
	if screen_pos.x == INF or screen_pos.y == INF:
		screen_pos = get_viewport().get_mouse_position()
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and (hovered == self or is_ancestor_of(hovered)):
		return true
	for id in _windows.keys():
		var panel: Control = _windows[id] as Control
		if panel != null and panel.visible and panel.get_global_rect().has_point(screen_pos):
			return true
	if _party_panel != null and _party_panel.visible and _party_panel.get_global_rect().has_point(screen_pos):
		return true
	if _npc_chat != null and _npc_chat.visible and _npc_chat.get_global_rect().has_point(screen_pos):
		return true
	# Fixed shell widgets that use STOP (chat, hotbar, minimap, bars, menus).
	for node_name in ["ChatLog", "ChatInput", "Hotbar", "MenuRow", "ChatTabs", "MinimapView", "TargetPanel"]:
		var n := find_child(node_name, true, false) as Control
		if n != null and n.visible and n.get_global_rect().has_point(screen_pos):
			return true
	# Status / CP-HP-MP cluster (top-left shell).
	for node_name in ["NameLabel", "CpBar", "HpBar", "MpBar"]:
		var n2 := find_child(node_name, true, false) as Control
		if n2 == null:
			continue
		var parent := n2.get_parent() as Control
		if parent != null and parent.visible and parent.get_global_rect().has_point(screen_pos):
			return true
		break
	return false

func _push_chat(channel: String, speaker: String, msg: String) -> void:
	var color := "#c9a66b"
	match channel:
		"system":
			color = "#a8a890"
		"nearby":
			color = "#9ec9ff"
		"whisper":
			color = "#e0a0ff"
		"party":
			color = "#6bc98a"
		"clan":
			color = "#6ba0c9"
		"trade":
			color = "#c9c26b"
		"alliance":
			color = "#c96bb0"
		_:
			color = "#c9a66b"
	_chat_history.append({
		"channel": channel,
		"speaker": speaker,
		"msg": msg,
		"color": color,
	})
	if _chat_history.size() > CHAT_HISTORY_MAX:
		_chat_history = _chat_history.slice(_chat_history.size() - CHAT_HISTORY_MAX)
	if _chat_visible(channel):
		chat_log.append_text("[color=%s]%s[/color]: %s\n" % [color, speaker, msg])

func _chat_visible(channel: String) -> bool:
	if _chat_channel == "all":
		return true
	# System chatter stays on 全部 only, so other tabs filter cleanly.
	if channel == "system":
		return false
	return channel == _chat_channel

func _rebuild_chat_log() -> void:
	chat_log.clear()
	for row in _chat_history:
		var ch := str(row.get("channel", "all"))
		if not _chat_visible(ch):
			continue
		chat_log.append_text("[color=%s]%s[/color]: %s\n" % [
			str(row.get("color", "#c9a66b")),
			str(row.get("speaker", "")),
			str(row.get("msg", "")),
		])

func _on_chat_submitted(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	var channel := _chat_channel
	var body := t
	var whisper_to := ""
	# Prefixes override current tab.
	if t.begins_with("/w ") or t.begins_with("/W "):
		channel = "whisper"
		var rest := t.substr(3).strip_edges()
		var sp := rest.find(" ")
		if sp <= 0:
			append_system("私聊格式：/w 名字 内容")
			chat_input.clear()
			return
		whisper_to = rest.substr(0, sp).strip_edges()
		body = rest.substr(sp + 1).strip_edges()
	elif t.begins_with(char(34)) and t.length() > 1:
		# "Name message
		channel = "whisper"
		var rest2 := t.substr(1).strip_edges()
		var sp2 := rest2.find(" ")
		if sp2 <= 0:
			append_system("私聊格式：/w 名字 内容")
			chat_input.clear()
			return
		whisper_to = rest2.substr(0, sp2).strip_edges()
		body = rest2.substr(sp2 + 1).strip_edges()
	elif t.begins_with("~"):
		channel = "nearby"
		body = t.substr(1).strip_edges()
	elif t.begins_with("!"):
		channel = "all"
		body = t.substr(1).strip_edges()
		if not body.is_empty():
			body = "（喊）" + body
	elif t.begins_with("#"):
		channel = "party"
		body = t.substr(1).strip_edges()
	elif t.begins_with("@"):
		channel = "clan"
		body = t.substr(1).strip_edges()
	elif t.begins_with("+"):
		channel = "trade"
		body = t.substr(1).strip_edges()
	elif t.begins_with("$"):
		channel = "alliance"
		body = t.substr(1).strip_edges()
	elif _chat_channel == "whisper":
		# On whisper tab without /w: need a prior target — prompt.
		append_system("私聊请用：/w 名字 内容")
		chat_input.clear()
		return
	elif _chat_channel == "all":
		# Default typing on 全部 = shout
		channel = "all"
	elif _chat_channel == "nearby":
		channel = "nearby"
	if body.is_empty():
		chat_input.clear()
		return
	_chat_channel = channel if channel != "whisper" else "whisper"
	_highlight_chat_tab(_chat_channel)
	# Prefer server-authoritative chat (nearby range, whisper stub echo).
	if _world_combat != null and _world_combat.has_method("request_chat"):
		_world_combat.request_chat(channel, body, whisper_to)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_chat"):
			_apply_chat_result_locally(srv.try_chat(channel, body, whisper_to))
		else:
			var who: String = str(Net.session().active_character().get("name", ""))
			if who.is_empty():
				who = "你"
			_push_chat(channel, who, body)
	if not _chat_visible(channel):
		_rebuild_chat_log()
	chat_input.clear()


func apply_chat_message(action: Dictionary) -> void:
	var channel := str(action.get("channel", "all"))
	var speaker := str(action.get("speaker", ""))
	var msg := str(action.get("text", "")).strip_edges()
	if msg.is_empty():
		return
	if channel == "whisper":
		var target := str(action.get("target", "")).strip_edges()
		var is_self := bool(action.get("self", false))
		if is_self and not target.is_empty():
			speaker = "%s → %s" % [speaker, target]
		elif not is_self and not target.is_empty():
			speaker = "%s → %s" % [speaker, target]
	_push_chat(channel, speaker if not speaker.is_empty() else "?", msg)
	if channel != _chat_channel and _chat_channel != "all":
		# Nudge: whisper/nearby always visible on 全部; optional flash ignored.
		pass


func _apply_chat_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"chat_message":
				apply_chat_message(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
			"remote_spawn":
				if _world_combat != null and _world_combat.has_method("_upsert_remote_marker"):
					var rp: Variant = action.get("player", {})
					if typeof(rp) == TYPE_DICTIONARY:
						_world_combat._upsert_remote_marker(rp)
			"remote_despawn":
				if _world_combat != null and _world_combat.has_method("_remove_remote_marker"):
					_world_combat._remove_remote_marker(str(action.get("player_id", "")))


func _on_remote_debug_spawn() -> void:
	if _world_combat != null and _world_combat.has_method("request_remote_debug_spawn"):
		_world_combat.request_remote_debug_spawn("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_remote_debug_spawn"):
		var result: Dictionary = srv.try_remote_debug_spawn("")
		_apply_chat_result_locally(result)
		# Also ask world if bound
		if _world_combat != null:
			pass


func _process(_delta: float) -> void:
	_tick_cast_bar_visual(_delta)
	_tick_hotbar_cooldowns(_delta)
	_sync_quest_drawer_follow()
	_tick_ground_drop_zone()
	if not RADAR_ENABLED:
		return
	if _radar_player == null or _radar == null:
		return
	_sync_radar(false)


func _sync_radar(force_hint: bool = false) -> void:
	if not RADAR_ENABLED:
		return
	if _radar == null or _radar_player == null:
		return
	var center: Vector2 = _radar_player.global_position
	var yaw: float = PI * 0.5
	if _radar_player.has_method("facing_angle"):
		yaw = float(_radar_player.facing_angle())
	if _radar.has_method("update_view"):
		_radar.update_view(center, yaw)
	_update_target_angle()
	var cell := Vector2i.ZERO
	if "cell" in _radar_player:
		cell = _radar_player.cell
	elif _radar_map_field != null and _radar_map_field.has_method("world_to_cell"):
		cell = _radar_map_field.world_to_cell(center)
	# Blips: throttle (wander NPCs); hint / map-window text only when cell changes.
	var now_ms: int = Time.get_ticks_msec()
	if force_hint or now_ms - _radar_blips_msec >= RADAR_BLIPS_INTERVAL_MS:
		_radar_blips_msec = now_ms
		_sync_radar_blips()
	if force_hint or cell != _radar_hint_cell:
		_radar_hint_cell = cell
		if minimap_label != null and _radar.has_method("hint_text"):
			minimap_label.text = str(_radar.hint_text())
		_refresh_map_window_info()


func _sync_radar_blips() -> void:
	if _radar == null or not _radar.has_method("set_entity_blips"):
		return
	var blips: Array = []
	if typeof(_radar_blip_source) == TYPE_CALLABLE:
		var result: Variant = _radar_blip_source.call()
		if typeof(result) == TYPE_ARRAY:
			blips = result
	elif _radar_blip_source is Node and is_instance_valid(_radar_blip_source):
		if _radar_blip_source.has_method("get_radar_blips"):
			var result2: Variant = _radar_blip_source.get_radar_blips()
			if typeof(result2) == TYPE_ARRAY:
				blips = result2
	_radar.set_entity_blips(blips)


func _update_target_angle() -> void:
	if _radar == null:
		return
	if typeof(_target_world_pos) != TYPE_VECTOR2 or _radar_player == null:
		return
	var delta: Vector2 = (_target_world_pos as Vector2) - _radar_player.global_position
	if delta.length_squared() < 0.0001:
		if _radar.has_method("clear_target_angle"):
			_radar.clear_target_angle()
		return
	if _radar.has_method("set_target_angle"):
		_radar.set_target_angle(atan2(delta.y, delta.x))


func _setup_radar() -> void:
	if not RADAR_ENABLED:
		var panel := get_node_or_null("MinimapPanel")
		if panel:
			panel.visible = false
		set_process(false)
		return
	for c in minimap_view_host.get_children():
		c.queue_free()
	_radar = Control.new()
	_radar.set_script(RadarView)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	minimap_view_host.add_child(_radar)

func _build_chat_tabs() -> void:
	for c in chat_tabs.get_children():
		c.queue_free()
	for item in CHAT_CHANNELS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(52, 24)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var channel := str(item[1])
		btn.pressed.connect(_on_chat_tab.bind(channel))
		chat_tabs.add_child(btn)
	_highlight_chat_tab("all")

func _on_chat_tab(channel: String) -> void:
	_chat_channel = channel
	_highlight_chat_tab(channel)
	_rebuild_chat_log()

func _highlight_chat_tab(channel: String) -> void:
	for i in range(chat_tabs.get_child_count()):
		var btn := chat_tabs.get_child(i) as Button
		if btn == null:
			continue
		var id := str(CHAT_CHANNELS[i][1])
		var on := id == channel
		btn.modulate = Color(1.15, 1.05, 0.75) if on else Color(0.85, 0.85, 0.9)
		btn.disabled = false

func _hotbar_bind_key(page: int, slot: int) -> String:
	return "%d:%d" % [page, slot]


func _session_hotbar_store() -> Node:
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("session"):
		return net.session()
	return get_node_or_null("/root/GameSession")


func _restore_hotbar_from_session() -> void:
	var sess := _session_hotbar_store()
	if sess == null:
		return
	_hotbar_page = clampi(int(sess.hotbar_page), 0, HOTBAR_PAGES.size() - 1)
	var raw: Variant = sess.hotbar_bindings
	if typeof(raw) != TYPE_DICTIONARY:
		_hotbar_bindings = {}
		return
	var src: Dictionary = raw
	var out: Dictionary = {}
	for k in src.keys():
		var v: Variant = src[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var kind := str(v.get("kind", "")).strip_edges()
		var id := str(v.get("id", "")).strip_edges()
		if kind.is_empty() or id.is_empty():
			continue
		out[str(k)] = {"kind": kind, "id": id}
	_hotbar_bindings = out


func _persist_hotbar_to_session() -> void:
	var sess := _session_hotbar_store()
	if sess == null:
		return
	sess.hotbar_page = _hotbar_page
	sess.hotbar_bindings = _hotbar_bindings.duplicate(true)


func _get_hotbar_binding(page: int, slot: int) -> Dictionary:
	var k := _hotbar_bind_key(page, slot)
	if _hotbar_bindings.has(k):
		var v: Variant = _hotbar_bindings[k]
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


func _set_hotbar_binding(page: int, slot: int, kind: String, id: String) -> void:
	kind = kind.strip_edges()
	id = id.strip_edges()
	var k := _hotbar_bind_key(page, slot)
	if kind.is_empty() or id.is_empty():
		_hotbar_bindings.erase(k)
	else:
		_hotbar_bindings[k] = {"kind": kind, "id": id}
	_persist_hotbar_to_session()
	_refresh_hotbar_slot_visuals()


func _clear_hotbar_binding(page: int, slot: int) -> void:
	_hotbar_bindings.erase(_hotbar_bind_key(page, slot))
	_persist_hotbar_to_session()
	_refresh_hotbar_slot_visuals()
	append_system("已清除快捷栏 %d 槽位 %d" % [page + 1, slot])


func _inventory_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	for it in _server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id:
			return int(it.get("qty", 0))
	return 0


func _is_item_equipped(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return false
	for it in _server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")).strip_edges() == item_id:
			return true
	return false


func _letter_avatar(name: String) -> String:
	return InvSlot.first_grapheme(name)


func _layout_hotbar_side_nav(prev: Node, next: Node) -> void:
	## Put < > on the sides of the slot row; hide page label / top nav row.
	if hotbar == null:
		return
	if hotbar_page_label != null:
		hotbar_page_label.visible = false
	var nav := find_child("HotbarNav", true, false) as Control
	if nav != null:
		nav.visible = false
	# Prefer a dedicated side-nav HBox wrapping prev | slots | next.
	var host := hotbar.get_parent()
	if host == null:
		return
	var side := host.get_node_or_null("HotbarSideRow") as HBoxContainer
	if side == null:
		side = HBoxContainer.new()
		side.name = "HotbarSideRow"
		side.add_theme_constant_override("separation", 4)
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_child(side)
		# Place above menu / where Hotbar was.
		if hotbar.get_parent() == host:
			host.move_child(side, hotbar.get_index())
		hotbar.reparent(side)
	if prev != null and is_instance_valid(prev):
		if prev.get_parent() != side:
			prev.reparent(side)
		side.move_child(prev, 0)
		prev.custom_minimum_size = Vector2(22, GRID_CELL)
		prev.text = "<"
	if hotbar.get_parent() == side:
		side.move_child(hotbar, mini(1, side.get_child_count() - 1))
	if next != null and is_instance_valid(next):
		if next.get_parent() != side:
			next.reparent(side)
		side.move_child(next, side.get_child_count() - 1)
		next.custom_minimum_size = Vector2(22, GRID_CELL)
		next.text = ">"


func _text_input_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is CodeEdit


func _hotbar_keycode_to_slot(keycode: int) -> Vector2i:
	## Returns Vector2i(page, slot_index0) or (-1,-1).
	match keycode:
		KEY_F1: return Vector2i(0, 0)
		KEY_F2: return Vector2i(0, 1)
		KEY_F3: return Vector2i(0, 2)
		KEY_F4: return Vector2i(0, 3)
		KEY_F5: return Vector2i(0, 4)
		KEY_F6: return Vector2i(0, 5)
		KEY_F7: return Vector2i(0, 6)
		KEY_F8: return Vector2i(0, 7)
		KEY_F9: return Vector2i(0, 8)
		KEY_F10: return Vector2i(0, 9)
		KEY_F11: return Vector2i(0, 10)
		KEY_F12: return Vector2i(0, 11)
		KEY_QUOTELEFT: return Vector2i(1, 0)  # `
		KEY_1: return Vector2i(1, 1)
		KEY_2: return Vector2i(1, 2)
		KEY_3: return Vector2i(1, 3)
		KEY_4: return Vector2i(1, 4)
		KEY_5: return Vector2i(1, 5)
		KEY_6: return Vector2i(1, 6)
		KEY_7: return Vector2i(1, 7)
		KEY_8: return Vector2i(1, 8)
		KEY_9: return Vector2i(1, 9)
		KEY_0: return Vector2i(1, 10)
		KEY_MINUS, KEY_EQUAL: return Vector2i(1, 11)  # - / = / + (last slot)
	return Vector2i(-1, -1)


func _try_hotbar_key(keycode: int) -> bool:
	if _text_input_focused():
		return false
	var map := _hotbar_keycode_to_slot(keycode)
	if map.x < 0:
		return false
	var page: int = map.x
	var idx: int = map.y
	if page >= HOTBAR_PAGES.size() or idx >= HOTBAR_PAGES[page].size():
		return false
	var key := str(HOTBAR_PAGES[page][idx])
	_on_hotbar_pressed(page, idx + 1, key)
	return true


func _build_hotbar() -> void:
	# Immediate free so get_child_count() is accurate this frame.
	while hotbar.get_child_count() > 0:
		var c: Node = hotbar.get_child(0)
		hotbar.remove_child(c)
		c.free()
	var keys: Array = HOTBAR_PAGES[_hotbar_page]
	for i in range(keys.size()):
		var slot := Button.new()
		slot.set_script(HotbarSlot)
		slot.custom_minimum_size = Vector2(GRID_CELL, GRID_CELL)
		var slot_n: int = i + 1
		slot.focus_mode = Control.FOCUS_NONE
		slot.configure(_hotbar_page, slot_n)
		slot.pressed.connect(_on_hotbar_pressed.bind(_hotbar_page, slot_n, str(keys[i])))
		slot.item_dropped.connect(_on_hotbar_item_dropped)
		slot.skill_dropped.connect(_on_hotbar_skill_dropped)
		slot.binding_cleared.connect(_on_hotbar_binding_cleared)
		hotbar.add_child(slot)
		if slot.has_method("set_key_hint"):
			slot.set_key_hint(str(keys[i]))
	if hotbar_page_label != null:
		hotbar_page_label.visible = false
	_refresh_hotbar_slot_visuals()


func _refresh_hotbar_slot_visuals() -> void:
	if hotbar == null:
		return
	var keys: Array = HOTBAR_PAGES[_hotbar_page]
	var page0_hints := {
		1: "普通攻击",
		2: "强力打击",
		3: "轻度治疗",
		4: "小型生命药水",
		5: "小型魔法药水",
	}
	for i in range(hotbar.get_child_count()):
		var btn := hotbar.get_child(i) as Button
		if btn == null:
			continue
		var slot_n: int = i + 1
		var key_label := str(keys[i]) if i < keys.size() else str(slot_n)
		var bind := _get_hotbar_binding(_hotbar_page, slot_n)
		if btn.has_method("set_binding_visual"):
			if not bind.is_empty():
				var kind := str(bind.get("kind", ""))
				var bid := str(bind.get("id", ""))
				if kind == "item":
					var dname := _item_label(bid)
					var q := _inventory_qty(bid)
					var eq_on := q <= 0 and _is_item_equipped(bid)
					var tip := "%s ×%d\n%s（右键清除）" % [dname, q, bid]
					if eq_on:
						tip = "%s（已装备）\n%s（右键清除）" % [dname, bid]
					btn.set_binding_visual(
						"item",
						_letter_avatar(dname),
						q,
						tip,
						_item_icon_index(bid),
						_item_icon_ref(bid)
					)
				elif kind == "skill":
					var sname := _skill_display_name(bid)
					var tip_extra := "（被动）" if _is_passive_skill(bid) else ""
					btn.set_binding_visual(
						"skill",
						_letter_avatar(sname),
						0,
						"技能 %s%s（右键清除）" % [sname, tip_extra],
						_skill_icon_index(bid),
						_skill_icon_ref(bid)
					)
				else:
					btn.set_binding_visual("", "", 0, key_label)
			elif _hotbar_page == 0 and page0_hints.has(slot_n):
				btn.set_binding_visual(
					"",
					"",
					0,
					"%s %s（未绑定，按键仍可用默认）" % [key_label, str(page0_hints[slot_n])]
				)
			else:
				btn.set_binding_visual("", "", 0, "%s（可从背包拖入，右键清除）" % key_label)
		if btn.has_method("set_key_hint"):
			btn.set_key_hint(key_label)
		else:
			# Fallback if script not attached yet.
			btn.text = ""
			btn.tooltip_text = key_label
		var cd_id := ""
		var cd_kind := ""
		if not bind.is_empty():
			cd_kind = str(bind.get("kind", ""))
			cd_id = str(bind.get("id", "")).strip_edges()
		elif _hotbar_page == 0:
			match slot_n:
				1:
					cd_kind = "skill"
					cd_id = "basic_attack"
				2:
					cd_kind = "skill"
					cd_id = "power_strike"
				3:
					cd_kind = "skill"
					cd_id = "heal_light"
				4:
					cd_kind = "item"
					cd_id = "potion_hp_small"
				5:
					cd_kind = "item"
					cd_id = "potion_mp_small"
		if btn.has_method("set_bound_id"):
			btn.set_bound_id(cd_id)
		_apply_slot_cooldown_visual(btn, cd_kind, cd_id)
	_sync_hotbar_cast_overlays()


func _on_hotbar_item_dropped(page: int, slot: int, item_id: String) -> void:
	_set_hotbar_binding(page, slot, "item", item_id)
	append_system("快捷栏绑定物品：%s → 页%d 槽%d" % [_item_label(item_id), page + 1, slot])


func _on_hotbar_skill_dropped(page: int, slot: int, skill_id: String) -> void:
	_set_hotbar_binding(page, slot, "skill", skill_id)
	append_system("快捷栏绑定技能：%s → 页%d 槽%d" % [_skill_display_name(skill_id), page + 1, slot])


func _on_hotbar_binding_cleared(page: int, slot: int) -> void:
	_clear_hotbar_binding(page, slot)


func _on_hotbar_pressed(page: int, slot: int, key: String) -> void:
	var bind := _get_hotbar_binding(page, slot)
	if not bind.is_empty() and _world_combat != null:
		var kind := str(bind.get("kind", ""))
		var bid := str(bind.get("id", ""))
		if kind == "item" and _world_combat.has_method("request_use_item"):
			_world_combat.request_use_item(bid)
			return
		if kind == "skill":
			if _is_passive_skill(bid):
				append_system("被动，无需施放")
				return
			if _world_combat.has_method("request_use_skill"):
				_world_combat.request_use_skill(bid)
				return
	# Page 0 default combat wiring when unbound.
	if page == 0 and _world_combat != null:
		match slot:
			1:
				if _world_combat.has_method("request_use_skill"):
					_world_combat.request_use_skill("basic_attack")
					return
			2:
				if _world_combat.has_method("request_use_skill"):
					_world_combat.request_use_skill("power_strike")
					return
			3:
				if _world_combat.has_method("request_use_skill"):
					_world_combat.request_use_skill("heal_light")
					return
			4:
				if _world_combat.has_method("request_use_item"):
					_world_combat.request_use_item("potion_hp_small")
					return
			5:
				if _world_combat.has_method("request_use_item"):
					_world_combat.request_use_item("potion_mp_small")
					return
	append_system("快捷栏%d [%s] 槽位 %d（可从背包拖入）" % [page + 1, key, slot])


func bind_world_combat(world: Node) -> void:
	_world_combat = world


func apply_combat_stats(stats: Dictionary) -> void:
	## Apply authoritative HP/MP/level/exp from MockServer actions / spawn.
	if stats.is_empty():
		return
	for k in stats.keys():
		var v = stats[k]
		# Skip sentinel -1 for numeric fields we treat as "unchanged".
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) < 0 and str(k) in ["hp", "hp_max", "mp", "mp_max", "level", "exp", "exp_to_next"]:
			continue
		_server_combat[str(k)] = v
	var hp_max_v: int = int(stats.get("hp_max", -1))
	var hp_v: int = int(stats.get("hp", -1))
	var mp_max_v: int = int(stats.get("mp_max", -1))
	var mp_v: int = int(stats.get("mp", -1))
	if hp_max_v >= 0:
		_hp_max = float(hp_max_v)
	if hp_v >= 0:
		_hp = float(hp_v)
	if mp_max_v >= 0:
		_mp_max = float(mp_max_v)
	if mp_v >= 0:
		_mp = float(mp_v)
	if stats.has("level") and int(stats.get("level", -1)) >= 1:
		var lv: int = int(stats.get("level", 1))
		if level_label != null:
			level_label.text = "Lv.%d" % lv
		if not _character.is_empty():
			_character["level"] = lv
	_refresh_bars()
	if _windows.has("character") and _windows["character"].visible:
		_refresh_window_contents()


func apply_inventory_snapshot(items: Array, gold: int = -1) -> void:
	_server_inventory = items.duplicate(true)
	if gold >= 0:
		_server_gold = gold
	elif Net.server() != null and Net.server().get("inventory") != null:
		var bag = Net.server().inventory
		if bag != null and bag.has_method("get_gold"):
			_server_gold = int(bag.get_gold())
	_refresh_inventory_gold_label()
	# Refresh open inventory window if present.
	if _windows.has("inventory") and _windows["inventory"].visible:
		_refresh_window_contents()
	# Update hotbar qty / letter avatars for item bindings.
	_refresh_hotbar_slot_visuals()
	# Keep shop sell list / gold in sync while open.
	if _shop_panel != null and _shop_panel.visible:
		_fill_shop_panel()


func apply_equipment_snapshot(slots: Array, bonuses: Dictionary = {}) -> void:
	_server_equipment = slots.duplicate(true)
	_server_equip_bonuses = bonuses.duplicate(true)
	if _windows.has("character") and _windows["character"].visible:
		_refresh_window_contents()
	# Equipped gear may leave bag qty 0 — still show hotbar letter.
	_refresh_hotbar_slot_visuals()


func apply_level_up(level: int, combat: Dictionary = {}) -> void:
	level = maxi(level, 1)
	if not combat.is_empty():
		apply_combat_stats(combat)
	else:
		apply_combat_stats({"level": level})
	if level_label != null:
		level_label.text = "Lv.%d" % level
	if not _character.is_empty():
		_character["level"] = level


func show_shop(shop_id: String, title: String, listings: Array, gold: int = 0) -> void:
	_shop_id = shop_id.strip_edges()
	_shop_title = title.strip_edges() if title.strip_edges() != "" else "商店"
	_shop_listings = listings.duplicate(true) if listings != null else []
	if gold >= 0:
		_server_gold = gold
	_ensure_shop_panel()
	_fill_shop_panel()
	if _shop_panel != null:
		_shop_panel.visible = true
		_shop_panel.move_to_front()


func hide_shop() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false
	_shop_id = ""
	_clear_shop_carts()


func show_loot(session_id: String, npc_id: String, items: Array) -> void:
	_loot_session_id = session_id.strip_edges()
	_loot_npc_id = npc_id.strip_edges()
	_loot_items = items.duplicate(true) if items != null else []
	_ensure_loot_panel()
	_fill_loot_panel()
	if _loot_panel != null:
		_loot_panel.visible = true
		_loot_panel.move_to_front()


func refresh_loot(session_id: String, items: Array) -> void:
	if session_id.strip_edges() != "" and _loot_session_id != "" and session_id != _loot_session_id:
		# Stale update from a previous session — ignore.
		return
	if session_id.strip_edges() != "":
		_loot_session_id = session_id.strip_edges()
	_loot_items = items.duplicate(true) if items != null else []
	if _loot_items.is_empty():
		hide_loot()
		return
	_ensure_loot_panel()
	_fill_loot_panel()
	if _loot_panel != null:
		_loot_panel.visible = true


func hide_loot() -> void:
	if _loot_panel != null:
		_loot_panel.visible = false
	_loot_session_id = ""
	_loot_npc_id = ""
	_loot_items.clear()


func _ensure_loot_panel() -> void:
	if _loot_panel != null and is_instance_valid(_loot_panel):
		return
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.name = "LootWindow"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(280, 220)
	panel.default_size = Vector2(300, 260)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(280, 220)
	panel.set_meta("fixed_size", true)
	panel.set_meta("base_size", Vector2(300, 260))
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head := HBoxContainer.new()
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.name = "LootTitle"
	title_l.text = "掉落确认"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 14)
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(_on_loot_close_pressed)
	head.add_child(close_btn)
	var hint := Label.new()
	hint.name = "LootHint"
	hint.text = "选择拾取或关闭（关闭将丢弃剩余）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	vbox.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.name = "LootScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "LootList"
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	var take_all := Button.new()
	take_all.text = "全部拾取"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.custom_minimum_size = Vector2(96, 30)
	take_all.pressed.connect(_on_loot_take_all_pressed)
	bottom.add_child(take_all)
	var close2 := Button.new()
	close2.text = "关闭"
	close2.focus_mode = Control.FOCUS_NONE
	close2.custom_minimum_size = Vector2(72, 30)
	close2.pressed.connect(_on_loot_close_pressed)
	bottom.add_child(close2)
	_loot_panel = panel
	call_deferred("_place_loot_panel")


func _place_loot_panel() -> void:
	if _loot_panel == null or not is_instance_valid(_loot_panel):
		return
	var vp := get_viewport_rect().size
	var sz := Vector2(300, 260)
	_loot_panel.size = sz
	_loot_panel.global_position = Vector2(
		maxi(8, int((vp.x - sz.x) * 0.5)),
		maxi(8, int((vp.y - sz.y) * 0.35))
	)


func _fill_loot_panel() -> void:
	if _loot_panel == null or not is_instance_valid(_loot_panel):
		return
	var list := _loot_panel.find_child("LootList", true, false) as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	if _loot_items.is_empty():
		var empty := Label.new()
		empty.text = "（无掉落）"
		empty.add_theme_font_size_override("font_size", 12)
		list.add_child(empty)
		return
	for it_v in _loot_items:
		if typeof(it_v) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_v
		var iid := str(it.get("item_id", it.get("id", ""))).strip_edges()
		var qty: int = int(it.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var dname := str(it.get("name", "")).strip_edges()
		if dname.is_empty():
			dname = _item_label(iid) if has_method("_item_label") else iid
		var iix := int(it.get("icon_index", _item_icon_index(iid)))
		var iref := str(it.get("icon_ref", "")).strip_edges()
		if iref.is_empty():
			var ic := str(it.get("icon", "")).strip_edges()
			if not ic.is_empty():
				iref = ic if ic.begins_with("content:") else ("content://icon/%s" % ic)
			else:
				iref = _item_icon_ref(iid)
		var icon_tex: Texture2D = null
		var am: Node = get_node_or_null("/root/AssetManager")
		if am != null and am.has_method("resolve_slot_icon_texture"):
			icon_tex = am.resolve_slot_icon_texture(iix, iref)
		if icon_tex != null:
			var tr := TextureRect.new()
			tr.texture = icon_tex
			tr.custom_minimum_size = Vector2(22, 22)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		else:
			var letter := Label.new()
			letter.text = dname.substr(0, 1) if dname.length() > 0 else "?"
			letter.custom_minimum_size = Vector2(22, 22)
			letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			letter.add_theme_font_size_override("font_size", 13)
			letter.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
			row.add_child(letter)
		var lab := Label.new()
		lab.text = "%s ×%d" % [dname, qty]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 13)
		row.add_child(lab)
		var take_btn := Button.new()
		take_btn.text = "拾取"
		take_btn.focus_mode = Control.FOCUS_NONE
		take_btn.custom_minimum_size = Vector2(56, 26)
		var captured := iid
		take_btn.pressed.connect(func(): _on_loot_take_pressed(captured))
		row.add_child(take_btn)


func _on_loot_take_pressed(item_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_loot_take"):
		_world_combat.request_loot_take(item_id, -1)
	else:
		append_system("无法拾取。")


func _on_loot_take_all_pressed() -> void:
	if _world_combat != null and _world_combat.has_method("request_loot_take_all"):
		_world_combat.request_loot_take_all()
	else:
		append_system("无法全部拾取。")


func _on_loot_close_pressed() -> void:
	if _world_combat != null and _world_combat.has_method("request_loot_close"):
		_world_combat.request_loot_close()
	else:
		hide_loot()


func _clear_shop_carts() -> void:
	_shop_buy_cart.clear()
	_shop_sell_cart.clear()


func _ensure_shop_panel() -> void:
	if _shop_panel != null and is_instance_valid(_shop_panel):
		if bool(_shop_panel.get_meta("shop_v2", false)):
			return
		_shop_panel.queue_free()
		_shop_panel = null
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.name = "ShopWindow"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(520, 400)
	panel.default_size = Vector2(560, 440)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(520, 400)
	panel.set_meta("fixed_size", true)
	panel.set_meta("base_size", Vector2(560, 440))
	panel.set_meta("shop_v2", true)
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	# Header: title + gold + close
	var head := HBoxContainer.new()
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.name = "ShopTitle"
	title_l.text = "商店"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 14)
	head.add_child(title_l)
	var gold_l := Label.new()
	gold_l.name = "ShopGold"
	gold_l.text = "金币: 0"
	gold_l.add_theme_font_size_override("font_size", 13)
	gold_l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.45))
	head.add_child(gold_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(hide_shop)
	head.add_child(close_btn)
	# Tabs
	var tabs := TabContainer.new()
	tabs.name = "ShopTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	var buy_root := _make_shop_tab_page("买入", "BuyCatalog", "BuyCart")
	tabs.add_child(buy_root)
	var sell_root := _make_shop_tab_page("卖出", "SellCatalog", "SellCart")
	tabs.add_child(sell_root)
	# Bottom confirm / cancel
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size = Vector2(88, 30)
	cancel_btn.pressed.connect(hide_shop)
	bottom.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.custom_minimum_size = Vector2(88, 30)
	ok_btn.pressed.connect(_on_shop_confirm)
	bottom.add_child(ok_btn)
	panel.set_meta("tabs", tabs)
	panel.set_meta("gold_label", gold_l)
	_shop_panel = panel
	call_deferred("_place_shop_panel")


func _make_shop_tab_page(title: String, catalog_name: String, cart_name: String) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = title
	root.add_theme_constant_override("separation", 4)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_label(root, "商品列表" if catalog_name.begins_with("Buy") else "背包可出售", 11, Color(0.75, 0.85, 0.95))
	var cat_scroll := ScrollContainer.new()
	cat_scroll.name = catalog_name + "Scroll"
	cat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cat_scroll.custom_minimum_size = Vector2(0, 140)
	root.add_child(cat_scroll)
	var cat_list := VBoxContainer.new()
	cat_list.name = catalog_name
	cat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_list.add_theme_constant_override("separation", 3)
	cat_scroll.add_child(cat_list)
	_add_label(root, "我的选择", 11, Color(0.85, 0.8, 0.65))
	var cart_scroll := ScrollContainer.new()
	cart_scroll.name = cart_name + "Scroll"
	cart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cart_scroll.custom_minimum_size = Vector2(0, 100)
	root.add_child(cart_scroll)
	var cart_list := VBoxContainer.new()
	cart_list.name = cart_name
	cart_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_list.add_theme_constant_override("separation", 3)
	cart_scroll.add_child(cart_list)
	return root


func _place_shop_panel() -> void:
	if _shop_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_shop_panel.size = Vector2(560, 440)
	_shop_panel.global_position = Vector2(maxi(8, int(vp.x * 0.2)), maxi(40, int(vp.y * 0.12)))


func _fill_shop_panel() -> void:
	_ensure_shop_panel()
	if _shop_panel == null:
		return
	var title_l := _shop_panel.find_child("ShopTitle", true, false) as Label
	if title_l != null:
		title_l.text = _shop_title if _shop_title != "" else "商店"
	var gold_l := _shop_panel.get_meta("gold_label") as Label
	if gold_l != null:
		gold_l.text = "金币: %d" % maxi(_server_gold, 0)
	var buy_cat := _shop_panel.find_child("BuyCatalog", true, false) as VBoxContainer
	var buy_cart := _shop_panel.find_child("BuyCart", true, false) as VBoxContainer
	var sell_cat := _shop_panel.find_child("SellCatalog", true, false) as VBoxContainer
	var sell_cart := _shop_panel.find_child("SellCart", true, false) as VBoxContainer
	_clear_container(buy_cat)
	_clear_container(buy_cart)
	_clear_container(sell_cat)
	_clear_container(sell_cart)
	# Buy catalog
	if buy_cat != null:
		if _shop_listings.is_empty():
			_add_label(buy_cat, "（无商品）", 12, Color(0.6, 0.6, 0.65))
		else:
			for it in _shop_listings:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid := str(it.get("item_id", ""))
				var iname := str(it.get("name", iid))
				var price: int = int(it.get("buy_price", 0))
				_add_shop_catalog_row(buy_cat, iname, price, true, iid, iname, price)
	# Buy cart
	_fill_cart_list(buy_cart, _shop_buy_cart, true)
	# Sell catalog from bag
	if sell_cat != null:
		var sellables: Array = _shop_sellable_bag_rows()
		if sellables.is_empty():
			_add_label(sell_cat, "（无可出售物品）", 12, Color(0.6, 0.6, 0.65))
		else:
			for it2 in sellables:
				var iid2 := str(it2.get("id", ""))
				var iname2 := str(it2.get("name", iid2))
				var sprice: int = int(it2.get("sell_price", 0))
				var have_q: int = int(it2.get("qty", 1))
				_add_shop_catalog_row(sell_cat, "%s×%d" % [iname2, have_q], sprice, false, iid2, iname2, sprice)
	_fill_cart_list(sell_cart, _shop_sell_cart, false)


func _clear_container(node: Node) -> void:
	if node == null:
		return
	while node.get_child_count() > 0:
		var c: Node = node.get_child(0)
		node.remove_child(c)
		c.free()


func _add_shop_catalog_row(parent: VBoxContainer, label_text: String, price: int, is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lab := Label.new()
	lab.text = "%s  %dG" % [label_text, price]
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_font_size_override("font_size", 12)
	lab.mouse_filter = Control.MOUSE_FILTER_STOP
	lab.tooltip_text = "点击加入选择"
	row.add_child(lab)
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.custom_minimum_size = Vector2(28, 24)
	add_btn.pressed.connect(_on_shop_catalog_add.bind(is_buy, item_id, display_name, unit_price))
	row.add_child(add_btn)
	# Whole row click also adds
	lab.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_on_shop_catalog_add(is_buy, item_id, display_name, unit_price)
	)


func _fill_cart_list(parent: VBoxContainer, cart: Array, is_buy: bool) -> void:
	if parent == null:
		return
	if cart.is_empty():
		_add_label(parent, "（未选择）", 12, Color(0.55, 0.55, 0.6))
		return
	var total := 0
	for line in cart:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid := str(line.get("item_id", ""))
		var q: int = int(line.get("qty", 1))
		var up: int = int(line.get("unit_price", 0))
		var nm := str(line.get("name", iid))
		var line_gold: int = up * q
		total += line_gold
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		parent.add_child(row)
		var lab := Label.new()
		lab.text = "%s ×%d  %dG" % [nm, q, line_gold]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 12)
		lab.tooltip_text = "点击移除"
		lab.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lab)
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.custom_minimum_size = Vector2(28, 24)
		minus.pressed.connect(_on_shop_cart_adjust.bind(is_buy, iid, -1))
		row.add_child(minus)
		lab.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					_on_shop_cart_remove(is_buy, iid)
		)
	_add_label(parent, "合计：%dG" % total, 12, Color(0.95, 0.88, 0.45))


func _on_shop_catalog_add(is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var cart: Array = _shop_buy_cart if is_buy else _shop_sell_cart
	# Cap sell qty by bag amount
	if not is_buy:
		var have := 0
		for it in _server_inventory:
			if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == item_id:
				have = int(it.get("qty", 0))
				break
		var cur := 0
		for line in cart:
			if typeof(line) == TYPE_DICTIONARY and str(line.get("item_id", "")) == item_id:
				cur = int(line.get("qty", 0))
				break
		if cur >= have:
			append_system("选择数量已达背包上限。")
			return
	var found := false
	for i in range(cart.size()):
		var line: Dictionary = cart[i]
		if str(line.get("item_id", "")) == item_id:
			line["qty"] = int(line.get("qty", 0)) + 1
			cart[i] = line
			found = true
			break
	if not found:
		cart.append({"item_id": item_id, "qty": 1, "unit_price": unit_price, "name": display_name})
	_fill_shop_panel()


func _on_shop_cart_adjust(is_buy: bool, item_id: String, delta: int) -> void:
	item_id = item_id.strip_edges()
	var cart: Array = _shop_buy_cart if is_buy else _shop_sell_cart
	for i in range(cart.size()):
		var line: Dictionary = cart[i]
		if str(line.get("item_id", "")) != item_id:
			continue
		var q: int = int(line.get("qty", 0)) + delta
		if q <= 0:
			cart.remove_at(i)
		else:
			line["qty"] = q
			cart[i] = line
		break
	_fill_shop_panel()


func _on_shop_cart_remove(is_buy: bool, item_id: String) -> void:
	item_id = item_id.strip_edges()
	var cart: Array = _shop_buy_cart if is_buy else _shop_sell_cart
	for i in range(cart.size() - 1, -1, -1):
		if typeof(cart[i]) == TYPE_DICTIONARY and str(cart[i].get("item_id", "")) == item_id:
			cart.remove_at(i)
	_fill_shop_panel()


func _on_shop_confirm() -> void:
	if _shop_panel == null:
		return
	var tabs := _shop_panel.get_meta("tabs") as TabContainer
	var idx := 0
	if tabs != null:
		idx = tabs.current_tab
	if idx == 0:
		_confirm_buy_cart()
	else:
		_confirm_sell_cart()


func _confirm_buy_cart() -> void:
	if _shop_id.is_empty():
		return
	if _shop_buy_cart.is_empty():
		append_system("请先选择要购买的物品。")
		return
	if _world_combat == null or not _world_combat.has_method("request_shop_buy"):
		append_system("无法购买。")
		return
	var lines: Array = _shop_buy_cart.duplicate(true)
	_shop_buy_cart.clear()
	_fill_shop_panel()
	for line in lines:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid := str(line.get("item_id", ""))
		var q: int = maxi(int(line.get("qty", 1)), 1)
		if iid.is_empty():
			continue
		# Server system_message reports gold/bag/stack failures per line.
		_world_combat.request_shop_buy(_shop_id, iid, q)


func _confirm_sell_cart() -> void:
	if _shop_sell_cart.is_empty():
		append_system("请先选择要出售的物品。")
		return
	if _world_combat == null or not _world_combat.has_method("request_shop_sell"):
		append_system("无法出售。")
		return
	var lines: Array = _shop_sell_cart.duplicate(true)
	_shop_sell_cart.clear()
	_fill_shop_panel()
	for line in lines:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid := str(line.get("item_id", ""))
		var q: int = maxi(int(line.get("qty", 1)), 1)
		if iid.is_empty():
			continue
		_world_combat.request_shop_sell(iid, q)


func _shop_sellable_bag_rows() -> Array:
	var out: Array = []
	var cat = null
	var srv = Net.server()
	if srv != null:
		cat = srv.get("item_catalog")
	for it in _server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("id", "")).strip_edges()
		var qty: int = int(it.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		var sell_price := 0
		var iname := iid
		if cat != null and cat.has_method("get_item"):
			var def: Dictionary = cat.get_item(iid)
			if not def.is_empty():
				sell_price = maxi(int(def.get("sell_price", 0)), 0)
				iname = str(def.get("name", iid))
		if sell_price <= 0:
			continue
		out.append({"id": iid, "qty": qty, "name": iname, "sell_price": sell_price})
	return out


func _on_shop_buy(item_id: String) -> void:
	## Legacy single-buy (kept for compatibility); prefer cart + confirm.
	if _shop_id.is_empty() or item_id.strip_edges().is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_shop_buy"):
		_world_combat.request_shop_buy(_shop_id, item_id, 1)


func _on_shop_sell(item_id: String) -> void:
	## Legacy single-sell (kept for compatibility); prefer cart + confirm.
	if item_id.strip_edges().is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_shop_sell"):
		_world_combat.request_shop_sell(item_id, 1)


func apply_skill_catalog(skills: Array) -> void:
	_server_skills = skills.duplicate(true)
	if _windows.has("skills") and _windows["skills"].visible:
		_refresh_window_contents()


func apply_quest_snapshot(quests: Array) -> void:
	_server_quests = quests.duplicate(true)
	# Drop selection if quest no longer in journal.
	if not _selected_quest_id.is_empty():
		var still := false
		for q in _server_quests:
			if typeof(q) == TYPE_DICTIONARY and str(q.get("id", "")) == _selected_quest_id:
				still = true
				break
		if not still:
			_selected_quest_id = ""
			_close_quest_drawer(false)
	if _windows.has("quest") and _windows["quest"].visible:
		_refresh_window_contents()
		_refresh_quest_drawer_content()




func _iter_skill_cells(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c == null:
			continue
		if c.has_method("set_cooldown") and c.has_method("tick_cooldown"):
			out.append(c)
	return out


func _skill_window_grid() -> Node:
	if not _windows.has("skills"):
		return null
	var panel: PanelContainer = _windows["skills"]
	if panel == null or not is_instance_valid(panel):
		return null
	return panel.find_child("SkillGrid", true, false)


func _tick_skill_cell_cooldowns(host: Node, delta: float) -> void:
	for cell in _iter_skill_cells(host):
		cell.tick_cooldown(delta)


func _tick_skill_window_cooldowns(delta: float) -> void:
	_tick_skill_cell_cooldowns(_skill_window_grid(), delta)


func _cell_bound_id(cell: Node) -> String:
	if cell == null:
		return ""
	if "bound_id" in cell:
		return str(cell.bound_id).strip_edges()
	if "skill_id" in cell:
		return str(cell.skill_id).strip_edges()
	return ""


func _apply_cooldown_to_container(host: Node, id: String, remaining: float, total: float) -> void:
	if host == null or id.is_empty():
		return
	for cell in _iter_skill_cells(host):
		if _cell_bound_id(cell) != id:
			continue
		cell.set_cooldown(remaining, total)


func _apply_cooldown_to_skill_window(id: String, remaining: float, total: float) -> void:
	_apply_cooldown_to_container(_skill_window_grid(), id, remaining, total)


func _apply_cast_to_container(host: Node, frac: float) -> void:
	if host == null:
		return
	for cell in _iter_skill_cells(host):
		if not cell.has_method("set_cast_progress"):
			continue
		var bid := _cell_bound_id(cell)
		if frac >= 0.0 and bid == _cast_skill_id and not bid.is_empty():
			cell.set_cast_progress(frac)
		else:
			cell.set_cast_progress(-1.0)


func _apply_cast_to_skill_window(frac: float) -> void:
	_apply_cast_to_container(_skill_window_grid(), frac)


func _refresh_skill_window_cooldowns() -> void:
	var grid := _skill_window_grid()
	if grid == null:
		return
	for cell in _iter_skill_cells(grid):
		var bid := _cell_bound_id(cell)
		if bid.is_empty():
			if cell.has_method("clear_cooldown"):
				cell.clear_cooldown()
			continue
		var row: Variant = _skill_cd_hint.get(bid, {})
		if typeof(row) == TYPE_DICTIONARY and float(row.get("remaining", 0.0)) > 0.0:
			cell.set_cooldown(float(row.get("remaining", 0.0)), float(row.get("cooldown", 0.0)))
		elif cell.has_method("clear_cooldown"):
			cell.clear_cooldown()
	_sync_skill_cast_overlays()


func _tick_hotbar_cooldowns(delta: float) -> void:
	var dead: Array = []
	for sid in _skill_cd_hint.keys():
		var row: Variant = _skill_cd_hint[sid]
		if typeof(row) != TYPE_DICTIONARY:
			dead.append(sid)
			continue
		var rem: float = maxf(float(row.get("remaining", 0.0)) - delta, 0.0)
		row["remaining"] = rem
		_skill_cd_hint[sid] = row
		if rem <= 0.0:
			dead.append(sid)
	for sid2 in dead:
		_skill_cd_hint.erase(sid2)
	_tick_skill_cell_cooldowns(hotbar, delta)
	_tick_skill_window_cooldowns(delta)


func _apply_hotbar_cooldown_for_id(id: String, remaining: float, total: float) -> void:
	if id.is_empty():
		return
	_apply_cooldown_to_container(hotbar, id, remaining, total)
	_apply_cooldown_to_skill_window(id, remaining, total)


func _apply_slot_cooldown_visual(btn: Button, _kind: String, id: String) -> void:
	if btn == null or not btn.has_method("set_cooldown"):
		return
	if id.is_empty():
		if btn.has_method("clear_cooldown"):
			btn.clear_cooldown()
		else:
			btn.set_cooldown(0.0, 0.0)
		return
	var row: Variant = _skill_cd_hint.get(id, {})
	if typeof(row) == TYPE_DICTIONARY and float(row.get("remaining", 0.0)) > 0.0:
		var rem: float = float(row.get("remaining", 0.0))
		var tot: float = float(row.get("cooldown", rem))
		btn.set_cooldown(rem, tot)
	else:
		if btn.has_method("clear_cooldown"):
			btn.clear_cooldown()
		else:
			btn.set_cooldown(0.0, 0.0)


func _sync_hotbar_cast_overlays() -> void:
	_sync_skill_cast_overlays()


func _sync_skill_cast_overlays() -> void:
	var frac: float = -1.0
	if _cast_active and _cast_duration > 0.0 and not _cast_skill_id.is_empty():
		frac = clampf(_cast_elapsed / _cast_duration, 0.0, 1.0)
	_apply_cast_to_container(hotbar, frac)
	_apply_cast_to_skill_window(frac)


func note_skill_cooldown(skill_id: String, remaining: float, cooldown: float = 0.0) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	var total: float = cooldown
	if total <= 0.0:
		total = remaining
	_skill_cd_hint[skill_id] = {"remaining": remaining, "cooldown": total}
	_apply_hotbar_cooldown_for_id(skill_id, remaining, total)
	if _windows.has("skills") and _windows["skills"].visible:
		_refresh_window_contents()

func hotbar_prev() -> void:
	_hotbar_page = (_hotbar_page + HOTBAR_PAGES.size() - 1) % HOTBAR_PAGES.size()
	_build_hotbar()
	_persist_hotbar_to_session()

func hotbar_next() -> void:
	_hotbar_page = (_hotbar_page + 1) % HOTBAR_PAGES.size()
	_build_hotbar()
	_persist_hotbar_to_session()

func _build_menu() -> void:
	for c in menu_row.get_children():
		c.queue_free()
	var items := [
		["角色", "character"],
		["背包", "inventory"],
		["技能", "skills"],
		["任务", "quest"],
		["队伍", "party"],
		["地图", "map"],
		["系统", "system"],
	]
	for item in items:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(58, 32)
		btn.text = str(item[0])
		btn.focus_mode = Control.FOCUS_NONE
		var wid := str(item[1])
		if wid == "party":
			btn.pressed.connect(_toggle_party_panel)
		else:
			btn.pressed.connect(_toggle_window.bind(wid))
		menu_row.add_child(btn)

func _build_windows() -> void:
	_windows["character"] = _make_window("角色状态", Vector2(480, 360), "top_left", Vector2(200, 120))
	_lock_character_window(_windows["character"] as PanelContainer)
	_windows["inventory"] = _make_window("背包", Vector2(420, 500), "top_right", Vector2(200, 40))
	_lock_inventory_window(_windows["inventory"] as PanelContainer)
	_windows["skills"] = _make_window("技能与魔法", Vector2(280, 400), "top_center", Vector2(0, 100))
	_lock_skills_window(_windows["skills"] as PanelContainer)
	_windows["quest"] = _make_window("任务", Vector2(360, 400), "bottom_right", Vector2(40, 80))
	_lock_quest_window(_windows["quest"] as PanelContainer)
	_windows["map"] = _make_window("地图", Vector2(460, 580), "top_center", Vector2(0, 36))
	_windows["system"] = _make_window("系统菜单", Vector2(300, 280), "bottom_center", Vector2(0, 100))
	var map_panel: PanelContainer = _windows.get("map")
	if map_panel:
		map_panel.min_size = Vector2(300, 280)
		map_panel.custom_minimum_size = Vector2(300, 280)
	for id in _windows.keys():
		(_windows[id] as Control).visible = false

func _make_window(title: String, size: Vector2, dock: String, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.screen_margin = 4.0
	panel.min_size = Vector2(240, 180)
	panel.default_size = size
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(240, 180)
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.text = title
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(func(): panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)
	panel.set_meta("body", body)
	panel.set_meta("title", title)
	panel.set_meta("dock_hint", dock)
	panel.set_meta("pos_offset", offset)
	panel.set_meta("base_size", size)
	return panel

func _lock_inventory_window(panel: PanelContainer) -> void:
	## Fixed-size bag: no HudDrag edge resize; size locked to base.
	## Gold footer sits below Scroll (outside scroll body).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(420, 500))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_ensure_inventory_gold_bar(panel)


func _lock_character_window(panel: PanelContainer) -> void:
	## Fixed-size character / paperdoll window (dark L2-like panel, not parchment).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(480, 360))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	sb.border_color = Color(0.62, 0.52, 0.30, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", sb)


func _ensure_inventory_gold_bar(panel: PanelContainer) -> void:
	if panel == null:
		return
	var existing: Label = panel.get_meta("gold_label", null) if panel.has_meta("gold_label") else null
	if existing != null and is_instance_valid(existing):
		_refresh_inventory_gold_label(panel)
		return
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var row := HBoxContainer.new()
	row.name = "GoldBar"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Label.new()
	tag.text = "金币"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color(0.92, 0.78, 0.38, 1.0))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var amt := Label.new()
	amt.name = "GoldAmount"
	amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_theme_font_size_override("font_size", 14)
	amt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45, 1.0))
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(amt)
	vbox.add_child(row)
	panel.set_meta("gold_label", amt)
	_refresh_inventory_gold_label(panel)


func _refresh_inventory_gold_label(panel: PanelContainer = null) -> void:
	if panel == null:
		panel = _windows.get("inventory") as PanelContainer
	if panel == null:
		return
	var lbl: Label = panel.get_meta("gold_label", null) if panel.has_meta("gold_label") else null
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = str(maxi(_server_gold, 0))


func _lock_skills_window(panel: PanelContainer) -> void:
	## Fixed-size skills: same lock as bag; tab bar sits above Scroll (not inside body).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(280, 400))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var tabs := vbox.get_node_or_null("SkillsTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "SkillsTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("skills_tabs", tabs)
	_rebuild_skills_tab_bar(panel)


func _lock_quest_window(panel: PanelContainer) -> void:
	## Fixed-size quest list window; tabs above Scroll; drawer is a separate HUD sibling.
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(360, 400))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	# Restore list Scroll (previous pass hid it for internal HBox split).
	scroll.visible = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Remove legacy internal QuestHost split if present.
	var legacy := vbox.get_node_or_null("QuestHost")
	if legacy != null:
		vbox.remove_child(legacy)
		legacy.free()
	if panel.has_meta("quest_host"):
		panel.remove_meta("quest_host")
	var tabs := vbox.get_node_or_null("QuestTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "QuestTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("quest_tabs", tabs)
	_rebuild_quest_tab_bar(panel)
	if not panel.visibility_changed.is_connected(_on_quest_window_visibility):
		panel.visibility_changed.connect(_on_quest_window_visibility)
	_ensure_quest_drawer()


func _rebuild_quest_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("quest_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in QUEST_TABS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(88, 26)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var tid := str(item[1])
		btn.pressed.connect(_on_quest_tab.bind(tid))
		tabs.add_child(btn)
	_highlight_quest_tabs(tabs)


func _on_quest_tab(tab_id: String) -> void:
	tab_id = tab_id.strip_edges()
	if tab_id.is_empty():
		return
	_quest_tab = tab_id
	# Drop selection if it no longer matches the active tab filter.
	if not _selected_quest_id.is_empty():
		var keep := false
		for q in _server_quests:
			if typeof(q) != TYPE_DICTIONARY:
				continue
			if str(q.get("id", "")) != _selected_quest_id:
				continue
			if _quest_status_matches_tab(str(q.get("status", ""))):
				keep = true
			break
		if not keep:
			_selected_quest_id = ""
			_close_quest_drawer(false)
	if _windows.has("quest"):
		var panel: PanelContainer = _windows["quest"]
		_highlight_quest_tabs(panel.get_meta("quest_tabs", null) as HBoxContainer)
		if panel.visible:
			_fill_window("quest")


func _highlight_quest_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn := tabs.get_child(i) as Button
		if btn == null or i >= QUEST_TABS.size():
			continue
		var id := str(QUEST_TABS[i][1])
		var on := id == _quest_tab
		btn.modulate = Color(1.2, 1.1, 0.75) if on else Color(0.85, 0.85, 0.9)


func _on_quest_window_visibility() -> void:
	var panel: PanelContainer = _windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		_selected_quest_id = ""
		_close_quest_drawer(false)


func _rebuild_skills_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("skills_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in SKILL_TABS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(72, 26)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var cat := str(item[1])
		btn.pressed.connect(_on_skills_tab.bind(cat))
		tabs.add_child(btn)
	_highlight_skills_tabs(tabs)


func _on_skills_tab(cat: String) -> void:
	cat = cat.strip_edges()
	if cat.is_empty():
		return
	_skills_tab = cat
	if _windows.has("skills"):
		var panel: PanelContainer = _windows["skills"]
		_highlight_skills_tabs(panel.get_meta("skills_tabs", null) as HBoxContainer)
		if panel.visible:
			_fill_window("skills")


func _highlight_skills_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn := tabs.get_child(i) as Button
		if btn == null or i >= SKILL_TABS.size():
			continue
		var id := str(SKILL_TABS[i][1])
		var on := id == _skills_tab
		btn.modulate = Color(1.15, 1.05, 0.75) if on else Color(0.85, 0.85, 0.9)


func _grid_cell_size() -> Vector2:
	## Same pixel size as hotbar slots.
	return Vector2(GRID_CELL, GRID_CELL)


func _grid_cols_for(panel: PanelContainer) -> int:
	## How many GRID_CELL columns fit the fixed window width (scroll for extra rows).
	var base: Vector2 = panel.get_meta("base_size", Vector2(420, 500)) if panel else Vector2(420, 460)
	var win_w: float = panel.size.x if panel and panel.size.x >= 64.0 else base.x
	const MARGIN_X := 20.0
	var inner := maxf(float(GRID_CELL), win_w - MARGIN_X)
	var cols := int(floor((inner + float(GRID_SEP)) / (float(GRID_CELL) + float(GRID_SEP))))
	return maxi(1, cols)


func _place_window(panel: PanelContainer) -> void:
	var vp := get_viewport().get_visible_rect().size
	var dock := str(panel.get_meta("dock_hint", "top_left"))
	var off: Vector2 = panel.get_meta("pos_offset", Vector2.ZERO)
	var base: Vector2 = panel.get_meta("base_size", panel.default_size)
	if panel.size.x < 64.0 or panel.size.y < 64.0 or panel.size.y > vp.y - 8.0:
		panel.size = base
	var s := panel.size
	var pos := Vector2(8, 8)
	match dock:
		"top_right":
			pos = Vector2(vp.x - s.x - 8, 8) + Vector2(-off.x, off.y)
		"top_center":
			pos = Vector2((vp.x - s.x) * 0.5, 8) + off
		"bottom_right":
			pos = Vector2(vp.x - s.x - 8, vp.y - s.y - 8) - off
		"bottom_center":
			pos = Vector2((vp.x - s.x) * 0.5, vp.y - s.y - 90) - Vector2(0, off.y)
		_:
			pos = Vector2(8, 150) + off
	panel.global_position = pos

func _toggle_window(id: String) -> void:
	if not _windows.has(id):
		return
	var panel: PanelContainer = _windows[id]
	panel.visible = not panel.visible
	if panel.visible:
		var base: Vector2 = panel.get_meta("base_size", panel.default_size)
		panel.size = base
		_fill_window(id)
		call_deferred("_lock_window_size", panel)
		call_deferred("_place_window", panel)
		panel.move_to_front()

func _lock_window_size(panel: PanelContainer) -> void:
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", panel.default_size)
	if bool(panel.get_meta("fixed_size", false)):
		panel.size = base
		panel.custom_minimum_size = base
		if "min_size" in panel:
			panel.min_size = base
		return
	var vp := get_viewport().get_visible_rect().size
	if panel.size.y > base.y + 8.0 or panel.size.y > vp.y * 0.85:
		panel.size = base

func _close_top_window() -> bool:
	# NPC Chat first, then shop, then highest visible floating window
	if _npc_chat != null and _npc_chat.visible:
		_npc_chat.visible = false
		return true
	if _shop_panel != null and _shop_panel.visible:
		hide_shop()
		return true
	if _party_panel != null and _party_panel.visible:
		_party_panel.visible = false
		return true
	var order := ["system", "map", "quest", "skills", "inventory", "character"]
	for id in order:
		var p: PanelContainer = _windows.get(id)
		if p and p.visible:
			p.visible = false
			return true
	return false

func _refresh_window_contents() -> void:
	for id in _windows.keys():
		var p: PanelContainer = _windows[id]
		if p.visible:
			_fill_window(str(id))

func _fill_window(id: String) -> void:
	var panel: PanelContainer = _windows[id]
	var body: VBoxContainer = panel.get_meta("body")
	for c in body.get_children():
		c.queue_free()
	var ch := _character
	if ch.is_empty():
		ch = Net.session().active_character()
	match id:
		"character":
			_fill_character(body, ch)
		"inventory":
			_fill_inventory(body, ch)
		"skills":
			_fill_skills(body, ch)
		"quest":
			_fill_quest(body, ch)
		"map":
			_fill_map(body, ch)
		"system":
			_fill_system(body)

func _add_label(parent: Node, text: String, size: int = 12, color: Color = Color(0.9, 0.9, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _fill_character(body: VBoxContainer, ch: Dictionary) -> void:
	_sync_equipment_cache()
	var st: Dictionary = L2Mock.char_stats(ch)
	var bon: Dictionary = _server_equip_bonuses
	var show_lv: int = int(_server_combat.get("level", ch.get("level", 1)))
	_add_label(body, "%s · %s · Lv.%d" % [str(ch.get("name", "?")), str(st.get("class_label", "")), show_lv], 14, Color(0.95, 0.92, 0.82))
	var main := HBoxContainer.new()
	main.name = "CharMain"
	main.add_theme_constant_override("separation", 10)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	# LEFT: opaque doll panel with compact 3-col grid (L2-like).
	var doll_panel := PanelContainer.new()
	doll_panel.name = "DollPanel"
	doll_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	doll_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	doll_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var doll_sb := StyleBoxFlat.new()
	doll_sb.bg_color = Color(0.08, 0.08, 0.10, 0.98)
	doll_sb.border_color = Color(0.55, 0.48, 0.32, 0.9)
	doll_sb.set_border_width_all(1)
	doll_sb.set_corner_radius_all(4)
	doll_sb.content_margin_left = 8
	doll_sb.content_margin_right = 8
	doll_sb.content_margin_top = 8
	doll_sb.content_margin_bottom = 8
	doll_panel.add_theme_stylebox_override("panel", doll_sb)
	main.add_child(doll_panel)
	var doll_vbox := VBoxContainer.new()
	doll_vbox.name = "DollVBox"
	doll_vbox.add_theme_constant_override("separation", 6)
	doll_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doll_panel.add_child(doll_vbox)
	_build_paperdoll(doll_vbox, ch)
	# RIGHT: readable stats on dark (window panel already dark).
	var stats := VBoxContainer.new()
	stats.name = "StatsCol"
	stats.add_theme_constant_override("separation", 3)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(stats)
	var light := Color(0.92, 0.92, 0.94)
	var muted := Color(0.72, 0.72, 0.78)
	var exp_cur: int = int(_server_combat.get("exp", st.get("exp", 0)))
	var exp_next: int = int(_server_combat.get("exp_to_next", 0))
	if exp_next > 0:
		_add_label(stats, "EXP %d / %d · SP %d" % [exp_cur, exp_next, int(st.get("sp", 0))], 12, light)
	else:
		_add_label(stats, "EXP %d · SP %d" % [exp_cur, int(st.get("sp", 0))], 12, light)
	var adena_v: int = maxi(_server_gold, 0) if _server_gold >= 0 else int(st.get("adena", 0))
	_add_label(stats, "Adena %d · 血盟：%s" % [adena_v, str(st.get("clan", "无"))], 12, light)
	_add_label(stats, "—— 属性 ——", 12, muted)
	_add_label(stats, "STR %d   DEX %d   CON %d" % [int(st.get("str", 0)), int(st.get("dex", 0)), int(st.get("con", 0))], 12, light)
	_add_label(stats, "INT %d   WIT %d   MEN %d" % [int(st.get("int", 0)), int(st.get("wit", 0)), int(st.get("men", 0))], 12, light)
	_add_label(stats, "—— 战斗 ——", 12, muted)
	var base_patk := int(_server_combat.get("atk", st.get("p_atk", 0)))
	var base_pdef := int(_server_combat.get("def", st.get("p_def", 0)))
	var p_atk := base_patk + int(bon.get("p_atk", 0))
	var m_atk := int(st.get("m_atk", 0)) + int(bon.get("m_atk", 0))
	var p_def := base_pdef + int(bon.get("p_def", 0))
	var m_def := int(st.get("m_def", 0)) + int(bon.get("m_def", 0))
	_add_label(stats, "P.Atk %d   M.Atk %d" % [p_atk, m_atk], 12, light)
	_add_label(stats, "P.Def %d   M.Def %d" % [p_def, m_def], 12, light)
	_add_label(stats, "CP/HP/MP  %d / %d / %d" % [int(_cp_max), int(_hp_max), int(_mp_max)], 12, light)
	if not bon.is_empty():
		_add_label(stats, "—— 装备加成 ——", 12, muted)
		var parts: Array[String] = []
		for k in bon.keys():
			var v: int = int(bon[k])
			if v != 0:
				parts.append("%s%+d" % [str(k), v])
		if parts.is_empty():
			_add_label(stats, "无", 12, Color(0.55, 0.55, 0.6))
		else:
			var line := ""
			for i in range(parts.size()):
				if i > 0:
					line += "  "
				line += parts[i]
			_add_label(stats, line, 12, Color(0.92, 0.82, 0.42))
	var panel: PanelContainer = _windows.get("character") as PanelContainer
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)


func _sync_equipment_cache() -> void:
	## Refresh from MockServer when opening / rebuilding character window.
	var srv = Net.server()
	if srv != null and srv.get("equipment") != null and srv.equipment.has_method("snapshot"):
		_server_equipment = srv.equipment.snapshot()
		if srv.equipment.has_method("total_bonuses"):
			_server_equip_bonuses = srv.equipment.total_bonuses()


func _equipment_map() -> Dictionary:
	## slot_id -> {item_id, name}
	var m: Dictionary = {}
	for it in _server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var sid := str(it.get("slot", "")).strip_edges()
		if sid.is_empty():
			continue
		m[sid] = {
			"item_id": str(it.get("item_id", "")).strip_edges(),
			"name": str(it.get("name", "")).strip_edges(),
		}
	return m


func _build_paperdoll(host: Control, _ch: Dictionary) -> void:
	## Compact L2-like 3-column GridContainer inside opaque DollPanel (no absolute float).
	const CELL := 42
	const SEP := 5
	# Row layout maps all existing SLOT_IDS (no invented cloak/belt):
	#   耳L | 头 | 耳R
	#   手  | 胸 | 主手
	#   项链| 腿 | 副手
	#   戒L | 脚 | 戒R
	var grid_order: Array[String] = [
		"earring_l", "head", "earring_r",
		"hands", "chest", "weapon_main",
		"necklace", "legs", "weapon_off",
		"ring_l", "feet", "ring_r",
	]
	var grid := GridContainer.new()
	grid.name = "DollGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", SEP)
	grid.add_theme_constant_override("v_separation", SEP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(grid)
	var eq_map := _equipment_map()
	for sid in grid_order:
		var cell := PanelContainer.new()
		cell.set_script(EquipSlot)
		cell.custom_minimum_size = Vector2(CELL, CELL)
		var entry: Dictionary = eq_map.get(sid, {})
		var iid := str(entry.get("item_id", "")).strip_edges()
		var nm := str(entry.get("name", "")).strip_edges()
		if nm.is_empty() and not iid.is_empty():
			nm = _item_label(iid)
		var hint := Equipment.label_zh(sid)
		var iix := _item_icon_index(iid) if not iid.is_empty() else -1
		var iref := _item_icon_ref(iid) if not iid.is_empty() else ""
		if not iid.is_empty() and entry.has("icon_index"):
			iix = int(entry.get("icon_index", iix))
		if not iid.is_empty():
			var er := str(entry.get("icon_ref", "")).strip_edges()
			if er.is_empty():
				er = str(entry.get("icon", "")).strip_edges()
				if not er.is_empty() and not er.begins_with("content:"):
					er = "content://icon/%s" % er
			if not er.is_empty():
				iref = er
		cell.setup(sid, iid, nm, hint, iix, iref)
		cell.equip_requested.connect(_on_equip_slot_equip)
		cell.unequip_requested.connect(_on_equip_slot_unequip)
		grid.add_child(cell)
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP


func _ensure_ground_drop_zone() -> void:
	if _ground_drop_zone != null and is_instance_valid(_ground_drop_zone):
		return
	var z := preload("res://scripts/ui/ground_drop_zone.gd").new()
	z.name = "GroundDropZone"
	add_child(z)
	move_child(z, 0)
	z.ground_drop_item.connect(_on_inventory_item_drop)
	z.ground_drop_equipped.connect(_on_equip_slot_drop)
	_ground_drop_zone = z


func _tick_ground_drop_zone() -> void:
	## Arm full-screen drop sink only while dragging bag/equip items (not window/skill drags).
	var want := false
	if get_viewport().gui_is_dragging():
		var data = get_viewport().gui_get_drag_data()
		if typeof(data) == TYPE_DICTIONARY:
			var kind := str(data.get("kind", ""))
			want = kind == "item" or kind == "equipped"
	if want == _ground_drop_armed:
		return
	_ground_drop_armed = want
	_ensure_ground_drop_zone()
	if _ground_drop_zone != null and _ground_drop_zone.has_method("set_active"):
		_ground_drop_zone.set_active(want)


func _on_equip_slot_equip(item_id: String, slot_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_equip_item"):
		_world_combat.request_equip_item(item_id, slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_equip_item"):
			var result: Dictionary = srv.try_equip_item(item_id, slot_id)
			_apply_equip_result_locally(result)
		else:
			append_system("无法装备：%s" % item_id)


func _on_equip_slot_unequip(slot_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_unequip_item"):
		_world_combat.request_unequip_item(slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_unequip_item"):
			var result: Dictionary = srv.try_unequip_item(slot_id)
			_apply_equip_result_locally(result)
		else:
			append_system("无法卸下：%s" % slot_id)


func _on_equip_slot_drop(slot_id: String) -> void:
	## Drag equipped item onto world GroundDropZone.
	if _world_combat != null and _world_combat.has_method("request_drop_equipped"):
		_world_combat.request_drop_equipped(slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_drop_equipped"):
			var result: Dictionary = srv.try_drop_equipped(slot_id)
			_apply_equip_result_locally(result)
		else:
			append_system("无法丢弃装备：%s" % slot_id)


func _apply_equip_result_locally(result: Dictionary) -> void:
	## Fallback when world bridge missing: apply action opcodes from try_* result.
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"equipment_update":
				var eq_v: Variant = action.get("equipment", [])
				var eq: Array = eq_v if typeof(eq_v) == TYPE_ARRAY else []
				var bon_v: Variant = action.get("bonuses", {})
				var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
				apply_equipment_snapshot(eq, bons)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)


func _item_label(item_id: String) -> String:
	var srv = Net.server()
	if srv != null and srv.has_method("item_display_name"):
		return str(srv.item_display_name(item_id))
	return item_id


func _item_icon_index(item_id: String) -> int:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return -1
	for it in _server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id and it.has("icon_index"):
			return int(it.get("icon_index", -1))
	for it in _server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")) == item_id and it.has("icon_index"):
			return int(it.get("icon_index", -1))
	var srv = Net.server()
	if srv != null and srv.get("item_catalog") != null:
		var cat = srv.item_catalog
		if cat != null and cat.has_method("icon_index_of"):
			return int(cat.icon_index_of(item_id))
		if cat != null and cat.has_method("get_item"):
			return int(cat.get_item(item_id).get("icon_index", -1))
	return -1


func _item_icon_ref(item_id: String) -> String:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return ""
	for it in _server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id:
			var r := str(it.get("icon_ref", "")).strip_edges()
			if not r.is_empty():
				return r
			var ic := str(it.get("icon", "")).strip_edges()
			if not ic.is_empty():
				return "content://icon/%s" % ic
	for it in _server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")) == item_id:
			var r2 := str(it.get("icon_ref", "")).strip_edges()
			if not r2.is_empty():
				return r2
			var ic2 := str(it.get("icon", "")).strip_edges()
			if not ic2.is_empty():
				return "content://icon/%s" % ic2
	var srv = Net.server()
	if srv != null and srv.get("item_catalog") != null:
		var cat = srv.item_catalog
		if cat != null and cat.has_method("icon_ref_of"):
			return str(cat.icon_ref_of(item_id))
		if cat != null and cat.has_method("get_item"):
			var def: Dictionary = cat.get_item(item_id)
			var r3 := str(def.get("icon_ref", "")).strip_edges()
			if not r3.is_empty():
				return r3
			var ic3 := str(def.get("icon", "")).strip_edges()
			if not ic3.is_empty():
				return "content://icon/%s" % ic3
	return ""


func _skill_icon_index(skill_id: String) -> int:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return -1
	for s in _server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			return int(s.get("icon_index", -1))
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("icon_index_of"):
			return int(cat.icon_index_of(skill_id))
		if cat != null and cat.has_method("get_skill"):
			return int(cat.get_skill(skill_id).get("icon_index", -1))
	return -1


func _skill_icon_ref(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return ""
	for s in _server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			var r := str(s.get("icon_ref", "")).strip_edges()
			if not r.is_empty():
				return r
			var ic := str(s.get("icon", "")).strip_edges()
			if not ic.is_empty():
				return "content://icon/%s" % ic
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("icon_ref_of"):
			return str(cat.icon_ref_of(skill_id))
		if cat != null and cat.has_method("get_skill"):
			var def: Dictionary = cat.get_skill(skill_id)
			var r2 := str(def.get("icon_ref", "")).strip_edges()
			if not r2.is_empty():
				return r2
			var ic2 := str(def.get("icon", "")).strip_edges()
			if not ic2.is_empty():
				return "content://icon/%s" % ic2
	return ""


func _fill_inventory(body: VBoxContainer, _ch: Dictionary) -> void:
	## ScrollContainer fills window body; grid alone (no chrome labels). Rows > viewport → scrollbar.
	var panel: PanelContainer = _windows.get("inventory") as PanelContainer
	var items: Array = _server_inventory
	if items.is_empty():
		var srv0 = Net.server()
		if srv0 != null and srv0.get("inventory") != null and srv0.inventory.has_method("snapshot"):
			items = srv0.inventory.snapshot()
			_server_inventory = items.duplicate(true)
	var cell_sz := _grid_cell_size()
	var cols := _grid_cols_for(panel)
	var ui_slots := cols * INV_ROWS
	# Soft capacity from server Inventory.max_slots (default MAX_SLOTS=40).
	var capacity := 40
	var srv = Net.server()
	if srv != null and srv.get("inventory") != null:
		capacity = maxi(int(srv.inventory.max_slots), 1)
	# Body is only the grid so ScrollContainer chrome is just title + scroll viewport.
	body.add_theme_constant_override("separation", 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.name = "InvGrid"
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", GRID_SEP)
	grid.add_theme_constant_override("v_separation", GRID_SEP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(grid)
	# Pack occupied stacks into first capacity cells; beyond capacity = disabled gray.
	var packed: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var q: int = int(it.get("qty", 0))
		if q <= 0:
			continue
		packed.append(it)
	for i in range(ui_slots):
		var cell := PanelContainer.new()
		cell.set_script(InvSlot)
		cell.custom_minimum_size = cell_sz
		if i >= capacity:
			cell.clear_slot()
			cell.set_disabled(true)
		elif i < packed.size():
			var it2: Dictionary = packed[i]
			var iid := str(it2.get("id", ""))
			var qty: int = int(it2.get("qty", 0))
			cell.set_disabled(false)
			cell.setup(iid, qty, _item_label(iid), i, _item_icon_index(iid), _item_icon_ref(iid))
			if not cell.activated.is_connected(_on_inventory_item_pressed):
				cell.activated.connect(_on_inventory_item_pressed)
		else:
			cell.set_disabled(false)
			cell.clear_slot()
		# Re-assert after script _ready may run on add_child.
		cell.custom_minimum_size = cell_sz
		grid.add_child(cell)
		cell.custom_minimum_size = cell_sz
		# Force STOP so HudDraggable pass-through never swallows InvSlot clicks.
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
	# Keep fixed window size even after content rebuild.
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)
	# Sync wallet from MockServer when opening bag (authoritative).
	if srv != null and srv.get("inventory") != null and srv.inventory.has_method("get_gold"):
		_server_gold = int(srv.inventory.get_gold())
	_ensure_inventory_gold_bar(panel)
	_refresh_inventory_gold_label(panel)


func _on_inventory_item_drop(item_id: String) -> void:
	## Drag bag item onto world → if stack>1 ask qty (default 1), else drop 1.
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var have: int = _inventory_qty(item_id)
	if have <= 0:
		# Snapshot may lag; still attempt drop 1.
		have = 1
	if have > 1:
		_show_drop_qty_dialog(item_id, have)
		return
	_commit_drop_item(item_id, 1)


func _commit_drop_item(item_id: String, qty: int) -> void:
	qty = maxi(qty, 1)
	if _world_combat != null and _world_combat.has_method("request_drop_item"):
		_world_combat.request_drop_item(item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_drop_item"):
			var result: Dictionary = srv.try_drop_item(item_id, qty)
			_apply_equip_result_locally(result)
		else:
			append_system("无法丢弃：%s" % item_id)


func _ensure_ground_tip() -> void:
	if _ground_tip != null and is_instance_valid(_ground_tip):
		return
	var tip := PanelContainer.new()
	tip.name = "GroundItemTip"
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 80
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	sb.border_color = Color(0.55, 0.5, 0.35, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	tip.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.name = "Text"
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	tip.add_child(lab)
	add_child(tip)
	_ground_tip = tip
	_ground_tip_label = lab


func show_ground_tip(text: String, screen_pos: Vector2) -> void:
	_ensure_ground_tip()
	if _ground_tip == null or _ground_tip_label == null:
		return
	_ground_tip_label.text = text.strip_edges()
	_ground_tip.visible = not _ground_tip_label.text.is_empty()
	move_ground_tip(screen_pos)


func move_ground_tip(screen_pos: Vector2) -> void:
	if _ground_tip == null or not _ground_tip.visible:
		return
	# Offset so tip does not sit under the cursor.
	var pos := screen_pos + Vector2(16, 18)
	var vp := get_viewport_rect().size
	var sz := _ground_tip.get_combined_minimum_size()
	if _ground_tip.size.x > 1.0:
		sz = _ground_tip.size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	_ground_tip.position = pos


func hide_ground_tip() -> void:
	if _ground_tip != null:
		_ground_tip.visible = false


func _show_drop_qty_dialog(item_id: String, max_qty: int) -> void:
	_ensure_drop_qty_dialog()
	_drop_qty_item_id = item_id
	max_qty = maxi(max_qty, 1)
	if _drop_qty_label != null:
		_drop_qty_label.text = "丢掉：%s（最多 %d）" % [_item_label(item_id), max_qty]
	if _drop_qty_spin != null:
		_drop_qty_spin.min_value = 1
		_drop_qty_spin.max_value = max_qty
		_drop_qty_spin.value = 1
	if _drop_qty_panel != null:
		_drop_qty_panel.visible = true
		_drop_qty_panel.reset_size()
		var vp := get_viewport_rect().size
		var sz := _drop_qty_panel.get_combined_minimum_size()
		if _drop_qty_panel.size.x > 1.0:
			sz = _drop_qty_panel.size
		_drop_qty_panel.position = Vector2(
			(vp.x - sz.x) * 0.5,
			(vp.y - sz.y) * 0.5
		)
		var parent := _drop_qty_panel.get_parent()
		if parent != null:
			parent.move_child(_drop_qty_panel, parent.get_child_count() - 1)


func _ensure_drop_qty_dialog() -> void:
	if _drop_qty_panel != null and is_instance_valid(_drop_qty_panel):
		return
	var panel := PanelContainer.new()
	panel.name = "DropQtyDialog"
	panel.visible = false
	panel.z_index = 90
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.12, 0.96)
	sb.border_color = Color(0.7, 0.55, 0.25, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var title := Label.new()
	title.text = "丢弃数量"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
	root.add_child(title)
	var info := Label.new()
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(220, 0)
	root.add_child(info)
	_drop_qty_label = info
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var qty_lab := Label.new()
	qty_lab.text = "数量"
	row.add_child(qty_lab)
	var spin := SpinBox.new()
	spin.name = "Qty"
	spin.min_value = 1
	spin.max_value = 99
	spin.value = 1
	spin.rounded = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	_drop_qty_spin = spin
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btns)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_on_drop_qty_cancel)
	btns.add_child(cancel)
	var ok := Button.new()
	ok.text = "确定"
	ok.pressed.connect(_on_drop_qty_confirm)
	btns.add_child(ok)
	panel.custom_minimum_size = Vector2(280, 0)
	add_child(panel)
	_drop_qty_panel = panel


func _on_drop_qty_cancel() -> void:
	_drop_qty_item_id = ""
	if _drop_qty_panel != null:
		_drop_qty_panel.visible = false


func _on_drop_qty_confirm() -> void:
	var iid := _drop_qty_item_id.strip_edges()
	var q: int = 1
	if _drop_qty_spin != null:
		q = int(_drop_qty_spin.value)
	_on_drop_qty_cancel()
	if iid.is_empty():
		return
	var have: int = _inventory_qty(iid)
	if have > 0:
		q = clampi(q, 1, have)
	else:
		q = maxi(q, 1)
	_commit_drop_item(iid, q)



func _on_inventory_item_pressed(item_id: String) -> void:
	## Double-click from InvSlot: equipment toggles via MockServer.try_use_item → try_toggle_equip;
	## consumables use as before.
	if _world_combat != null and _world_combat.has_method("request_use_item"):
		_world_combat.request_use_item(item_id)
	else:
		append_system("无法使用：%s" % item_id)


func _skill_display_name(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	for s in _server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			var n := str(s.get("name", "")).strip_edges()
			return n if not n.is_empty() else skill_id
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("get_skill"):
			var def: Dictionary = cat.get_skill(skill_id)
			var n2 := str(def.get("name", "")).strip_edges()
			if not n2.is_empty():
				return n2
	return skill_id


func _skill_category(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	for s in _server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			return _normalize_skill_category(s)
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("get_skill"):
			return _normalize_skill_category(cat.get_skill(skill_id))
	return "physical"


func _normalize_skill_category(def: Dictionary) -> String:
	if def.is_empty():
		return "physical"
	var cat := str(def.get("category", "")).strip_edges()
	if cat == "physical" or cat == "magic" or cat == "passive":
		return cat
	var eff := str(def.get("effect", ""))
	if eff.begins_with("passive"):
		return "passive"
	if eff == "heal":
		return "magic"
	return "physical"


func _is_passive_skill(skill_id: String) -> bool:
	return _skill_category(skill_id) == "passive"


func _fill_skills(body: VBoxContainer, _ch: Dictionary) -> void:
	## Grid + tabs (tabs live outside Scroll). No chrome helper labels.
	var panel: PanelContainer = _windows.get("skills") as PanelContainer
	if panel != null:
		_rebuild_skills_tab_bar(panel)
	var skills: Array = _server_skills
	if skills.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_skill_catalog"):
			skills = srv.snapshot_skill_catalog()
			_server_skills = skills.duplicate(true)
	var filtered: Array = []
	for s in skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if _normalize_skill_category(s) == _skills_tab:
			filtered.append(s)
	var cell_sz := _grid_cell_size()
	var cols := SKILL_COLS
	body.add_theme_constant_override("separation", 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if filtered.is_empty():
		var empty := Label.new()
		empty.text = "（暂无技能）"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1.0))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(empty)
	else:
		var grid := GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", GRID_SEP)
		grid.add_theme_constant_override("v_separation", GRID_SEP)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.mouse_filter = Control.MOUSE_FILTER_STOP
		body.add_child(grid)
		# Only real skills — no empty filler columns/rows.
		for i in range(filtered.size()):
			var cell := PanelContainer.new()
			cell.set_script(SkillSlot)
			cell.custom_minimum_size = cell_sz
			var sdef: Dictionary = filtered[i]
			var sid := str(sdef.get("id", ""))
			var sname := str(sdef.get("name", sid))
			var cat := _normalize_skill_category(sdef)
			var six := int(sdef.get("icon_index", _skill_icon_index(sid)))
			var sref := str(sdef.get("icon_ref", "")).strip_edges()
			if sref.is_empty():
				var sic := str(sdef.get("icon", "")).strip_edges()
				if not sic.is_empty():
					sref = "content://icon/%s" % sic
				else:
					sref = _skill_icon_ref(sid)
			cell.setup(sid, sname, cat, i, six, sref)
			cell.activated.connect(_on_skill_slot_pressed)
			cell.custom_minimum_size = cell_sz
			grid.add_child(cell)
			cell.custom_minimum_size = cell_sz
		_refresh_skill_window_cooldowns()
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)


func _on_skill_slot_pressed(skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	if _is_passive_skill(skill_id):
		# Stub toggle + message; never try_use_skill for passives.
		var on := not bool(_passive_toggles.get(skill_id, false))
		_passive_toggles[skill_id] = on
		var sname := _skill_display_name(skill_id)
		if on:
			append_system("被动，无需施放 · 【%s】（已标记启用，效果占位）" % sname)
		else:
			append_system("被动，无需施放 · 【%s】（已取消标记）" % sname)
		return
	if _world_combat != null and _world_combat.has_method("request_use_skill"):
		_world_combat.request_use_skill(skill_id)
	else:
		append_system("无法施放：%s" % skill_id)


func _on_skill_row_pressed(skill_id: String) -> void:
	## Compat alias for older call sites.
	_on_skill_slot_pressed(skill_id)

func _fill_quest(body: VBoxContainer, _ch: Dictionary) -> void:
	## List-only quest window (tabs filter); detail lives in external side drawer.
	var panel: PanelContainer = _windows.get("quest") as PanelContainer
	if panel != null:
		if not panel.has_meta("quest_tabs"):
			_lock_quest_window(panel)
		else:
			_rebuild_quest_tab_bar(panel)
	body.custom_minimum_size = Vector2.ZERO
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var quests: Array = _server_quests
	if quests.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("get_quest_list"):
			quests = srv.get_quest_list()
			_server_quests = quests.duplicate(true)
	var filtered: Array = []
	for q in quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if _quest_status_matches_tab(str(q.get("status", ""))):
			filtered.append(q)
	# Validate selection against filtered list.
	if not _selected_quest_id.is_empty():
		var still := false
		for q in filtered:
			if str(q.get("id", "")) == _selected_quest_id:
				still = true
				break
		if not still:
			_selected_quest_id = ""
			_close_quest_drawer(false)
	if filtered.is_empty():
		var empty_msg := "（暂无已完成任务）" if _quest_tab == "completed" else "（暂无进行中任务）"
		_add_label(body, empty_msg, 12, Color(0.65, 0.65, 0.7))
	else:
		for q in filtered:
			body.add_child(_make_quest_row(q, str(q.get("id", "")) == _selected_quest_id))
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)
	# Soft drawer sync: refresh content if open; do not cancel in-flight slide tweens.
	_soft_sync_quest_drawer()


func _soft_sync_quest_drawer() -> void:
	if _selected_quest_id.is_empty():
		return
	if _quest_drawer != null and is_instance_valid(_quest_drawer) and _quest_drawer.visible:
		_refresh_quest_drawer_content()
		_place_quest_drawer()


func _quest_status_matches_tab(status: String) -> bool:
	var st := _normalize_quest_status(status)
	if _quest_tab == "completed":
		return st == "completed"
	# 正在进行: in_progress / ready (and legacy active aliases)
	return st in ["in_progress", "ready"]


func _normalize_quest_status(status: String) -> String:
	match status.strip_edges():
		"completed", "complete":
			return "completed"
		"ready", "deliverable":
			return "ready"
		"active", "in_progress", "progress":
			return "in_progress"
		_:
			return "in_progress"


func _make_quest_row(q: Dictionary, selected: bool) -> Button:
	var qid := str(q.get("id", "")).strip_edges()
	var title := str(q.get("title", qid if not qid.is_empty() else "?"))
	var st := _quest_status_label(str(q.get("status", "in_progress")))
	var btn := Button.new()
	btn.text = "%s    [%s]" % [title, st]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.modulate = Color(1.15, 1.05, 0.75) if selected else Color(0.92, 0.92, 0.95)
	if not qid.is_empty():
		btn.pressed.connect(_on_quest_row_selected.bind(qid))
	return btn


func _quest_status_label(status: String) -> String:
	match _normalize_quest_status(status):
		"ready":
			return "可交付"
		"completed":
			return "已完成"
		_:
			return "进行中"


func _on_quest_row_selected(quest_id: String) -> void:
	_abandon_confirm_id = ""
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if _selected_quest_id == quest_id:
		# Toggle off → slide drawer away; list stays.
		_selected_quest_id = ""
		if _windows.has("quest") and _windows["quest"].visible:
			_fill_window("quest")
		_close_quest_drawer(true)
		return
	_selected_quest_id = quest_id
	if _windows.has("quest") and _windows["quest"].visible:
		_fill_window("quest")
	_open_quest_drawer(quest_id, true)


func _on_quest_drawer_close() -> void:
	_selected_quest_id = ""
	_close_quest_drawer(true)
	if _windows.has("quest") and _windows["quest"].visible:
		_fill_window("quest")


func _ensure_quest_drawer() -> void:
	if _quest_drawer != null and is_instance_valid(_quest_drawer):
		return
	var drawer := PanelContainer.new()
	drawer.name = "QuestDrawer"
	drawer.visible = false
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.clip_contents = true
	drawer.custom_minimum_size = Vector2(0, 0)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.07, 0.07, 0.11, 0.92)
	dsb.set_border_width_all(1)
	dsb.border_color = Color(0.55, 0.45, 0.28, 0.75)
	dsb.set_content_margin_all(8)
	drawer.add_theme_stylebox_override("panel", dsb)
	add_child(drawer)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 8)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 8)
	marg.add_theme_constant_override("margin_bottom", 6)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.name = "DrawerTitle"
	title_l.text = "详情"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_on_quest_drawer_close)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.name = "DrawerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var dbody := VBoxContainer.new()
	dbody.name = "DrawerBody"
	dbody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbody.add_theme_constant_override("separation", 6)
	dbody.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(dbody)
	_quest_drawer = drawer
	_quest_drawer_body = dbody


func _quest_by_id(quest_id: String) -> Dictionary:
	for q in _server_quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if str(q.get("id", "")) == quest_id:
			return q
	return {}


func _place_quest_drawer() -> void:
	if _quest_drawer == null or not is_instance_valid(_quest_drawer):
		return
	var panel: PanelContainer = _windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		return
	# Sibling of quest window: attach to its right edge, same top.
	_quest_drawer.global_position = Vector2(
		panel.global_position.x + panel.size.x,
		panel.global_position.y
	)
	var h: float = panel.size.y
	if _quest_drawer.size.y != h:
		_quest_drawer.size.y = h
	_quest_drawer.move_to_front()


func _sync_quest_drawer_follow() -> void:
	if _quest_drawer == null or not is_instance_valid(_quest_drawer):
		return
	if not _quest_drawer.visible:
		return
	var panel: PanelContainer = _windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		_close_quest_drawer(false)
		return
	_place_quest_drawer()


func _open_quest_drawer(quest_id: String, animate: bool) -> void:
	_ensure_quest_drawer()
	var selected: Dictionary = _quest_by_id(quest_id)
	if selected.is_empty():
		_close_quest_drawer(false)
		return
	_refresh_quest_drawer_content()
	var panel: PanelContainer = _windows.get("quest") as PanelContainer
	var h: float = panel.size.y if panel != null else 400.0
	var was_open := _quest_drawer.visible and _quest_drawer.size.x > 1.0
	_quest_drawer.visible = true
	_place_quest_drawer()
	if _quest_drawer_tween != null and is_instance_valid(_quest_drawer_tween):
		_quest_drawer_tween.kill()
		_quest_drawer_tween = null
	# Animate only when sliding out from collapsed; switching rows keeps width.
	if animate and not was_open:
		_quest_drawer.size = Vector2(0, h)
		_quest_drawer.modulate = Color(1, 1, 1, 0.35)
		_quest_drawer_tween = create_tween()
		_quest_drawer_tween.set_parallel(true)
		_quest_drawer_tween.tween_property(_quest_drawer, "size:x", QUEST_DRAWER_WIDTH, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_quest_drawer_tween.tween_property(_quest_drawer, "modulate:a", 1.0, 0.14)
	else:
		_quest_drawer.size = Vector2(QUEST_DRAWER_WIDTH, h)
		_quest_drawer.modulate = Color(1, 1, 1, 1)


func _close_quest_drawer(animate: bool) -> void:
	if _quest_drawer == null or not is_instance_valid(_quest_drawer):
		return
	if not _quest_drawer.visible and (_quest_drawer_tween == null or not is_instance_valid(_quest_drawer_tween)):
		return
	if _quest_drawer_tween != null and is_instance_valid(_quest_drawer_tween):
		_quest_drawer_tween.kill()
		_quest_drawer_tween = null
	if animate and _quest_drawer.visible and _quest_drawer.size.x > 1.0:
		var tw := create_tween()
		_quest_drawer_tween = tw
		tw.set_parallel(true)
		tw.tween_property(_quest_drawer, "size:x", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(_quest_drawer, "modulate:a", 0.0, 0.12)
		tw.chain().tween_callback(_finish_quest_drawer_close)
	else:
		_finish_quest_drawer_close()


func _finish_quest_drawer_close() -> void:
	if _quest_drawer != null and is_instance_valid(_quest_drawer):
		_quest_drawer.visible = false
		_quest_drawer.size.x = 0
		_quest_drawer.modulate = Color(1, 1, 1, 1)
	_quest_drawer_tween = null


func _refresh_quest_drawer_content() -> void:
	_ensure_quest_drawer()
	if _quest_drawer_body == null or not is_instance_valid(_quest_drawer_body):
		return
	while _quest_drawer_body.get_child_count() > 0:
		var c: Node = _quest_drawer_body.get_child(0)
		_quest_drawer_body.remove_child(c)
		c.free()
	if _selected_quest_id.is_empty():
		return
	var selected: Dictionary = _quest_by_id(_selected_quest_id)
	if selected.is_empty():
		return
	var title_l := _quest_drawer.find_child("DrawerTitle", true, false) as Label
	if title_l != null:
		title_l.text = str(selected.get("title", "?"))
	_add_label(_quest_drawer_body, _quest_status_label(str(selected.get("status", "in_progress"))), 12, Color(0.75, 0.85, 0.7))
	var desc := str(selected.get("desc", "")).strip_edges()
	if not desc.is_empty():
		_add_label(_quest_drawer_body, desc, 12, Color(0.88, 0.88, 0.9))
	_add_label(_quest_drawer_body, "目标", 12, Color(0.7, 0.7, 0.75))
	var objs_v: Variant = selected.get("objectives", [])
	if typeof(objs_v) == TYPE_ARRAY and not (objs_v as Array).is_empty():
		for o in objs_v:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var ot := str(o.get("text", ""))
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			var done := cur >= mx
			var col := Color(0.55, 0.85, 0.55) if done else Color(0.9, 0.9, 0.92)
			_add_label(_quest_drawer_body, "· %s（%d / %d）" % [ot, cur, mx], 12, col)
	else:
		_add_label(_quest_drawer_body, "· （无）", 12, Color(0.6, 0.6, 0.65))
	var rewards := str(selected.get("rewards", "")).strip_edges()
	_add_label(_quest_drawer_body, "奖励", 12, Color(0.7, 0.7, 0.75))
	_add_label(_quest_drawer_body, rewards if not rewards.is_empty() else "（无）", 12, Color(0.92, 0.82, 0.55))
	var qstatus := _normalize_quest_status(str(selected.get("status", "")))
	if qstatus == "ready":
		var turn_btn := Button.new()
		turn_btn.text = "交付任务"
		turn_btn.focus_mode = Control.FOCUS_NONE
		turn_btn.custom_minimum_size = Vector2(120, 28)
		turn_btn.pressed.connect(_on_quest_turn_in.bind(_selected_quest_id))
		_quest_drawer_body.add_child(turn_btn)
	elif qstatus == "completed":
		_add_label(_quest_drawer_body, "（已完成）", 12, Color(0.55, 0.75, 0.55))
	if qstatus == "in_progress" or qstatus == "ready":
		var ab_btn := Button.new()
		ab_btn.text = "确认放弃" if _abandon_confirm_id == _selected_quest_id else "放弃任务"
		ab_btn.focus_mode = Control.FOCUS_NONE
		ab_btn.custom_minimum_size = Vector2(120, 28)
		ab_btn.pressed.connect(_on_quest_abandon.bind(_selected_quest_id))
		_quest_drawer_body.add_child(ab_btn)


func _on_quest_turn_in(quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_turn_in_quest"):
		_world_combat.request_turn_in_quest(quest_id)


func _on_quest_abandon(quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if _abandon_confirm_id != quest_id:
		_abandon_confirm_id = quest_id
		append_system("再点一次以确认放弃任务。")
		_refresh_quest_drawer_content()
		return
	_abandon_confirm_id = ""
	if _world_combat != null and _world_combat.has_method("request_abandon_quest"):
		_world_combat.request_abandon_quest(quest_id)


func _fill_map(body: VBoxContainer, ch: Dictionary) -> void:
	var spawn: Dictionary = Net.session().spawn_data
	var map_id := _radar_map_id
	if map_id.is_empty():
		map_id = str(spawn.get("map_id", "demo_map"))

	var panel: PanelContainer = _windows.get("map")
	# Keep map panel min at base — never raise it to the enlarged size.
	const MAP_MIN := Vector2(300, 280)
	if panel:
		panel.min_size = MAP_MIN
		panel.custom_minimum_size = MAP_MIN
		panel.clip_contents = true

	# Bypass ScrollContainer for map: its child custom_minimum_size=avail caused
	# grow-only resize. Use an expand-fill MapSlot in the outer vbox instead.
	var scroll: ScrollContainer = null
	var outer: VBoxContainer = null
	if panel:
		scroll = panel.find_child("Scroll", true, false) as ScrollContainer
		if scroll:
			outer = scroll.get_parent() as VBoxContainer
			scroll.visible = false
			scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			scroll.custom_minimum_size = Vector2.ZERO

	var mount: VBoxContainer = body
	if outer != null:
		var slot := outer.get_node_or_null("MapSlot") as VBoxContainer
		if slot == null:
			slot = VBoxContainer.new()
			slot.name = "MapSlot"
			outer.add_child(slot)
		else:
			# Immediate free so reopen does not stack duplicate hosts before queue_free runs.
			while slot.get_child_count() > 0:
				var c: Node = slot.get_child(0)
				slot.remove_child(c)
				c.free()
		slot.visible = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2.ZERO
		slot.add_theme_constant_override("separation", 4)
		slot.clip_contents = true
		mount = slot
		# Keep scroll body empty so it does not inflate minimum size.
		body.custom_minimum_size = Vector2.ZERO
		body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_map_info_label = _add_label(mount, "", 13, Color(0.92, 0.88, 0.65))
	_add_label(mount, "角色：%s" % str(ch.get("name", "?")), 12)

	var host := Control.new()
	host.name = "MapHost"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.custom_minimum_size = Vector2.ZERO
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.clip_contents = true
	mount.add_child(host)

	var overview := Control.new()
	overview.set_script(MapOverview)
	overview.name = "MapOverview"
	overview.mouse_filter = Control.MOUSE_FILTER_STOP
	overview.custom_minimum_size = Vector2.ZERO
	overview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(overview)
	if overview.has_method("bind"):
		overview.bind(_radar_map_field, _radar_player, map_id)
	_map_overview = overview
	_refresh_map_window_info()
	call_deferred("_sync_map_overview_layout", panel, mount, host)
	if panel and not panel.resized.is_connected(_on_map_panel_resized):
		panel.resized.connect(_on_map_panel_resized)


func _on_map_panel_resized() -> void:
	var panel: PanelContainer = _windows.get("map")
	if panel == null or not panel.visible:
		return
	var mount: Control = null
	var outer_marg := panel.get_child(0) if panel.get_child_count() > 0 else null
	var outer_vbox: VBoxContainer = null
	if outer_marg is MarginContainer and outer_marg.get_child_count() > 0:
		outer_vbox = outer_marg.get_child(0) as VBoxContainer
	if outer_vbox:
		mount = outer_vbox.get_node_or_null("MapSlot") as Control
	if mount == null:
		mount = panel.get_meta("body", null) as Control
	if mount == null:
		return
	var host := mount.get_node_or_null("MapHost") as Control
	if host == null:
		return
	_sync_map_overview_layout(panel, mount, host)


func _sync_map_overview_layout(panel: PanelContainer, mount: Control, host: Control) -> void:
	if panel == null or mount == null or host == null:
		return
	if not is_instance_valid(panel) or not is_instance_valid(mount) or not is_instance_valid(host):
		return
	# Never raise custom_minimum_size to current avail — that locks grow-only resize.
	host.custom_minimum_size = Vector2.ZERO
	host.clip_contents = true
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _map_overview != null and is_instance_valid(_map_overview):
		_map_overview.custom_minimum_size = Vector2.ZERO
		_map_overview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_map_overview.queue_redraw()
	# Keep panel floor at intended base min (HudDrag.min_size), not enlarged content.
	const MAP_MIN := Vector2(300, 280)
	if panel.min_size != MAP_MIN:
		panel.min_size = MAP_MIN
	if panel.custom_minimum_size != MAP_MIN:
		panel.custom_minimum_size = MAP_MIN


func _refresh_map_window_info() -> void:
	var panel: PanelContainer = _windows.get("map")
	if panel == null or not panel.visible:
		return
	if _map_info_label == null or not is_instance_valid(_map_info_label):
		return
	if _map_overview != null and is_instance_valid(_map_overview) and _map_overview.has_method("hint_line"):
		_map_info_label.text = "当前地图：%s" % str(_map_overview.hint_line())
		return
	var map_id := _radar_map_id
	if map_id.is_empty():
		map_id = str(Net.session().spawn_data.get("map_id", "demo_map"))
	var cell := Vector2i.ZERO
	if _radar_player != null and "cell" in _radar_player:
		cell = _radar_player.cell
	elif _radar_map_field != null and _radar_player != null and _radar_map_field.has_method("world_to_cell"):
		cell = _radar_map_field.world_to_cell(_radar_player.global_position)
	_map_info_label.text = "当前地图：%s  (%d, %d)" % [map_id, cell.x, cell.y]


func _fill_system(body: VBoxContainer) -> void:
	_add_label(body, "系统选项（占位）", 14)
	var mk := func(text: String, cb: Callable) -> void:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(cb)
		body.add_child(b)
	mk.call("内容编辑器", func(): Net.session().go_content_editor())
	if bool(Net.session().get("editor_return")):
		mk.call("返回编辑器", func(): Net.session().go_content_editor())
	mk.call("返回角色选择", func(): Net.session().go_character_select())
	mk.call("返回登录", func(): Net.session().go_login())
	mk.call("关闭所有窗口", func():
		for id in _windows.keys():
			(_windows[id] as Control).visible = false
		hide_npc_dialogue()
		hide_loot()
	)

func _build_party_stub() -> void:
	## Live party shell panel (debug stubs via MockServer try_party_*).
	_party_panel = PanelContainer.new()
	_party_panel.name = "PartyPanel"
	_party_panel.set_script(HudDrag)
	_party_panel.screen_margin = 4.0
	_party_panel.min_size = Vector2(160, 80)
	_party_panel.default_size = Vector2(240, 280)
	_party_panel.initial_dock = "top_left"
	_party_panel.drag_anywhere = true
	add_child(_party_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 8)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 8)
	marg.add_theme_constant_override("margin_bottom", 6)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_child(outer)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(head)
	var title := Label.new()
	title.text = "队伍"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 22)
	close_btn.pressed.connect(func(): _party_panel.visible = false)
	head.add_child(close_btn)
	_party_body = VBoxContainer.new()
	_party_body.name = "PartyBody"
	_party_body.add_theme_constant_override("separation", 4)
	_party_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_party_body)
	_party_panel.visible = false
	_refresh_party_panel()
	call_deferred("_nudge_party")


func _nudge_party() -> void:
	if _party_panel:
		_party_panel.global_position = Vector2(8, 160)


func _toggle_party_panel() -> void:
	if _party_panel == null:
		return
	_party_panel.visible = not _party_panel.visible
	if _party_panel.visible:
		_refresh_party_panel()
		_party_panel.move_to_front()
		call_deferred("_nudge_party")


func _party_in_party() -> bool:
	var pid := str(_party_state.get("party_id", "")).strip_edges()
	var mem_v: Variant = _party_state.get("members", [])
	if pid.is_empty():
		return false
	return typeof(mem_v) == TYPE_ARRAY and not (mem_v as Array).is_empty()


func apply_party_update(action: Dictionary) -> void:
	## From World action dispatch / local try_* fallback.
	var party_v: Variant = action.get("party", action)
	if typeof(party_v) != TYPE_DICTIONARY:
		return
	var party: Dictionary = party_v
	_party_state = {
		"party_id": str(party.get("party_id", "")),
		"leader": str(party.get("leader", "")),
		"members": [],
		"shared_target_id": str(party.get("shared_target_id", "")),
		"shared_target_name": str(party.get("shared_target_name", "")),
	}
	var mem_v: Variant = party.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for m in mem_v:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = m
			cleaned.append({
				"id": str(md.get("id", "")),
				"name": str(md.get("name", "?")),
				"hp": int(md.get("hp", 0)),
				"hp_max": maxi(int(md.get("hp_max", 1)), 1),
				"online": bool(md.get("online", true)),
			})
		_party_state["members"] = cleaned
	_refresh_party_panel()
	_sync_radar_party_stubs()


func _sync_radar_party_stubs() -> void:
	if _radar == null:
		return
	var others := 0
	var mem_v: Variant = _party_state.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		others = maxi((mem_v as Array).size() - 1, 0)
	if "show_party_stubs" in _radar:
		_radar.show_party_stubs = others > 0
	if _radar.has_method("set_party_angles"):
		var angles: Array = []
		for i in range(mini(others, 4)):
			angles.append(2.0 + float(i) * 1.1)
		_radar.set_party_angles(angles)
	elif "_party_angles" in _radar:
		var angles2: Array = []
		for i2 in range(mini(others, 4)):
			angles2.append(2.0 + float(i2) * 1.1)
		if angles2.is_empty():
			angles2 = [2.1, 4.0]
		_radar._party_angles = angles2
		_radar.queue_redraw()


func _refresh_party_panel() -> void:
	if _party_body == null:
		return
	for c in _party_body.get_children():
		c.queue_free()
	var self_id := _party_self_id_for_ui()
	var leader := str(_party_state.get("leader", ""))
	if not _party_in_party():
		_add_label(_party_body, "（未组队）", 11, Color(0.6, 0.6, 0.65))
		var create_btn := Button.new()
		create_btn.text = "创建队伍"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.custom_minimum_size = Vector2(0, 26)
		create_btn.pressed.connect(_on_party_create)
		_party_body.add_child(create_btn)
		var fill_btn := Button.new()
		fill_btn.text = "创建调试队伍"
		fill_btn.focus_mode = Control.FOCUS_NONE
		fill_btn.custom_minimum_size = Vector2(0, 26)
		fill_btn.pressed.connect(_on_party_debug_fill)
		_party_body.add_child(fill_btn)
		var remote_btn0 := Button.new()
		remote_btn0.text = "生成假玩家"
		remote_btn0.focus_mode = Control.FOCUS_NONE
		remote_btn0.custom_minimum_size = Vector2(0, 26)
		remote_btn0.pressed.connect(_on_remote_debug_spawn)
		_party_body.add_child(remote_btn0)
		return
	# Shared assist target
	var st_name := str(_party_state.get("shared_target_name", "")).strip_edges()
	var st_id := str(_party_state.get("shared_target_id", "")).strip_edges()
	if not st_id.is_empty() or not st_name.is_empty():
		var tip := "目标：%s" % (st_name if not st_name.is_empty() else st_id)
		var st_row := HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 4)
		_party_body.add_child(st_row)
		var stl := Label.new()
		stl.text = tip
		stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stl.add_theme_font_size_override("font_size", 11)
		stl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
		stl.autowrap_mode = TextServer.AUTOWRAP_OFF
		st_row.add_child(stl)
		var clr := Button.new()
		clr.text = "清除"
		clr.focus_mode = Control.FOCUS_NONE
		clr.custom_minimum_size = Vector2(40, 22)
		clr.pressed.connect(_on_party_clear_shared_target)
		st_row.add_child(clr)
	else:
		_add_label(_party_body, "目标：（无）· 点选怪物同步", 10, Color(0.55, 0.55, 0.6))
	var mem_v: Variant = _party_state.get("members", [])
	var members: Array = mem_v if typeof(mem_v) == TYPE_ARRAY else []
	for m in members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var mid := str(md.get("id", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		_party_body.add_child(row)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 4)
		row.add_child(name_row)
		var nm := str(md.get("name", "?"))
		if mid == leader:
			nm = "★" + nm
		if mid == self_id:
			nm += "（我）"
		if not bool(md.get("online", true)):
			nm += "（离线）"
		var nl := Label.new()
		nl.text = nm
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(nl)
		if mid != self_id and leader == self_id:
			var kick := Button.new()
			kick.text = "踢"
			kick.focus_mode = Control.FOCUS_NONE
			kick.custom_minimum_size = Vector2(28, 20)
			kick.pressed.connect(_on_party_kick.bind(mid))
			name_row.add_child(kick)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = float(maxi(int(md.get("hp_max", 1)), 1))
		bar.value = float(clampi(int(md.get("hp", 0)), 0, int(bar.max_value)))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_status_bar(bar, Color(0.35, 0.75, 0.4, 1.0))
		row.add_child(bar)
		var hp_lab := Label.new()
		hp_lab.text = "%d/%d" % [int(md.get("hp", 0)), int(md.get("hp_max", 1))]
		hp_lab.add_theme_font_size_override("font_size", 9)
		hp_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
		hp_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hp_lab)
	# Invite row
	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 4)
	_party_body.add_child(inv_row)
	var inv_edit := LineEdit.new()
	inv_edit.name = "PartyInviteEdit"
	inv_edit.placeholder_text = "右键玩家，或输入名字"
	inv_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_edit.custom_minimum_size = Vector2(0, 24)
	inv_row.add_child(inv_edit)
	var inv_btn := Button.new()
	inv_btn.text = "邀请"
	inv_btn.focus_mode = Control.FOCUS_NONE
	inv_btn.disabled = leader != self_id
	inv_btn.pressed.connect(func():
		var name := inv_edit.text.strip_edges()
		_on_party_invite(name)
	)
	inv_row.add_child(inv_btn)
	var leave_btn := Button.new()
	leave_btn.text = "离开队伍"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(0, 26)
	leave_btn.pressed.connect(_on_party_leave)
	_party_body.add_child(leave_btn)
	var remote_btn := Button.new()
	remote_btn.text = "生成假玩家"
	remote_btn.focus_mode = Control.FOCUS_NONE
	remote_btn.custom_minimum_size = Vector2(0, 26)
	remote_btn.pressed.connect(_on_remote_debug_spawn)
	_party_body.add_child(remote_btn)


func _party_self_id_for_ui() -> String:
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		return str(srv._party_self_id())
	return "player"


func _on_party_create() -> void:
	if _world_combat != null and _world_combat.has_method("request_party_create"):
		_world_combat.request_party_create()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_create"):
		_apply_party_result_locally(srv.try_party_create())
	else:
		append_system("无法创建队伍。")


func _on_party_invite(target: String = "") -> void:
	if _world_combat != null and _world_combat.has_method("request_party_invite"):
		_world_combat.request_party_invite(target)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_invite"):
		_apply_party_result_locally(srv.try_party_invite(target))
	else:
		append_system("无法邀请。")


func _on_party_kick(member_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_party_kick"):
		_world_combat.request_party_kick(member_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_kick"):
		_apply_party_result_locally(srv.try_party_kick(member_id))
	else:
		append_system("无法踢出。")


func _on_party_clear_shared_target() -> void:
	if _world_combat != null and _world_combat.has_method("request_party_clear_target"):
		_world_combat.request_party_clear_target()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_clear_target"):
		_apply_party_result_locally(srv.try_party_clear_target())


func _on_party_debug_fill() -> void:
	if _world_combat != null and _world_combat.has_method("request_party_debug_fill"):
		_world_combat.request_party_debug_fill()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_debug_fill"):
		var result: Dictionary = srv.try_party_debug_fill()
		_apply_party_result_locally(result)
	else:
		append_system("无法创建调试队伍。")


func _on_party_leave() -> void:
	if _world_combat != null and _world_combat.has_method("request_party_leave"):
		_world_combat.request_party_leave()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_leave"):
		var result: Dictionary = srv.try_party_leave()
		_apply_party_result_locally(result)
	else:
		append_system("无法离开队伍。")


func _apply_party_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"party_update":
				apply_party_update(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)

func on_hotbar_prev_pressed() -> void:
	hotbar_prev()

func on_hotbar_next_pressed() -> void:
	hotbar_next()


func _build_player_context_menu() -> void:
	if _player_ctx_menu != null and is_instance_valid(_player_ctx_menu):
		return
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	_player_ctx_menu = PopupMenu.new()
	_player_ctx_menu.name = "PlayerContextMenu"
	_player_ctx_menu.add_theme_font_size_override("font_size", 13)
	add_child(_player_ctx_menu)
	_player_ctx_menu.id_pressed.connect(_on_player_context_id)


func ensure_player_context_menu() -> PopupMenu:
	_build_player_context_menu()
	return _player_ctx_menu


func close_player_context_menu() -> void:
	if _player_ctx_menu != null and is_instance_valid(_player_ctx_menu) and _player_ctx_menu.visible:
		_player_ctx_menu.hide()


func open_player_context_menu(player_id: String, display_name: String, screen_pos: Vector2) -> void:
	_build_player_context_menu()
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	player_id = str(player_id).strip_edges()
	display_name = str(display_name).strip_edges()
	if display_name.is_empty():
		display_name = player_id if not player_id.is_empty() else "玩家"
	_player_ctx_target_id = player_id
	_player_ctx_target_name = display_name
	_player_ctx_menu.clear()
	_player_ctx_menu.add_item(display_name, PCM.Action.HEADER)
	_player_ctx_menu.set_item_disabled(0, true)
	_player_ctx_menu.add_separator()
	for d in PCM.item_defs():
		_player_ctx_menu.add_item(str(d.get("text", "")), int(d.get("id", 0)))
	_player_ctx_menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	_player_ctx_menu.reset_size()
	_player_ctx_menu.popup()


func prefill_whisper(target_name: String) -> void:
	## Focus chat with /w Name  so the player can type a whisper.
	target_name = str(target_name).strip_edges()
	if target_name.is_empty():
		return
	if chat_input != null:
		chat_input.text = "/w %s " % target_name
		chat_input.caret_column = chat_input.text.length()
		chat_input.grab_focus()
	_chat_channel = "whisper"
	append_system("密语对象：【%s】（发送即可）" % target_name)


func _on_player_context_id(id: int) -> void:
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	var dname := _player_ctx_target_name
	var pid := _player_ctx_target_id
	match id:
		PCM.Action.VIEW:
			append_system("玩家【%s】 id=%s" % [dname, pid])
		PCM.Action.INVITE:
			_on_party_invite(dname)
		PCM.Action.TRADE:
			_on_trade_open_with(dname)
		PCM.Action.WHISPER:
			prefill_whisper(dname)
		PCM.Action.FOLLOW:
			append_system("跟随：暂未实现")


func _on_trade_open_with(partner_name: String) -> void:
	partner_name = str(partner_name).strip_edges()
	if _world_combat != null and _world_combat.has_method("request_trade_open"):
		_world_combat.request_trade_open(partner_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		_apply_trade_result_locally(srv.try_trade_open(partner_name))


func _build_trade_panel() -> void:
	_trade_panel = PanelContainer.new()
	_trade_panel.name = "TradePanel"
	_trade_panel.set_script(HudDrag)
	_trade_panel.screen_margin = 4.0
	_trade_panel.min_size = Vector2(320, 240)
	_trade_panel.default_size = Vector2(420, 360)
	_trade_panel.initial_dock = "none"
	_trade_panel.drag_anywhere = true
	add_child(_trade_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	_trade_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "TradeTitle"
	title.text = "交易"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(_on_trade_cancel)
	head.add_child(close_btn)
	_trade_body = VBoxContainer.new()
	_trade_body.name = "TradeBody"
	_trade_body.add_theme_constant_override("separation", 6)
	_trade_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_trade_body)
	_trade_panel.visible = false
	_refresh_trade_panel()
	call_deferred("_nudge_trade")


func _nudge_trade() -> void:
	if _trade_panel:
		var vp := get_viewport_rect().size
		_trade_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 210)), 80)


func _toggle_trade_panel() -> void:
	## Legacy no-op for callers; trade is started only via player right-click.
	if _trade_panel == null:
		return
	if not bool(_trade_state.get("active", false)):
		append_system("交易请右键玩家发起。")
		hide_trade()
		return
	_trade_panel.visible = not _trade_panel.visible
	if _trade_panel.visible:
		_refresh_trade_panel()
		call_deferred("_nudge_trade")


func apply_trade_update(action: Dictionary) -> void:
	var trade_v: Variant = action.get("trade", action)
	if typeof(trade_v) != TYPE_DICTIONARY:
		return
	var trade: Dictionary = trade_v
	if not bool(trade.get("active", true)) and str(trade.get("session_id", "")).is_empty():
		_trade_state = {"active": false}
		hide_trade()
		return
	_trade_state = trade.duplicate(true)
	_trade_state["active"] = true
	if _trade_panel != null:
		_trade_panel.visible = true
		_refresh_trade_panel()
		call_deferred("_nudge_trade")


func hide_trade() -> void:
	_trade_state = {"active": false}
	if _trade_panel != null:
		_trade_panel.visible = false


func _refresh_trade_panel() -> void:
	if _trade_body == null:
		return
	for c in _trade_body.get_children():
		c.queue_free()
	_trade_gold_spin = null
	if not bool(_trade_state.get("active", false)):
		_add_label(_trade_body, "未在交易。右键玩家 →「交易」发起。", 11, Color(0.65, 0.65, 0.7))
		# Keep panel hidden when idle — no HUD button / stub open.
		if _trade_panel != null:
			_trade_panel.visible = false
		return
	var pname := str(_trade_state.get("partner_name", "对方"))
	var title := _trade_panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/TradeTitle")
	# Title path may differ — update via first label in head if needed.
	_add_label(_trade_body, "对方：%s" % pname, 12, Color(0.9, 0.88, 0.7))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_body.add_child(cols)
	var my_col := VBoxContainer.new()
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_col.add_theme_constant_override("separation", 4)
	cols.add_child(my_col)
	var their_col := VBoxContainer.new()
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_col.add_theme_constant_override("separation", 4)
	cols.add_child(their_col)
	_add_label(my_col, "你的报价", 11, Color(0.7, 0.85, 0.95))
	_add_label(their_col, "对方报价", 11, Color(0.95, 0.75, 0.55))
	_fill_trade_item_list(my_col, _trade_state.get("my_items", []), true)
	_fill_trade_item_list(their_col, _trade_state.get("their_items", []), false)
	_add_label(my_col, "金币：%d" % int(_trade_state.get("my_gold", 0)), 11, Color(0.95, 0.9, 0.4))
	_add_label(their_col, "金币：%d" % int(_trade_state.get("their_gold", 0)), 11, Color(0.95, 0.9, 0.4))
	var ready_me := bool(_trade_state.get("my_ready", false))
	var ready_them := bool(_trade_state.get("their_ready", false))
	_add_label(
		_trade_body,
		"锁定：你[%s] / 对方[%s]" % ["是" if ready_me else "否", "是" if ready_them else "否"],
		11,
		Color(0.75, 0.8, 0.75)
	)
	if not ready_me:
		# Put items from bag (first few stacks as quick buttons)
		_add_label(_trade_body, "从背包放入（×1）：", 10, Color(0.6, 0.6, 0.65))
		var bag_row := HFlowContainer.new()
		bag_row.add_theme_constant_override("h_separation", 4)
		bag_row.add_theme_constant_override("v_separation", 4)
		_trade_body.add_child(bag_row)
		var added := 0
		for it in _server_inventory:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid := str(it.get("id", "")).strip_edges()
			var q: int = int(it.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			var b := Button.new()
			b.text = "%s×%d" % [_item_label(iid), q]
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_on_trade_put_item.bind(iid))
			bag_row.add_child(b)
			added += 1
			if added >= 8:
				break
		if added == 0:
			_add_label(bag_row, "（背包为空）", 10, Color(0.5, 0.5, 0.55))
		var gold_row := HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		_trade_body.add_child(gold_row)
		_add_label(gold_row, "放入金币", 11, Color(0.85, 0.85, 0.7))
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(_server_gold + int(_trade_state.get("my_gold", 0)), 0)
		spin.value = int(_trade_state.get("my_gold", 0))
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(spin)
		_trade_gold_spin = spin
		var setg := Button.new()
		setg.text = "设定"
		setg.focus_mode = Control.FOCUS_NONE
		setg.pressed.connect(_on_trade_set_gold)
		gold_row.add_child(setg)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_trade_body.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_on_trade_cancel)
	btn_row.add_child(cancel)
	var ready_btn := Button.new()
	ready_btn.text = "取消锁定" if ready_me else "锁定"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.pressed.connect(_on_trade_ready.bind(not ready_me))
	btn_row.add_child(ready_btn)
	var conf := Button.new()
	conf.text = "确认交易"
	conf.focus_mode = Control.FOCUS_NONE
	conf.disabled = not (ready_me and ready_them)
	conf.pressed.connect(_on_trade_confirm)
	btn_row.add_child(conf)


func _fill_trade_item_list(parent: Node, items_v: Variant, mine: bool) -> void:
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		_add_label(parent, "（空）", 10, Color(0.5, 0.5, 0.55))
		return
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = it
		var iid := str(md.get("item_id", ""))
		var nm := str(md.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = _item_label(iid)
		var q: int = int(md.get("qty", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var lab := Label.new()
		lab.text = "%s ×%d" % [nm, q]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 11)
		row.add_child(lab)
		if mine and not bool(_trade_state.get("my_ready", false)):
			var rm := Button.new()
			rm.text = "−"
			rm.focus_mode = Control.FOCUS_NONE
			rm.custom_minimum_size = Vector2(24, 20)
			rm.pressed.connect(_on_trade_take_item.bind(iid))
			row.add_child(rm)


func _on_trade_open() -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_open"):
		_world_combat.request_trade_open("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		_apply_trade_result_locally(srv.try_trade_open(""))


func _on_trade_cancel() -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_cancel"):
		_world_combat.request_trade_cancel()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_cancel"):
		_apply_trade_result_locally(srv.try_trade_cancel())


func _on_trade_put_item(item_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_put_item"):
		_world_combat.request_trade_put_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_put_item"):
		_apply_trade_result_locally(srv.try_trade_put_item(item_id, 1))


func _on_trade_take_item(item_id: String) -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_take_item"):
		_world_combat.request_trade_take_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_take_item"):
		_apply_trade_result_locally(srv.try_trade_take_item(item_id, 1))


func _on_trade_set_gold() -> void:
	var amount: int = 0
	if _trade_gold_spin != null:
		amount = int(_trade_gold_spin.value)
	if _world_combat != null and _world_combat.has_method("request_trade_set_gold"):
		_world_combat.request_trade_set_gold(amount)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_set_gold"):
		_apply_trade_result_locally(srv.try_trade_set_gold(amount))


func _on_trade_ready(ready: bool) -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_ready"):
		_world_combat.request_trade_ready(ready)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_ready"):
		_apply_trade_result_locally(srv.try_trade_ready(ready))


func _on_trade_confirm() -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_confirm"):
		_world_combat.request_trade_confirm()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_confirm"):
		_apply_trade_result_locally(srv.try_trade_confirm())


func _apply_trade_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"trade_update":
				apply_trade_update(action)
			"trade_close":
				hide_trade()
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
