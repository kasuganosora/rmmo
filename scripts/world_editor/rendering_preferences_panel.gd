extends AcceptDialog
var service:Node
var editor:Node
var choices:Dictionary={}
var note:Label
var apply_button:Button
var previous_button:Button
var defaults_button:Button

func setup(host:Node)->void:
	editor=host;service=editor._rendering_preferences
	title="本机画质 · Godot 4.8";min_size=Vector2i(500,270)
	get_ok_button().text="关闭"
	var box:=VBoxContainer.new();add_child(box)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=470;box.add_child(note)
	for item:Array in [["contact_shadows","接触阴影（改善物件接触处的细小阴影）"],["multi_bounce_ao","多次反弹 AO（减轻环境遮蔽过度变暗）"]]:
		var button:=CheckBox.new();button.text=item[1];box.add_child(button);choices[item[0]]=button
	var buttons:=HBoxContainer.new();box.add_child(buttons)
	apply_button=Button.new();apply_button.text="保存，下次启动生效";buttons.add_child(apply_button);apply_button.pressed.connect(_apply)
	previous_button=Button.new();previous_button.text="恢复上一次";buttons.add_child(previous_button);previous_button.pressed.connect(func():_show_result(service.restore_previous()))
	defaults_button=Button.new();defaults_button.text="恢复默认";buttons.add_child(defaults_button);defaults_button.pressed.connect(func():_show_result(service.reset_defaults()))
	# Attach beside the existing service menu without changing workspace layout.
	var toolbar:Node=editor._mcp_popup.get_parent().get_parent()
	var entry:=Button.new();entry.text="本机画质";toolbar.add_child(entry)
	entry.pressed.connect(func():refresh();popup_centered())
	service.changed.connect(refresh);refresh()

func refresh()->void:
	var state:Dictionary=service.state()
	for key:String in choices:
		choices[key].set_pressed_no_signal(state.saved[key]);choices[key].disabled=state.pending or not state.writable
	apply_button.disabled=state.pending or not state.writable
	previous_button.disabled=state.pending or not state.writable or not state.can_restore_previous
	defaults_button.disabled=state.pending or not state.writable
	var applied:Array=[]
	for pair:Array in [["contact_shadows","接触阴影"],["multi_bounce_ao","多次反弹 AO"]]:applied.append(pair[1]+("开" if state.applied[pair[0]] else "关"))
	note.text="影响本机编辑器和游戏；不写入地图。\n当前启动设置：%s。\n%s"%["、".join(applied),"正在保存…" if state.pending else ("已保存，重新启动编辑器/游戏后生效。" if state.restart_required else "已保存设置与当前启动设置一致。")]
	if not state.renderer_supported:note.text+="\n当前渲染器不支持这些效果；使用 Forward+ 后生效。"
	if not state.writable:note.text+="\n"+(str(state.error) if not str(state.error).is_empty() else "工程禁用了本机启动配置或指定了其他配置。")
	if not state.last_result.is_empty() and not state.last_result.get("ok",false):note.text+="\n"+str(state.last_result.get("error","保存失败"))

func _apply()->void:
	var values:Dictionary={}
	for key:String in choices:values[key]=choices[key].button_pressed
	_show_result(service.apply(values))

func _show_result(result:Dictionary)->void:
	refresh()
	if not result.ok:note.text+="\n"+str(result.error)
