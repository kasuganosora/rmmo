extends SceneTree
## Exercise module-owned storage and compatibility through the public facade.
const Server = preload("res://scripts/net/mock_server.gd")
const Config = preload("res://scripts/net/server/mock_config.gd")
var failed := 0

class Summons extends RefCounted:
	var pending := {"invites": {"peer": {}}}
	func snapshot_pet() -> Dictionary: return {"adapter": "3d_pet"}
	func pet_summon(_id: String) -> Dictionary: return {"ok": true, "adapter": "3d_summon"}
	func pet_dismiss() -> Dictionary: return {"ok": true, "adapter": "3d_dismiss"}
	func snapshot_party() -> Dictionary: return {"adapter": "3d_party"}
	func party_accept(_id: String) -> Dictionary: return {"ok": true, "adapter": "3d_accept"}
	func party_decline(_id: String) -> Dictionary: return {"ok": true, "adapter": "3d_decline"}

class WorldAdapter extends RefCounted:
	var summons := Summons.new()
	func use_item(_id: String) -> Dictionary: return {"ok": true, "adapter": "3d_item"}

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failed += 1

func _run() -> void:
	create_timer(20.0).timeout.connect(func():
		print("FAIL module test watchdog expired")
		quit(1))
	var a = Server.new()
	var b = Server.new()
	a._init_combat_layers()
	b._init_combat_layers()
	expect(a.inventory != b.inventory, "independent model instances")
	a._session_user = "isolated"
	expect(a._session_module_logic._session_user == "isolated" and b._session_user == "", "scalar setters reach owner only")
	a._session_module_logic._session_user = "from_module"
	expect(a.is_logged_in() and a._session_user == "from_module", "module writes reach facade and queries")
	a._remote_players["test"] = {"name": "Test"}
	expect(a._remote_module_logic._remote_players.has("test") and b._remote_players.is_empty(), "dictionary mutation preserves alias and isolation")
	a._party_members.append({"id": "test"})
	expect(a._party_module_logic._party_members.size() == 1 and b._party_members.is_empty(), "array mutation preserves alias and isolation")
	a._party_members = []
	expect(a._party_module_logic._party_members.is_empty(), "collection replacement reaches owner")
	a.combat_randf = func(): return 0.25
	expect(is_equal_approx(a.combat_engine.combat_randf.call(), 0.25), "combat roll setter keeps engine synchronized")
	a.combat_randf = Callable()
	a._init_combat_layers()
	expect(a.inventory.get_qty("wooden_sword") >= 1, "bootstrap retains starter inventory")
	expect(a.combat_engine.bag == a.inventory, "bootstrap connects engine to owned inventory")
	a.weather_auto = false
	a._tick_frame(0.5)
	expect(a._pending_tick_actions.is_empty(), "unplaced player does not tick gameplay")
	a.set_player_cell(0, 0)
	a.register_npc("refactor_guide", 1, 0)
	a.npc_meta["refactor_guide"] = {"name": "Guide", "interact_text": "Welcome"}
	var result: Dictionary = a.try_interact("refactor_guide", 100, 100)
	expect(result.ok and result.actions[0].type == "show_npc_dialogue", "interaction uses authoritative position across modules")
	a.set_player_cell(10, 10)
	expect(not a.try_interact("refactor_guide", 0, 0).ok, "spoofed nearby coordinates cannot bypass interaction range")
	a._pending_tick_actions = [{"type": "test_tick"}]
	var drained: Array = a.poll_combat_tick()
	expect(drained.size() == 1 and a._pending_tick_actions.is_empty(), "poll drains module-owned action queue")
	drained.clear()
	expect(a._pending_tick_actions.is_empty(), "drained actions have independent storage")
	var adapter := WorldAdapter.new()
	a.world3d_summons = weakref(adapter)
	expect(a.try_use_item("anything").adapter == "3d_item", "item routes through mounted 3D adapter")
	expect(a.snapshot_pet().adapter == "3d_pet", "pet snapshot routes through 3D adapter")
	expect(a.try_pet_summon().adapter == "3d_summon" and a.try_pet_dismiss().adapter == "3d_dismiss", "pet mutations route through 3D adapter")
	expect(a.snapshot_party_summon().adapter == "3d_party", "party snapshot routes through 3D adapter")
	expect(a.try_party_summon_accept().adapter == "3d_accept" and a.try_party_summon_decline().adapter == "3d_decline", "party responses route through 3D adapter")
	expect(a.try_party_summon_accept_all().accepted == 1, "party accept-all retains 3D routing")
	adapter = null
	expect(a.snapshot_pet().has("active"), "expired 3D adapter restores module fallback")
	_exercise_business(a)
	for key in Config.SETTINGS:
		var setting: String = "rmmo/mock/" + key
		var previous: Variant = ProjectSettings.get_setting(setting)
		ProjectSettings.set_setting(setting, -10.0)
		expect(Config.number(key) == float(Config.SETTINGS[key][1]), "config clamps lower bound: " + key)
		ProjectSettings.set_setting(setting, INF)
		expect(Config.number(key) == float(Config.SETTINGS[key][0]), "config rejects non-finite value: " + key)
		ProjectSettings.set_setting(setting, "invalid")
		expect(Config.number(key) == float(Config.SETTINGS[key][0]), "config rejects wrong type: " + key)
		ProjectSettings.set_setting(setting, previous)
	a.free()
	b.free()
	# The asynchronous API must still emit its original signals through the facade.
	var srv = root.get_node("MockServer")
	var old_latency: Variant = ProjectSettings.get_setting("rmmo/mock/latency_sec")
	ProjectSettings.set_setting("rmmo/mock/latency_sec", 0.0)
	srv.logout()
	srv.login("module_test", "password", "local")
	var login: Array = await srv.login_finished
	expect(login[0] and srv.is_logged_in(), "async login signal survives module dispatch")
	srv.fetch_characters()
	var characters: Array = await srv.characters_ready
	expect(characters.is_empty(), "new account retains empty character list")
	srv.create_character("Module Hero", "adventurer", "1")
	var created: Array = await srv.character_created
	expect(created[0] and created[2].name == "Module Hero", "async character creation survives module dispatch")
	srv.fetch_characters()
	characters = await srv.characters_ready
	expect(characters.size() == 1, "fetch reads character created in owned session state")
	srv.enter_world3d(int(created[2].id))
	var entered: Array = await srv.enter_world_ready
	expect(entered[0] and not srv._session_character_id.is_empty(), "3D entry adapter preserves session initialization")
	srv.logout()
	expect(not srv.is_logged_in() and srv._session_character_id.is_empty(), "logout clears owned session state")
	ProjectSettings.set_setting("rmmo/mock/latency_sec", old_latency)
	print("MOCK_MODULE_TESTS failures=", failed)
	quit(0 if failed == 0 else 1)

func _exercise_business(srv) -> void:
	# Explicit test definitions avoid depending on optional external catalogs.
	srv.item_catalog.register_item({"id": "module_blade", "type": "equipment", "equip_slot": "weapon_main"})
	srv.inventory.add_item("module_blade", 1)
	expect(srv.try_equip_item("module_blade", "weapon_main").ok, "equipment module transfers registered item from inventory")
	expect(srv.equipment.get_item_in("weapon_main") == "module_blade", "equipment state projects equipped item")
	expect(srv.try_use_item("module_blade").ok and srv.equipment.get_item_in("weapon_main") == "", "item use delegates to equipment toggle")
	srv.item_catalog.register_item({"id": "module_herb", "type": "material", "sell_price": 3})
	srv.set_player_cell(0, 0)
	srv._gather_nodes["module_node"] = {"id": "module_node", "cell": {"x": 1, "y": 0},
		"respawn_sec": 5.0, "yields": [{"item_id": "module_herb", "qty": 2, "weight": 1}]}
	expect(srv.try_gather("module_node").ok and srv.inventory.get_qty("module_herb") == 2, "gathering updates owned inventory")
	expect(srv._gather_state.module_node.depleted, "gathering marks owned resource state depleted")
	expect(not srv.try_gather("module_node").ok, "depleted node rejects duplicate gathering")
	srv.force_gather_respawn("module_node")
	expect(srv.try_gather("module_node").ok, "resource respawn restores gathering")
	srv.recipe_catalog.register_recipe({"id": "module_recipe", "ingredients": [{"id": "module_herb", "qty": 2}],
		"output": {"id": "potion_hp_small", "qty": 1}})
	var before: int = srv.inventory.get_qty("potion_hp_small")
	expect(srv.try_craft("module_recipe").ok and srv.inventory.get_qty("potion_hp_small") == before + 1, "crafting consumes registered ingredients and grants output")
	var gold: int = srv.inventory.get_gold()
	expect(srv.try_shop_sell("module_herb", 1).ok and srv.inventory.get_gold() == gold + 3, "shop sale updates inventory and gold")
	var rows: Array = srv.snapshot_shop_buyback()
	expect(not rows.is_empty() and rows[-1].item_id == "module_herb", "shop owns buyback rows")
	expect(srv.try_shop_buyback(rows.size() - 1).ok, "buyback restores sold material")
	srv.combat_stats.statuses.apply_status("player", {"id": "module_buff", "kind": "buff"}, 30.0, "player")
	expect(srv.try_cancel_status("module_buff").ok and not srv.combat_stats.statuses.has_status("player", "module_buff"), "combat cancels beneficial status through module facade")
	srv.combat_stats.statuses.apply_status("player", {"id": "module_dot", "kind": "dot"}, 30.0, "player")
	expect(not srv.try_cancel_status("module_dot").ok, "combat rejects cancellation of harmful status")
	var actions: Array = srv._add_items_to_ground({"x": 0, "y": 0}, [{"item_id": "module_herb", "qty": 1}], "test")
	expect(not actions.is_empty() and srv.ground_bag_count() == 1, "loot creates bag in owned ground state")
	srv._add_items_to_ground({"x": 0, "y": 0}, [{"item_id": "module_herb", "qty": 1}], "test")
	expect(srv.ground_bag_count() == 1, "loot merges drops at same cell")
	var bag_id: String = srv.find_ground_bag_at(0, 0)
	expect(srv.try_open_ground_bag(bag_id).ok and srv.try_loot_take_all().ok, "loot opens and transfers bag contents through facade")
