extends RefCounted
## 用例编排（应用层）：全部 request_* 服务端请求适配器。
## 静态方法接收组合根 ctrl；Net.server() 权威逻辑 → try_* → ctrl._apply_server_actions()。

const Net = preload("res://scripts/net/net.gd")
const RequestPipeline = preload("res://scripts/net/request_pipeline.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")

## These adapters route through RequestPipeline.dispatch(), which applies the returned
## actions synchronously today and will transparently defer to response_ready when an
## async transport is active. Behavior against the sync MockServer is unchanged.
static func request_party_invite_respond(ctrl, invite_id: String, accept: bool) -> void:
	RequestPipeline.dispatch(ctrl, "try_party_invite_respond", [invite_id, accept])

static func request_respawn(ctrl, where: String = "town") -> void:
	RequestPipeline.dispatch(ctrl, "try_respawn", [where])

static func request_recall(ctrl) -> void:
	RequestPipeline.dispatch(ctrl, "try_recall", [])

static func request_sit(ctrl, on: Variant = null) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_sit"):
		return
	var want := true
	if typeof(on) == TYPE_BOOL:
		want = bool(on)
	elif "sitting" in srv:
		want = not bool(srv.sitting)
	if want:
		ctrl.stop_follow()
		ctrl._auto_attack = false
		ctrl._clear_pending_engage()
	RequestPipeline.dispatch(ctrl, "try_sit", [want])

static func request_map_move(ctrl, cell: Vector2i, label: String = "") -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	if not ctrl.player.has_method("click_move_to"):
		return
	ctrl.stop_follow()
	ctrl._auto_attack = false
	ctrl._clear_pending_engage()
	var ok: bool = bool(ctrl.player.click_move_to(cell))
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		var tag := str(label).strip_edges()
		if tag.is_empty():
			tag = ctrl._map_poi_label_at(cell)
		if ok:
			if tag != "":
				ctrl.hud.append_system("前往：%s" % tag)
			else:
				ctrl.hud.append_system("前往 (%d, %d)" % [cell.x, cell.y])
		else:
			if tag != "":
				ctrl.hud.append_system("无法到达：%s" % tag)
			else:
				ctrl.hud.append_system("无法到达 (%d, %d)" % [cell.x, cell.y])

static func request_event_choice(ctrl, option_id: String = "", option_index: int = -1) -> void:
	## Dialogue option → quest_* / shop_open / MV event choice.
	var srv = Net.server()
	if srv == null:
		return
	var result: Dictionary = {}
	if srv.has_method("try_dialogue_choice"):
		result = srv.try_dialogue_choice(option_id, option_index)
	elif srv.has_method("try_event_choice"):
		result = srv.try_event_choice(option_id, option_index)
	else:
		return
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v, null)

static func request_shop_buy(ctrl, shop_id: String, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_buy"):
		return
	var result: Dictionary = srv.try_shop_buy(shop_id, item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_shop_buyback(ctrl, index: int, qty: int = -1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_buyback"):
		return
	var result: Dictionary = srv.try_shop_buyback(index, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_shop_close(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_close"):
		return
	var result: Dictionary = srv.try_shop_close()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_inventory_split(ctrl, item_id: String, qty: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_split"):
		return
	var result: Dictionary = srv.try_inventory_split(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_inventory_sort(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_sort"):
		return
	var result: Dictionary = srv.try_inventory_sort()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_inventory_lock(ctrl, item_id: String, on: bool) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_lock"):
		return
	var result: Dictionary = srv.try_inventory_lock(item_id, on)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_shop_sell(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_sell"):
		return
	var result: Dictionary = srv.try_shop_sell(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_shop_sell_junk(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_sell_junk"):
		return
	var result: Dictionary = srv.try_shop_sell_junk()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_open_ground_bag(ctrl, bag_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_open_ground_bag"):
		return
	var result: Dictionary = srv.try_open_ground_bag(bag_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_drop_item(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_drop_item"):
		return
	var result: Dictionary = srv.try_drop_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_drop_equipped(ctrl, slot: String) -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_drop_equipped"):
		return
	var result: Dictionary = srv.try_drop_equipped(slot)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_loot_take(ctrl, item_id: String, qty: int = -1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_take"):
		return
	var result: Dictionary = srv.try_loot_take(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_loot_take_all(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_take_all"):
		return
	var result: Dictionary = srv.try_loot_take_all()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_loot_close(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_close"):
		return
	var result: Dictionary = srv.try_loot_close()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_loot_roll(ctrl, choice: String, roll_id: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_roll"):
		return
	var result: Dictionary = srv.try_loot_roll(choice, roll_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_turn_in_quest(ctrl, quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_turn_in_quest"):
		return
	var result: Dictionary = srv.try_turn_in_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_accept_quest(ctrl, quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_accept_quest"):
		return
	var result: Dictionary = srv.try_accept_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_abandon_quest(ctrl, quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_abandon_quest"):
		return
	var result: Dictionary = srv.try_abandon_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_cancel_status(ctrl, status_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_cancel_status"):
		return
	var result: Dictionary = srv.try_cancel_status(status_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_debug_fill(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_debug_fill"):
		return
	var result: Dictionary = srv.try_party_debug_fill()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_create(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_create"):
		return
	var result: Dictionary = srv.try_party_create()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_invite(ctrl, target: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_invite"):
		return
	var result: Dictionary = srv.try_party_invite(target)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_leave(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_leave"):
		return
	var result: Dictionary = srv.try_party_leave()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_kick(ctrl, member_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_kick"):
		return
	var result: Dictionary = srv.try_party_kick(member_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_set_target(ctrl, npc_id: String, display_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_set_target"):
		return
	if not srv.has_method("in_party") or not srv.in_party():
		return
	var result: Dictionary = srv.try_party_set_target(npc_id, display_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_clear_target(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_clear_target"):
		return
	var result: Dictionary = srv.try_party_clear_target()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_party_set_loot_mode(ctrl, mode: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_set_loot_mode"):
		return
	var result: Dictionary = srv.try_party_set_loot_mode(mode)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_chat(ctrl, channel: String, text: String, whisper_to: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_chat"):
		return
	var result: Dictionary = srv.try_chat(channel, text, whisper_to)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_remote_debug_spawn(ctrl, display_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_remote_debug_spawn"):
		return
	var result: Dictionary = srv.try_remote_debug_spawn(display_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_open(ctrl, partner_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_open"):
		return
	var result: Dictionary = srv.try_trade_open(partner_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_cancel(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_cancel"):
		return
	var result: Dictionary = srv.try_trade_cancel()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_put_item(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_put_item"):
		return
	var result: Dictionary = srv.try_trade_put_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_take_item(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_take_item"):
		return
	var result: Dictionary = srv.try_trade_take_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_set_gold(ctrl, amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_set_gold"):
		return
	var result: Dictionary = srv.try_trade_set_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_ready(ctrl, ready: bool = true) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_ready"):
		return
	var result: Dictionary = srv.try_trade_ready(ready)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_trade_confirm(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_confirm"):
		return
	var result: Dictionary = srv.try_trade_confirm()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_duel_challenge(ctrl, target_id_or_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_challenge"):
		return
	var result: Dictionary = srv.try_duel_challenge(target_id_or_name)
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_duel_accept(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_accept"):
		return
	var result: Dictionary = srv.try_duel_accept()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_duel_decline(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_decline"):
		return
	var result: Dictionary = srv.try_duel_decline()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_duel_forfeit(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_forfeit"):
		return
	var result: Dictionary = srv.try_duel_forfeit()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_craft(ctrl, recipe_id: String, qty: int = 1) -> void:
	recipe_id = str(recipe_id).strip_edges()
	qty = int(qty)
	if recipe_id.is_empty() or qty <= 0:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_craft"):
		return
	var result: Dictionary = srv.try_craft(recipe_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_emote(ctrl, emote_id: String) -> void:
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_emote"):
		return
	var result: Dictionary = srv.try_emote(emote_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_dungeon_enter(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_enter"):
		return
	var result: Dictionary = srv.try_dungeon_enter()
	ctrl._apply_dungeon_server_result(result)

static func request_dungeon_exit(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_exit"):
		return
	var result: Dictionary = srv.try_dungeon_exit()
	ctrl._apply_dungeon_server_result(result)

static func request_pet_summon(ctrl, pet_id: String = "default") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_pet_summon"):
		return
	var result: Dictionary = srv.try_pet_summon(pet_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_pet_dismiss(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_pet_dismiss"):
		return
	var result: Dictionary = srv.try_pet_dismiss()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_warehouse_open(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_open"):
		return
	var result: Dictionary = srv.try_warehouse_open()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_warehouse_deposit(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_deposit"):
		return
	var result: Dictionary = srv.try_warehouse_deposit(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_warehouse_withdraw(ctrl, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_withdraw"):
		return
	var result: Dictionary = srv.try_warehouse_withdraw(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_warehouse_deposit_gold(ctrl, amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_deposit_gold"):
		return
	var result: Dictionary = srv.try_warehouse_deposit_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_warehouse_withdraw_gold(ctrl, amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_withdraw_gold"):
		return
	var result: Dictionary = srv.try_warehouse_withdraw_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_friend_add(ctrl, name_or_id: String) -> void:
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_friend_add"):
		return
	var result: Dictionary = srv.try_friend_add(name_or_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_friend_remove(ctrl, friend_id: String) -> void:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_friend_remove"):
		return
	var result: Dictionary = srv.try_friend_remove(friend_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_create(ctrl, guild_name: String) -> void:
	guild_name = str(guild_name).strip_edges()
	if guild_name.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_create"):
		return
	var result: Dictionary = srv.try_guild_create(guild_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_invite(ctrl, target: String) -> void:
	target = str(target).strip_edges()
	if target.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_invite"):
		return
	var result: Dictionary = srv.try_guild_invite(target)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_kick(ctrl, member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_kick"):
		return
	var result: Dictionary = srv.try_guild_kick(member_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_leave(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_leave"):
		return
	var result: Dictionary = srv.try_guild_leave()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_disband(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_disband"):
		return
	var result: Dictionary = srv.try_guild_disband()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_guild_invite_respond(ctrl, invite_id: String, accept: bool) -> void:
	invite_id = str(invite_id).strip_edges()
	if invite_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_invite_respond"):
		return
	var result: Dictionary = srv.try_guild_invite_respond(invite_id, accept)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_mail_send(ctrl, to: String, subject: String, body: String, gold: int = 0, item_id: String = "", qty: int = 1) -> void:
	to = str(to).strip_edges()
	if to.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_send"):
		return
	var result: Dictionary = srv.try_mail_send(to, subject, body, gold, item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_mail_read(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_read"):
		return
	var result: Dictionary = srv.try_mail_read(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_mail_claim(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_claim"):
		return
	var result: Dictionary = srv.try_mail_claim(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_mail_delete(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_delete"):
		return
	var result: Dictionary = srv.try_mail_delete(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_auction_list(ctrl, item_id: String, qty: int = 1, price_gold: int = 1) -> void:
	item_id = str(item_id).strip_edges()
	if item_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_list"):
		return
	var result: Dictionary = srv.try_auction_list(item_id, qty, price_gold)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_auction_buy(ctrl, listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_buy"):
		return
	var result: Dictionary = srv.try_auction_buy(listing_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_auction_cancel(ctrl, listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_cancel"):
		return
	var result: Dictionary = srv.try_auction_cancel(listing_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)

static func request_learn_skill(ctrl, skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_learn_skill"):
		return
	var result: Dictionary = srv.try_learn_skill(skill_id)
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_skill_respec(ctrl) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_skill_respec"):
		return
	var result: Dictionary = srv.try_skill_respec()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(acts_v)

static func request_use_skill(ctrl, skill_id: String, ground: Vector2i = Vector2i(-9999, -9999)) -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_use_skill"):
		return
	skill_id = skill_id.strip_edges()
	var def: Dictionary = {}
	if srv.has_method("skill_def"):
		def = srv.skill_def(skill_id)
	var tmode := str(def.get("target_mode", "")).strip_edges().to_lower()
	if tmode.is_empty() and bool(def.get("requires_target", false)):
		tmode = "unit"
	if tmode.is_empty():
		tmode = "none"
	var target_id := ""
	var npc = null
	if not ctrl._selected_npc_id.is_empty():
		npc = ctrl._find_npc_by_id(ctrl._selected_npc_id)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = ctrl._selected_npc_id
		else:
			npc = null
	if target_id.is_empty() and tmode != "ground":
		var facing_dir: int = 2
		if ctrl.player.has_method("get_facing"):
			facing_dir = CharsetSheet.dir_from_facing(str(ctrl.player.get_facing()))
		npc = ctrl._find_adjacent_npc(ctrl.player.cell, facing_dir)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = str(npc.npc_id) if "npc_id" in npc else ""
	# Duel shell: selected remote opponent is a valid skill/attack target.
	if target_id.is_empty() and not ctrl._selected_remote_id.is_empty():
		var duel_srv = Net.server()
		if duel_srv != null and duel_srv.has_method("in_duel") and duel_srv.in_duel():
			var dsnap: Dictionary = duel_srv.snapshot_duel() if duel_srv.has_method("snapshot_duel") else {}
			if str(dsnap.get("opponent_id", "")) == ctrl._selected_remote_id:
				target_id = ctrl._selected_remote_id
	if tmode == "ground" and ground.x <= -9990:
		if npc != null and "cell" in npc:
			ground = npc.cell
		elif target_id.is_empty():
			ctrl.begin_skill_aim(skill_id)
			return
	var chase_rng: int = ctrl._skill_chase_range(def)
	if chase_rng > 0 and npc != null and ctrl.player != null:
		var pcell: Vector2i = ctrl.player.cell
		if not ctrl._player_in_skill_range(npc, chase_rng, pcell):
			ctrl._set_pending_engage(npc, skill_id, chase_rng)
			if not ctrl._path_to_npc_range(npc, chase_rng):
				ctrl._clear_pending_engage()
				if ctrl.hud != null and ctrl.hud.has_method("append_system"):
					ctrl.hud.append_system("无法到达施法距离")
			return
		ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
	ctrl.cancel_skill_aim()
	var gx: int = ground.x
	var gy: int = ground.y
	var result: Dictionary = srv.try_use_skill(skill_id, target_id, ctrl.player.cell.x, ctrl.player.cell.y, gx, gy)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, npc)

static func request_use_item(ctrl, item_id: String) -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_use_item"):
		return
	var result: Dictionary = srv.try_use_item(item_id)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, null)

static func request_equip_item(ctrl, item_id: String, slot: String = "") -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_equip_item"):
		return
	var result: Dictionary = srv.try_equip_item(item_id, slot)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, null)

static func request_unequip_item(ctrl, slot: String) -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_unequip_item"):
		return
	var result: Dictionary = srv.try_unequip_item(slot)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, null)

