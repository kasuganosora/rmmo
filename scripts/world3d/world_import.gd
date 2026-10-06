extends RefCounted
## Read-only tile passage becomes symmetric ground. One-way edges are counted, not stored.

static func loss_count(opens_east: bool, neighbor_opens_west: bool) -> int:
	return 1 if opens_east != neighbor_opens_west else 0


static func import_row(walkable: Array) -> Dictionary:
	var boxes := []
	var lost := 0
	for i in walkable.size():
		if not bool(walkable[i]):
			continue
		boxes.append({"x": float(i), "z": 0.0, "surface_id": "ground"})
		if i + 1 < walkable.size():
			var east := true
			var back := bool(walkable[i + 1])
			lost += loss_count(east, back)
	return {"boxes": boxes, "one_way_lost": lost}
