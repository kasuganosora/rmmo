extends CanvasLayer
## Minimal opaque cover for the initial white-map load. It deliberately does not
## run a fade or a per-frame progress layout: the load path only needs a stable
## 2D surface so the viewport can disable 3D and use the covered-loading budget.

var _drawn:=false
var _failed:=false
var _background:ColorRect
var _label:Label
var _return_button:Button

func _ready()->void:
	layer=1000
	_background=ColorRect.new()
	_background.color=Color(.035,.045,.065,1)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(_background)
	_label=Label.new()
	_label.text="正在准备地图"
	_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size",24)
	_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_background.add_child(_label)
	await get_tree().process_frame
	_drawn=true

func is_opaque_drawn()->bool:
	return _drawn and is_inside_tree() and visible

func update_progress(_value:String,_current:int=0,_count:int=0)->void:
	pass

func show_failure(reason:String,return_action:Callable)->void:
	if _failed:return
	_failed=true
	_label.text="地图准备失败\n"+reason
	_return_button=Button.new()
	_return_button.text="返回角色选择"
	_background.add_child(_return_button)
	_return_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_return_button.position=(_background.size-Vector2(240,44))*.5+Vector2(0,76)
	_return_button.size=Vector2(240,44)
	_return_button.pressed.connect(return_action)
	_return_button.grab_focus()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _input(_event:InputEvent)->void:
	# Failed loading keeps gameplay blocked but lets GUI process the return
	# button before _unhandled_input absorbs anything the UI did not consume.
	if not _failed and is_inside_tree():get_viewport().set_input_as_handled()

func _unhandled_input(_event:InputEvent)->void:
	if is_inside_tree():get_viewport().set_input_as_handled()

func retire()->void:
	hide()
	set_process_input(false)
	set_process_unhandled_input(false)
	queue_free()
