extends Node
## Machine-local startup settings, deliberately separate from map history.
signal changed
const PATH:="user://rmmo_rendering_override.cfg"
const KEYS:={"contact_shadows":"lights_and_shadows/contact_shadow/enabled","multi_bounce_ao":"lights_and_shadows/multi_bounce_occlusion/enabled"}
const DEFAULTS:={"contact_shadows":false,"multi_bounce_ao":false}
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
var _applied:Dictionary={}
var _queue:Node
var _serial:=0
var _pending:=""
var _last:Dictionary={}

func configure(ledger:RefCounted)->void:
	for key:String in KEYS:_applied[key]=bool(ProjectSettings.get_setting("rendering/"+KEYS[key],false))
	_queue=Queue.new();_queue.ledger=ledger;_queue.shared_ledger_enabled=true
	add_child(_queue);set_process(false)

static func _valid(value:Variant)->bool:
	if not value is Dictionary or value.size()!=KEYS.size():return false
	for key:String in KEYS:
		if not value.get(key) is bool:return false
	return true

static func _read()->Dictionary:
	var config:=ConfigFile.new();var error:=config.load(PATH)
	if error==ERR_FILE_NOT_FOUND:return {"ok":true,"saved":DEFAULTS.duplicate(),"previous":{},"sha":""}
	if error!=OK:return {"ok":false,"error":"画质偏好文件无法读取："+error_string(error)}
	var saved:Dictionary={}
	for key:String in KEYS:saved[key]=config.get_value("rendering",KEYS[key],false)
	if not _valid(saved):return {"ok":false,"error":"画质偏好格式无效，未覆盖原文件"}
	var previous:Variant=config.get_value("rmmo_rendering_preferences","previous",{})
	return {"ok":true,"saved":saved,"previous":previous if _valid(previous) else {},"sha":FileAccess.get_sha256(PATH)}

func state()->Dictionary:
	var stored:=_read();var saved:Dictionary=stored.get("saved",_applied)
	var enabled:bool=not ProjectSettings.get_setting("application/config/disable_project_settings_override",false)
	var managed:bool=ProjectSettings.get_setting("application/config/project_settings_override","")==PATH
	var renderer:=RenderingServer.get_current_rendering_method()
	return {"ok":true,"applied":_applied.duplicate(),"saved":saved,"restart_required":saved!=_applied,"pending":not _pending.is_empty(),"last_result":_last.duplicate(true),
		"can_restore_previous":not stored.get("previous",{}).is_empty(),"writable":enabled and managed and stored.ok,"error":stored.get("error",""),
		"startup_override_enabled":enabled,"managed_override":managed,"renderer":renderer,"renderer_supported":renderer=="forward_plus","scope":"machine_editor_and_game_startup","path":PATH}

func apply(changes:Dictionary)->Dictionary:
	if not _pending.is_empty():return {"ok":false,"error":"画质设置正在保存，请等待完成"}
	if changes.is_empty():return {"ok":false,"error":"请至少选择一项画质设置"}
	for key:Variant in changes:
		if not KEYS.has(key) or not changes[key] is bool:return {"ok":false,"error":"画质设置只接受已声明的布尔选项"}
	var status:=state()
	if not status.writable:return {"ok":false,"error":status.error if not str(status.error).is_empty() else "当前工程禁用了本机画质配置或使用其他启动配置，未覆盖"}
	var stored:=_read()
	if not stored.ok:return stored
	var desired:Dictionary=stored.saved.merged(changes,true)
	if desired==stored.saved:return state().merged({"saved_successfully":true},true)
	_serial+=1;_pending="render_preferences:%d"%_serial
	var estimate:={"estimated_bytes":65536,"exclusive":false,"cpu_only":true,"stage":"rendering_preferences"}
	if not _queue.enqueue(_pending,_write.bind(desired,stored.saved,stored.sha),estimate,"neutral"):
		_pending="";return {"ok":false,"error":"画质设置保存任务无法启动"}
	set_process(true);changed.emit()
	return {"ok":true,"pending":true,"operation":"rendering_preferences","request_id":_serial,"restart_required":desired!=_applied}

func reset_defaults()->Dictionary:return apply(DEFAULTS)

func restore_previous()->Dictionary:
	var stored:=_read()
	if not stored.ok:return stored
	if stored.previous.is_empty():return {"ok":false,"error":"没有可恢复的上一次画质设置"}
	return apply(stored.previous)

static func _write(desired:Dictionary,previous:Dictionary,expected_sha:String,before_publish:Callable=Callable())->Dictionary:
	var current:=FileAccess.get_sha256(PATH) if FileAccess.file_exists(PATH) else ""
	if current!=expected_sha:return {"ok":false,"error":"画质设置已被其他操作修改，请刷新后重试"}
	var config:=ConfigFile.new()
	if not expected_sha.is_empty():
		var read_error:=config.load(PATH)
		if read_error!=OK:return {"ok":false,"error":"画质设置读取失败，未覆盖原文件"}
	for key:String in KEYS:config.set_value("rendering",KEYS[key],desired[key])
	config.set_value("rmmo_rendering_preferences","previous",previous)
	var temporary:=PATH+".tmp-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var error:=config.save(temporary)
	if error==OK:
		if before_publish.is_valid():before_publish.call()
		current=FileAccess.get_sha256(PATH) if FileAccess.file_exists(PATH) else ""
		if current!=expected_sha:
			DirAccess.remove_absolute(temporary)
			return {"ok":false,"error":"画质设置在保存期间被其他操作修改，请刷新后重试"}
	if error==OK:error=Atomic.publish(temporary,PATH)
	if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
	return {"ok":true,"saved_successfully":true} if error==OK else {"ok":false,"error":"画质设置保存失败："+error_string(error)}

func _process(_delta:float)->void:
	if _pending.is_empty() or not _queue.is_ready(_pending):return
	_last=_queue.acquire(_pending).duplicate(true)
	_queue.release(_pending);_queue.forget_terminal(_pending)
	_pending="";set_process(false);changed.emit()

func _exit_tree()->void:
	if is_instance_valid(_queue):_queue.cancel()
