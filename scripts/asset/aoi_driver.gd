extends RefCounted
## Client AOI preload rings for actor assets (charset/look).
## Distance metric: Chebyshev cell distance (max(|dx|,|dy|)) from local player.
## Radii (cells): VIEW=14 HIGH, AOI=22 NORMAL, PREFETCH=30 LOW, else COLD.
## Map chunk streaming (P2d) is out of scope — actors only.
## See docs/asset_manager_design.md.

const RING_VIEW := "VIEW"
const RING_AOI := "AOI"
const RING_PREFETCH := "PREFETCH"
const RING_COLD := "COLD"

## Chebyshev radii in cells from local player.
var view_radius_cells: int = 14
var aoi_radius_cells: int = 22
var prefetch_radius_cells: int = 30
## Reclassify interval (also runs immediately when player cell changes).
var refresh_interval_sec: float = 0.25

var _accum: float = 0.0
var _last_player_cell: Vector2i = Vector2i(0x7fffffff, 0x7fffffff)
## actor_id -> last ring we applied (for upgrade enqueue)
var _prev_rings: Dictionary = {}


func configure(view_r: int = 14, aoi_r: int = 22, prefetch_r: int = 30, interval: float = 0.25) -> void:
	view_radius_cells = maxi(view_r, 1)
	aoi_radius_cells = maxi(aoi_r, view_radius_cells)
	prefetch_radius_cells = maxi(prefetch_r, aoi_radius_cells)
	refresh_interval_sec = maxf(interval, 0.05)


func reset() -> void:
	_accum = 0.0
	_last_player_cell = Vector2i(0x7fffffff, 0x7fffffff)
	_prev_rings.clear()


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func classify_distance(dist: int) -> String:
	if dist <= view_radius_cells:
		return RING_VIEW
	if dist <= aoi_radius_cells:
		return RING_AOI
	if dist <= prefetch_radius_cells:
		return RING_PREFETCH
	return RING_COLD


func ring_priority(ring: String) -> int:
	## Matches AssetManager.Priority: LOW=0 NORMAL=1 HIGH=2. -1 = no enqueue.
	match ring:
		RING_VIEW:
			return 2
		RING_AOI:
			return 1
		RING_PREFETCH:
			return 0
		_:
			return -1


func ring_rank(ring: String) -> int:
	match ring:
		RING_VIEW:
			return 3
		RING_AOI:
			return 2
		RING_PREFETCH:
			return 1
		_:
			return 0


## Call from World._process. Only processes NPCs already in `npcs` (never invents actors).
func tick(delta: float, player: Node, npcs: Array, am: Node, force: bool = false) -> void:
	if am == null or player == null:
		return
	var pcell: Vector2i = Vector2i.ZERO
	if "cell" in player:
		pcell = player.cell
	_accum += delta
	var cell_changed := pcell != _last_player_cell
	if not force and not cell_changed and _accum < refresh_interval_sec:
		return
	_accum = 0.0
	_last_player_cell = pcell
	refresh(player, npcs, am)


func refresh(player: Node, npcs: Array, am: Node) -> void:
	if am == null:
		return
	var pcell := Vector2i.ZERO
	if player != null and "cell" in player:
		pcell = player.cell

	var view_ids: Array = []
	var aoi_ids: Array = []
	var prefetch_ids: Array = []
	var upgrades: Array = []  # {id, ring, ref}
	var live: Dictionary = {}

	for n in npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid := ""
		if "npc_id" in n:
			nid = str(n.npc_id).strip_edges()
		if nid.is_empty():
			continue
		live[nid] = true
		var ncell := Vector2i.ZERO
		if "cell" in n:
			ncell = n.cell
		var dist := chebyshev(pcell, ncell)
		var ring := classify_distance(dist)

		var charset := ""
		if "charset" in n:
			charset = str(n.charset).strip_edges()
		var refs: Array = []
		if charset != "":
			refs.append("content://charset/%s" % charset)
		if am.has_method("bind_actor_refs"):
			am.bind_actor_refs(nid, refs)

		match ring:
			RING_VIEW:
				view_ids.append(nid)
			RING_AOI:
				aoi_ids.append(nid)
			RING_PREFETCH:
				prefetch_ids.append(nid)
			_:
				pass

		var prev := str(_prev_rings.get(nid, ""))
		var upgraded := ring_rank(ring) > ring_rank(prev)
		var enter_load := prev == "" and ring != RING_COLD
		var reenter := prev == RING_COLD and ring != RING_COLD
		if (upgraded or enter_load or reenter) and ring != RING_COLD and not refs.is_empty():
			upgrades.append({"id": nid, "ring": ring, "refs": refs})
		_prev_rings[nid] = ring

	# Drop tracking for despawned NPCs
	var stale: Array = []
	for k in _prev_rings.keys():
		if not live.has(str(k)):
			stale.append(str(k))
	for sid in stale:
		_prev_rings.erase(sid)
		if am.has_method("clear_actor_refs"):
			am.clear_actor_refs(sid)
		if am.has_method("note_actor_ring"):
			am.note_actor_ring(sid, RING_COLD)

	if am.has_method("set_interest"):
		am.set_interest(view_ids, aoi_ids, prefetch_ids)
	else:
		for id in view_ids:
			am.note_actor_ring(str(id), RING_VIEW)
		for id in aoi_ids:
			am.note_actor_ring(str(id), RING_AOI)
		for id in prefetch_ids:
			am.note_actor_ring(str(id), RING_PREFETCH)

	# Enqueue on ring upgrade / enter (skip if already local)
	if am.has_method("enqueue"):
		for u in upgrades:
			var ring := str(u.get("ring", ""))
			var pri := ring_priority(ring)
			if pri < 0:
				continue
			var refs: Array = u.get("refs", [])
			var need: Array = []
			for r in refs:
				var ref := str(r)
				if ref.is_empty():
					continue
				if am.has_method("has") and bool(am.has(ref)):
					continue
				need.append(ref)
			if not need.is_empty():
				am.enqueue(need, pri)
