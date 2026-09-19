extends Control
const StatusIconBar = preload("res://scripts/ui/status_icon_bar.gd")
## Lineage 2–inspired HUD: shell + toggle windows (inventory / status / skills / quest / system).

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Mock = preload("res://scripts/ui/l2_mock.gd")
const RadarView = preload("res://scripts/ui/radar_view.gd")
const MapOverview = preload("res://scripts/ui/map_overview.gd")
const InvSlot = preload("res://scripts/ui/inv_slot.gd")
const EquipCompare = preload("res://scripts/ui/equip_compare.gd")
const EquipSlot = preload("res://scripts/ui/equip_slot.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const HotbarSlot = preload("res://scripts/ui/hotbar_slot.gd")
const SkillSlot = preload("res://scripts/ui/skill_slot.gd")
const RecipeCatalog = preload("res://scripts/net/combat/recipe_catalog.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const PaperdollLook = preload("res://scripts/char/paperdoll_look.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const CombatLogScript = preload("res://scripts/game/combat_log.gd")
const QuestTrackerUtil = preload("res://scripts/ui/quest_tracker_util.gd")
const ChatTimestampUtil = preload("res://scripts/ui/chat_timestamp_util.gd")
const ItemRarity = preload("res://scripts/ui/item_rarity.gd")
const AfkWarnUtil = preload("res://scripts/game/afk_warn_util.gd")
const InvSearchUtil = preload("res://scripts/ui/inv_search_util.gd")

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
var _target_mp: ProgressBar = null
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
const ShopPanel = preload("res://scripts/ui/panels/shop_panel.gd")
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
var _map_pin_cell: Vector2i = Vector2i(-9999, -9999)
## Personal pins snapshot [{id,slot,name,cell,map_id}, ...] (max 3).
var _map_pins: Array = []
var _party_panel: PanelContainer
var _party_body: VBoxContainer = null
## Last party snapshot {party_id, leader, members:[{id,name,hp,hp_max,online}]}
var _party_state: Dictionary = {"party_id": "", "leader": "", "members": [], "loot_mode": "ffa"}
## member_id -> expanded (show status icons under party row)
var _party_expanded: Dictionary = {}
var _trade_panel: PanelContainer = null
var _trade_body: VBoxContainer = null
var _trade_state: Dictionary = {"active": false}
var _trade_gold_spin: SpinBox = null
var _warehouse_panel: PanelContainer = null
var _warehouse_body: VBoxContainer = null
var _warehouse_state: Dictionary = {"items": [], "gold": 0, "max_slots": 60, "used_slots": 0}
var _warehouse_gold_spin: SpinBox = null
var _friends_panel: PanelContainer = null
var _friends_body: VBoxContainer = null
var _friends_state: Dictionary = {"friends": [], "count": 0, "max_friends": 50}
var _friends_add_input: LineEdit = null
var _mail_panel: PanelContainer = null
var _mail_body: VBoxContainer = null
var _mail_state: Dictionary = {"mails": [], "count": 0, "max_mail": 30}
var _mail_selected_id: String = ""
var _mail_to_input: LineEdit = null
var _mail_subject_input: LineEdit = null
var _mail_body_input: TextEdit = null
var _mail_gold_spin: SpinBox = null
var _mail_item_id_input: LineEdit = null
var _mail_item_qty_spin: SpinBox = null
var _craft_panel: PanelContainer = null
var _craft_body: VBoxContainer = null
var _craft_recipes: Array = []
var _craft_selected_id: String = ""
var _craft_qty_spin: SpinBox = null
var _craft_level: int = 1
var _craft_xp: int = 0
var _craft_xp_to_next: int = 30
var _gather_level: int = 1
var _gather_xp: int = 0
var _gather_xp_to_next: int = 30
var _gather_level_label: Label = null
var _emote_panel: PanelContainer = null
var _emote_body: VBoxContainer = null
var _combat_log_panel: PanelContainer = null
var _dps_meter_panel: PanelContainer = null
var _dps_meter_label: Label = null
var _dps_meter_active: bool = false
var _dps_meter_value: float = 0.0
var _combat_log_body: VBoxContainer = null
var _combat_log_scroll: ScrollContainer = null
var _combat_log = null
var _combat_log_filter_row: HBoxContainer = null
var _titles_panel: PanelContainer = null
var _titles_body: VBoxContainer = null
var _titles_state: Dictionary = {"counters": {}, "unlocked_titles": [], "active_title": "", "titles": []}
var _title_under_name: Label = null
var _achievements_panel: PanelContainer = null
var _achievements_body: VBoxContainer = null
var _achievements_state: Dictionary = {"counters": {}, "unlocked_achievements": [], "achievements": []}
var _daily_panel: PanelContainer = null
var _daily_body: VBoxContainer = null
var _daily_state: Dictionary = {"daily_date": "", "daily": []}
var _guild_panel: PanelContainer = null
var _guild_body: VBoxContainer = null
var _guild_state: Dictionary = {"id": "", "name": "", "leader_id": "", "members": []}
var _guild_name_input: LineEdit = null
var _guild_invite_input: LineEdit = null
var _guild_pending_invite: Dictionary = {}
var _auction_panel: PanelContainer = null
var _auction_body: VBoxContainer = null
var _auction_state: Dictionary = {"listings": [], "count": 0, "max_listings": 50}
var _auction_item_id_input: LineEdit = null
var _auction_qty_spin: SpinBox = null
var _auction_price_spin: SpinBox = null
var _base_char_name: String = ""
var _player_ctx_menu: PopupMenu = null
var _player_ctx_target_id: String = ""
var _player_ctx_target_name: String = ""
var _duel_banner: PanelContainer = null
var _duel_label: Label = null
var _duel_state: Dictionary = {"active": false}
var _duel_banner_acc: float = 0.0
## Thin non-blocking 「安全区」 chip near status panel.
var _safe_zone_chip: Label = null
var _safe_zone_inside: bool = false
## Thin 「试炼 N/M」 chip when dungeon session active.
var _dungeon_chip: Label = null
var _dungeon_state: Dictionary = {}
## Short-lived level-up toast (mouse-filter ignore — never blocks input).
var _level_toast: PanelContainer = null
var _level_toast_label: Label = null
var _level_toast_ttl: float = 0.0
var _level_toast_armed: bool = false
var _level_toast_level: int = 1
var _level_toast_sp_note: bool = false
const LEVEL_TOAST_DURATION := 2.0
## Short-lived quest ready/complete toast (same top-banner style; mouse ignore).
var _quest_toast: PanelContainer = null
var _quest_toast_label: Label = null
var _quest_toast_ttl: float = 0.0
const QUEST_TOAST_DURATION := 2.0

## Idle AFK warn (client toast; no kick).
var _afk_toast: PanelContainer = null
var _afk_toast_label: Label = null
var _afk_toast_ttl: float = 0.0
const AFK_TOAST_DURATION := 3.0
var _last_input_sec: float = 0.0
var _afk_warned: bool = false
## id -> last seen status; first snapshot only seeds (no toast spam on enter_world).
var _quest_status_seen: Dictionary = {}
var _quest_status_seeded: bool = false
## Thin EXP-gain float tip 「经验 +N」(~1.2s; coalesces rapid gains). Distinct from level-up toast.
var _exp_float: Label = null
var _exp_float_ttl: float = 0.0
var _exp_float_amount: int = 0
const EXP_FLOAT_DURATION := 1.2
## Thin gold-gain float tip 「金币 +N」(~1.2s; coalesces; yellow). Distinct from exp float.
var _gold_float: Label = null
var _gold_float_ttl: float = 0.0
var _gold_float_amount: int = 0
const GOLD_FLOAT_DURATION := 1.2
## First wallet snapshot only seeds (no float spam on enter_world).
var _gold_wallet_known: bool = false
## Thin item-gain floats 「获得：野草 ×2」(~1.2s; coalesce same id; cap ~3).
var _item_float_host: VBoxContainer = null
## Active lines: [{id:String, qty:int, ttl:float, label:Label, name:String}]
var _item_floats: Array = []
const ITEM_FLOAT_DURATION := 1.2
const ITEM_FLOAT_MAX_LINES := 3
## First bag snapshot only seeds (no float spam on enter_world).
var _inv_qty_known: bool = false
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
## Known skill ids from MockServer skill_book.
var _known_skills: Dictionary = {}
var _skill_points: int = 0
var _selected_skill_id: String = ""
## Second-click arm for skill respec (like quest abandon).
var _skill_respec_armed: bool = false
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
## System settings tab: video | audio | game | system
var _system_tab: String = "video"
var _menu_popup: PanelContainer = null
var _menu_dim: ColorRect = null
var _menu_btn: Button = null
var _death_panel: PanelContainer = null
var _inspect_panel: PanelContainer = null
var _quest_tracker: PanelContainer = null
var _invite_panel: PanelContainer = null
var _loot_roll_panel: PanelContainer = null
var _loot_roll_id: String = ""
var _loot_roll_label: Label = null
var _waiting_bind: String = ""
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
## Active shop tab: buy | sell
var _shop_tab: String = "buy"
var _shop_buyback: Array = []
## Vendor reputation shown while shop is open (-1 = hide).
var _shop_vendor_rep: int = -1
var _inv_filter: String = "all"
## Client-only bag search query (name/id substring); empty = show all.
var _inv_search_query: String = ""
var _qty_mode: String = "drop"
const SHOP_TABS := [
	["买入", "buy"],
	["卖出", "sell"],
	["回购", "buyback"],
]
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
## Small 「休息 N」 label on XP bar when rested_exp > 0.
var _rested_label: Label = null
## Player status icon strip (L2 plate + FF14 pie timer).
var _status_chip_row: Control = null
var _player_statuses: Array = []
## Optional chips under target panel.
var _target_status_chip_row: Control = null
## Thin 「仇恨」/「无仇恨」 chip on hostile target bar.
var _threat_chip: Label = null
var _threat_you: bool = false
var _threat_visible: bool = false
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
const SYSTEM_TABS := [
	["画面", "video"],
	["声音", "audio"],
	["游戏", "game"],
	["按键", "keys"],
	["系统", "system"],
]
const MENU_ITEMS := [
	["角色", "character", "icon_character.png"],
	["背包", "inventory", "icon_inventory.png"],
	["技能", "skills", "icon_skills.png"],
	["任务", "quest", "icon_quest.png"],
	["队伍", "party", "icon_party.png"],
	["地图", "map", "icon_map.png"],
	["系统", "system", "icon_system.png"],
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
	["战斗", "combat"],
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
	_connect_game_settings()
	_build_party_stub()
	_build_trade_panel()
	_build_warehouse_panel()
	_build_friends_panel()
	_build_mail_panel()
	_build_craft_panel()
	_build_emote_panel()
	_build_combat_log_panel()
	_build_dps_meter()
	_build_titles_panel()
	_build_achievements_panel()
	_build_daily_panel()
	_build_guild_panel()
	_build_auction_panel()
	_build_player_context_menu()
	_build_duel_banner()
	_ensure_safe_zone_chip()
	_ensure_dungeon_chip()
	_build_level_toast()
	_build_quest_toast()
	_build_afk_toast()
	_last_input_sec = Time.get_ticks_msec() / 1000.0
	_build_exp_float()
	_build_gold_float()
	_build_item_floats()
	_ensure_target_chrome()
	_compact_status_panel()
	clear_target()
	_build_death_dialog()
	_build_inspect_panel()
	_build_quest_tracker()
	_restore_window_layouts()
	_connect_window_layout_signals()

func _input(event: InputEvent) -> void:
	## Any key / mouse press counts as activity for AFK warn (non-consuming).
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_note_player_input()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_note_player_input()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if not _waiting_bind.is_empty():
		_finish_keybind(k.keycode)
		get_viewport().set_input_as_handled()
		return
	if _try_hotbar_key(k.keycode):
		get_viewport().set_input_as_handled()
		return
	var gs := GameSettingsScript.get_i()
	var code := k.keycode
	if gs != null:
		if code == int(gs.key_for("character")):
			_toggle_window("character")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("inventory")):
			_toggle_window("inventory")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("skills")):
			_toggle_window("skills")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("quest")):
			_toggle_window("quest")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("quest_tracker")):
			gs.set_flag("show_quest_tracker", not bool(gs.show_quest_tracker))
			_refresh_quest_tracker()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("map")):
			_toggle_window("map")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("system")):
			_toggle_window("system")
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("party")):
			_toggle_party_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("warehouse")):
			_toggle_warehouse_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("friends")):
			_toggle_friends_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("mail")):
			_toggle_mail_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("craft")):
			_toggle_craft_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("emote")):
			_toggle_emote_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("titles")):
			_toggle_titles_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("achievements")):
			_toggle_achievements_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("guild")):
			_toggle_guild_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("auction")):
			_toggle_auction_panel()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("cycle_target")):
			if _world_combat != null and _world_combat.has_method("cycle_hostile_target"):
				var dir := -1 if k.shift_pressed else 1
				_world_combat.cycle_hostile_target(dir)
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("sit")):
			if _world_combat != null and _world_combat.has_method("request_sit"):
				_world_combat.request_sit()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("pickup")):
			if _world_combat != null and _world_combat.has_method("pickup_nearest"):
				_world_combat.pickup_nearest()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("auto_attack")):
			if _world_combat != null and _world_combat.has_method("toggle_auto_attack"):
				_world_combat.toggle_auto_attack()
			get_viewport().set_input_as_handled()
			return
		if code == int(gs.key_for("combat_log")):
			_toggle_combat_log_panel()
			get_viewport().set_input_as_handled()
			return
	if k.keycode == KEY_ESCAPE:
		if _world_combat != null and _world_combat.has_method("is_skill_aiming") and _world_combat.is_skill_aiming():
			_world_combat.cancel_skill_aim()
			get_viewport().set_input_as_handled()
			return
		if _menu_popup != null and _menu_popup.visible:
			_close_menu_popup()
			get_viewport().set_input_as_handled()
		elif _death_panel != null and _death_panel.visible:
			get_viewport().set_input_as_handled()
		elif _invite_panel != null and _invite_panel.visible:
			_hide_invite_dialog()
			get_viewport().set_input_as_handled()
		elif _close_top_window():
			get_viewport().set_input_as_handled()

func bind_character(ch: Dictionary) -> void:
	_character = ch.duplicate(true)
	if ch.is_empty():
		_base_char_name = "???"
		name_label.text = "???"
		level_label.text = "Lv.?"
		return
	var lv := int(ch.get("level", 1))
	var cname := str(ch.get("name", "")).strip_edges()
	if cname.is_empty():
		cname = "???"
	_base_char_name = cname
	_refresh_name_with_title()
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
	_ensure_title_under_name()
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
	## L2/FF14 icon strip under the CP/HP/MP panel (buffs then debuffs).
	var panel := get_node_or_null("%StatusPanel") as PanelContainer
	if panel == null:
		return
	if _status_chip_row != null and is_instance_valid(_status_chip_row):
		return
	var existing := panel.get_parent().get_node_or_null("StatusIconBar") if panel.get_parent() else null
	if existing != null:
		_status_chip_row = existing
		_wire_player_status_bar(_status_chip_row)
		return
	var parent_ctl := panel.get_parent() as Control
	var bar = StatusIconBar.new()
	bar.name = "StatusIconBar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent_ctl != null:
		parent_ctl.add_child(bar)
		parent_ctl.move_child(bar, panel.get_index() + 1)
	else:
		panel.add_child(bar)
	_status_chip_row = bar
	_wire_player_status_bar(bar)
	if bar.has_method("apply_statuses"):
		bar.apply_statuses(_player_statuses)


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
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.add_theme_stylebox_override("panel", sb)
		var inner := Label.new()
		inner.text = txt
		inner.add_theme_font_size_override("font_size", 10)
		inner.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(inner)
		var desc := str(d.get("desc", d.get("description", ""))).strip_edges()
		var kind := str(d.get("kind", ""))
		chip.tooltip_text = "%s\n剩余 %.1f 秒%s%s" % [n, rem, ("\n" + kind) if kind != "" else "", ("\n" + desc) if desc != "" else ""]
		row.add_child(chip)


func apply_status_chips(statuses: Array) -> void:
	_player_statuses = statuses.duplicate(true)
	_ensure_status_chip_row()
	if _status_chip_row != null and _status_chip_row.has_method("apply_statuses"):
		_status_chip_row.apply_statuses(_player_statuses)
	elif _status_chip_row != null:
		_rebuild_status_chips(_status_chip_row, _player_statuses)
	# Soft-refresh expanded self row in party panel when statuses change.
	if _party_in_party():
		_sync_party_self_statuses_from_player()
		if _party_panel != null and _party_panel.visible:
			_refresh_party_panel()


func _wire_player_status_bar(bar: Control) -> void:
	if bar == null:
		return
	if "allow_cancel" in bar:
		bar.allow_cancel = true
	if bar.has_signal("cancel_requested"):
		if not bar.cancel_requested.is_connected(_on_status_cancel_requested):
			bar.cancel_requested.connect(_on_status_cancel_requested)


func _on_status_cancel_requested(status_id: String) -> void:
	status_id = str(status_id).strip_edges()
	if status_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_cancel_status"):
		_world_combat.request_cancel_status(status_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_cancel_status"):
		_apply_party_result_locally(srv.try_cancel_status(status_id))
	else:
		append_system("无法取消状态。")


func _sync_party_self_statuses_from_player() -> void:
	var self_id := _party_self_id_for_ui()
	var mem_v: Variant = _party_state.get("members", [])
	if typeof(mem_v) != TYPE_ARRAY:
		return
	var members: Array = mem_v
	for i in range(members.size()):
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = members[i]
		if str(md.get("id", "")) == self_id:
			md["statuses"] = _player_statuses.duplicate(true)
			members[i] = md
			_party_state["members"] = members
			return


func apply_target_status_chips(statuses: Array) -> void:
	if target_panel == null:
		return
	_ensure_target_chrome()
	if _target_status_chip_row == null or not is_instance_valid(_target_status_chip_row):
		var vbox := target_panel.find_child("TargetVBox", true, false) as VBoxContainer
		if vbox == null:
			return
		var existing = vbox.get_node_or_null("TargetStatusIconBar")
		if existing != null:
			_target_status_chip_row = existing
		else:
			var bar = StatusIconBar.new()
			bar.name = "TargetStatusIconBar"
			bar.icon_size = 28.0
			bar.allow_cancel = false
			vbox.add_child(bar)
			_target_status_chip_row = bar
	if _target_status_chip_row.has_method("apply_statuses"):
		_target_status_chip_row.apply_statuses(statuses)
	else:
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
	var rested: int = maxi(int(_server_combat.get("rested_exp", 0)), 0)
	var tip := ""
	if exp_next <= 0:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		tip = "经验 %d" % exp_cur
	else:
		_xp_bar.max_value = float(exp_next)
		_xp_bar.value = float(mini(exp_cur, exp_next))
		tip = "经验 %d / %d" % [exp_cur, exp_next]
	if rested > 0:
		tip += "
休息 %d" % rested
		var rmax: int = int(_server_combat.get("rested_exp_max", 0))
		if rmax > 0:
			tip += " / %d" % rmax
	_xp_bar.tooltip_text = tip
	_refresh_rested_label(rested)


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
	_connect_radar_nav()
	if _radar != null and _radar.has_method("set_pin_cell"):
		_radar.set_pin_cell(_map_pin_cell)
	_sync_radar(true)


func clear_target() -> void:
	target_panel.visible = false
	target_name.text = ""
	target_hp.value = 0
	target_hp.visible = false
	if _target_mp != null:
		_target_mp.value = 0
		_target_mp.visible = false
	_target_world_pos = null
	_threat_visible = false
	_threat_you = false
	if _threat_chip != null and is_instance_valid(_threat_chip):
		_threat_chip.visible = false
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
	# Keep HP under the head row; MP under HP.
	if target_hp.get_parent() == vbox:
		vbox.move_child(target_hp, mini(1, vbox.get_child_count() - 1))
	if _target_mp == null or not is_instance_valid(_target_mp):
		_target_mp = vbox.get_node_or_null("TargetMp") as ProgressBar
	if _target_mp == null:
		_target_mp = ProgressBar.new()
		_target_mp.name = "TargetMp"
		_target_mp.custom_minimum_size = Vector2(0, 10)
		_target_mp.show_percentage = false
		_target_mp.modulate = Color(0.28, 0.48, 0.95, 1)
		_target_mp.max_value = 100.0
		_target_mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_target_mp)
	if _target_mp.get_parent() == vbox:
		vbox.move_child(_target_mp, mini(2, vbox.get_child_count() - 1))
	_ensure_threat_chip()


## Hostile target bar: 「仇恨」 gold/red when you are victim; 「无仇恨」 muted otherwise.
func apply_threat_chip(show: bool, threat_you: bool = false) -> void:
	_threat_visible = show
	_threat_you = threat_you
	_ensure_threat_chip()
	if _threat_chip == null:
		return
	if not show:
		_threat_chip.visible = false
		return
	var ThreatUtil = preload("res://scripts/ui/threat_hud_util.gd")
	_threat_chip.text = ThreatUtil.chip_text(threat_you)
	_threat_chip.add_theme_color_override("font_color", ThreatUtil.chip_color(threat_you))
	_threat_chip.visible = true


func apply_threat_update(action: Dictionary) -> void:
	## From threat_update / set_stat piggyback while a hostile target is shown.
	if not _threat_visible and not bool(action.get("force", false)):
		# Only refresh when chip already armed for a hostile target.
		if target_panel == null or not target_panel.visible:
			return
	var ThreatUtil = preload("res://scripts/ui/threat_hud_util.gd")
	var n: Dictionary = ThreatUtil.normalize(action)
	apply_threat_chip(true, bool(n.get("threat_you", false)))


func _ensure_threat_chip() -> void:
	if target_panel == null:
		return
	if _threat_chip != null and is_instance_valid(_threat_chip):
		_threat_chip.visible = _threat_visible
		return
	var vbox := target_panel.find_child("TargetVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var head := vbox.get_node_or_null("TargetHead") as HBoxContainer
	_threat_chip = Label.new()
	_threat_chip.name = "ThreatChip"
	_threat_chip.text = "无仇恨"
	_threat_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_chip.add_theme_font_size_override("font_size", 11)
	_threat_chip.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1.0))
	_threat_chip.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	_threat_chip.add_theme_constant_override("outline_size", 2)
	_threat_chip.visible = _threat_visible
	if head != null:
		# Insert before close button (last child) when possible.
		head.add_child(_threat_chip)
		var close := head.get_node_or_null("TargetClose")
		if close != null:
			head.move_child(_threat_chip, close.get_index())
	else:
		vbox.add_child(_threat_chip)
		vbox.move_child(_threat_chip, 0)


func _on_target_close_pressed() -> void:
	## × clears HUD target and world selection / foot ring.
	if _world_combat != null and _world_combat.has_method("clear_target_selection"):
		_world_combat.clear_target_selection()
	else:
		clear_target()


func show_target(
	p_name: String,
	hp_ratio: float = 1.0,
	world_pos: Variant = null,
	show_hp_bar: bool = true,
	mp_ratio: float = -1.0,
	show_threat: bool = false,
	threat_you: bool = false
) -> void:
	_ensure_target_chrome()
	target_panel.visible = true
	target_name.text = p_name
	target_hp.visible = show_hp_bar
	if show_hp_bar:
		target_hp.max_value = 100.0
		target_hp.value = clampf(hp_ratio, 0.0, 1.0) * 100.0
	else:
		target_hp.value = 0
	var show_mp := show_hp_bar and mp_ratio >= 0.0
	if _target_mp != null:
		_target_mp.visible = show_mp
		if show_mp:
			_target_mp.max_value = 100.0
			_target_mp.value = clampf(mp_ratio, 0.0, 1.0) * 100.0
		else:
			_target_mp.value = 0
	if typeof(world_pos) == TYPE_VECTOR2:
		_target_world_pos = world_pos
		_update_target_angle()
	else:
		_target_world_pos = null
		if _radar and _radar.has_method("clear_target_angle"):
			_radar.clear_target_angle()
	apply_threat_chip(show_threat, threat_you)

func append_chat(speaker: String, msg: String) -> void:
	_push_chat(_chat_channel if _chat_channel != "all" else "all", speaker, msg)

func append_system(msg: String) -> void:
	_push_chat("system", "系统", msg)


func append_combat(msg: String) -> void:
	msg = msg.strip_edges()
	if msg.is_empty():
		return
	_ensure_combat_log()
	_combat_log.push(msg)
	_refresh_combat_log_panel()
	# Keep combat chat-tab feed (channel filter only — not a second full chat UI).
	_push_chat("combat", "战斗", msg)


func append_combat_typed(kind: String, msg: String) -> void:
	msg = msg.strip_edges()
	if msg.is_empty():
		return
	_ensure_combat_log()
	_combat_log.push_typed(kind, msg)
	_refresh_combat_log_panel()
	_push_chat("combat", "战斗", msg)


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
	_npc_chat_body.append_text(safe)
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
		link.add_theme_color_override("default_color", L2Style.COL_LINK)
		link.add_theme_color_override("font_url_color", L2Style.COL_LINK)
		link.custom_minimum_size = Vector2(0, 22)
		link.append_text("[center][url][u]%s[/u][/url][/center]" % label)
		var opt_id := ""
		var opt_idx := _npc_chat_options.get_child_count()
		if typeof(opt) == TYPE_DICTIONARY:
			opt_id = str(opt.get("id", "")).strip_edges()
		link.meta_clicked.connect(_make_dialogue_option_handler(opt_id, opt_idx, label))
		_npc_chat_options.add_child(link)
	_npc_chat.visible = true
	_npc_chat.move_to_front()
	var base: Vector2 = _npc_chat.get_meta("base_size", Vector2(380, 400))
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
	panel.min_size = Vector2(280, 220)
	panel.default_size = Vector2(380, 400)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(280, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
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
	title_l.text = "对话"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(hide_npc_dialogue)
	head.add_child(close_btn)
	vbox.add_child(L2Style.hairline())
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", L2Style.COL_TITLE)
	name_l.add_theme_constant_override("outline_size", 3)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
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
	vbox.add_child(L2Style.hairline())
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
	body_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	L2Style.style_body_rtl(body_rtl)
	scroll.add_child(body_rtl)
	var opts := VBoxContainer.new()
	opts.name = "Options"
	opts.add_theme_constant_override("separation", 4)
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opts.size_flags_vertical = Control.SIZE_SHRINK_END
	opts.custom_minimum_size = Vector2(0, 88)
	vbox.add_child(opts)
	var foot := Control.new()
	foot.name = "FiligreePad"
	foot.custom_minimum_size = Vector2(0, 12)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(foot)
	panel.set_meta("base_size", Vector2(380, 400))
	_npc_chat = panel
	_npc_chat_name = name_l
	_npc_chat_body = body_rtl
	_npc_chat_options = opts
	_npc_chat_face = face_tex
	_apply_l2_chrome(panel)


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
	var base: Vector2 = _npc_chat.get_meta("base_size", Vector2(380, 400))
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
	if _menu_popup != null and _menu_popup.visible and _menu_popup.get_global_rect().has_point(screen_pos):
		return true
	if _menu_dim != null and _menu_dim.visible:
		return true
	for node_name in ["ChatLog", "ChatInput", "Hotbar", "MenuRow", "MenuPanel", "ChatTabs", "MinimapView", "TargetPanel"]:
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
		"combat":
			color = "#e08060"
		_:
			color = "#c9a66b"
	var ts := ChatTimestampUtil.format_now()
	_chat_history.append({
		"channel": channel,
		"speaker": speaker,
		"msg": msg,
		"color": color,
		"ts": ts,
	})
	if _chat_history.size() > CHAT_HISTORY_MAX:
		_chat_history = _chat_history.slice(_chat_history.size() - CHAT_HISTORY_MAX)
	if _chat_visible(channel):
		chat_log.append_text(_format_chat_bbcode(color, speaker, msg, ts))

func _format_chat_bbcode(color: String, speaker: String, msg: String, ts: String = "") -> String:
	var line := "[color=%s]%s[/color]: %s\n" % [color, speaker, msg]
	if GameSettingsScript.flag("show_chat_timestamps", true) and not str(ts).is_empty():
		return "%s %s" % [ts, line]
	return line

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
		chat_log.append_text(_format_chat_bbcode(
			str(row.get("color", "#c9a66b")),
			str(row.get("speaker", "")),
			str(row.get("msg", "")),
			str(row.get("ts", "")),
		))

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
	_tick_duel_banner(_delta)
	_tick_level_toast(_delta)
	_tick_quest_toast(_delta)
	_tick_afk_warn(_delta)
	_tick_exp_float(_delta)
	_tick_gold_float(_delta)
	_tick_item_floats(_delta)
	_tick_cast_bar_visual(_delta)
	_tick_hotbar_cooldowns(_delta)
	_tick_status_icon_bars(_delta)
	_sync_quest_drawer_follow()
	_tick_ground_drop_zone()
	if not RADAR_ENABLED:
		return
	if _radar_player == null or _radar == null:
		return
	_sync_radar(false)



func _tick_status_icon_bars(delta: float) -> void:
	## Advance pie timers on player/target StatusIconBar strips (no-op if absent).
	if _status_chip_row != null and is_instance_valid(_status_chip_row) and _status_chip_row.has_method("tick"):
		_status_chip_row.tick(delta)
	if _target_status_chip_row != null and is_instance_valid(_target_status_chip_row) and _target_status_chip_row.has_method("tick"):
		_target_status_chip_row.tick(delta)


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
	_sync_map_poi_markers()


func _sync_map_poi_markers() -> void:
	if _map_overview == null or not is_instance_valid(_map_overview):
		return
	if not _map_overview.has_method("set_poi_markers"):
		return
	var markers: Array = []
	if _radar_blip_source is Node and is_instance_valid(_radar_blip_source):
		if _radar_blip_source.has_method("get_radar_poi_markers"):
			var mv: Variant = _radar_blip_source.get_radar_poi_markers()
			if typeof(mv) == TYPE_ARRAY:
				markers = mv
	_map_overview.set_poi_markers(markers)


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
	minimap_view_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_radar = Control.new()
	_radar.set_script(RadarView)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_radar.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_view_host.add_child(_radar)
	_setup_radar_zoom_buttons()
	_apply_radar_view_radius_from_settings()
	_connect_radar_nav()


func _connect_radar_nav() -> void:
	if _radar == null or not is_instance_valid(_radar):
		return
	if _radar.has_signal("cell_clicked") and not _radar.cell_clicked.is_connected(_on_map_nav_cell):
		_radar.cell_clicked.connect(_on_map_nav_cell)
	if _radar.has_signal("cell_pinned") and not _radar.cell_pinned.is_connected(_on_map_pin_cell):
		_radar.cell_pinned.connect(_on_map_pin_cell)


func _setup_radar_zoom_buttons() -> void:
	if minimap_view_host == null:
		return
	var row := HBoxContainer.new()
	row.name = "RadarZoomBtns"
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_constant_override("separation", 2)
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -44
	row.offset_top = -22
	row.offset_right = -2
	row.offset_bottom = -2
	var mk := func(label: String, dir: int) -> void:
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(20, 18)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.tooltip_text = "缩小" if dir > 0 else "放大"
		b.pressed.connect(func():
			var gs := GameSettingsScript.get_i()
			if gs != null and gs.has_method("cycle_radar_view_radius"):
				gs.cycle_radar_view_radius(dir)
		)
		row.add_child(b)
	# "-" = zoom out (larger radius); "+" = zoom in (smaller radius)
	mk.call("-", 1)
	mk.call("+", -1)
	minimap_view_host.add_child(row)


func _apply_radar_view_radius_from_settings() -> void:
	if _radar == null or not is_instance_valid(_radar):
		return
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var r: float = 11.0
	if "radar_view_radius" in gs:
		r = float(gs.radar_view_radius)
	if _radar.has_method("set_view_radius"):
		_radar.set_view_radius(r)
	elif "view_radius_tiles" in _radar:
		_radar.view_radius_tiles = r


func _connect_overview_nav(overview: Control) -> void:
	if overview == null or not is_instance_valid(overview):
		return
	if overview.has_signal("cell_clicked") and not overview.cell_clicked.is_connected(_on_map_nav_cell):
		overview.cell_clicked.connect(_on_map_nav_cell)
	if overview.has_signal("cell_pinned") and not overview.cell_pinned.is_connected(_on_map_pin_cell):
		overview.cell_pinned.connect(_on_map_pin_cell)


func set_map_pin(cell: Vector2i) -> void:
	_map_pin_cell = cell
	if _radar != null and is_instance_valid(_radar) and _radar.has_method("set_pin_cell"):
		_radar.set_pin_cell(cell)
	if _map_overview != null and is_instance_valid(_map_overview) and _map_overview.has_method("set_pin_cell"):
		_map_overview.set_pin_cell(cell)


func apply_map_pins_update(action: Dictionary) -> void:
	var snap_v: Variant = action.get("map_pins", action)
	var pins: Array = []
	if typeof(snap_v) == TYPE_DICTIONARY:
		var pv: Variant = snap_v.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			pins = pv
	elif typeof(snap_v) == TYPE_ARRAY:
		pins = snap_v
	_map_pins = pins.duplicate(true)
	# Personal pins render via RadarPoi kind=pin; keep legacy cyan overlay off.
	_map_pin_cell = Vector2i(-9999, -9999)
	set_map_pin(_map_pin_cell)
	_sync_map_poi_markers()


func _on_map_nav_cell(cell: Vector2i) -> void:
	var label := ""
	if _map_overview != null and is_instance_valid(_map_overview) and _map_overview.has_method("consume_nav_label"):
		label = str(_map_overview.consume_nav_label())
	if label.is_empty() and _radar != null and is_instance_valid(_radar) and _radar.has_method("consume_nav_label"):
		label = str(_radar.consume_nav_label())
	if _world_combat != null and _world_combat.has_method("request_map_move"):
		_world_combat.request_map_move(cell, label)


func _on_map_pin_cell(cell: Vector2i) -> void:
	if _world_combat != null and _world_combat.has_method("toggle_map_pin"):
		_world_combat.toggle_map_pin(cell)
	else:
		if _map_pin_cell == cell:
			set_map_pin(Vector2i(-9999, -9999))
		else:
			set_map_pin(cell)


func _on_clear_map_pins() -> void:
	if _world_combat != null and _world_combat.has_method("clear_map_pins"):
		_world_combat.clear_map_pins()
	else:
		_map_pins.clear()
		set_map_pin(Vector2i(-9999, -9999))
		append_system("已清除全部标记")


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


func _item_def(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return {}
	var srv = Net.server()
	if srv != null and srv.get("item_catalog") != null:
		var cat = srv.item_catalog
		if cat != null and cat.has_method("get_item"):
			var def: Dictionary = cat.get_item(item_id)
			if not def.is_empty() and str(def.get("id", "")).strip_edges().is_empty():
				def = def.duplicate(true)
				def["id"] = item_id
			return def
	return {}



## Plain name + catalog rarity → 「[优秀] 名称」 for tips / floats.
func _item_rarity_name_line(item_id: String, plain_name: String = "") -> String:
	var nm := plain_name.strip_edges()
	if nm.is_empty():
		nm = _item_label(item_id)
		if nm.is_empty():
			nm = item_id
	var def := _item_def(item_id)
	return ItemRarity.format_name_line(nm, ItemRarity.rarity_of_def(def))


## Resolve currently equipped def for the same paperdoll family as item_id (MockServer snapshot).
func _equipped_def_for_compare(item_id: String) -> Dictionary:
	var def := _item_def(item_id)
	var slot_key := EquipCompare.equip_slot_for_item(def)
	if slot_key.is_empty():
		return {}
	var eq_id := EquipCompare.find_equipped_id(slot_key, _server_equipment)
	if eq_id.is_empty():
		return {}
	return _item_def(eq_id)


func _equipped_enhance_for_compare(item_id: String) -> int:
	var def := _item_def(item_id)
	var slot_key := EquipCompare.equip_slot_for_item(def)
	if slot_key.is_empty():
		return 0
	var entry := EquipCompare.find_equipped_entry(slot_key, _server_equipment)
	return clampi(int(entry.get("enhance", 0)), 0, 5)


func _equip_compare_tip(item_id: String, base_lines: String, item_enhance: int = 0) -> String:
	var def := _item_def(item_id)
	if not EquipCompare.is_equipment(def):
		return base_lines
	return EquipCompare.format_compare_tip(
		def,
		_equipped_def_for_compare(item_id),
		base_lines,
		item_enhance,
		_equipped_enhance_for_compare(item_id)
	)


func _apply_inv_slot_compare_tip(cell: PanelContainer, item_id: String, locked: bool, bound: bool = false, enhance: int = 0, durability: int = -1, durability_max: int = 0) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or cell == null:
		return
	var dname := _item_rarity_name_line(item_id)
	enhance = clampi(int(enhance), 0, 5)
	if enhance > 0:
		dname = "%s +%d" % [dname, enhance]
	var base: String
	if locked:
		base = "%s\n%s\n已锁定（右键解锁）" % [dname, item_id]
	else:
		base = "%s\n%s\nCtrl+点击拆分 · 右键锁定" % [dname, item_id]
	if enhance > 0:
		base += "\n强化 +%d" % enhance
	if durability_max > 0 and durability >= 0:
		base += "\n耐久：%d/%d" % [maxi(durability, 0), durability_max]
	if bound:
		base += "\n已绑定"
	else:
		var def := _item_def(item_id)
		var bop := Equipment.is_bind_on_pickup(def)
		var boe := Equipment.is_bind_on_equip(def)
		if bop:
			base += "\n拾取绑定"
		elif boe:
			base += "\n装备后绑定"
	cell.tooltip_text = _equip_compare_tip(item_id, base, enhance)



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
	_sync_equipment_cache()
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
					var tip_name := _item_rarity_name_line(bid, dname)
					var q := _inventory_qty(bid)
					var eq_on := q <= 0 and _is_item_equipped(bid)
					var tip := "%s ×%d\n%s（右键清除）" % [tip_name, q, bid]
					if eq_on:
						tip = "%s（已装备）\n%s（右键清除）" % [tip_name, bid]
					tip = _equip_compare_tip(bid, tip)
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
	var prev_qty: Dictionary = _inv_qty_map(_server_inventory)
	var had_inv: bool = _inv_qty_known
	_server_inventory = items.duplicate(true)
	_inv_qty_known = true
	var prev_gold: int = _server_gold
	var had_wallet: bool = _gold_wallet_known
	if gold >= 0:
		_server_gold = gold
		_gold_wallet_known = true
	elif Net.server() != null and Net.server().get("inventory") != null:
		var bag = Net.server().inventory
		if bag != null and bag.has_method("get_gold"):
			_server_gold = int(bag.get_gold())
			_gold_wallet_known = true
	# Gold-gain float from inventory_update / wallet delta (loot, sell, quest, attendance…).
	# Ignore decreases (spending) and the first seed snapshot.
	if had_wallet and _server_gold > prev_gold:
		show_gold_gain_float(_server_gold - prev_gold)
	# Item-gain floats: positive qty deltas only; ignore seed + removals.
	if had_inv:
		_emit_item_gain_floats_from_delta(prev_qty, _inv_qty_map(_server_inventory))
	_refresh_inventory_gold_label()
	# Refresh open inventory window if present.
	if _windows.has("inventory") and _windows["inventory"].visible:
		_refresh_window_contents()
	# Update hotbar qty / letter avatars for item bindings.
	_refresh_hotbar_slot_visuals()
	# Keep shop sell list / gold in sync while open.
	if _shop_panel != null and _shop_panel.visible:
		_fill_shop_panel()
	# Refresh craft have/need while open.
	if _craft_panel != null and _craft_panel.visible:
		_refresh_craft_panel()


func apply_equipment_snapshot(slots: Array, bonuses: Dictionary = {}) -> void:
	_server_equipment = slots.duplicate(true)
	_server_equip_bonuses = bonuses.duplicate(true)
	if _windows.has("character") and _windows["character"].visible:
		_refresh_window_contents()
	# Equipped gear may leave bag qty 0 — still show hotbar letter.
	_refresh_hotbar_slot_visuals()


func apply_level_up(level: int, combat: Dictionary = {}, sp_gained: int = 0) -> void:
	level = maxi(level, 1)
	if not combat.is_empty():
		apply_combat_stats(combat)
	else:
		apply_combat_stats({"level": level})
	if level_label != null:
		level_label.text = "Lv.%d" % level
	if not _character.is_empty():
		_character["level"] = level
	# Infer SP gained from combat snapshot absolute skill_points when not passed.
	if sp_gained <= 0 and not combat.is_empty():
		sp_gained = int(combat.get("skill_points_gained", combat.get("sp_gained", 0)))
		if sp_gained <= 0 and combat.has("skill_points"):
			var abs_sp: int = maxi(int(combat.get("skill_points", 0)), 0)
			if abs_sp > _skill_points:
				sp_gained = abs_sp - _skill_points
	show_level_up_toast(level, sp_gained)


func show_shop(shop_id: String, title: String, listings: Array, gold: int = 0, vendor_rep: int = -1) -> void:
	ShopPanel.show_shop(self, shop_id, title, listings, gold, vendor_rep)
func apply_shop_buyback(rows: Variant) -> void:
	ShopPanel.apply_shop_buyback(self, rows)
func _add_buyback_row(parent: Node, index: int, label: String, price: int) -> void:
	ShopPanel._add_buyback_row(self, parent, index, label, price)
func hide_shop() -> void:
	ShopPanel.hide_shop(self, )
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
		if bool(_loot_panel.get_meta("loot_v2", false)):
			return
		_loot_panel.queue_free()
		_loot_panel = null
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.name = "LootWindow"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(300, 240)
	panel.default_size = Vector2(340, 300)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(300, 240)
	panel.set_meta("fixed_size", true)
	panel.set_meta("base_size", Vector2(340, 300))
	panel.set_meta("loot_v2", true)
	add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 12)
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
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_loot_close_pressed)
	head.add_child(close_btn)
	var hint := Label.new()
	hint.name = "LootHint"
	hint.text = "选择拾取或关闭（关闭将丢弃剩余）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", L2Style.COL_MUTED)
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
	take_all.pressed.connect(_on_loot_take_all_pressed)
	L2Style.style_action_button(take_all)
	bottom.add_child(take_all)
	var close2 := Button.new()
	close2.text = "关闭"
	close2.focus_mode = Control.FOCUS_NONE
	close2.pressed.connect(_on_loot_close_pressed)
	L2Style.style_action_button(close2)
	bottom.add_child(close2)
	_loot_panel = panel
	_apply_l2_chrome(panel)
	call_deferred("_place_loot_panel")


func _place_loot_panel() -> void:
	if _loot_panel == null or not is_instance_valid(_loot_panel):
		return
	var vp := get_viewport_rect().size
	var sz := Vector2(340, 300)
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
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
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
		lab.add_theme_color_override("font_color", L2Style.COL_TEXT)
		var loot_tip := _equip_compare_tip(iid, "%s ×%d" % [_item_rarity_name_line(iid, dname), qty])
		lab.tooltip_text = loot_tip
		row.tooltip_text = loot_tip
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lab)
		var take_btn := Button.new()
		take_btn.text = "拾取"
		take_btn.focus_mode = Control.FOCUS_NONE
		take_btn.custom_minimum_size = Vector2(56, 26)
		var captured := iid
		take_btn.pressed.connect(func(): _on_loot_take_pressed(captured))
		L2Style.style_compact_button(take_btn)
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
	ShopPanel._clear_shop_carts(self, )
func _ensure_shop_panel() -> void:
	ShopPanel._ensure_shop_panel(self, )
func _make_shop_tab_page(page_name: String, catalog_name: String, cart_name: String, cat_title: String, cart_title: String) -> HBoxContainer:
	return ShopPanel._make_shop_tab_page(self, page_name, catalog_name, cart_name, cat_title, cart_title)
func _make_shop_list_pane(list_name: String, heading: String) -> PanelContainer:
	return ShopPanel._make_shop_list_pane(self, list_name, heading)
func _rebuild_shop_tab_bar(panel: PanelContainer) -> void:
	ShopPanel._rebuild_shop_tab_bar(self, panel)
func _on_shop_tab(tab_id: String) -> void:
	ShopPanel._on_shop_tab(self, tab_id)
func _highlight_shop_tabs(tabs: HBoxContainer) -> void:
	ShopPanel._highlight_shop_tabs(self, tabs)
func _show_shop_tab_pages() -> void:
	ShopPanel._show_shop_tab_pages(self, )
func _place_shop_panel() -> void:
	ShopPanel._place_shop_panel(self, )
func _fill_shop_panel() -> void:
	ShopPanel._fill_shop_panel(self, )
func _clear_container(node: Node) -> void:
	if node == null:
		return
	while node.get_child_count() > 0:
		var c: Node = node.get_child(0)
		node.remove_child(c)
		c.free()


func _add_shop_catalog_row(parent: VBoxContainer, label_text: String, price: int, is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	ShopPanel._add_shop_catalog_row(self, parent, label_text, price, is_buy, item_id, display_name, unit_price)
func _fill_cart_list(parent: VBoxContainer, cart: Array, is_buy: bool) -> void:
	ShopPanel._fill_cart_list(self, parent, cart, is_buy)
func _on_shop_catalog_add(is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	ShopPanel._on_shop_catalog_add(self, is_buy, item_id, display_name, unit_price)
func _on_shop_cart_adjust(is_buy: bool, item_id: String, delta: int) -> void:
	ShopPanel._on_shop_cart_adjust(self, is_buy, item_id, delta)
func _on_shop_cart_remove(is_buy: bool, item_id: String) -> void:
	ShopPanel._on_shop_cart_remove(self, is_buy, item_id)
func _on_shop_confirm() -> void:
	ShopPanel._on_shop_confirm(self, )
func _confirm_buy_cart() -> void:
	ShopPanel._confirm_buy_cart(self, )
func _confirm_sell_cart() -> void:
	ShopPanel._confirm_sell_cart(self, )
func _shop_sellable_bag_rows() -> Array:
	return ShopPanel._shop_sellable_bag_rows(self, )
func _on_shop_buy(item_id: String) -> void:
	ShopPanel._on_shop_buy(self, item_id)
func _on_shop_sell(item_id: String) -> void:
	ShopPanel._on_shop_sell(self, item_id)
func _on_shop_sell_junk() -> void:
	ShopPanel._on_shop_sell_junk(self, )
func apply_skill_catalog(skills: Array) -> void:
	_server_skills = skills.duplicate(true)
	if _windows.has("skills") and _windows["skills"].visible:
		_refresh_window_contents()



func apply_skill_book(book: Dictionary) -> void:
	_skill_respec_armed = false
	var prev_sp: int = _skill_points
	_known_skills.clear()
	var known_v: Variant = book.get("known", book.get("known_skills", []))
	if typeof(known_v) == TYPE_ARRAY:
		for sid_v in known_v:
			var sid := str(sid_v).strip_edges()
			if not sid.is_empty():
				_known_skills[sid] = true
	_skill_points = maxi(int(book.get("skill_points", 0)), 0)
	# Always treat basic_attack as known locally for UI.
	_known_skills["basic_attack"] = true
	if _windows.has("skills") and _windows["skills"].visible:
		_fill_window("skills")
	# Level-up toast: skill_book_update often follows level_up with SP grant.
	if _level_toast_armed and _skill_points > prev_sp:
		_set_level_toast_sp_note(true)


func is_skill_known(skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	if skill_id == "basic_attack":
		return true
	if _known_skills.is_empty():
		# Before first book sync, assume starters only once catalog applied.
		return _known_skills.has(skill_id)
	return _known_skills.has(skill_id)



func apply_quest_snapshot(quests: Array) -> void:
	_detect_quest_status_toasts(quests)
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
	_refresh_quest_tracker()




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
	menu_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row.add_theme_constant_override("separation", 0)
	var panel := get_node_or_null("%MenuPanel") as Control
	if panel != null:
		if "min_size" in panel:
			panel.min_size = Vector2(52, 48)
		if "default_size" in panel:
			panel.default_size = Vector2(52, 48)
		panel.custom_minimum_size = Vector2(52, 48)
		panel.size = Vector2(52, 48)
	_menu_btn = Button.new()
	_menu_btn.name = "MenuLauncher"
	_menu_btn.tooltip_text = "菜单"
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.pressed.connect(_toggle_menu_popup)
	L2Style.style_icon_button(_menu_btn, "icon_menu.png", 40.0)
	if _menu_btn.icon == null:
		_menu_btn.text = "菜单"
	menu_row.add_child(_menu_btn)
	_ensure_menu_popup()


func _ensure_menu_popup() -> void:
	if _menu_dim == null or not is_instance_valid(_menu_dim):
		_menu_dim = ColorRect.new()
		_menu_dim.name = "MenuDim"
		_menu_dim.color = Color(0, 0, 0, 0.01)
		_menu_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_menu_dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_menu_dim.visible = false
		_menu_dim.gui_input.connect(_on_menu_dim_input)
		add_child(_menu_dim)
	if _menu_popup != null and is_instance_valid(_menu_popup):
		return
	_menu_popup = PanelContainer.new()
	_menu_popup.name = "MenuPopup"
	_menu_popup.visible = false
	_menu_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.name = "Items"
	col.add_theme_constant_override("separation", 2)
	_menu_popup.add_child(col)
	for item in MENU_ITEMS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(108, 32)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 22)
		var ic := L2Style.tex(str(item[2]))
		if ic != null:
			btn.icon = ic
		var wid := str(item[1])
		btn.pressed.connect(_on_menu_item.bind(wid))
		col.add_child(btn)
	add_child(_menu_popup)


func _on_menu_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_menu_popup()
		accept_event()


func _toggle_menu_popup() -> void:
	_ensure_menu_popup()
	if _menu_popup.visible:
		_close_menu_popup()
		return
	_menu_dim.visible = true
	_menu_dim.move_to_front()
	_menu_popup.visible = true
	_menu_popup.move_to_front()
	call_deferred("_place_menu_popup")


func _close_menu_popup() -> void:
	if _menu_popup != null:
		_menu_popup.visible = false
	if _menu_dim != null:
		_menu_dim.visible = false


func _place_menu_popup() -> void:
	if _menu_popup == null or not _menu_popup.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := _menu_popup.get_combined_minimum_size()
	if sz.x < 108.0:
		sz.x = 108.0
	_menu_popup.size = sz
	var anchor := Vector2(vp.x - sz.x - 12.0, vp.y - sz.y - 64.0)
	if _menu_btn != null and is_instance_valid(_menu_btn):
		var r := _menu_btn.get_global_rect()
		anchor = Vector2(r.position.x + r.size.x - sz.x, r.position.y - sz.y - 6.0)
	anchor.x = clampf(anchor.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
	anchor.y = clampf(anchor.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	_menu_popup.global_position = anchor


func _on_menu_item(wid: String) -> void:
	_close_menu_popup()
	if wid == "party":
		_toggle_party_panel()
	elif wid == "warehouse":
		_toggle_warehouse_panel()
	elif wid == "friends":
		_toggle_friends_panel()
	elif wid == "mail":
		_toggle_mail_panel()
	elif wid == "craft":
		_toggle_craft_panel()
	elif wid == "emote":
		_toggle_emote_panel()
	elif wid == "titles":
		_toggle_titles_panel()
	elif wid == "guild":
		_toggle_guild_panel()
	elif wid == "auction":
		_toggle_auction_panel()
	else:
		_toggle_window(wid)


func _connect_game_settings() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	if not gs.changed.is_connected(_on_game_settings_changed):
		gs.changed.connect(_on_game_settings_changed)
	_on_game_settings_changed()


func _on_game_settings_changed() -> void:
	var gs := GameSettingsScript.get_i()
	if gs != null and gs.has_method("apply_hud_scale"):
		gs.apply_hud_scale(self)
	_apply_radar_view_radius_from_settings()
	_refresh_quest_tracker()


func show_death_dialog() -> void:
	_build_death_dialog()
	if _death_panel:
		_death_panel.visible = true
		_death_panel.move_to_front()
		call_deferred("_place_death_dialog")


func hide_death_dialog() -> void:
	if _death_panel:
		_death_panel.visible = false


func _build_death_dialog() -> void:
	if _death_panel != null and is_instance_valid(_death_panel):
		return
	_death_panel = PanelContainer.new()
	_death_panel.name = "DeathDialog"
	_death_panel.visible = false
	_death_panel.custom_minimum_size = Vector2(320, 180)
	L2Style.apply_panel(_death_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 16)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 18)
	_death_panel.add_child(marg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	marg.add_child(col)
	var title := Label.new()
	title.text = "你死了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	L2Style.style_title(title)
	col.add_child(title)
	var body := Label.new()
	body.text = "就地复活：半血\n回城复活：安全点满血"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", L2Style.COL_TEXT)
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var here_btn := Button.new()
	here_btn.name = "HereBtn"
	here_btn.text = "就地复活"
	here_btn.focus_mode = Control.FOCUS_NONE
	here_btn.custom_minimum_size = Vector2(110, 28)
	L2Style.style_action_button(here_btn)
	here_btn.pressed.connect(func():
		if _world_combat != null and _world_combat.has_method("request_respawn"):
			_world_combat.request_respawn("here")
		hide_death_dialog()
	)
	row.add_child(here_btn)
	var town_btn := Button.new()
	town_btn.name = "TownBtn"
	town_btn.text = "回城复活"
	town_btn.focus_mode = Control.FOCUS_NONE
	town_btn.custom_minimum_size = Vector2(110, 28)
	L2Style.style_action_button(town_btn)
	town_btn.pressed.connect(func():
		if _world_combat != null and _world_combat.has_method("request_respawn"):
			_world_combat.request_respawn("town")
		hide_death_dialog()
	)
	row.add_child(town_btn)
	add_child(_death_panel)
	call_deferred("_place_death_dialog")


func _place_death_dialog() -> void:
	if _death_panel == null or not is_instance_valid(_death_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_death_panel.size = Vector2(320, 190)
	_death_panel.global_position = Vector2((vp.x - 320.0) * 0.5, (vp.y - 190.0) * 0.4)


func _build_inspect_panel() -> void:
	if _inspect_panel != null and is_instance_valid(_inspect_panel):
		return
	_inspect_panel = _make_window("查看", Vector2(360, 320), "top_center", Vector2(0, 80))
	_apply_l2_chrome(_inspect_panel)
	_inspect_panel.visible = false
	_inspect_panel.name = "InspectPanel"


func _show_inspect(pid: String, dname: String) -> void:
	_build_inspect_panel()
	var ch := {"name": dname, "level": 1, "gender": "female"}
	var eq: Array = []
	if _world_combat != null and _world_combat.has_method("inspect_remote"):
		var snap: Dictionary = _world_combat.inspect_remote(pid)
		ch["name"] = str(snap.get("name", dname))
		ch["level"] = int(snap.get("level", 1))
		ch["gender"] = str(snap.get("gender", "female"))
		if snap.has("class_id") and str(snap.get("class_id", "")) != "":
			ch["class_id"] = str(snap.get("class_id"))
		var eq_v: Variant = snap.get("equipment", [])
		if typeof(eq_v) == TYPE_ARRAY:
			eq = eq_v
	var body: VBoxContainer = _inspect_panel.get_meta("body")
	for c in body.get_children():
		c.queue_free()
	var saved_eq: Array = _server_equipment.duplicate(true)
	_server_equipment = eq
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	body.add_child(main)
	var doll_panel := PanelContainer.new()
	doll_panel.name = "DollPanel"
	doll_panel.add_theme_stylebox_override("panel", L2Style.inner_box())
	main.add_child(doll_panel)
	_build_paperdoll(doll_panel, ch)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(stats)
	_add_label(stats, str(ch.get("name", "?")), 14, L2Style.COL_TITLE)
	_add_label(stats, "Lv.%d" % int(ch.get("level", 1)), 13, L2Style.COL_TEXT)
	var g := str(ch.get("gender", ""))
	if g != "":
		_add_label(stats, "性别  %s" % ("男" if g == "male" else "女"), 12, L2Style.COL_TEXT)
	if str(ch.get("class_id", "")) != "":
		_add_label(stats, "职业  %s" % str(ch.get("class_id")), 12, L2Style.COL_TEXT)
	if eq.is_empty():
		_add_label(stats, "装备  （无）", 12, L2Style.COL_MUTED)
	_add_label(stats, "属性未公开", 11, L2Style.COL_MUTED)
	_server_equipment = saved_eq
	for slot in _inspect_panel.find_children("*", "PanelContainer", true, false):
		if slot.get_script() != null and str(slot.get_script().resource_path).ends_with("equip_slot.gd"):
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_panel.visible = true
	_inspect_panel.move_to_front()
	call_deferred("_place_window", _inspect_panel)


func _build_quest_tracker() -> void:
	if _quest_tracker != null and is_instance_valid(_quest_tracker):
		return
	_quest_tracker = PanelContainer.new()
	_quest_tracker.name = "QuestTracker"
	_quest_tracker.set_script(HudDrag)
	_quest_tracker.screen_margin = 4.0
	_quest_tracker.min_size = Vector2(180, 48)
	_quest_tracker.default_size = Vector2(220, 120)
	_quest_tracker.initial_dock = "none"
	_quest_tracker.resizable = false
	_quest_tracker.visible = false
	L2Style.apply_panel(_quest_tracker)
	add_child(_quest_tracker)
	if _quest_tracker.has_signal("layout_changed"):
		_quest_tracker.layout_changed.connect(func():
			var gs := GameSettingsScript.get_i()
			if gs != null:
				gs.save_window_layout("quest_tracker", _quest_tracker.global_position, _quest_tracker.visible)
		)
	call_deferred("_place_quest_tracker")


func _default_quest_tracker_pos() -> Vector2:
	## Prefer just under the minimap (top-right); fall back to viewport top-right.
	var tracker_w := 220.0
	var mini := get_node_or_null("MinimapPanel") as Control
	if mini != null and is_instance_valid(mini):
		var mx: float = mini.global_position.x + mini.size.x - tracker_w
		var my: float = mini.global_position.y + mini.size.y + 4.0
		return Vector2(maxf(mx, 4.0), maxf(my, 4.0))
	var vp := get_viewport_rect().size
	return Vector2(maxf(vp.x - tracker_w - 4.0, 4.0), 176.0)


func _place_quest_tracker() -> void:
	if _quest_tracker == null or not is_instance_valid(_quest_tracker):
		return
	var gs := GameSettingsScript.get_i()
	var placed := false
	if gs != null:
		var lay: Dictionary = gs.window_layout("quest_tracker")
		if not lay.is_empty():
			_quest_tracker.global_position = Vector2(float(lay.get("x", 8)), float(lay.get("y", 176)))
			placed = true
	if not placed:
		_quest_tracker.global_position = _default_quest_tracker_pos()
	if _quest_tracker.find_child("TrackerBody", true, false) == null:
		var marg := MarginContainer.new()
		marg.add_theme_constant_override("margin_left", 8)
		marg.add_theme_constant_override("margin_top", 6)
		marg.add_theme_constant_override("margin_right", 8)
		marg.add_theme_constant_override("margin_bottom", 6)
		_quest_tracker.add_child(marg)
		var col := VBoxContainer.new()
		col.name = "TrackerBody"
		col.add_theme_constant_override("separation", 4)
		marg.add_child(col)
	_refresh_quest_tracker()


func _refresh_quest_tracker() -> void:
	if _quest_tracker == null or not is_instance_valid(_quest_tracker):
		return
	var col := _quest_tracker.find_child("TrackerBody", true, false) as VBoxContainer
	if col == null:
		return
	for c in col.get_children():
		c.queue_free()
	var active: Array = QuestTrackerUtil.active_quests(_server_quests, QuestTrackerUtil.MAX_TRACKED)
	if active.is_empty():
		_quest_tracker.visible = false
		return
	if not GameSettingsScript.flag("show_quest_tracker", true):
		_quest_tracker.visible = false
		return
	_quest_tracker.visible = true
	# Header row with close (hides via settings flag).
	var head := HBoxContainer.new()
	col.add_child(head)
	var head_lab := Label.new()
	head_lab.text = "任务追踪"
	head_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_lab.add_theme_font_size_override("font_size", 11)
	head_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
	head.add_child(head_lab)
	var close_b := Button.new()
	close_b.text = "×"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.custom_minimum_size = Vector2(22, 22)
	close_b.pressed.connect(func():
		var gs := GameSettingsScript.get_i()
		if gs != null:
			gs.set_flag("show_quest_tracker", false)
		_quest_tracker.visible = false
	)
	head.add_child(close_b)
	for q in active:
		var qid := str(q.get("id", "")).strip_edges()
		var title := str(q.get("title", "")).strip_edges()
		if title.is_empty():
			title = qid if not qid.is_empty() else "任务"
		var st := _normalize_quest_status(str(q.get("status", "")))
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 4)
		col.add_child(title_row)
		var title_btn := Button.new()
		if st == "ready":
			title_btn.text = "%s [可交付]" % title
		else:
			title_btn.text = title
		title_btn.focus_mode = Control.FOCUS_NONE
		title_btn.flat = true
		title_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_btn.add_theme_font_size_override("font_size", 12)
		title_btn.add_theme_color_override("font_color", L2Style.COL_TITLE)
		title_btn.add_theme_color_override("font_hover_color", L2Style.COL_GOLD)
		title_btn.tooltip_text = "左键前往 / 右键详情"
		if not qid.is_empty():
			title_btn.gui_input.connect(_on_tracked_quest_gui_input.bind(qid, -1))
			# Flat button still emits pressed on LMB; route through path-or-journal.
			title_btn.pressed.connect(_on_tracked_quest_activate.bind(qid, -1))
		title_row.add_child(title_btn)
		var nav_preview: Dictionary = _resolve_tracked_quest_nav(qid, -1)
		if bool(nav_preview.get("ok", false)):
			var go_btn := Button.new()
			go_btn.text = "去"
			go_btn.focus_mode = Control.FOCUS_NONE
			go_btn.flat = true
			go_btn.custom_minimum_size = Vector2(22, 18)
			go_btn.add_theme_font_size_override("font_size", 11)
			go_btn.add_theme_color_override("font_color", L2Style.COL_GOLD)
			go_btn.tooltip_text = "前往：%s" % str(nav_preview.get("label", ""))
			go_btn.pressed.connect(_path_to_tracked_quest.bind(qid, -1))
			title_row.add_child(go_btn)
		var objs: Variant = q.get("objectives", [])
		if typeof(objs) != TYPE_ARRAY:
			continue
		var oi := 0
		for o in objs:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var obj_row := HBoxContainer.new()
			obj_row.add_theme_constant_override("separation", 4)
			col.add_child(obj_row)
			var line := Button.new()
			line.text = "  %s" % QuestTrackerUtil.format_objective(o)
			line.focus_mode = Control.FOCUS_NONE
			line.flat = true
			line.alignment = HORIZONTAL_ALIGNMENT_LEFT
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_theme_font_size_override("font_size", 11)
			line.add_theme_color_override("font_color", L2Style.COL_TEXT)
			line.add_theme_color_override("font_hover_color", L2Style.COL_GOLD)
			line.tooltip_text = "左键前往 / 右键详情"
			if not qid.is_empty():
				line.gui_input.connect(_on_tracked_quest_gui_input.bind(qid, oi))
				line.pressed.connect(_on_tracked_quest_activate.bind(qid, oi))
			obj_row.add_child(line)
			oi += 1
	call_deferred("_fit_quest_tracker")


func _fit_quest_tracker() -> void:
	if _quest_tracker == null or not is_instance_valid(_quest_tracker):
		return
	if not _quest_tracker.visible:
		return
	var ms := _quest_tracker.get_combined_minimum_size()
	_quest_tracker.size = Vector2(maxf(ms.x, 180.0), maxf(ms.y, 48.0))


func _open_tracked_quest(quest_id: String) -> void:
	## Open journal detail drawer for a tracked quest.
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	_quest_tab = "active"
	_selected_quest_id = quest_id
	if not (_windows.has("quest") and _windows["quest"] != null and _windows["quest"].visible):
		_toggle_window("quest")
	else:
		_fill_window("quest")
	_open_quest_drawer(quest_id, true)


func _quest_nav_world_ctx() -> Dictionary:
	if _world_combat != null and _world_combat.has_method("get_quest_nav_context"):
		var ctx_v: Variant = _world_combat.get_quest_nav_context()
		if typeof(ctx_v) == TYPE_DICTIONARY:
			return ctx_v
	# Headless / unbound fallback: empty context (resolver returns ok=false → journal).
	return {"npcs": [], "gather": [], "fish": [], "warps": []}


func _find_tracked_quest_row(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	for q in _server_quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if str(q.get("id", "")).strip_edges() == quest_id:
			return q
	return {}


func _resolve_tracked_quest_nav(quest_id: String, objective_index: int = -1) -> Dictionary:
	var row: Dictionary = _find_tracked_quest_row(quest_id)
	if row.is_empty():
		return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}
	return QuestTrackerUtil.resolve_quest_nav(row, _quest_nav_world_ctx(), objective_index)


func _path_to_tracked_quest(quest_id: String, objective_index: int = -1) -> void:
	var nav: Dictionary = _resolve_tracked_quest_nav(quest_id, objective_index)
	if not bool(nav.get("ok", false)):
		return
	var cell: Vector2i = nav.get("cell", Vector2i.ZERO)
	if typeof(cell) != TYPE_VECTOR2I:
		cell = Vector2i(int(nav.get("x", 0)), int(nav.get("y", 0)))
	var label := str(nav.get("label", "")).strip_edges()
	if _world_combat != null and _world_combat.has_method("request_map_move"):
		_world_combat.request_map_move(cell, label)
	else:
		append_system("前往：%s" % (label if label != "" else "(%d, %d)" % [cell.x, cell.y]))


## Left-click: pathfind when a nav cell resolves, else open journal.
func _on_tracked_quest_activate(quest_id: String, objective_index: int = -1) -> void:
	var nav: Dictionary = _resolve_tracked_quest_nav(quest_id, objective_index)
	if bool(nav.get("ok", false)):
		_path_to_tracked_quest(quest_id, objective_index)
		return
	_open_tracked_quest(quest_id)


## Right-click always opens journal detail (even when left-click paths).
func _on_tracked_quest_gui_input(event: InputEvent, quest_id: String, objective_index: int = -1) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		_open_tracked_quest(quest_id)


func apply_party_invite(action: Dictionary) -> void:
	var dir := str(action.get("direction", ""))
	var status := str(action.get("status", ""))
	if dir == "in" and status == "pending":
		_show_invite_dialog(str(action.get("invite_id", "")), str(action.get("name", "玩家")))
	elif dir == "in" and status != "pending":
		_hide_invite_dialog()
	if _party_panel != null and _party_panel.visible:
		_refresh_party_panel()



func show_loot_roll(action: Dictionary) -> void:
	hide_loot_roll({})
	_loot_roll_id = str(action.get("roll_id", action.get("id", ""))).strip_edges()
	var iname := str(action.get("name", action.get("item_id", "物品"))).strip_edges()
	var qty := int(action.get("qty", 1))
	_loot_roll_panel = PanelContainer.new()
	_loot_roll_panel.name = "LootRollDialog"
	_loot_roll_panel.custom_minimum_size = Vector2(280, 130)
	L2Style.apply_panel(_loot_roll_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 14)
	marg.add_theme_constant_override("margin_top", 12)
	marg.add_theme_constant_override("margin_right", 14)
	marg.add_theme_constant_override("margin_bottom", 12)
	_loot_roll_panel.add_child(marg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	marg.add_child(col)
	_loot_roll_label = Label.new()
	var qty_s := (" ×%d" % qty) if qty > 1 else ""
	_loot_roll_label.text = "掷骰：%s%s\n需求 / 贪婪 / 放弃" % [iname, qty_s]
	_loot_roll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loot_roll_label.add_theme_color_override("font_color", L2Style.COL_TEXT)
	col.add_child(_loot_roll_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for pair in [["需求", "need"], ["贪婪", "greed"], ["放弃", "pass"]]:
		var btn := Button.new()
		btn.text = str(pair[0])
		btn.focus_mode = Control.FOCUS_NONE
		var choice := str(pair[1])
		btn.pressed.connect(func():
			_submit_loot_roll(choice)
		)
		row.add_child(btn)
	add_child(_loot_roll_panel)
	_loot_roll_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_loot_roll_panel.position = Vector2(-140, 72)
	_loot_roll_panel.move_to_front()


func apply_loot_roll_choice(action: Dictionary) -> void:
	# Optional: could grey out after self voted; keep panel until resolve.
	pass


func hide_loot_roll(_action: Dictionary = {}) -> void:
	if _loot_roll_panel != null and is_instance_valid(_loot_roll_panel):
		_loot_roll_panel.queue_free()
	_loot_roll_panel = null
	_loot_roll_id = ""
	_loot_roll_label = null


func _submit_loot_roll(choice: String) -> void:
	var rid := _loot_roll_id
	hide_loot_roll({})
	if _world_combat != null and _world_combat.has_method("request_loot_roll"):
		_world_combat.request_loot_roll(choice, rid)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_loot_roll"):
		var result: Dictionary = srv.try_loot_roll(choice, rid)
		if typeof(result.get("actions", null)) == TYPE_ARRAY and _world_combat != null and _world_combat.has_method("_apply_server_actions"):
			_world_combat._apply_server_actions(result["actions"])


func _show_invite_dialog(invite_id: String, from_name: String) -> void:
	_hide_invite_dialog()
	_invite_panel = PanelContainer.new()
	_invite_panel.name = "InviteDialog"
	_invite_panel.custom_minimum_size = Vector2(260, 120)
	L2Style.apply_panel(_invite_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 14)
	marg.add_theme_constant_override("margin_top", 12)
	marg.add_theme_constant_override("margin_right", 14)
	marg.add_theme_constant_override("margin_bottom", 12)
	_invite_panel.add_child(marg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	marg.add_child(col)
	var lab := Label.new()
	lab.text = "【%s】邀请你组队" % from_name
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_color_override("font_color", L2Style.COL_TEXT)
	col.add_child(lab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var acc := Button.new()
	acc.text = "接受"
	acc.focus_mode = Control.FOCUS_NONE
	acc.pressed.connect(func():
		_respond_invite(invite_id, true)
	)
	row.add_child(acc)
	var dec := Button.new()
	dec.text = "拒绝"
	dec.focus_mode = Control.FOCUS_NONE
	dec.pressed.connect(func():
		_respond_invite(invite_id, false)
	)
	row.add_child(dec)
	add_child(_invite_panel)
	_invite_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_invite_panel.position = Vector2(-130, -60)
	_invite_panel.move_to_front()


func _respond_invite(invite_id: String, accept: bool) -> void:
	_hide_invite_dialog()
	if _world_combat != null and _world_combat.has_method("request_party_invite_respond"):
		_world_combat.request_party_invite_respond(invite_id, accept)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_invite_respond"):
		var result: Dictionary = srv.try_party_invite_respond(invite_id, accept)
		_apply_party_result_locally(result)


func _hide_invite_dialog() -> void:
	if _invite_panel != null and is_instance_valid(_invite_panel):
		_invite_panel.queue_free()
	_invite_panel = null


func _finish_keybind(keycode: int) -> void:
	var action := _waiting_bind
	_waiting_bind = ""
	var gs := GameSettingsScript.get_i()
	if gs == null or action.is_empty():
		return
	var conflict := str(gs.set_keybind(action, keycode))
	if conflict == "reserved":
		append_system("该键不能绑定。")
	elif conflict != "":
		append_system("与【%s】冲突。" % conflict)
	if _windows.has("system") and _windows["system"].visible:
		_fill_window("system")


func _connect_window_layout_signals() -> void:
	for id in _windows.keys():
		var p: Control = _windows[id]
		if p != null and p.has_signal("layout_changed"):
			if not p.layout_changed.is_connected(_on_window_layout.bind(str(id))):
				p.layout_changed.connect(_on_window_layout.bind(str(id)))
		if p != null and not p.visibility_changed.is_connected(_on_window_layout.bind(str(id))):
			p.visibility_changed.connect(_on_window_layout.bind(str(id)))


func _on_window_layout(id: String) -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var p: Control = _windows.get(id)
	if p == null:
		return
	gs.save_window_layout(id, p.global_position, p.visible)


func _restore_window_layouts() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	for id in _windows.keys():
		var lay: Dictionary = gs.window_layout(str(id))
		if lay.is_empty():
			continue
		var p: Control = _windows[id]
		if p == null:
			continue
		p.global_position = Vector2(float(lay.get("x", p.global_position.x)), float(lay.get("y", p.global_position.y)))

func _build_windows() -> void:
	_windows["character"] = _make_window("角色状态", Vector2(560, 420), "top_left", Vector2(200, 90))
	_lock_character_window(_windows["character"] as PanelContainer)
	_windows["inventory"] = _make_window("背包", Vector2(420, 500), "top_right", Vector2(200, 40))
	_lock_inventory_window(_windows["inventory"] as PanelContainer)
	_windows["skills"] = _make_window("技能与魔法", Vector2(400, 420), "top_center", Vector2(0, 100))
	_lock_skills_window(_windows["skills"] as PanelContainer)
	_windows["quest"] = _make_window("任务", Vector2(380, 430), "bottom_right", Vector2(40, 80))
	_lock_quest_window(_windows["quest"] as PanelContainer)
	_windows["map"] = _make_window("地图", Vector2(460, 580), "top_center", Vector2(0, 36))
	_apply_l2_chrome(_windows["map"] as PanelContainer)
	_windows["system"] = _make_window("系统设置", Vector2(500, 520), "bottom_center", Vector2(0, 80))
	_lock_system_window(_windows["system"] as PanelContainer)
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
	_apply_l2_chrome(panel)
	_ensure_inventory_gold_bar(panel)


func _lock_character_window(panel: PanelContainer) -> void:
	## Fixed-size character / paperdoll window (L2 chrome).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(560, 420))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)


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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 80)
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var row := HBoxContainer.new()
	row.name = "GoldBar"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad_l := Control.new()
	pad_l.custom_minimum_size = Vector2(48, 0)
	pad_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad_l)
	var tag := Label.new()
	tag.text = "Adena"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_gold_amount(tag)
	row.add_child(tag)
	var amt := Label.new()
	amt.name = "GoldAmount"
	amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_gold_amount(amt)
	row.add_child(amt)
	var pad_r := Control.new()
	pad_r.custom_minimum_size = Vector2(48, 0)
	pad_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad_r)
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


func _lock_system_window(panel: PanelContainer) -> void:
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(500, 520))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var tabs := vbox.get_node_or_null("SystemTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "SystemTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("system_tabs", tabs)
	_rebuild_system_tab_bar(panel)


func _rebuild_system_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("system_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in SYSTEM_TABS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(90, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_system_tab.bind(str(item[1])))
		tabs.add_child(btn)
	_highlight_system_tabs(tabs)


func _on_system_tab(tab_id: String) -> void:
	tab_id = tab_id.strip_edges()
	if tab_id.is_empty() or tab_id == _system_tab:
		return
	_system_tab = tab_id
	var panel: PanelContainer = _windows.get("system")
	if panel != null:
		_highlight_system_tabs(panel.get_meta("system_tabs", null) as HBoxContainer)
	if panel != null and panel.visible:
		_fill_window("system")


func _highlight_system_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn := tabs.get_child(i) as Button
		if btn == null or i >= SYSTEM_TABS.size():
			continue
		L2Style.style_tab_button(btn, str(SYSTEM_TABS[i][1]) == _system_tab)


func _lock_skills_window(panel: PanelContainer) -> void:
	## Fixed-size skills: same lock as bag; tab bar sits above Scroll (not inside body).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(400, 420))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)
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
	var base: Vector2 = panel.get_meta("base_size", Vector2(380, 430))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)
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


func _apply_l2_chrome(panel: PanelContainer) -> void:
	## Ornate panel + title strip + close icon. Idempotent. Works without a named Scroll.
	if panel == null:
		return
	L2Style.apply_panel(panel)
	var marg := panel.get_child(0) as MarginContainer
	if marg != null:
		marg.add_theme_constant_override("margin_left", 8)
		marg.add_theme_constant_override("margin_top", 6)
		marg.add_theme_constant_override("margin_right", 8)
		marg.add_theme_constant_override("margin_bottom", 14)
	var vbox: VBoxContainer = null
	if marg != null and marg.get_child_count() > 0:
		vbox = marg.get_child(0) as VBoxContainer
	if vbox == null:
		return
	vbox.add_theme_constant_override("separation", 4)
	var title_bar := vbox.get_node_or_null("TitleBar") as PanelContainer
	var head: HBoxContainer = null
	if title_bar != null:
		head = title_bar.get_child(0) as HBoxContainer if title_bar.get_child_count() > 0 else null
	else:
		for c in vbox.get_children():
			if c is HBoxContainer:
				head = c
				break
		if head != null:
			title_bar = PanelContainer.new()
			title_bar.name = "TitleBar"
			title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title_bar.custom_minimum_size = Vector2(0, 30)
			title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
			var idx := head.get_index()
			vbox.remove_child(head)
			title_bar.add_child(head)
			vbox.add_child(title_bar)
			vbox.move_child(title_bar, idx)
	if head != null:
		head.add_theme_constant_override("separation", 4)
		if head.get_child_count() > 0:
			L2Style.style_title(head.get_child(0) as Label)
		if head.get_child_count() > 1:
			L2Style.style_close(head.get_child(head.get_child_count() - 1) as Button)
		for c in head.get_children():
			if c is Label and str(c.name).find("Gold") >= 0:
				L2Style.style_gold_amount(c)


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
		btn.custom_minimum_size = Vector2(140, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		L2Style.style_tab_button(btn, id == _quest_tab)


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
		btn.custom_minimum_size = Vector2(100, 30)
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
		L2Style.style_tab_button(btn, id == _skills_tab)


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
	if _inspect_panel != null and _inspect_panel.visible:
		_inspect_panel.visible = false
		return true
	if _invite_panel != null and _invite_panel.visible:
		_hide_invite_dialog()
		return true
	if _npc_chat != null and _npc_chat.visible:
		_npc_chat.visible = false
		return true
	if _shop_panel != null and _shop_panel.visible:
		hide_shop()
		return true
	if _party_panel != null and _party_panel.visible:
		_party_panel.visible = false
		return true
	if _friends_panel != null and _friends_panel.visible:
		_friends_panel.visible = false
		return true
	if _guild_panel != null and _guild_panel.visible:
		_guild_panel.visible = false
		return true
	if _auction_panel != null and _auction_panel.visible:
		_auction_panel.visible = false
		return true
	if _daily_panel != null and _daily_panel.visible:
		_daily_panel.visible = false
		return true
	if _mail_panel != null and _mail_panel.visible:
		_mail_panel.visible = false
		return true
	if _emote_panel != null and _emote_panel.visible:
		_emote_panel.visible = false
		return true
	if _combat_log_panel != null and _combat_log_panel.visible:
		_combat_log_panel.visible = false
		return true
	if _craft_panel != null and _craft_panel.visible:
		_craft_panel.visible = false
		return true
	if _warehouse_panel != null and _warehouse_panel.visible:
		_warehouse_panel.visible = false
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

func _fill_character(body: VBoxContainer, ch: Dictionary, use_server_eq: bool = true) -> void:
	if use_server_eq:
		_sync_equipment_cache()
	_sync_attr_cache_from_server()
	var st: Dictionary = L2Mock.char_stats(ch)
	var bon: Dictionary = _server_equip_bonuses
	var show_lv: int = int(_server_combat.get("level", ch.get("level", 1)))
	var main := HBoxContainer.new()
	main.name = "CharMain"
	main.add_theme_constant_override("separation", 12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var doll_panel := PanelContainer.new()
	doll_panel.name = "DollPanel"
	doll_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	doll_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	doll_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	doll_panel.add_theme_stylebox_override("panel", L2Style.inner_box())
	main.add_child(doll_panel)
	_build_paperdoll(doll_panel, ch)
	var stats_wrap := PanelContainer.new()
	stats_wrap.name = "StatsPanel"
	stats_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	main.add_child(stats_wrap)
	var stats := VBoxContainer.new()
	stats.name = "StatsCol"
	stats.add_theme_constant_override("separation", 3)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_wrap.add_child(stats)
	_add_label(stats, "%s  ·  %s  ·  Lv.%d" % [str(ch.get("name", "?")), str(st.get("class_label", "")), show_lv], 13, L2Style.COL_TITLE)
	var exp_cur: int = int(_server_combat.get("exp", st.get("exp", 0)))
	var exp_next: int = int(_server_combat.get("exp_to_next", 0))
	if exp_next > 0:
		_add_label(stats, "EXP  %d / %d" % [exp_cur, exp_next], 12, L2Style.COL_TEXT)
	else:
		_add_label(stats, "EXP  %d" % exp_cur, 12, L2Style.COL_TEXT)
	_add_label(stats, "SP  %d" % int(st.get("sp", 0)), 12, L2Style.COL_TEXT)
	var adena_v: int = maxi(_server_gold, 0) if _server_gold >= 0 else int(st.get("adena", 0))
	_add_label(stats, "Adena  %d" % adena_v, 12, L2Style.COL_GOLD)
	var _guild_chip := str(_guild_state.get("name", "")).strip_edges()
	if _guild_chip.is_empty():
		_guild_chip = str(st.get("clan", "无"))
	_add_label(stats, "血盟  %s" % _guild_chip, 12, L2Style.COL_TEXT)
	_add_label(stats, "— 属性 —", 11, L2Style.COL_MUTED)
	var attrs_v: Variant = _server_combat.get("attrs", {})
	var attrs: Dictionary = attrs_v if typeof(attrs_v) == TYPE_DICTIONARY else {}
	var unspent_ap: int = maxi(int(_server_combat.get("attr_points", 0)), 0)
	_add_label(stats, "属性点：%d" % unspent_ap, 12, L2Style.COL_GOLD if unspent_ap > 0 else L2Style.COL_TEXT)
	_add_attr_row(stats, "力量", "str", int(attrs.get("str", 0)), unspent_ap)
	_add_attr_row(stats, "敏捷", "agi", int(attrs.get("agi", 0)), unspent_ap)
	_add_attr_row(stats, "体质", "vit", int(attrs.get("vit", 0)), unspent_ap)
	_add_attr_row(stats, "智力", "intel", int(attrs.get("intel", 0)), unspent_ap)
	var respec_btn := Button.new()
	respec_btn.text = "重置属性（30金）"
	respec_btn.focus_mode = Control.FOCUS_NONE
	respec_btn.disabled = (int(attrs.get("str", 0)) + int(attrs.get("agi", 0)) + int(attrs.get("vit", 0)) + int(attrs.get("intel", 0))) <= 0
	respec_btn.pressed.connect(_on_attr_respec_pressed)
	stats.add_child(respec_btn)
	_add_label(stats, "— 战斗 —", 11, L2Style.COL_MUTED)
	var base_patk := int(_server_combat.get("atk", st.get("p_atk", 0)))
	var base_pdef := int(_server_combat.get("def", st.get("p_def", 0)))
	var p_atk := base_patk + int(bon.get("p_atk", 0))
	var m_atk := int(st.get("m_atk", 0)) + int(bon.get("m_atk", 0))
	var p_def := base_pdef + int(bon.get("p_def", 0))
	var m_def := int(st.get("m_def", 0)) + int(bon.get("m_def", 0))
	_add_stat_line(stats, "P.Atk", p_atk, "M.Atk", m_atk)
	_add_stat_line(stats, "P.Def", p_def, "M.Def", m_def)
	_add_label(stats, "CP / HP / MP", 11, L2Style.COL_MUTED)
	_add_label(stats, "%d  /  %d  /  %d" % [int(_cp_max), int(_hp_max), int(_mp_max)], 12, L2Style.COL_VALUE)
	if not bon.is_empty():
		_add_label(stats, "— 装备加成 —", 11, L2Style.COL_MUTED)
		var parts: Array[String] = []
		for k in bon.keys():
			var v: int = int(bon[k])
			if v != 0:
				parts.append("%s%+d" % [str(k), v])
		if parts.is_empty():
			_add_label(stats, "无", 12, L2Style.COL_MUTED)
		else:
			var line := ""
			for i in range(parts.size()):
				if i > 0:
					line += "   "
				line += parts[i]
			_add_label(stats, line, 12, L2Style.COL_GOLD)
	var panel: PanelContainer = _windows.get("character") as PanelContainer
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)


func _add_stat_line(parent: Node, k1: String, v1: int, k2: String, v2: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	_add_label(row, "%s  %d" % [k1, v1], 12, L2Style.COL_VALUE).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(row, "%s  %d" % [k2, v2], 12, L2Style.COL_VALUE).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_attr_row(parent: Node, label_zh: String, key: String, value: int, unspent: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var lbl := _add_label(row, "%s  %d" % [label_zh, value], 12, L2Style.COL_VALUE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.custom_minimum_size = Vector2(28, 22)
	plus.disabled = unspent <= 0
	plus.pressed.connect(_on_attr_plus_pressed.bind(key))
	row.add_child(plus)


func _on_attr_plus_pressed(stat_key: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_allocate_attr"):
		append_system("无法分配属性点。")
		return
	var result: Dictionary = srv.try_allocate_attr(stat_key, 1)
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "system_message":
			append_system(str(a.get("text", "")))
		elif t == "attr_update":
			apply_attr_update(a)
		elif t == "set_stat":
			_apply_server_stat_action(a)


func _on_attr_respec_pressed() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_attr_respec"):
		append_system("无法重置属性。")
		return
	var result: Dictionary = srv.try_attr_respec()
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "system_message":
			append_system(str(a.get("text", "")))
		elif t == "attr_update":
			apply_attr_update(a)
		elif t == "set_stat":
			_apply_server_stat_action(a)
		elif t == "inventory_update":
			apply_inventory_snapshot(a.get("items", []), int(a.get("gold", -1)))


func _apply_server_stat_action(a: Dictionary) -> void:
	var st: Dictionary = {}
	for k in ["hp", "hp_max", "mp", "mp_max", "level", "exp", "exp_to_next", "atk", "def", "attr_points", "rested_exp", "rested_exp_max"]:
		if a.has(k):
			st[k] = int(a.get(k, 0))
	if a.has("attrs"):
		st["attrs"] = a.get("attrs", {})
	if not st.is_empty():
		apply_combat_stats(st)


func apply_attr_update(action: Dictionary) -> void:

	## Snapshot apply for character open / attr_update opcode.
	if action.has("attr_points"):
		_server_combat["attr_points"] = maxi(int(action.get("attr_points", 0)), 0)
	if action.has("attrs") and typeof(action.get("attrs")) == TYPE_DICTIONARY:
		_server_combat["attrs"] = (action.get("attrs") as Dictionary).duplicate(true)
	var combat_v: Variant = action.get("combat", {})
	if typeof(combat_v) == TYPE_DICTIONARY and not (combat_v as Dictionary).is_empty():
		apply_combat_stats(combat_v)
	elif _windows.has("character") and _windows["character"].visible:
		_refresh_window_contents()


func _sync_attr_cache_from_server() -> void:
	## Pull attrs / combat scalars from MockServer when opening character.
	var srv = Net.server()
	if srv == null or srv.get("combat_stats") == null:
		return
	var cs = srv.combat_stats
	if cs.has_method("ensure_attrs"):
		cs.ensure_attrs()
	if cs.has_method("snapshot_player_stats"):
		var snap: Dictionary = cs.snapshot_player_stats()
		for k in snap.keys():
			_server_combat[str(k)] = snap[k]


func _sync_equipment_cache() -> void:
	## Refresh from MockServer when opening / rebuilding character window.
	var srv = Net.server()
	if srv != null and srv.get("equipment") != null and srv.equipment.has_method("snapshot"):
		_server_equipment = srv.equipment.snapshot()
		if srv.equipment.has_method("total_bonuses"):
			_server_equip_bonuses = srv.equipment.total_bonuses()


func _equipment_map() -> Dictionary:
	## slot_id -> {item_id, name, durability, durability_max, icon_index?, icon_ref?}
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
			"durability": int(it.get("durability", -1)),
			"durability_max": int(it.get("durability_max", -1)),
			"icon_index": int(it.get("icon_index", -1)),
			"icon": str(it.get("icon", "")).strip_edges(),
			"icon_ref": str(it.get("icon_ref", "")).strip_edges(),
		}
	return m


func _build_paperdoll(host: Control, ch: Dictionary) -> void:
	## Slots around the live character (gender + equipped MV layers).
	const CELL := 38
	const CANVAS := Vector2(224, 300)
	var canvas := Control.new()
	canvas.name = "DollCanvas"
	canvas.custom_minimum_size = CANVAS
	canvas.size = CANVAS
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(canvas)
	var sil := TextureRect.new()
	sil.name = "Silhouette"
	sil.texture = _paperdoll_texture(ch)
	sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sil.offset_left = 38
	sil.offset_right = -38
	sil.offset_top = 18
	sil.offset_bottom = -6
	canvas.add_child(sil)
	# Left column jewelry/armor, right column weapons/rings, head/feet on the figure.
	var positions: Dictionary = {
		"head": Vector2(93, 4),
		"earring_l": Vector2(4, 16),
		"earring_r": Vector2(182, 16),
		"necklace": Vector2(4, 62),
		"weapon_main": Vector2(182, 62),
		"chest": Vector2(4, 108),
		"weapon_off": Vector2(182, 108),
		"hands": Vector2(4, 154),
		"ring_r": Vector2(182, 154),
		"legs": Vector2(4, 200),
		"ring_l": Vector2(182, 200),
		"feet": Vector2(93, 256),
	}
	var eq_map := _equipment_map()
	for sid in positions.keys():
		var cell := PanelContainer.new()
		cell.set_script(EquipSlot)
		cell.position = positions[sid]
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.size = Vector2(CELL, CELL)
		var entry: Dictionary = eq_map.get(sid, {})
		var iid := str(entry.get("item_id", "")).strip_edges()
		var nm := str(entry.get("name", "")).strip_edges()
		if nm.is_empty() and not iid.is_empty():
			nm = _item_label(iid)
		if not iid.is_empty():
			nm = _item_rarity_name_line(iid, nm)
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
		var dur := int(entry.get("durability", -1))
		var dur_max := int(entry.get("durability_max", -1))
		cell.setup(sid, iid, nm, hint, iix, iref, dur, dur_max)
		if not iid.is_empty():
			var eq_def := _item_def(iid)
			var enh_pd := clampi(int(entry.get("enhance", 0)), 0, 5)
			if enh_pd > 0:
				var tip0 := str(cell.tooltip_text)
				if not tip0.is_empty():
					# Prefix display name line with +N when present
					var tip_lines := tip0.split("\n")
					if tip_lines.size() > 0 and not str(tip_lines[0]).strip_edges().is_empty():
						tip_lines[0] = "%s +%d" % [str(tip_lines[0]).strip_edges(), enh_pd]
						cell.tooltip_text = "\n".join(tip_lines)
				cell.tooltip_text = str(cell.tooltip_text) + "\n强化 +%d" % enh_pd
			var bonus_lines := EquipCompare.format_bonus_lines(eq_def, enh_pd)
			if not bonus_lines.is_empty():
				cell.tooltip_text = str(cell.tooltip_text) + "\n" + "\n".join(bonus_lines)
			if bool(entry.get("bound", false)):
				cell.tooltip_text = str(cell.tooltip_text) + "\n已绑定"
		cell.equip_requested.connect(_on_equip_slot_equip)
		cell.unequip_requested.connect(_on_equip_slot_unequip)
		canvas.add_child(cell)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP


func _paperdoll_texture(ch: Dictionary) -> Texture2D:
	var catalog = null
	var srv = Net.server()
	if srv != null:
		catalog = srv.get("item_catalog")
	var tex: Texture2D = PaperdollLook.standing_texture(ch, _server_equipment, catalog)
	if tex != null:
		return tex
	return L2Style.tex("paperdoll.png")


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
	_sync_equipment_cache()
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
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	body.add_child(tools)
	for spec in [["全部", "all"], ["消耗", "consumable"], ["装备", "equipment"], ["材料", "material"]]:
		var fb := Button.new()
		fb.text = str(spec[0])
		fb.focus_mode = Control.FOCUS_NONE
		fb.custom_minimum_size = Vector2(48, 24)
		var fid := str(spec[1])
		L2Style.style_compact_button(fb)
		if _inv_filter == fid:
			fb.modulate = Color(1.15, 1.05, 0.7)
		fb.pressed.connect(func():
			_inv_filter = fid
			_fill_window("inventory")
		)
		tools.add_child(fb)
	var sort_b := Button.new()
	sort_b.text = "排序"
	sort_b.focus_mode = Control.FOCUS_NONE
	sort_b.custom_minimum_size = Vector2(48, 24)
	sort_b.pressed.connect(func():
		if _world_combat != null and _world_combat.has_method("request_inventory_sort"):
			_world_combat.request_inventory_sort()
		else:
			var srv_s = Net.server()
			if srv_s != null and srv_s.has_method("try_inventory_sort"):
				_apply_equip_result_locally(srv_s.try_inventory_sort())
	)
	tools.add_child(sort_b)
	var search := LineEdit.new()
	search.name = "InvSearch"
	search.placeholder_text = "搜索物品…"
	search.text = _inv_search_query
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(0, 28)
	search.focus_mode = Control.FOCUS_CLICK
	search.text_changed.connect(_on_inv_search_text_changed)
	body.add_child(search)
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
		if not _inv_row_matches_filter(it):
			continue
		packed.append(it)
	for i in range(ui_slots):
		var cell := PanelContainer.new()
		cell.set_script(InvSlot)
		cell.custom_minimum_size = cell_sz
		grid.add_child(cell)
		if i >= capacity:
			cell.clear_slot()
			cell.set_disabled(true)
		elif i < packed.size():
			var it2: Dictionary = packed[i]
			var iid := str(it2.get("id", ""))
			var qty: int = int(it2.get("qty", 0))
			cell.set_disabled(false)
			cell.setup(iid, qty, _item_label(iid), i, _item_icon_index(iid), _item_icon_ref(iid))
			var locked_flag := bool(it2.get("locked", false))
			var bound_flag := bool(it2.get("bound", false))
			var enhance_flag := clampi(int(it2.get("enhance", 0)), 0, 5)
			var dur_flag := int(it2.get("durability", -1))
			var dur_max_flag := int(it2.get("durability_max", 0))
			cell.set_meta("locked", locked_flag)
			cell.set_meta("bound", bound_flag)
			cell.set_meta("enhance", enhance_flag)
			if dur_max_flag > 0:
				cell.set_meta("durability", dur_flag)
				cell.set_meta("durability_max", dur_max_flag)
			_apply_inv_slot_compare_tip(cell, iid, locked_flag, bound_flag, enhance_flag, dur_flag, dur_max_flag)
			if not cell.activated.is_connected(_on_inventory_item_pressed):
				cell.activated.connect(_on_inventory_item_pressed)
			if cell.has_signal("split_requested") and not cell.split_requested.is_connected(_on_inventory_split):
				cell.split_requested.connect(_on_inventory_split)
			if cell.has_signal("lock_toggled") and not cell.lock_toggled.is_connected(_on_inventory_lock):
				cell.lock_toggled.connect(_on_inventory_lock)
		else:
			cell.set_disabled(false)
			cell.clear_slot()
		cell.custom_minimum_size = cell_sz
		# Force STOP so HudDraggable pass-through never swallows InvSlot clicks.
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_inv_search_visibility(grid)
	# Keep fixed window size even after content rebuild.
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)
	# Sync wallet from MockServer when opening bag (authoritative).
	if srv != null and srv.get("inventory") != null and srv.inventory.has_method("get_gold"):
		_server_gold = int(srv.inventory.get_gold())
	_ensure_inventory_gold_bar(panel)
	_refresh_inventory_gold_label(panel)


func _inv_row_matches_filter(it: Dictionary) -> bool:
	if _inv_filter == "all" or _inv_filter.strip_edges() == "":
		return true
	var t := str(it.get("type", "")).strip_edges().to_lower()
	if t.is_empty():
		var iid := str(it.get("id", ""))
		var srv = Net.server()
		if srv != null and srv.get("item_catalog") != null:
			var def: Dictionary = srv.item_catalog.get_item(iid)
			t = str(def.get("type", "")).to_lower()
	match _inv_filter:
		"consumable":
			return t in ["consumable", "potion"]
		"equipment":
			return t in ["weapon", "armor", "equipment", "equip"]
		"material":
			return t == "material"
		_:
			return true


func _on_inv_search_text_changed(new_text: String) -> void:
	_inv_search_query = str(new_text)
	var panel: PanelContainer = _windows.get("inventory") as PanelContainer
	if panel == null:
		return
	var grid := panel.find_child("InvGrid", true, false) as GridContainer
	if grid != null:
		_apply_inv_search_visibility(grid)


func _apply_inv_search_visibility(grid: GridContainer) -> void:
	## Client-only: hide non-matching filled slots; hide empty/locked while query active.
	if grid == null:
		return
	var q := _inv_search_query.strip_edges()
	var filtering := not q.is_empty()
	for cell in grid.get_children():
		if cell == null or not is_instance_valid(cell):
			continue
		if not filtering:
			cell.visible = true
			continue
		var iid := ""
		var dname := ""
		if "item_id" in cell:
			iid = str(cell.item_id)
		if "display_name" in cell:
			dname = str(cell.display_name)
		if iid.is_empty():
			# Empty usable or locked/capacity cells — hide while filtering.
			cell.visible = false
			continue
		cell.visible = InvSearchUtil.matches(q, iid, dname)


func _on_inventory_split(item_id: String, qty: int) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or qty <= 1:
		return
	_qty_mode = "split"
	_show_drop_qty_dialog(item_id, qty - 1)
	if _drop_qty_label != null:
		_drop_qty_label.text = "拆分：%s（最多 %d）" % [_item_label(item_id), qty - 1]


func _on_inventory_lock(item_id: String) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var on := true
	for it in _server_inventory:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == item_id:
			on = not bool(it.get("locked", false))
			break
	if _world_combat != null and _world_combat.has_method("request_inventory_lock"):
		_world_combat.request_inventory_lock(item_id, on)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_inventory_lock"):
			_apply_equip_result_locally(srv.try_inventory_lock(item_id, on))


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
		_qty_mode = "drop"
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
	if _qty_mode != "split":
		_qty_mode = "drop"
	if _drop_qty_label != null:
		if _qty_mode == "split":
			_drop_qty_label.text = "拆分：%s（最多 %d）" % [_item_label(item_id), max_qty]
		else:
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
	L2Style.apply_panel(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 28)
	marg.add_theme_constant_override("margin_top", 24)
	marg.add_theme_constant_override("margin_right", 28)
	marg.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(marg)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	marg.add_child(root)
	var title := Label.new()
	title.text = "丢弃数量"
	L2Style.style_title(title)
	root.add_child(title)
	var info := Label.new()
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(220, 0)
	info.add_theme_color_override("font_color", L2Style.COL_TEXT)
	root.add_child(info)
	_drop_qty_label = info
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var qty_lab := Label.new()
	qty_lab.text = "数量"
	qty_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
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
	L2Style.style_action_button(cancel)
	btns.add_child(cancel)
	var ok := Button.new()
	ok.text = "确定"
	ok.pressed.connect(_on_drop_qty_confirm)
	L2Style.style_action_button(ok)
	btns.add_child(ok)
	panel.custom_minimum_size = Vector2(340, 220)
	add_child(panel)
	_drop_qty_panel = panel


func _on_drop_qty_cancel() -> void:
	_drop_qty_item_id = ""
	_qty_mode = "drop"
	if _drop_qty_panel != null:
		_drop_qty_panel.visible = false


func _on_drop_qty_confirm() -> void:
	var iid := _drop_qty_item_id.strip_edges()
	var q: int = 1
	if _drop_qty_spin != null:
		q = int(_drop_qty_spin.value)
	var mode := _qty_mode
	_on_drop_qty_cancel()
	if iid.is_empty():
		return
	var have: int = _inventory_qty(iid)
	if have > 0:
		q = clampi(q, 1, have)
	else:
		q = maxi(q, 1)
	if mode == "split":
		if _world_combat != null and _world_combat.has_method("request_inventory_split"):
			_world_combat.request_inventory_split(iid, q)
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_inventory_split"):
				_apply_equip_result_locally(srv.try_inventory_split(iid, q))
		return
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
	## Grid + tabs (tabs live outside Scroll). SP + Learn row above grid.
	var panel: PanelContainer = _windows.get("skills") as PanelContainer
	if panel != null:
		_rebuild_skills_tab_bar(panel)
	var skills: Array = _server_skills
	if skills.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_skill_catalog"):
			skills = srv.snapshot_skill_catalog()
			_server_skills = skills.duplicate(true)
	# SP / Learn header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(head)
	var sp_lbl := Label.new()
	sp_lbl.name = "SkillPointsLabel"
	sp_lbl.text = "技能点：%d" % _skill_points
	sp_lbl.add_theme_color_override("font_color", L2Style.COL_TEXT)
	sp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp_lbl)
	var learn_btn := Button.new()
	learn_btn.name = "LearnSkillButton"
	learn_btn.text = "学习"
	learn_btn.focus_mode = Control.FOCUS_NONE
	learn_btn.disabled = true
	learn_btn.pressed.connect(_on_learn_skill_pressed)
	head.add_child(learn_btn)
	var respec_btn := Button.new()
	respec_btn.name = "RespecSkillButton"
	respec_btn.text = "重置技能"
	respec_btn.focus_mode = Control.FOCUS_NONE
	respec_btn.tooltip_text = "重置已学技能并返还技能点（花费 50 金币）。保留普通攻击。"
	respec_btn.pressed.connect(_on_respec_skill_pressed)
	head.add_child(respec_btn)
	var sel_lbl := Label.new()
	sel_lbl.name = "SelectedSkillHint"
	sel_lbl.text = ""
	sel_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
	sel_lbl.add_theme_font_size_override("font_size", 11)
	body.add_child(sel_lbl)
	_update_skills_learn_row(learn_btn, sel_lbl)
	var filtered: Array = []
	for s in skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if _normalize_skill_category(s) == _skills_tab:
			filtered.append(s)
	var cell_sz := _grid_cell_size()
	var cols := SKILL_COLS
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if filtered.is_empty():
		var empty := Label.new()
		empty.text = "（暂无技能）"
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
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
			grid.add_child(cell)
			cell.setup(sid, sname, cat, i, six, sref)
			var known := _is_skill_known(sid)
			if cell.has_method("set_known"):
				cell.set_known(known)
			cell.activated.connect(_on_skill_slot_pressed)
			cell.custom_minimum_size = cell_sz
		_refresh_skill_window_cooldowns()
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		call_deferred("_lock_window_size", panel)



func _on_skill_slot_pressed(skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	_selected_skill_id = skill_id
	_refresh_skills_learn_controls()
	if not _is_skill_known(skill_id):
		var sname := _skill_display_name(skill_id)
		var def := _skill_def(skill_id)
		var need_lv := maxi(int(def.get("learn_level", 1)), 1)
		var cost := maxi(int(def.get("sp_cost", 1)), 0)
		append_system("未学会【%s】（需要 Lv.%d · %d 技能点）。选中后点「学习」。" % [sname, need_lv, cost])
		return
	if _is_passive_skill(skill_id):
		var sname2 := _skill_display_name(skill_id)
		var extra := ""
		for s in _server_skills:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			if str(s.get("id", "")) != skill_id:
				continue
			var atk_b := int(s.get("atk_bonus", 0))
			var def_b := int(s.get("def_bonus", 0))
			if atk_b != 0:
				extra = "（攻击+%d）" % atk_b
			elif def_b != 0:
				extra = "（防御+%d）" % def_b
			break
		append_system("被动已生效 · 【%s】%s" % [sname2, extra])
		return
	if _world_combat != null and _world_combat.has_method("request_use_skill"):
		_world_combat.request_use_skill(skill_id)
	else:
		append_system("无法施放：%s" % skill_id)



func _on_skill_row_pressed(skill_id: String) -> void:
	## Compat alias for older call sites.
	_on_skill_slot_pressed(skill_id)


func _is_skill_known(skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	if skill_id == "basic_attack":
		return true
	return _known_skills.has(skill_id)


func _skill_def(skill_id: String) -> Dictionary:
	for s in _server_skills:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == skill_id:
			return s
	var srv = Net.server()
	if srv != null and srv.has_method("skill_def"):
		return srv.skill_def(skill_id)
	return {}


func _player_level_for_skills() -> int:
	var lv := int(_server_combat.get("level", 0))
	if lv <= 0 and not _character.is_empty():
		lv = int(_character.get("level", 1))
	return maxi(lv, 1)


func _can_learn_selected() -> bool:
	var sid := _selected_skill_id.strip_edges()
	if sid.is_empty() or _is_skill_known(sid):
		return false
	var def := _skill_def(sid)
	if def.is_empty():
		return false
	var need_lv := maxi(int(def.get("learn_level", 1)), 1)
	var cost := maxi(int(def.get("sp_cost", 1)), 0)
	if bool(def.get("starter", false)):
		need_lv = 1
		cost = 0
	if _player_level_for_skills() < need_lv:
		return false
	if _skill_points < cost:
		return false
	return true


func _update_skills_learn_row(learn_btn: Button, sel_lbl: Label) -> void:
	var sid := _selected_skill_id.strip_edges()
	if sid.is_empty():
		sel_lbl.text = "选择技能后可学习"
		learn_btn.disabled = true
		return
	var def := _skill_def(sid)
	var sname := str(def.get("name", _skill_display_name(sid)))
	if _is_skill_known(sid):
		sel_lbl.text = "已学会：%s" % sname
		learn_btn.disabled = true
		return
	var need_lv := maxi(int(def.get("learn_level", 1)), 1)
	var cost := maxi(int(def.get("sp_cost", 1)), 0)
	sel_lbl.text = "选中：%s · 需要 Lv.%d · %d SP" % [sname, need_lv, cost]
	learn_btn.disabled = not _can_learn_selected()


func _refresh_skills_learn_controls() -> void:
	if not _windows.has("skills"):
		return
	var panel: PanelContainer = _windows["skills"]
	if panel == null or not panel.visible:
		return
	# Controls live inside scroll body; find by name.
	var learn_btn: Button = panel.find_child("LearnSkillButton", true, false) as Button
	var sel_lbl: Label = panel.find_child("SelectedSkillHint", true, false) as Label
	var sp_lbl: Label = panel.find_child("SkillPointsLabel", true, false) as Label
	if sp_lbl != null:
		sp_lbl.text = "技能点：%d" % _skill_points
	if learn_btn != null and sel_lbl != null:
		_update_skills_learn_row(learn_btn, sel_lbl)


func _on_learn_skill_pressed() -> void:
	var sid := _selected_skill_id.strip_edges()
	if sid.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_learn_skill"):
		_world_combat.request_learn_skill(sid)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_learn_skill"):
			var result: Dictionary = srv.try_learn_skill(sid)
			var acts_v: Variant = result.get("actions", [])
			if typeof(acts_v) == TYPE_ARRAY and _world_combat != null and _world_combat.has_method("apply_server_actions"):
				_world_combat.apply_server_actions(acts_v)
			elif typeof(acts_v) == TYPE_ARRAY:
				for a in acts_v:
					if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
						append_system(str(a.get("text", "")))
					elif typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "skill_book_update":
						apply_skill_book(a)


func _on_respec_skill_pressed() -> void:
	if not _skill_respec_armed:
		_skill_respec_armed = true
		append_system("再点一次以确认重置技能（花费 50 金币）。")
		return
	_skill_respec_armed = false
	if _world_combat != null and _world_combat.has_method("request_skill_respec"):
		_world_combat.request_skill_respec()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_skill_respec"):
		var result: Dictionary = srv.try_skill_respec()
		var acts_v: Variant = result.get("actions", [])
		if typeof(acts_v) == TYPE_ARRAY and _world_combat != null and _world_combat.has_method("apply_server_actions"):
			_world_combat.apply_server_actions(acts_v)
		elif typeof(acts_v) == TYPE_ARRAY:
			for a in acts_v:
				if typeof(a) != TYPE_DICTIONARY:
					continue
				var t := str(a.get("type", ""))
				if t == "system_message":
					append_system(str(a.get("text", "")))
				elif t == "skill_book_update":
					apply_skill_book(a)
				elif t == "skill_respec":
					apply_skill_respec(a)
				elif t == "inventory_update" and a.has("gold"):
					_server_gold = int(a.get("gold", _server_gold))


## Clear hotbar skill bindings that reference forgotten skill ids (client-only hotkeys).
func apply_skill_respec(action: Dictionary) -> void:
	var cleared_ids: Dictionary = {}
	var cleared_v: Variant = action.get("cleared", [])
	if typeof(cleared_v) == TYPE_ARRAY:
		for c in cleared_v:
			var cid := str(c).strip_edges()
			if not cid.is_empty():
				cleared_ids[cid] = true
	if cleared_ids.is_empty():
		# Also scrub any skill binding not currently known.
		for k in _hotbar_bindings.keys():
			var v: Variant = _hotbar_bindings[k]
			if typeof(v) != TYPE_DICTIONARY:
				continue
			if str(v.get("kind", "")) != "skill":
				continue
			var sid := str(v.get("id", "")).strip_edges()
			if sid.is_empty() or sid == "basic_attack":
				continue
			if not _is_skill_known(sid):
				cleared_ids[sid] = true
	var removed := false
	var keys: Array = _hotbar_bindings.keys()
	for k in keys:
		var bv: Variant = _hotbar_bindings[k]
		if typeof(bv) != TYPE_DICTIONARY:
			continue
		if str(bv.get("kind", "")) != "skill":
			continue
		var bid := str(bv.get("id", "")).strip_edges()
		if cleared_ids.has(bid) or (not bid.is_empty() and bid != "basic_attack" and not _is_skill_known(bid)):
			_hotbar_bindings.erase(k)
			removed = true
	if removed:
		_persist_hotbar_to_session()
		_refresh_hotbar_slot_visuals()


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
		_add_label(body, empty_msg, 12, L2Style.COL_MUTED)
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
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	L2Style.style_row_button(btn, selected)
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
	L2Style.apply_panel(drawer)
	add_child(drawer)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var title_bar := PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.custom_minimum_size = Vector2(0, 30)
	title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
	vbox.add_child(title_bar)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(head)
	var title_l := Label.new()
	title_l.name = "DrawerTitle"
	title_l.text = "详情"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_title(title_l)
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_on_quest_drawer_close)
	L2Style.style_close(close_btn)
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
	_add_label(_quest_drawer_body, _quest_status_label(str(selected.get("status", "in_progress"))), 12, L2Style.COL_GOLD)
	var desc := str(selected.get("desc", "")).strip_edges()
	if not desc.is_empty():
		_add_label(_quest_drawer_body, desc, 12, L2Style.COL_TEXT)
	_add_label(_quest_drawer_body, "目标", 12, L2Style.COL_MUTED)
	var objs_v: Variant = selected.get("objectives", [])
	if typeof(objs_v) == TYPE_ARRAY and not (objs_v as Array).is_empty():
		for o in objs_v:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var ot := str(o.get("text", ""))
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			var done := cur >= mx
			var col := Color(0.55, 0.85, 0.55) if done else L2Style.COL_TEXT
			_add_label(_quest_drawer_body, "· %s（%d / %d）" % [ot, cur, mx], 12, col)
	else:
		_add_label(_quest_drawer_body, "· （无）", 12, L2Style.COL_MUTED)
	var rewards := str(selected.get("rewards", "")).strip_edges()
	_add_label(_quest_drawer_body, "奖励", 12, L2Style.COL_MUTED)
	_add_label(_quest_drawer_body, rewards if not rewards.is_empty() else "（无）", 12, L2Style.COL_GOLD)
	var qstatus := _normalize_quest_status(str(selected.get("status", "")))
	if qstatus == "ready":
		var turn_btn := Button.new()
		turn_btn.text = "交付任务"
		turn_btn.focus_mode = Control.FOCUS_NONE
		turn_btn.pressed.connect(_on_quest_turn_in.bind(_selected_quest_id))
		L2Style.style_action_button(turn_btn)
		_quest_drawer_body.add_child(turn_btn)
	elif qstatus == "completed":
		_add_label(_quest_drawer_body, "（已完成）", 12, Color(0.55, 0.75, 0.55))
	if qstatus == "in_progress" or qstatus == "ready":
		var ab_btn := Button.new()
		ab_btn.text = "确认放弃" if _abandon_confirm_id == _selected_quest_id else "放弃任务"
		ab_btn.focus_mode = Control.FOCUS_NONE
		ab_btn.pressed.connect(_on_quest_abandon.bind(_selected_quest_id))
		L2Style.style_action_button(ab_btn)
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
	_add_label(mount, "Shift+左键 / 右键：设/清个人标记（最多3）", 11, Color(0.7, 0.72, 0.68))
	var pin_row := HBoxContainer.new()
	pin_row.add_theme_constant_override("separation", 8)
	mount.add_child(pin_row)
	var clear_pins := Button.new()
	clear_pins.text = "清除标记"
	clear_pins.focus_mode = Control.FOCUS_NONE
	clear_pins.custom_minimum_size = Vector2(100, 26)
	clear_pins.pressed.connect(_on_clear_map_pins)
	pin_row.add_child(clear_pins)

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
	_connect_overview_nav(overview)
	if overview.has_method("set_pin_cell"):
		overview.set_pin_cell(_map_pin_cell)
	_sync_map_poi_markers()
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
	var gs := GameSettingsScript.get_i()
	match _system_tab:
		"audio":
			_fill_system_audio(body, gs)
		"game":
			_fill_system_game(body, gs)
		"keys":
			_fill_system_keys(body, gs)
		"system":
			_fill_system_nav(body)
		_:
			_fill_system_video(body, gs)


func _fill_system_video(body: VBoxContainer, gs: Node) -> void:
	_add_label(body, "画面设置", 14, L2Style.COL_TITLE)
	if gs == null:
		_add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_setting_row(body, "显示模式", _make_mode_option(gs))
	var res_opt := _make_res_option(gs)
	_add_setting_row(body, "分辨率", res_opt)
	res_opt.disabled = str(gs.window_mode) != "windowed"
	_add_check(body, "垂直同步", bool(gs.vsync), func(on: bool): gs.set_vsync(on))
	_add_setting_row(body, "帧率上限", _make_fps_option(gs))
	_add_setting_row(body, "界面缩放", _make_scale_option(gs))
	_add_reset_row(body, gs)


func _fill_system_audio(body: VBoxContainer, gs: Node) -> void:
	_add_label(body, "声音设置", 14, L2Style.COL_TITLE)
	if gs == null:
		_add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_volume_row(body, "主音量", int(gs.master_volume), func(v: int): gs.set_master_volume(v))
	_add_volume_row(body, "音乐", int(gs.bgm_volume), func(v: int): gs.set_bgm_volume(v))
	_add_volume_row(body, "音效", int(gs.sfx_volume), func(v: int): gs.set_sfx_volume(v))
	_add_volume_row(body, "环境", int(gs.ambient_volume), func(v: int): gs.set_ambient_volume(v))
	_add_check(body, "静音", bool(gs.mute), func(on: bool): gs.set_mute(on))
	_add_reset_row(body, gs)


func _fill_system_game(body: VBoxContainer, gs: Node) -> void:
	_add_label(body, "游戏设置", 14, L2Style.COL_TITLE)
	_gather_level_label = _add_label(
		body,
		"采集 Lv.%d" % maxi(_gather_level, 1),
		11,
		L2Style.COL_MUTED
	)
	if gs == null:
		_add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_check(body, "显示 NPC 名称", bool(gs.show_npc_names), func(on: bool): gs.set_flag("show_npc_names", on))
	_add_check(body, "显示玩家名称", bool(gs.show_player_names), func(on: bool): gs.set_flag("show_player_names", on))
	_add_setting_row(body, "名牌距离", _make_nameplate_distance_spin(gs))
	_add_setting_row(body, "挂机提醒(分钟)", _make_afk_warn_minutes_spin(gs))
	_add_check(body, "显示血条", bool(gs.show_hp_bars), func(on: bool): gs.set_flag("show_hp_bars", on))
	_add_check(body, "显示伤害数字", bool(gs.show_damage_numbers), func(on: bool): gs.set_flag("show_damage_numbers", on))
	_add_check(body, "显示 DPS 计量", bool(gs.show_dps_meter), func(on: bool):
		gs.set_flag("show_dps_meter", on)
		_refresh_dps_meter_visibility()
	)
	_add_check(body, "聊天时间戳", bool(gs.show_chat_timestamps), func(on: bool):
		gs.set_flag("show_chat_timestamps", on)
		_rebuild_chat_log()
	)
	_add_check(body, "宠物助战", bool(gs.pet_assist) if "pet_assist" in gs else true, func(on: bool):
		gs.set_flag("pet_assist", on)
	)
	_add_check(body, "显示经验飘字", bool(gs.show_exp_floats), func(on: bool): gs.set_flag("show_exp_floats", on))
	_add_check(body, "显示金币飘字", bool(gs.show_gold_floats), func(on: bool): gs.set_flag("show_gold_floats", on))
	_add_check(body, "显示物品飘字", bool(gs.show_item_floats), func(on: bool): gs.set_flag("show_item_floats", on))
	_add_check(body, "暴击震屏", bool(gs.screen_shake), func(on: bool): gs.set_flag("screen_shake", on))
	_add_check(body, "战斗镜头偏移", bool(gs.combat_camera_frame), func(on: bool): gs.set_flag("combat_camera_frame", on))
	_add_check(body, "始终奔跑", bool(gs.always_run), func(on: bool): gs.set_flag("always_run", on))
	_add_check(body, "天气特效", bool(gs.weather_fx), func(on: bool): gs.set_flag("weather_fx", on))
	_add_check(body, "自动拾取", bool(gs.auto_pickup), func(on: bool): gs.set_flag("auto_pickup", on))
	_add_setting_row(body, "自动拾取过滤", _make_auto_pickup_filter_option(gs))
	_add_check(body, "低血自动喝药", bool(gs.auto_potion_hp), func(on: bool):
		if gs.has_method("set_auto_potion_hp"):
			gs.set_auto_potion_hp(on)
		else:
			gs.set_flag("auto_potion_hp", on)
	)
	_add_setting_row(body, "自动喝药 HP%", _make_auto_potion_pct_spin(gs, true))
	_add_check(body, "低蓝自动喝药", bool(gs.auto_potion_mp), func(on: bool):
		if gs.has_method("set_auto_potion_mp"):
			gs.set_auto_potion_mp(on)
		else:
			gs.set_flag("auto_potion_mp", on)
	)
	_add_setting_row(body, "自动喝药 MP%", _make_auto_potion_pct_spin(gs, false))
	_add_check(body, "锁定 HUD", bool(gs.hud_locked), func(on: bool): gs.set_flag("hud_locked", on))
	_add_check(body, "任务追踪", bool(gs.show_quest_tracker), func(on: bool):
		gs.set_flag("show_quest_tracker", on)
		_refresh_quest_tracker()
	)
	_add_setting_row(body, "镜头缩放", _make_zoom_option(gs))
	_add_setting_row(body, "小地图缩放", _make_radar_zoom_option(gs))
	var reset_lay := Button.new()
	reset_lay.text = "重置窗口位置"
	reset_lay.focus_mode = Control.FOCUS_NONE
	reset_lay.pressed.connect(func():
		gs.clear_window_layouts()
		append_system("窗口位置已重置，下次打开按默认停靠。")
	)
	body.add_child(reset_lay)
	_add_reset_row(body, gs)


func _fill_system_keys(body: VBoxContainer, gs: Node) -> void:
	_add_label(body, "按键绑定", 14, L2Style.COL_TITLE)
	if gs == null:
		_add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	if not _waiting_bind.is_empty():
		_add_label(body, "请按下新按键…", 12, L2Style.COL_GOLD)
	for item in GameSettingsScript.KEYBIND_ACTIONS:
		var action := str(item[1])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.text = str(item[0])
		lab.custom_minimum_size = Vector2(96, 0)
		lab.add_theme_color_override("font_color", L2Style.COL_TEXT)
		row.add_child(lab)
		var btn := Button.new()
		btn.text = OS.get_keycode_string(int(gs.key_for(action)))
		if _waiting_bind == action:
			btn.text = "…"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(100, 26)
		btn.pressed.connect(func():
			_waiting_bind = action
			_fill_window("system")
		)
		row.add_child(btn)
		body.add_child(row)
	_add_reset_row(body, gs)


func _make_auto_pickup_filter_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var modes: Array = GameSettingsScript.AUTO_PICKUP_FILTERS
	var cur := str(gs.auto_pickup_filter)
	var sel := 0
	for i in range(modes.size()):
		opt.add_item(str(modes[i][0]), i)
		opt.set_item_metadata(i, str(modes[i][1]))
		if str(modes[i][1]) == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_auto_pickup_filter(str(opt.get_item_metadata(idx)))
	)
	return opt



func _make_auto_potion_pct_spin(gs: Node, for_hp: bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 90
	spin.step = 1
	spin.rounded = true
	var cur: int = int(gs.auto_potion_hp_pct) if for_hp else int(gs.auto_potion_mp_pct)
	spin.value = clampi(cur, 1, 90)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if for_hp:
			if gs.has_method("set_auto_potion_hp_pct"):
				gs.set_auto_potion_hp_pct(int(v))
		else:
			if gs.has_method("set_auto_potion_mp_pct"):
				gs.set_auto_potion_mp_pct(int(v))
	)
	return spin

func _make_nameplate_distance_spin(gs: Node) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 4
	spin.max_value = 32
	spin.step = 1
	spin.rounded = true
	var cur: int = 12
	if gs != null and "nameplate_distance" in gs:
		cur = int(gs.nameplate_distance)
	spin.value = clampi(cur, 4, 32)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if gs != null and gs.has_method("set_nameplate_distance"):
			gs.set_nameplate_distance(int(v))
	)
	return spin


func _make_afk_warn_minutes_spin(gs: Node) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 60
	spin.step = 1
	spin.rounded = true
	spin.suffix = "(0=关)"
	var cur: int = 10
	if gs != null and "afk_warn_minutes" in gs:
		cur = int(gs.afk_warn_minutes)
	spin.value = AfkWarnUtil.clamp_minutes(cur)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if gs != null and gs.has_method("set_afk_warn_minutes"):
			gs.set_afk_warn_minutes(int(v))
			# Reflect clamp (1–4 → 5) back into the spin.
			var clamped := int(gs.afk_warn_minutes)
			if int(spin.value) != clamped:
				spin.value = clamped
	)
	return spin


func _make_zoom_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var zooms: Array = GameSettingsScript.CAMERA_ZOOMS
	var cur := float(gs.camera_zoom)
	var sel := 1
	for i in range(zooms.size()):
		var z: float = float(zooms[i])
		opt.add_item("%d%%" % int(round(z * 100.0)), i)
		opt.set_item_metadata(i, z)
		if is_equal_approx(z, cur):
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_camera_zoom(float(opt.get_item_metadata(idx)))
	)
	return opt


func _make_radar_zoom_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var radii: Array = GameSettingsScript.RADAR_VIEW_RADII
	var cur: int = 11
	if gs != null and "radar_view_radius" in gs:
		cur = int(gs.radar_view_radius)
	var sel := 1
	for i in range(radii.size()):
		var r: int = int(radii[i])
		var label := "%d 格" % r
		match r:
			8:
				label = "近 (8)"
			11:
				label = "默认 (11)"
			16:
				label = "中 (16)"
			22:
				label = "远 (22)"
		opt.add_item(label, i)
		opt.set_item_metadata(i, r)
		if r == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		if gs != null and gs.has_method("set_radar_view_radius"):
			gs.set_radar_view_radius(int(opt.get_item_metadata(idx)))
	)
	return opt


func _fill_system_nav(body: VBoxContainer) -> void:
	_add_label(body, "系统选项", 14, L2Style.COL_TITLE)
	var mk := func(text: String, cb: Callable) -> void:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(cb)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size = Vector2(160, 28)
		body.add_child(b)
	mk.call("内容编辑器", func(): Net.session().go_content_editor())
	if bool(Net.session().get("editor_return")):
		mk.call("返回编辑器", func(): Net.session().go_content_editor())
	mk.call("返回角色选择", func(): Net.session().go_character_select())
	mk.call("返回登录", func(): Net.session().go_login())
	mk.call("生成假玩家", func(): _on_remote_debug_spawn())
	mk.call("创建调试队伍", func(): _on_party_debug_fill())
	mk.call("仓库", func(): _toggle_warehouse_panel(true))
	mk.call("好友", func(): _toggle_friends_panel(true))
	mk.call("邮件", func(): _toggle_mail_panel(true))
	mk.call("制作", func(): _toggle_craft_panel(true))
	mk.call("表情", func(): _toggle_emote_panel(true))
	mk.call("战斗日志", func(): _toggle_combat_log_panel(true))
	mk.call("称号", func(): _toggle_titles_panel(true))
	mk.call("成就", func(): _toggle_achievements_panel(true))
	mk.call("公会", func(): _toggle_guild_panel(true))
	mk.call("拍卖", func(): _toggle_auction_panel(true))
	mk.call("日常任务", func():
		_toggle_daily_panel(true)
		_close_menu_popup()
	)
	var srv_d = Net.server()
	var dungeon_active := false
	if srv_d != null and srv_d.has_method("in_dungeon"):
		dungeon_active = bool(srv_d.in_dungeon())
		if not dungeon_active and srv_d.has_method("snapshot_dungeon"):
			dungeon_active = bool(srv_d.snapshot_dungeon().get("completed", false))
	elif not _dungeon_state.is_empty():
		dungeon_active = bool(_dungeon_state.get("active", false)) or bool(_dungeon_state.get("completed", false))
	if dungeon_active:
		mk.call("离开试炼", func():
			_on_dungeon_exit_pressed()
			_close_menu_popup()
		)
	else:
		mk.call("进入试炼洞窟", func():
			_on_dungeon_enter_pressed()
			_close_menu_popup()
		)
	mk.call("清除标记", func():
		_on_clear_map_pins()
		_close_menu_popup()
	)
	mk.call("召唤宠物", func():
		if _world_combat != null and _world_combat.has_method("request_pet_summon"):
			_world_combat.request_pet_summon("default")
		_close_menu_popup()
	)
	mk.call("收回宠物", func():
		if _world_combat != null and _world_combat.has_method("request_pet_dismiss"):
			_world_combat.request_pet_dismiss()
		_close_menu_popup()
	)
	mk.call("关闭所有窗口", func():
		for id in _windows.keys():
			(_windows[id] as Control).visible = false
		hide_npc_dialogue()
		hide_loot()
		if _party_panel:
			_party_panel.visible = false
		if _warehouse_panel:
			_warehouse_panel.visible = false
		if _friends_panel:
			_friends_panel.visible = false
		if _mail_panel:
			_mail_panel.visible = false
		if _craft_panel:
			_craft_panel.visible = false
		if _emote_panel:
			_emote_panel.visible = false
		if _combat_log_panel:
			_combat_log_panel.visible = false
		if _titles_panel:
			_titles_panel.visible = false
		if _achievements_panel:
			_achievements_panel.visible = false
		if _daily_panel:
			_daily_panel.visible = false
		if _guild_panel:
			_guild_panel.visible = false
		if _auction_panel:
			_auction_panel.visible = false
		_close_menu_popup()
	)


func _add_setting_row(body: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", L2Style.COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	body.add_child(row)


func _add_volume_row(body: VBoxContainer, label: String, value: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(72, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", L2Style.COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 1
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	L2Style.style_slider(sl)
	var amt := Label.new()
	amt.text = str(value)
	amt.custom_minimum_size = Vector2(36, 0)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_theme_font_size_override("font_size", 13)
	amt.add_theme_color_override("font_color", L2Style.COL_GOLD)
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.value_changed.connect(func(v: float):
		amt.text = str(int(v))
		cb.call(int(v))
	)
	row.add_child(sl)
	row.add_child(amt)
	body.add_child(row)


func _add_check(body: VBoxContainer, label: String, on: bool, cb: Callable) -> void:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = on
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	L2Style.style_check(box)
	box.toggled.connect(cb)
	body.add_child(box)


func _add_reset_row(body: VBoxContainer, gs: Node) -> void:
	body.add_child(L2Style.hairline())
	var b := Button.new()
	b.text = "恢复默认"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func():
		if gs != null:
			gs.reset_defaults()
		_fill_window("system")
	)
	body.add_child(b)


func _make_mode_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var modes: Array = GameSettingsScript.WINDOW_MODES
	var cur := str(gs.window_mode)
	var sel := 0
	for i in range(modes.size()):
		opt.add_item(str(modes[i][0]), i)
		opt.set_item_metadata(i, str(modes[i][1]))
		if str(modes[i][1]) == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_window_mode(str(opt.get_item_metadata(idx)))
		_fill_window("system")
	)
	return opt


func _make_res_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var cur: Vector2i = gs.resolution
	var sel := 0
	var res_list: Array = GameSettingsScript.RESOLUTIONS
	for i in range(res_list.size()):
		var r: Vector2i = res_list[i]
		opt.add_item("%d × %d" % [r.x, r.y], i)
		opt.set_item_metadata(i, r)
		if r == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		var r: Vector2i = opt.get_item_metadata(idx)
		gs.set_resolution(r)
	)
	return opt


func _make_fps_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var caps: Array = GameSettingsScript.FPS_CAPS
	var cur := int(gs.max_fps)
	var sel := 0
	for i in range(caps.size()):
		var cap: int = int(caps[i])
		opt.add_item("不限制" if cap == 0 else str(cap), i)
		opt.set_item_metadata(i, cap)
		if cap == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_max_fps(int(opt.get_item_metadata(idx)))
	)
	return opt


func _make_scale_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var scales: Array = GameSettingsScript.UI_SCALES
	var cur := float(gs.ui_scale)
	var sel := 1
	for i in range(scales.size()):
		var s: float = float(scales[i])
		opt.add_item("%d%%" % int(round(s * 100.0)), i)
		opt.set_item_metadata(i, s)
		if is_equal_approx(s, cur):
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_ui_scale(float(opt.get_item_metadata(idx)))
	)
	return opt

func _build_party_stub() -> void:
	## Live party shell panel (debug stubs via MockServer try_party_*).
	_party_panel = PanelContainer.new()
	_party_panel.name = "PartyPanel"
	_party_panel.set_script(HudDrag)
	_party_panel.screen_margin = 4.0
	_party_panel.min_size = Vector2(180, 100)
	_party_panel.default_size = Vector2(260, 300)
	_party_panel.initial_dock = "top_left"
	_party_panel.drag_anywhere = true
	add_child(_party_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 12)
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
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _party_panel.visible = false)
	head.add_child(close_btn)
	_party_body = VBoxContainer.new()
	_party_body.name = "PartyBody"
	_party_body.add_theme_constant_override("separation", 4)
	_party_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_party_body)
	_party_panel.visible = false
	_apply_l2_chrome(_party_panel)
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
		"loot_mode": str(party.get("loot_mode", "ffa")).strip_edges().to_lower(),
	}
	var mem_v: Variant = party.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for m in mem_v:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = m
			var st_v: Variant = md.get("statuses", [])
			var st_arr: Array = []
			if typeof(st_v) == TYPE_ARRAY:
				for s in st_v:
					if typeof(s) == TYPE_DICTIONARY:
						st_arr.append((s as Dictionary).duplicate(true))
			cleaned.append({
				"id": str(md.get("id", "")),
				"name": str(md.get("name", "?")),
				"hp": int(md.get("hp", 0)),
				"hp_max": maxi(int(md.get("hp_max", 1)), 1),
				"online": bool(md.get("online", true)),
				"statuses": st_arr,
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
		_add_label(_party_body, "（未组队）", 11, L2Style.COL_MUTED)
		var create_btn := Button.new()
		create_btn.text = "创建队伍"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.pressed.connect(_on_party_create)
		L2Style.style_action_button(create_btn)
		create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_party_body.add_child(create_btn)
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
		var expanded := bool(_party_expanded.get(mid, false))
		var expand_btn := Button.new()
		expand_btn.text = "▼" if expanded else "▶"
		expand_btn.focus_mode = Control.FOCUS_NONE
		expand_btn.custom_minimum_size = Vector2(22, 20)
		expand_btn.tooltip_text = "展开状态" if not expanded else "收起状态"
		expand_btn.pressed.connect(_on_party_toggle_expand.bind(mid))
		name_row.add_child(expand_btn)
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
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		nl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_on_party_toggle_expand(mid)
		)
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
		if expanded:
			var st_v2: Variant = md.get("statuses", [])
			var st_list: Array = []
			if typeof(st_v2) == TYPE_ARRAY:
				for s2 in st_v2:
					if typeof(s2) == TYPE_DICTIONARY:
						st_list.append(s2)
			# Prefer server statuses; fall back to live player chips for self.
			if st_list.is_empty() and mid == self_id:
				st_list = _player_statuses.duplicate(true)
			if st_list.is_empty():
				var empty_lab := Label.new()
				empty_lab.text = "（无状态）"
				empty_lab.add_theme_font_size_override("font_size", 10)
				empty_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
				empty_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(empty_lab)
			else:
				var sbar = StatusIconBar.new()
				sbar.name = "PartyMemberStatuses"
				sbar.icon_size = 24.0
				sbar.allow_cancel = false
				sbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(sbar)
				sbar.apply_statuses(st_list)
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
	# Loot mode (leader-only control)
	var loot_row := HBoxContainer.new()
	loot_row.add_theme_constant_override("separation", 4)
	_party_body.add_child(loot_row)
	var loot_lab := Label.new()
	loot_lab.text = "拾取"
	loot_lab.add_theme_font_size_override("font_size", 10)
	loot_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	loot_row.add_child(loot_lab)
	var loot_opt := OptionButton.new()
	loot_opt.focus_mode = Control.FOCUS_NONE
	loot_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_opt.add_item("自由", 0)
	loot_opt.set_item_metadata(0, "ffa")
	loot_opt.add_item("队长", 1)
	loot_opt.set_item_metadata(1, "leader")
	loot_opt.add_item("轮流", 2)
	loot_opt.set_item_metadata(2, "round_robin")
	loot_opt.add_item("需求/贪婪", 3)
	loot_opt.set_item_metadata(3, "need_greed")
	var cur_mode := str(_party_state.get("loot_mode", "ffa")).strip_edges().to_lower()
	if cur_mode == "":
		cur_mode = "ffa"
	elif cur_mode == "roll":
		cur_mode = "need_greed"
	var sel_idx := 0
	match cur_mode:
		"leader":
			sel_idx = 1
		"round_robin":
			sel_idx = 2
		"need_greed":
			sel_idx = 3
		_:
			sel_idx = 0
	loot_opt.select(sel_idx)
	var is_leader := leader == self_id
	loot_opt.disabled = not is_leader
	loot_opt.tooltip_text = "队长可切换：自由拾取 / 队长分配 / 轮流拾取 / 需求贪婪"
	if is_leader:
		loot_opt.item_selected.connect(func(idx: int):
			var m := str(loot_opt.get_item_metadata(idx))
			_on_party_set_loot_mode(m)
		)
	loot_row.add_child(loot_opt)
	var leave_btn := Button.new()
	leave_btn.text = "离开队伍"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(0, 26)
	leave_btn.pressed.connect(_on_party_leave)
	_party_body.add_child(leave_btn)


func _party_self_id_for_ui() -> String:
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		return str(srv._party_self_id())
	return "player"


func _on_party_toggle_expand(member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	var cur := bool(_party_expanded.get(member_id, false))
	_party_expanded[member_id] = not cur
	_refresh_party_panel()


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


func _on_party_set_loot_mode(mode: String) -> void:
	mode = str(mode).strip_edges().to_lower()
	if mode.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_party_set_loot_mode"):
		_world_combat.request_party_set_loot_mode(mode)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_set_loot_mode"):
		_apply_party_result_locally(srv.try_party_set_loot_mode(mode))


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
			"status_update":
				var tgt := str(action.get("target", "")).strip_edges().to_lower()
				if tgt == "player" or tgt == "":
					var st_v3: Variant = action.get("statuses", [])
					if typeof(st_v3) == TYPE_ARRAY:
						apply_status_chips(st_v3)
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
	var follow_id := ""
	if _world_combat != null and _world_combat.has_method("is_following") and _world_combat.is_following():
		if _world_combat.has_method("get_follow_id") and _world_combat.get_follow_id() == player_id:
			follow_id = player_id
	for d in PCM.item_defs(follow_id):
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
			_show_inspect(pid, dname)
		PCM.Action.INVITE:
			_on_party_invite(dname)
		PCM.Action.TRADE:
			_on_trade_open_with(dname)
		PCM.Action.DUEL:
			var duel_key := dname if not dname.is_empty() else pid
			_on_duel_challenge(duel_key)
		PCM.Action.WHISPER:
			prefill_whisper(dname)
		PCM.Action.ADD_FRIEND:
			var add_key := dname if not dname.is_empty() else pid
			_on_friend_add(add_key)
		PCM.Action.INVITE_GUILD:
			var gkey := dname if not dname.is_empty() else pid
			_on_guild_invite(gkey)
		PCM.Action.FOLLOW:
			if _world_combat == null:
				append_system("无法跟随。")
			elif pid != "" and _world_combat.has_method("is_following") and _world_combat.is_following() and _world_combat.has_method("get_follow_id") and _world_combat.get_follow_id() == pid:
				if _world_combat.has_method("stop_follow"):
					_world_combat.stop_follow()
			elif _world_combat.has_method("start_follow"):
				_world_combat.start_follow(pid)
			else:
				append_system("无法跟随。")


func _on_trade_open_with(partner_name: String) -> void:
	partner_name = str(partner_name).strip_edges()
	if _world_combat != null and _world_combat.has_method("request_trade_open"):
		_world_combat.request_trade_open(partner_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		_apply_trade_result_locally(srv.try_trade_open(partner_name))



func _on_duel_challenge(target_id_or_name: String) -> void:
	target_id_or_name = str(target_id_or_name).strip_edges()
	if _world_combat != null and _world_combat.has_method("request_duel_challenge"):
		_world_combat.request_duel_challenge(target_id_or_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_duel_challenge"):
		_apply_duel_result_locally(srv.try_duel_challenge(target_id_or_name))


func _on_duel_forfeit() -> void:
	if _world_combat != null and _world_combat.has_method("request_duel_forfeit"):
		_world_combat.request_duel_forfeit()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_duel_forfeit"):
		_apply_duel_result_locally(srv.try_duel_forfeit())


func _apply_duel_result_locally(result: Dictionary) -> void:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		match t:
			"duel_update":
				apply_duel_update(a)
			"system_message":
				append_system(str(a.get("text", "")))


func _build_duel_banner() -> void:
	_duel_banner = PanelContainer.new()
	_duel_banner.name = "DuelBanner"
	_duel_banner.visible = false
	add_child(_duel_banner)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 6)
	_duel_banner.add_child(marg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	marg.add_child(row)
	_duel_label = Label.new()
	_duel_label.name = "DuelLabel"
	_duel_label.text = "决斗"
	_duel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_duel_label)
	var forfeit_btn := Button.new()
	forfeit_btn.name = "DuelForfeitBtn"
	forfeit_btn.text = "认输"
	forfeit_btn.focus_mode = Control.FOCUS_NONE
	forfeit_btn.pressed.connect(_on_duel_forfeit)
	row.add_child(forfeit_btn)
	if has_method("_apply_l2_chrome"):
		_apply_l2_chrome(_duel_banner)
	_duel_banner.position = Vector2(12, 72)
	_duel_banner.z_index = 40


func apply_duel_update(action: Dictionary) -> void:
	var d: Variant = action.get("duel", action)
	if typeof(d) != TYPE_DICTIONARY:
		return
	_duel_state = (d as Dictionary).duplicate(true)
	_refresh_duel_banner()


func _refresh_duel_banner() -> void:
	if _duel_banner == null:
		return
	var active := bool(_duel_state.get("active", false))
	_duel_banner.visible = active
	if not active:
		return
	var oname := str(_duel_state.get("opponent_name", "对手"))
	var hp := int(_duel_state.get("opponent_hp", 0))
	var hp_max := int(_duel_state.get("opponent_hp_max", 0))
	var left := _duel_remaining_sec()
	if _duel_label != null:
		_duel_label.text = "决斗 vs 【%s】  HP %d/%d  剩余 %ds" % [oname, hp, hp_max, left]
	_duel_banner.reset_size()
	_duel_banner.move_to_front()



func apply_rested_update(action: Dictionary) -> void:
	## Snapshot / tick opcode: refresh rested pool on XP bar HUD.
	if action.has("rested_exp"):
		_server_combat["rested_exp"] = maxi(int(action.get("rested_exp", 0)), 0)
	if action.has("rested_exp_max"):
		_server_combat["rested_exp_max"] = maxi(int(action.get("rested_exp_max", 0)), 0)
	_refresh_xp_bar()


func _refresh_rested_label(rested: int = -1) -> void:
	_ensure_xp_bar()
	if _xp_bar == null:
		return
	if rested < 0:
		rested = maxi(int(_server_combat.get("rested_exp", 0)), 0)
	if _rested_label == null or not is_instance_valid(_rested_label):
		_rested_label = Label.new()
		_rested_label.name = "RestedLabel"
		_rested_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rested_label.add_theme_font_size_override("font_size", 10)
		_rested_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0, 1.0))
		_rested_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))
		_rested_label.add_theme_constant_override("outline_size", 2)
		_rested_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rested_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rested_label.offset_left = 2.0
		_rested_label.offset_right = -2.0
		_rested_label.offset_top = -1.0
		_rested_label.offset_bottom = 0.0
		_xp_bar.add_child(_rested_label)
	_rested_label.text = "休息 %d" % rested if rested > 0 else ""
	_rested_label.visible = rested > 0


func apply_safe_zone(action: Dictionary) -> void:
	var inside := bool(action.get("inside", action.get("in_safe_zone", false)))
	_safe_zone_inside = inside
	_ensure_safe_zone_chip()
	if _safe_zone_chip != null:
		_safe_zone_chip.visible = inside


func _ensure_safe_zone_chip() -> void:
	if _safe_zone_chip != null and is_instance_valid(_safe_zone_chip):
		_safe_zone_chip.visible = _safe_zone_inside
		return
	var panel := get_node_or_null("%StatusPanel") as Control
	_safe_zone_chip = Label.new()
	_safe_zone_chip.name = "SafeZoneChip"
	_safe_zone_chip.text = "安全区"
	_safe_zone_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_zone_chip.add_theme_font_size_override("font_size", 11)
	_safe_zone_chip.add_theme_color_override("font_color", Color(0.55, 0.92, 0.7, 1.0))
	_safe_zone_chip.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.06, 0.9))
	_safe_zone_chip.add_theme_constant_override("outline_size", 2)
	_safe_zone_chip.visible = _safe_zone_inside
	_safe_zone_chip.z_index = 30
	if panel != null and panel.get_parent() != null:
		var parent_ctl: Node = panel.get_parent()
		parent_ctl.add_child(_safe_zone_chip)
		# Sit just under the status panel.
		_safe_zone_chip.position = Vector2(panel.position.x + 6.0, panel.position.y + panel.size.y + 2.0)
		if parent_ctl is Control:
			# Prefer anchors under panel when layout settles.
			_safe_zone_chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_safe_zone_chip.offset_left = panel.offset_left + 6.0 if "offset_left" in panel else 8.0
			_safe_zone_chip.offset_top = (panel.offset_bottom if "offset_bottom" in panel else 90.0) + 2.0
	else:
		add_child(_safe_zone_chip)
		_safe_zone_chip.position = Vector2(12, 100)



func apply_dungeon_update(action: Dictionary) -> void:
	var d: Variant = action.get("dungeon", action)
	if typeof(d) != TYPE_DICTIONARY:
		return
	_dungeon_state = (d as Dictionary).duplicate(true)
	_ensure_dungeon_chip()
	_refresh_dungeon_chip()


func _refresh_dungeon_chip() -> void:
	_ensure_dungeon_chip()
	if _dungeon_chip == null:
		return
	var active := bool(_dungeon_state.get("active", false))
	var completed := bool(_dungeon_state.get("completed", false))
	if not active and not completed:
		_dungeon_chip.visible = false
		return
	var kills := int(_dungeon_state.get("kills", 0))
	var needed := int(_dungeon_state.get("kills_needed", 2))
	if completed:
		_dungeon_chip.text = "试炼完成"
	else:
		_dungeon_chip.text = "试炼 %d/%d" % [kills, needed]
	_dungeon_chip.visible = true


func _ensure_dungeon_chip() -> void:
	if _dungeon_chip != null and is_instance_valid(_dungeon_chip):
		return
	var panel := get_node_or_null("%StatusPanel") as Control
	_dungeon_chip = Label.new()
	_dungeon_chip.name = "DungeonChip"
	_dungeon_chip.text = "试炼 0/2"
	_dungeon_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dungeon_chip.add_theme_font_size_override("font_size", 11)
	_dungeon_chip.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45, 1.0))
	_dungeon_chip.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.9))
	_dungeon_chip.add_theme_constant_override("outline_size", 2)
	_dungeon_chip.visible = false
	_dungeon_chip.z_index = 30
	if panel != null and panel.get_parent() != null:
		var parent_ctl: Node = panel.get_parent()
		parent_ctl.add_child(_dungeon_chip)
		_dungeon_chip.position = Vector2(panel.position.x + 6.0, panel.position.y + panel.size.y + 16.0)
	else:
		add_child(_dungeon_chip)
		_dungeon_chip.position = Vector2(12, 116)


func _on_dungeon_enter_pressed() -> void:
	if _world_combat != null and _world_combat.has_method("request_dungeon_enter"):
		_world_combat.request_dungeon_enter()
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_enter"):
		return
	_apply_dungeon_result_locally(srv.try_dungeon_enter())


func _on_dungeon_exit_pressed() -> void:
	if _world_combat != null and _world_combat.has_method("request_dungeon_exit"):
		_world_combat.request_dungeon_exit()
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_exit"):
		return
	_apply_dungeon_result_locally(srv.try_dungeon_exit())


func _apply_dungeon_result_locally(result: Dictionary) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "dungeon_update":
			apply_dungeon_update(a)
		elif t == "system_message":
			var msg := str(a.get("text", "")).strip_edges()
			if msg != "":
				append_system(msg)
		elif t == "map_transfer" and _world_combat != null and _world_combat.has_method("_on_transfer_requested"):
			if bool(a.get("ok", true)):
				_world_combat._on_transfer_requested(a)
		elif t == "inventory_update":
			apply_inventory_snapshot(a.get("items", []), int(a.get("gold", -1)))
		elif t == "exp_gain":
			show_exp_gain_float(int(a.get("amount", 0)))



func _duel_remaining_sec() -> int:
	if not bool(_duel_state.get("active", false)):
		return 0
	var ends := float(_duel_state.get("ends_at", 0.0))
	var now := Time.get_ticks_msec() / 1000.0
	return maxi(0, int(ceil(ends - now)))


func _tick_duel_banner(delta: float) -> void:
	if not bool(_duel_state.get("active", false)):
		return
	_duel_banner_acc += delta
	if _duel_banner_acc < 0.25:
		return
	_duel_banner_acc = 0.0
	_refresh_duel_banner()


func _build_level_toast() -> void:
	if _level_toast != null and is_instance_valid(_level_toast):
		return
	_level_toast = PanelContainer.new()
	_level_toast.name = "LevelUpToast"
	_level_toast.visible = false
	_level_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_toast.z_index = 80
	add_child(_level_toast)
	var marg := MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	_level_toast.add_child(marg)
	_level_toast_label = Label.new()
	_level_toast_label.name = "LevelUpToastLabel"
	_level_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_toast_label.add_theme_font_size_override("font_size", 22)
	_level_toast_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	_level_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	_level_toast_label.add_theme_constant_override("outline_size", 4)
	_level_toast_label.text = "升级！"
	marg.add_child(_level_toast_label)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.85, 0.72, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_level_toast.add_theme_stylebox_override("panel", sb)


## Public toast API (headless tests + world level_up path).
## sp_gained > 0 appends 「获得技能点」; mouse-filter ignore so input stays free.
func show_level_up_toast(level: int, sp_gained: int = 0) -> void:
	_build_level_toast()
	if _level_toast == null:
		return
	_level_toast_level = maxi(level, 1)
	_level_toast_sp_note = sp_gained > 0
	_level_toast_armed = true
	_level_toast_ttl = LEVEL_TOAST_DURATION
	_refresh_level_toast_text()
	_level_toast.visible = true
	_layout_level_toast()
	_level_toast.move_to_front()


func hide_level_up_toast() -> void:
	_level_toast_ttl = 0.0
	_level_toast_armed = false
	_level_toast_sp_note = false
	if _level_toast != null:
		_level_toast.visible = false


func is_level_up_toast_visible() -> bool:
	return _level_toast != null and _level_toast.visible and _level_toast_ttl > 0.0


func get_level_up_toast_text() -> String:
	if _level_toast_label == null:
		return ""
	return str(_level_toast_label.text)


func _set_level_toast_sp_note(on: bool) -> void:
	if not _level_toast_armed:
		return
	_level_toast_sp_note = on
	# Refresh TTL slightly so SP note is readable after late skill_book_update.
	_level_toast_ttl = maxf(_level_toast_ttl, 1.2)
	_refresh_level_toast_text()
	_layout_level_toast()


func _refresh_level_toast_text() -> void:
	if _level_toast_label == null:
		return
	var line := "升级！Lv.%d" % _level_toast_level
	if _level_toast_sp_note:
		line += "\n获得技能点"
	_level_toast_label.text = line


func _layout_level_toast() -> void:
	if _level_toast == null:
		return
	_level_toast.reset_size()
	var vp := get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = _level_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = _level_toast.size
	_level_toast.position = Vector2((vp.x - sz.x) * 0.5, 56.0)


func _tick_level_toast(delta: float) -> void:
	if _level_toast_ttl <= 0.0:
		return
	_level_toast_ttl -= delta
	if _level_toast_ttl <= 0.0:
		hide_level_up_toast()


## Compare previous statuses → toast only on transition to ready / completed.
## First snapshot seeds only (enter_world / spawn must not spam).
func _detect_quest_status_toasts(quests: Array) -> void:
	var next_seen: Dictionary = {}
	var ready_titles: Array = []
	var done_titles: Array = []
	for q_v in quests:
		if typeof(q_v) != TYPE_DICTIONARY:
			continue
		var q: Dictionary = q_v
		var qid := str(q.get("id", "")).strip_edges()
		if qid.is_empty():
			continue
		var st := _normalize_quest_status(str(q.get("status", "")))
		next_seen[qid] = st
		var title := str(q.get("title", qid)).strip_edges()
		if title.is_empty():
			title = qid
		if not _quest_status_seeded:
			continue
		var prev := str(_quest_status_seen.get(qid, ""))
		if st == "ready" and prev != "ready":
			ready_titles.append(title)
		elif st == "completed" and prev != "completed":
			done_titles.append(title)
	_quest_status_seen = next_seen
	_quest_status_seeded = true
	# Prefer complete over ready if both somehow fire; show one banner (last wins).
	for t in ready_titles:
		show_quest_ready_toast(str(t))
	for t in done_titles:
		show_quest_complete_toast(str(t))


func _build_quest_toast() -> void:
	if _quest_toast != null and is_instance_valid(_quest_toast):
		return
	_quest_toast = PanelContainer.new()
	_quest_toast.name = "QuestToast"
	_quest_toast.visible = false
	_quest_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_toast.z_index = 80
	add_child(_quest_toast)
	var marg := MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	_quest_toast.add_child(marg)
	_quest_toast_label = Label.new()
	_quest_toast_label.name = "QuestToastLabel"
	_quest_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quest_toast_label.add_theme_font_size_override("font_size", 20)
	_quest_toast_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.55, 1.0))
	_quest_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	_quest_toast_label.add_theme_constant_override("outline_size", 4)
	_quest_toast_label.text = "任务"
	marg.add_child(_quest_toast_label)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.55, 0.82, 0.40, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_quest_toast.add_theme_stylebox_override("panel", sb)


## Public toast API (headless + apply_quest_snapshot transitions).
func show_quest_ready_toast(title: String) -> void:
	_show_quest_toast("任务可交付：%s" % title.strip_edges(), Color(0.75, 0.95, 0.55, 1.0), Color(0.55, 0.82, 0.40, 0.95))


func show_quest_complete_toast(title: String) -> void:
	_show_quest_toast("任务完成：%s" % title.strip_edges(), Color(1.0, 0.92, 0.45, 1.0), Color(0.85, 0.72, 0.28, 0.95))


func _show_quest_toast(line: String, font_col: Color, border_col: Color) -> void:
	_build_quest_toast()
	if _quest_toast == null or _quest_toast_label == null:
		return
	_quest_toast_label.text = line
	_quest_toast_label.add_theme_color_override("font_color", font_col)
	var sb: StyleBox = _quest_toast.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var flat: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
		flat.border_color = border_col
		_quest_toast.add_theme_stylebox_override("panel", flat)
	_quest_toast_ttl = QUEST_TOAST_DURATION
	_quest_toast.visible = true
	_layout_quest_toast()
	_quest_toast.move_to_front()


func hide_quest_toast() -> void:
	_quest_toast_ttl = 0.0
	if _quest_toast != null:
		_quest_toast.visible = false


func is_quest_toast_visible() -> bool:
	return _quest_toast != null and _quest_toast.visible and _quest_toast_ttl > 0.0


func get_quest_toast_text() -> String:
	if _quest_toast_label == null:
		return ""
	return str(_quest_toast_label.text)


func _layout_quest_toast() -> void:
	if _quest_toast == null:
		return
	_quest_toast.reset_size()
	var vp := get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = _quest_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = _quest_toast.size
	# Sit just under level-up toast band when that is visible; else same top slot.
	var y := 56.0
	if is_level_up_toast_visible():
		y = 100.0
	_quest_toast.position = Vector2((vp.x - sz.x) * 0.5, y)


func _tick_quest_toast(delta: float) -> void:
	if _quest_toast_ttl <= 0.0:
		return
	_quest_toast_ttl -= delta
	if _quest_toast_ttl <= 0.0:
		hide_quest_toast()


func _note_player_input() -> void:
	_last_input_sec = Time.get_ticks_msec() / 1000.0
	_afk_warned = false


func _tick_afk_warn(_delta: float) -> void:
	_tick_afk_toast(_delta)
	var gs := GameSettingsScript.get_i()
	var minutes: int = 10
	if gs != null and "afk_warn_minutes" in gs:
		minutes = int(gs.afk_warn_minutes)
	var threshold := AfkWarnUtil.threshold_sec_from_minutes(minutes)
	var now := Time.get_ticks_msec() / 1000.0
	var idle := now - _last_input_sec
	if not AfkWarnUtil.should_warn(idle, threshold, _afk_warned):
		return
	_afk_warned = true
	show_afk_warn_toast(true)
	append_system("你已离开一段时间。建议按 R 坐下休息。")


func _build_afk_toast() -> void:
	if _afk_toast != null and is_instance_valid(_afk_toast):
		return
	_afk_toast = PanelContainer.new()
	_afk_toast.name = "AfkWarnToast"
	_afk_toast.visible = false
	_afk_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_afk_toast.z_index = 80
	add_child(_afk_toast)
	var marg := MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	_afk_toast.add_child(marg)
	_afk_toast_label = Label.new()
	_afk_toast_label.name = "AfkWarnToastLabel"
	_afk_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_afk_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_afk_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_afk_toast_label.add_theme_font_size_override("font_size", 18)
	_afk_toast_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0, 1.0))
	_afk_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	_afk_toast_label.add_theme_constant_override("outline_size", 4)
	_afk_toast_label.text = "你已离开一段时间"
	marg.add_child(_afk_toast_label)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.55, 0.70, 0.95, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_afk_toast.add_theme_stylebox_override("panel", sb)


## Non-blocking AFK banner. Optional soft sit line; never locks input / disconnects.
func show_afk_warn_toast(suggest_sit: bool = true) -> void:
	_build_afk_toast()
	if _afk_toast == null or _afk_toast_label == null:
		return
	var line := "你已离开一段时间"
	if suggest_sit:
		line += "\n建议坐下休息（R）"
	_afk_toast_label.text = line
	_afk_toast_ttl = AFK_TOAST_DURATION
	_afk_toast.visible = true
	_layout_afk_toast()
	_afk_toast.move_to_front()


func hide_afk_warn_toast() -> void:
	_afk_toast_ttl = 0.0
	if _afk_toast != null:
		_afk_toast.visible = false


func is_afk_warn_toast_visible() -> bool:
	return _afk_toast != null and _afk_toast.visible and _afk_toast_ttl > 0.0


func get_afk_warn_toast_text() -> String:
	if _afk_toast_label == null:
		return ""
	return str(_afk_toast_label.text)


func _layout_afk_toast() -> void:
	if _afk_toast == null:
		return
	_afk_toast.reset_size()
	var vp := get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = _afk_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = _afk_toast.size
	_afk_toast.position = Vector2((vp.x - sz.x) * 0.5, 100.0)


func _tick_afk_toast(delta: float) -> void:
	if _afk_toast_ttl <= 0.0:
		return
	_afk_toast_ttl -= delta
	if _afk_toast_ttl <= 0.0:
		hide_afk_warn_toast()



func _build_exp_float() -> void:
	if _exp_float != null and is_instance_valid(_exp_float):
		return
	_exp_float = Label.new()
	_exp_float.name = "ExpGainFloat"
	_exp_float.visible = false
	_exp_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exp_float.z_index = 75
	_exp_float.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_exp_float.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_float.add_theme_font_size_override("font_size", 14)
	_exp_float.add_theme_color_override("font_color", Color(0.45, 0.88, 1.0, 1.0))
	_exp_float.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08, 0.9))
	_exp_float.add_theme_constant_override("outline_size", 3)
	_exp_float.text = "经验 +0"
	add_child(_exp_float)


## Public EXP float API (headless tests + world exp_gain path).
## Rapid/same-frame gains coalesce into one tip showing the sum.
func show_exp_gain_float(amount: int) -> void:
	amount = int(amount)
	if amount <= 0:
		return
	if not GameSettingsScript.flag("show_exp_floats", true):
		return
	_build_exp_float()
	if _exp_float == null:
		return
	if _exp_float_ttl > 0.0:
		_exp_float_amount += amount
	else:
		_exp_float_amount = amount
	_exp_float_ttl = EXP_FLOAT_DURATION
	_exp_float.text = "经验 +%d" % _exp_float_amount
	_exp_float.modulate = Color(1, 1, 1, 1)
	_exp_float.visible = true
	_layout_exp_float()
	_exp_float.move_to_front()


func hide_exp_gain_float() -> void:
	_exp_float_ttl = 0.0
	_exp_float_amount = 0
	if _exp_float != null:
		_exp_float.visible = false
		_exp_float.modulate = Color(1, 1, 1, 1)


func is_exp_gain_float_visible() -> bool:
	return _exp_float != null and _exp_float.visible and _exp_float_ttl > 0.0


func get_exp_gain_float_text() -> String:
	if _exp_float == null:
		return ""
	return str(_exp_float.text)


func get_exp_gain_float_amount() -> int:
	return _exp_float_amount if _exp_float_ttl > 0.0 else 0


func _layout_exp_float() -> void:
	if _exp_float == null:
		return
	_exp_float.reset_size()
	var pos := Vector2(16.0, 118.0)
	var panel := get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Local to HUD: float just under status / XP bar.
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 4.0) - global_position
	_exp_float.position = pos


func _tick_exp_float(delta: float) -> void:
	if _exp_float_ttl <= 0.0:
		return
	_exp_float_ttl -= delta
	if _exp_float != null and is_instance_valid(_exp_float):
		# Fade in last ~0.4s.
		var a: float = 1.0
		if _exp_float_ttl < 0.4:
			a = clampf(_exp_float_ttl / 0.4, 0.0, 1.0)
		_exp_float.modulate = Color(1, 1, 1, a)
		# Slight rise while alive.
		var rise: float = (EXP_FLOAT_DURATION - maxf(_exp_float_ttl, 0.0)) * 10.0
		# Re-anchor under status; Y drifts up while fading.
		_layout_exp_float()
		_exp_float.position.y -= rise
	if _exp_float_ttl <= 0.0:
		hide_exp_gain_float()


func _build_gold_float() -> void:
	if _gold_float != null and is_instance_valid(_gold_float):
		return
	_gold_float = Label.new()
	_gold_float.name = "GoldGainFloat"
	_gold_float.visible = false
	_gold_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_float.z_index = 75
	_gold_float.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_gold_float.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_float.add_theme_font_size_override("font_size", 14)
	# Yellow/gold — distinct from cyan exp float.
	_gold_float.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22, 1.0))
	_gold_float.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.0, 0.92))
	_gold_float.add_theme_constant_override("outline_size", 3)
	_gold_float.text = "金币 +0"
	add_child(_gold_float)


## Public gold float API (headless tests + inventory gold delta).
## Rapid/same-frame gains coalesce into one tip showing the sum. Ignores <=0.
func show_gold_gain_float(amount: int) -> void:
	amount = int(amount)
	if amount <= 0:
		return
	if not GameSettingsScript.flag("show_gold_floats", true):
		return
	_build_gold_float()
	if _gold_float == null:
		return
	if _gold_float_ttl > 0.0:
		_gold_float_amount += amount
	else:
		_gold_float_amount = amount
	_gold_float_ttl = GOLD_FLOAT_DURATION
	_gold_float.text = "金币 +%d" % _gold_float_amount
	_gold_float.modulate = Color(1, 1, 1, 1)
	_gold_float.visible = true
	_layout_gold_float()
	_gold_float.move_to_front()


func hide_gold_gain_float() -> void:
	_gold_float_ttl = 0.0
	_gold_float_amount = 0
	if _gold_float != null:
		_gold_float.visible = false
		_gold_float.modulate = Color(1, 1, 1, 1)


func is_gold_gain_float_visible() -> bool:
	return _gold_float != null and _gold_float.visible and _gold_float_ttl > 0.0


func get_gold_gain_float_text() -> String:
	if _gold_float == null:
		return ""
	return str(_gold_float.text)


func get_gold_gain_float_amount() -> int:
	return _gold_float_amount if _gold_float_ttl > 0.0 else 0


func _layout_gold_float() -> void:
	if _gold_float == null:
		return
	_gold_float.reset_size()
	var pos := Vector2(16.0, 136.0)
	var panel := get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Just under exp float band (exp sits at +4 under status).
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 22.0) - global_position
	_gold_float.position = pos


func _tick_gold_float(delta: float) -> void:
	if _gold_float_ttl <= 0.0:
		return
	_gold_float_ttl -= delta
	if _gold_float != null and is_instance_valid(_gold_float):
		var a: float = 1.0
		if _gold_float_ttl < 0.4:
			a = clampf(_gold_float_ttl / 0.4, 0.0, 1.0)
		_gold_float.modulate = Color(1, 1, 1, a)
		var rise: float = (GOLD_FLOAT_DURATION - maxf(_gold_float_ttl, 0.0)) * 10.0
		_layout_gold_float()
		_gold_float.position.y -= rise
	if _gold_float_ttl <= 0.0:
		hide_gold_gain_float()


func _inv_qty_map(items: Array) -> Dictionary:
	var m: Dictionary = {}
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		m[iid] = int(m.get(iid, 0)) + maxi(int(it.get("qty", 0)), 0)
	return m


func _emit_item_gain_floats_from_delta(prev_qty: Dictionary, new_qty: Dictionary) -> void:
	var gains: Array = []
	for iid in new_qty.keys():
		var nid := str(iid)
		var delta: int = int(new_qty.get(nid, 0)) - int(prev_qty.get(nid, 0))
		if delta > 0:
			gains.append({"id": nid, "qty": delta})
	if gains.is_empty():
		return
	# Prefer larger stacks first so loot_all keeps useful tips under the cap.
	gains.sort_custom(func(a, b): return int(a.get("qty", 0)) > int(b.get("qty", 0)))
	for g in gains:
		show_item_gain_float(str(g.get("id", "")), int(g.get("qty", 0)))


func _build_item_floats() -> void:
	if _item_float_host != null and is_instance_valid(_item_float_host):
		return
	_item_float_host = VBoxContainer.new()
	_item_float_host.name = "ItemGainFloats"
	_item_float_host.visible = false
	_item_float_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_float_host.z_index = 75
	_item_float_host.add_theme_constant_override("separation", 2)
	add_child(_item_float_host)


func _make_item_float_label() -> Label:
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 14)
	# Soft green — distinct from cyan exp / yellow gold.
	lab.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1.0))
	lab.add_theme_color_override("font_outline_color", Color(0.02, 0.12, 0.04, 0.92))
	lab.add_theme_constant_override("outline_size", 3)
	return lab


## Public item float API. Coalesces same item_id while TTL alive; caps concurrent lines.
func show_item_gain_float(item_id: String, qty: int, display_name: String = "") -> void:
	item_id = item_id.strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		return
	if not GameSettingsScript.flag("show_item_floats", true):
		return
	_build_item_floats()
	if _item_float_host == null:
		return
	var dname := display_name.strip_edges()
	if dname.is_empty():
		dname = _item_label(item_id)
		if dname.is_empty():
			dname = item_id
	dname = _item_rarity_name_line(item_id, dname)
	# Coalesce into existing active line for same id.
	for entry in _item_floats:
		if str(entry.get("id", "")) != item_id:
			continue
		entry["qty"] = int(entry.get("qty", 0)) + qty
		entry["ttl"] = ITEM_FLOAT_DURATION
		if not dname.is_empty():
			entry["name"] = dname
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			lab.text = "获得：%s ×%d" % [str(entry.get("name", dname)), int(entry.get("qty", 0))]
			lab.modulate = Color(1, 1, 1, 1)
		_layout_item_floats()
		return
	# Cap concurrent unique lines (loot_all safety).
	if _item_floats.size() >= ITEM_FLOAT_MAX_LINES:
		return
	var lab2 := _make_item_float_label()
	lab2.name = "ItemGainFloat_%s" % item_id
	lab2.text = "获得：%s ×%d" % [dname, qty]
	_item_float_host.add_child(lab2)
	_item_floats.append({
		"id": item_id,
		"qty": qty,
		"ttl": ITEM_FLOAT_DURATION,
		"label": lab2,
		"name": dname,
	})
	_item_float_host.visible = true
	_layout_item_floats()
	_item_float_host.move_to_front()


func hide_item_gain_floats() -> void:
	for entry in _item_floats:
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			lab.queue_free()
	_item_floats.clear()
	if _item_float_host != null and is_instance_valid(_item_float_host):
		_item_float_host.visible = false


func is_item_gain_float_visible() -> bool:
	return not _item_floats.is_empty()


func get_item_gain_float_count() -> int:
	return _item_floats.size()


func get_item_gain_float_texts() -> Array:
	var out: Array = []
	for entry in _item_floats:
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			out.append(str(lab.text))
		else:
			out.append("获得：%s ×%d" % [str(entry.get("name", entry.get("id", ""))), int(entry.get("qty", 0))])
	return out


func get_item_gain_float_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	for entry in _item_floats:
		if str(entry.get("id", "")) == item_id and float(entry.get("ttl", 0.0)) > 0.0:
			return int(entry.get("qty", 0))
	return 0


func _layout_item_floats() -> void:
	if _item_float_host == null:
		return
	var pos := Vector2(16.0, 154.0)
	var panel := get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Under gold float band (exp +4, gold +22 → items +40).
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 40.0) - global_position
	_item_float_host.position = pos


func _tick_item_floats(delta: float) -> void:
	if _item_floats.is_empty():
		return
	var remain: Array = []
	for entry in _item_floats:
		var ttl: float = float(entry.get("ttl", 0.0)) - delta
		entry["ttl"] = ttl
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			var a: float = 1.0
			if ttl < 0.4:
				a = clampf(ttl / 0.4, 0.0, 1.0)
			lab.modulate = Color(1, 1, 1, a)
		if ttl > 0.0:
			remain.append(entry)
		else:
			if lab != null and is_instance_valid(lab):
				lab.queue_free()
	_item_floats = remain
	_layout_item_floats()
	if _item_floats.is_empty() and _item_float_host != null and is_instance_valid(_item_float_host):
		_item_float_host.visible = false


func _build_trade_panel() -> void:
	_trade_panel = PanelContainer.new()
	_trade_panel.name = "TradePanel"
	_trade_panel.set_script(HudDrag)
	_trade_panel.screen_margin = 4.0
	_trade_panel.min_size = Vector2(360, 260)
	_trade_panel.default_size = Vector2(520, 400)
	_trade_panel.initial_dock = "none"
	_trade_panel.drag_anywhere = true
	add_child(_trade_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
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
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_trade_cancel)
	head.add_child(close_btn)
	_trade_body = VBoxContainer.new()
	_trade_body.name = "TradeBody"
	_trade_body.add_theme_constant_override("separation", 6)
	_trade_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_trade_body)
	_trade_panel.visible = false
	_apply_l2_chrome(_trade_panel)
	_refresh_trade_panel()
	call_deferred("_nudge_trade")


func _nudge_trade() -> void:
	if _trade_panel:
		_trade_panel.size = Vector2(520, 400)
		var vp := get_viewport_rect().size
		_trade_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 260)), 80)


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
		_add_label(_trade_body, "未在交易。右键玩家 →「交易」发起。", 11, L2Style.COL_MUTED)
		# Keep panel hidden when idle — no HUD button / stub open.
		if _trade_panel != null:
			_trade_panel.visible = false
		return
	var pname := str(_trade_state.get("partner_name", "对方"))
	var title_l := _trade_panel.find_child("TradeTitle", true, false) as Label
	if title_l != null:
		title_l.text = "交易 · %s" % pname
		L2Style.style_title(title_l)
	_add_label(_trade_body, "对方：%s" % pname, 12, L2Style.COL_TITLE)
	var cols := GridContainer.new()
	cols.columns = 2
	cols.add_theme_constant_override("h_separation", 10)
	cols.add_theme_constant_override("v_separation", 4)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_body.add_child(cols)
	var my_wrap := PanelContainer.new()
	my_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	my_wrap.custom_minimum_size = Vector2(180, 120)
	my_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(my_wrap)
	var their_wrap := PanelContainer.new()
	their_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	their_wrap.custom_minimum_size = Vector2(180, 120)
	their_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(their_wrap)
	var my_col := VBoxContainer.new()
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_col.add_theme_constant_override("separation", 4)
	my_wrap.add_child(my_col)
	var their_col := VBoxContainer.new()
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_col.add_theme_constant_override("separation", 4)
	their_wrap.add_child(their_col)
	_add_label(my_col, "你的报价", 11, L2Style.COL_MUTED)
	_add_label(their_col, "对方报价", 11, L2Style.COL_MUTED)
	_fill_trade_item_list(my_col, _trade_state.get("my_items", []), true)
	_fill_trade_item_list(their_col, _trade_state.get("their_items", []), false)
	_add_label(my_col, "Adena  %d" % int(_trade_state.get("my_gold", 0)), 12, L2Style.COL_GOLD)
	_add_label(their_col, "Adena  %d" % int(_trade_state.get("their_gold", 0)), 12, L2Style.COL_GOLD)
	var ready_me := bool(_trade_state.get("my_ready", false))
	var ready_them := bool(_trade_state.get("their_ready", false))
	_add_label(
		_trade_body,
		"锁定：你[%s] / 对方[%s]" % ["是" if ready_me else "否", "是" if ready_them else "否"],
		11,
		L2Style.COL_TEXT
	)
	if not ready_me:
		# Put items from bag (first few stacks as quick buttons)
		_add_label(_trade_body, "从背包放入（×1）：", 10, L2Style.COL_MUTED)
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
			L2Style.style_compact_button(b)
			bag_row.add_child(b)
			added += 1
			if added >= 8:
				break
		if added == 0:
			_add_label(bag_row, "（背包为空）", 10, L2Style.COL_MUTED)
		var gold_row := HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		_trade_body.add_child(gold_row)
		_add_label(gold_row, "放入 Adena", 11, L2Style.COL_TEXT)
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
		L2Style.style_compact_button(setg)
		gold_row.add_child(setg)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_trade_body.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_on_trade_cancel)
	L2Style.style_action_button(cancel)
	btn_row.add_child(cancel)
	var ready_btn := Button.new()
	ready_btn.text = "取消锁定" if ready_me else "锁定"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.pressed.connect(_on_trade_ready.bind(not ready_me))
	L2Style.style_action_button(ready_btn)
	btn_row.add_child(ready_btn)
	var conf := Button.new()
	conf.text = "确认交易"
	conf.focus_mode = Control.FOCUS_NONE
	conf.disabled = not (ready_me and ready_them)
	conf.pressed.connect(_on_trade_confirm)
	L2Style.style_action_button(conf)
	btn_row.add_child(conf)


func _fill_trade_item_list(parent: Node, items_v: Variant, mine: bool) -> void:
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		_add_label(parent, "（空）", 10, L2Style.COL_MUTED)
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
		var lab := Button.new()
		lab.text = "%s ×%d" % [nm, q]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.focus_mode = Control.FOCUS_NONE
		lab.custom_minimum_size = Vector2(0, 28)
		L2Style.style_row_button(lab, false)
		row.add_child(lab)
		if mine and not bool(_trade_state.get("my_ready", false)):
			var rm := Button.new()
			rm.text = "−"
			rm.focus_mode = Control.FOCUS_NONE
			rm.custom_minimum_size = Vector2(28, 28)
			rm.pressed.connect(_on_trade_take_item.bind(iid))
			L2Style.style_compact_button(rm)
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


func _build_warehouse_panel() -> void:
	_warehouse_panel = PanelContainer.new()
	_warehouse_panel.name = "WarehousePanel"
	_warehouse_panel.set_script(HudDrag)
	_warehouse_panel.screen_margin = 4.0
	_warehouse_panel.min_size = Vector2(420, 320)
	_warehouse_panel.default_size = Vector2(560, 420)
	_warehouse_panel.initial_dock = "none"
	_warehouse_panel.drag_anywhere = true
	add_child(_warehouse_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_warehouse_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "WarehouseTitle"
	title.text = "仓库"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _warehouse_panel.visible = false)
	head.add_child(close_btn)
	_warehouse_body = VBoxContainer.new()
	_warehouse_body.name = "WarehouseBody"
	_warehouse_body.add_theme_constant_override("separation", 6)
	_warehouse_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_warehouse_body)
	_warehouse_panel.visible = false
	_apply_l2_chrome(_warehouse_panel)
	_refresh_warehouse_panel()
	call_deferred("_nudge_warehouse")


func _nudge_warehouse() -> void:
	if _warehouse_panel == null:
		return
	_warehouse_panel.size = Vector2(560, 420)
	var vp := get_viewport_rect().size
	_warehouse_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 280)), 72)


func _toggle_warehouse_panel(force_open: bool = false) -> void:
	if _warehouse_panel == null:
		return
	if force_open:
		_warehouse_panel.visible = true
	else:
		_warehouse_panel.visible = not _warehouse_panel.visible
	if _warehouse_panel.visible:
		if _world_combat != null and _world_combat.has_method("request_warehouse_open"):
			_world_combat.request_warehouse_open()
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_warehouse_open"):
				_apply_warehouse_result_locally(srv.try_warehouse_open())
		_refresh_warehouse_panel()
		_warehouse_panel.move_to_front()
		call_deferred("_nudge_warehouse")


func apply_warehouse_update(action: Dictionary) -> void:
	var wh_v: Variant = action.get("warehouse", action)
	if typeof(wh_v) != TYPE_DICTIONARY:
		return
	var wh: Dictionary = wh_v
	_warehouse_state = {
		"items": [],
		"gold": int(wh.get("gold", 0)),
		"max_slots": int(wh.get("max_slots", 60)),
		"used_slots": int(wh.get("used_slots", 0)),
	}
	var items_v: Variant = wh.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for it in items_v:
			if typeof(it) == TYPE_DICTIONARY:
				cleaned.append((it as Dictionary).duplicate(true))
		_warehouse_state["items"] = cleaned
		_warehouse_state["used_slots"] = cleaned.size()
	if _warehouse_panel != null and _warehouse_panel.visible:
		_refresh_warehouse_panel()


func _refresh_warehouse_panel() -> void:
	if _warehouse_body == null:
		return
	for c in _warehouse_body.get_children():
		c.queue_free()
	_warehouse_gold_spin = null
	var used: int = int(_warehouse_state.get("used_slots", 0))
	var cap: int = int(_warehouse_state.get("max_slots", 60))
	_add_label(_warehouse_body, "容量 %d / %d" % [used, cap], 11, L2Style.COL_MUTED)
	_add_label(_warehouse_body, "金币 %d" % int(_warehouse_state.get("gold", 0)), 12, L2Style.COL_TITLE)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_warehouse_body.add_child(cols)

	var bag_wrap := VBoxContainer.new()
	bag_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_wrap.add_theme_constant_override("separation", 4)
	cols.add_child(bag_wrap)
	_add_label(bag_wrap, "背包（双击存入）", 11, L2Style.COL_MUTED)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.custom_minimum_size = Vector2(0, 180)
	bag_wrap.add_child(bag_scroll)
	var bag_list := VBoxContainer.new()
	bag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_list.add_theme_constant_override("separation", 2)
	bag_scroll.add_child(bag_list)
	var bag_items: Array = _server_inventory
	if bag_items.is_empty():
		_add_label(bag_list, "（空）", 11, L2Style.COL_MUTED)
	else:
		for it in bag_items:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid := str(it.get("id", "")).strip_edges()
			var q: int = int(it.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			var row := Button.new()
			row.text = "%s ×%d" % [_item_label(iid), q]
			row.focus_mode = Control.FOCUS_NONE
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.tooltip_text = "存入 1 个（Shift+点击存入全部）"
			row.pressed.connect(_on_warehouse_deposit_pressed.bind(iid, q))
			bag_list.add_child(row)

	var wh_wrap := VBoxContainer.new()
	wh_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wh_wrap.add_theme_constant_override("separation", 4)
	cols.add_child(wh_wrap)
	_add_label(wh_wrap, "仓库（双击取出）", 11, L2Style.COL_MUTED)
	var wh_scroll := ScrollContainer.new()
	wh_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wh_scroll.custom_minimum_size = Vector2(0, 180)
	wh_wrap.add_child(wh_scroll)
	var wh_list := VBoxContainer.new()
	wh_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh_list.add_theme_constant_override("separation", 2)
	wh_scroll.add_child(wh_list)
	var wh_items: Array = _warehouse_state.get("items", [])
	if wh_items.is_empty():
		_add_label(wh_list, "（空）", 11, L2Style.COL_MUTED)
	else:
		for it2 in wh_items:
			if typeof(it2) != TYPE_DICTIONARY:
				continue
			var wid := str(it2.get("id", "")).strip_edges()
			var wq: int = int(it2.get("qty", 0))
			if wid.is_empty() or wq <= 0:
				continue
			var wrow := Button.new()
			wrow.text = "%s ×%d" % [_item_label(wid), wq]
			wrow.focus_mode = Control.FOCUS_NONE
			wrow.alignment = HORIZONTAL_ALIGNMENT_LEFT
			wrow.tooltip_text = "取出 1 个（Shift+点击取出全部）"
			wrow.pressed.connect(_on_warehouse_withdraw_pressed.bind(wid, wq))
			wh_list.add_child(wrow)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	_warehouse_body.add_child(gold_row)
	_add_label(gold_row, "金币", 12, L2Style.COL_TEXT)
	_warehouse_gold_spin = SpinBox.new()
	_warehouse_gold_spin.min_value = 1
	_warehouse_gold_spin.max_value = 999999999
	_warehouse_gold_spin.value = 1
	_warehouse_gold_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(_warehouse_gold_spin)
	var dep_g := Button.new()
	dep_g.text = "存入"
	dep_g.focus_mode = Control.FOCUS_NONE
	dep_g.pressed.connect(_on_warehouse_deposit_gold)
	gold_row.add_child(dep_g)
	var wd_g := Button.new()
	wd_g.text = "取出"
	wd_g.focus_mode = Control.FOCUS_NONE
	wd_g.pressed.connect(_on_warehouse_withdraw_gold)
	gold_row.add_child(wd_g)


func _on_warehouse_deposit_pressed(item_id: String, stack_qty: int) -> void:
	var qty := stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1
	qty = clampi(qty, 1, maxi(stack_qty, 1))
	if _world_combat != null and _world_combat.has_method("request_warehouse_deposit"):
		_world_combat.request_warehouse_deposit(item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_deposit"):
			_apply_warehouse_result_locally(srv.try_warehouse_deposit(item_id, qty))


func _on_warehouse_withdraw_pressed(item_id: String, stack_qty: int) -> void:
	var qty := stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1
	qty = clampi(qty, 1, maxi(stack_qty, 1))
	if _world_combat != null and _world_combat.has_method("request_warehouse_withdraw"):
		_world_combat.request_warehouse_withdraw(item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_withdraw"):
			_apply_warehouse_result_locally(srv.try_warehouse_withdraw(item_id, qty))


func _on_warehouse_deposit_gold() -> void:
	var amount: int = int(_warehouse_gold_spin.value) if _warehouse_gold_spin else 1
	if _world_combat != null and _world_combat.has_method("request_warehouse_deposit_gold"):
		_world_combat.request_warehouse_deposit_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_deposit_gold"):
			_apply_warehouse_result_locally(srv.try_warehouse_deposit_gold(amount))


func _on_warehouse_withdraw_gold() -> void:
	var amount: int = int(_warehouse_gold_spin.value) if _warehouse_gold_spin else 1
	if _world_combat != null and _world_combat.has_method("request_warehouse_withdraw_gold"):
		_world_combat.request_warehouse_withdraw_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_withdraw_gold"):
			_apply_warehouse_result_locally(srv.try_warehouse_withdraw_gold(amount))


func _apply_warehouse_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"warehouse_update":
				apply_warehouse_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)



func _build_friends_panel() -> void:
	_friends_panel = PanelContainer.new()
	_friends_panel.name = "FriendsPanel"
	_friends_panel.set_script(HudDrag)
	_friends_panel.screen_margin = 4.0
	_friends_panel.min_size = Vector2(280, 220)
	_friends_panel.default_size = Vector2(340, 420)
	_friends_panel.initial_dock = "none"
	_friends_panel.drag_anywhere = true
	add_child(_friends_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_friends_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "FriendsTitle"
	title.text = "好友"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _friends_panel.visible = false)
	head.add_child(close_btn)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	outer.add_child(add_row)
	_friends_add_input = LineEdit.new()
	_friends_add_input.placeholder_text = "输入玩家名字"
	_friends_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_add_input.text_submitted.connect(func(t: String): _on_friend_add(t))
	add_row.add_child(_friends_add_input)
	var add_btn := Button.new()
	add_btn.text = "添加"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(func(): _on_friend_add(_friends_add_input.text if _friends_add_input else ""))
	add_row.add_child(add_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	outer.add_child(scroll)
	_friends_body = VBoxContainer.new()
	_friends_body.name = "FriendsBody"
	_friends_body.add_theme_constant_override("separation", 4)
	_friends_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_friends_body)
	_friends_panel.visible = false
	_apply_l2_chrome(_friends_panel)
	_refresh_friends_panel()
	call_deferred("_nudge_friends")


func _nudge_friends() -> void:
	if _friends_panel == null:
		return
	_friends_panel.size = Vector2(340, 420)
	var vp := get_viewport_rect().size
	_friends_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 96)


func _toggle_friends_panel(force_open: bool = false) -> void:
	if _friends_panel == null:
		return
	if force_open:
		_friends_panel.visible = true
	else:
		_friends_panel.visible = not _friends_panel.visible
	if _friends_panel.visible:
		# Refresh online flags from server snapshot when opening.
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_friends"):
			apply_friends_update({"type": "friends_update", "friends": srv.snapshot_friends()})
		_refresh_friends_panel()
		_friends_panel.move_to_front()
		call_deferred("_nudge_friends")


func apply_friends_update(action: Dictionary) -> void:
	var fr_v: Variant = action.get("friends", action)
	if typeof(fr_v) != TYPE_DICTIONARY:
		# Allow raw array payload
		if typeof(fr_v) == TYPE_ARRAY:
			_friends_state = {"friends": [], "count": 0, "max_friends": 50}
			var cleaned0: Array = []
			for e0 in fr_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append({
						"id": str(e0.get("id", "")),
						"name": str(e0.get("name", "?")),
						"online": bool(e0.get("online", false)),
					})
			_friends_state["friends"] = cleaned0
			_friends_state["count"] = cleaned0.size()
			if _friends_panel != null and _friends_panel.visible:
				_refresh_friends_panel()
		return
	var fr: Dictionary = fr_v
	_friends_state = {
		"friends": [],
		"count": int(fr.get("count", 0)),
		"max_friends": int(fr.get("max_friends", 50)),
	}
	var list_v: Variant = fr.get("friends", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			cleaned.append({
				"id": str(e.get("id", "")),
				"name": str(e.get("name", "?")),
				"online": bool(e.get("online", false)),
			})
		_friends_state["friends"] = cleaned
		_friends_state["count"] = cleaned.size()
	if _friends_panel != null and _friends_panel.visible:
		_refresh_friends_panel()


func _refresh_friends_panel() -> void:
	if _friends_body == null:
		return
	for c in _friends_body.get_children():
		c.queue_free()
	var friends_v: Variant = _friends_state.get("friends", [])
	var friends: Array = friends_v if typeof(friends_v) == TYPE_ARRAY else []
	var cap := int(_friends_state.get("max_friends", 50))
	_add_label(_friends_body, "人数 %d / %d" % [friends.size(), cap], 11, L2Style.COL_MUTED)
	if friends.is_empty():
		_add_label(_friends_body, "（暂无好友）", 12, L2Style.COL_MUTED)
		return
	for e in friends:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var fid := str(e.get("id", ""))
		var fname := str(e.get("name", "?"))
		var online := bool(e.get("online", false))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_friends_body.add_child(row)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		row.add_child(name_row)
		var nl := Label.new()
		nl.text = "%s（%s）" % [fname, "在线" if online else "离线"]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75) if online else Color(0.65, 0.65, 0.7))
		name_row.add_child(nl)
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		var whisper_btn := Button.new()
		whisper_btn.text = "私聊"
		whisper_btn.focus_mode = Control.FOCUS_NONE
		whisper_btn.custom_minimum_size = Vector2(48, 24)
		whisper_btn.pressed.connect(_on_friend_whisper.bind(fname))
		btn_row.add_child(whisper_btn)
		var invite_btn := Button.new()
		invite_btn.text = "邀请入队"
		invite_btn.focus_mode = Control.FOCUS_NONE
		invite_btn.custom_minimum_size = Vector2(72, 24)
		invite_btn.pressed.connect(_on_friend_invite.bind(fname))
		btn_row.add_child(invite_btn)
		var ginv_btn := Button.new()
		ginv_btn.text = "邀请入会"
		ginv_btn.focus_mode = Control.FOCUS_NONE
		ginv_btn.custom_minimum_size = Vector2(72, 24)
		ginv_btn.pressed.connect(_on_guild_invite.bind(fname))
		btn_row.add_child(ginv_btn)
		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(48, 24)
		del_btn.pressed.connect(_on_friend_remove.bind(fid))
		btn_row.add_child(del_btn)


func _on_friend_add(name_or_id: String) -> void:
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		append_system("请输入要添加的玩家名字。")
		return
	if _friends_add_input != null:
		_friends_add_input.text = ""
	if _world_combat != null and _world_combat.has_method("request_friend_add"):
		_world_combat.request_friend_add(name_or_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_friend_add"):
		_apply_friends_result_locally(srv.try_friend_add(name_or_id))
	else:
		append_system("无法添加好友。")


func _on_friend_remove(friend_id: String) -> void:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_friend_remove"):
		_world_combat.request_friend_remove(friend_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_friend_remove"):
		_apply_friends_result_locally(srv.try_friend_remove(friend_id))


func _on_friend_whisper(target_name: String) -> void:
	prefill_whisper(str(target_name).strip_edges())


func _on_friend_invite(target_name: String) -> void:
	_on_party_invite(str(target_name).strip_edges())


func _apply_friends_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"friends_update":
				apply_friends_update(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)



func _build_mail_panel() -> void:
	_mail_panel = PanelContainer.new()
	_mail_panel.name = "MailPanel"
	_mail_panel.set_script(HudDrag)
	_mail_panel.screen_margin = 4.0
	_mail_panel.min_size = Vector2(420, 320)
	_mail_panel.default_size = Vector2(520, 480)
	_mail_panel.initial_dock = "none"
	_mail_panel.drag_anywhere = true
	add_child(_mail_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_mail_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "MailTitle"
	title.text = "邮件"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _mail_panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	outer.add_child(scroll)
	_mail_body = VBoxContainer.new()
	_mail_body.name = "MailBody"
	_mail_body.add_theme_constant_override("separation", 4)
	_mail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mail_body)
	_add_label(outer, "写信", 12, L2Style.COL_TITLE)
	_mail_to_input = LineEdit.new()
	_mail_to_input.placeholder_text = "收件人（自己 / 好友 / 旅人）"
	outer.add_child(_mail_to_input)
	_mail_subject_input = LineEdit.new()
	_mail_subject_input.placeholder_text = "主题"
	outer.add_child(_mail_subject_input)
	_mail_body_input = TextEdit.new()
	_mail_body_input.custom_minimum_size = Vector2(0, 64)
	_mail_body_input.placeholder_text = "正文"
	outer.add_child(_mail_body_input)
	var attach_row := HBoxContainer.new()
	attach_row.add_theme_constant_override("separation", 6)
	outer.add_child(attach_row)
	_add_label(attach_row, "金币", 11, L2Style.COL_MUTED)
	_mail_gold_spin = SpinBox.new()
	_mail_gold_spin.min_value = 0
	_mail_gold_spin.max_value = 999999
	_mail_gold_spin.step = 1
	_mail_gold_spin.custom_minimum_size = Vector2(90, 0)
	attach_row.add_child(_mail_gold_spin)
	_add_label(attach_row, "物品ID", 11, L2Style.COL_MUTED)
	_mail_item_id_input = LineEdit.new()
	_mail_item_id_input.placeholder_text = "可选"
	_mail_item_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_row.add_child(_mail_item_id_input)
	_add_label(attach_row, "数量", 11, L2Style.COL_MUTED)
	_mail_item_qty_spin = SpinBox.new()
	_mail_item_qty_spin.min_value = 1
	_mail_item_qty_spin.max_value = 99
	_mail_item_qty_spin.value = 1
	_mail_item_qty_spin.custom_minimum_size = Vector2(70, 0)
	attach_row.add_child(_mail_item_qty_spin)
	var send_btn := Button.new()
	send_btn.text = "发送"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(_on_mail_send)
	outer.add_child(send_btn)
	_mail_panel.visible = false
	_apply_l2_chrome(_mail_panel)
	_refresh_mail_panel()
	call_deferred("_nudge_mail")


func _nudge_mail() -> void:
	if _mail_panel == null:
		return
	_mail_panel.size = Vector2(520, 480)
	var vp := get_viewport_rect().size
	_mail_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 260)), 72)


func _toggle_mail_panel(force_open: bool = false) -> void:
	if _mail_panel == null:
		return
	if force_open:
		_mail_panel.visible = true
	else:
		_mail_panel.visible = not _mail_panel.visible
	if _mail_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_mail"):
			apply_mail_update({"type": "mail_update", "mail": srv.snapshot_mail()})
		_refresh_mail_panel()
		_mail_panel.move_to_front()
		call_deferred("_nudge_mail")


func apply_mail_update(action: Dictionary) -> void:
	var mail_v: Variant = action.get("mail", action)
	if typeof(mail_v) != TYPE_DICTIONARY:
		if typeof(mail_v) == TYPE_ARRAY:
			_mail_state = {"mails": [], "count": 0, "max_mail": 30}
			var cleaned0: Array = []
			for e0 in mail_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append((e0 as Dictionary).duplicate(true))
			_mail_state["mails"] = cleaned0
			_mail_state["count"] = cleaned0.size()
			if _mail_panel != null and _mail_panel.visible:
				_refresh_mail_panel()
		return
	var md: Dictionary = mail_v
	_mail_state = {
		"mails": [],
		"count": int(md.get("count", 0)),
		"max_mail": int(md.get("max_mail", 30)),
	}
	var list_v: Variant = md.get("mails", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) == TYPE_DICTIONARY:
				cleaned.append((e as Dictionary).duplicate(true))
		_mail_state["mails"] = cleaned
		_mail_state["count"] = cleaned.size()
	if _mail_panel != null and _mail_panel.visible:
		_refresh_mail_panel()


func _refresh_mail_panel() -> void:
	if _mail_body == null:
		return
	for c in _mail_body.get_children():
		c.queue_free()
	var mails_v: Variant = _mail_state.get("mails", [])
	var mails: Array = mails_v if typeof(mails_v) == TYPE_ARRAY else []
	var cap := int(_mail_state.get("max_mail", 30))
	_add_label(_mail_body, "收件箱 %d / %d" % [mails.size(), cap], 11, L2Style.COL_MUTED)
	if mails.is_empty():
		_add_label(_mail_body, "（暂无邮件）", 12, L2Style.COL_MUTED)
		return
	for e in mails:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var mid := str(e.get("id", ""))
		var frm := str(e.get("from", "?"))
		var subj := str(e.get("subject", "（无主题）"))
		var is_read := bool(e.get("read", false))
		var claimed := bool(e.get("claimed", false))
		var gold := int(e.get("gold", 0))
		var items_v2: Variant = e.get("items", [])
		var items2: Array = items_v2 if typeof(items_v2) == TYPE_ARRAY else []
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_mail_body.add_child(row)
		var mark := "" if is_read else "● "
		var attach_hint := ""
		if not claimed and (gold > 0 or not items2.is_empty()):
			attach_hint = " [附件]"
		var nl := Label.new()
		nl.text = "%s%s ← %s%s" % [mark, subj, frm, attach_hint]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.7) if not is_read else L2Style.COL_TEXT)
		row.add_child(nl)
		var body_txt := str(e.get("body", "")).strip_edges()
		if not body_txt.is_empty():
			_add_label(row, body_txt, 10, L2Style.COL_MUTED)
		if gold > 0 or not items2.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			if gold > 0:
				parts.append("金币 %d" % gold)
			for it in items2:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid := str(it.get("id", ""))
				var q := int(it.get("qty", 0))
				if iid.is_empty() or q <= 0:
					continue
				parts.append("%s×%d" % [_item_label(iid), q])
			if parts.size() > 0:
				_add_label(row, "附件：%s%s" % [", ".join(parts), "（已领）" if claimed else ""], 10, L2Style.COL_GOLD)
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		var read_btn := Button.new()
		read_btn.text = "阅读"
		read_btn.focus_mode = Control.FOCUS_NONE
		read_btn.custom_minimum_size = Vector2(48, 24)
		read_btn.pressed.connect(_on_mail_read.bind(mid))
		btn_row.add_child(read_btn)
		var claim_btn := Button.new()
		claim_btn.text = "收取"
		claim_btn.focus_mode = Control.FOCUS_NONE
		claim_btn.custom_minimum_size = Vector2(48, 24)
		claim_btn.disabled = claimed or (gold <= 0 and items2.is_empty())
		claim_btn.pressed.connect(_on_mail_claim.bind(mid))
		btn_row.add_child(claim_btn)
		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(48, 24)
		del_btn.pressed.connect(_on_mail_delete.bind(mid))
		btn_row.add_child(del_btn)


func _on_mail_send() -> void:
	var to := _mail_to_input.text.strip_edges() if _mail_to_input else ""
	var subject := _mail_subject_input.text.strip_edges() if _mail_subject_input else ""
	var body := _mail_body_input.text if _mail_body_input else ""
	var gold := int(_mail_gold_spin.value) if _mail_gold_spin else 0
	var item_id := _mail_item_id_input.text.strip_edges() if _mail_item_id_input else ""
	var qty := int(_mail_item_qty_spin.value) if _mail_item_qty_spin else 1
	if to.is_empty():
		append_system("请填写收件人。")
		return
	if _world_combat != null and _world_combat.has_method("request_mail_send"):
		_world_combat.request_mail_send(to, subject, body, gold, item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_mail_send"):
			_apply_mail_result_locally(srv.try_mail_send(to, subject, body, gold, item_id, qty))
		else:
			append_system("无法发送邮件。")
			return
	if _mail_to_input:
		_mail_to_input.text = ""
	if _mail_subject_input:
		_mail_subject_input.text = ""
	if _mail_body_input:
		_mail_body_input.text = ""
	if _mail_gold_spin:
		_mail_gold_spin.value = 0
	if _mail_item_id_input:
		_mail_item_id_input.text = ""
	if _mail_item_qty_spin:
		_mail_item_qty_spin.value = 1


func _on_mail_read(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	_mail_selected_id = mail_id
	if _world_combat != null and _world_combat.has_method("request_mail_read"):
		_world_combat.request_mail_read(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_read"):
		_apply_mail_result_locally(srv.try_mail_read(mail_id))


func _on_mail_claim(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_mail_claim"):
		_world_combat.request_mail_claim(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_claim"):
		_apply_mail_result_locally(srv.try_mail_claim(mail_id))


func _on_mail_delete(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_mail_delete"):
		_world_combat.request_mail_delete(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_delete"):
		_apply_mail_result_locally(srv.try_mail_delete(mail_id))


func _apply_mail_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"mail_update":
				apply_mail_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)


func _ensure_craft_recipes_loaded() -> void:
	if not _craft_recipes.is_empty():
		return
	var cat = RecipeCatalog.new()
	cat.load_catalog()
	_craft_recipes = cat.list_all()
	# Prefer live server catalog when available.
	var srv = Net.server()
	if srv != null and srv.get("recipe_catalog") != null and srv.recipe_catalog != null:
		if srv.recipe_catalog.has_method("list_all"):
			var live: Array = srv.recipe_catalog.list_all()
			if not live.is_empty():
				_craft_recipes = live


func _build_craft_panel() -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.name = "CraftPanel"
	_craft_panel.set_script(HudDrag)
	_craft_panel.screen_margin = 4.0
	_craft_panel.min_size = Vector2(360, 280)
	_craft_panel.default_size = Vector2(480, 420)
	_craft_panel.initial_dock = "none"
	_craft_panel.drag_anywhere = true
	add_child(_craft_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_craft_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "CraftTitle"
	title.text = "制作"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _craft_panel.visible = false)
	head.add_child(close_btn)
	_craft_body = VBoxContainer.new()
	_craft_body.name = "CraftBody"
	_craft_body.add_theme_constant_override("separation", 6)
	_craft_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_craft_body)
	_craft_panel.visible = false
	_apply_l2_chrome(_craft_panel)
	_ensure_craft_recipes_loaded()
	_refresh_craft_panel()
	call_deferred("_nudge_craft")


func _nudge_craft() -> void:
	if _craft_panel == null:
		return
	_craft_panel.size = Vector2(480, 420)
	var vp := get_viewport_rect().size
	_craft_panel.global_position = Vector2(maxi(8, int(vp.x * 0.55 - 240)), 64)


func _toggle_craft_panel(force_open: bool = false) -> void:
	if _craft_panel == null:
		return
	if force_open:
		_craft_panel.visible = true
	else:
		_craft_panel.visible = not _craft_panel.visible
	if _craft_panel.visible:
		_ensure_craft_recipes_loaded()
		_refresh_craft_panel()
		_craft_panel.move_to_front()
		call_deferred("_nudge_craft")


func _inv_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	var n := 0
	for it in _server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id:
			n += int(it.get("qty", 0))
	return n


func _refresh_craft_panel() -> void:
	if _craft_body == null:
		return
	for c in _craft_body.get_children():
		c.queue_free()
	_craft_qty_spin = null
	_ensure_craft_recipes_loaded()
	_add_label(_craft_body, "选择配方后点击制作（任意地点）", 11, L2Style.COL_MUTED)
	_add_label(_craft_body, "金币 %d" % int(_server_gold), 12, L2Style.COL_TITLE)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	_craft_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if _craft_recipes.is_empty():
		_add_label(list, "（暂无配方）", 11, L2Style.COL_MUTED)
	else:
		for rec in _craft_recipes:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			var rid := str(rec.get("id", "")).strip_edges()
			if rid.is_empty():
				continue
			var selected := rid == _craft_selected_id
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			list.add_child(box)
			var head_btn := Button.new()
			var rname := str(rec.get("name", rid))
			var out_v: Variant = rec.get("output", {})
			var out_id := ""
			var out_q := 1
			if typeof(out_v) == TYPE_DICTIONARY:
				out_id = str(out_v.get("id", "")).strip_edges()
				out_q = maxi(int(out_v.get("qty", 1)), 1)
			var out_label := _item_label(out_id) if not out_id.is_empty() else "?"
			head_btn.text = ("%s → %s×%d" % [rname, out_label, out_q]) if not selected else ("▸ %s → %s×%d" % [rname, out_label, out_q])
			head_btn.focus_mode = Control.FOCUS_NONE
			head_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			head_btn.pressed.connect(_on_craft_select.bind(rid))
			box.add_child(head_btn)
			var ings_v: Variant = rec.get("ingredients", [])
			var mats_ok := true
			if typeof(ings_v) == TYPE_ARRAY:
				for ing in ings_v:
					if typeof(ing) != TYPE_DICTIONARY:
						continue
					var iid := str(ing.get("id", "")).strip_edges()
					var need: int = maxi(int(ing.get("qty", 0)), 0)
					if iid.is_empty() or need <= 0:
						continue
					var have: int = _inv_qty(iid)
					if have < need:
						mats_ok = false
					var col = L2Style.COL_TITLE if have >= need else Color(0.95, 0.45, 0.45)
					_add_label(box, "  %s  %d / %d" % [_item_label(iid), have, need], 11, col)
			var gcost: int = maxi(int(rec.get("gold_cost", 0)), 0)
			if gcost > 0:
				var gcol = L2Style.COL_MUTED if int(_server_gold) >= gcost else Color(0.95, 0.45, 0.45)
				_add_label(box, "  金币 %d" % gcost, 11, gcol)
				if int(_server_gold) < gcost:
					mats_ok = false
			if selected:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)
				box.add_child(row)
				_add_label(row, "数量", 12, L2Style.COL_TEXT)
				_craft_qty_spin = SpinBox.new()
				_craft_qty_spin.min_value = 1
				_craft_qty_spin.max_value = 99
				_craft_qty_spin.value = 1
				_craft_qty_spin.custom_minimum_size = Vector2(72, 0)
				row.add_child(_craft_qty_spin)
				var craft_btn := Button.new()
				craft_btn.text = "制作"
				craft_btn.focus_mode = Control.FOCUS_NONE
				craft_btn.disabled = not mats_ok
				craft_btn.pressed.connect(_on_craft_pressed.bind(rid))
				row.add_child(craft_btn)

	_add_label(
		_craft_body,
		"制作 Lv.%d (%d/%d)" % [_craft_level, _craft_xp, _craft_xp_to_next],
		11,
		L2Style.COL_MUTED
	)


func _on_craft_select(recipe_id: String) -> void:
	_craft_selected_id = str(recipe_id).strip_edges()
	_refresh_craft_panel()


func _on_craft_pressed(recipe_id: String) -> void:
	recipe_id = str(recipe_id).strip_edges()
	if recipe_id.is_empty():
		return
	var qty := 1
	if _craft_qty_spin != null:
		qty = clampi(int(_craft_qty_spin.value), 1, 99)
	if _world_combat != null and _world_combat.has_method("request_craft"):
		_world_combat.request_craft(recipe_id, qty)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_craft"):
		_apply_craft_result_locally(srv.try_craft(recipe_id, qty))
	else:
		append_system("无法制作。")


func apply_craft_update(action: Dictionary) -> void:
	if action.has("craft_level"):
		_craft_level = maxi(int(action.get("craft_level", 1)), 1)
	if action.has("craft_xp"):
		_craft_xp = maxi(int(action.get("craft_xp", 0)), 0)
	if action.has("craft_xp_to_next"):
		_craft_xp_to_next = maxi(int(action.get("craft_xp_to_next", 0)), 0)
	if _craft_panel != null and _craft_panel.visible:
		_refresh_craft_panel()


func apply_gather_update(action: Dictionary) -> void:
	## Profession skill packet (gather_level/xp). Node deplete packets omit these keys.
	if action.has("gather_level"):
		_gather_level = maxi(int(action.get("gather_level", 1)), 1)
	if action.has("gather_xp"):
		_gather_xp = maxi(int(action.get("gather_xp", 0)), 0)
	if action.has("gather_xp_to_next"):
		_gather_xp_to_next = maxi(int(action.get("gather_xp_to_next", 0)), 0)
	if _gather_level_label != null and is_instance_valid(_gather_level_label):
		_gather_level_label.text = "采集 Lv.%d" % _gather_level


func _apply_craft_result_locally(result: Dictionary) -> void:
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
			"craft_update":
				apply_craft_update(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
	if _craft_panel != null and _craft_panel.visible:
		_refresh_craft_panel()

func _build_emote_panel() -> void:
	_emote_panel = PanelContainer.new()
	_emote_panel.name = "EmotePanel"
	_emote_panel.set_script(HudDrag)
	_emote_panel.screen_margin = 4.0
	_emote_panel.min_size = Vector2(280, 200)
	_emote_panel.default_size = Vector2(340, 280)
	_emote_panel.initial_dock = "none"
	_emote_panel.drag_anywhere = true
	add_child(_emote_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_emote_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "EmoteTitle"
	title.text = "表情"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _emote_panel.visible = false)
	head.add_child(close_btn)
	_emote_body = VBoxContainer.new()
	_emote_body.name = "EmoteBody"
	_emote_body.add_theme_constant_override("separation", 6)
	_emote_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_emote_body)
	_emote_panel.visible = false
	_apply_l2_chrome(_emote_panel)
	_refresh_emote_panel()
	call_deferred("_nudge_emote")


func _nudge_emote() -> void:
	if _emote_panel == null:
		return
	_emote_panel.size = Vector2(340, 280)
	var vp := get_viewport_rect().size
	_emote_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 96)


func _toggle_emote_panel(force_open: bool = false) -> void:
	if _emote_panel == null:
		return
	if force_open:
		_emote_panel.visible = true
	else:
		_emote_panel.visible = not _emote_panel.visible
	if _emote_panel.visible:
		_refresh_emote_panel()
		_emote_panel.move_to_front()
		call_deferred("_nudge_emote")


func _emote_catalog_rows() -> Array:
	var srv = Net.server()
	if srv != null and srv.has_method("emote_catalog"):
		var live: Array = srv.emote_catalog()
		if not live.is_empty():
			return live
	# Static mirror of MockServer.EMOTE_CATALOG labels (fallback).
	return [
		{"id": "wave", "label": "挥手", "text": "（挥手）"},
		{"id": "laugh", "label": "大笑", "text": "哈哈哈"},
		{"id": "bow", "label": "鞠躬", "text": "（鞠躬）"},
		{"id": "cry", "label": "哭泣", "text": "（呜呜）"},
		{"id": "angry", "label": "生气", "text": "（哼！）"},
		{"id": "love", "label": "爱心", "text": "❤"},
		{"id": "cheer", "label": "加油", "text": "（加油！）"},
		{"id": "think", "label": "思考", "text": "（思考中…）"},
		{"id": "shrug", "label": "耸肩", "text": "（耸肩）"},
		{"id": "clap", "label": "鼓掌", "text": "（啪啪啪）"},
		{"id": "sleepy", "label": "困倦", "text": "（打哈欠）"},
		{"id": "wow", "label": "惊讶", "text": "（哇！）"},
	]


func _refresh_emote_panel() -> void:
	if _emote_body == null:
		return
	for c in _emote_body.get_children():
		c.queue_free()
	_add_label(_emote_body, "选择表情（服务器冷却）", 11, L2Style.COL_MUTED)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emote_body.add_child(grid)
	var rows: Array = _emote_catalog_rows()
	if rows.is_empty():
		_add_label(_emote_body, "（暂无表情）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var eid := str(row.get("id", "")).strip_edges()
		if eid.is_empty():
			continue
		var btn := Button.new()
		btn.text = str(row.get("label", eid))
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(96, 32)
		btn.pressed.connect(_on_emote_pressed.bind(eid))
		grid.add_child(btn)


func _on_emote_pressed(emote_id: String) -> void:
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_emote"):
		_world_combat.request_emote(emote_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_emote"):
		_apply_emote_result_locally(srv.try_emote(emote_id))
	else:
		append_system("无法使用表情。")


func _apply_emote_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
			"emote":
				# Without world host, still echo bubble text to system chat.
				var bubble := str(action.get("text", "")).strip_edges()
				if not bubble.is_empty():
					append_system(bubble)



## --- 战斗日志 panel (client ring buffer; hotkey B) ---


func apply_dps_update(action: Dictionary) -> void:
	## From dps_update opcode — personal fight DPS meter.
	var DpsUtil = preload("res://scripts/ui/dps_meter_util.gd")
	var n: Dictionary = DpsUtil.normalize(action)
	_dps_meter_active = bool(n.get("active", false))
	_dps_meter_value = float(n.get("dps", 0.0))
	_ensure_dps_meter()
	if _dps_meter_label != null:
		_dps_meter_label.text = DpsUtil.format_label(_dps_meter_value)
		if _dps_meter_active:
			_dps_meter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
		else:
			_dps_meter_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.68, 1.0))
	_refresh_dps_meter_visibility()


func _refresh_dps_meter_visibility() -> void:
	_ensure_dps_meter()
	if _dps_meter_panel == null:
		return
	var gs = null
	var Settings = load("res://scripts/game/game_settings.gd")
	if Settings != null and Settings.has_method("get_i"):
		gs = Settings.get_i()
	var setting_on := true
	if gs != null and "show_dps_meter" in gs:
		setting_on = bool(gs.show_dps_meter)
	var DpsUtil = preload("res://scripts/ui/dps_meter_util.gd")
	# Hide when idle; show when active (or setting forces idle zero — we hide).
	_dps_meter_panel.visible = DpsUtil.should_show(setting_on, _dps_meter_active, false)


func _ensure_dps_meter() -> void:
	if _dps_meter_panel != null and is_instance_valid(_dps_meter_panel):
		return
	_build_dps_meter()


func _build_dps_meter() -> void:
	if _dps_meter_panel != null and is_instance_valid(_dps_meter_panel):
		return
	_dps_meter_panel = PanelContainer.new()
	_dps_meter_panel.name = "DpsMeterPanel"
	_dps_meter_panel.set_script(HudDrag)
	_dps_meter_panel.screen_margin = 4.0
	_dps_meter_panel.min_size = Vector2(88, 28)
	_dps_meter_panel.default_size = Vector2(110, 32)
	_dps_meter_panel.initial_dock = "none"
	_dps_meter_panel.drag_anywhere = true
	_dps_meter_panel.resizable = false
	add_child(_dps_meter_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 8)
	marg.add_theme_constant_override("margin_top", 4)
	marg.add_theme_constant_override("margin_right", 8)
	marg.add_theme_constant_override("margin_bottom", 4)
	_dps_meter_panel.add_child(marg)
	_dps_meter_label = Label.new()
	_dps_meter_label.name = "DpsMeterLabel"
	_dps_meter_label.text = "DPS 0"
	_dps_meter_label.add_theme_font_size_override("font_size", 13)
	_dps_meter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	_dps_meter_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	_dps_meter_label.add_theme_constant_override("outline_size", 2)
	_dps_meter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_child(_dps_meter_label)
	if has_method("_apply_l2_chrome"):
		_apply_l2_chrome(_dps_meter_panel)
	_dps_meter_panel.visible = false
	call_deferred("_nudge_dps_meter")


func _nudge_dps_meter() -> void:
	if _dps_meter_panel == null:
		return
	_dps_meter_panel.size = Vector2(110, 32)
	var vp := get_viewport_rect().size
	# Near combat log / bottom-left.
	_dps_meter_panel.global_position = Vector2(12, maxf(8.0, vp.y - 120.0))


func _ensure_combat_log() -> void:
	if _combat_log == null:
		_combat_log = CombatLogScript.new()


func _build_combat_log_panel() -> void:
	_ensure_combat_log()
	_combat_log_panel = PanelContainer.new()
	_combat_log_panel.name = "CombatLogPanel"
	_combat_log_panel.set_script(HudDrag)
	_combat_log_panel.screen_margin = 4.0
	_combat_log_panel.min_size = Vector2(280, 200)
	_combat_log_panel.default_size = Vector2(320, 290)
	_combat_log_panel.initial_dock = "none"
	_combat_log_panel.drag_anywhere = true
	add_child(_combat_log_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	_combat_log_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "CombatLogTitle"
	title.text = "战斗日志"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var clear_btn := Button.new()
	clear_btn.text = "清除"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_combat_log_clear)
	head.add_child(clear_btn)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _combat_log_panel.visible = false)
	head.add_child(close_btn)
	_combat_log_filter_row = HBoxContainer.new()
	_combat_log_filter_row.name = "CombatLogFilters"
	_combat_log_filter_row.add_theme_constant_override("separation", 8)
	outer.add_child(_combat_log_filter_row)
	_build_combat_log_filters()
	_combat_log_scroll = ScrollContainer.new()
	_combat_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combat_log_scroll.custom_minimum_size = Vector2(0, 180)
	_combat_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_combat_log_scroll)
	_combat_log_body = VBoxContainer.new()
	_combat_log_body.name = "CombatLogBody"
	_combat_log_body.add_theme_constant_override("separation", 2)
	_combat_log_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combat_log_scroll.add_child(_combat_log_body)
	_combat_log_panel.visible = false
	_apply_l2_chrome(_combat_log_panel)
	_refresh_combat_log_panel()
	call_deferred("_nudge_combat_log")


func _nudge_combat_log() -> void:
	if _combat_log_panel == null:
		return
	_combat_log_panel.size = Vector2(320, 290)
	var vp := get_viewport_rect().size
	_combat_log_panel.global_position = Vector2(12, maxi(8, int(vp.y * 0.35)))


func _toggle_combat_log_panel(force_open: bool = false) -> void:
	if _combat_log_panel == null:
		_build_combat_log_panel()
	if force_open:
		_combat_log_panel.visible = true
	else:
		_combat_log_panel.visible = not _combat_log_panel.visible
	if _combat_log_panel.visible:
		_refresh_combat_log_panel()
		_combat_log_panel.move_to_front()
		call_deferred("_nudge_combat_log")


func _on_combat_log_clear() -> void:
	_ensure_combat_log()
	_combat_log.clear()
	_refresh_combat_log_panel()


func _refresh_combat_log_panel() -> void:
	if _combat_log_body == null:
		return
	_ensure_combat_log()
	for c in _combat_log_body.get_children():
		c.queue_free()
	var flags := _combat_log_filter_flags()
	var rows: PackedStringArray = _combat_log.filtered_lines(flags)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "（暂无战斗记录）" if _combat_log.size() == 0 else "（当前筛选无记录）"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_combat_log_body.add_child(empty)
	else:
		for line in rows:
			var lab := Label.new()
			lab.text = str(line)
			lab.add_theme_font_size_override("font_size", 12)
			lab.add_theme_color_override("font_color", Color(0.88, 0.55, 0.42))
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_combat_log_body.add_child(lab)
	# Scroll to bottom after layout.
	if _combat_log_scroll != null:
		call_deferred("_combat_log_scroll_to_end")


func _combat_log_filter_flags() -> Dictionary:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return {
			"show_damage": true,
			"show_heal": true,
			"show_miss": true,
			"show_kill": true,
		}
	return {
		"show_damage": bool(gs.get("combat_log_show_damage")),
		"show_heal": bool(gs.get("combat_log_show_heal")),
		"show_miss": bool(gs.get("combat_log_show_miss")),
		"show_kill": bool(gs.get("combat_log_show_kill")),
	}


func _build_combat_log_filters() -> void:
	if _combat_log_filter_row == null:
		return
	for c in _combat_log_filter_row.get_children():
		c.queue_free()
	var specs := [
		["伤害", "combat_log_show_damage"],
		["治疗", "combat_log_show_heal"],
		["未命中", "combat_log_show_miss"],
		["击杀", "combat_log_show_kill"],
	]
	var gs := GameSettingsScript.get_i()
	for spec in specs:
		var label: String = spec[0]
		var key: String = spec[1]
		var box := CheckBox.new()
		box.text = label
		box.focus_mode = Control.FOCUS_NONE
		box.button_pressed = true if gs == null else bool(gs.get(key))
		var captured_key := key
		box.toggled.connect(func(on: bool):
			var g := GameSettingsScript.get_i()
			if g != null:
				g.set_flag(captured_key, on)
			_refresh_combat_log_panel()
		)
		_combat_log_filter_row.add_child(box)


func _combat_log_scroll_to_end() -> void:
	if _combat_log_scroll == null:
		return
	await get_tree().process_frame
	if _combat_log_scroll == null or not is_instance_valid(_combat_log_scroll):
		return
	var bar := _combat_log_scroll.get_v_scroll_bar()
	if bar != null:
		_combat_log_scroll.scroll_vertical = int(bar.max_value)


## --- 称号 panel ---

func _build_titles_panel() -> void:
	_titles_panel = PanelContainer.new()
	_titles_panel.name = "TitlesPanel"
	_titles_panel.set_script(HudDrag)
	_titles_panel.screen_margin = 4.0
	_titles_panel.min_size = Vector2(300, 240)
	_titles_panel.default_size = Vector2(360, 440)
	_titles_panel.initial_dock = "none"
	_titles_panel.drag_anywhere = true
	add_child(_titles_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_titles_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "TitlesTitle"
	title.text = "称号"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _titles_panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	outer.add_child(scroll)
	_titles_body = VBoxContainer.new()
	_titles_body.name = "TitlesBody"
	_titles_body.add_theme_constant_override("separation", 6)
	_titles_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_titles_body)
	_titles_panel.visible = false
	_apply_l2_chrome(_titles_panel)
	_refresh_titles_panel()
	call_deferred("_nudge_titles")


func _nudge_titles() -> void:
	if _titles_panel == null:
		return
	_titles_panel.size = Vector2(360, 440)
	var vp := get_viewport_rect().size
	_titles_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 88)


func _toggle_titles_panel(force_open: bool = false) -> void:
	if _titles_panel == null:
		return
	if force_open:
		_titles_panel.visible = true
	else:
		_titles_panel.visible = not _titles_panel.visible
	if _titles_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_titles"):
			apply_title_update({"type": "title_update", "titles": srv.snapshot_titles()})
		_refresh_titles_panel()
		_titles_panel.move_to_front()
		call_deferred("_nudge_titles")


func apply_title_update(action: Dictionary) -> void:
	var tv: Variant = action.get("titles", action)
	if typeof(tv) != TYPE_DICTIONARY:
		return
	var d: Dictionary = tv
	_titles_state = {
		"counters": d.get("counters", {}).duplicate(true) if typeof(d.get("counters", {})) == TYPE_DICTIONARY else {},
		"unlocked_titles": d.get("unlocked_titles", []).duplicate() if typeof(d.get("unlocked_titles", [])) == TYPE_ARRAY else [],
		"active_title": str(d.get("active_title", "")),
		"titles": d.get("titles", []).duplicate(true) if typeof(d.get("titles", [])) == TYPE_ARRAY else [],
		"kills": int(d.get("kills", 0)),
		"crafts": int(d.get("crafts", 0)),
		"deaths": int(d.get("deaths", 0)),
	}
	_refresh_name_with_title()
	if _titles_panel != null and _titles_panel.visible:
		_refresh_titles_panel()


func _build_daily_panel() -> void:
	_daily_panel = PanelContainer.new()
	_daily_panel.name = "DailyQuestPanel"
	_daily_panel.set_script(HudDrag)
	_daily_panel.screen_margin = 4.0
	_daily_panel.min_size = Vector2(280, 180)
	_daily_panel.default_size = Vector2(340, 280)
	_daily_panel.initial_dock = "none"
	_daily_panel.drag_anywhere = true
	add_child(_daily_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_daily_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "DailyTitle"
	title.text = "日常任务"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _daily_panel.visible = false)
	head.add_child(close_btn)
	var date_lbl := Label.new()
	date_lbl.name = "DailyDateLabel"
	date_lbl.text = ""
	date_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
	outer.add_child(date_lbl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	outer.add_child(scroll)
	_daily_body = VBoxContainer.new()
	_daily_body.name = "DailyBody"
	_daily_body.add_theme_constant_override("separation", 6)
	_daily_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_daily_body)
	_daily_panel.visible = false
	_apply_l2_chrome(_daily_panel)
	_refresh_daily_panel()
	call_deferred("_nudge_daily")


func _nudge_daily() -> void:
	if _daily_panel == null:
		return
	_daily_panel.size = Vector2(340, 280)
	var vp := get_viewport_rect().size
	_daily_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 100)


func _toggle_daily_panel(force_open: bool = false) -> void:
	if _daily_panel == null:
		return
	if force_open:
		_daily_panel.visible = true
	else:
		_daily_panel.visible = not _daily_panel.visible
	if _daily_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_daily"):
			apply_daily_board(srv.snapshot_daily())
		elif srv != null and srv.has_method("try_daily_board_list"):
			apply_daily_board({"daily": srv.try_daily_board_list(), "daily_date": ""})
		_refresh_daily_panel()
		_daily_panel.move_to_front()
		call_deferred("_nudge_daily")


func apply_daily_board(action: Dictionary) -> void:
	var date := str(action.get("daily_date", "")).strip_edges()
	var list_v: Variant = action.get("daily", action.get("daily_quests", []))
	var list: Array = list_v if typeof(list_v) == TYPE_ARRAY else []
	if date != "" or not list.is_empty() or action.has("daily") or action.has("daily_date"):
		_daily_state = {
			"daily_date": date if date != "" else str(_daily_state.get("daily_date", "")),
			"daily": list.duplicate(true),
		}
	if _daily_panel != null and _daily_panel.visible:
		_refresh_daily_panel()


func _refresh_daily_panel() -> void:
	if _daily_body == null:
		return
	for c in _daily_body.get_children():
		c.queue_free()
	var date_lbl: Label = null
	if _daily_panel != null:
		date_lbl = _find_named_descendant(_daily_panel, "DailyDateLabel") as Label
	var ymd := str(_daily_state.get("daily_date", ""))
	if date_lbl != null:
		date_lbl.text = ("日期：%s" % ymd) if ymd != "" else "日常委托"
	var rows: Array = _daily_state.get("daily", [])
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "今日暂无日常。"
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
		_daily_body.add_child(empty)
		return
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var qid := str(row.get("id", "")).strip_edges()
		var state := str(row.get("state", "available")).strip_edges()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		_daily_body.add_child(box)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)
		var name_lbl := Label.new()
		name_lbl.text = str(row.get("title", qid))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_lbl)
		var state_lbl := Label.new()
		var btn_text := "接取"
		match state:
			"accepted":
				state_lbl.text = "已接"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_TITLE)
				btn_text = "已接"
			"done_today":
				state_lbl.text = "已完成"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
				btn_text = "已完成"
			_:
				state_lbl.text = "可接"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_TITLE)
				btn_text = "接取"
		line.add_child(state_lbl)
		var btn := Button.new()
		btn.text = btn_text
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = state != "available"
		btn.custom_minimum_size = Vector2(72, 26)
		var accept_id := qid
		btn.pressed.connect(func():
			if _world_combat != null and _world_combat.has_method("request_accept_quest"):
				_world_combat.request_accept_quest(accept_id)
			# Refresh from server after accept
			var srv = Net.server()
			if srv != null and srv.has_method("snapshot_daily"):
				apply_daily_board(srv.snapshot_daily())
			_refresh_daily_panel()
		)
		line.add_child(btn)
		var rewards := str(row.get("rewards", "")).strip_edges()
		if rewards != "":
			var rlab := Label.new()
			rlab.text = rewards
			rlab.add_theme_color_override("font_color", L2Style.COL_MUTED)
			box.add_child(rlab)


func _find_named_descendant(root: Node, want: String) -> Node:
	if root == null:
		return null
	if root.name == want:
		return root
	for c in root.get_children():
		var f := _find_named_descendant(c, want)
		if f != null:
			return f
	return null


func _active_title_display_name() -> String:
	var aid := str(_titles_state.get("active_title", "")).strip_edges()
	if aid.is_empty():
		return ""
	for row in _titles_state.get("titles", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == aid:
			return str(row.get("name", aid))
	var srv = Net.server()
	if srv != null and srv.get("title_catalog") != null and srv.title_catalog.has_method("title_name"):
		return str(srv.title_catalog.title_name(aid))
	return aid


func _ensure_title_under_name() -> void:
	## Thin Label under StatusPanel nameplate for equipped title (not glued into NameLabel).
	if _title_under_name != null and is_instance_valid(_title_under_name):
		return
	var panel := get_node_or_null("%StatusPanel") as PanelContainer
	if panel == null:
		return
	var vbox := panel.find_child("StatusVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var existing := vbox.get_node_or_null("TitleUnderName") as Label
	if existing != null:
		_title_under_name = existing
	else:
		_title_under_name = Label.new()
		_title_under_name.name = "TitleUnderName"
		_title_under_name.add_theme_font_size_override("font_size", 10)
		_title_under_name.add_theme_color_override("font_color", L2Style.COL_GOLD)
		_title_under_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_under_name.visible = false
		_title_under_name.text = ""
		var name_row := vbox.get_node_or_null("NameRow")
		if name_row != null:
			var idx := name_row.get_index()
			vbox.add_child(_title_under_name)
			vbox.move_child(_title_under_name, idx + 1)
		else:
			vbox.add_child(_title_under_name)
			vbox.move_child(_title_under_name, 0)
	# Slightly taller status so title line fits.
	if panel != null:
		panel.min_size = Vector2(160, 84)
		panel.default_size = Vector2(200, 100)
		panel.custom_minimum_size = Vector2(160, 84)


func _refresh_name_with_title() -> void:
	_ensure_title_under_name()
	if name_label == null:
		return
	var base := _base_char_name.strip_edges()
	if base.is_empty():
		base = str(name_label.text).strip_edges()
		# Strip previous suffix if re-applied without bind.
		var cut := base.find("「")
		if cut > 0:
			base = base.substr(0, cut)
		var cut2 := base.find("【")
		if cut2 > 0:
			base = base.substr(0, cut2)
		if base.is_empty():
			base = "???"
		_base_char_name = base
	var tname := _active_title_display_name()
	var gname := str(_guild_state.get("name", "")).strip_edges()
	var shown := base
	# Title lives on thin Label under nameplate; keep guild suffix on name if any.
	if not gname.is_empty():
		shown = "%s【%s】" % [shown, gname]
	name_label.text = shown
	if _title_under_name != null:
		if tname.is_empty():
			_title_under_name.text = ""
			_title_under_name.visible = false
		else:
			_title_under_name.text = "「%s」" % tname
			_title_under_name.visible = true


func _title_unlock_hint(row: Dictionary) -> String:
	var desc := str(row.get("desc", "")).strip_edges()
	if not desc.is_empty():
		return desc
	var req_v: Variant = row.get("require", {})
	if typeof(req_v) != TYPE_DICTIONARY or (req_v as Dictionary).is_empty():
		return ""
	var parts: Array = []
	var labels := {"kills": "击杀", "crafts": "制作", "deaths": "死亡"}
	for k in (req_v as Dictionary).keys():
		var key := str(k)
		var need: int = int(req_v[k])
		var label := str(labels.get(key, key))
		parts.append("%s %d" % [label, need])
	if parts.is_empty():
		return ""
	return "解锁条件：" + " · ".join(PackedStringArray(parts))


func _refresh_titles_panel() -> void:
	if _titles_body == null:
		return
	for c in _titles_body.get_children():
		c.queue_free()
	var ctr: Dictionary = _titles_state.get("counters", {}) if typeof(_titles_state.get("counters", {})) == TYPE_DICTIONARY else {}
	var kills: int = int(ctr.get("kills", _titles_state.get("kills", 0)))
	var crafts: int = int(ctr.get("crafts", _titles_state.get("crafts", 0)))
	var deaths: int = int(ctr.get("deaths", _titles_state.get("deaths", 0)))
	_add_label(_titles_body, "进度  击杀 %d · 制作 %d · 死亡 %d" % [kills, crafts, deaths], 11, L2Style.COL_MUTED)
	var active := str(_titles_state.get("active_title", ""))
	if active.is_empty():
		_add_label(_titles_body, "当前：无（点击已解锁称号装备）", 12, L2Style.COL_TEXT)
	else:
		_add_label(_titles_body, "当前：%s（再点卸下）" % _active_title_display_name(), 12, L2Style.COL_GOLD)
	var unequip := Button.new()
	unequip.text = "卸下"
	unequip.focus_mode = Control.FOCUS_NONE
	unequip.disabled = active.is_empty()
	unequip.pressed.connect(func(): _on_title_equip(""))
	_titles_body.add_child(unequip)
	var rows: Array = _titles_state.get("titles", [])
	if rows.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_titles"):
			var snap: Dictionary = srv.snapshot_titles()
			rows = snap.get("titles", []) if typeof(snap.get("titles", [])) == TYPE_ARRAY else []
	if rows.is_empty():
		_add_label(_titles_body, "（暂无称号）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var tid := str(row.get("id", "")).strip_edges()
		if tid.is_empty():
			continue
		var unlocked: bool = bool(row.get("unlocked", false))
		var is_active: bool = bool(row.get("active", false)) or tid == active
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		_titles_body.add_child(box)
		var display := str(row.get("name", tid))
		if unlocked:
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if is_active:
				btn.text = "✓ %s  · 装备中" % display
				L2Style.style_row_button(btn, true)
				btn.pressed.connect(_on_title_equip.bind(""))
			else:
				btn.text = "○ %s" % display
				L2Style.style_row_button(btn, false)
				btn.pressed.connect(_on_title_equip.bind(tid))
			box.add_child(btn)
			var desc := str(row.get("desc", "")).strip_edges()
			if not desc.is_empty():
				_add_label(box, desc, 11, L2Style.COL_MUTED)
		else:
			var nm := Label.new()
			nm.text = "🔒 %s" % display
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.add_theme_font_size_override("font_size", 13)
			nm.add_theme_color_override("font_color", L2Style.COL_MUTED)
			nm.modulate = Color(0.72, 0.72, 0.72, 1.0)
			box.add_child(nm)
			var hint := _title_unlock_hint(row)
			if not hint.is_empty():
				_add_label(box, hint, 11, L2Style.COL_MUTED)


func _on_title_equip(title_id: String) -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_title_equip"):
		_apply_title_result_locally(srv.try_title_equip(title_id))
	else:
		append_system("无法装备称号。")


func _apply_title_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
			"title_update":
				apply_title_update(action)


## --- 成就 panel ---

func _build_achievements_panel() -> void:
	_achievements_panel = PanelContainer.new()
	_achievements_panel.name = "AchievementsPanel"
	_achievements_panel.set_script(HudDrag)
	_achievements_panel.screen_margin = 4.0
	_achievements_panel.min_size = Vector2(300, 240)
	_achievements_panel.default_size = Vector2(360, 440)
	_achievements_panel.initial_dock = "none"
	_achievements_panel.drag_anywhere = true
	add_child(_achievements_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_achievements_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "AchievementsTitle"
	title.text = "成就"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _achievements_panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	outer.add_child(scroll)
	_achievements_body = VBoxContainer.new()
	_achievements_body.name = "AchievementsBody"
	_achievements_body.add_theme_constant_override("separation", 6)
	_achievements_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_achievements_body)
	_achievements_panel.visible = false
	_apply_l2_chrome(_achievements_panel)
	_refresh_achievements_panel()
	call_deferred("_nudge_achievements")


func _nudge_achievements() -> void:
	if _achievements_panel == null:
		return
	_achievements_panel.size = Vector2(360, 440)
	var vp := get_viewport_rect().size
	_achievements_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 100)


func _toggle_achievements_panel(force_open: bool = false) -> void:
	if _achievements_panel == null:
		return
	if force_open:
		_achievements_panel.visible = true
	else:
		_achievements_panel.visible = not _achievements_panel.visible
	if _achievements_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_achievements"):
			apply_achievement_update({"type": "achievement_update", "achievements": srv.snapshot_achievements()})
		_refresh_achievements_panel()
		_achievements_panel.move_to_front()
		call_deferred("_nudge_achievements")


func apply_achievement_update(action: Dictionary) -> void:
	var av: Variant = action.get("achievements", action)
	if typeof(av) != TYPE_DICTIONARY:
		return
	var d: Dictionary = av
	_achievements_state = {
		"counters": d.get("counters", {}).duplicate(true) if typeof(d.get("counters", {})) == TYPE_DICTIONARY else {},
		"unlocked_achievements": d.get("unlocked_achievements", []).duplicate() if typeof(d.get("unlocked_achievements", [])) == TYPE_ARRAY else [],
		"achievements": d.get("achievements", []).duplicate(true) if typeof(d.get("achievements", [])) == TYPE_ARRAY else [],
		"kills": int(d.get("kills", 0)),
		"gathers": int(d.get("gathers", 0)),
		"level": int(d.get("level", 1)),
		"party": int(d.get("party", 0)),
	}
	if _achievements_panel != null and _achievements_panel.visible:
		_refresh_achievements_panel()


func _achievement_unlock_hint(row: Dictionary) -> String:
	var desc := str(row.get("desc", "")).strip_edges()
	if not desc.is_empty():
		return desc
	var req_v: Variant = row.get("require", {})
	if typeof(req_v) != TYPE_DICTIONARY:
		return ""
	var labels := {"kills": "击杀", "gathers": "采集", "level": "等级", "party": "组队"}
	var parts: PackedStringArray = PackedStringArray()
	for k in (req_v as Dictionary).keys():
		var key := str(k)
		var need: int = int(req_v[k])
		var label := str(labels.get(key, key))
		parts.append("%s %d" % [label, need])
	if parts.is_empty():
		return ""
	return "解锁条件：" + " · ".join(parts)


func _refresh_achievements_panel() -> void:
	if _achievements_body == null:
		return
	for c in _achievements_body.get_children():
		c.queue_free()
	var ctr: Dictionary = _achievements_state.get("counters", {}) if typeof(_achievements_state.get("counters", {})) == TYPE_DICTIONARY else {}
	var kills: int = int(ctr.get("kills", _achievements_state.get("kills", 0)))
	var gathers: int = int(ctr.get("gathers", _achievements_state.get("gathers", 0)))
	var level: int = int(ctr.get("level", _achievements_state.get("level", 1)))
	var party: int = int(ctr.get("party", _achievements_state.get("party", 0)))
	_add_label(_achievements_body, "进度  击杀 %d · 采集 %d · 等级 %d · 组队 %d" % [kills, gathers, level, party], 11, L2Style.COL_MUTED)
	var rows: Array = _achievements_state.get("achievements", [])
	if rows.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_achievements"):
			var snap: Dictionary = srv.snapshot_achievements()
			rows = snap.get("achievements", []) if typeof(snap.get("achievements", [])) == TYPE_ARRAY else []
	if rows.is_empty():
		_add_label(_achievements_body, "（暂无成就）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var aid := str(row.get("id", "")).strip_edges()
		if aid.is_empty():
			continue
		var unlocked: bool = bool(row.get("unlocked", false))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		_achievements_body.add_child(box)
		var letter := str(row.get("letter", "")).strip_edges()
		var display := str(row.get("name", aid))
		if not letter.is_empty():
			display = "[%s] %s" % [letter, display]
		var nm := Label.new()
		if unlocked:
			nm.text = "✓ %s" % display
			nm.add_theme_color_override("font_color", L2Style.COL_GOLD)
		else:
			nm.text = "🔒 %s" % display
			nm.add_theme_color_override("font_color", L2Style.COL_MUTED)
			nm.modulate = Color(0.72, 0.72, 0.72, 1.0)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", 13)
		box.add_child(nm)
		if unlocked:
			var desc := str(row.get("desc", "")).strip_edges()
			if not desc.is_empty():
				_add_label(box, desc, 11, L2Style.COL_MUTED)
			var rew_v: Variant = row.get("reward", {})
			if typeof(rew_v) == TYPE_DICTIONARY:
				var rg: int = int(rew_v.get("gold", 0))
				var re: int = int(rew_v.get("exp", 0))
				if rg > 0 or re > 0:
					var bits: PackedStringArray = PackedStringArray()
					if rg > 0:
						bits.append("金 %d" % rg)
					if re > 0:
						bits.append("经验 %d" % re)
					_add_label(box, "奖励：" + " · ".join(bits), 11, L2Style.COL_MUTED)
		else:
			var hint := _achievement_unlock_hint(row)
			if not hint.is_empty():
				_add_label(box, hint, 11, L2Style.COL_MUTED)


## --- Guild panel ---

func _build_guild_panel() -> void:
	_guild_panel = PanelContainer.new()
	_guild_panel.name = "GuildPanel"
	_guild_panel.set_script(HudDrag)
	_guild_panel.screen_margin = 4.0
	_guild_panel.min_size = Vector2(300, 260)
	_guild_panel.default_size = Vector2(360, 460)
	_guild_panel.initial_dock = "none"
	_guild_panel.drag_anywhere = true
	add_child(_guild_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_guild_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "GuildTitle"
	title.text = "公会"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _guild_panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	outer.add_child(scroll)
	_guild_body = VBoxContainer.new()
	_guild_body.name = "GuildBody"
	_guild_body.add_theme_constant_override("separation", 4)
	_guild_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_guild_body)
	_guild_panel.visible = false
	_apply_l2_chrome(_guild_panel)
	_refresh_guild_panel()
	call_deferred("_nudge_guild")


func _nudge_guild() -> void:
	if _guild_panel == null:
		return
	_guild_panel.size = Vector2(360, 460)
	var vp := get_viewport_rect().size
	_guild_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 88)


func _toggle_guild_panel(force_open: bool = false) -> void:
	if _guild_panel == null:
		return
	if force_open:
		_guild_panel.visible = true
	else:
		_guild_panel.visible = not _guild_panel.visible
	if _guild_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_guild"):
			apply_guild_update({"type": "guild_update", "guild": srv.snapshot_guild()})
		_refresh_guild_panel()
		_guild_panel.move_to_front()
		call_deferred("_nudge_guild")


func apply_guild_update(action: Dictionary) -> void:
	var gu_v: Variant = action.get("guild", action)
	if typeof(gu_v) != TYPE_DICTIONARY:
		return
	var gu: Dictionary = gu_v
	var members_out: Array = []
	var mem_v: Variant = gu.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		for e in mem_v:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			members_out.append({
				"id": str(e.get("id", "")),
				"name": str(e.get("name", "?")),
				"rank": str(e.get("rank", "member")),
			})
	_guild_state = {
		"id": str(gu.get("id", "")),
		"name": str(gu.get("name", "")),
		"leader_id": str(gu.get("leader_id", "")),
		"members": members_out,
	}
	_refresh_name_with_title()
	if _guild_panel != null and _guild_panel.visible:
		_refresh_guild_panel()
	# Refresh character window 血盟 chip if open.
	if _windows.has("character"):
		var cw: Variant = _windows["character"]
		if cw is Control and (cw as Control).visible:
			_fill_window("character")


func apply_guild_invite(action: Dictionary) -> void:
	var status := str(action.get("status", "pending"))
	var invite_id := str(action.get("invite_id", "")).strip_edges()
	var gname := str(action.get("guild_name", "")).strip_edges()
	var from_name := str(action.get("from", "")).strip_edges()
	if status == "pending" and not invite_id.is_empty():
		_guild_pending_invite = {
			"invite_id": invite_id,
			"guild_name": gname,
			"from": from_name,
		}
		if _guild_panel != null and _guild_panel.visible:
			_refresh_guild_panel()
		append_system("【%s】邀请你加入公会【%s】。" % [from_name if from_name != "" else "?", gname if gname != "" else "?"])
	else:
		if str(_guild_pending_invite.get("invite_id", "")) == invite_id:
			_guild_pending_invite.clear()
		if _guild_panel != null and _guild_panel.visible:
			_refresh_guild_panel()


func _refresh_guild_panel() -> void:
	if _guild_body == null:
		return
	for c in _guild_body.get_children():
		c.queue_free()
	_guild_name_input = null
	_guild_invite_input = null
	var gid := str(_guild_state.get("id", "")).strip_edges()
	var gname := str(_guild_state.get("name", "")).strip_edges()
	var leader_id := str(_guild_state.get("leader_id", "")).strip_edges()
	var members: Array = _guild_state.get("members", []) if typeof(_guild_state.get("members", [])) == TYPE_ARRAY else []
	var self_id := ""
	var srv = Net.server()
	if srv != null and srv.has_method("_guild_self_id"):
		self_id = str(srv._guild_self_id())
	elif srv != null and srv.has_method("_party_self_id"):
		self_id = str(srv._party_self_id())
	var is_leader := gid != "" and leader_id != "" and leader_id == self_id

	# Pending invite banner
	var pend_id := str(_guild_pending_invite.get("invite_id", "")).strip_edges()
	if not pend_id.is_empty():
		_add_label(_guild_body, "收到邀请：【%s】来自 %s" % [
			str(_guild_pending_invite.get("guild_name", "?")),
			str(_guild_pending_invite.get("from", "?")),
		], 12, L2Style.COL_GOLD)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 6)
		_guild_body.add_child(prow)
		var acc := Button.new()
		acc.text = "接受"
		acc.focus_mode = Control.FOCUS_NONE
		acc.pressed.connect(func(): _on_guild_invite_respond(pend_id, true))
		prow.add_child(acc)
		var dec := Button.new()
		dec.text = "拒绝"
		dec.focus_mode = Control.FOCUS_NONE
		dec.pressed.connect(func(): _on_guild_invite_respond(pend_id, false))
		prow.add_child(dec)

	if gid.is_empty() or members.is_empty():
		_add_label(_guild_body, "你还没有公会。", 12, L2Style.COL_MUTED)
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 6)
		_guild_body.add_child(crow)
		_guild_name_input = LineEdit.new()
		_guild_name_input.placeholder_text = "公会名称（2～12字）"
		_guild_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(_guild_name_input)
		var create_btn := Button.new()
		create_btn.text = "创建公会"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.pressed.connect(_on_guild_create_pressed)
		crow.add_child(create_btn)
		return

	_add_label(_guild_body, "公会：%s" % gname, 13, L2Style.COL_TITLE)
	_add_label(_guild_body, "人数 %d / 20" % members.size(), 11, L2Style.COL_MUTED)

	if is_leader:
		var irow := HBoxContainer.new()
		irow.add_theme_constant_override("separation", 6)
		_guild_body.add_child(irow)
		_guild_invite_input = LineEdit.new()
		_guild_invite_input.placeholder_text = "输入名字邀请"
		_guild_invite_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_guild_invite_input.text_submitted.connect(func(t: String): _on_guild_invite(t))
		irow.add_child(_guild_invite_input)
		var inv_btn := Button.new()
		inv_btn.text = "邀请"
		inv_btn.focus_mode = Control.FOCUS_NONE
		inv_btn.pressed.connect(func(): _on_guild_invite(_guild_invite_input.text if _guild_invite_input else ""))
		irow.add_child(inv_btn)

	for e in members:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var mid := str(e.get("id", ""))
		var mname := str(e.get("name", "?"))
		var rank := str(e.get("rank", "member"))
		var rank_cn := "会长" if rank == "leader" else "成员"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_guild_body.add_child(row)
		var nl := Label.new()
		nl.text = "%s（%s）" % [mname, rank_cn]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		row.add_child(nl)
		if is_leader and mid != self_id and rank != "leader":
			var kick_btn := Button.new()
			kick_btn.text = "踢出"
			kick_btn.focus_mode = Control.FOCUS_NONE
			kick_btn.custom_minimum_size = Vector2(48, 24)
			kick_btn.pressed.connect(_on_guild_kick.bind(mid))
			row.add_child(kick_btn)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	_guild_body.add_child(brow)
	var leave_btn := Button.new()
	leave_btn.text = "离开公会"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.pressed.connect(_on_guild_leave)
	brow.add_child(leave_btn)
	if is_leader:
		var dis_btn := Button.new()
		dis_btn.text = "解散公会"
		dis_btn.focus_mode = Control.FOCUS_NONE
		dis_btn.pressed.connect(_on_guild_disband)
		brow.add_child(dis_btn)


func _on_guild_create_pressed() -> void:
	var n := ""
	if _guild_name_input != null:
		n = str(_guild_name_input.text).strip_edges()
	if n.is_empty():
		append_system("请输入公会名称。")
		return
	if _world_combat != null and _world_combat.has_method("request_guild_create"):
		_world_combat.request_guild_create(n)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_create"):
		_apply_guild_result_locally(srv.try_guild_create(n))
	else:
		append_system("无法创建公会。")


func _on_guild_invite(target: String) -> void:
	target = str(target).strip_edges()
	if target.is_empty():
		append_system("请输入要邀请的玩家名字。")
		return
	if _guild_invite_input != null:
		_guild_invite_input.text = ""
	if _world_combat != null and _world_combat.has_method("request_guild_invite"):
		_world_combat.request_guild_invite(target)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_invite"):
		_apply_guild_result_locally(srv.try_guild_invite(target))
	else:
		append_system("无法邀请。")


func _on_guild_kick(member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_guild_kick"):
		_world_combat.request_guild_kick(member_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_kick"):
		_apply_guild_result_locally(srv.try_guild_kick(member_id))


func _on_guild_leave() -> void:
	if _world_combat != null and _world_combat.has_method("request_guild_leave"):
		_world_combat.request_guild_leave()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_leave"):
		_apply_guild_result_locally(srv.try_guild_leave())


func _on_guild_disband() -> void:
	if _world_combat != null and _world_combat.has_method("request_guild_disband"):
		_world_combat.request_guild_disband()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_disband"):
		_apply_guild_result_locally(srv.try_guild_disband())


func _on_guild_invite_respond(invite_id: String, accept: bool) -> void:
	invite_id = str(invite_id).strip_edges()
	if invite_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_guild_invite_respond"):
		_world_combat.request_guild_invite_respond(invite_id, accept)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_invite_respond"):
		_apply_guild_result_locally(srv.try_guild_invite_respond(invite_id, accept))


func _apply_guild_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"guild_update":
				apply_guild_update(action)
			"guild_invite":
				apply_guild_invite(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)


## --- Auction house panel ---

func _build_auction_panel() -> void:
	_auction_panel = PanelContainer.new()
	_auction_panel.name = "AuctionPanel"
	_auction_panel.set_script(HudDrag)
	_auction_panel.screen_margin = 4.0
	_auction_panel.min_size = Vector2(420, 320)
	_auction_panel.default_size = Vector2(540, 500)
	_auction_panel.initial_dock = "none"
	_auction_panel.drag_anywhere = true
	add_child(_auction_panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	_auction_panel.add_child(marg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.name = "AuctionTitle"
	title.text = "拍卖行"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _auction_panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	outer.add_child(scroll)
	_auction_body = VBoxContainer.new()
	_auction_body.name = "AuctionBody"
	_auction_body.add_theme_constant_override("separation", 4)
	_auction_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_auction_body)
	_add_label(outer, "上架", 12, L2Style.COL_TITLE)
	var list_row := HBoxContainer.new()
	list_row.add_theme_constant_override("separation", 6)
	outer.add_child(list_row)
	_add_label(list_row, "物品ID", 11, L2Style.COL_MUTED)
	_auction_item_id_input = LineEdit.new()
	_auction_item_id_input.placeholder_text = "如 potion_hp_small"
	_auction_item_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_row.add_child(_auction_item_id_input)
	_add_label(list_row, "数量", 11, L2Style.COL_MUTED)
	_auction_qty_spin = SpinBox.new()
	_auction_qty_spin.min_value = 1
	_auction_qty_spin.max_value = 99
	_auction_qty_spin.value = 1
	_auction_qty_spin.custom_minimum_size = Vector2(70, 0)
	list_row.add_child(_auction_qty_spin)
	_add_label(list_row, "售价", 11, L2Style.COL_MUTED)
	_auction_price_spin = SpinBox.new()
	_auction_price_spin.min_value = 1
	_auction_price_spin.max_value = 999999
	_auction_price_spin.value = 10
	_auction_price_spin.custom_minimum_size = Vector2(90, 0)
	list_row.add_child(_auction_price_spin)
	var list_btn := Button.new()
	list_btn.text = "上架"
	list_btn.focus_mode = Control.FOCUS_NONE
	list_btn.pressed.connect(_on_auction_list)
	outer.add_child(list_btn)
	_auction_panel.visible = false
	_apply_l2_chrome(_auction_panel)
	_refresh_auction_panel()
	call_deferred("_nudge_auction")


func _nudge_auction() -> void:
	if _auction_panel == null:
		return
	_auction_panel.size = Vector2(540, 500)
	var vp := get_viewport_rect().size
	_auction_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 270)), 64)


func _toggle_auction_panel(force_open: bool = false) -> void:
	if _auction_panel == null:
		return
	if force_open:
		_auction_panel.visible = true
	else:
		_auction_panel.visible = not _auction_panel.visible
	if _auction_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_auction"):
			apply_auction_update({"type": "auction_update", "auction": srv.snapshot_auction()})
		_refresh_auction_panel()
		_auction_panel.move_to_front()
		call_deferred("_nudge_auction")


func apply_auction_update(action: Dictionary) -> void:
	var ah_v: Variant = action.get("auction", action)
	if typeof(ah_v) != TYPE_DICTIONARY:
		if typeof(ah_v) == TYPE_ARRAY:
			_auction_state = {"listings": [], "count": 0, "max_listings": 50}
			var cleaned0: Array = []
			for e0 in ah_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append((e0 as Dictionary).duplicate(true))
			_auction_state["listings"] = cleaned0
			_auction_state["count"] = cleaned0.size()
			if _auction_panel != null and _auction_panel.visible:
				_refresh_auction_panel()
		return
	var ad: Dictionary = ah_v
	_auction_state = {
		"listings": [],
		"count": int(ad.get("count", 0)),
		"max_listings": int(ad.get("max_listings", 50)),
	}
	var list_v: Variant = ad.get("listings", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) == TYPE_DICTIONARY:
				cleaned.append((e as Dictionary).duplicate(true))
		_auction_state["listings"] = cleaned
		_auction_state["count"] = cleaned.size()
	if _auction_panel != null and _auction_panel.visible:
		_refresh_auction_panel()


func _refresh_auction_panel() -> void:
	if _auction_body == null:
		return
	for c in _auction_body.get_children():
		c.queue_free()
	var listings_v: Variant = _auction_state.get("listings", [])
	var listings: Array = listings_v if typeof(listings_v) == TYPE_ARRAY else []
	var cap := int(_auction_state.get("max_listings", 50))
	_add_label(_auction_body, "在售 %d / %d" % [listings.size(), cap], 11, L2Style.COL_MUTED)
	if listings.is_empty():
		_add_label(_auction_body, "（暂无拍卖品）", 12, L2Style.COL_MUTED)
		return
	var self_id := ""
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		self_id = str(srv._party_self_id())
	elif srv != null:
		var sid: Variant = srv.get("_session_character_id")
		if sid != null and str(sid) != "":
			self_id = str(sid)
	for e in listings:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var lid := str(e.get("id", ""))
		var seller_id := str(e.get("seller_id", ""))
		var seller := str(e.get("seller_name", "?"))
		var iid := str(e.get("item_id", ""))
		var iname := str(e.get("item_name", ""))
		if iname.is_empty():
			iname = _item_label(iid)
		var qty := int(e.get("qty", 0))
		var price := int(e.get("price_gold", 0))
		var is_own := (self_id != "" and seller_id == self_id) or seller_id == "player"
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_auction_body.add_child(row)
		var nl := Label.new()
		nl.text = "%s ×%d — %d 金币（%s）" % [iname, qty, price, seller]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", L2Style.COL_TEXT)
		row.add_child(nl)
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		if is_own:
			var cancel_btn := Button.new()
			cancel_btn.text = "下架"
			cancel_btn.focus_mode = Control.FOCUS_NONE
			cancel_btn.custom_minimum_size = Vector2(56, 24)
			cancel_btn.pressed.connect(_on_auction_cancel.bind(lid))
			btn_row.add_child(cancel_btn)
			_add_label(btn_row, "（我的）", 10, L2Style.COL_MUTED)
		else:
			var buy_btn := Button.new()
			buy_btn.text = "购买"
			buy_btn.focus_mode = Control.FOCUS_NONE
			buy_btn.custom_minimum_size = Vector2(56, 24)
			buy_btn.pressed.connect(_on_auction_buy.bind(lid))
			btn_row.add_child(buy_btn)


func _on_auction_list() -> void:
	var item_id := _auction_item_id_input.text.strip_edges() if _auction_item_id_input else ""
	var qty := int(_auction_qty_spin.value) if _auction_qty_spin else 1
	var price := int(_auction_price_spin.value) if _auction_price_spin else 1
	if item_id.is_empty():
		append_system("请填写要上架的物品 ID。")
		return
	if _world_combat != null and _world_combat.has_method("request_auction_list"):
		_world_combat.request_auction_list(item_id, qty, price)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_auction_list"):
			_apply_auction_result_locally(srv.try_auction_list(item_id, qty, price))
		else:
			append_system("无法上架。")
			return
	if _auction_item_id_input:
		_auction_item_id_input.text = ""
	if _auction_qty_spin:
		_auction_qty_spin.value = 1
	if _auction_price_spin:
		_auction_price_spin.value = 10


func _on_auction_buy(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_auction_buy"):
		_world_combat.request_auction_buy(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_buy"):
		_apply_auction_result_locally(srv.try_auction_buy(listing_id))


func _on_auction_cancel(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if _world_combat != null and _world_combat.has_method("request_auction_cancel"):
		_world_combat.request_auction_cancel(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_cancel"):
		_apply_auction_result_locally(srv.try_auction_cancel(listing_id))


func _apply_auction_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"auction_update":
				apply_auction_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
