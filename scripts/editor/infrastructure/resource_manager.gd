extends Window
## RPG Maker MV–style resource manager: folders, file list, preview.

signal assets_changed
signal tileset_slot_assigned(slot: int, sheet_id: String)

const CATS := [
	{"id": "tilesheet", "label": "图块", "img": true},
	{"id": "charset", "label": "行走图", "img": true},
	{"id": "faces", "label": "脸图", "img": true},
	{"id": "parallax", "label": "远景", "img": true},
	{"id": "audio/bgm", "label": "BGM", "img": false},
	{"id": "audio/bgs", "label": "BGS", "img": false},
	{"id": "audio/me", "label": "ME", "img": false},
	{"id": "audio/se", "label": "SE", "img": false},
]

var pack: RefCounted
var _cat: Tree
var _files: ItemList
var _preview: TextureRect
var _info: Label
var _slot_opt: OptionButton
var _kind: String = "tilesheet"
var _file_dlg: FileDialog
var _export_dlg: FileDialog


func _ready() -> void:
	title = "资源管理器"
	size = Vector2i(820, 520)
	unresizable = false
	visible = false
	close_requested.connect(hide)
	var root_m := MarginContainer.new()
	root_m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root_m.add_theme_constant_override(m, 8)
	add_child(root_m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	root_m.add_child(v)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	_cat = Tree.new()
	_cat.custom_minimum_size = Vector2(160, 0)
	_cat.hide_root = true
	_cat.item_selected.connect(_on_cat)
	body.add_child(_cat)
	_files = ItemList.new()
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files.custom_minimum_size = Vector2(240, 0)
	_files.item_selected.connect(_on_file)
	_files.item_activated.connect(func(_i): _on_file(_i))
	body.add_child(_files)
	var prev_col := VBoxContainer.new()
	prev_col.custom_minimum_size = Vector2(280, 0)
	prev_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(prev_col)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 1)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.22, 0.22, 0.26, 1)
	frame.add_theme_stylebox_override("panel", sb)
	prev_col.add_child(frame)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.custom_minimum_size = Vector2(260, 260)
	frame.add_child(_preview)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = "选择一个文件"
	prev_col.add_child(_info)
	var slot_row := HBoxContainer.new()
	prev_col.add_child(slot_row)
	var sl := Label.new()
	sl.text = "编入图块套"
	slot_row.add_child(sl)
	_slot_opt = OptionButton.new()
	for s in ["A1", "A2", "A3", "A4", "A5", "B", "C", "D", "E"]:
		_slot_opt.add_item(s)
	_slot_opt.select(4)
	slot_row.add_child(_slot_opt)
	var setb := Button.new()
	setb.text = "指定"
	setb.pressed.connect(_assign_slot)
	slot_row.add_child(setb)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_mk_btn(bar, "导入…", _import)
	_mk_btn(bar, "导出…", _export)
	_mk_btn(bar, "删除", _delete)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_mk_btn(bar, "关闭", hide)
	_file_dlg = FileDialog.new()
	_file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dlg.files_selected.connect(_on_imported)
	_file_dlg.file_selected.connect(func(p): _on_imported(PackedStringArray([p])))
	add_child(_file_dlg)
	_export_dlg = FileDialog.new()
	_export_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_export_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dlg.file_selected.connect(_on_exported)
	add_child(_export_dlg)
	_fill_cats()


func bind_pack(p: RefCounted) -> void:
	pack = p
	_reload_files()


func _fill_cats() -> void:
	_cat.clear()
	var root := _cat.create_item()
	var img := _cat.create_item(root)
	img.set_text(0, "图像")
	img.set_selectable(0, false)
	var aud := _cat.create_item(root)
	aud.set_text(0, "音频")
	aud.set_selectable(0, false)
	for i in range(CATS.size()):
		var c: Dictionary = CATS[i]
		var parent := aud if str(c["id"]).begins_with("audio") else img
		var it := _cat.create_item(parent)
		it.set_text(0, str(c["label"]))
		it.set_metadata(0, str(c["id"]))
		if i == 0:
			it.select(0)
	_kind = "tilesheet"


func _on_cat() -> void:
	var it := _cat.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	_kind = str(it.get_metadata(0))
	_reload_files()


func _reload_files() -> void:
	_files.clear()
	_preview.texture = null
	_info.text = "选择一个文件"
	if pack == null or not pack.has_method("list_assets"):
		return
	var items: Array = pack.list_assets(_kind)
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var idx := _files.add_item(str(it.get("file", it.get("id", ""))))
		_files.set_item_metadata(idx, it)
	if _files.item_count > 0:
		_files.select(0)
		_on_file(0)


func _on_file(idx: int) -> void:
	if idx < 0 or idx >= _files.item_count:
		return
	var meta: Variant = _files.get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var abs_path := str(meta.get("abs", ""))
	var fn := str(meta.get("file", ""))
	var ext := fn.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp", "bmp"]:
		var img := Image.new()
		if img.load(abs_path) == OK:
			_preview.texture = ImageTexture.create_from_image(img)
			_info.text = "%s\n%d × %d" % [fn, img.get_width(), img.get_height()]
		else:
			_preview.texture = null
			_info.text = "%s\n无法预览" % fn
	else:
		_preview.texture = null
		_info.text = "%s\n音频文件" % fn


func _import() -> void:
	if _kind.begins_with("audio"):
		_file_dlg.filters = PackedStringArray(["*.ogg ; OGG", "*.wav ; WAV", "*.mp3 ; MP3"])
	else:
		_file_dlg.filters = PackedStringArray(["*.png ; PNG"])
	_file_dlg.popup_centered_ratio(0.6)


func _on_imported(paths: PackedStringArray) -> void:
	if pack == null or not pack.has_method("import_asset_file"):
		return
	var n := 0
	for p in paths:
		if str(pack.import_asset_file(p, _kind)) != "":
			n += 1
	_reload_files()
	assets_changed.emit()
	_info.text = "已导入 %d 个文件" % n


func _delete() -> void:
	if pack == null or not pack.has_method("delete_asset"):
		return
	var sel := _files.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _files.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return
	if pack.delete_asset(_kind, str(meta.get("file", ""))):
		_reload_files()
		assets_changed.emit()


func _export() -> void:
	var sel := _files.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _files.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return
	_export_dlg.current_file = str(meta.get("file", "asset"))
	_export_dlg.popup_centered_ratio(0.5)


func _on_exported(path: String) -> void:
	var sel := _files.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _files.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var src := str(meta.get("abs", ""))
	if src == "" or not FileAccess.file_exists(src):
		return
	DirAccess.copy_absolute(src, path)


func _assign_slot() -> void:
	if _kind != "tilesheet":
		_info.text = "只有图块可以编入图块套"
		return
	var sel := _files.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _files.get_item_metadata(sel[0])
	if typeof(meta) != TYPE_DICTIONARY:
		return
	tileset_slot_assigned.emit(_slot_opt.selected, str(meta.get("id", "")))


func _mk_btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
