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
const AuctionPanel = preload("res://scripts/ui/panels/auction_panel.gd")
const WarehousePanel = preload("res://scripts/ui/panels/warehouse_panel.gd")
var _warehouse_panel_logic: WarehousePanel = WarehousePanel.new(self)
const TradePanel = preload("res://scripts/ui/panels/trade_panel.gd")
var _trade_panel_logic: TradePanel = TradePanel.new(self)
const TitlesPanel = preload("res://scripts/ui/panels/titles_panel.gd")
var _titles_panel_logic: TitlesPanel = TitlesPanel.new(self)
const TargetPanel = preload("res://scripts/ui/panels/target_panel.gd")
var _target_panel_logic: TargetPanel = TargetPanel.new(self)
const StatusPanel = preload("res://scripts/ui/panels/status_panel.gd")
var _status_panel_logic: StatusPanel = StatusPanel.new(self)
const SkillsPanel = preload("res://scripts/ui/panels/skills_panel.gd")
var _skills_panel_logic: SkillsPanel = SkillsPanel.new(self)
const ShopPanel = preload("res://scripts/ui/panels/shop_panel.gd")
var _shop_panel_logic: ShopPanel = ShopPanel.new(self)
const QuestPanel = preload("res://scripts/ui/panels/quest_panel.gd")
var _quest_panel_logic: QuestPanel = QuestPanel.new(self)
const PartyPanel = preload("res://scripts/ui/panels/party_panel.gd")
var _party_panel_logic: PartyPanel = PartyPanel.new(self)
const NpcDialoguePanel = preload("res://scripts/ui/panels/npc_dialogue_panel.gd")
var _npc_dialogue_panel_logic: NpcDialoguePanel = NpcDialoguePanel.new(self)
const MinimapPanel = preload("res://scripts/ui/panels/minimap_panel.gd")
var _minimap_panel_logic: MinimapPanel = MinimapPanel.new(self)
const MailPanel = preload("res://scripts/ui/panels/mail_panel.gd")
var _mail_panel_logic: MailPanel = MailPanel.new(self)
const LootPanel = preload("res://scripts/ui/panels/loot_panel.gd")
var _loot_panel_logic: LootPanel = LootPanel.new(self)
const InventoryPanel = preload("res://scripts/ui/panels/inventory_panel.gd")
var _inventory_panel_logic: InventoryPanel = InventoryPanel.new(self)
const GuildPanel = preload("res://scripts/ui/panels/guild_panel.gd")
var _guild_panel_logic: GuildPanel = GuildPanel.new(self)
const GroundDropPanel = preload("res://scripts/ui/panels/ground_drop_panel.gd")
var _ground_drop_panel_logic: GroundDropPanel = GroundDropPanel.new(self)
const FriendsPanel = preload("res://scripts/ui/panels/friends_panel.gd")
var _friends_panel_logic: FriendsPanel = FriendsPanel.new(self)
const EquipmentPanel = preload("res://scripts/ui/panels/equipment_panel.gd")
var _equipment_panel_logic: EquipmentPanel = EquipmentPanel.new(self)
const EmotePanel = preload("res://scripts/ui/panels/emote_panel.gd")
var _emote_panel_logic: EmotePanel = EmotePanel.new(self)
const DungeonPanel = preload("res://scripts/ui/panels/dungeon_panel.gd")
var _dungeon_panel_logic: DungeonPanel = DungeonPanel.new(self)
const DuelPanel = preload("res://scripts/ui/panels/duel_panel.gd")
var _duel_panel_logic: DuelPanel = DuelPanel.new(self)
const DeathPanel = preload("res://scripts/ui/panels/death_panel.gd")
var _death_panel_logic: DeathPanel = DeathPanel.new(self)
const CraftPanel = preload("res://scripts/ui/panels/craft_panel.gd")
var _craft_panel_logic: CraftPanel = CraftPanel.new(self)
const ChatPanel = preload("res://scripts/ui/panels/chat_panel.gd")
var _chat_panel_logic: ChatPanel = ChatPanel.new(self)
const CastBarPanel = preload("res://scripts/ui/panels/cast_bar_panel.gd")
var _cast_bar_panel_logic: CastBarPanel = CastBarPanel.new(self)
var _auction_panel_logic: AuctionPanel = AuctionPanel.new(self)
const ToastPanel = preload("res://scripts/ui/panels/toast_panel.gd")
var _toast_panel_logic: ToastPanel = ToastPanel.new(self)
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
	_status_panel_logic._compact_status_panel()
func _style_status_bar(bar: ProgressBar, fill: Color) -> void:
	_status_panel_logic._style_status_bar(bar, fill)
func _ensure_status_overlays() -> void:
	_status_panel_logic._ensure_status_overlays()
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
	_status_panel_logic._ensure_xp_bar()
func _ensure_status_chip_row() -> void:
	_status_panel_logic._ensure_status_chip_row()
func _status_kind_color(kind: String) -> Color:
	return _status_panel_logic._status_kind_color(kind)
func _rebuild_status_chips(row: HBoxContainer, statuses: Array) -> void:
	_status_panel_logic._rebuild_status_chips(row, statuses)
func apply_status_chips(statuses: Array) -> void:
	_status_panel_logic.apply_status_chips(statuses)
func _wire_player_status_bar(bar: Control) -> void:
	_status_panel_logic._wire_player_status_bar(bar)
func _on_status_cancel_requested(status_id: String) -> void:
	_quest_panel_logic._on_status_cancel_requested(status_id)
func _sync_party_self_statuses_from_player() -> void:
	_party_panel_logic._sync_party_self_statuses_from_player()
func apply_target_status_chips(statuses: Array) -> void:
	_target_panel_logic.apply_target_status_chips(statuses)
func _ensure_cast_bar() -> void:
	_cast_bar_panel_logic._ensure_cast_bar()
func _style_cast_bar_mode(mode: String) -> void:
	_cast_bar_panel_logic._style_cast_bar_mode(mode)
func _tick_cast_bar_visual(delta: float) -> void:
	_cast_bar_panel_logic._tick_cast_bar_visual(delta)
func apply_cast_start(action: Dictionary) -> void:
	_cast_bar_panel_logic.apply_cast_start(action)
func apply_cast_update(action: Dictionary) -> void:
	_cast_bar_panel_logic.apply_cast_update(action)
func apply_cast_end(action: Dictionary) -> void:
	_cast_bar_panel_logic.apply_cast_end(action)
func _refresh_xp_bar() -> void:
	_status_panel_logic._refresh_xp_bar()
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
	_minimap_panel_logic.set_minimap_hint(text)
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
	_target_panel_logic.clear_target()
func _ensure_target_chrome() -> void:
	_target_panel_logic._ensure_target_chrome()
## Hostile target bar: 「仇恨」 gold/red when you are victim; 「无仇恨」 muted otherwise.
func apply_threat_chip(show: bool, threat_you: bool = false) -> void:
	_target_panel_logic.apply_threat_chip(show, threat_you)
func apply_threat_update(action: Dictionary) -> void:
	_target_panel_logic.apply_threat_update(action)
func _ensure_threat_chip() -> void:
	_target_panel_logic._ensure_threat_chip()
func _on_target_close_pressed() -> void:
	_target_panel_logic._on_target_close_pressed()
func show_target( p_name: String, hp_ratio: float = 1.0, world_pos: Variant = null, show_hp_bar: bool = true, mp_ratio: float = -1.0, show_threat: bool = false, threat_you: bool = false ) -> void:
	_target_panel_logic.show_target(p_name, hp_ratio, world_pos, show_hp_bar, mp_ratio, show_threat, threat_you)
func append_chat(speaker: String, msg: String) -> void:
	_chat_panel_logic.append_chat(speaker, msg)
func append_system(msg: String) -> void:
	_chat_panel_logic.append_system(msg)
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
	_npc_dialogue_panel_logic.show_npc_dialogue(npc_name, body, options, face)
func _make_dialogue_option_handler(option_id: String, option_index: int, label: String) -> Callable:
	return _npc_dialogue_panel_logic._make_dialogue_option_handler(option_id, option_index, label)
func hide_npc_dialogue() -> void:
	_npc_dialogue_panel_logic.hide_npc_dialogue()
func _ensure_npc_chat() -> void:
	_chat_panel_logic._ensure_npc_chat()
func _apply_dialogue_face(face: Dictionary) -> void:
	_npc_dialogue_panel_logic._apply_dialogue_face(face)
func _place_npc_chat() -> void:
	_chat_panel_logic._place_npc_chat()
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
	_chat_panel_logic._push_chat(channel, speaker, msg)
func _format_chat_bbcode(color: String, speaker: String, msg: String, ts: String = "") -> String:
	return _chat_panel_logic._format_chat_bbcode(color, speaker, msg, ts)
func _chat_visible(channel: String) -> bool:
	return _chat_panel_logic._chat_visible(channel)
func _rebuild_chat_log() -> void:
	_chat_panel_logic._rebuild_chat_log()
func _on_chat_submitted(text: String) -> void:
	_chat_panel_logic._on_chat_submitted(text)
func apply_chat_message(action: Dictionary) -> void:
	_chat_panel_logic.apply_chat_message(action)
func _apply_chat_result_locally(result: Dictionary) -> void:
	_chat_panel_logic._apply_chat_result_locally(result)
func _on_remote_debug_spawn() -> void:
	_emote_panel_logic._on_remote_debug_spawn()
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
	_status_panel_logic._tick_status_icon_bars(delta)
func _sync_radar(force_hint: bool = false) -> void:
	_minimap_panel_logic._sync_radar(force_hint)
func _sync_radar_blips() -> void:
	_minimap_panel_logic._sync_radar_blips()
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
	_target_panel_logic._update_target_angle()
func _setup_radar() -> void:
	_minimap_panel_logic._setup_radar()
func _connect_radar_nav() -> void:
	_minimap_panel_logic._connect_radar_nav()
func _setup_radar_zoom_buttons() -> void:
	_minimap_panel_logic._setup_radar_zoom_buttons()
func _apply_radar_view_radius_from_settings() -> void:
	_minimap_panel_logic._apply_radar_view_radius_from_settings()
func _connect_overview_nav(overview: Control) -> void:
	if overview == null or not is_instance_valid(overview):
		return
	if overview.has_signal("cell_clicked") and not overview.cell_clicked.is_connected(_on_map_nav_cell):
		overview.cell_clicked.connect(_on_map_nav_cell)
	if overview.has_signal("cell_pinned") and not overview.cell_pinned.is_connected(_on_map_pin_cell):
		overview.cell_pinned.connect(_on_map_pin_cell)


func set_map_pin(cell: Vector2i) -> void:
	_minimap_panel_logic.set_map_pin(cell)
func apply_map_pins_update(action: Dictionary) -> void:
	_minimap_panel_logic.apply_map_pins_update(action)
func _on_map_nav_cell(cell: Vector2i) -> void:
	var label := ""
	if _map_overview != null and is_instance_valid(_map_overview) and _map_overview.has_method("consume_nav_label"):
		label = str(_map_overview.consume_nav_label())
	if label.is_empty() and _radar != null and is_instance_valid(_radar) and _radar.has_method("consume_nav_label"):
		label = str(_radar.consume_nav_label())
	if _world_combat != null and _world_combat.has_method("request_map_move"):
		_world_combat.request_map_move(cell, label)


func _on_map_pin_cell(cell: Vector2i) -> void:
	_minimap_panel_logic._on_map_pin_cell(cell)
func _on_clear_map_pins() -> void:
	_minimap_panel_logic._on_clear_map_pins()
func _build_chat_tabs() -> void:
	_chat_panel_logic._build_chat_tabs()
func _on_chat_tab(channel: String) -> void:
	_chat_panel_logic._on_chat_tab(channel)
func _highlight_chat_tab(channel: String) -> void:
	_chat_panel_logic._highlight_chat_tab(channel)
func _hotbar_bind_key(page: int, slot: int) -> String:
	return "%d:%d" % [page, slot]


func _session_hotbar_store() -> Node:
	return _skills_panel_logic._session_hotbar_store()
func _restore_hotbar_from_session() -> void:
	_skills_panel_logic._restore_hotbar_from_session()
func _persist_hotbar_to_session() -> void:
	_skills_panel_logic._persist_hotbar_to_session()
func _get_hotbar_binding(page: int, slot: int) -> Dictionary:
	return _skills_panel_logic._get_hotbar_binding(page, slot)
func _set_hotbar_binding(page: int, slot: int, kind: String, id: String) -> void:
	_skills_panel_logic._set_hotbar_binding(page, slot, kind, id)
func _clear_hotbar_binding(page: int, slot: int) -> void:
	_skills_panel_logic._clear_hotbar_binding(page, slot)
func _inventory_qty(item_id: String) -> int:
	return _inventory_panel_logic._inventory_qty(item_id)
func _is_item_equipped(item_id: String) -> bool:
	return _equipment_panel_logic._is_item_equipped(item_id)
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
	return _equipment_panel_logic._equipped_def_for_compare(item_id)
func _equipped_enhance_for_compare(item_id: String) -> int:
	return _equipment_panel_logic._equipped_enhance_for_compare(item_id)
func _equip_compare_tip(item_id: String, base_lines: String, item_enhance: int = 0) -> String:
	return _equipment_panel_logic._equip_compare_tip(item_id, base_lines, item_enhance)
func _apply_inv_slot_compare_tip(cell: PanelContainer, item_id: String, locked: bool, bound: bool = false, enhance: int = 0, durability: int = -1, durability_max: int = 0) -> void:
	_inventory_panel_logic._apply_inv_slot_compare_tip(cell, item_id, locked, bound, enhance, durability, durability_max)
func _letter_avatar(name: String) -> String:
	return InvSlot.first_grapheme(name)


func _layout_hotbar_side_nav(prev: Node, next: Node) -> void:
	_skills_panel_logic._layout_hotbar_side_nav(prev, next)
func _text_input_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is CodeEdit


func _hotbar_keycode_to_slot(keycode: int) -> Vector2i:
	return _skills_panel_logic._hotbar_keycode_to_slot(keycode)
func _try_hotbar_key(keycode: int) -> bool:
	return _skills_panel_logic._try_hotbar_key(keycode)
func _build_hotbar() -> void:
	_skills_panel_logic._build_hotbar()
func _refresh_hotbar_slot_visuals() -> void:
	_skills_panel_logic._refresh_hotbar_slot_visuals()
func _on_hotbar_item_dropped(page: int, slot: int, item_id: String) -> void:
	_skills_panel_logic._on_hotbar_item_dropped(page, slot, item_id)
func _on_hotbar_skill_dropped(page: int, slot: int, skill_id: String) -> void:
	_skills_panel_logic._on_hotbar_skill_dropped(page, slot, skill_id)
func _on_hotbar_binding_cleared(page: int, slot: int) -> void:
	_skills_panel_logic._on_hotbar_binding_cleared(page, slot)
func _on_hotbar_pressed(page: int, slot: int, key: String) -> void:
	_skills_panel_logic._on_hotbar_pressed(page, slot, key)
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
	_inventory_panel_logic.apply_inventory_snapshot(items, gold)
func apply_equipment_snapshot(slots: Array, bonuses: Dictionary = {}) -> void:
	_equipment_panel_logic.apply_equipment_snapshot(slots, bonuses)
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
	_shop_panel_logic.show_shop(shop_id, title, listings, gold, vendor_rep)
func apply_shop_buyback(rows: Variant) -> void:
	_shop_panel_logic.apply_shop_buyback(rows)
func _add_buyback_row(parent: Node, index: int, label: String, price: int) -> void:
	_shop_panel_logic._add_buyback_row(parent, index, label, price)
func hide_shop() -> void:
	_shop_panel_logic.hide_shop()
func show_loot(session_id: String, npc_id: String, items: Array) -> void:
	_loot_panel_logic.show_loot(session_id, npc_id, items)
func refresh_loot(session_id: String, items: Array) -> void:
	_loot_panel_logic.refresh_loot(session_id, items)
func hide_loot() -> void:
	_loot_panel_logic.hide_loot()
func _ensure_loot_panel() -> void:
	_loot_panel_logic._ensure_loot_panel()
func _place_loot_panel() -> void:
	_loot_panel_logic._place_loot_panel()
func _fill_loot_panel() -> void:
	_loot_panel_logic._fill_loot_panel()
func _on_loot_take_pressed(item_id: String) -> void:
	_loot_panel_logic._on_loot_take_pressed(item_id)
func _on_loot_take_all_pressed() -> void:
	_loot_panel_logic._on_loot_take_all_pressed()
func _on_loot_close_pressed() -> void:
	_loot_panel_logic._on_loot_close_pressed()
func _clear_shop_carts() -> void:
	_shop_panel_logic._clear_shop_carts()
func _ensure_shop_panel() -> void:
	_shop_panel_logic._ensure_shop_panel()
func _make_shop_tab_page(page_name: String, catalog_name: String, cart_name: String, cat_title: String, cart_title: String) -> HBoxContainer:
	return _shop_panel_logic._make_shop_tab_page(page_name, catalog_name, cart_name, cat_title, cart_title)
func _make_shop_list_pane(list_name: String, heading: String) -> PanelContainer:
	return _shop_panel_logic._make_shop_list_pane(list_name, heading)
func _rebuild_shop_tab_bar(panel: PanelContainer) -> void:
	_shop_panel_logic._rebuild_shop_tab_bar(panel)
func _on_shop_tab(tab_id: String) -> void:
	_shop_panel_logic._on_shop_tab(tab_id)
func _highlight_shop_tabs(tabs: HBoxContainer) -> void:
	_shop_panel_logic._highlight_shop_tabs(tabs)
func _show_shop_tab_pages() -> void:
	_shop_panel_logic._show_shop_tab_pages()
func _place_shop_panel() -> void:
	_shop_panel_logic._place_shop_panel()
func _fill_shop_panel() -> void:
	_shop_panel_logic._fill_shop_panel()
func _clear_container(node: Node) -> void:
	if node == null:
		return
	while node.get_child_count() > 0:
		var c: Node = node.get_child(0)
		node.remove_child(c)
		c.free()


func _add_shop_catalog_row(parent: VBoxContainer, label_text: String, price: int, is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	_shop_panel_logic._add_shop_catalog_row(parent, label_text, price, is_buy, item_id, display_name, unit_price)
func _fill_cart_list(parent: VBoxContainer, cart: Array, is_buy: bool) -> void:
	_shop_panel_logic._fill_cart_list(parent, cart, is_buy)
func _on_shop_catalog_add(is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	_shop_panel_logic._on_shop_catalog_add(is_buy, item_id, display_name, unit_price)
func _on_shop_cart_adjust(is_buy: bool, item_id: String, delta: int) -> void:
	_shop_panel_logic._on_shop_cart_adjust(is_buy, item_id, delta)
func _on_shop_cart_remove(is_buy: bool, item_id: String) -> void:
	_shop_panel_logic._on_shop_cart_remove(is_buy, item_id)
func _on_shop_confirm() -> void:
	_shop_panel_logic._on_shop_confirm()
func _confirm_buy_cart() -> void:
	_shop_panel_logic._confirm_buy_cart()
func _confirm_sell_cart() -> void:
	_shop_panel_logic._confirm_sell_cart()
func _shop_sellable_bag_rows() -> Array:
	return _shop_panel_logic._shop_sellable_bag_rows()
func _on_shop_buy(item_id: String) -> void:
	_shop_panel_logic._on_shop_buy(item_id)
func _on_shop_sell(item_id: String) -> void:
	_shop_panel_logic._on_shop_sell(item_id)
func _on_shop_sell_junk() -> void:
	_shop_panel_logic._on_shop_sell_junk()
func apply_skill_catalog(skills: Array) -> void:
	_skills_panel_logic.apply_skill_catalog(skills)
func apply_skill_book(book: Dictionary) -> void:
	_skills_panel_logic.apply_skill_book(book)
func is_skill_known(skill_id: String) -> bool:
	return _skills_panel_logic.is_skill_known(skill_id)
func apply_quest_snapshot(quests: Array) -> void:
	_quest_panel_logic.apply_quest_snapshot(quests)
func _iter_skill_cells(root: Node) -> Array:
	return _skills_panel_logic._iter_skill_cells(root)
func _skill_window_grid() -> Node:
	return _skills_panel_logic._skill_window_grid()
func _tick_skill_cell_cooldowns(host: Node, delta: float) -> void:
	_skills_panel_logic._tick_skill_cell_cooldowns(host, delta)
func _tick_skill_window_cooldowns(delta: float) -> void:
	_skills_panel_logic._tick_skill_window_cooldowns(delta)
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
	_skills_panel_logic._apply_cooldown_to_skill_window(id, remaining, total)
func _apply_cast_to_container(host: Node, frac: float) -> void:
	_cast_bar_panel_logic._apply_cast_to_container(host, frac)
func _apply_cast_to_skill_window(frac: float) -> void:
	_skills_panel_logic._apply_cast_to_skill_window(frac)
func _refresh_skill_window_cooldowns() -> void:
	_skills_panel_logic._refresh_skill_window_cooldowns()
func _tick_hotbar_cooldowns(delta: float) -> void:
	_skills_panel_logic._tick_hotbar_cooldowns(delta)
func _apply_hotbar_cooldown_for_id(id: String, remaining: float, total: float) -> void:
	_skills_panel_logic._apply_hotbar_cooldown_for_id(id, remaining, total)
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
	_skills_panel_logic._sync_hotbar_cast_overlays()
func _sync_skill_cast_overlays() -> void:
	_skills_panel_logic._sync_skill_cast_overlays()
func note_skill_cooldown(skill_id: String, remaining: float, cooldown: float = 0.0) -> void:
	_skills_panel_logic.note_skill_cooldown(skill_id, remaining, cooldown)
func hotbar_prev() -> void:
	_skills_panel_logic.hotbar_prev()
func hotbar_next() -> void:
	_skills_panel_logic.hotbar_next()
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
	_death_panel_logic.show_death_dialog()
func hide_death_dialog() -> void:
	_death_panel_logic.hide_death_dialog()
func _build_death_dialog() -> void:
	_death_panel_logic._build_death_dialog()
func _place_death_dialog() -> void:
	_death_panel_logic._place_death_dialog()
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
	_quest_panel_logic._build_quest_tracker()
func _default_quest_tracker_pos() -> Vector2:
	return _quest_panel_logic._default_quest_tracker_pos()
func _place_quest_tracker() -> void:
	_quest_panel_logic._place_quest_tracker()
func _refresh_quest_tracker() -> void:
	_quest_panel_logic._refresh_quest_tracker()
func _fit_quest_tracker() -> void:
	_quest_panel_logic._fit_quest_tracker()
func _open_tracked_quest(quest_id: String) -> void:
	_quest_panel_logic._open_tracked_quest(quest_id)
func _quest_nav_world_ctx() -> Dictionary:
	return _quest_panel_logic._quest_nav_world_ctx()
func _find_tracked_quest_row(quest_id: String) -> Dictionary:
	return _quest_panel_logic._find_tracked_quest_row(quest_id)
func _resolve_tracked_quest_nav(quest_id: String, objective_index: int = -1) -> Dictionary:
	return _quest_panel_logic._resolve_tracked_quest_nav(quest_id, objective_index)
func _path_to_tracked_quest(quest_id: String, objective_index: int = -1) -> void:
	_quest_panel_logic._path_to_tracked_quest(quest_id, objective_index)
## Left-click: pathfind when a nav cell resolves, else open journal.
func _on_tracked_quest_activate(quest_id: String, objective_index: int = -1) -> void:
	_quest_panel_logic._on_tracked_quest_activate(quest_id, objective_index)
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
	_party_panel_logic.apply_party_invite(action)
func show_loot_roll(action: Dictionary) -> void:
	_loot_panel_logic.show_loot_roll(action)
func apply_loot_roll_choice(action: Dictionary) -> void:
	_loot_panel_logic.apply_loot_roll_choice(action)
func hide_loot_roll(_action: Dictionary = {}) -> void:
	_loot_panel_logic.hide_loot_roll(_action)
func _submit_loot_roll(choice: String) -> void:
	_loot_panel_logic._submit_loot_roll(choice)
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
	_inventory_panel_logic._lock_inventory_window(panel)
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
	_inventory_panel_logic._ensure_inventory_gold_bar(panel)
func _refresh_inventory_gold_label(panel: PanelContainer = null) -> void:
	_inventory_panel_logic._refresh_inventory_gold_label(panel)
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
	_skills_panel_logic._lock_skills_window(panel)
func _lock_quest_window(panel: PanelContainer) -> void:
	_quest_panel_logic._lock_quest_window(panel)
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
	_quest_panel_logic._rebuild_quest_tab_bar(panel)
func _on_quest_tab(tab_id: String) -> void:
	_quest_panel_logic._on_quest_tab(tab_id)
func _highlight_quest_tabs(tabs: HBoxContainer) -> void:
	_quest_panel_logic._highlight_quest_tabs(tabs)
func _on_quest_window_visibility() -> void:
	_quest_panel_logic._on_quest_window_visibility()
func _rebuild_skills_tab_bar(panel: PanelContainer) -> void:
	_skills_panel_logic._rebuild_skills_tab_bar(panel)
func _on_skills_tab(cat: String) -> void:
	_skills_panel_logic._on_skills_tab(cat)
func _highlight_skills_tabs(tabs: HBoxContainer) -> void:
	_skills_panel_logic._highlight_skills_tabs(tabs)
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
	_equipment_panel_logic._sync_equipment_cache()
func _equipment_map() -> Dictionary:
	return _equipment_panel_logic._equipment_map()
func _build_paperdoll(host: Control, ch: Dictionary) -> void:
	_equipment_panel_logic._build_paperdoll(host, ch)
func _paperdoll_texture(ch: Dictionary) -> Texture2D:
	return _equipment_panel_logic._paperdoll_texture(ch)
func _ensure_ground_drop_zone() -> void:
	_ground_drop_panel_logic._ensure_ground_drop_zone()
func _tick_ground_drop_zone() -> void:
	_ground_drop_panel_logic._tick_ground_drop_zone()
func _on_equip_slot_equip(item_id: String, slot_id: String) -> void:
	_equipment_panel_logic._on_equip_slot_equip(item_id, slot_id)
func _on_equip_slot_unequip(slot_id: String) -> void:
	_equipment_panel_logic._on_equip_slot_unequip(slot_id)
func _on_equip_slot_drop(slot_id: String) -> void:
	_equipment_panel_logic._on_equip_slot_drop(slot_id)
func _apply_equip_result_locally(result: Dictionary) -> void:
	_equipment_panel_logic._apply_equip_result_locally(result)
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
	return _skills_panel_logic._skill_icon_index(skill_id)
func _skill_icon_ref(skill_id: String) -> String:
	return _skills_panel_logic._skill_icon_ref(skill_id)
func _fill_inventory(body: VBoxContainer, _ch: Dictionary) -> void:
	_inventory_panel_logic._fill_inventory(body, _ch)
func _inv_row_matches_filter(it: Dictionary) -> bool:
	return _inventory_panel_logic._inv_row_matches_filter(it)
func _on_inv_search_text_changed(new_text: String) -> void:
	_inventory_panel_logic._on_inv_search_text_changed(new_text)
func _apply_inv_search_visibility(grid: GridContainer) -> void:
	_inventory_panel_logic._apply_inv_search_visibility(grid)
func _on_inventory_split(item_id: String, qty: int) -> void:
	_inventory_panel_logic._on_inventory_split(item_id, qty)
func _on_inventory_lock(item_id: String) -> void:
	_inventory_panel_logic._on_inventory_lock(item_id)
func _on_inventory_item_drop(item_id: String) -> void:
	_inventory_panel_logic._on_inventory_item_drop(item_id)
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
	_ground_drop_panel_logic._ensure_ground_tip()
func show_ground_tip(text: String, screen_pos: Vector2) -> void:
	_ground_drop_panel_logic.show_ground_tip(text, screen_pos)
func move_ground_tip(screen_pos: Vector2) -> void:
	_ground_drop_panel_logic.move_ground_tip(screen_pos)
func hide_ground_tip() -> void:
	_ground_drop_panel_logic.hide_ground_tip()
func _show_drop_qty_dialog(item_id: String, max_qty: int) -> void:
	_ground_drop_panel_logic._show_drop_qty_dialog(item_id, max_qty)
func _ensure_drop_qty_dialog() -> void:
	_ground_drop_panel_logic._ensure_drop_qty_dialog()
func _on_drop_qty_cancel() -> void:
	_ground_drop_panel_logic._on_drop_qty_cancel()
func _on_drop_qty_confirm() -> void:
	_ground_drop_panel_logic._on_drop_qty_confirm()
func _on_inventory_item_pressed(item_id: String) -> void:
	_inventory_panel_logic._on_inventory_item_pressed(item_id)
func _skill_display_name(skill_id: String) -> String:
	return _skills_panel_logic._skill_display_name(skill_id)
func _skill_category(skill_id: String) -> String:
	return _skills_panel_logic._skill_category(skill_id)
func _normalize_skill_category(def: Dictionary) -> String:
	return _skills_panel_logic._normalize_skill_category(def)
func _is_passive_skill(skill_id: String) -> bool:
	return _skills_panel_logic._is_passive_skill(skill_id)
func _fill_skills(body: VBoxContainer, _ch: Dictionary) -> void:
	_skills_panel_logic._fill_skills(body, _ch)
func _on_skill_slot_pressed(skill_id: String) -> void:
	_skills_panel_logic._on_skill_slot_pressed(skill_id)
func _on_skill_row_pressed(skill_id: String) -> void:
	_skills_panel_logic._on_skill_row_pressed(skill_id)
func _is_skill_known(skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	if skill_id == "basic_attack":
		return true
	return _known_skills.has(skill_id)


func _skill_def(skill_id: String) -> Dictionary:
	return _skills_panel_logic._skill_def(skill_id)
func _player_level_for_skills() -> int:
	return _skills_panel_logic._player_level_for_skills()
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
	_skills_panel_logic._update_skills_learn_row(learn_btn, sel_lbl)
func _refresh_skills_learn_controls() -> void:
	_skills_panel_logic._refresh_skills_learn_controls()
func _on_learn_skill_pressed() -> void:
	_skills_panel_logic._on_learn_skill_pressed()
func _on_respec_skill_pressed() -> void:
	_skills_panel_logic._on_respec_skill_pressed()
## Clear hotbar skill bindings that reference forgotten skill ids (client-only hotkeys).
func apply_skill_respec(action: Dictionary) -> void:
	_skills_panel_logic.apply_skill_respec(action)
func _fill_quest(body: VBoxContainer, _ch: Dictionary) -> void:
	_quest_panel_logic._fill_quest(body, _ch)
func _soft_sync_quest_drawer() -> void:
	_quest_panel_logic._soft_sync_quest_drawer()
func _quest_status_matches_tab(status: String) -> bool:
	return _quest_panel_logic._quest_status_matches_tab(status)
func _normalize_quest_status(status: String) -> String:
	return _quest_panel_logic._normalize_quest_status(status)
func _make_quest_row(q: Dictionary, selected: bool) -> Button:
	return _quest_panel_logic._make_quest_row(q, selected)
func _quest_status_label(status: String) -> String:
	return _quest_panel_logic._quest_status_label(status)
func _on_quest_row_selected(quest_id: String) -> void:
	_quest_panel_logic._on_quest_row_selected(quest_id)
func _on_quest_drawer_close() -> void:
	_quest_panel_logic._on_quest_drawer_close()
func _ensure_quest_drawer() -> void:
	_quest_panel_logic._ensure_quest_drawer()
func _quest_by_id(quest_id: String) -> Dictionary:
	return _quest_panel_logic._quest_by_id(quest_id)
func _place_quest_drawer() -> void:
	_quest_panel_logic._place_quest_drawer()
func _sync_quest_drawer_follow() -> void:
	_quest_panel_logic._sync_quest_drawer_follow()
func _open_quest_drawer(quest_id: String, animate: bool) -> void:
	_quest_panel_logic._open_quest_drawer(quest_id, animate)
func _close_quest_drawer(animate: bool) -> void:
	_quest_panel_logic._close_quest_drawer(animate)
func _finish_quest_drawer_close() -> void:
	_quest_panel_logic._finish_quest_drawer_close()
func _refresh_quest_drawer_content() -> void:
	_quest_panel_logic._refresh_quest_drawer_content()
func _on_quest_turn_in(quest_id: String) -> void:
	_quest_panel_logic._on_quest_turn_in(quest_id)
func _on_quest_abandon(quest_id: String) -> void:
	_quest_panel_logic._on_quest_abandon(quest_id)
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
	_minimap_panel_logic._sync_map_overview_layout(panel, mount, host)
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
	return _minimap_panel_logic._make_radar_zoom_option(gs)
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
	_party_panel_logic._build_party_stub()
func _nudge_party() -> void:
	_party_panel_logic._nudge_party()
func _toggle_party_panel() -> void:
	_party_panel_logic._toggle_party_panel()
func _party_in_party() -> bool:
	return _party_panel_logic._party_in_party()
func apply_party_update(action: Dictionary) -> void:
	_party_panel_logic.apply_party_update(action)
func _sync_radar_party_stubs() -> void:
	_party_panel_logic._sync_radar_party_stubs()
func _refresh_party_panel() -> void:
	_party_panel_logic._refresh_party_panel()
func _party_self_id_for_ui() -> String:
	return _party_panel_logic._party_self_id_for_ui()
func _on_party_toggle_expand(member_id: String) -> void:
	_party_panel_logic._on_party_toggle_expand(member_id)
func _on_party_create() -> void:
	_party_panel_logic._on_party_create()
func _on_party_invite(target: String = "") -> void:
	_party_panel_logic._on_party_invite(target)
func _on_party_kick(member_id: String) -> void:
	_party_panel_logic._on_party_kick(member_id)
func _on_party_clear_shared_target() -> void:
	_party_panel_logic._on_party_clear_shared_target()
func _on_party_set_loot_mode(mode: String) -> void:
	_loot_panel_logic._on_party_set_loot_mode(mode)
func _on_party_debug_fill() -> void:
	_party_panel_logic._on_party_debug_fill()
func _on_party_leave() -> void:
	_party_panel_logic._on_party_leave()
func _apply_party_result_locally(result: Dictionary) -> void:
	_party_panel_logic._apply_party_result_locally(result)
func on_hotbar_prev_pressed() -> void:
	_skills_panel_logic.on_hotbar_prev_pressed()
func on_hotbar_next_pressed() -> void:
	_skills_panel_logic.on_hotbar_next_pressed()
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
	_trade_panel_logic._on_trade_open_with(partner_name)
func _on_duel_challenge(target_id_or_name: String) -> void:
	_duel_panel_logic._on_duel_challenge(target_id_or_name)
func _on_duel_forfeit() -> void:
	_duel_panel_logic._on_duel_forfeit()
func _apply_duel_result_locally(result: Dictionary) -> void:
	_duel_panel_logic._apply_duel_result_locally(result)
func _build_duel_banner() -> void:
	_duel_panel_logic._build_duel_banner()
func apply_duel_update(action: Dictionary) -> void:
	_duel_panel_logic.apply_duel_update(action)
func _refresh_duel_banner() -> void:
	_duel_panel_logic._refresh_duel_banner()
func apply_rested_update(action: Dictionary) -> void:
	_status_panel_logic.apply_rested_update(action)
func _refresh_rested_label(rested: int = -1) -> void:
	_status_panel_logic._refresh_rested_label(rested)
func apply_safe_zone(action: Dictionary) -> void:
	_dungeon_panel_logic.apply_safe_zone(action)
func _ensure_safe_zone_chip() -> void:
	_dungeon_panel_logic._ensure_safe_zone_chip()
func apply_dungeon_update(action: Dictionary) -> void:
	_dungeon_panel_logic.apply_dungeon_update(action)
func _refresh_dungeon_chip() -> void:
	_dungeon_panel_logic._refresh_dungeon_chip()
func _ensure_dungeon_chip() -> void:
	_dungeon_panel_logic._ensure_dungeon_chip()
func _on_dungeon_enter_pressed() -> void:
	_dungeon_panel_logic._on_dungeon_enter_pressed()
func _on_dungeon_exit_pressed() -> void:
	_dungeon_panel_logic._on_dungeon_exit_pressed()
func _apply_dungeon_result_locally(result: Dictionary) -> void:
	_dungeon_panel_logic._apply_dungeon_result_locally(result)
func _duel_remaining_sec() -> int:
	return _duel_panel_logic._duel_remaining_sec()
func _tick_duel_banner(delta: float) -> void:
	_duel_panel_logic._tick_duel_banner(delta)
func _build_level_toast() -> void:
	_toast_panel_logic._build_level_toast()


## Public toast API (headless tests + world level_up path).
## sp_gained > 0 appends 「获得技能点」; mouse-filter ignore so input stays free.
func show_level_up_toast(level: int, sp_gained: int = 0) -> void:
	_toast_panel_logic.show_level_up_toast(level, sp_gained)


func hide_level_up_toast() -> void:
	_toast_panel_logic.hide_level_up_toast()


func is_level_up_toast_visible() -> bool:
	return _toast_panel_logic.is_level_up_toast_visible()


func get_level_up_toast_text() -> String:
	return _toast_panel_logic.get_level_up_toast_text()


func _set_level_toast_sp_note(on: bool) -> void:
	_toast_panel_logic._set_level_toast_sp_note(on)


func _refresh_level_toast_text() -> void:
	_toast_panel_logic._refresh_level_toast_text()


func _layout_level_toast() -> void:
	_toast_panel_logic._layout_level_toast()


func _tick_level_toast(delta: float) -> void:
	_toast_panel_logic._tick_level_toast(delta)


## Compare previous statuses → toast only on transition to ready / completed.
## First snapshot seeds only (enter_world / spawn must not spam).
func _detect_quest_status_toasts(quests: Array) -> void:
	_quest_panel_logic._detect_quest_status_toasts(quests)
func _build_quest_toast() -> void:
	_quest_panel_logic._build_quest_toast()
## Public toast API (headless + apply_quest_snapshot transitions).
func show_quest_ready_toast(title: String) -> void:
	_show_quest_toast("任务可交付：%s" % title.strip_edges(), Color(0.75, 0.95, 0.55, 1.0), Color(0.55, 0.82, 0.40, 0.95))


func show_quest_complete_toast(title: String) -> void:
	_quest_panel_logic.show_quest_complete_toast(title)
func _show_quest_toast(line: String, font_col: Color, border_col: Color) -> void:
	_quest_panel_logic._show_quest_toast(line, font_col, border_col)
func hide_quest_toast() -> void:
	_quest_panel_logic.hide_quest_toast()
func is_quest_toast_visible() -> bool:
	return _quest_panel_logic.is_quest_toast_visible()
func get_quest_toast_text() -> String:
	return _quest_panel_logic.get_quest_toast_text()
func _layout_quest_toast() -> void:
	_quest_panel_logic._layout_quest_toast()
func _tick_quest_toast(delta: float) -> void:
	_quest_panel_logic._tick_quest_toast(delta)
func _note_player_input() -> void:
	_toast_panel_logic._note_player_input()


func _tick_afk_warn(_delta: float) -> void:
	_toast_panel_logic._tick_afk_warn(_delta)


func _build_afk_toast() -> void:
	_toast_panel_logic._build_afk_toast()


## Non-blocking AFK banner. Optional soft sit line; never locks input / disconnects.
func show_afk_warn_toast(suggest_sit: bool = true) -> void:
	_toast_panel_logic.show_afk_warn_toast(suggest_sit)


func hide_afk_warn_toast() -> void:
	_toast_panel_logic.hide_afk_warn_toast()


func is_afk_warn_toast_visible() -> bool:
	return _toast_panel_logic.is_afk_warn_toast_visible()


func get_afk_warn_toast_text() -> String:
	return _toast_panel_logic.get_afk_warn_toast_text()


func _layout_afk_toast() -> void:
	_toast_panel_logic._layout_afk_toast()


func _tick_afk_toast(delta: float) -> void:
	_toast_panel_logic._tick_afk_toast(delta)



func _build_exp_float() -> void:
	_toast_panel_logic._build_exp_float()


## Public EXP float API (headless tests + world exp_gain path).
## Rapid/same-frame gains coalesce into one tip showing the sum.
func show_exp_gain_float(amount: int) -> void:
	_toast_panel_logic.show_exp_gain_float(amount)


func hide_exp_gain_float() -> void:
	_toast_panel_logic.hide_exp_gain_float()


func is_exp_gain_float_visible() -> bool:
	return _toast_panel_logic.is_exp_gain_float_visible()


func get_exp_gain_float_text() -> String:
	return _toast_panel_logic.get_exp_gain_float_text()


func get_exp_gain_float_amount() -> int:
	return _toast_panel_logic.get_exp_gain_float_amount()


func _layout_exp_float() -> void:
	_toast_panel_logic._layout_exp_float()


func _tick_exp_float(delta: float) -> void:
	_toast_panel_logic._tick_exp_float(delta)


func _build_gold_float() -> void:
	_inventory_panel_logic._build_gold_float()
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
	_inventory_panel_logic._layout_gold_float()
func _tick_gold_float(delta: float) -> void:
	_inventory_panel_logic._tick_gold_float(delta)
func _inv_qty_map(items: Array) -> Dictionary:
	return _inventory_panel_logic._inv_qty_map(items)
func _emit_item_gain_floats_from_delta(prev_qty: Dictionary, new_qty: Dictionary) -> void:
	_toast_panel_logic._emit_item_gain_floats_from_delta(prev_qty, new_qty)


func _build_item_floats() -> void:
	_toast_panel_logic._build_item_floats()


func _make_item_float_label() -> Label:
	return _toast_panel_logic._make_item_float_label()


## Public item float API. Coalesces same item_id while TTL alive; caps concurrent lines.
func show_item_gain_float(item_id: String, qty: int, display_name: String = "") -> void:
	_toast_panel_logic.show_item_gain_float(item_id, qty, display_name)


func hide_item_gain_floats() -> void:
	_toast_panel_logic.hide_item_gain_floats()


func is_item_gain_float_visible() -> bool:
	return _toast_panel_logic.is_item_gain_float_visible()


func get_item_gain_float_count() -> int:
	return _toast_panel_logic.get_item_gain_float_count()


func get_item_gain_float_texts() -> Array:
	return _toast_panel_logic.get_item_gain_float_texts()


func get_item_gain_float_qty(item_id: String) -> int:
	return _toast_panel_logic.get_item_gain_float_qty(item_id)


func _layout_item_floats() -> void:
	_toast_panel_logic._layout_item_floats()


func _tick_item_floats(delta: float) -> void:
	_toast_panel_logic._tick_item_floats(delta)


func _build_trade_panel() -> void:
	_trade_panel_logic._build_trade_panel()
func _nudge_trade() -> void:
	_trade_panel_logic._nudge_trade()
func _toggle_trade_panel() -> void:
	_trade_panel_logic._toggle_trade_panel()
func apply_trade_update(action: Dictionary) -> void:
	_trade_panel_logic.apply_trade_update(action)
func hide_trade() -> void:
	_trade_panel_logic.hide_trade()
func _refresh_trade_panel() -> void:
	_trade_panel_logic._refresh_trade_panel()
func _fill_trade_item_list(parent: Node, items_v: Variant, mine: bool) -> void:
	_trade_panel_logic._fill_trade_item_list(parent, items_v, mine)
func _on_trade_open() -> void:
	_trade_panel_logic._on_trade_open()
func _on_trade_cancel() -> void:
	_trade_panel_logic._on_trade_cancel()
func _on_trade_put_item(item_id: String) -> void:
	_trade_panel_logic._on_trade_put_item(item_id)
func _on_trade_take_item(item_id: String) -> void:
	_trade_panel_logic._on_trade_take_item(item_id)
func _on_trade_set_gold() -> void:
	_trade_panel_logic._on_trade_set_gold()
func _on_trade_ready(ready: bool) -> void:
	if _world_combat != null and _world_combat.has_method("request_trade_ready"):
		_world_combat.request_trade_ready(ready)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_ready"):
		_apply_trade_result_locally(srv.try_trade_ready(ready))


func _on_trade_confirm() -> void:
	_trade_panel_logic._on_trade_confirm()
func _apply_trade_result_locally(result: Dictionary) -> void:
	_trade_panel_logic._apply_trade_result_locally(result)
func _build_warehouse_panel() -> void:
	_warehouse_panel_logic._build_warehouse_panel()
func _nudge_warehouse() -> void:
	_warehouse_panel_logic._nudge_warehouse()
func _toggle_warehouse_panel(force_open: bool = false) -> void:
	_warehouse_panel_logic._toggle_warehouse_panel(force_open)
func apply_warehouse_update(action: Dictionary) -> void:
	_warehouse_panel_logic.apply_warehouse_update(action)
func _refresh_warehouse_panel() -> void:
	_warehouse_panel_logic._refresh_warehouse_panel()
func _on_warehouse_deposit_pressed(item_id: String, stack_qty: int) -> void:
	_warehouse_panel_logic._on_warehouse_deposit_pressed(item_id, stack_qty)
func _on_warehouse_withdraw_pressed(item_id: String, stack_qty: int) -> void:
	_warehouse_panel_logic._on_warehouse_withdraw_pressed(item_id, stack_qty)
func _on_warehouse_deposit_gold() -> void:
	_warehouse_panel_logic._on_warehouse_deposit_gold()
func _on_warehouse_withdraw_gold() -> void:
	_warehouse_panel_logic._on_warehouse_withdraw_gold()
func _apply_warehouse_result_locally(result: Dictionary) -> void:
	_warehouse_panel_logic._apply_warehouse_result_locally(result)
func _build_friends_panel() -> void:
	_friends_panel_logic._build_friends_panel()
func _nudge_friends() -> void:
	_friends_panel_logic._nudge_friends()
func _toggle_friends_panel(force_open: bool = false) -> void:
	_friends_panel_logic._toggle_friends_panel(force_open)
func apply_friends_update(action: Dictionary) -> void:
	_friends_panel_logic.apply_friends_update(action)
func _refresh_friends_panel() -> void:
	_friends_panel_logic._refresh_friends_panel()
func _on_friend_add(name_or_id: String) -> void:
	_friends_panel_logic._on_friend_add(name_or_id)
func _on_friend_remove(friend_id: String) -> void:
	_friends_panel_logic._on_friend_remove(friend_id)
func _on_friend_whisper(target_name: String) -> void:
	_friends_panel_logic._on_friend_whisper(target_name)
func _on_friend_invite(target_name: String) -> void:
	_friends_panel_logic._on_friend_invite(target_name)
func _apply_friends_result_locally(result: Dictionary) -> void:
	_friends_panel_logic._apply_friends_result_locally(result)
func _build_mail_panel() -> void:
	_mail_panel_logic._build_mail_panel()
func _nudge_mail() -> void:
	_mail_panel_logic._nudge_mail()
func _toggle_mail_panel(force_open: bool = false) -> void:
	_mail_panel_logic._toggle_mail_panel(force_open)
func apply_mail_update(action: Dictionary) -> void:
	_mail_panel_logic.apply_mail_update(action)
func _refresh_mail_panel() -> void:
	_mail_panel_logic._refresh_mail_panel()
func _on_mail_send() -> void:
	_mail_panel_logic._on_mail_send()
func _on_mail_read(mail_id: String) -> void:
	_mail_panel_logic._on_mail_read(mail_id)
func _on_mail_claim(mail_id: String) -> void:
	_mail_panel_logic._on_mail_claim(mail_id)
func _on_mail_delete(mail_id: String) -> void:
	_mail_panel_logic._on_mail_delete(mail_id)
func _apply_mail_result_locally(result: Dictionary) -> void:
	_mail_panel_logic._apply_mail_result_locally(result)
func _ensure_craft_recipes_loaded() -> void:
	_craft_panel_logic._ensure_craft_recipes_loaded()
func _build_craft_panel() -> void:
	_craft_panel_logic._build_craft_panel()
func _nudge_craft() -> void:
	_craft_panel_logic._nudge_craft()
func _toggle_craft_panel(force_open: bool = false) -> void:
	_craft_panel_logic._toggle_craft_panel(force_open)
func _inv_qty(item_id: String) -> int:
	return _inventory_panel_logic._inv_qty(item_id)
func _refresh_craft_panel() -> void:
	_craft_panel_logic._refresh_craft_panel()
func _on_craft_select(recipe_id: String) -> void:
	_craft_panel_logic._on_craft_select(recipe_id)
func _on_craft_pressed(recipe_id: String) -> void:
	_craft_panel_logic._on_craft_pressed(recipe_id)
func apply_craft_update(action: Dictionary) -> void:
	_craft_panel_logic.apply_craft_update(action)
func apply_gather_update(action: Dictionary) -> void:
	_craft_panel_logic.apply_gather_update(action)
func _apply_craft_result_locally(result: Dictionary) -> void:
	_craft_panel_logic._apply_craft_result_locally(result)
func _build_emote_panel() -> void:
	_emote_panel_logic._build_emote_panel()
func _nudge_emote() -> void:
	_emote_panel_logic._nudge_emote()
func _toggle_emote_panel(force_open: bool = false) -> void:
	_emote_panel_logic._toggle_emote_panel(force_open)
func _emote_catalog_rows() -> Array:
	return _emote_panel_logic._emote_catalog_rows()
func _refresh_emote_panel() -> void:
	_emote_panel_logic._refresh_emote_panel()
func _on_emote_pressed(emote_id: String) -> void:
	_emote_panel_logic._on_emote_pressed(emote_id)
func _apply_emote_result_locally(result: Dictionary) -> void:
	_emote_panel_logic._apply_emote_result_locally(result)
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
	_chat_panel_logic._refresh_dps_meter_visibility()
func _ensure_dps_meter() -> void:
	_chat_panel_logic._ensure_dps_meter()
func _build_dps_meter() -> void:
	_chat_panel_logic._build_dps_meter()
func _nudge_dps_meter() -> void:
	_chat_panel_logic._nudge_dps_meter()
func _ensure_combat_log() -> void:
	_chat_panel_logic._ensure_combat_log()
func _build_combat_log_panel() -> void:
	_chat_panel_logic._build_combat_log_panel()
func _nudge_combat_log() -> void:
	_chat_panel_logic._nudge_combat_log()
func _toggle_combat_log_panel(force_open: bool = false) -> void:
	_chat_panel_logic._toggle_combat_log_panel(force_open)
func _on_combat_log_clear() -> void:
	_chat_panel_logic._on_combat_log_clear()
func _refresh_combat_log_panel() -> void:
	_chat_panel_logic._refresh_combat_log_panel()
func _combat_log_filter_flags() -> Dictionary:
	return _chat_panel_logic._combat_log_filter_flags()
func _build_combat_log_filters() -> void:
	_chat_panel_logic._build_combat_log_filters()
func _combat_log_scroll_to_end() -> void:
	_chat_panel_logic._combat_log_scroll_to_end()
## --- 称号 panel ---

func _build_titles_panel() -> void:
	_titles_panel_logic._build_titles_panel()
func _nudge_titles() -> void:
	_titles_panel_logic._nudge_titles()
func _toggle_titles_panel(force_open: bool = false) -> void:
	_titles_panel_logic._toggle_titles_panel(force_open)
func apply_title_update(action: Dictionary) -> void:
	_titles_panel_logic.apply_title_update(action)
func _build_daily_panel() -> void:
	_titles_panel_logic._build_daily_panel()
func _nudge_daily() -> void:
	_titles_panel_logic._nudge_daily()
func _toggle_daily_panel(force_open: bool = false) -> void:
	_titles_panel_logic._toggle_daily_panel(force_open)
func apply_daily_board(action: Dictionary) -> void:
	_titles_panel_logic.apply_daily_board(action)
func _refresh_daily_panel() -> void:
	_titles_panel_logic._refresh_daily_panel()
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
	return _titles_panel_logic._active_title_display_name()
func _ensure_title_under_name() -> void:
	_titles_panel_logic._ensure_title_under_name()
func _refresh_name_with_title() -> void:
	_titles_panel_logic._refresh_name_with_title()
func _title_unlock_hint(row: Dictionary) -> String:
	return _titles_panel_logic._title_unlock_hint(row)
func _refresh_titles_panel() -> void:
	_titles_panel_logic._refresh_titles_panel()
func _on_title_equip(title_id: String) -> void:
	_equipment_panel_logic._on_title_equip(title_id)
func _apply_title_result_locally(result: Dictionary) -> void:
	_titles_panel_logic._apply_title_result_locally(result)
## --- 成就 panel ---

func _build_achievements_panel() -> void:
	_titles_panel_logic._build_achievements_panel()
func _nudge_achievements() -> void:
	_titles_panel_logic._nudge_achievements()
func _toggle_achievements_panel(force_open: bool = false) -> void:
	_titles_panel_logic._toggle_achievements_panel(force_open)
func apply_achievement_update(action: Dictionary) -> void:
	_titles_panel_logic.apply_achievement_update(action)
func _achievement_unlock_hint(row: Dictionary) -> String:
	return _titles_panel_logic._achievement_unlock_hint(row)
func _refresh_achievements_panel() -> void:
	_titles_panel_logic._refresh_achievements_panel()
## --- Guild panel ---

func _build_guild_panel() -> void:
	_guild_panel_logic._build_guild_panel()
func _nudge_guild() -> void:
	_guild_panel_logic._nudge_guild()
func _toggle_guild_panel(force_open: bool = false) -> void:
	_guild_panel_logic._toggle_guild_panel(force_open)
func apply_guild_update(action: Dictionary) -> void:
	_guild_panel_logic.apply_guild_update(action)
func apply_guild_invite(action: Dictionary) -> void:
	_guild_panel_logic.apply_guild_invite(action)
func _refresh_guild_panel() -> void:
	_guild_panel_logic._refresh_guild_panel()
func _on_guild_create_pressed() -> void:
	_guild_panel_logic._on_guild_create_pressed()
func _on_guild_invite(target: String) -> void:
	_guild_panel_logic._on_guild_invite(target)
func _on_guild_kick(member_id: String) -> void:
	_guild_panel_logic._on_guild_kick(member_id)
func _on_guild_leave() -> void:
	_guild_panel_logic._on_guild_leave()
func _on_guild_disband() -> void:
	_guild_panel_logic._on_guild_disband()
func _on_guild_invite_respond(invite_id: String, accept: bool) -> void:
	_guild_panel_logic._on_guild_invite_respond(invite_id, accept)
func _apply_guild_result_locally(result: Dictionary) -> void:
	_guild_panel_logic._apply_guild_result_locally(result)
## --- Auction house panel ---

func _build_auction_panel() -> void:
	_auction_panel_logic._build_auction_panel()
func _nudge_auction() -> void:
	_auction_panel_logic._nudge_auction()
func _toggle_auction_panel(force_open: bool = false) -> void:
	_auction_panel_logic._toggle_auction_panel(force_open)
func apply_auction_update(action: Dictionary) -> void:
	_auction_panel_logic.apply_auction_update(action)
func _refresh_auction_panel() -> void:
	_auction_panel_logic._refresh_auction_panel()
func _on_auction_list() -> void:
	_auction_panel_logic._on_auction_list()
func _on_auction_buy(listing_id: String) -> void:
	_auction_panel_logic._on_auction_buy(listing_id)
func _on_auction_cancel(listing_id: String) -> void:
	_auction_panel_logic._on_auction_cancel(listing_id)
func _apply_auction_result_locally(result: Dictionary) -> void:
	_auction_panel_logic._apply_auction_result_locally(result)
