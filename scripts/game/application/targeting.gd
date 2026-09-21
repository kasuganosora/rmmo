extends RefCounted
## 用例编排（应用层）：目标选择 / 交战 / 名牌距离 / 寻路接近。
## 静态方法接收组合根 ctrl；组内互调经 ctrl.<name>() 回到组合根委托（非自调用，不成环）。

const Net = preload("res://scripts/net/net.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const NameplateUtil = preload("res://scripts/game/nameplate_util.gd")
const GridUtil = preload("res://scripts/util/grid_util.gd")

static func _find_npc_by_id(ctrl, npc_id: String):
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return null
	for n in ctrl._npcs:
		if n != null and is_instance_valid(n) and "npc_id" in n and str(n.npc_id) == npc_id:
			return n
	return null

static func _sync_npc_combat_display(ctrl) -> void:
	## Pull MockServer combat_stats onto actors for nameplates (render-only).
	var srv = Net.server()
	if srv == null or srv.get("combat_stats") == null:
		return
	var stats = srv.combat_stats
	if stats == null or not ("npcs" in stats):
		return
	for actor in ctrl._npcs:
		if actor == null or not is_instance_valid(actor):
			continue
		var nid = str(actor.npc_id) if "npc_id" in actor else ""
		if nid.is_empty() or not stats.npcs.has(nid):
			continue
		var st_v: Variant = stats.npcs[nid]
		if typeof(st_v) != TYPE_DICTIONARY:
			continue
		if actor.has_method("apply_combat_display"):
			actor.apply_combat_display(st_v)

static func _clear_npc_selection(ctrl) -> void:
	if ctrl._selected_npc_id.is_empty():
		return
	var prev = ctrl._find_npc_by_id(ctrl._selected_npc_id)
	if prev != null and prev.has_method("set_selected"):
		prev.set_selected(false)
	ctrl._selected_npc_id = ""

static func clear_target_selection(ctrl) -> void:
	## HUD × / explicit clear: drop foot ring + top target frame.
	ctrl._clear_npc_selection()
	ctrl._clear_remote_selection()
	if ctrl.hud != null and ctrl.hud.has_method("clear_target"):
		ctrl.hud.clear_target()

static func _npc_shows_target_hp(ctrl, npc) -> bool:
	## Only monsters get the red HP bar in the top target frame.
	if npc == null:
		return false
	if "kind" in npc and str(npc.kind) == "monster":
		return true
	if "hostile" in npc and bool(npc.hostile):
		return true
	return false

static func _push_target_hud(ctrl, npc, display_name: String, ratio: float, threat_snap: Dictionary = {}) -> void:
	if ctrl.hud == null or not ctrl.hud.has_method("show_target"):
		return
	var world_pos: Variant = npc.global_position if npc else null
	var mp_ratio = -1.0
	if npc != null and "mp_max" in npc and int(npc.mp_max) > 0:
		mp_ratio = clampf(float(npc.mp) / float(maxi(int(npc.mp_max), 1)), 0.0, 1.0)
	var show_threat = ctrl._npc_shows_target_hp(npc)  # hostile / monster only
	var threat_you = false
	if show_threat:
		if threat_snap.is_empty():
			threat_snap = ctrl._fetch_threat_snapshot(str(npc.npc_id) if npc != null and "npc_id" in npc else "")
		threat_you = bool(threat_snap.get("threat_you", false))
	ctrl.hud.show_target(display_name, ratio, world_pos, ctrl._npc_shows_target_hp(npc), mp_ratio, show_threat, threat_you)

static func _fetch_threat_snapshot(ctrl, npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return {}
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_threat"):
		var s: Variant = srv.snapshot_threat(npc_id)
		if typeof(s) == TYPE_DICTIONARY:
			return s
	return {}

static func _select_npc(ctrl, npc) -> void:
	if npc == null:
		ctrl.clear_target_selection()
		return
	var nid = str(npc.npc_id).strip_edges() if "npc_id" in npc else ""
	if nid.is_empty():
		return
	ctrl._clear_remote_selection()
	if ctrl._selected_npc_id != nid:
		ctrl._clear_npc_selection()
		ctrl._selected_npc_id = nid
		if npc.has_method("set_selected"):
			npc.set_selected(true)
	# Refresh HUD target frame from actor display fields.
	var display_name = nid
	if "npc_name" in npc and str(npc.npc_name).strip_edges() != "":
		display_name = str(npc.npc_name)
	var ratio = 1.0
	if "hp_max" in npc and int(npc.hp_max) > 0:
		ratio = clampf(float(npc.hp) / float(npc.hp_max), 0.0, 1.0)
	ctrl._push_target_hud(npc, display_name, ratio)
	# Shell: selecting a target while grouped marks party shared assist target.
	ctrl.request_party_set_target(nid, display_name)

static func _clear_pending_engage(ctrl) -> void:
	ctrl._pending_engage_npc_id = ""
	ctrl._pending_skill_id = ""
	ctrl._pending_skill_range = 1

static func _set_pending_engage(ctrl, npc, skill_id: String = "", range_cells: int = 1) -> void:
	if npc == null or not ("npc_id" in npc):
		ctrl._clear_pending_engage()
		return
	ctrl._pending_engage_npc_id = str(npc.npc_id).strip_edges()
	ctrl._pending_skill_id = skill_id.strip_edges()
	ctrl._pending_skill_range = maxi(range_cells, 1)

static func _player_beside_npc(ctrl, npc, pcell: Vector2i) -> bool:
	if npc == null:
		return false
	if npc.has_method("is_adjacent_to") and npc.is_adjacent_to(pcell):
		return true
	if npc.has_method("contains_cell") and npc.contains_cell(pcell):
		return true
	return false

static func _cheb(ctrl, a: Vector2i, b: Vector2i) -> int:
	return GridUtil.chebyshev(a, b)

static func _nameplate_max_dist(ctrl) -> int:
	var gs = GameSettingsScript.get_i()
	if gs == null:
		return 12
	return NameplateUtil.clamp_distance(int(gs.nameplate_distance))

static func _refresh_npc_nameplates(ctrl) -> void:
	for npc in ctrl._npcs:
		if npc != null and is_instance_valid(npc) and npc.has_method("_refresh_nameplate"):
			npc._refresh_nameplate()

static func _refresh_remote_nameplates(ctrl) -> void:
	var show_p = GameSettingsScript.flag("show_player_names", true)
	var max_d = ctrl._nameplate_max_dist()
	var pc: Vector2i = ctrl.player.cell if ctrl.player != null and "cell" in ctrl.player else Vector2i.ZERO
	for rid in ctrl._remote_markers.keys():
		var mk = ctrl._remote_markers[rid]
		if mk == null or not is_instance_valid(mk):
			continue
		var lab = mk.get_node_or_null("Name") as Label
		if lab == null:
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var cell = Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			cell = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		var dist = NameplateUtil.chebyshev(pc, cell)
		var is_sel = str(rid) == ctrl._selected_remote_id
		lab.visible = show_p and NameplateUtil.should_show(dist, max_d, is_sel)

static func _tick_nameplate_distance(ctrl, delta: float) -> void:
	# Refresh NPC plates ~4 Hz; remotes update every frame in _tick_remote_aoi.
	ctrl._nameplate_tick_acc += delta
	if ctrl._nameplate_tick_acc < 0.25:
		return
	ctrl._nameplate_tick_acc = 0.0
	ctrl._refresh_npc_nameplates()

static func _approach_cell(ctrl, from: Vector2i, target: Vector2i, range_cells: int) -> Vector2i:
	range_cells = maxi(range_cells, 1)
	var dist: int = ctrl._cheb(from, target)
	if dist <= range_cells:
		return from
	var steps: int = dist - range_cells
	var x: int = from.x
	var y: int = from.y
	for i in range(steps):
		var tdx: int = target.x - x
		var tdy: int = target.y - y
		if tdx == 0 and tdy == 0:
			break
		if tdx > 0:
			x += 1
		elif tdx < 0:
			x -= 1
		if tdy > 0:
			y += 1
		elif tdy < 0:
			y -= 1
	return Vector2i(x, y)

static func _face_toward_cell(ctrl, to: Vector2i) -> void:
	if ctrl.player == null or not ctrl.player.has_method("set_facing_dir"):
		return
	var pcell: Vector2i = ctrl.player.cell
	var d: int = TileId.dir_from_vec(Vector2(float(to.x - pcell.x), float(to.y - pcell.y)))
	if d != 0:
		ctrl.player.set_facing_dir(d)

static func _npc_target_cell(ctrl, npc) -> Vector2i:
	if npc != null and "cell" in npc:
		return npc.cell
	return Vector2i(-9999, -9999)

