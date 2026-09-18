extends VBoxContainer
## MV-style A/B/C/D/E tile picker. Click a cell to choose a tile id.

const TileId = preload("res://scripts/map/tile_id.gd")
const TileBlit = preload("res://scripts/map/tile_blit.gd")
const Rtp = preload("res://scripts/editor/infrastructure/rtp.gd")

signal tile_selected(tile_id: int)
signal tileset_changed(tileset_id: String)
signal flags_changed(tileset_id: String, flags: PackedInt32Array)
signal stamp_changed(width: int, height: int, tiles: PackedInt32Array)

var tileset_id: String = "outside"
var tileset: Dictionary = {}
var sheets: Array = []
var tab: String = "A"
var selected_id: int = 2816
var tile_px: int = 48

var _ts_opt: OptionButton
var _tab_btns: Dictionary = {}
var _info: Label
var _scroll: ScrollContainer
var _host: Control
var _tex: TextureRect
var _hi: ReferenceRect
var _catalog: Dictionary = {}
var _flags: PackedInt32Array = PackedInt32Array()
var _view_mode: String = "" ## "A" composed atlas, else raw sheet B/C/D/E
var show_passage: bool = false
var pass_brush: int = TileId.PASS_O
var stamp_w: int = 1
var stamp_h: int = 1
var stamp_tiles: PackedInt32Array = PackedInt32Array()
var _drag_a: Vector2i = Vector2i(-1, -1)
var _drag_b: Vector2i = Vector2i(-1, -1)
var _dragging: bool = false
var _pass_layer: Control
var _btn_o: Button
var _btn_x: Button
var _btn_star: Button
var _dir_btns: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var ts_lbl := Label.new()
	ts_lbl.text = "图块套"
	add_child(ts_lbl)
	_ts_opt = OptionButton.new()
	_ts_opt.item_selected.connect(_on_ts)
	add_child(_ts_opt)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	add_child(tabs)
	for t in ["A", "B", "C", "D", "E"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tab.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b
	_info = Label.new()
	_info.text = "图块 2816"
	add_child(_info)
	var pass_row := HBoxContainer.new()
	pass_row.add_theme_constant_override("separation", 4)
	add_child(pass_row)
	var pl := Label.new()
	pl.text = "通行"
	pass_row.add_child(pl)
	_btn_o = _pass_btn(pass_row, "○", func(): _set_selected_kind(TileId.PASS_O))
	_btn_x = _pass_btn(pass_row, "×", func(): _set_selected_kind(TileId.PASS_X))
	_btn_star = _pass_btn(pass_row, "★", func(): _set_selected_kind(TileId.PASS_STAR))
	pass_row.add_child(VSeparator.new())
	_dir_btns[TileId.FLAG_UP] = _pass_btn(pass_row, "↑", func(): _toggle_dir(TileId.FLAG_UP))
	_dir_btns[TileId.FLAG_DOWN] = _pass_btn(pass_row, "↓", func(): _toggle_dir(TileId.FLAG_DOWN))
	_dir_btns[TileId.FLAG_LEFT] = _pass_btn(pass_row, "←", func(): _toggle_dir(TileId.FLAG_LEFT))
	_dir_btns[TileId.FLAG_RIGHT] = _pass_btn(pass_row, "→", func(): _toggle_dir(TileId.FLAG_RIGHT))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	add_child(_scroll)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.gui_input.connect(_on_view_input)
	_scroll.add_child(_host)
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP
	_host.add_child(_tex)
	_hi = ReferenceRect.new()
	_hi.editor_only = false
	_hi.border_color = Color(1.0, 0.85, 0.2, 1)
	_hi.border_width = 2
	_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hi.size = Vector2(tile_px, tile_px)
	_host.add_child(_hi)
	_pass_layer = preload("res://scripts/editor/passage_marks.gd").new()
	_pass_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_layer.visible = false
	_host.add_child(_pass_layer)
	_sync_tab_buttons()


func _pass_btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func set_show_passage(on: bool) -> void:
	show_passage = on
	_rebuild_passage_marks()
	_sync_pass_buttons()


func select_slot(slot: int) -> void:
	var t := TileId.slot_tab(slot)
	if t != tab:
		_on_tab(t)
	else:
		_rebuild_view()
	if _scroll:
		var row := 0
		match slot:
			1:
				row = 2
			2:
				row = 6
			3:
				row = 10
			4:
				row = 16
		_scroll.scroll_vertical = row * tile_px


func set_catalog(tilesets: Dictionary, current_id: String = "") -> void:
	_catalog = tilesets
	if _ts_opt == null:
		return
	_ts_opt.clear()
	var keys: Array = tilesets.keys()
	keys.sort()
	var pick := current_id if current_id != "" and tilesets.has(current_id) else ""
	if pick == "" and tilesets.has(Rtp.default_tileset_id()):
		pick = Rtp.default_tileset_id()
	if pick == "" and not keys.is_empty():
		pick = str(keys[0])
	var i := 0
	for k in keys:
		var sid := str(k)
		var ts: Dictionary = tilesets[k] if typeof(tilesets[k]) == TYPE_DICTIONARY else {}
		var label := Rtp.display_name(sid)
		var raw_name := str(ts.get("name", ""))
		if raw_name != "" and raw_name != label:
			label = "%s · %s" % [label, raw_name]
		_ts_opt.add_item(label, i)
		_ts_opt.set_item_metadata(i, sid)
		if sid == pick:
			_ts_opt.select(i)
		i += 1
	if pick != "":
		_apply_tileset(pick, false)


func select_tile(id: int) -> void:
	selected_id = id
	_clear_stamp()
	stamp_tiles = PackedInt32Array([id])
	var cell := _cell_for_id(id)
	if cell.x >= 0:
		_drag_a = cell
		_drag_b = cell
	var next_tab := _tab_for_id(id)
	if next_tab != tab:
		tab = next_tab
		_sync_tab_buttons()
		_rebuild_view()
	else:
		_move_highlight()
	if TileId.is_autotile(selected_id) and not TileId.is_tile_a5(selected_id):
		_info.text = "自动元件 %d · 相同地面会拼接" % selected_id
	else:
		_info.text = "图块 %d" % selected_id


func current_tileset_id() -> String:
	return tileset_id


func _on_ts(idx: int) -> void:
	var sid := str(_ts_opt.get_item_metadata(idx))
	if sid == tileset_id:
		return
	_apply_tileset(sid, true)


func _apply_tileset(id: String, emit_change: bool) -> void:
	tileset_id = id
	tileset = _catalog.get(id, {}) if _catalog.has(id) else {}
	_flags = PackedInt32Array()
	var fv: Variant = tileset.get("flags", [])
	if typeof(fv) == TYPE_ARRAY:
		var arr: Array = fv
		_flags.resize(arr.size())
		for i in range(arr.size()):
			_flags[i] = int(arr[i])
	_load_sheets()
	_rebuild_view()
	if emit_change:
		tileset_changed.emit(tileset_id)


func _on_tab(t: String) -> void:
	if t == tab:
		_sync_tab_buttons()
		return
	tab = t
	_clear_stamp()
	_sync_tab_buttons()
	_rebuild_view()


func _sync_tab_buttons() -> void:
	for t in _tab_btns.keys():
		var b: Button = _tab_btns[t]
		b.set_pressed_no_signal(str(t) == tab)


func _load_sheets() -> void:
	sheets.clear()
	sheets.resize(9)
	var names_v: Variant = tileset.get("tilesetNames", [])
	var names: Array = names_v if typeof(names_v) == TYPE_ARRAY else []
	var am = Engine.get_main_loop().root.get_node_or_null("/root/AssetManager")
	for i in range(9):
		var n := str(names[i]) if i < names.size() else ""
		if n.strip_edges() == "":
			sheets[i] = null
			continue
		sheets[i] = _load_sheet(am, n)


func _load_sheet(am, sheet_name: String) -> Image:
	if am != null and am.has_method("path"):
		var cref := "content://tilesheet/%s" % sheet_name
		var resolved := str(am.path(cref)).strip_edges()
		if resolved != "" and FileAccess.file_exists(resolved):
			if am.has_method("load_image"):
				var via = am.load_image(cref)
				if via != null:
					return _sheet_rgba(via as Image)
			var img := Image.new()
			if img.load(resolved) == OK:
				return _sheet_rgba(img)
	var root := Rtp.content_root()
	var fallback := "%s/assets/tilesheet/%s.png" % [root, sheet_name]
	if FileAccess.file_exists(fallback):
		var img2 := Image.new()
		if img2.load(fallback) == OK:
			return _sheet_rgba(img2)
	return null


func _sheet_rgba(img: Image) -> Image:
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _rebuild_view() -> void:
	var img = null
	if tab == "A":
		_view_mode = "A"
		img = _compose_a_atlas()
	else:
		_view_mode = tab
		var si := _sheet_index_for_tab(tab)
		img = sheets[si] if si >= 0 and si < sheets.size() else null
		if img != null:
			img = img.duplicate()
	if img == null:
		img = Image.create(tile_px * 8, tile_px * 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.15, 0.08, 0.08, 1))
		_info.text = "图块 %d · %s 无图" % [selected_id, tab]
	var tex := ImageTexture.create_from_image(img)
	_tex.texture = tex
	_tex.size = Vector2(img.get_width(), img.get_height())
	_host.custom_minimum_size = Vector2(img.get_width(), img.get_height())
	_host.size = _host.custom_minimum_size
	if _pass_layer:
		_pass_layer.size = _host.size
		_pass_layer.position = Vector2.ZERO
	_move_highlight()
	_rebuild_passage_marks()
	_sync_pass_buttons()


func _compose_a_atlas() -> Image:
	var cols := 8
	var rows := 32
	var img := Image.create(cols * tile_px, rows * tile_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.13, 1))
	TileBlit.ensure_tables()
	for row in range(16):
		for col in range(8):
			var id := a_cell_to_id(col, row)
			var preview := _preview_id(id)
			TileBlit.blit_tile(img, preview, col * tile_px, row * tile_px, sheets, tile_px, tile_px, _flags, 0)
	var a5 = sheets[4] if sheets.size() > 4 else null
	if a5 != null:
		var w := mini(a5.get_width(), 8 * tile_px)
		var h := mini(a5.get_height(), 16 * tile_px)
		img.blit_rect(a5, Rect2i(0, 0, w, h), Vector2i(0, 16 * tile_px))
	else:
		for row in range(16, 32):
			for col in range(8):
				var id5 := a_cell_to_id(col, row)
				TileBlit.blit_tile(img, id5, col * tile_px, row * tile_px, sheets, tile_px, tile_px, _flags, 0)
	return img


func _preview_id(id: int) -> int:
	if not TileId.is_autotile(id):
		return id
	var kind := TileId.autotile_kind(id)
	var base: int = TileId.TILE_ID_A1 + kind * 48
	if TileId.is_waterfall_kind(kind):
		return base
	if TileId.is_wall_autotile(base):
		return base
	# Isolated floor (shape 46) shows edge art so dirt-with-tufts ≠ plain sand.
	var isolated: int = base + 46
	if isolated >= TileId.TILE_ID_MAX:
		return base
	return isolated


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _dragging:
			var hc := _cell_at(mm.position)
			if hc.x >= 0 and _info:
				var hid: int = _id_at_cell(hc.x, hc.y)
				var TileLabels = load("res://scripts/editor/domain/tile_labels.gd")
				_info.text = "指向 %s  @ %d,%d" % [str(TileLabels.info_line(hid)), hc.x, hc.y]
		if _dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var c := _cell_at(mm.position)
			if c.x >= 0:
				_drag_b = c
				_move_highlight()
		return
	if event is InputEventPanGesture and _scroll:
		var pg := event as InputEventPanGesture
		_scroll.scroll_horizontal = int(_scroll.scroll_horizontal + pg.delta.x)
		_scroll.scroll_vertical = int(_scroll.scroll_vertical + pg.delta.y)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and _scroll and (
		mb.button_index == MOUSE_BUTTON_WHEEL_LEFT
		or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT
		or ((mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.shift_pressed)
	):
		var step := float(maxi(tile_px, 24))
		var toward_right := mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		_scroll.scroll_horizontal = int(_scroll.scroll_horizontal + (step if toward_right else -step))
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_dragging = false
		selected_id = 0
		_clear_stamp()
		tile_selected.emit(0)
		stamp_changed.emit(1, 1, PackedInt32Array([0]))
		_move_highlight()
		_info.text = "图块 0（空）"
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		var c0 := _cell_at(mb.position)
		if c0.x < 0:
			return
		_dragging = true
		_drag_a = c0
		_drag_b = c0
		_commit_stamp(false)
		return
	if _dragging:
		_dragging = false
		var c1 := _cell_at(mb.position)
		if c1.x >= 0:
			_drag_b = c1
		_commit_stamp(true)


func _cell_at(pos: Vector2) -> Vector2i:
	var col := int(floor(pos.x / float(tile_px)))
	var row := int(floor(pos.y / float(tile_px)))
	if col < 0 or row < 0:
		return Vector2i(-1, -1)
	var max_c := 8
	var max_r := 32
	if tab != "A":
		var si := _sheet_index_for_tab(tab)
		var sheet = sheets[si] if si >= 0 and si < sheets.size() else null
		if sheet == null:
			return Vector2i(-1, -1)
		max_c = int(sheet.get_width() / tile_px)
		max_r = int(sheet.get_height() / tile_px)
	else:
		max_c = 8
		max_r = 32
	if col >= max_c or row >= max_r:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _id_at(pos: Vector2) -> int:
	var c := _cell_at(pos)
	if c.x < 0:
		return -1
	return _id_at_cell(c.x, c.y)


func _id_at_cell(col: int, row: int) -> int:
	if tab == "A":
		if col > 7 or row > 31:
			return -1
		return a_cell_to_id(col, row)
	var base := _base_for_tab(tab)
	var si := _sheet_index_for_tab(tab)
	var sheet = sheets[si] if si >= 0 and si < sheets.size() else null
	if sheet == null:
		return -1
	var max_c := int(sheet.get_width() / tile_px)
	var max_r := int(sheet.get_height() / tile_px)
	if col < 0 or row < 0 or col >= max_c or row >= max_r:
		return -1
	return sheet_cell_to_id(col, row, base)


func _clear_stamp() -> void:
	stamp_w = 1
	stamp_h = 1
	stamp_tiles = PackedInt32Array()
	_drag_a = Vector2i(-1, -1)
	_drag_b = Vector2i(-1, -1)


func _commit_stamp(emit_now: bool) -> void:
	if _drag_a.x < 0 or _drag_b.x < 0:
		return
	var x0 := mini(_drag_a.x, _drag_b.x)
	var x1 := maxi(_drag_a.x, _drag_b.x)
	var y0 := mini(_drag_a.y, _drag_b.y)
	var y1 := maxi(_drag_a.y, _drag_b.y)
	var w := mini(x1 - x0 + 1, 8)
	var h := mini(y1 - y0 + 1, 8)
	x1 = x0 + w - 1
	y1 = y0 + h - 1
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	var i := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles[i] = _id_at_cell(x, y)
			i += 1
	# A1–A4 are one autotile per cell. Dragging two kinds (sand + grass-on-sand)
	# used to stamp vertical grass stripes into a sand field.
	var origin_id: int = _id_at_cell(_drag_a.x, _drag_a.y)
	if tab == "A" and TileId.is_autotile(origin_id) and not TileId.is_tile_a5(origin_id):
		w = 1
		h = 1
		tiles = PackedInt32Array([origin_id])
		_drag_b = _drag_a
	stamp_w = w
	stamp_h = h
	stamp_tiles = tiles
	selected_id = int(tiles[0]) if tiles.size() > 0 else 0
	if show_passage and w == 1 and h == 1:
		_write_flag(selected_id, TileId.with_passage_kind(_flag_of(selected_id), pass_brush))
	_move_highlight()
	_sync_pass_buttons()
	if _info:
		var TileLabels = load("res://scripts/editor/domain/tile_labels.gd")
		var lab: String = str(TileLabels.info_line(selected_id))
		if w > 1 or h > 1:
			_info.text = "%s · %d×%d 图章" % [lab, w, h]
		elif TileId.is_autotile(selected_id) and not TileId.is_tile_a5(selected_id):
			_info.text = "%s · 相同地面会拼接" % lab
		else:
			_info.text = lab
	if emit_now:
		tile_selected.emit(selected_id)
		stamp_changed.emit(w, h, tiles)


func _move_highlight() -> void:
	if _hi == null:
		return
	if _drag_a.x >= 0 and _drag_b.x >= 0:
		var x0 := mini(_drag_a.x, _drag_b.x)
		var y0 := mini(_drag_a.y, _drag_b.y)
		var w := mini(absi(_drag_b.x - _drag_a.x) + 1, 8)
		var h := mini(absi(_drag_b.y - _drag_a.y) + 1, 8)
		_hi.visible = true
		_hi.position = Vector2(x0 * tile_px, y0 * tile_px)
		_hi.size = Vector2(w * tile_px, h * tile_px)
		return
	var cell := _cell_for_id(selected_id)
	if cell.x < 0:
		_hi.visible = false
		return
	_hi.visible = true
	_hi.position = Vector2(cell.x * tile_px, cell.y * tile_px)
	_hi.size = Vector2(tile_px * stamp_w, tile_px * stamp_h)


func _cell_for_id(id: int) -> Vector2i:
	if tab == "A":
		return a_id_to_cell(id)
	var base := _base_for_tab(tab)
	var index := id - base
	if index < 0 or index > 255:
		return Vector2i(-1, -1)
	if index < 128:
		return Vector2i(index % 8, int(index / 8))
	var i2 := index - 128
	return Vector2i(8 + i2 % 8, int(i2 / 8))


func _tab_for_id(id: int) -> String:
	if TileId.is_autotile(id) or TileId.is_tile_a5(id):
		return "A"
	if id < TileId.TILE_ID_C:
		return "B"
	if id < TileId.TILE_ID_D:
		return "C"
	if id < TileId.TILE_ID_E:
		return "D"
	if id < TileId.TILE_ID_A5:
		return "E"
	return "A"


func _base_for_tab(t: String) -> int:
	match t:
		"B":
			return TileId.TILE_ID_B
		"C":
			return TileId.TILE_ID_C
		"D":
			return TileId.TILE_ID_D
		"E":
			return TileId.TILE_ID_E
		_:
			return 0


func _sheet_index_for_tab(t: String) -> int:
	match t:
		"B":
			return 5
		"C":
			return 6
		"D":
			return 7
		"E":
			return 8
		_:
			return 4


static func a_cell_to_id(col: int, row: int) -> int:
	if col < 0 or col > 7 or row < 0:
		return 0
	if row < 2:
		return TileId.TILE_ID_A1 + (row * 8 + col) * 48
	if row < 6:
		return TileId.TILE_ID_A1 + (16 + (row - 2) * 8 + col) * 48
	if row < 10:
		return TileId.TILE_ID_A1 + (48 + (row - 6) * 8 + col) * 48
	if row < 16:
		return TileId.TILE_ID_A1 + (80 + (row - 10) * 8 + col) * 48
	if row < 32:
		return TileId.TILE_ID_A5 + (row - 16) * 8 + col
	return 0


static func a_id_to_cell(id: int) -> Vector2i:
	if TileId.is_tile_a5(id):
		var n: int = id - TileId.TILE_ID_A5
		return Vector2i(n % 8, 16 + int(n / 8))
	if not TileId.is_autotile(id):
		return Vector2i(-1, -1)
	var kind := TileId.autotile_kind(id)
	if kind < 16:
		return Vector2i(kind % 8, int(kind / 8))
	if kind < 48:
		var k2 := kind - 16
		return Vector2i(k2 % 8, 2 + int(k2 / 8))
	if kind < 80:
		var k3 := kind - 48
		return Vector2i(k3 % 8, 6 + int(k3 / 8))
	if kind < 128:
		var k4 := kind - 80
		return Vector2i(k4 % 8, 10 + int(k4 / 8))
	return Vector2i(-1, -1)


static func sheet_cell_to_id(col: int, row: int, base: int) -> int:
	if col < 8:
		return base + row * 8 + col
	return base + 128 + row * 8 + (col - 8)


func _flag_of(id: int) -> int:
	if id <= 0 or id >= _flags.size():
		return 0
	return int(_flags[id])


func _ensure_flags() -> void:
	if _flags.size() < TileId.TILE_ID_MAX:
		var old := _flags.size()
		_flags.resize(TileId.TILE_ID_MAX)
		for i in range(old, TileId.TILE_ID_MAX):
			_flags[i] = 0


func _write_flag(id: int, flag: int) -> void:
	_ensure_flags()
	var ids: PackedInt32Array = TileId.passage_ids_for(id)
	if ids.is_empty():
		return
	for tid in ids:
		if tid >= 0 and tid < _flags.size():
			_flags[tid] = flag
	if tileset_id != "" and _catalog.has(tileset_id):
		var ts: Dictionary = _catalog[tileset_id]
		var arr: Array = []
		arr.resize(_flags.size())
		for i in range(_flags.size()):
			arr[i] = int(_flags[i])
		ts["flags"] = arr
		_catalog[tileset_id] = ts
		tileset = ts
	_rebuild_passage_marks()
	_sync_pass_buttons()
	flags_changed.emit(tileset_id, _flags)


func _cycle_selected() -> void:
	if selected_id <= 0:
		return
	var cur := TileId.passage_kind(_flag_of(selected_id))
	var nxt := (cur + 1) % 3
	_write_flag(selected_id, TileId.with_passage_kind(_flag_of(selected_id), nxt))


func _set_selected_kind(kind: int) -> void:
	pass_brush = kind
	if selected_id <= 0:
		_sync_pass_buttons()
		return
	_write_flag(selected_id, TileId.with_passage_kind(_flag_of(selected_id), kind))


func _toggle_dir(bit: int) -> void:
	if selected_id <= 0:
		_sync_pass_buttons()
		return
	var f := _flag_of(selected_id)
	var blocked := (f & bit) != 0
	_write_flag(selected_id, TileId.with_dir_blocked(f, bit, not blocked))


func _sync_pass_buttons() -> void:
	var f := _flag_of(selected_id) if selected_id > 0 else 0
	var kind := pass_brush if show_passage else (TileId.passage_kind(f) if selected_id > 0 else -1)
	if _btn_o:
		_btn_o.set_pressed_no_signal(kind == TileId.PASS_O)
	if _btn_x:
		_btn_x.set_pressed_no_signal(kind == TileId.PASS_X)
	if _btn_star:
		_btn_star.set_pressed_no_signal(kind == TileId.PASS_STAR)
	for bit in _dir_btns.keys():
		var b: Button = _dir_btns[bit]
		b.set_pressed_no_signal(selected_id > 0 and (f & int(bit)) != 0)


func _rebuild_passage_marks() -> void:
	if _pass_layer == null:
		return
	_pass_layer.visible = show_passage
	var cols := 8
	var rows := 1
	if tab == "A":
		cols = 8
		rows = 32
	else:
		var si := _sheet_index_for_tab(tab)
		var sheet = sheets[si] if si >= 0 and si < sheets.size() else null
		if sheet == null:
			_pass_layer.set_grid(8, tile_px, PackedByteArray())
			return
		cols = maxi(1, int(sheet.get_width() / tile_px))
		rows = maxi(1, int(sheet.get_height() / tile_px))
	var kinds := PackedByteArray()
	kinds.resize(cols * rows)
	kinds.fill(255)
	for row in range(rows):
		for col in range(cols):
			var id := 0
			if tab == "A":
				id = a_cell_to_id(col, row)
			else:
				id = sheet_cell_to_id(col, row, _base_for_tab(tab))
			if id <= 0:
				continue
			kinds[row * cols + col] = TileId.passage_kind(_flag_of(id))
	_pass_layer.set_grid(cols, tile_px, kinds)
	_pass_layer.size = _host.size if _host else Vector2(cols * tile_px, rows * tile_px)

