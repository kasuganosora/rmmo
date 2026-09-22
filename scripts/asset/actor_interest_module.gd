extends RefCounted
## Domain module: actor interest rings (VIEW/AOI/PREFETCH/COLD), ref binding, LOW-job
## cancellation and ring-aware eviction protection/scoring. Cache/queue state lives on
## the AssetManager (ctrl); this module owns the ring policy.

var ctrl
func _init(c):
	ctrl = c

const ContentRef = preload("res://scripts/asset/content_ref.gd")

func bind_actor_refs(actor_id: String, refs: Array) -> void:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return
	var cleaned: Array[String] = []
	var seen: Dictionary = {}
	for r in refs:
		var s := str(r).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		cleaned.append(s)
	ctrl._actor_refs[actor_id] = cleaned

func clear_actor_refs(actor_id: String) -> void:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return
	ctrl._actor_refs.erase(actor_id)

func get_actor_refs(actor_id: String) -> Array:
	var v: Variant = ctrl._actor_refs.get(actor_id.strip_edges(), [])
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate()
	return []

func note_actor_ring(actor_id: String, ring: String) -> void:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return
	var r := ring.strip_edges().to_upper()
	if r not in [ctrl.RING_VIEW, ctrl.RING_AOI, ctrl.RING_PREFETCH, ctrl.RING_COLD]:
		r = ctrl.RING_AOI
	var prev := str(ctrl._actor_rings.get(actor_id, ""))
	if prev == r:
		return
	ctrl._actor_rings[actor_id] = r
	# VIEW / AOI: keep decoded assets hot (clear evictable mark)
	if r == ctrl.RING_VIEW or r == ctrl.RING_AOI:
		ctrl._clear_actor_evictable(actor_id)
	# Leave PREFETCH (or any ring) into COLD → cancel unstarted LOW jobs for this actor
	if r == ctrl.RING_COLD:
		ctrl.cancel_actor_low_jobs(actor_id)
		ctrl._mark_actor_evictable(actor_id)
	# Leave AOI → mark look/charset evictable (hysteresis); PREFETCH may still download
	elif prev == ctrl.RING_AOI and r == ctrl.RING_PREFETCH:
		ctrl._mark_actor_evictable(actor_id)
	elif prev == ctrl.RING_VIEW and r == ctrl.RING_PREFETCH:
		ctrl._mark_actor_evictable(actor_id)

func get_actor_ring(actor_id: String) -> String:
	return str(ctrl._actor_rings.get(actor_id.strip_edges(), ctrl.RING_COLD))

func set_interest(view_ids: Array, aoi_ids: Array, prefetch_ids: Array) -> void:
	var assigned: Dictionary = {}
	for raw in view_ids:
		var id := str(raw).strip_edges()
		if id.is_empty() or assigned.has(id):
			continue
		assigned[id] = ctrl.RING_VIEW
		ctrl.note_actor_ring(id, ctrl.RING_VIEW)
	for raw in aoi_ids:
		var id := str(raw).strip_edges()
		if id.is_empty() or assigned.has(id):
			continue
		assigned[id] = ctrl.RING_AOI
		ctrl.note_actor_ring(id, ctrl.RING_AOI)
	for raw in prefetch_ids:
		var id := str(raw).strip_edges()
		if id.is_empty() or assigned.has(id):
			continue
		assigned[id] = ctrl.RING_PREFETCH
		ctrl.note_actor_ring(id, ctrl.RING_PREFETCH)
	# Previous actors not listed become COLD
	var prev_ids: Array = ctrl._actor_rings.keys()
	for key in prev_ids:
		var id := str(key)
		if assigned.has(id):
			continue
		ctrl.note_actor_ring(id, ctrl.RING_COLD)

func cancel_actor_low_jobs(actor_id: String) -> void:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return
	var refs_v: Variant = ctrl._actor_refs.get(actor_id, [])
	if typeof(refs_v) != TYPE_ARRAY or (refs_v as Array).is_empty():
		return
	var drop: Dictionary = {}
	for r in refs_v:
		var ref := str(r)
		if ref.is_empty():
			continue
		if ctrl._ref_needed_by_non_cold(ref, actor_id):
			continue
		drop[ref] = true
	if drop.is_empty():
		return
	var kept: Array = []
	var removed := false
	for item in ctrl._queue:
		var ref := str(item.get("ref", ""))
		var pri := int(item.get("priority", 0))
		if pri <= ctrl.Priority.LOW and drop.has(ref):
			removed = true
			continue
		kept.append(item)
	if removed:
		ctrl._queue = kept
		ctrl.queue_changed.emit(ctrl._queue.size())

func _ref_needed_by_non_cold(ref: String, exclude_actor: String) -> bool:
	for aid_k in ctrl._actor_refs.keys():
		var aid := str(aid_k)
		if aid == exclude_actor:
			continue
		var ring := str(ctrl._actor_rings.get(aid, ctrl.RING_COLD))
		if ring == ctrl.RING_COLD:
			continue
		var refs_v: Variant = ctrl._actor_refs.get(aid, [])
		if typeof(refs_v) != TYPE_ARRAY:
			continue
		for r in refs_v:
			if str(r) == ref:
				return true
	return false

func _mark_actor_evictable(actor_id: String) -> void:
	var refs_v: Variant = ctrl._actor_refs.get(actor_id, [])
	if typeof(refs_v) != TYPE_ARRAY:
		return
	var now := Time.get_ticks_msec()
	for r in refs_v:
		var ref := str(r)
		if ref.is_empty():
			continue
		# Do not mark if still held by VIEW/AOI actor
		if ctrl._ref_held_by_rings(ref, [ctrl.RING_VIEW, ctrl.RING_AOI]):
			continue
		ctrl._evictable_refs[ref] = true
		if not ctrl._evictable_at_msec.has(ref):
			ctrl._evictable_at_msec[ref] = now

func _clear_actor_evictable(actor_id: String) -> void:
	var refs_v: Variant = ctrl._actor_refs.get(actor_id, [])
	if typeof(refs_v) != TYPE_ARRAY:
		return
	for r in refs_v:
		var ref := str(r)
		ctrl._evictable_refs.erase(ref)
		ctrl._evictable_at_msec.erase(ref)

func _ref_held_by_rings(ref: String, rings: Array) -> bool:
	for aid_k in ctrl._actor_refs.keys():
		var aid := str(aid_k)
		var ring := str(ctrl._actor_rings.get(aid, ctrl.RING_COLD))
		if ring not in rings:
			continue
		var refs_v: Variant = ctrl._actor_refs.get(aid, [])
		if typeof(refs_v) != TYPE_ARRAY:
			continue
		for r in refs_v:
			if str(r) == ref:
				return true
	return false

func _paths_for_ref(ref: String) -> Array[String]:
	var out: Array[String] = []
	var p: String = ctrl.path(ref) if ref.begins_with("content:") or ref.begins_with(ContentRef.SCHEME) else ref
	if p.is_empty():
		return out
	out.append(p)
	var alt := p.replace("\\", "/")
	if alt != p:
		out.append(alt)
	return out

func _is_path_view_protected(p: String) -> bool:
	for aid_k in ctrl._actor_rings.keys():
		var aid := str(aid_k)
		if str(ctrl._actor_rings.get(aid, "")) != ctrl.RING_VIEW:
			continue
		var refs_v: Variant = ctrl._actor_refs.get(aid, [])
		if typeof(refs_v) != TYPE_ARRAY:
			continue
		for r in refs_v:
			for cand in ctrl._paths_for_ref(str(r)):
				if cand == p or cand.replace("\\", "/") == p.replace("\\", "/"):
					return true
	return false

func _is_path_aoi_protected(p: String) -> bool:
	for aid_k in ctrl._actor_rings.keys():
		var aid := str(aid_k)
		if str(ctrl._actor_rings.get(aid, "")) != ctrl.RING_AOI:
			continue
		var refs_v: Variant = ctrl._actor_refs.get(aid, [])
		if typeof(refs_v) != TYPE_ARRAY:
			continue
		for r in refs_v:
			for cand in ctrl._paths_for_ref(str(r)):
				if cand == p or cand.replace("\\", "/") == p.replace("\\", "/"):
					return true
	return false

func _path_evict_score(p: String, hard: bool) -> int:
	## Lower = evict sooner. -1 = never (VIEW). Soft: skip AOI. Prefer marked-evictable / COLD.
	if ctrl._is_path_view_protected(p):
		return -1
	if not hard and ctrl._is_path_aoi_protected(p):
		return -1
	var score := 50  # default LRU candidate
	# Prefer paths tied to COLD / PREFETCH actors or marked evictable
	var tied_cold := false
	var tied_prefetch := false
	var marked := false
	var past_hyst := false
	var now := Time.get_ticks_msec()
	for aid_k in ctrl._actor_refs.keys():
		var aid := str(aid_k)
		var refs_v: Variant = ctrl._actor_refs.get(aid, [])
		if typeof(refs_v) != TYPE_ARRAY:
			continue
		var hit := false
		for r in refs_v:
			for cand in ctrl._paths_for_ref(str(r)):
				if cand == p or cand.replace("\\", "/") == p.replace("\\", "/"):
					hit = true
					var ref := str(r)
					if ctrl._evictable_refs.get(ref, false):
						marked = true
						var at := int(ctrl._evictable_at_msec.get(ref, 0))
						if at == 0 or (now - at) >= ctrl.evict_hysteresis_msec:
							past_hyst = true
					break
			if hit:
				break
		if not hit:
			continue
		var ring := str(ctrl._actor_rings.get(aid, ctrl.RING_COLD))
		if ring == ctrl.RING_COLD:
			tied_cold = true
		elif ring == ctrl.RING_PREFETCH:
			tied_prefetch = true
	if marked and past_hyst:
		score = 10
	elif tied_cold:
		score = 20
	elif marked:
		score = 30  # marked but still in hysteresis — soft pass skips
	elif tied_prefetch:
		score = 40
	if not hard and marked and not past_hyst and not tied_cold:
		return -1  # hysteresis hold under soft budget
	return score
