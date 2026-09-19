extends RefCounted
## 应用层查询服务：雷达 blips / POI / 任务导航 / NPC 与远程玩家的空间查询。
## 静态方法接收组合根 ctrl；只读查询，不改状态、不创建节点。

const Net = preload("res://scripts/net/net.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const RadarPoi = preload("res://scripts/ui/radar_poi.gd")

static func get_radar_blips(ctrl) -> Array:
	## View-only blips for HUD radar: { world, hostile, kind? }.
	## Includes thin POI dots (quest/inn/smith/gather/fish) from known positions.
	## Cache while NPC cells/hostile/POI flags + remotes unchanged.
	var sig = PackedInt32Array()
	var poi_sample = ctrl._radar_poi_sample()
	var poi_markers: Array = RadarPoi.build_markers(poi_sample)
	var poi_ids: Dictionary = {}
	for pm in poi_markers:
		if typeof(pm) != TYPE_DICTIONARY:
			continue
		var pid = str(pm.get("id", "")).strip_edges()
		if pid != "":
			poi_ids[pid] = true
		var cell_p: Vector2i = pm.get("cell", Vector2i.ZERO)
		sig.append(cell_p.x)
		sig.append(cell_p.y)
		sig.append(ctrl._radar_kind_code(str(pm.get("kind", ""))))
	for n in ctrl._npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid0 = str(n.npc_id) if "npc_id" in n else ""
		if poi_ids.has(nid0):
			continue
		if not ctrl._npc_shows_on_radar(n):
			continue
		var c: Vector2i = n.cell if "cell" in n else Vector2i.ZERO
		var hostile_i: int = 1 if ("hostile" in n and bool(n.hostile)) else 0
		sig.append(c.x)
		sig.append(c.y)
		sig.append(hostile_i)
	for rid in ctrl._remote_markers.keys():
		var rm = ctrl._remote_markers[rid]
		if rm == null or not is_instance_valid(rm):
			continue
		var rc_v: Variant = rm.get_meta("cell", Vector2i.ZERO)
		var rc = rc_v as Vector2i if typeof(rc_v) == TYPE_VECTOR2I else Vector2i(0, 0)
		if typeof(rc_v) == TYPE_DICTIONARY:
			rc = Vector2i(int(rc_v.get("x", 0)), int(rc_v.get("y", 0)))
		sig.append(rc.x)
		sig.append(rc.y)
		sig.append(2)  # friendly remote marker
	if ctrl._radar_blips_ready and ctrl._radar_blips_sig == sig:
		return ctrl._radar_blips_cache
	var out: Array = []
	for pm2 in poi_markers:
		if typeof(pm2) != TYPE_DICTIONARY:
			continue
		var cell2: Vector2i = pm2.get("cell", Vector2i.ZERO)
		var world_pos = Vector2.ZERO
		if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
			world_pos = ctrl.map_field.cell_to_world(cell2)
		else:
			world_pos = Vector2(float(cell2.x) + 0.5, float(cell2.y) + 0.5) * 48.0
		out.append({
			"world": world_pos,
			"hostile": false,
			"kind": str(pm2.get("kind", "")),
			"id": str(pm2.get("id", "")),
			"name": str(pm2.get("name", "")),
		})
	for n in ctrl._npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid1 = str(n.npc_id) if "npc_id" in n else ""
		if poi_ids.has(nid1):
			continue
		if not ctrl._npc_shows_on_radar(n):
			continue
		var world_pos2 = Vector2.ZERO
		if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
			world_pos2 = ctrl.map_field.cell_to_world(n.cell)
		else:
			world_pos2 = n.global_position
		out.append({
			"world": world_pos2,
			"hostile": bool(n.hostile) if "hostile" in n else false,
		})
	for rid2 in ctrl._remote_markers.keys():
		var rm2 = ctrl._remote_markers[rid2]
		if rm2 == null or not is_instance_valid(rm2) or not rm2.visible:
			continue
		out.append({
			"world": rm2.global_position,
			"hostile": false,
			"remote": true,
		})
	ctrl._radar_blips_cache = out
	ctrl._radar_blips_sig = sig
	ctrl._radar_blips_ready = true
	return out

static func get_radar_poi_markers(ctrl) -> Array:
	return RadarPoi.build_markers(ctrl._radar_poi_sample())

static func get_quest_nav_context(ctrl) -> Dictionary:
	var sample: Dictionary = ctrl._radar_poi_sample()
	var npcs: Array = sample.get("npcs", []) if typeof(sample.get("npcs", [])) == TYPE_ARRAY else []
	var gather: Array = sample.get("gather", []) if typeof(sample.get("gather", [])) == TYPE_ARRAY else []
	var fish: Array = sample.get("fish", []) if typeof(sample.get("fish", [])) == TYPE_ARRAY else []
	var srv = Net.server()
	# Attach yields from catalogs so gather/fish item matching works.
	if srv != null and "gather_catalog" in srv and srv.gather_catalog != null:
		var gcat = srv.gather_catalog
		for i in range(gather.size()):
			if typeof(gather[i]) != TYPE_DICTIONARY:
				continue
			var gid = str(gather[i].get("id", "")).strip_edges()
			if gid.is_empty() or not gcat.has_method("get_node"):
				continue
			var def: Dictionary = gcat.get_node(gid)
			if def.is_empty():
				continue
			if def.has("yields"):
				gather[i]["yields"] = def.get("yields", [])
			if str(gather[i].get("name", "")).strip_edges() == "" and def.has("name"):
				gather[i]["name"] = def.get("name")
	if srv != null and "fish_catalog" in srv and srv.fish_catalog != null:
		var fcat = srv.fish_catalog
		for j in range(fish.size()):
			if typeof(fish[j]) != TYPE_DICTIONARY:
				continue
			var fid = str(fish[j].get("id", "")).strip_edges()
			if fid.is_empty() or not fcat.has_method("get_spot"):
				continue
			var fdef: Dictionary = fcat.get_spot(fid)
			if fdef.is_empty():
				continue
			if fdef.has("yields"):
				fish[j]["yields"] = fdef.get("yields", [])
			if str(fish[j].get("name", "")).strip_edges() == "" and fdef.has("name"):
				fish[j]["name"] = fdef.get("name")
	var warps: Array = []
	if srv != null and "map_warps" in srv and typeof(srv.map_warps) == TYPE_ARRAY:
		warps = (srv.map_warps as Array).duplicate(true)
	return {"npcs": npcs, "gather": gather, "fish": fish, "warps": warps}

static func _radar_kind_code(ctrl, kind: String) -> int:
	match kind.strip_edges():
		RadarPoi.KIND_QUEST:
			return 10
		RadarPoi.KIND_INN:
			return 11
		RadarPoi.KIND_SMITH:
			return 12
		RadarPoi.KIND_GATHER:
			return 13
		RadarPoi.KIND_FISH:
			return 14
		RadarPoi.KIND_PIN:
			return 15
		RadarPoi.KIND_BOSS:
			return 16
		_:
			return 0

static func _radar_poi_sample(ctrl) -> Dictionary:
	var npcs_out: Array = []
	var gather_out: Array = []
	var fish_out: Array = []
	var srv = Net.server()
	var qj = null
	if srv != null and "quest_journal" in srv:
		qj = srv.quest_journal
	var gcat = null
	var fcat = null
	if srv != null and "gather_catalog" in srv:
		gcat = srv.gather_catalog
	if srv != null and "fish_catalog" in srv:
		fcat = srv.fish_catalog
	for n in ctrl._npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid = str(n.npc_id) if "npc_id" in n else ""
		if nid.is_empty():
			continue
		var cell: Vector2i = n.cell if "cell" in n else Vector2i.ZERO
		var row: Dictionary = {
			"id": nid,
			"name": str(n.npc_name) if "npc_name" in n else nid,
			"cell": {"x": cell.x, "y": cell.y},
		}
		var inn = bool(n.inn_rest) if "inn_rest" in n else false
		var smith = bool(n.blacksmith) if "blacksmith" in n else false
		if srv != null and "npc_meta" in srv and typeof(srv.npc_meta) == TYPE_DICTIONARY:
			var meta_v: Variant = srv.npc_meta.get(nid, {})
			if typeof(meta_v) == TYPE_DICTIONARY:
				var meta: Dictionary = meta_v
				if bool(meta.get("inn_rest", false)):
					inn = true
				if bool(meta.get("blacksmith", false)) or bool(meta.get("repair", false)):
					smith = true
		row["inn_rest"] = inn
		row["blacksmith"] = smith
		var quest_offer = false
		var quest_turn = false
		if qj != null:
			if qj.has_method("list_offers_for_npc"):
				var offers: Array = qj.list_offers_for_npc(nid)
				quest_offer = not offers.is_empty()
			if qj.has_method("can_turn_in_to"):
				var turns: Array = qj.can_turn_in_to(nid)
				quest_turn = not turns.is_empty()
		row["quest_offer"] = quest_offer
		row["quest_turn_in"] = quest_turn
		var is_gather = false
		var is_fish = false
		if gcat != null and gcat.has_method("has_node") and bool(gcat.has_node(nid)):
			is_gather = true
		if fcat != null and fcat.has_method("has_spot") and bool(fcat.has_spot(nid)):
			is_fish = true
		row["is_gather"] = is_gather
		row["is_fish"] = is_fish
		var is_boss = false
		if srv != null and "npc_meta" in srv and typeof(srv.npc_meta) == TYPE_DICTIONARY:
			var bm_v: Variant = srv.npc_meta.get(nid, {})
			if typeof(bm_v) == TYPE_DICTIONARY and bool(bm_v.get("world_boss", false)):
				is_boss = true
		if srv != null and "npc_spawn_templates" in srv and typeof(srv.npc_spawn_templates) == TYPE_DICTIONARY:
			var bt_v: Variant = srv.npc_spawn_templates.get(nid, {})
			if typeof(bt_v) == TYPE_DICTIONARY:
				var bt: Dictionary = bt_v
				if bool(bt.get("world_boss", false)) or bool(bt.get("is_boss", false)):
					is_boss = true
		if nid == "world_boss_king":
			is_boss = true
		row["world_boss"] = is_boss
		row["is_boss"] = is_boss
		# Depleted gather/fish: omit from NPC row; also push dedicated lists.
		var gather_dep = false
		var fish_dep = false
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			gather_dep = true
		if n.has_meta("fish_depleted") and bool(n.get_meta("fish_depleted")):
			fish_dep = true
		if srv != null and srv.has_method("is_gather_depleted") and is_gather:
			gather_dep = gather_dep or bool(srv.is_gather_depleted(nid))
		if srv != null and srv.has_method("is_fish_depleted") and is_fish:
			fish_dep = fish_dep or bool(srv.is_fish_depleted(nid))
		if is_gather:
			gather_out.append({
				"id": nid,
				"name": row["name"],
				"cell": row["cell"],
				"depleted": gather_dep,
			})
			# Avoid double-classifying as npc+gather; gather list owns the marker.
			row["is_gather"] = false
		elif is_fish:
			fish_out.append({
				"id": nid,
				"name": row["name"],
				"cell": row["cell"],
				"depleted": fish_dep,
			})
			row["is_fish"] = false
		npcs_out.append(row)
	var pins_out: Array = []
	if srv != null and srv.has_method("list_map_pins_for_map"):
		var mid = ""
		if "map_pack_id" in srv:
			mid = str(srv.map_pack_id)
		pins_out = srv.list_map_pins_for_map(mid)
	elif srv != null and "_map_pins" in srv:
		for pv in srv._map_pins:
			if typeof(pv) == TYPE_DICTIONARY:
				pins_out.append((pv as Dictionary).duplicate(true))
	return {"npcs": npcs_out, "gather": gather_out, "fish": fish_out, "pins": pins_out}

static func _npc_shows_on_radar(ctrl, n) -> bool:
	# Explicit radar: false force-hides; radar: true force-shows.
	if "radar_opt" in n and n.radar_opt != null:
		return bool(n.radar_opt)
	# Hostile always shows (red).
	if "hostile" in n and bool(n.hostile):
		return true
	# Object-like charset (!...) stays off radar (POI path covers gather/fish).
	var cs = str(n.charset) if "charset" in n else ""
	if cs.begins_with("!"):
		return false
	# Character sheets (non-! charset) show as friendly by default.
	return true

static func _find_npc_at(ctrl, cell: Vector2i):
	for n in ctrl._npcs:
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			continue
		if n.has_method("contains_cell") and n.contains_cell(cell):
			return n
	return null

static func _find_remote_at(ctrl, cell: Vector2i):
	## Pick remote marker on the same cell (Chebyshev 0). Visible markers only.
	for rid in ctrl._remote_markers.keys():
		var mk = ctrl._remote_markers[rid]
		if mk == null or not is_instance_valid(mk) or not mk.visible:
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var mc = Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			mc = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			mc = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		if mc == cell:
			return mk
	return null

static func _find_adjacent_npc(ctrl, from_cell: Vector2i, prefer_dir: int = 0):
	# Prefer the cell the player faces (8-way).
	if TileId.is_dir(prefer_dir):
		var faced = ctrl._find_npc_at(from_cell + TileId.dir_delta(prefer_dir))
		if faced != null:
			return faced
	for n in ctrl._npcs:
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			continue
		if n.has_method("is_adjacent_to") and n.is_adjacent_to(from_cell):
			return n
	return null

