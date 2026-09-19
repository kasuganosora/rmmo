extends RefCounted
## Domain ops: map CRUD (create/delete/rename/duplicate/resize/reparent).

var ctrl
func _init(c):
	ctrl = c

const MAP_MAX_SIDE := 16384

func create_map(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var mid = str(args.get("map_id", "")).strip_edges()
	if mid == "":
		mid = p.next_map_id()
	var nm = str(args.get("name", mid)).strip_edges()
	if nm == "":
		nm = mid
	var cw = maxi(int(args.get("w", 40)), 1)
	var ch = maxi(int(args.get("h", 30)), 1)
	if cw > MAP_MAX_SIDE or ch > MAP_MAX_SIDE:
		return ctrl.mcp._err("单张地图最大 %d×%d。更大的世界请拆成多张地图，用传送点连接。" % [MAP_MAX_SIDE, MAP_MAX_SIDE])
	var ok = bool(p.add_map(
		mid, nm,
		str(args.get("parent", "")),
		cw, ch,
		str(args.get("tileset", ""))
	))
	if not ok:
		return ctrl.mcp._err("create_map failed (id exists?)")
	ctrl._persist()
	ctrl._switch_map(mid)
	return ctrl.mcp._ok({"map_id": mid, "name": nm, "width": int(ctrl.doc().width), "height": int(ctrl.doc().height)})



func delete_map(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var mid = str(args.get("map_id", "")).strip_edges()
	if mid == "":
		return ctrl.mcp._err("map_id required")
	if p.map_tree.size() <= 1:
		return ctrl.mcp._err("cannot delete last map")
	if not bool(p.remove_map(mid)):
		return ctrl.mcp._err("delete failed")
	ctrl._persist()
	if ctrl.mcp._map_id() == mid:
		var nxt = str(p.start_map)
		if nxt == "" or nxt == mid:
			nxt = str(p.map_tree[0]["id"]) if not p.map_tree.is_empty() else ""
		if nxt != "":
			ctrl._switch_map(nxt)
	if ctrl.ed() and ctrl.ed().has_method("_refresh_tree"):
		ctrl.ed()._refresh_tree()
	return ctrl.mcp._ok({"deleted": mid, "map_id": ctrl.mcp._map_id()})



func rename_map(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var mid = str(args.get("map_id", ctrl.mcp._map_id())).strip_edges()
	var nm = str(args.get("name", "")).strip_edges()
	if mid == "" or nm == "":
		return ctrl.mcp._err("map_id and name required")
	p.rename_map(mid, nm)
	ctrl._persist()
	if ctrl.ed() and ctrl.ed().has_method("_refresh_tree"):
		ctrl.ed()._refresh_tree()
	return ctrl.mcp._ok({"map_id": mid, "name": nm})



func duplicate_map(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var src = str(args.get("map_id", ctrl.mcp._map_id())).strip_edges()
	var nid: String = p.duplicate_map(src)
	if nid == "":
		return ctrl.mcp._err("duplicate failed")
	ctrl._persist()
	ctrl._switch_map(nid)
	return ctrl.mcp._ok({"map_id": nid, "from": src})



func resize_map(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var w = maxi(int(args.get("w", d.width)), 1)
	var h = maxi(int(args.get("h", d.height)), 1)
	if w > MAP_MAX_SIDE or h > MAP_MAX_SIDE:
		return ctrl.mcp._err("单张地图最大 %d×%d。更大的世界请拆成多张地图，用传送点连接。" % [MAP_MAX_SIDE, MAP_MAX_SIDE])
	d.resize(w, h)
	if ctrl.pack():
		ctrl.pack().dirty = true
	ctrl._persist()
	if ctrl.ed() and ctrl.ed().has_method("_reload_field"):
		ctrl.ed()._reload_field()
	return ctrl.mcp._ok({"width": int(d.width), "height": int(d.height)})



func reparent_map(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var mid = str(args.get("map_id", "")).strip_edges()
	var parent = str(args.get("parent", ""))
	if not bool(p.set_parent(mid, parent)):
		return ctrl.mcp._err("reparent failed")
	if ctrl.ed() and ctrl.ed().has_method("_refresh_tree"):
		ctrl.ed()._refresh_tree()
	return ctrl.mcp._ok({"map_id": mid, "parent": parent})


