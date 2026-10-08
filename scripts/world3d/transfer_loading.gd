extends CanvasLayer
## Owned by one transfer transaction and freed with its world.
var stage:="准备传送"
var done:=0
var total:=0
var started_ms:=Time.get_ticks_msec()
var drawn_frame:=-1
var _label:Label

func _ready()->void:
	name="TransferLoading";layer=1000
	var background:=ColorRect.new();background.color=Color(.035,.045,.065,1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(background)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",18);center.add_child(column)
	var title:=Label.new();title.text="正在进入目标区域";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",28);column.add_child(title)
	_label=Label.new();_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size",18);column.add_child(_label)
	_refresh()

func update_progress(value:String,current:int=0,count:int=0)->void:
	stage=value;done=current;total=count;_refresh()

func _refresh()->void:
	if _label==null:return
	var count:=" · %d / %d"%[done,total] if total>0 else ""
	_label.text="%s%s\n已用时 %.1f 秒"%[stage,count,(Time.get_ticks_msec()-started_ms)/1000.0]

func _process(_delta:float)->void:_refresh()
func _input(_event:InputEvent)->void:get_viewport().set_input_as_handled()

func wait_until_drawn()->void:
	if DisplayServer.get_name()=="headless":await get_tree().process_frame
	else:await RenderingServer.frame_post_draw
	drawn_frame=Engine.get_frames_drawn()

func finish()->void:
	# The destination has been mounted, but input remains frozen through its
	# first rendered frame. Removing the cover reveals an already-drawn world.
	update_progress("目标区域已准备好")
	if DisplayServer.get_name()=="headless":await get_tree().process_frame
	else:await RenderingServer.frame_post_draw
