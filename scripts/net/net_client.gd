extends Node
## Abstract NetClient contract — the boundary between the client and the authoritative
## server. `MockServer` satisfies this today (duck-typed, in-process); a future
## Go-backed transport (WebSocket/gRPC/HTTP) should `extends` this base to inherit the
## signals below and implement the method surface, then be registered via
## `Net.set_server(node)` so the whole UI keeps working without changes.
##
## The client talks to the server only through:
##   * request adapters  -> `try_*(...)` -> returns `{ok, actions:[...]}`
##   * action_apply       <- applies server `actions[]`
##   * `snapshot_*()`     -> pull current authoritative state for a panel
##   * lifecycle          -> login / create_character / fetch_characters / enter_world
##
## The constant arrays are a machine-checkable interface spec: `validate()` reports any
## member a candidate server is missing, so a real transport can be diffed against the
## exact surface the client depends on.

signal login_finished(ok: bool, message: String)
signal characters_ready(list: Array)
signal character_created(ok: bool, message: String, character: Dictionary)
signal enter_world_ready(ok: bool, message: String, spawn: Dictionary)

const REQUIRED_SIGNALS: Array[String] = [
	"login_finished", "characters_ready", "character_created", "enter_world_ready",
]

## Session lifecycle.
const CORE_METHODS: Array[String] = [
	"login", "create_character", "fetch_characters", "enter_world",
]

## Boundary methods called directly by the client (outside the try_/snapshot_ groups).
const MISC_METHODS: Array[String] = [
	"poll_combat_tick", "load_world_pack", "register_npc",
	"set_player_cell", "player_in_safe_zone",
]

## Boundary properties the client reads directly off the server node.
const REQUIRED_PROPERTIES: Array[String] = [
	"map_collision", "inventory", "combat_stats",
]

## Intent requests: client -> server, each returns `{ok, actions:[...]}` (or applies async).
const REQUEST_METHODS: Array[String] = [
	"try_abandon_quest", "try_accept_quest", "try_allocate_attr", "try_attack", "try_attr_respec", "try_auction_buy",
	"try_auction_cancel", "try_auction_list", "try_cancel_status", "try_chat", "try_craft", "try_daily_board_list",
	"try_dialogue_choice", "try_drop_equipped", "try_drop_item", "try_duel_accept", "try_duel_challenge", "try_duel_debug_hit",
	"try_duel_debug_pending", "try_duel_decline", "try_duel_forfeit", "try_dungeon_enter", "try_dungeon_exit", "try_emote",
	"try_enhance", "try_equip_item", "try_event_choice", "try_fish", "try_friend_add", "try_friend_remove",
	"try_gather", "try_guild_create", "try_guild_disband", "try_guild_incoming_invite", "try_guild_invite", "try_guild_invite_respond",
	"try_guild_kick", "try_guild_leave", "try_inn_rest", "try_interact", "try_inventory_lock", "try_inventory_sort",
	"try_inventory_split", "try_learn_skill", "try_loot_close", "try_loot_roll", "try_loot_roll_for", "try_loot_take",
	"try_loot_take_all", "try_mail_claim", "try_mail_delete", "try_mail_read", "try_mail_send", "try_map_pin_clear",
	"try_map_pin_toggle", "try_mount", "try_move", "try_npc_move", "try_npc_skill", "try_open_ground_bag",
	"try_party_clear_target", "try_party_create", "try_party_debug_fill", "try_party_incoming_invite", "try_party_invite", "try_party_invite_respond",
	"try_party_kick", "try_party_leave", "try_party_set_loot_mode", "try_party_set_target", "try_party_summon_accept", "try_party_summon_accept_all",
	"try_party_summon_decline", "try_pet_dismiss", "try_pet_summon", "try_recall", "try_remote_debug_spawn", "try_remote_despawn",
	"try_repair", "try_respawn", "try_set_auto_potion", "try_set_combat_target", "try_set_pet_assist", "try_shop_buy",
	"try_shop_buyback", "try_shop_close", "try_shop_sell", "try_shop_sell_junk", "try_sit", "try_skill_respec",
	"try_title_equip", "try_toggle_equip", "try_trade_cancel", "try_trade_confirm", "try_trade_open", "try_trade_put_item",
	"try_trade_ready", "try_trade_set_gold", "try_trade_take_item", "try_transfer", "try_turn_in_quest", "try_unequip_item",
	"try_use_item", "try_use_skill", "try_warehouse_deposit", "try_warehouse_deposit_gold", "try_warehouse_open", "try_warehouse_withdraw",
	"try_warehouse_withdraw_gold",
]

## Authoritative state pulls: client -> server -> current dictionary/array snapshot.
const SNAPSHOT_METHODS: Array[String] = [
	"snapshot_achievements", "snapshot_auction", "snapshot_craft", "snapshot_daily", "snapshot_dps", "snapshot_duel",
	"snapshot_dungeon", "snapshot_friends", "snapshot_gather", "snapshot_ground_bags", "snapshot_guild", "snapshot_loot_rolls",
	"snapshot_mail", "snapshot_map_pins", "snapshot_party", "snapshot_party_summon", "snapshot_pet", "snapshot_quest_journal",
	"snapshot_recipes", "snapshot_remote_players", "snapshot_safe_zone", "snapshot_shop", "snapshot_shop_buyback", "snapshot_skill_book",
	"snapshot_skill_catalog", "snapshot_threat", "snapshot_titles", "snapshot_trade", "snapshot_warehouse",
]


## Every method a conforming server must expose.
static func required_methods() -> Array[String]:
	var out: Array[String] = []
	out.append_array(CORE_METHODS)
	out.append_array(MISC_METHODS)
	out.append_array(REQUEST_METHODS)
	out.append_array(SNAPSHOT_METHODS)
	return out


static func _has_property(node: Object, prop: String) -> bool:
	for p in node.get_property_list():
		if str(p.get("name", "")) == prop:
			return true
	return false


## Diff a candidate server against the contract.
## Returns { ok, missing_signals: [...], missing_methods: [...], missing_properties: [...] }.
static func validate(node: Object) -> Dictionary:
	var missing_signals: Array[String] = []
	var missing_methods: Array[String] = []
	var missing_properties: Array[String] = []
	if node == null:
		return {
			"ok": false,
			"missing_signals": REQUIRED_SIGNALS.duplicate(),
			"missing_methods": required_methods(),
			"missing_properties": REQUIRED_PROPERTIES.duplicate(),
		}
	for sig in REQUIRED_SIGNALS:
		if not node.has_signal(sig):
			missing_signals.append(sig)
	for m in required_methods():
		if not node.has_method(m):
			missing_methods.append(m)
	for prop in REQUIRED_PROPERTIES:
		if not _has_property(node, prop):
			missing_properties.append(prop)
	return {
		"ok": missing_signals.is_empty() and missing_methods.is_empty() and missing_properties.is_empty(),
		"missing_signals": missing_signals,
		"missing_methods": missing_methods,
		"missing_properties": missing_properties,
	}


## Convenience: true when `node` implements the full contract.
static func satisfies(node: Object) -> bool:
	return bool(validate(node).get("ok", false))
