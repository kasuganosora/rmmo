extends CanvasLayer
## In-world house access editor. The server owns every saved permission.
var transport:Node
var _panel:PanelContainer
var _rows:VBoxContainer
var _view:Dictionary={}
var _pending_request:=0
var _error:Label
func show_house(view:Dictionary,server:Node)->void:
	layer=20
	transport=server;_view=view.duplicate(true)
	if not transport.response_ready.is_connected(_response):transport.response_ready.connect(_response)
	if is_instance_valid(_panel):_panel.queue_free()
	_panel=PanelContainer.new();_panel.offset_left=24;_panel.offset_top=90;_panel.custom_minimum_size=Vector2(440,260);add_child(_panel)
	var margin:=MarginContainer.new();for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	_panel.add_child(margin);_rows=VBoxContainer.new();_rows.add_theme_constant_override("separation",8);margin.add_child(_rows)
	var header:=HBoxContainer.new();_rows.add_child(header)
	var title:=Label.new();title.text=str(view.get("name","房屋"))+" · 权限";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();close.text="关闭";close.pressed.connect(queue_free);header.add_child(close)
	var refresh:=Button.new();refresh.text="刷新";refresh.pressed.connect(func():transport.try_house_permissions(str(_view.get("house",""))));header.add_child(refresh)
	_error=Label.new();_rows.add_child(_error)
	var status:=Label.new();status.text={"personal":"个人共享房屋","guild":"公会驻地","public":"公共建筑"}.get(str(view.get("kind","")),"房屋");_rows.add_child(status)
	var hint:=Label.new();hint.text="入口打开时访客也可进入；关闭后按授权准入。\n打开窗户不改变入屋权限。";_rows.add_child(hint)
	var rights:=Label.new();rights.text="你的权限："+("进入 " if view.get("can_enter",false) else "")+("操作门窗 " if view.get("can_operate",false) else "")+("管理" if view.get("can_manage",false) else "");_rows.add_child(rights)
	if not view.get("can_manage",false):return
	var entry:=CheckBox.new();entry.text="入口关闭时也允许访客进入";entry.button_pressed=bool(view.get("public_entry",false));_rows.add_child(entry)
	var operate:=CheckBox.new();operate.text="允许访客操作门窗";operate.button_pressed=bool(view.get("public_operate",false));_rows.add_child(operate)
	var apply:=Button.new();apply.text="保存访客权限";apply.pressed.connect(func():_submit({"action":"public","enter":entry.button_pressed,"operate":operate.button_pressed}));_rows.add_child(apply)
	var member:=LineEdit.new();member.placeholder_text="要共享房屋的角色名字";_rows.add_child(member)
	var access:=HBoxContainer.new();_rows.add_child(access)
	var can_enter:=CheckBox.new();can_enter.text="进入";can_enter.button_pressed=true;access.add_child(can_enter)
	var can_operate:=CheckBox.new();can_operate.text="门窗操作";can_operate.button_pressed=true;access.add_child(can_operate)
	var manage:=CheckBox.new();manage.text="共同管理";access.add_child(manage)
	manage.toggled.connect(func(on:bool):
		if on:can_enter.button_pressed=true;can_operate.button_pressed=true)
	var grant:=Button.new();grant.text="添加或更新共享权限";grant.pressed.connect(func():_submit({"action":"grant","member_name":member.text.strip_edges(),"enter":can_enter.button_pressed,"operate":can_operate.button_pressed,"manage":manage.button_pressed}));_rows.add_child(grant)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=120;_rows.add_child(scroll)
	var members:=VBoxContainer.new();members.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(members)
	for row:Dictionary in view.get("members",[]):
		var line:=HBoxContainer.new();members.add_child(line)
		var name_label:=Label.new();name_label.text=str(row.get("name",row.get("id","")))+" · "+("共同管理" if row.get("manage",false) else ("进入 " if row.get("enter",false) else "")+("门窗操作" if row.get("operate",false) else ""));name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(name_label)
		var revoke:=Button.new();revoke.text="取消共享";revoke.pressed.connect(func():_submit({"action":"revoke","member_id":str(row.id)}));line.add_child(revoke)
func _submit(change:Dictionary)->void:
	if not is_instance_valid(transport):return
	change.house=_view.get("house","");change.expected_revision=int(_view.get("revision",0))
	var result:Dictionary=transport.try_house_update(change)
	if result.get("deferred",false):
		_pending_request=int(result.request_id)
		_lock_buttons(_rows,true)
	elif is_instance_valid(_error):_error.text=str(result.get("error","保存失败，请刷新后重试"))

func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled();queue_free()

func _lock_buttons(node:Node,on:bool)->void:
	for child in node.get_children():
		if child is Button:child.disabled=on
		_lock_buttons(child,on)
func _response(id:int,result:Dictionary)->void:
	if id!=_pending_request:return
	_pending_request=0
	if is_instance_valid(_rows):_lock_buttons(_rows,false)
	if not result.get("ok",false) and is_instance_valid(_error):_error.text=str(result.get("error","保存失败，请刷新后重试"))
