extends RefCounted
## Domain module: tileset/palette (tileset window, catalog, apply, preset, sheet assign, palette sync).

var ctrl
func _init(c):
	ctrl = c

const EditorAtmosphere = preload("res://scripts/editor/interface/editor_atmosphere.gd")
const EditorSession = preload("res://scripts/editor/application/editor_session.gd")

func _open_tileset_win() -> void:
	if ctrl._tileset_win and ctrl._tileset_win.has_method("bind_pack"):
		ctrl._tileset_win.bind_pack(ctrl.pack)
	ctrl._popup_win(ctrl._tileset_win)



func _on_tileset_catalog() -> void:
	if ctrl.pack:
		ctrl.pack.dirty = true
	_sync_palette()
	if ctrl._tileset_win and ctrl._tileset_win.has_method("bind_pack"):
		ctrl._tileset_win.bind_pack(ctrl.pack)
	ctrl._status.text = "图块套已更新（未写入磁盘，Ctrl+S 保存）"



func _on_tileset_apply(ts_id: String) -> void:
	if ctrl.pack == null or ctrl.current_map_id == "" or ts_id.strip_edges() == "":
		return
	if ctrl.pack.set_map_tileset(ctrl.current_map_id, ts_id):
		_sync_palette()
		ctrl._reload_field()
		var label: String = ctrl.pack.tileset_label(ts_id) if ctrl.pack.has_method("tileset_label") else ts_id
		ctrl._status.text = "当前地图使用图块套：%s" % label



func _fill_preset_opt(opt: OptionButton, path: String, fallback: PackedStringArray) -> void:
	EditorAtmosphere.fill_preset_opt(ctrl, opt, path, fallback)

func _finish_sheet_assign(slot: int, sheet: String) -> void:
	EditorSession.finish_sheet_assign(ctrl, slot, sheet)



func _sync_palette() -> void:
	if ctrl._palette == null or ctrl.pack == null:
		return
	var ts = ""
	if ctrl.doc:
		ts = str(ctrl.doc.tileset_id)
	ctrl._palette.set_catalog(ctrl.pack.tilesets, ts)
	ctrl.paint.tile_id = int(ctrl._palette.selected_id)


