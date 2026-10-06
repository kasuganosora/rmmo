extends Control
const Net = preload("res://scripts/net/net.gd")
const CharacterAssets = preload("res://scripts/char/character_axis_assets.gd")
const Style = preload("res://scripts/ui/entry_style.gd")
var _accepted_login := false
var _requested_user := ""
var _requested_server := ""
var user_edit: LineEdit
var pass_edit: LineEdit
var server_edit: LineEdit
var status_label: Label
var login_btn: Button
var _show_password: CheckBox
var _connection_toggle: Button
var _connection: VBoxContainer
var _scroll: ScrollContainer
var _form: VBoxContainer
var _brand: VBoxContainer

func _ready() -> void:
	Style.apply(self)
	_brand = Style.column(self, 6)
	_brand.add_child(Style.label("R M M O", 58, Style.GOLD))
	_brand.add_child(Style.label("你的下一段冒险，从这里开始", 17))
	_scroll = ScrollContainer.new(); _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_form = Style.column(_scroll, 12); _form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(Style.label("欢迎归来", 30))
	_form.add_child(Style.label("登录账号，继续你的旅程", 15, Style.MUTED))
	Style.divider(_form)
	user_edit = Style.field(_form, "账号", "输入账号")
	pass_edit = Style.field(_form, "密码", "输入密码", true)
	_show_password = CheckBox.new(); _show_password.text = "显示密码"; _show_password.custom_minimum_size.y = 30
	_form.add_child(_show_password)
	_show_password.toggled.connect(func(value: bool): pass_edit.secret = not value)
	login_btn = Style.button("登  录", true); _form.add_child(login_btn)
	status_label = Style.label("", 14, Style.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status_label.custom_minimum_size.y = 44
	_form.add_child(status_label)
	_connection_toggle = Style.button("连接设置  ▸"); _connection_toggle.flat = true; _connection_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_form.add_child(_connection_toggle)
	_connection = Style.column(_form, 8); _connection.visible = false
	server_edit = Style.field(_connection, "服务器地址", "127.0.0.1:7777")
	_connection_toggle.pressed.connect(func():
		_connection.visible = not _connection.visible
		_connection_toggle.text = "连接设置  ▾" if _connection.visible else "连接设置  ▸"
	)
	var hint := Style.label("首次使用的新账号将自动注册", 13, Style.MUTED); _form.add_child(hint)
	server_edit.text = Net.session().server_address
	user_edit.text = Net.session().username
	login_btn.pressed.connect(_on_login_pressed)
	for field in [user_edit, pass_edit, server_edit]: field.text_submitted.connect(func(_text: String): _on_login_pressed())
	Net.server().login_finished.connect(_on_login_finished)
	resized.connect(_layout); _layout()
	if user_edit.text.is_empty(): user_edit.grab_focus()
	else: pass_edit.grab_focus()
	CharacterAssets.begin_preload()

func _layout() -> void:
	if _scroll == null: return
	var narrow := size.x < 840
	_brand.visible = not narrow
	_brand.position = Vector2(56, maxf(32, size.y * .16))
	var width := minf(360, size.x - 48)
	_scroll.position = Vector2((size.x - width) / 2 if narrow else size.x - width - 72, maxf(24, (size.y - 530) / 2))
	_scroll.size = Vector2(width, maxf(100, size.y - _scroll.position.y - 24))

func _process(_delta: float) -> void:
	var prepared := CharacterAssets.poll_preload()
	if _accepted_login and prepared:
		_accepted_login = false
		Net.session().username = _requested_user
		Net.session().server_address = _requested_server
		Net.session().go_character_select()

func _set_busy(busy: bool) -> void:
	login_btn.disabled = busy
	for field in [user_edit, pass_edit, server_edit]: field.editable = not busy
	_show_password.disabled = busy
	_connection_toggle.disabled = busy
	login_btn.text = "正在登录…" if busy else "登  录"

func _on_login_pressed() -> void:
	if login_btn.disabled: return
	_requested_user = user_edit.text.strip_edges(); _requested_server = server_edit.text.strip_edges()
	_set_busy(true)
	status_label.add_theme_color_override("font_color", Style.MUTED)
	status_label.text = "正在连接服务器…"
	Net.server().login(_requested_user, pass_edit.text, _requested_server)

func _on_login_finished(ok: bool, message: String) -> void:
	if not login_btn.disabled: return
	_accepted_login = ok
	_set_busy(ok)
	status_label.text = "正在准备人物资源…" if ok else message
	if not ok:
		status_label.add_theme_color_override("font_color", Color("edb5a4"))
		pass_edit.grab_focus()
