extends RefCounted
## 小地图桥接（接口层）：重建/刷新/跳转/书签。纯逻辑，通过 ctrl 读写 minimap / 相机 / 文档。
## 相机与滚动条相关调用转发到 EditorCanvas；_sync_minimap_view 同时被 EditorCanvas 调用，
## 故在组合根保留同名委托。

const EditorCanvas = preload("res://scripts/editor/interface/editor_canvas.gd")

static func rebuild_minimap(ctrl) -> void:
	if ctrl._minimap == null or ctrl.map_field == null or ctrl.doc == null:
		return
	if ctrl._palette != null and ctrl._palette.sheets.size() > 0 and ctrl.map_field.pack != null:
		ctrl.map_field.pack.sheets = ctrl._palette.sheets
		if ctrl._palette._flags.size() > 0:
			ctrl.map_field.pack.flags = ctrl._palette._flags
	ctrl._minimap.rebuild(ctrl.map_field, ctrl.doc)
	sync_minimap_view(ctrl)

static func schedule_minimap(ctrl, cells: Array = []) -> void:
	if ctrl._minimap == null:
		return
	if cells.size() > 0 and cells.size() <= 80 and ctrl._minimap.has_method("patch_cells"):
		ctrl._minimap.patch_cells(ctrl.map_field, cells)
		sync_minimap_view(ctrl)
		return
	if ctrl._minimap_timer:
		ctrl._minimap_timer.start()

static func sync_minimap_view(ctrl) -> void:
	if ctrl._minimap == null or ctrl._cam == null or ctrl._vp == null:
		return
	var z := maxf(ctrl._zoom, 0.05)
	var view := Vector2(float(ctrl._vp.size.x) / z, float(ctrl._vp.size.y) / z)
	ctrl._minimap.set_view_world(Rect2(ctrl._cam.position - view * 0.5, view))
	if ctrl.map_field != null and ctrl.map_field.has_method("current_chunk_rect") and ctrl._minimap.has_method("set_chunk_world"):
		var cr: Rect2i = ctrl.map_field.current_chunk_rect()
		var ts := float(maxi(int(ctrl.doc.tile_size) if ctrl.doc else 48, 1))
		ctrl._minimap.set_chunk_world(Rect2(Vector2(cr.position) * ts, Vector2(cr.size) * ts))

static func on_minimap_jump(ctrl, world: Vector2) -> void:
	if ctrl._cam == null:
		return
	ctrl._cam.position = world
	EditorCanvas.clamp_camera(ctrl)
	EditorCanvas.sync_scrollbars(ctrl)
	EditorCanvas.update_edit_observer(ctrl)

static func add_bookmark_here(ctrl) -> void:
	if ctrl.doc == null:
		return
	if not ("bookmarks" in ctrl.doc):
		ctrl.doc.bookmarks = []
	var name := "点%d" % (ctrl.doc.bookmarks.size() + 1)
	ctrl.doc.bookmarks.append({"name": name, "x": ctrl._cursor.x, "y": ctrl._cursor.y})
	ctrl.doc.dirty = true
	refresh_bookmarks(ctrl)
	ctrl._status.text = "书签 %s @ %d,%d" % [name, ctrl._cursor.x, ctrl._cursor.y]

static func refresh_bookmarks(ctrl) -> void:
	if ctrl._bm_opt == null:
		return
	ctrl._bm_opt.clear()
	ctrl._bm_opt.add_item("书签")
	if ctrl.doc == null or not ("bookmarks" in ctrl.doc):
		return
	for bm in ctrl.doc.bookmarks:
		if typeof(bm) == TYPE_DICTIONARY:
			ctrl._bm_opt.add_item("%s (%d,%d)" % [str(bm.get("name", "")), int(bm.get("x", 0)), int(bm.get("y", 0))])

static func on_bookmark_sel(ctrl, idx: int) -> void:
	if idx <= 0 or ctrl.doc == null or not ("bookmarks" in ctrl.doc):
		return
	var bm: Dictionary = ctrl.doc.bookmarks[idx - 1] if idx - 1 < ctrl.doc.bookmarks.size() else {}
	if bm.is_empty():
		return
	ctrl._cursor = Vector2i(int(bm.get("x", 0)), int(bm.get("y", 0)))
	if ctrl._cam and ctrl.doc:
		ctrl._cam.position = Vector2((float(ctrl._cursor.x) + 0.5) * float(ctrl.doc.tile_size), (float(ctrl._cursor.y) + 0.5) * float(ctrl.doc.tile_size))
		EditorCanvas.clamp_camera(ctrl)
		EditorCanvas.sync_scrollbars(ctrl)
