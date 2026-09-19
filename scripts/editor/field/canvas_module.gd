extends RefCounted
## Domain module: canvas viewport (input, hover, zoom, pan/scrollbars, mouse cell, far scroll).

var ctrl
func _init(c):
	ctrl = c

const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")
const EditorCanvas = preload("res://scripts/editor/interface/editor_canvas.gd")
const EditorAtmosphere = preload("res://scripts/editor/interface/editor_atmosphere.gd")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k = event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_S:
			ctrl._save()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Z:
			ctrl._undo_edit()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			ctrl._redo_edit()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_C:
			if ctrl._mode == 1 and ctrl._copy_entity():
				_mark_handled()
			else:
				ctrl._copy_tiles()
				_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_X:
			ctrl._cut_tiles()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_V:
			if ctrl._mode == 1 and ctrl._paste_entity():
				_mark_handled()
			else:
				ctrl._paste_tiles()
				_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_A:
			ctrl._select_all()
			_mark_handled()
		elif k.keycode == KEY_F5:
			ctrl._playtest(k.shift_pressed)
			_mark_handled()
		elif k.keycode == KEY_DELETE:
			if ctrl._mode == 1 and ctrl._inspector:
				ctrl._inspector.cell = ctrl._cursor
				ctrl._inspector._delete()
			elif ctrl.paint and ctrl.paint.tool == PaintTools.Tool.SELECT:
				ctrl._erase_selection()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_D:
			ctrl._dup_map(ctrl.current_map_id)
			_mark_handled()
		elif k.keycode == KEY_ESCAPE:
			if ctrl._poly_pts.size() > 0:
				ctrl._poly_pts.clear()
				ctrl._status.text = "已取消折线"
				_mark_handled()
			else:
				_mark_handled()
				ctrl._leave()
		elif k.keycode == KEY_F2:
			ctrl._open_rename(ctrl.current_map_id)
			_mark_handled()
		elif k.keycode == KEY_G:
			if ctrl.map_field:
				ctrl.map_field.show_grid = not ctrl.map_field.show_grid
			_mark_handled()
		elif k.keycode == KEY_1:
			ctrl._set_tool(PaintTools.Tool.PENCIL)
			_mark_handled()
		elif k.keycode == KEY_2:
			ctrl._set_tool(PaintTools.Tool.RECT)
			_mark_handled()
		elif k.keycode == KEY_3:
			ctrl._set_tool(PaintTools.Tool.FILL)
			_mark_handled()
		elif k.keycode == KEY_4:
			ctrl._set_tool(PaintTools.Tool.EYEDROP)
			_mark_handled()
		elif k.keycode == KEY_5:
			ctrl._set_tool(PaintTools.Tool.ERASE)
			_mark_handled()
		elif k.keycode == KEY_6:
			ctrl._set_tool(PaintTools.Tool.SELECT)
			_mark_handled()
		elif k.keycode == KEY_7:
			ctrl._set_tool(PaintTools.Tool.LINE)
			_mark_handled()
		elif k.keycode == KEY_8:
			ctrl._set_tool(PaintTools.Tool.POLYLINE)
			_mark_handled()
		elif k.keycode == KEY_9:
			ctrl._set_tool(PaintTools.Tool.ELLIPSE)
			_mark_handled()
		elif k.keycode == KEY_0:
			ctrl._set_tool(PaintTools.Tool.RING)
			_mark_handled()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			if ctrl.paint and ctrl.paint.tool == PaintTools.Tool.POLYLINE:
				ctrl._commit_polyline(false)
				_mark_handled()
		elif k.keycode == KEY_BRACKETLEFT:
			ctrl._cycle_layer(-1)
			_mark_handled()
		elif k.keycode == KEY_BRACKETRIGHT:
			ctrl._cycle_layer(1)
			_mark_handled()
		elif k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD:
			_set_zoom(ctrl._zoom * 1.25)
			_mark_handled()
		elif k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT:
			_set_zoom(ctrl._zoom / 1.25)
			_mark_handled()
		elif not k.ctrl_pressed and ctrl._cam != null:
			var step = float(ctrl.doc.tile_size if ctrl.doc else 48) * 4.0 / maxf(ctrl._zoom, 0.05)
			var delta = Vector2.ZERO
			if k.keycode == KEY_A or k.keycode == KEY_LEFT:
				delta.x = -step
			elif k.keycode == KEY_D or k.keycode == KEY_RIGHT:
				delta.x = step
			elif k.keycode == KEY_W or k.keycode == KEY_UP:
				delta.y = -step
			elif k.keycode == KEY_S or k.keycode == KEY_DOWN:
				delta.y = step
			if delta != Vector2.ZERO:
				ctrl._cam.position += delta
				_clamp_camera()
				_sync_scrollbars()
				ctrl._update_edit_observer()
				_mark_handled()



func _mark_handled() -> void:
	var vp = ctrl.get_viewport()
	if vp:
		vp.set_input_as_handled()



func _set_far_scroll(x: float, y: float) -> void:
	EditorAtmosphere.set_far_scroll(ctrl, x, y)

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k = event as InputEventKey
		if k.keycode == KEY_SPACE:
			ctrl._space_down = k.pressed
		if k.pressed and not k.echo and ctrl.paint and ctrl.paint.tool == PaintTools.Tool.POLYLINE:
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				ctrl._commit_polyline(false)
				_mark_handled()
				return
			if k.keycode == KEY_ESCAPE:
				ctrl._poly_pts.clear()
				ctrl._status.text = "已取消折线"
				_mark_handled()
				return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			if mb.ctrl_pressed:
				var factor = 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.25
				_zoom_at(mb.position, ctrl._zoom * factor)
			elif mb.shift_pressed:
				_canvas_wheel_scroll(true, mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
			else:
				_canvas_wheel_scroll(false, mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
			_mark_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			if mb.pressed:
				_canvas_wheel_scroll(true, mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT)
				_mark_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (ctrl._space_down and mb.button_index == MOUSE_BUTTON_LEFT):
			ctrl._panning = mb.pressed
			return
		if not mb.pressed:
			if ctrl.paint.rect_start.x >= 0 and ctrl.doc and not ctrl._placing_start:
				var cell = _mouse_cell(mb.position)
				if ctrl.paint.tool == PaintTools.Tool.SELECT and ctrl._mode == 0:
					if ctrl.map_field:
						ctrl.map_field.edit_rect_b = cell
					ctrl._status.text = "选区 %d,%d → %d,%d" % [ctrl.paint.rect_start.x, ctrl.paint.rect_start.y, cell.x, cell.y]
				elif ctrl.paint.tool == PaintTools.Tool.RECT:
					if ctrl._mode == 2:
						ctrl._passage_rect(ctrl.paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					elif ctrl._mode == 0 and ctrl._is_spec_paint():
						ctrl._spec_rect(ctrl.paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					elif ctrl._mode == 0:
						ctrl.paint.exact_autotile = mb.shift_pressed
						var dirty: Array[Vector2i] = ctrl.paint.apply_rect(ctrl.doc, ctrl.paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
						ctrl.paint.exact_autotile = false
						ctrl._refresh_dirty(dirty)
					ctrl.paint.rect_start = Vector2i(-1, -1)
					if ctrl.map_field:
						ctrl.map_field.edit_rect_a = Vector2i(-1, -1)
						ctrl.map_field.edit_rect_b = Vector2i(-1, -1)
				elif ctrl._mode == 0 and ctrl.paint.tool in [PaintTools.Tool.LINE, PaintTools.Tool.ELLIPSE, PaintTools.Tool.RING]:
					ctrl._commit_shape(ctrl.paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					ctrl.paint.rect_start = Vector2i(-1, -1)
					if ctrl.map_field:
						ctrl.map_field.edit_rect_a = Vector2i(-1, -1)
						ctrl.map_field.edit_rect_b = Vector2i(-1, -1)
			return
		var cell2 = _mouse_cell(mb.position)
		ctrl._cursor = cell2
		_set_hover(cell2)
		if ctrl._placing_start:
			ctrl._set_start_cell(cell2)
			return
		if ctrl._mode == 1:
			ctrl._cursor = cell2
			if ctrl.map_field:
				ctrl.map_field.edit_cursor_cell = cell2
			ctrl._open_entity_win()
			ctrl._status.text = "实体格 %d,%d" % [cell2.x, cell2.y]
			return
		if ctrl.paint.tool == PaintTools.Tool.POLYLINE and ctrl._mode == 0:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				ctrl._commit_polyline(false)
				return
			ctrl._poly_pts.append(cell2)
			ctrl._status.text = "折线 %d 点 · 右键/Enter 完成 / Esc 取消" % ctrl._poly_pts.size()
			return
		if ctrl.paint.tool == PaintTools.Tool.RECT or ctrl.paint.tool == PaintTools.Tool.SELECT or ctrl.paint.tool == PaintTools.Tool.LINE or ctrl.paint.tool == PaintTools.Tool.ELLIPSE or ctrl.paint.tool == PaintTools.Tool.RING:
			ctrl.paint.rect_start = cell2
			if ctrl.map_field:
				ctrl.map_field.edit_rect_a = cell2
				ctrl.map_field.edit_rect_b = cell2
			return
		if ctrl.paint.has_method("begin_stroke"):
			ctrl.paint.begin_stroke()
		if ctrl._mode == 2:
			if ctrl.paint.tool == PaintTools.Tool.FILL:
				ctrl._passage_fill(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			else:
				ctrl._paint_passage(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			return
		if ctrl._is_spec_paint():
			if ctrl.paint.tool == PaintTools.Tool.FILL:
				ctrl._spec_fill(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			elif ctrl.paint.tool == PaintTools.Tool.EYEDROP:
				ctrl._spec_eyedrop(cell2)
			else:
				ctrl._paint_spec(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			return
		ctrl.paint.exact_autotile = mb.shift_pressed
		var erase = mb.button_index == MOUSE_BUTTON_RIGHT
		var dirty2: Array[Vector2i] = ctrl.paint.apply_cell(ctrl.doc, cell2, erase)
		ctrl.paint.exact_autotile = false
		if ctrl.paint.tool == PaintTools.Tool.EYEDROP and ctrl._palette:
			ctrl._palette.select_tile(ctrl.paint.tile_id)
			ctrl.paint.set_stamp(1, 1, PackedInt32Array())
			if ctrl.map_field:
				ctrl.map_field.edit_stamp_size = Vector2i(1, 1)
		ctrl._status.text = "画 %d @ %d,%d%s" % [ctrl.paint.tile_id, cell2.x, cell2.y, " · Shift精确" if mb.shift_pressed else ""]
		ctrl._refresh_dirty(dirty2)
	elif event is InputEventPanGesture:
		var pg = event as InputEventPanGesture
		ctrl._canvas_pan_pixels(pg.delta)
		_mark_handled()
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		var hover = _mouse_cell(mm.position)
		_set_hover(hover)
		if ctrl._panning and ctrl._cam:
			var z = maxf(ctrl._zoom, 0.05)
			ctrl._cam.position -= mm.relative / z
			_clamp_camera()
			_sync_scrollbars()
			ctrl._update_edit_observer()
			return
		if ctrl._placing_start:
			return
		if (ctrl.paint.tool == PaintTools.Tool.RECT or ctrl.paint.tool == PaintTools.Tool.SELECT or ctrl.paint.tool == PaintTools.Tool.LINE or ctrl.paint.tool == PaintTools.Tool.ELLIPSE or ctrl.paint.tool == PaintTools.Tool.RING) and ctrl.paint.rect_start.x >= 0 and ctrl.map_field:
			ctrl.map_field.edit_rect_b = hover
			return
		if ctrl._mode == 0 and ctrl._is_spec_paint() and ctrl.paint.tool == PaintTools.Tool.PENCIL:
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				ctrl._paint_spec(hover, false)
			elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
				ctrl._paint_spec(hover, true)
			return
		if ctrl._mode == 2:
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and ctrl.paint.tool == PaintTools.Tool.PENCIL:
				ctrl._paint_passage(hover, false)
			elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and ctrl.paint.tool == PaintTools.Tool.PENCIL:
				ctrl._paint_passage(hover, true)
			return
		if ctrl._mode != 0:
			return
		ctrl.paint.exact_autotile = mm.shift_pressed
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and ctrl.paint.tool == PaintTools.Tool.PENCIL:
			var dirty3: Array[Vector2i] = ctrl.paint.apply_cell(ctrl.doc, hover, false)
			ctrl._refresh_dirty(dirty3)
		elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and ctrl.paint.tool == PaintTools.Tool.PENCIL:
			var dirty4: Array[Vector2i] = ctrl.paint.apply_cell(ctrl.doc, hover, true)
			ctrl._refresh_dirty(dirty4)
		ctrl.paint.exact_autotile = false



func _mouse_cell(pos: Vector2) -> Vector2i:
	return EditorCanvas.mouse_cell(ctrl, pos)

func _set_hover(cell: Vector2i) -> void:
	if ctrl.map_field:
		ctrl.map_field.edit_hover_cell = cell
		ctrl.map_field.edit_cursor_cell = ctrl._cursor
	if ctrl.doc == null or cell.x < 0:
		return
	var z: int = int(ctrl.paint.layer_z) if ctrl.paint else 0
	var tid = int(ctrl.doc.tile(cell.x, cell.y, z)) if z >= 0 else int(ctrl.doc.ext_tile(ctrl.paint.ext_layer, cell.x, cell.y))
	var mark = ""
	if ctrl.map_field and ctrl.map_field.has_method("edit_cell_passable"):
		match int(ctrl.map_field.edit_cell_passable(cell.x, cell.y)):
			0:
				mark = "○"
			1:
				mark = "×"
			2:
				mark = "强制○"
			3:
				mark = "强制×"
	ctrl._status.text = "%d,%d  图块 %d  通行%s" % [cell.x, cell.y, tid, (" " + mark) if mark != "" else ""]



func _set_zoom(z: float) -> void:
	EditorCanvas.set_zoom(ctrl, z)

func _zoom_at(local_pos: Vector2, z: float) -> void:
	EditorCanvas.zoom_at(ctrl, local_pos, z)

func _zoom_fit() -> void:
	EditorCanvas.zoom_fit(ctrl)

func _clamp_camera() -> void:
	EditorCanvas.clamp_camera(ctrl)

func _sync_scrollbars() -> void:
	EditorCanvas.sync_scrollbars(ctrl)

func _canvas_wheel_scroll(horizontal: bool, toward_positive: bool) -> void:
	EditorCanvas.canvas_wheel_scroll(ctrl, horizontal, toward_positive)
