extends SubViewportContainer
signal streaming_failed(message:String)
var viewport_: SubViewport
var scene: Node3D
var camera: Camera3D
var current_path := ""
var _preparation:Node
var _request:=0
var _generation:=0
var _streamed_observer=preload("res://scripts/world_editor/streamed_preview_observer.gd").new()
var _readiness=preload("res://scripts/world_editor/streamed_preview_readiness.gd").new()
var streaming_error:=""

func _ready() -> void:
	stretch = true
	custom_minimum_size.y = 140
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_ = SubViewport.new()
	viewport_.own_world_3d = true
	viewport_.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_)
	camera = Camera3D.new()
	viewport_.add_child(camera)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("252c35")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	preload("res://scripts/world_editor/asset_preview_environment.gd").apply_reflections(environment)
	camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	viewport_.add_child(light)
	visible = false
	set_process(false)

func show_asset(path: String) -> void:
	if path == current_path and (scene!=null or _request!=0): return
	_cancel_preparation()
	current_path = path
	_dispose_scene()
	visible = not path.is_empty()
	if not visible: return
	_preparation=preload("res://scripts/world_editor/editor_asset_preparation.gd").for_consumer(self)
	if _preparation==null:visible=false;return
	_request=_preparation.request_many([path],self,_prepared.bind(_generation,{}))
	if _request==0:visible=false


func show_prefab(entry: Dictionary) -> void:
	var path := str(entry.get("prefab_path", ""))
	if path == current_path and (scene!=null or _request!=0): return
	_cancel_preparation()
	current_path = path
	_dispose_scene()
	var prefabs=preload("res://scripts/world_editor/prefab_library.gd")
	var loaded:Dictionary=prefabs.read(entry)
	visible=false
	if not loaded.get("ok",false):return
	_preparation=preload("res://scripts/world_editor/editor_asset_preparation.gd").for_consumer(self)
	if _preparation==null:return
	_request=_preparation.request_many(prefabs.preview_dependencies(loaded),self,_prepared.bind(_generation,loaded))


func _prepared(id:int,result:Dictionary,generation:int,prefab:Dictionary)->void:
	if generation!=_generation or id!=_request or not is_inside_tree():return
	_request=0
	if not result.get("ok",false):visible=false;return
	if prefab.is_empty():
		var handle:Variant=result.handles.get(current_path.replace("\\","/").simplify_path())
		scene=handle.instantiate() if handle!=null else null
	else:
		var templates:Dictionary={}
		for path:String in result.handles:
			if not result.handles[path].current():visible=false;return
			templates[path]=result.handles[path].packed
		scene=preload("res://scripts/world_editor/prefab_library.gd").preview_prepared(prefab,templates)
	visible=scene!=null
	_show_scene()


func _cancel_preparation()->void:
	_generation+=1
	if _request!=0 and is_instance_valid(_preparation):_preparation.cancel(_request)
	_request=0


func _show_scene() -> void:
	if scene == null:
		visible = false
		return
	viewport_.add_child(scene)
	for imported in scene.find_children("*", "Camera3D", true, false): imported.current = false
	camera.current = true
	var bounds := preload("res://scripts/world_editor/asset_library.gd").bounds_of(scene)
	var distance := maxf(bounds.size.length() * 1.4, 1)
	camera.position = bounds.get_center() + Vector3(1, 0.7, 1).normalized() * distance
	camera.look_at(bounds.get_center())
	camera.near = maxf(0.001, distance / 1000)
	camera.far = maxf(100, distance * 5)
	_streamed_observer.capture(scene)
	if is_visible_in_tree():_start_render()

func _start_render()->void:
	streaming_error="";tooltip_text=""
	_readiness.start(viewport_,self,_streamed_observer,_streaming_finished.bind(_generation))
	set_process(true)

func _process(_delta:float)->void:
	if not is_visible_in_tree():_readiness.cancel()
	else:_readiness.pump()
	set_process(_readiness.active())

func _streaming_finished(result:Dictionary,generation:int)->void:
	if generation!=_generation or not is_inside_tree():return
	set_process(false)
	if result.ok:return
	streaming_error=str(result.error);tooltip_text=streaming_error
	visible=false
	streaming_failed.emit(streaming_error)

func _notification(what:int)->void:
	if what!=NOTIFICATION_VISIBILITY_CHANGED or not is_instance_valid(viewport_):return
	var active:=is_visible_in_tree() and is_instance_valid(scene)
	# Hidden previews cancel their ticket. Reopening starts a new feedback
	# period with the same weak descriptors, without scanning the scene again.
	if active:_start_render()
	else:_readiness.cancel();set_process(false)

func _dispose_scene()->void:
	_readiness.cancel();_streamed_observer.clear();set_process(false)
	if is_instance_valid(viewport_):viewport_.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var owned:=scene;scene=null
	if not is_instance_valid(owned):return
	# Only this viewport's private preview belongs to us. A reparented instance
	# has a different owner and must not be destroyed through a stale field.
	if owned.get_parent()!=null:
		if owned.get_parent()!=viewport_:return
		viewport_.remove_child(owned)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(owned)

func _exit_tree()->void:
	_cancel_preparation()
	_dispose_scene()
