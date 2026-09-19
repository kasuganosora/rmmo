extends RefCounted
## Application layer: item pickup, auto pickup, take all.

const Net = preload("res://scripts/net/net.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

static func pickup_nearest(ctrl) -> void:
	if ctrl.player == null or ctrl.player.input_locked:
		return
	var best_id = ""
	var best_d = 99
	var pcell: Vector2i = ctrl.player.cell
	for bag_id in ctrl._ground_markers.keys():
		var mk = ctrl._ground_markers[bag_id]
		if mk == null or not is_instance_valid(mk) or not mk.has_meta("cell"):
			continue
		var c: Vector2i = mk.get_meta("cell")
		var d: int = maxi(absi(pcell.x - c.x), absi(pcell.y - c.y))
		if d < best_d:
			best_d = d
			best_id = str(bag_id)
	if best_id.is_empty() or best_d > 8:
		if ctrl.hud != null and ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system("附近没有掉落。")
		return
	if best_d <= 1:
		ctrl.request_open_ground_bag(best_id)
		return
	var mk2 = ctrl._ground_markers[best_id]
	if ctrl.player.has_method("click_move_to") and mk2.has_meta("cell"):
		ctrl.player.click_move_to(mk2.get_meta("cell"))

static func _try_auto_pickup_at(ctrl, cell: Vector2i) -> void:
	var bag_id = ctrl._find_ground_bag_at(cell)
	if bag_id.is_empty():
		return
	var srv = Net.server()
	# Respect party loot ownership — do not auto-open/take teammates' bags.
	if srv != null and srv.has_method("can_loot_ground_bag") and not bool(srv.can_loot_ground_bag(bag_id)):
		return
	ctrl.request_open_ground_bag(bag_id)
	ctrl.call_deferred("_auto_take_all")

static func _auto_take_all(ctrl) -> void:
	var srv = Net.server()
	if srv == null:
		return
	var gs = GameSettingsScript.get_i()
	var filter = "all"
	if gs != null:
		filter = str(gs.get("auto_pickup_filter"))
	if filter not in GameSettingsScript.AUTO_PICKUP_FILTER_IDS:
		filter = "all"
	if filter == "all":
		if srv.has_method("try_loot_take_all"):
			var result: Dictionary = srv.try_loot_take_all()
			var actions_v: Variant = result.get("actions", [])
			if typeof(actions_v) == TYPE_ARRAY:
				ctrl._apply_server_actions(actions_v)
		return
	# Filtered auto-loot: take matching stacks only; leave rest on ground.
	if not srv.has_method("try_loot_take"):
		return
	var catalog = srv.get("item_catalog")
	var pending: Array = []
	if srv.has_method("pending_loot_snapshot"):
		var snap: Dictionary = srv.pending_loot_snapshot()
		var items_v: Variant = snap.get("items", [])
		if typeof(items_v) == TYPE_ARRAY:
			pending = items_v
	var ids: Array = []
	for d_v in pending:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var iid = str(d_v.get("item_id", "")).strip_edges()
		if iid.is_empty():
			continue
		if GameSettingsScript.matches_auto_pickup_filter(filter, iid, catalog):
			ids.append(iid)
	for iid in ids:
		if not srv.has_method("has_pending_loot") or not bool(srv.has_pending_loot()):
			break
		var r: Dictionary = srv.try_loot_take(str(iid), -1)
		var sub_v: Variant = r.get("actions", [])
		if typeof(sub_v) == TYPE_ARRAY:
			ctrl._apply_server_actions(sub_v)
	# Close loot UI if leftovers remain (manual window still can take anything).
	if srv.has_method("has_pending_loot") and bool(srv.has_pending_loot()) and srv.has_method("try_loot_close"):
		var cr: Dictionary = srv.try_loot_close()
		var ca: Variant = cr.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			ctrl._apply_server_actions(ca)

