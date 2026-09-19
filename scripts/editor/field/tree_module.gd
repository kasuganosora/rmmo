extends RefCounted
## Domain module: map/layer trees (refresh, fill, selection, mouse).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")

func _exit_tree() -> void:
	if ctrl._mcp != null and ctrl._mcp.has_method("stop"):
		ctrl._mcp.stop()
	ctrl._restore_window_scale()



func _refresh_tree() -> void:
	ctrl._tree.clear()
	var root_item = ctrl._tree.create_item()
	root_item.set_text(0, ctrl.pack.pack_name)
	root_item.set_selectable(0, false)
	var by_parent = {}
	for item in ctrl.pack.map_tree:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var p = str(item.get("parent", ""))
		if not by_parent.has(p):
			by_parent[p] = []
		by_parent[p].append(item)
	_fill_tree(root_item, "", by_parent)



func _fill_tree(parent_item: TreeItem, parent_id: String, by_parent: Dictionary) -> void:
	var kids: Array = by_parent.get(parent_id, [])
	for item in kids:
		var it = ctrl._tree.create_item(parent_item)
		var mid = str(item.get("id", ""))
		var mark = " ★" if ctrl.pack != null and mid == ctrl.pack.start_map else ""
		it.set_text(0, "%s (%s)%s" % [str(item.get("name", mid)), mid, mark])
		it.set_meta("map_id", mid)
		if mid == ctrl.current_map_id:
			it.select(0)
		_fill_tree(it, mid, by_parent)



func _on_tree_sel() -> void:
	var it = ctrl._tree.get_selected()
	if it == null or not it.has_meta("map_id"):
		return
	var mid = str(it.get_meta("map_id"))
	if mid != ctrl.current_map_id:
		ctrl._select_map(mid)



func _on_tree_mouse(pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var it = ctrl._tree.get_item_at_position(pos)
	if it == null or not it.has_meta("map_id"):
		return
	var mid = str(it.get_meta("map_id"))
	ctrl._ctx_map_id = mid
	if mid != ctrl.current_map_id:
		ctrl._select_map(mid)
	var last: bool = ctrl.pack != null and ctrl.pack.maps.size() <= 1
	ctrl._map_ctx.set_item_disabled(ctrl._map_ctx.get_item_index(ctrl.CTX_DEL), last)
	ctrl._map_ctx.position = Vector2i(ctrl._tree.get_global_mouse_position())
	ctrl._map_ctx.popup()



func _fill_layer_tree() -> void:
	if ctrl._layer_tree == null:
		return
	ctrl._layer_tree.clear()
	var root = ctrl._layer_tree.create_item()
	var groups: Array = [
		{"label": "MV 图层", "rows": [
			{"z": 0, "ext": "", "spec": "", "name": "地面 z0（先铺草地）"},
			{"z": 1, "ext": "", "spec": "", "name": "叠层 z1（路/沙盖在草上）"},
			{"z": 2, "ext": "", "spec": "", "name": "物件 z2"},
			{"z": 3, "ext": "", "spec": "", "name": "上层 z3"},
			{"z": 4, "ext": "", "spec": "shadow", "name": "阴影 z4"},
			{"z": 5, "ext": "", "spec": "region", "name": "区域 z5"},
		]},
		{"label": "扩展绘制", "rows": []},
		{"label": "逻辑", "rows": []},
	]
	for id in MapExt.VISUAL_EXT:
		(groups[1]["rows"] as Array).append({"z": -1, "ext": id, "spec": id, "name": MapExt.layer_label(id)})
	for id in MapExt.SPEC_EXT:
		(groups[2]["rows"] as Array).append({"z": -1, "ext": id, "spec": id, "name": MapExt.layer_label(id)})
	var first: TreeItem = null
	for g in groups:
		var head = ctrl._layer_tree.create_item(root)
		head.set_text(1, str(g["label"]))
		head.set_selectable(0, false)
		head.set_selectable(1, false)
		head.set_custom_color(1, Color(0.65, 0.68, 0.72, 1))
		for row in g["rows"]:
			var it = ctrl._layer_tree.create_item(head)
			it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			it.set_checked(0, true)
			it.set_editable(0, true)
			it.set_text(1, str(row["name"]))
			it.set_metadata(0, row)
			if first == null:
				first = it
	if first:
		first.select(1)




func _on_layer_tree() -> void:
	var it = ctrl._layer_tree.get_selected() if ctrl._layer_tree else null
	if it == null:
		return
	var meta: Variant = it.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var z = int(meta.get("z", 0))
	var ext = str(meta.get("ext", ""))
	if z >= 0:
		ctrl.paint.layer_z = z
		ctrl.paint.ext_layer = ""
	else:
		ctrl.paint.layer_z = -1
		ctrl.paint.ext_layer = ext
	ctrl._sync_spec_panel(str(meta.get("spec", "")), str(meta.get("name", "")))
	var vis: String = "显示" if it.is_checked(0) else "隐藏"
	if ctrl._status:
		ctrl._status.text = "绘制 %s（%s）" % [str(meta.get("name", "")), vis]


