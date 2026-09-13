extends Control
const Net = preload("res://scripts/net/net.gd")

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

func _on_login_pressed() -> void:
	login_btn.disabled = true
	status_label.text = "连接中…"
	Net.server().login(user_edit.text, pass_edit.text, server_edit.text)

func _on_login_finished(ok: bool, message: String) -> void:
	login_btn.disabled = false
	status_label.text = message
	if not ok:
		return
	Net.session().username = user_edit.text.strip_edges()
	Net.session().server_address = server_edit.text.strip_edges()
	Net.session().go_character_select()
