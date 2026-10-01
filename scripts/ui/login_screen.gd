extends Control
const Net = preload("res://scripts/net/net.gd")
const CharacterAssets=preload("res://scripts/char/character_axis_assets.gd")
var _accepted_login:=false
var _requested_user:=""
var _requested_server:=""

@onready var user_edit: LineEdit = %Username
@onready var pass_edit: LineEdit = %Password
@onready var server_edit: LineEdit = %Server
@onready var status_label: Label = %Status
@onready var login_btn: Button = %LoginButton

func _ready() -> void:
	server_edit.text = Net.session().server_address
	user_edit.text = "demo"
	pass_edit.text = "demo"
	status_label.text = "测试账号 demo / demo · 新用户名会自动注册"
	login_btn.pressed.connect(_on_login_pressed)
	Net.server().login_finished.connect(_on_login_finished)
	user_edit.grab_focus()
	CharacterAssets.begin_preload()

func _process(_delta:float)->void:
	var prepared:=CharacterAssets.poll_preload()
	if _accepted_login and prepared:
		_accepted_login=false
		Net.session().username=_requested_user
		Net.session().server_address=_requested_server
		Net.session().go_character_select()

func _on_login_pressed() -> void:
	if login_btn.disabled:return
	_requested_user=user_edit.text.strip_edges();_requested_server=server_edit.text.strip_edges()
	login_btn.disabled = true
	status_label.text = "连接中…"
	Net.server().login(user_edit.text, pass_edit.text, server_edit.text)

func _on_login_finished(ok: bool, message: String) -> void:
	_accepted_login=ok
	login_btn.disabled = ok
	status_label.text = message
	if not ok:
		return
	status_label.text="正在准备人物资源…"
