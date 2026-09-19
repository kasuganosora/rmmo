extends RefCounted
## Domain module: assets (asset window, changed, import).

var ctrl
func _init(c):
	ctrl = c

const EditorSession = preload("res://scripts/editor/application/editor_session.gd")

func _open_asset_win() -> void:
	if ctrl._asset_win and ctrl._asset_win.has_method("bind_pack"):
		ctrl._asset_win.bind_pack(ctrl.pack)
	ctrl._popup_win(ctrl._asset_win)




func _on_assets_changed() -> void:
	if ctrl.pack:
		ctrl.pack.dirty = true
	EditorSession.reload_assets(ctrl)



func _import_asset(src: String, kind: String) -> void:
	EditorSession.import_asset(ctrl, src, kind)


