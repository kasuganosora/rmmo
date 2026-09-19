extends RefCounted
## Application layer: spawn NPCs from content pack, clear, layer ensure.

const Net = preload("res://scripts/net/net.gd")
const NpcActor = preload("res://scripts/game/npc_actor.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")

static func _clear_npcs(ctrl) -> void:
	var am: Node = ctrl._asset_mgr
	for n in ctrl._npcs:
		if n != null and is_instance_valid(n):
			if am != null and "npc_id" in n and am.has_method("clear_actor_refs"):
				var nid = str(n.npc_id).strip_edges()
				if nid != "":
					am.clear_actor_refs(nid)
					if am.has_method("note_actor_ring"):
						am.note_actor_ring(nid, "COLD")
			n.queue_free()
	ctrl._npcs.clear()
	if ctrl._aoi != null:
		ctrl._aoi.reset()
	ctrl._radar_blips_cache.clear()
	ctrl._radar_blips_sig = PackedInt32Array()
	ctrl._radar_blips_ready = false
	if ctrl._npc_layer != null and is_instance_valid(ctrl._npc_layer):
		for c in ctrl._npc_layer.get_children():
			c.queue_free()
	ctrl._clear_ground_markers()

static func _ensure_npc_layer(ctrl) -> Node2D:
	if ctrl._npc_layer != null and is_instance_valid(ctrl._npc_layer):
		return ctrl._npc_layer
	ctrl._npc_layer = ctrl.get_node_or_null("NpcLayer") as Node2D
	if ctrl._npc_layer == null:
		ctrl._npc_layer = Node2D.new()
		ctrl._npc_layer.name = "NpcLayer"
		ctrl._npc_layer.y_sort_enabled = true
		ctrl._npc_layer.z_index = 5
		ctrl._npc_layer.z_as_relative = false
		ctrl.add_child(ctrl._npc_layer)
		# Keep under map visuals but with player/npcs sorting among themselves.
		if ctrl.map_field != null:
			ctrl.move_child(ctrl._npc_layer, ctrl.map_field.get_index() + 1)
	return ctrl._npc_layer

static func _spawn_npcs_from_pack(ctrl) -> void:
	ctrl._clear_npcs()
	if ctrl.map_field == null or ctrl.map_field.pack == null:
		return
	var pack = ctrl.map_field.pack
	# Optional pack charset_root -> ProjectSettings for this session.
	var pack_root: String = str(pack.charset_root) if pack.get("charset_root") != null else ""
	if pack_root.strip_edges() != "":
		ProjectSettings.set_setting(CharsetSheet.SETTING_ROOT, pack_root.strip_edges())
	elif not ProjectSettings.has_setting(CharsetSheet.SETTING_ROOT):
		ProjectSettings.set_setting(CharsetSheet.SETTING_ROOT, CharsetSheet.DEFAULT_DEV_ROOT)

	var list: Array = pack.npcs if pack.get("npcs") != null else []
	var occupied: Dictionary = {}
	for item0 in list:
		if typeof(item0) != TYPE_DICTIONARY:
			continue
		var c0: Variant = item0.get("cell", {})
		if typeof(c0) == TYPE_DICTIONARY:
			occupied["%d,%d" % [int(c0.get("x", 0)), int(c0.get("y", 0))]] = true
	var evs: Array = pack.events if pack.get("events") != null else []
	var rt = null
	var srv0 = Net.server()
	if srv0 != null and "event_runtime" in srv0:
		rt = srv0.event_runtime
	for ev_v in evs:
		if typeof(ev_v) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_v
		var ec: Variant = ev.get("cell", {})
		if typeof(ec) != TYPE_DICTIONARY:
			continue
		var ekey = "%d,%d" % [int(ec.get("x", 0)), int(ec.get("y", 0))]
		if occupied.has(ekey):
			continue
		var page: Dictionary = {}
		if rt != null and rt.has_method("select_page"):
			page = rt.select_page(ev)
		var ev_actor: Dictionary = EventCommands.event_actor_data(ev, page)
		list.append(ev_actor)
		occupied[ekey] = true
	if list.is_empty():
		return
	var layer = ctrl._ensure_npc_layer()
	var pack_dir: String = str(pack.pack_dir)
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var npc_n = NpcActor.new()
		layer.add_child(npc_n)
		npc_n.setup(item, ctrl.map_field, pack_dir)
		# Charset stream: AOI driver enqueues by ring; NpcActor may show placeholder
		ctrl._npcs.append(npc_n)
	# Sync occupancy onto MockServer collision (authoritative move checks).
	var srv = Net.server()
	if srv != null and srv.map_collision != null and srv.map_collision.has_method("apply_npc_blocks"):
		srv.map_collision.clear_extra_blocked()
		srv.map_collision.apply_npc_blocks(list)
		# Re-apply player occupancy wiped by clear_extra_blocked.
		if ctrl.player != null and srv.has_method("set_player_cell"):
			srv.set_player_cell(ctrl.player.cell.x, ctrl.player.cell.y)
	# Register NPC cells for server-side range / tick counter-attacks.
	if srv != null and srv.has_method("register_npc"):
		for item in list:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = item
			var nid = str(n.get("id", "")).strip_edges()
			if nid.is_empty():
				continue
			var cell_v: Variant = n.get("cell", {})
			if typeof(cell_v) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = cell_v
			srv.register_npc(
				nid,
				int(cd.get("x", 0)),
				int(cd.get("y", 0)),
				bool(n.get("hostile", false)),
				bool(n.get("aggressive", false)),
				int(n.get("direction", 2)),
				maxi(int(n.get("wander_radius", 0)), 0),
				int(n.get("group_id", 0)),
				n
			)
	ctrl._sync_npc_combat_display()
	ctrl._refresh_aoi(true)

