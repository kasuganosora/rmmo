extends VBoxContainer
## Errors have their own persistent surface, independent of transient tool hints.
var editor: Node3D
var title: Label
var notice: HBoxContainer
var summary: Label
var message := ""
var context := ""
var _elapsed := 0.0

func setup(host: Node3D, document_title: Label) -> void:
	editor = host; title = document_title
	name = "WorkspaceFeedback"
	notice = HBoxContainer.new(); notice.name = "PersistentEditorNotice"
	add_child(notice)
	summary = Label.new(); summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.add_theme_color_override("font_color", Color("ffd08a")); notice.add_child(summary)
	var details := Button.new(); details.text = "查看原因"; notice.add_child(details)
	details.pressed.connect(func():
		var dialog := AcceptDialog.new(); dialog.title = context; dialog.dialog_text = message
		dialog.dialog_autowrap = true; dialog.min_size = Vector2i(420, 120)
		dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free)
		add_child(dialog); dialog.popup_centered(Vector2i(600, 240))
	)
	var dismiss := Button.new(); dismiss.text = "关闭"; dismiss.tooltip_text = "关闭这条提示"; notice.add_child(dismiss)
	dismiss.pressed.connect(func(): clear(context))
	notice.hide(); refresh_title()

func report(result: Dictionary, success: String, source: String) -> void:
	if bool(result.get("ok", false)):
		clear(source); editor._status.text = success
	else: error(str(result.get("error", "操作未完成")), source)

func error(text: String, source: String) -> void:
	message = text; context = source
	summary.text = source + " · " + text.replace("\n", " ")
	summary.tooltip_text = text; notice.show()
	editor._status.text = text

func clear(source: String) -> void:
	if source != context: return
	message = ""; context = ""; notice.hide()

func refresh_title() -> void:
	if editor == null or title == null: return
	var path: String = editor._path.replace("\\", "/")
	var map_name: String = path.get_base_dir().get_file() if path.get_file() == "map.gltf" else path.get_file().get_basename()
	if editor._doc != null:
		map_name = str(editor._doc.map_meta.get("name", map_name))
	if map_name.is_empty(): map_name = "未命名地图"
	var pack := ""
	if not editor._asset_pack_root.is_empty(): pack = " · " + editor._asset_pack_root.get_file()
	var state := "未保存" if editor._dirty else "已保存"
	if editor._load_failed: state = "读取失败"
	elif editor._load_job != null and editor._load_job.active: state = "加载中…"
	elif editor._save_job != null and editor._save_job.active: state = "保存中…"
	title.text = map_name + pack + " · " + state
	title.tooltip_text = path + "\n" + state

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0; refresh_title()
	if editor._status != null: editor._status.tooltip_text = editor._status.text
