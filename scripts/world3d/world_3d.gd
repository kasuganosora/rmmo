extends Node3D
## Meter-space world used by the world3d login profile and editor playtests.

const GltfMapIo = preload("res://scripts/world3d/gltf_map_io.gd")
const WorldMapPaths = preload("res://scripts/world3d/map_paths.gd")
const Travel = preload("res://scripts/world3d/world_travel.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
const Net = preload("res://scripts/net/net.gd")

var _player: CharacterBody3D
var _camera: Node3D
var _status: Label
var _travel = null
var _map_path := ""
var _map_root: Node

## Program-controlled doors, glazed casements and shutters. Runtime changes persist
## across chunk residency; authored defaults are changed through editor/MCP tools.
func list_building_components(building_id: String) -> Array:
	return preload("res://scripts/world3d/building_fixtures.gd").list_runtime(_map_root,building_id) if is_instance_valid(_map_root) else []

func set_building_component_state(building_id: String, component_id: String, open: float, duration := .35) -> Dictionary:
	if not is_instance_valid(_map_root): return {"ok":false,"error":"地图未加载"}
	return preload("res://scripts/world3d/building_fixtures.gd").set_runtime(_map_root,building_id,component_id,open,duration)
var _sun: DirectionalLight3D
var _env: Environment
var _weather: Node3D
var _outline: CanvasLayer
var _lamps: Array = []
var _night := false
var _check_map := false
var _actor_host: Node3D
var _failed_warp := ""
var _transfer_pending := false
var _transfer_loader: Node
var _ready_for_play := false
var _combat: Node
var _pending_ground_skill := ""
var _revive: Button
var _hud: Control
var _navigation: Node
var _previous_feet := Vector3.ZERO
var _map_data = preload("res://scripts/world3d/world_map_data.gd").new()
var _map_pin_sets:Dictionary={}
var _sit_revision:=0
var _sit_preparing:=false
var furniture=preload("res://scripts/world3d/world_furniture.gd").new(self)
var remote_players=preload("res://scripts/world3d/world_remote_players.gd").new(self)

func facial_expression_catalog()->Array:
	if not is_instance_valid(_player) or _player._model.axis_rig==null:return []
	var catalog=preload("res://scripts/char/character_expressions.gd")
	var rows:Array=[{"id":"neutral","label":"恢复自然","tag":""}]
	for id in catalog.NAMES:rows.append({"id":id,"label":catalog.NAMES[id],"tag":catalog.LABELS[id],"group":catalog.group_for(id)})
	return rows

func facial_expression_state()->Dictionary:
	if not is_instance_valid(_player):return {}
	return _player._model.expression_target()

func request_facial_expression(id:String,combine:bool=false)->bool:
	if not is_instance_valid(_player) or _player.input_locked:return false
	if id=="neutral":return _send_facial_expression({})
	var catalog=preload("res://scripts/char/character_expressions.gd")
	if not catalog.CHANNELS.has(id):return false
	if not combine:return _send_facial_expression({id:1.0})
	# Use the pending target so rapid clicks do not lose a category mid-transition.
	var values:Dictionary=facial_expression_state()
	var selected:bool=values.has(id)
	for peer:String in catalog.GROUPS[catalog.group_for(id)]:values.erase(peer)
	if not selected:values[id]=1.0
	return _send_facial_expression(values)

func request_remote_debug_spawn(display_name:String="")->void:
	var feet:Vector3=_player.global_position-Vector3(0,.9,0)+Vector3(2,0,0)
	var result:Dictionary=Net.server().facial_expressions.spawn_peer(display_name,_map_path,feet)
	apply_actions(result.get("actions",[]))


func _send_facial_expression(weights:Dictionary)->bool:
	var result:Dictionary=Net.server().try_facial_expression(weights)
	apply_actions(result.get("actions",[]))
	return bool(result.get("ok",false))

func _on_identity_shapes_changed()->void:
	call_deferred("_refresh_player_clearance")
	furniture.cancel()
	cancel_sit_preparation()
	if Net.server().sitting:
		apply_actions(Net.server().try_sit(false).get("actions",[]))

func cancel_sit_preparation()->void:
	_sit_revision+=1

func _on_movement_intent()->void:
	if furniture.active():furniture.stand()
	cancel_sit_preparation()
	if Net.server().sitting:apply_actions(Net.server().try_sit(false).get("actions",[]))

func request_sit(on:Variant=null)->void:
	if furniture.active():
		furniture.stand();return
	var want:bool=bool(on) if on is bool else not (Net.server().sitting or _sit_preparing)
	if want and _sit_preparing:return
	cancel_sit_preparation()
	if not want:
		apply_actions(Net.server().try_sit(false).get("actions",[]));return
	if _sit_preparing or _transfer_pending or not is_instance_valid(_player) or _player.input_locked:return
	if not Net.server().combat_stats.player_alive():return
	var model=_player._model
	if model.axis_rig==null:return
	if model.action in _player.REST_ACTIONS:return
	_player.click_target=null;_player._route.clear()
	var revision:int=_sit_revision
	_sit_preparing=true
	var requested_rig=model.axis_rig
	var bundle:AnimationLibrary=await requested_rig.prepare_ground_actions()
	_sit_preparing=false
	if revision!=_sit_revision or not is_instance_valid(_player) or not is_instance_valid(model):return
	if model!=_player._model or model.axis_rig!=requested_rig:return
	if _transfer_pending or _player.input_locked or not Net.server().combat_stats.player_alive():return
	if bundle==null:
		apply_actions([{"type":"system_message","text":"坐下动作准备失败："+model.axis_rig.last_error}]);return
	var library:AnimationLibrary=model.axis_rig.animations.library.duplicate()
	for clip:StringName in bundle.get_animation_list():
		if library.has_animation(clip):library.remove_animation(clip)
		library.add_animation(clip,bundle.get_animation(clip))
	if not model.axis_rig.animations.install(model.skeleton,library):return
	apply_actions(Net.server().try_sit(true).get("actions",[]))

func _refresh_world_map()->void:
	_map_data.build(_map_root)
	_map_data.pins.assign(_map_pin_sets.get(_map_path,[]))
	if is_instance_valid(_hud):
		_hud.bind_world_map_3d(self)
		if is_instance_valid(_hud._map_overview) and _hud._map_overview.has_method("bind_world"):_hud._map_overview.bind_world(self)

func toggle_world_map_pin(point:Vector2)->void:
	if not point.is_finite() or not _map_data.bounds.has_point(point):return
	_map_data.toggle_pin(point)
	_map_pin_sets[_map_path]=_map_data.pins.duplicate()

func clear_world_map_pins()->void:
	_map_data.pins.clear();_map_pin_sets[_map_path]=[]

func request_world_map_move(point:Vector2)->bool:
	if _player.input_locked or not point.is_finite() or not _map_data.bounds.has_point(point):return false
	var desired:=Vector3(point.x,_player.position.y-.9,point.y)
	var goal:=NavigationServer3D.map_get_closest_point(_navigation.map,desired)
	if Vector2(goal.x,goal.z).distance_to(point)>1.5:
		_hud.append_system("此处暂无可用路径；远处导航可能仍在准备。")
		return false
	var result:Dictionary=_navigation.find_path(_player.position-Vector3(0,.9,0),goal)
	if not result.get("ok",false):
		_hud.append_system("无法到达此处。")
		return false
	_player.set_click_target(goal,"ground")
	return true


func is_world_ready() -> bool:
	return _ready_for_play


func _exit_tree() -> void:
	furniture.cancel()
	cancel_sit_preparation()
	if is_instance_valid(_transfer_loader): _transfer_loader.cancel()
	var server = Net.server()
	if server != null and server.sitting:server.try_sit(false)
	if server != null and server.get("world3d_authority") != null:
		server.world3d_authority.release()
	if server != null and server.has_method("world3d_release_actors"):
		server.world3d_release_actors()


func _ready() -> void:
	_travel = Net.session().world3d_travel()
	_add_light()
	_add_hud()
	if not Net.session().has_active_character():
		_status.text = "缺少角色数据：请登录并选择角色后进入三维世界"
		_ready_for_play = true
		return
	var body_type := str(Net.session().active_character().gender)
	if not preload("res://scripts/char/character_model_3d.gd").source_available(body_type,Net.session().active_character().get("customization",{})):
		_status.text = "角色资源缺失：请检查外部素材包，未使用替代模型"
		_ready_for_play = true
		return
	var map_root := _load_or_fail()
	if map_root == null:
		_ready_for_play = true
		return
	add_child(map_root)
	_map_root = map_root
	if Net.session().world3d_loading:
		while not map_root.has_meta("stream_chunk"):
			Stream.sync(map_root, self, Net.session().world3d_spawn, Stream.FRAME_BUDGET)
			await get_tree().process_frame
	else:
		_add_collision(map_root)
	_add_player()
	_player.movement_intent.connect(_on_movement_intent)
	await _prepare_navigation()
	_add_town_lamps(map_root)
	_apply_map_environment()
	_mount_events()
	if not Net.session().active_character().is_empty():
		_add_game_hud()
	_previous_feet = _player.global_position - Vector3(0, 0.9, 0)
	apply_actions(Net.server().world3d_events.runtime.collect_autorun(Net.server().world3d_events.context()))
	await get_tree().process_frame
	_player.input_locked = Net.session()._world_transition_active
	_ready_for_play = true
	if _check_map:
		_status.text = "检查用白模，不是正式地图 · WASD 走 · N 切换路灯"
	elif _lamps.is_empty():
		_status.text = "WASD 走 · 右键转动 · E 对话 · 走到北边的垫子会去另一张图"
	else:
		_status.text = "WASD 走 · 右键转动 · N 切换路灯"
	if is_instance_valid(Net.session().editor_playtest): _status.text = "WASD 移动 · 右键转动 · E 交互 · 临时试玩"


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _player.input_locked:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _camera.captured:
			var hit := _pick(button.position)
			if not hit.is_empty():
				if _pending_ground_skill != "":
					_combat.use_skill(_pending_ground_skill, hit.position)
					_pending_ground_skill = ""
					get_viewport().set_input_as_handled()
					return
				var body: Object = hit.collider
				var id := str(body.get_meta("uuid", ""))
				if _combat.targets.has(id):
					_combat.attack(id)
					get_viewport().set_input_as_handled()
					return
				var surface_id := "ground"
				if body is CollisionObject3D and (body as CollisionObject3D).has_meta("surface_id"):
					surface_id = str((body as CollisionObject3D).get_meta("surface_id"))
				if not _navigation.fully_ready and not _navigation.near_surface(hit.position):
					_status.text = "远处导航仍在准备，请稍后再试。"
				_player.set_click_target(hit.position, surface_id)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			if _pending_ground_skill != "":
				_pending_ground_skill = ""
				_status.text = "已取消地点选择。"
				return
			_leave()
		elif key.pressed and not key.echo and key.keycode == KEY_N and not _lamps.is_empty():
			set_night(not _night)
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode == KEY_E:
			if not _combat.pickup_nearby(): _talk()


func _process(delta: float) -> void:
	if is_instance_valid(_player):apply_actions(Net.server().facial_expressions.drain())
	if _player == null or _camera == null:
		return
	furniture.tick()
	if _ready_for_play and not _transfer_pending and is_instance_valid(_navigation):
		_navigation.resize_agent(float(_player.get_meta("standing_height",1.9)),_map_root.get_meta("stream_library",[]),_player.position)
	_apply_residency(Stream.FRAME_BUDGET)
	_camera.follow(_player.global_position, delta)
	if is_instance_valid(_outline):_outline.visual_exclusions=_camera.visual_exclusions()
	_apply_actor_view()
	_poll_warp()

func _update_cloth_scene()->void:
	if not is_instance_valid(_map_root):return
	var objects:Array=[]
	var bodies:Dictionary=_map_root.get_meta("stream_bodies",{})
	var meshes:Dictionary=_map_root.get_meta("stream_meshes",{})
	for id in meshes:
		if bodies.has(id) and is_instance_valid(bodies[id]):objects.append(meshes[id])
	var model=_player._model
	if model.axis_rig!=null:model.axis_rig.cloth.set_scene_colliders(objects)
	if is_instance_valid(_combat):
		for actor in _combat.actors.values():
			if is_instance_valid(actor) and actor.model.axis_rig!=null:actor.model.axis_rig.cloth.set_scene_colliders(objects)


func _physics_process(_delta: float) -> void:
	if _player == null or _player.input_locked or not _ready_for_play:
		return
	var feet := _player.global_position - Vector3(0, 0.9, 0)
	apply_actions(Net.server().world3d_events.touch_segment(_previous_feet, feet))
	_previous_feet = feet


func _prepare_navigation() -> void:
	if is_instance_valid(_combat):
		_combat.free()
	_player.input_locked = true
	if is_instance_valid(_navigation):
		_navigation.free()
	_navigation = preload("res://scripts/world3d/world_navigation.gd").new()
	_navigation.agent_height=float(_player.get_meta("standing_height",1.9))
	add_child(_navigation)
	_player.navigation = _navigation
	_navigation.build(_map_root.get_meta("stream_library", []), _player.position)
	while not _navigation.ready_for_queries:
		await get_tree().process_frame
	Net.server().world3d_authority.mount(_player, _navigation, _map_ref())
	_combat = preload("res://scripts/world3d/world_combat.gd").new()
	add_child(_combat)
	_combat.setup(self)
	remote_players.refresh()


func _load_or_fail() -> Node:
	if is_instance_valid(Net.session().prepared_world3d):
		var prepared: Node = Net.session().prepared_world3d
		Net.session().prepared_world3d = null
		_map_path = Net.session().world3d_map_path
		_note_map(prepared)
		_use_map_spawn(prepared)
		return prepared
	var authored := str(Net.session().world3d_map_path)
	if authored != "":
		var loaded_authored := GltfMapIo.load_scene(authored)
		if loaded_authored == null:
			_status.text = "外部地图读取失败"
			return null
		_map_path = authored
		_note_map(loaded_authored)
		_use_map_spawn(loaded_authored)
		return loaded_authored
	var yard_dir := WorldMapPaths.cache_directory("p4_yard")
	var inn_dir := WorldMapPaths.cache_directory("p4_inn")
	if yard_dir.is_empty() or inn_dir.is_empty():
		_status.text = "没有工程外的 content_root，不能进入 3D 世界"
		return null
	var path := yard_dir.path_join("map.gltf")
	var inn_path := inn_dir.path_join("map.gltf")
	var docs = load("res://scripts/world3d/world_document.gd")
	var err: Error = docs.sample_yard(inn_path).save(path)
	if err != OK:
		_status.text = "外部地图写入失败"
		return null
	err = docs.make_inn(path).save(inn_path)
	if err != OK:
		_status.text = "外部地图写入失败"
		return null
	var loaded := GltfMapIo.load_scene(path)
	if loaded == null:
		_status.text = "外部地图读取失败"
		return null
	_map_path = path
	_use_map_spawn(loaded)
	return loaded


func _note_map(map_root: Node) -> void:
	var extras := GltfMapIo.extras_of(map_root)
	var name := str(extras.get("map_name", ""))
	_check_map = str(extras.get("rmmo_role", "")) == "check" or name.contains("白模")


func _use_map_spawn(map_root: Node) -> void:
	var spawn: Variant = GltfMapIo.extras_of(map_root).get("spawn", [])
	if typeof(spawn) != TYPE_ARRAY or (spawn as Array).size() < 3:
		return
	var current: Vector3 = Net.session().world3d_spawn
	if current != Vector3(0, 0.9, 4):
		return
	var coords: Array = spawn
	Net.session().world3d_spawn = Vector3(float(coords[0]), float(coords[1]), float(coords[2]))


func _add_collision(map_root: Node) -> void:
	Stream.sync(map_root, self, Net.session().world3d_spawn)


func _add_player() -> void:
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.set_script(load("res://scripts/world3d/world_player.gd"))
	body.map_ref = _map_ref()
	body.character = Net.session().active_character()
	var equipment: Array = Net.session().spawn_data.get("equipment", [])
	body.equipment_parts = preload("res://scripts/char/character_view_3d.gd").equipment_parts(str(body.character.gender), equipment, Net.server().item_catalog)
	body.position = Net.session().world3d_spawn
	var capsule := CollisionShape3D.new()
	capsule.name="CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	capsule.shape = shape
	body.add_child(capsule)
	var model := preload("res://scripts/char/character_model_3d.gd").create(str(body.character.gender), body.character.get("customization", {}), body.equipment_parts)
	model.name = "CharacterModel3D"
	model.position = Vector3(0, -0.9, 0)
	body.add_child(model)
	add_child(body)
	_player = body
	model.identity_shapes_changed.connect(_on_identity_shapes_changed)
	var rig := Node3D.new()
	rig.name = "FollowCamera"
	rig.set_script(load("res://scripts/world3d/third_person_camera.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 55.0
	rig.add_child(camera)
	add_child(rig)
	_camera = rig
	_refresh_player_clearance()
	_camera.exclude_body(_player.get_rid())
	_player.camera_path = _camera.get_path()
	_outline = preload("res://scripts/world3d/occlusion_outline.gd").new()
	add_child(_outline)
	_outline.bind(_player, camera)

func _refresh_player_clearance()->void:
	if not is_instance_valid(_player) or not is_instance_valid(_camera):return
	_camera.actor_height=preload("res://scripts/world3d/player_clearance.gd").apply(_player,_player.get_node("CharacterModel3D"))

## Perspective controllers must switch this before taking over camera/head pose.
## First-person/VR controllers own their movement; this does not simulate an HMD.
func set_camera_mode(mode:String)->bool:
	return is_instance_valid(_camera) and _camera.set_view_mode(mode)


func _add_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 32, 0)
	_sun.light_energy = 1.15
	_sun.light_color = Color(1.0, 0.97, 0.9)
	add_child(_sun)
	_sun.add_to_group("character_key_light")
	var env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.68, 0.78)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.72, 0.76, 0.82)
	_env.ambient_light_energy = 0.42
	env.environment = _env
	add_child(env)


func set_night(on: bool) -> void:
	_request_environment({"preset":"night" if on else "day"})

func _request_environment(changes: Dictionary) -> Dictionary:
	var server = Net.server()
	if not is_instance_valid(_weather) or not server.has_method("try_set_world3d_environment"): return {"ok":false,"error":"环境服务未就绪"}
	var result: Dictionary = server.try_set_world3d_environment(_map_ref(),changes)
	if result.get("ok",false): _weather.sky_poll = 0; _weather._process(0)
	return result

func _on_server_environment(config: Dictionary) -> void:
	_night = config.preset == "night"; _refresh_lamps()
	if is_instance_valid(_outline): _outline.configure(config)
	if is_instance_valid(_camera): _camera.bind_map(_map_root,config)

## Runtime weather changes are transient; editor/MCP author the map's initial weather.
func set_weather(kind: String, intensity := .7) -> Dictionary:
	var changes := {"weather":kind, "weather_intensity":intensity}
	var settings = preload("res://scripts/world3d/environment_settings.gd")
	var invalid: String = settings.Schema.validate(changes, settings.schema())
	if not invalid.is_empty(): return {"ok":false, "error":invalid}
	if not is_instance_valid(_weather): return {"ok":false, "error":"地图天气尚未就绪"}
	return _request_environment(changes)

func _apply_map_environment() -> void:
	var settings = preload("res://scripts/world3d/environment_settings.gd")
	var values: Dictionary = settings.resolve(GltfMapIo.extras_of(_map_root))
	settings.apply(values, _sun, _env)
	if not is_instance_valid(_weather):
		_weather = preload("res://scripts/world3d/weather_controller.gd").new()
		add_child(_weather)
		_weather.bind(_camera.camera, _sun, _env, _player)
		_weather.environment_changed.connect(_on_server_environment)
	var sky_server = Net.server()
	if sky_server.has_method("mount_world3d_sky"): sky_server.mount_world3d_sky(_map_ref(),_map_path)
	if sky_server.has_method("snapshot_world3d_sky"): _weather.bind_sky(_map_ref(),Callable(sky_server,"snapshot_world3d_sky").bind(_map_ref()))
	_weather.configure(values, true)
	values = _weather.values
	_night = values.preset == "night"
	if is_instance_valid(_outline): _outline.configure(values)
	if is_instance_valid(_camera):_camera.bind_map(_map_root,values)
	_refresh_lamps()

func _refresh_lamps() -> void:
	for lamp in _lamps:
		if lamp is OmniLight3D:
			(lamp as OmniLight3D).light_energy = 1.8 if _night else 0.0
	if _status != null and not _lamps.is_empty():
		var prefix := "检查用白模 · " if _check_map else ""
		_status.text = prefix + ("夜晚 · 路灯亮着" if _night else "白天 · 路灯关掉")


func _add_town_lamps(map_root: Node) -> void:
	var extras := GltfMapIo.extras_of(map_root)
	var raw: Variant = extras.get("lamps", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	var coords: Array = raw
	var i := 0
	while i + 2 < coords.size():
		var lamp := OmniLight3D.new()
		lamp.name = "TownLamp%d" % _lamps.size()
		lamp.position = Vector3(float(coords[i]), float(coords[i + 1]), float(coords[i + 2]))
		lamp.light_color = Color(1.0, 0.78, 0.48)
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		add_child(lamp)
		_lamps.append(lamp)
		i += 3


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_revive = Button.new()
	_revive.text = "返回出生点复活"
	_revive.position = Vector2(530, 80)
	_revive.visible = false
	_revive.pressed.connect(func():
		if _combat.respawn(): _revive.hide()
	)
	layer.add_child(_revive)
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.text = "正在读取外部地图…"
	layer.add_child(_status)
	if is_instance_valid(Net.session().editor_playtest): return
	var back := Button.new()
	back.text = "返回登录"
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.position = Vector2(-110, 12)
	back.pressed.connect(_leave)
	layer.add_child(back)
	if Net.session().editor_return:
		var edit := Button.new()
		edit.text = "返回编辑"
		edit.anchor_left = 0.5
		edit.anchor_right = 0.5
		edit.position = Vector2(0, 12)
		edit.pressed.connect(_back_to_editor)
		layer.add_child(edit)


func _pick(screen: Vector2) -> Dictionary:
	var camera := _camera.get_node("Camera3D") as Camera3D
	var origin := camera.project_ray_origin(screen)
	var end := origin + camera.project_ray_normal(screen) * 80.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = _camera.visual_exclusions()
	return get_world_3d().direct_space_state.intersect_ray(query)


func _apply_actor_view() -> void:
	var server = Net.server()
	if server == null or not server.has_method("try_world3d_chunk"):
		return
	var packet: Dictionary = server.try_world3d_chunk(_player.global_position.x, _player.global_position.z)
	if not bool(packet.get("ok", false)):
		return
	if _actor_host == null:
		_actor_host = Node3D.new()
		_actor_host.name = "ActorView"
		add_child(_actor_host)
	load("res://scripts/world3d/view_actors.gd").apply(_actor_host, packet.get("view", []))


func _apply_residency(budget: int = 0) -> void:
	if _map_root == null or _player == null:
		return
	Stream.sync(_map_root, self, _player.global_position, budget)


func _poll_warp() -> void:
	if _player == null or _map_path == "" or _player.input_locked:
		return
	for child in get_children():
		if str(child.get_meta("kind", "")) != "warp":
			continue
		var center: Vector3 = child.get_meta("center")
		if not Travel.near(_player.global_position, center, 1.2):
			continue
		var target := str(child.get_meta("target_path", ""))
		if target == _failed_warp:
			return
		var spawn: Array = child.get_meta("spawn", [])
		if spawn.size() != 3: return
		var destination := Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
		if not await transfer_map(target, destination): _failed_warp = target
		return
	_failed_warp = ""


func _map_ref() -> String:
	var authored := str(GltfMapIo.extras_of(_map_root).get("map_ref", ""))
	if preload("res://scripts/world3d/world_location.gd").map_ref_ok(authored):
		return authored
	return "prototype/map_" + _map_path.sha256_text().substr(0, 16)


func _talk() -> void:
	if furniture.active():
		furniture.stand();return
	if _player == null or _travel == null:
		return
	var bodies: Array = []
	for child in get_children():
		if child.has_meta("seat"):
			bodies.append(child)
	var closest: StaticBody3D
	var distance := 2.0
	for body in bodies:
		var center: Vector3 = body.get_meta("center")
		var flat := Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(center.x, center.z))
		if absf(_player.global_position.y - center.y) <= 1.0 and flat < distance:
			closest = body
			distance = flat
	if closest != null:
		if closest.has_meta("seat"):
			if not furniture.interact(closest):_status.text="无法使用这张椅子。"
			return
	var events = Net.server().world3d_events
	var id: String = events.nearest(_player)
	if not id.is_empty(): apply_actions(events.interact(id, _player))


func _mount_events() -> void:
	Net.server().world3d_events.mount(_map_ref(), _map_root.get_meta("stream_library", []), GltfMapIo.extras_of(_map_root).get("rmmo_records", []))


func _add_game_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_hud = load("res://scenes/ui/game_hud.tscn").instantiate()
	layer.add_child(_hud)
	_hud.bind_character(Net.session().active_character())
	_hud.bind_world_combat(self)
	var data: Dictionary = Net.session().spawn_data
	_hud.apply_combat_stats(data.get("combat", {}))
	_hud.apply_inventory_snapshot(data.get("inventory", []), int(data.get("gold", 0)))
	_hud.apply_equipment_snapshot(data.get("equipment", []), data.get("equipment_bonuses", {}))
	_hud.apply_quest_snapshot(data.get("quests", []))
	_hud.apply_skill_catalog(Net.server().snapshot_skill_catalog())
	_hud.apply_skill_book(data.get("skill_book", {}))
	_refresh_world_map()
	_status.position.y = 106


func apply_actions(actions: Array) -> void:
	for action in actions:
		match str(action.get("type", "")):
			"open_shop":
				if _hud != null:
					_hud.show_shop(str(action.get("shop_id", "")), str(action.get("title", "")), action.get("listings", []), int(action.get("gold", 0)), int(action.get("vendor_rep", -1)))
					_hud.apply_shop_buyback(action.get("buyback", []))
			"shop_buyback":
				if _hud != null: _hud.apply_shop_buyback(action.get("buyback", []))
			"facial_expression":remote_players.receive(action)
			"remote_spawn":remote_players.spawn(action.get("player",{}))
			"remote_despawn":remote_players.despawn(str(action.get("id",action.get("player_id",""))))
			"sit":
				if furniture.active():
					if not bool(action.get("on",false)):furniture.stand()
					continue
				if bool(action.get("on",false)):
					if _player._model.action not in ["sit_down_ground","sit_ground"]:_player.request_rest("sit_down_ground")
				elif _player._model.action in ["sit_down_ground","sit_ground"]:
					_player._begin_ground_exit()
			"player_died":
				furniture.cancel(true)
				cancel_sit_preparation()
				Net.server().sitting=false
				Net.server().awaiting_respawn = true
				_player.input_locked = true
				_player.velocity = Vector3.ZERO
				_player.click_target = null
				_player._route.clear()
				_player.get_node("CharacterModel3D").play("death", "front")
				_revive.show()
			"skill_cd":
				if _hud != null: _hud.note_skill_cooldown(str(action.skill_id), float(action.remaining), float(action.get("cooldown", 0)))
			"cast_start":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_start(action)
			"cast_update":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_update(action)
			"cast_end":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_end(action)
			"show_npc_dialogue":
				_status.text = str(action.get("body", ""))
				if _hud != null:
					_hud.show_npc_dialogue(str(action.get("npc_name", "")), str(action.get("body", "")), action.get("options", []))
			"system_message":
				_status.text = str(action.get("text", ""))
				if _hud != null:
					_hud.append_system(_status.text)
			"inventory_update":
				Net.session().spawn_data["inventory"] = action.get("items", [])
				Net.session().spawn_data["gold"] = action.get("gold", 0)
				if _hud != null:
					_hud.apply_inventory_snapshot(action.get("items", []), int(action.get("gold", 0)))
			"equipment_update":
				var equipment: Array = action.get("equipment", [])
				Net.session().spawn_data["equipment"] = equipment
				var gender := str(_player.character.gender)
				_player.get_node("CharacterModel3D").set_equipment(preload("res://scripts/char/character_view_3d.gd").equipment_parts(gender, equipment, Net.server().item_catalog))
				if _hud != null:
					_hud.apply_equipment_snapshot(equipment, action.get("bonuses", {}))
			"quest_update":
				if _hud != null:
					_hud.apply_quest_snapshot(Net.server().snapshot_quest_journal())
			"world3d_transfer":
				var loc = preload("res://scripts/world3d/world_location.gd").from_dictionary(action["location"])
				var warp := StaticBody3D.new()
				warp.set_meta("kind", "warp")
				warp.set_meta("center", _player.global_position)
				warp.set_meta("target_path", action["path"])
				warp.set_meta("spawn", [loc.position_m.x, loc.position_m.y + 0.9, loc.position_m.z])
				add_child(warp)
				_poll_warp()
				warp.queue_free()


func request_event_choice(option_id: String, option_index: int) -> void:
	apply_actions(Net.server().world3d_events.choice(option_id, option_index))

func request_shop_buy(shop_id: String, item_id: String, quantity: int = 1) -> void:
	apply_actions(Net.server().try_shop_buy(shop_id, item_id, quantity).get("actions", []))

func request_shop_sell(item_id: String, quantity: int = 1) -> void:
	apply_actions(Net.server().try_shop_sell(item_id, quantity).get("actions", []))

func request_shop_sell_junk() -> void:
	apply_actions(Net.server().try_shop_sell_junk().get("actions", []))

func request_shop_buyback(index: int) -> void:
	apply_actions(Net.server().try_shop_buyback(index).get("actions", []))

func request_shop_close() -> void:
	apply_actions(Net.server().try_shop_close().get("actions", []))


func request_equip_item(item_id: String, slot: String = "") -> void:
	apply_actions(Net.server().try_equip_item(item_id, slot).get("actions", []))


func request_unequip_item(slot: String) -> void:
	apply_actions(Net.server().try_unequip_item(slot).get("actions", []))


func _leave() -> void:
	if _camera != null and _camera.has_method("release_capture"):
		_camera.release_capture()
	Net.session().editor_return = false
	Net.session().go_login()


func _back_to_editor() -> void:
	if _camera != null and _camera.has_method("release_capture"):
		_camera.release_capture()
	Net.session().go_world_editor()


func request_use_skill(skill_id: String) -> void:
	var definition: Dictionary = Net.server().skill_catalog.get_skill(skill_id)
	if Net.server().combat_engine.skill_target_mode(definition) == "ground":
		_pending_ground_skill = skill_id
		_status.text = "点击地面选择施法位置。"
		return
	_combat.use_skill(skill_id)


func request_use_item(item_id: String) -> void:
	_combat.use_item(item_id)


func transfer_map(target: String, destination: Vector3, before_commit: Callable = Callable()) -> bool:
	if is_instance_valid(Net.session().editor_playtest): target = Net.session().editor_playtest.resolve_map(target)
	if _transfer_pending or not destination.is_finite() or target.is_empty(): return false
	if not Net.server().combat_stats.player_alive(): return false
	cancel_sit_preparation()
	if Net.server().sitting:apply_actions(Net.server().try_sit(false).get("actions",[]))
	furniture.cancel()
	_transfer_pending = true
	_combat._save_map_state()
	var combat_processing: bool = _combat.is_physics_processing()
	_combat.set_physics_process(false)
	var was_locked: bool = _player.input_locked
	_player.input_locked = true
	_status.text = "读取目标地图…"
	var loader = preload("res://scripts/world3d/map_loader.gd").new()
	_transfer_loader = loader
	loader.progress.connect(func(stage: String, done: int, total: int): _status.text = "%s %d/%d" % [stage, done, total])
	Net.session().add_child(loader)
	loader.start(target)
	var result: Array = await loader.finished
	_transfer_loader = null
	var prepared: Node = result[0]
	if prepared == null:
		_combat.set_physics_process(combat_processing)
		_transfer_pending = false
		_player.input_locked = was_locked
		_status.text = str(result[2])
		return false
	# Prepare and validate in an isolated physics world. The current map and
	# inventory stay intact until navigation and the destination capsule fit.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.disable_3d = true
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	stage.add_child(prepared)
	while not prepared.has_meta("stream_chunk"):
		Stream.sync(prepared, stage, destination, Stream.FRAME_BUDGET)
		await get_tree().process_frame
	var navigation = preload("res://scripts/world3d/world_navigation.gd").new()
	navigation.agent_height=float(_player.get_meta("standing_height",1.9))
	add_child(navigation)
	navigation.build(prepared.get_meta("stream_library", []), destination)
	while not navigation.ready_for_queries: await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var feet := destination - Vector3(0, 0.9, 0)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = float(_player.get_meta("standing_height",1.9))-.02
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, capsule.height/2+.02, 0))
	var fits: bool = navigation.near_surface(feet, 0.35, 0.4) and stage.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	# Dynamic actors are deliberately absent from static navigation/collision.
	# Check their authored occupancy before committing, including cached poses.
	var saved: Dictionary = Net.server().world3d_state.read_map(target.simplify_path())
	for spec in prepared.get_meta("stream_library", []):
		var data: Dictionary = spec.get("extras", {})
		if not bool(data.get("hostile", false)) and not bool(data.get("ally", false)): continue
		var bounds: AABB = spec.transform * spec.mesh.get_aabb()
		var actor_feet := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		var cached: Dictionary = saved.get("actors", {}).get(str(spec.uuid), {})
		if not cached.is_empty() and cached.get("signature", "") == _combat._signature(spec):
			if cached.get("stats", {}).is_empty() or int(cached.stats.get("hp", 0)) <= 0: continue
			actor_feet = cached.position - Vector3(0, 0.9, 0)
		if absf(actor_feet.y - feet.y) < 1.8 and Vector2(actor_feet.x - feet.x, actor_feet.z - feet.z).length() < 0.6: fits = false
	if not fits or (before_commit.is_valid() and not before_commit.call()):
		_combat.set_physics_process(combat_processing)
		navigation.free()
		viewport.queue_free()
		_transfer_pending = false
		_player.input_locked = was_locked
		_status.text = "目标出生点不可用，或操作条件已变化；保留当前地图。"
		return false
	# Commit after preparation. Save the outgoing mock map state before freeing it.
	_combat.free()
	for body in _map_root.get_meta("stream_bodies", {}).values():
		if is_instance_valid(body): body.free()
	_map_root.free()
	_navigation.free()
	for lamp in _lamps: lamp.free()
	_lamps.clear()
	Net.server().world3d_release_actors()
	if is_instance_valid(_actor_host): _actor_host.free()
	_actor_host = null
	_map_root = prepared
	prepared.reparent(self)
	for body in prepared.get_meta("stream_bodies", {}).values():
		if is_instance_valid(body): body.reparent(self)
	_navigation = navigation
	viewport.queue_free()
	_map_path = target
	Net.session().world3d_map_path = target
	Net.session().world3d_spawn = destination
	_player.global_position = destination
	_player.velocity = Vector3.ZERO
	_player.click_target = null
	_player._route.clear()
	_previous_feet = feet
	_player.map_ref = _map_ref()
	_player.navigation = navigation
	Net.server().world3d_authority.mount(_player, navigation, _map_ref())
	_combat = preload("res://scripts/world3d/world_combat.gd").new()
	add_child(_combat)
	_combat.setup(self)
	remote_players.refresh()
	_add_town_lamps(prepared)
	_note_map(prepared)
	_mount_events()
	_refresh_world_map()
	_apply_map_environment()
	await get_tree().physics_frame
	_player.input_locked = false
	_transfer_pending = false
	_status.text = "已进入目标地图。"
	return true


func request_pet_summon(id: String = "default") -> void:
	_combat.summons.pet_summon(id)

func request_pet_dismiss() -> void:
	_combat.summons.pet_dismiss()
