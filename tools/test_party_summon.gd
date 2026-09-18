extends SceneTree
## Headless: party_summon「集结石」— same-map party pull to adjacent free cells.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_summon: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_stats == null:
		print("test_party_summon: FAIL combat layers missing")
		quit(1)
		return

	# --- Catalog ---
	failed += _expect(srv.item_catalog.has_item("party_summon"), "catalog has party_summon")
	var def: Dictionary = srv.item_catalog.get_item("party_summon")
	failed += _expect(str(def.get("name", "")) == "集结石", "Chinese name 集结石")
	failed += _expect(str(def.get("use_effect", def.get("effect", ""))) == "party_summon", "use_effect party_summon")
	failed += _expect(bool(def.get("consumable", false)), "consumable")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 60.0) < 0.01, "cooldown 60s")
	failed += _expect(int(def.get("icon_index", -1)) == 186, "reuse scroll icon_index 186")

	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "party_summon"), "shop sells party_summon")

	failed += _expect(srv.has_method("try_party_summon_accept"), "has try_party_summon_accept")
	failed += _expect(srv.has_method("try_party_summon_accept_all"), "has try_party_summon_accept_all")
	failed += _expect(srv.has_method("snapshot_party_summon"), "has snapshot_party_summon")

	var stats = srv.combat_stats
	srv.awaiting_respawn = false
	srv.sitting = false
	srv.party_summon_auto_accept = false
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("1")
	stats.reset_player(3)
	stats.item_ready_at.clear()
	srv.set_player_cell(10, 10)
	# Open map collision: everything landable (null collision → free cells OK).
	srv.map_collision = null

	# --- Solo fail ---
	srv.inventory.clear()
	srv.inventory.add_item("party_summon", 3)
	failed += _expect(not srv.in_party(), "solo not in party")
	var r_solo: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(not bool(r_solo.get("ok", true)), "solo use fails")
	failed += _expect(str(r_solo.get("reason", "")) == "need_party", "solo reason need_party")
	failed += _expect(_has_msg(r_solo, "需要队伍。"), "solo msg 需要队伍。")
	failed += _expect(srv.inventory.get_qty("party_summon") == 3, "solo not consumed")

	# --- Party N=1 fail ---
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "party create ok")
	failed += _expect(int(srv._party_online_same_map_count()) == 1, "N=1")
	var r_n1: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(not bool(r_n1.get("ok", true)), "N=1 fails")
	failed += _expect(_has_msg(r_n1, "需要队伍。"), "N=1 msg 需要队伍。")
	failed += _expect(srv.inventory.get_qty("party_summon") == 3, "N=1 not consumed")

	# --- Party N=2: use + accept ---
	var stub: Dictionary = srv._party_make_stub("stub_ally_summon")
	stub["name"] = "盟友甲"
	srv._party_members.append(stub)
	failed += _expect(int(srv._party_online_same_map_count()) == 2, "N=2")
	stats.item_ready_at.clear()
	var r_use: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(bool(r_use.get("ok", false)), "party use ok")
	failed += _expect(_has_msg(r_use, "发出了集结。"), "msg 发出了集结。")
	failed += _expect(_has_type(r_use.get("actions", []), "party_summon"), "emits party_summon")
	failed += _expect(srv.inventory.get_qty("party_summon") == 2, "consumed 1")
	var snap: Dictionary = srv.snapshot_party_summon()
	failed += _expect(bool(snap.get("active", false)), "pending active")
	failed += _expect(str(snap.get("id", "")) != "", "summon id")
	var invites: Dictionary = snap.get("invites", {}) if typeof(snap.get("invites", {})) == TYPE_DICTIONARY else {}
	failed += _expect(invites.has("stub_ally_summon"), "invite for stub")

	var r_acc: Dictionary = srv.try_party_summon_accept("stub_ally_summon")
	failed += _expect(bool(r_acc.get("ok", false)), "accept ok")
	failed += _expect(_has_msg(r_acc, "响应了集结"), "accept msg")
	failed += _expect(_has_type(r_acc.get("actions", []), "party_summon_arrive"), "arrive action")
	var ax: int = int(r_acc.get("x", -9999))
	var ay: int = int(r_acc.get("y", -9999))
	failed += _expect(ax > -9990 and ay > -9990, "dest cell set")
	failed += _expect(maxi(absi(ax - 10), absi(ay - 10)) == 1, "dest adjacent to caster (got %d,%d)" % [ax, ay])
	var midx: int = srv._party_find_member_index("stub_ally_summon")
	failed += _expect(midx >= 0, "stub still in party")
	if midx >= 0:
		var mcell: Variant = (srv._party_members[midx] as Dictionary).get("cell", {})
		failed += _expect(typeof(mcell) == TYPE_DICTIONARY, "member cell dict")
		if typeof(mcell) == TYPE_DICTIONARY:
			failed += _expect(int(mcell.get("x", -1)) == ax and int(mcell.get("y", -1)) == ay, "member cell matches")

	# --- CD blocks ---
	var r_cd: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(not bool(r_cd.get("ok", true)), "on CD rejected")
	failed += _expect(str(r_cd.get("reason", "")) == "cooldown", "reason cooldown")
	failed += _expect(srv.inventory.get_qty("party_summon") == 2, "CD no consume")

	# --- No free cell fail ---
	stats.item_ready_at.clear()
	srv._party_summon_pending.clear()
	# Block all adjacent via custom collision
	srv.map_collision = _BlockedAll.new()
	var r_block: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(not bool(r_block.get("ok", true)), "no space fails")
	failed += _expect(str(r_block.get("reason", "")) == "no_space", "reason no_space")
	failed += _expect(_has_msg(r_block, "没有空余位置。"), "msg 没有空余位置。")
	failed += _expect(srv.inventory.get_qty("party_summon") == 2, "no-space not consumed")

	# --- Auto-accept debug path ---
	srv.map_collision = null
	stats.item_ready_at.clear()
	srv._party_summon_pending.clear()
	# Reset stub cell
	midx = srv._party_find_member_index("stub_ally_summon")
	if midx >= 0:
		var m2: Dictionary = srv._party_members[midx]
		m2.erase("cell")
		srv._party_members[midx] = m2
	srv.party_summon_auto_accept = true
	var r_auto: Dictionary = srv.try_use_item("party_summon")
	failed += _expect(bool(r_auto.get("ok", false)), "auto use ok")
	failed += _expect(_has_msg(r_auto, "发出了集结。"), "auto emit msg")
	failed += _expect(_has_msg(r_auto, "响应了集结"), "auto accept msg in same result")
	failed += _expect(_has_type(r_auto.get("actions", []), "party_summon_arrive"), "auto arrive")
	failed += _expect(srv.inventory.get_qty("party_summon") == 1, "auto consumed")
	srv.party_summon_auto_accept = false

	# Cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv.map_collision = null

	if failed == 0:
		print("test_party_summon: PASS")
		quit(0)
		return
	print("test_party_summon: FAIL count=%d" % failed)
	quit(1)


class _BlockedAll extends RefCounted:
	func is_landable(_x: int, _y: int) -> bool:
		return false

	func is_extra_blocked(_x: int, _y: int) -> bool:
		return true

	func is_valid(_x: int, _y: int) -> bool:
		return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	print("  FAIL  %s" % label)
	return 1


func _has_msg(result: Dictionary, frag: String) -> bool:
	var acts: Variant = result.get("actions", [])
	if typeof(acts) != TYPE_ARRAY:
		return false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(frag) >= 0:
			return true
	return false


func _has_type(acts: Variant, t: String) -> bool:
	if typeof(acts) != TYPE_ARRAY:
		return false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false
