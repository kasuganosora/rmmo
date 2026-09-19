extends RefCounted
## Application layer: map/scene transfer requested by server action.

const Net = preload("res://scripts/net/net.gd")

static func _on_transfer_requested(ctrl, result: Dictionary) -> void:
	## Hand off to Loading screen; do not rebuild map in-place or call enter_world.
	ctrl._clear_pending_engage()
	ctrl._clear_npc_selection()
	if ctrl.player != null:
		ctrl.player.input_locked = true
		if ctrl.player.has_method("clear_move_path"):
			ctrl.player.clear_move_path()
	ctrl._clear_npcs()
	# Client-side: drop old-map ground bags / remotes before scene swap.
	ctrl._clear_ground_markers()
	ctrl._clear_remote_markers()
	if ctrl.hud != null:
		if ctrl.hud.has_method("hide_loot"):
			ctrl.hud.hide_loot()
		if ctrl.hud.has_method("hide_ground_tip"):
			ctrl.hud.hide_ground_tip()
		if ctrl.hud.has_method("hide_trade"):
			ctrl.hud.hide_trade()

	var pack_path: String = str(result.get("pack_path", ""))
	var map_id: String = str(result.get("map_id", ""))
	var cell_v: Variant = result.get("cell", {})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var facing: int = int(result.get("facing", 2))
	var message: String = str(result.get("message", ""))

	var spawn: Dictionary = Net.session().spawn_data.duplicate(true)
	spawn["map_id"] = map_id if map_id != "" else pack_path.get_file()
	spawn["pack_path"] = pack_path
	var cid = str(result.get("content_id", "")).strip_edges()
	if cid != "":
		spawn["content_id"] = cid
	var cver = str(result.get("content_version", "")).strip_edges()
	if cver != "":
		spawn["content_version"] = cver
	spawn["cell"] = {"x": cell.x, "y": cell.y}
	spawn["facing"] = facing
	if message != "":
		spawn["transfer_message"] = message
	# Never carry previous map's ground bags / remotes into the new spawn snapshot.
	spawn["ground_bags"] = []
	spawn["remote_players"] = []
	if bool(result.get("bags_cleared", true)):
		spawn["bags_cleared"] = true
	# Prefer fresh journal from transfer result / MockServer (reach objectives).
	var quests_v: Variant = result.get("quests", null)
	if typeof(quests_v) == TYPE_ARRAY:
		spawn["quests"] = quests_v
	else:
		var srv_q = Net.server()
		if srv_q != null and srv_q.has_method("get_quest_list"):
			spawn["quests"] = srv_q.get_quest_list()
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_party"):
		spawn["party"] = srv.snapshot_party()
	if not spawn.has("character") or typeof(spawn.get("character")) != TYPE_DICTIONARY:
		var ch: Dictionary = Net.session().active_character()
		if not ch.is_empty():
			spawn["character"] = ch
	# Apply transfer system messages (bag clear tip) before leaving World.
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY and ctrl.hud != null:
		for a in actions_v:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if str(a.get("type", "")) == "system_message" and ctrl.hud.has_method("append_system"):
				var msg = str(a.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.hud.append_system(msg)
	Net.session().spawn_data = spawn
	Net.session().loading_mode = "transfer"
	Net.session().go_loading()

