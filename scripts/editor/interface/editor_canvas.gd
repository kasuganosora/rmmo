extends RefCounted
## 编辑器画布服务（接口层）：相机/缩放/平移/滚动条/坐标换算。
## 纯逻辑，不持有节点；通过 ctrl 读写相机/视口/滚动条等状态，组内函数互相直接调用。

static func sync_vp_size(ctrl) -> void:
	if ctrl._vpc == null or ctrl._vp == null:
		return
	var s := Vector2i(maxi(1, int(ctrl._vpc.size.x)), maxi(1, int(ctrl._vpc.size.y)))
	if ctrl._vp.size != s:
		ctrl._vp.size = s
	sync_scrollbars(ctrl)
	update_edit_observer(ctrl)

static func mouse_cell(ctrl, pos: Vector2) -> Vector2i:
	if ctrl.map_field == null or ctrl._vp == null:
		return Vector2i.ZERO
	var vp_pos := pos
	if ctrl._vpc != null and ctrl._vpc.size.x > 0.5 and ctrl._vpc.size.y > 0.5:
		vp_pos = Vector2(
			pos.x * float(ctrl._vp.size.x) / ctrl._vpc.size.x,
			pos.y * float(ctrl._vp.size.y) / ctrl._vpc.size.y
		)
	var xform: Transform2D = ctrl._vp.get_canvas_transform()
	var world: Vector2 = xform.affine_inverse() * vp_pos
	return ctrl.map_field.world_to_cell(world)

static func fit_layout(ctrl) -> void:
	var win := ctrl.get_tree().root as Window
	if win:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.size = ctrl.get_viewport_rect().size
	sync_vp_size(ctrl)
	sync_scrollbars(ctrl)

static func set_zoom(ctrl, z: float) -> void:
	ctrl._zoom = clampf(z, 0.25, 4.0)
	if ctrl._cam:
		ctrl._cam.zoom = Vector2(ctrl._zoom, ctrl._zoom)
	if ctrl._zoom_lbl:
		ctrl._zoom_lbl.text = "%d%%" % int(round(ctrl._zoom * 100.0))
	clamp_camera(ctrl)
	sync_scrollbars(ctrl)
	update_edit_observer(ctrl)

static func zoom_at(ctrl, local_pos: Vector2, z: float) -> void:
	var before := mouse_world(ctrl, local_pos)
	set_zoom(ctrl, z)
	var after := mouse_world(ctrl, local_pos)
	if ctrl._cam:
		ctrl._cam.position += before - after
		clamp_camera(ctrl)
		sync_scrollbars(ctrl)

static func zoom_fit(ctrl) -> void:
	if ctrl.doc == null or ctrl._vp == null:
		return
	var mw := float(ctrl.doc.width * ctrl.doc.tile_size)
	var mh := float(ctrl.doc.height * ctrl.doc.tile_size)
	if mw <= 1.0 or mh <= 1.0:
		return
	var zx := float(ctrl._vp.size.x) / mw
	var zy := float(ctrl._vp.size.y) / mh
	set_zoom(ctrl, minf(zx, zy))
	ctrl._cam.position = Vector2(mw * 0.5, mh * 0.5)
	sync_scrollbars(ctrl)

static func mouse_world(ctrl, pos: Vector2) -> Vector2:
	if ctrl._vp == null:
		return Vector2.ZERO
	var vp_pos := pos
	if ctrl._vpc != null and ctrl._vpc.size.x > 0.5 and ctrl._vpc.size.y > 0.5:
		vp_pos = Vector2(pos.x * float(ctrl._vp.size.x) / ctrl._vpc.size.x, pos.y * float(ctrl._vp.size.y) / ctrl._vpc.size.y)
	return ctrl._vp.get_canvas_transform().affine_inverse() * vp_pos

static func clamp_camera(ctrl) -> void:
	if ctrl._cam == null or ctrl._vp == null or ctrl.doc == null:
		return
	var z := maxf(ctrl._zoom, 0.05)
	var view_w := float(ctrl._vp.size.x) / z
	var view_h := float(ctrl._vp.size.y) / z
	var map_w := float(ctrl.doc.width * ctrl.doc.tile_size)
	var map_h := float(ctrl.doc.height * ctrl.doc.tile_size)
	var min_x := view_w * 0.5
	var max_x := maxf(min_x, map_w - view_w * 0.5)
	var min_y := view_h * 0.5
	var max_y := maxf(min_y, map_h - view_h * 0.5)
	ctrl._cam.position.x = clampf(ctrl._cam.position.x, min_x, max_x)
	ctrl._cam.position.y = clampf(ctrl._cam.position.y, min_y, max_y)

static func sync_scrollbars(ctrl) -> void:
	if ctrl._syncing_scroll or ctrl._cam == null or ctrl._vp == null or ctrl.doc == null or ctrl._hscroll == null:
		return
	ctrl._syncing_scroll = true
	var z := maxf(ctrl._zoom, 0.05)
	var view_w := maxf(float(ctrl._vp.size.x) / z, 1.0)
	var view_h := maxf(float(ctrl._vp.size.y) / z, 1.0)
	var map_w := float(maxi(ctrl.doc.width, 1) * ctrl.doc.tile_size)
	var map_h := float(maxi(ctrl.doc.height, 1) * ctrl.doc.tile_size)
	ctrl._hscroll.min_value = 0
	ctrl._hscroll.max_value = maxf(map_w, view_w)
	ctrl._hscroll.page = view_w
	ctrl._vscroll.min_value = 0
	ctrl._vscroll.max_value = maxf(map_h, view_h)
	ctrl._vscroll.page = view_h
	ctrl._hscroll.value = ctrl._cam.position.x - view_w * 0.5
	ctrl._vscroll.value = ctrl._cam.position.y - view_h * 0.5
	ctrl._syncing_scroll = false
	ctrl._sync_minimap_view()

static func canvas_wheel_scroll(ctrl, horizontal: bool, toward_positive: bool) -> void:
	var bar: ScrollBar = ctrl._hscroll if horizontal else ctrl._vscroll
	if bar == null:
		return
	var delta := bar.page * 0.12
	bar.value += delta if toward_positive else -delta

static func canvas_pan_pixels(ctrl, delta: Vector2) -> void:
	if ctrl._hscroll and absf(delta.x) > 0.01:
		ctrl._hscroll.value += delta.x
	if ctrl._vscroll and absf(delta.y) > 0.01:
		ctrl._vscroll.value += delta.y

static func on_hscroll(ctrl, v: float) -> void:
	if ctrl._syncing_scroll or ctrl._cam == null or ctrl._vp == null:
		return
	var z := maxf(ctrl._zoom, 0.05)
	ctrl._cam.position.x = v + float(ctrl._vp.size.x) / z * 0.5
	update_edit_observer(ctrl)

static func on_vscroll(ctrl, v: float) -> void:
	if ctrl._syncing_scroll or ctrl._cam == null or ctrl._vp == null:
		return
	var z := maxf(ctrl._zoom, 0.05)
	ctrl._cam.position.y = v + float(ctrl._vp.size.y) / z * 0.5
	update_edit_observer(ctrl)

static func map_status_line(ctrl) -> String:
	if ctrl.doc == null or ctrl.pack == null:
		return ""
	var chunk_s := ""
	if ctrl.map_field != null and ctrl.map_field.has_method("current_chunk"):
		var ch: Vector2i = ctrl.map_field.current_chunk()
		chunk_s = " · chunk %d,%d" % [ch.x, ch.y]
	return "%s · %dx%d%s · %s" % [ctrl.doc.display_name, ctrl.doc.width, ctrl.doc.height, chunk_s, ctrl.pack.root]

static func update_edit_observer(ctrl) -> void:
	if ctrl.map_field == null or ctrl._cam == null:
		return
	ctrl.map_field.set_edit_camera_cell(ctrl.map_field.world_to_cell(ctrl._cam.position))
	ctrl._sync_minimap_view()
	if ctrl._status and ctrl.doc and ctrl.pack:
		ctrl._status.text = map_status_line(ctrl)
