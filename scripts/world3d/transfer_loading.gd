extends CanvasLayer
## Presentation only. The owning transfer retains all readiness/authority gates.
const FADE_OUT_SECONDS:=.18
const FADE_IN_SECONDS:=.22
const HINT_DELAY_MS:=700
const SLOW_HINT_MS:=8000
var title_text:="正在进入目标区域"
var ready_text:="目标区域已准备好"
var stage:="准备传送"
var done:=0
var total:=0
var started_ms:=Time.get_ticks_msec()
var drawn_frame:=-1
var phase:="source"
var opacity:=0.0
var milestones:Dictionary={}
var _background:ColorRect
var _column:VBoxContainer
var _title:Label
var _label:Label
var _hint:Label
var _back:Button
var _retired:=false

func _ready()->void:
	name="TransferLoading";layer=1000
	_background=ColorRect.new();_background.color=Color(.035,.045,.065,1)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(_background)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE;_background.add_child(center)
	_column=VBoxContainer.new();_column.add_theme_constant_override("separation",18);center.add_child(_column)
	_title=Label.new();_title.text=title_text;_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size",28);_column.add_child(_title)
	_label=Label.new();_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size",18);_column.add_child(_label)
	_hint=Label.new();_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_column.add_child(_hint)
	_set_opacity(0);_refresh()

func update_progress(value:String,current:int=0,count:int=0)->void:
	if _retired or is_queued_for_deletion():return
	stage=value;total=maxi(0,count);done=clampi(current,0,total) if total>0 else 0;_refresh()

func _refresh()->void:
	if _label==null or not _alive():return
	_column.custom_minimum_size.x=clampf(get_viewport().get_visible_rect().size.x-48,160,640)
	var elapsed:=Time.get_ticks_msec()-started_ms
	_column.visible=phase=="failed" or (elapsed>=HINT_DELAY_MS and phase!="revealing")
	var count:=" · %d / %d"%[done,total] if total>0 else ""
	_label.text="%s%s\n已用时 %.1f 秒"%[stage,count,elapsed/1000.0]
	_hint.text="正在完成场景准备，请稍候。" if elapsed>=SLOW_HINT_MS else ""
	if phase=="failed":_hint.text="尚未恢复操作，请返回角色选择。"

func _process(_delta:float)->void:_refresh()
func _input(_event:InputEvent)->void:
	# Failure actions must reach GUI dispatch; unhandled input still stops here.
	if phase!="failed":get_viewport().set_input_as_handled()
func _unhandled_input(_event:InputEvent)->void:get_viewport().set_input_as_handled()

func _alive()->bool:return not _retired and is_inside_tree() and not is_queued_for_deletion()
func _set_opacity(value:float)->void:
	opacity=value
	if is_instance_valid(_background):_background.modulate.a=value

func _fade(target:float,seconds:float)->bool:
	var expected_phase:=phase
	var initial:=opacity
	var began:=Time.get_ticks_msec()
	while _alive() and phase==expected_phase:
		var t:=clampf((Time.get_ticks_msec()-began)/(seconds*1000),0,1)
		_set_opacity(lerpf(initial,target,t*t*(3-2*t)))
		if t>=1:return true
		await get_tree().process_frame
	return false

func _draw()->bool:
	if not _alive():return false
	var expected_phase:=phase
	var viewport:=get_viewport()
	if viewport is SubViewport and viewport.render_target_update_mode!=SubViewport.UPDATE_ALWAYS:return false
	if viewport.get_visible_rect().size.x<=0 or viewport.get_visible_rect().size.y<=0:return false
	# Start a fresh viewport frame after the caller's scene/camera mutations.
	await get_tree().process_frame
	if not _alive():return false
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	return _alive() and get_viewport()==viewport and phase==expected_phase

func wait_until_drawn()->bool:
	if phase!="source":return is_opaque_drawn()
	phase="covering";milestones.fade_out_started_ms=Time.get_ticks_msec()
	if not await _fade(1,FADE_OUT_SECONDS) or not await _draw():return false
	drawn_frame=Engine.get_frames_drawn();phase="waiting"
	milestones.covered_ms=Time.get_ticks_msec()
	return true

func is_opaque_drawn()->bool:
	return _alive() and visible and opacity==1.0 and drawn_frame>=0 and phase in ["waiting","ready","failed"]

func finish(expected_camera:Camera3D=null)->bool:
	# First frame is necessary, never sufficient: the owner validates authority
	# AFTER this returns, then explicitly calls reveal. Failure stays opaque.
	if not is_opaque_drawn() or phase!="waiting" or get_viewport().disable_3d:return false
	if expected_camera!=null and get_viewport().get_camera_3d()!=expected_camera:return false
	update_progress(ready_text)
	if not await _draw():return false
	if expected_camera!=null and get_viewport().get_camera_3d()!=expected_camera:return false
	milestones.viewport_id=get_viewport().get_instance_id()
	phase="ready";milestones.ready_ms=Time.get_ticks_msec();milestones.ready_frame=Engine.get_frames_drawn()
	return true

func reveal()->bool:
	if not _alive() or phase!="ready" or get_viewport().disable_3d:return false
	phase="revealing";milestones.reveal_started_ms=Time.get_ticks_msec();_refresh()
	if not await _fade(0,FADE_IN_SECONDS) or not await _draw():return false
	phase="revealed";milestones.revealed_ms=Time.get_ticks_msec()
	return true

func show_failure(reason:String,exit_action:Callable)->void:
	phase="failed";_title.text="暂时无法进入目标区域";_set_opacity(1);update_progress(reason)
	if _back==null:
		_back=Button.new();_back.text="返回角色选择";_back.focus_mode=Control.FOCUS_ALL;_column.add_child(_back)
		_back.pressed.connect(exit_action)
	_back.grab_focus()

func profile()->Dictionary:
	var result:=milestones.duplicate()
	result.merge({"drawn_frame":drawn_frame,"elapsed_ms":Time.get_ticks_msec()-started_ms,"phase":phase,"headless":DisplayServer.get_name()=="headless"})
	return result

func retire()->void:
	_retired=true;hide();set_process(false);set_process_input(false);set_process_unhandled_input(false)
	if get_parent()!=null:get_parent().remove_child(self)
	queue_free()
