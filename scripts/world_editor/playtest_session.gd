extends Node
## Keep the editor alive; run a disposable document in its own physics world and
## a private in-memory server. No gameplay state is restored by guessing fields
## on the real server: the real server is never used by the preview.
const Net = preload("res://scripts/net/net.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
class PreviewServer extends "res://scripts/net/mock_server.gd":
	func _ready() -> void: _init_combat_layers()

var editor: Node3D
var phase := "idle"
var last_error := ""
var directory := ""
var map_path := ""
var source_path := ""
var spawn := Vector3.ZERO
var world: Node3D
var viewport: SubViewport
var server: Node
var _stage: SubViewport
var _overlay: CanvasLayer
var _session_before := {}
var _source_server: Node
var _override_before: Node
var _source_mode: int
var _editor_mode: int
var _mcp_mode: int
var _layers: Array = []
var _generation := 0
var _caption: Label

func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS
func active() -> bool: return phase in ["preparing","loading","running","stopping"]
func state() -> Dictionary:
	return {"ok":true,"phase":phase,"active":active(),"error":last_error,"source_path":source_path,"temporary_path":map_path,"spawn":[spawn.x,spawn.y,spawn.z]}
func start(position: Variant = null) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	editor._finish_edits()
	if DisplayServer.get_name() == "headless": return {"ok":false,"error":"试玩需要图形渲染器；请连接图形编辑器的 3D MCP"}
	var raw: Variant = editor._authoring.settings.spawn if position == null else position
	var error := preload("res://scripts/world3d/document_schema.gd").validate(raw,preload("res://scripts/world3d/document_schema.gd").vector(-100000,100000))
	if not error.is_empty(): return {"ok":false,"error":error}
	for record in editor._doc.records:
		if record.get("kind") == "asset" and not Paths.allowed(str(record.get("asset_path",""))): return {"ok":false,"error":"模型路径不在授权内容根内"}
	var character: Dictionary = Net.session().active_character()
	if character.is_empty(): character = {"id":-100,"name":"试玩角色","class_id":"adventurer","gender":"male","level":1,"customization":{}}
	if not preload("res://scripts/char/character_model_3d.gd").source_available(str(character.gender),character.get("customization",{})): return {"ok":false,"error":"试玩角色资源缺失，请先配置角色资源包"}
	var token := Crypto.new().generate_random_bytes(12).hex_encode()
	var path := Paths.cache_directory("playtests").path_join(token)
	if not Paths.allowed(path): return {"ok":false,"error":"试玩缓存路径不在内容根内"}
	var clone := Doc.new(); clone.apply_recovery(editor._doc.recovery_snapshot())
	if not clone.map_meta.has("map_ref"): clone.map_meta.map_ref = "prototype/map_"+editor._path.sha256_text().substr(0,16)
	var result := clone.save(path.path_join("map.gltf"))
	if result != OK:
		if DirAccess.dir_exists_absolute(path): Io._remove_tree(path)
		return {"ok":false,"error":"创建试玩副本失败："+error_string(result)}
	directory = path; map_path = path.path_join("map.gltf"); source_path = editor._path
	spawn = Vector3(raw[0],raw[1],raw[2]); phase = "preparing"; last_error = ""; _generation += 1
	_overlay = CanvasLayer.new(); _overlay.layer = 100; add_child(_overlay)
	var blocker := ColorRect.new(); blocker.color = Color(.08,.1,.14,.9); blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _overlay.add_child(blocker)
	var progress := VBoxContainer.new(); progress.position = Vector2(32,32); blocker.add_child(progress)
	var label := Label.new(); label.text = "正在准备临时地图与出生位置…"; progress.add_child(label)
	var cancel := Button.new(); cancel.text = "取消试玩"; cancel.pressed.connect(stop); progress.add_child(cancel)
	_prepare.call_deferred(clone,character,_generation)
	return state()

func resolve_map(path: String) -> String:
	return map_path if path.replace("\\","/").simplify_path().to_lower() == source_path.replace("\\","/").simplify_path().to_lower() else path

func _prepare(clone, character: Dictionary, generation: int) -> void:
	if generation != _generation or not active(): return
	_stage = SubViewport.new(); _stage.own_world_3d = true; _stage.disable_3d = true; add_child(_stage)
	var host := Node3D.new(); _stage.add_child(host)
	var scene: Node3D = clone.build(); host.add_child(scene)
	Stream.sync(scene,host,spawn+Vector3(0,.9,0))
	await get_tree().physics_frame; await get_tree().process_frame
	if generation != _generation or not active(): return
	var space := host.get_world_3d().direct_space_state
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn+Vector3(0,.15,0),spawn-Vector3(0,.2,0)))
	var query := PhysicsShapeQueryParameters3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = .3; capsule.height = preload("res://scripts/world3d/player_clearance.gd").NAV_HEIGHT
	query.shape = capsule; query.transform = Transform3D(Basis.IDENTITY,spawn+Vector3(0,capsule.height/2+.01,0)); query.margin = .001
	if ground.is_empty() or ground.normal.y < .7 or absf(ground.position.y-spawn.y) > .12 or not space.intersect_shape(query,1).is_empty():
		_fail("出生点没有支撑或角色空间被占用，请重新选择地面位置"); return
	_stage.free(); _stage = null
	_enter(character,generation)

func _enter(character: Dictionary, generation: int) -> void:
	var session := Net.session()
	_source_server = Net.server(); _source_mode = _source_server.process_mode; _override_before = Net._server_override
	for property in session.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or property.name == "editor_playtest": continue
		var value: Variant = session.get(property.name)
		_session_before[property.name] = value
		if value is Dictionary or value is Array: session.set(property.name,value.duplicate(true))
	session.editor_playtest = self
	session.prepared_world3d = null; session.world3d_switches = {}; session.world3d_loading = false
	session.world3d_requested = true; session.editor_return = true
	session.world3d_map_path = map_path; session.world3d_spawn = spawn+Vector3(0,.9,0)
	session.selected_character = character.duplicate(true)
	server = PreviewServer.new(); server.name = "PlaytestServer"; add_child(server)
	server.item_catalog._by_id = _source_server.item_catalog._by_id.duplicate(true)
	server.shop_catalog._shops = _source_server.shop_catalog._shops.duplicate(true)
	server.skill_catalog._by_id = _source_server.skill_catalog._by_id.duplicate(true)
	if not _session_before.selected_character.is_empty():
		server.inventory.restore_session_state(_source_server.inventory.capture_session_state())
		server.equipment.restore_session_state(_source_server.equipment.capture_session_state())
	server._session_user = "__playtest__"; server._session_character_id = str(character.id)
	server._accounts = {"__playtest__":{"password":"","characters":[character.duplicate(true)]}}
	server.combat_stats.reset_player(int(character.get("level",1)))
	session.spawn_data = {"character":character.duplicate(true),"world_mode":"world3d","inventory":server.inventory.snapshot(),"gold":server.inventory.get_gold(),"equipment":server.equipment.snapshot(),"equipment_bonuses":server.equipment.total_bonuses(),"combat":server.combat_stats.snapshot_player_stats(),"quests":server.quest_journal.snapshot(),"skill_book":server.snapshot_skill_book()}
	_source_server.process_mode = Node.PROCESS_MODE_DISABLED
	Net.set_server(server)
	_editor_mode = editor.process_mode; editor.process_mode = Node.PROCESS_MODE_DISABLED
	if editor._mcp != null: _mcp_mode = editor._mcp.process_mode; editor._mcp.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in editor.get_children():
		if child is CanvasLayer: _layers.append([child,child.visible]); child.visible = false
	for child in _overlay.get_children(): child.free()
	var container := SubViewportContainer.new(); container.stretch = true; container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _overlay.add_child(container)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.handle_input_locally = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(viewport)
	world = load("res://scenes/world_3d.tscn").instantiate(); phase = "loading"; viewport.add_child(world)
	var banner := HBoxContainer.new(); banner.position = Vector2(340,8); _overlay.add_child(banner)
	_caption = Label.new(); _caption.text = "临时试玩 · 正式地图与角色进度不受影响"; banner.add_child(_caption)
	var exit_button := Button.new(); exit_button.text = "结束试玩，返回编辑器"; exit_button.pressed.connect(stop); banner.add_child(exit_button)
	var deadline := Time.get_ticks_msec()+60000
	while is_instance_valid(world) and not world.is_world_ready() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if generation != _generation or not active(): return
	if not is_instance_valid(world) or not world.is_world_ready() or world._player == null: _fail("试玩场景加载失败或超时，编辑状态已保留"); return
	phase = "running"; editor._status.text = "临时试玩中"

func stop() -> Dictionary:
	if not active(): return state()
	phase = "stopping"; _generation += 1
	_finish.call_deferred()
	return state()

func _fail(message: String) -> void:
	last_error = message; _generation += 1
	_finish()
	phase = "failed"
	editor._status.text = message

func _finish() -> void:
	if is_instance_valid(world):
		if world._camera != null: world._camera.release_capture()
		world.free()
	world = null
	if is_instance_valid(_overlay): _overlay.free()
	_overlay = null; viewport = null
	if is_instance_valid(_stage): _stage.free()
	_stage = null
	if server != null:
		Net._server_override = _override_before
		_source_server.process_mode = _source_mode
		server.free(); server = null
		var session := Net.session(); session.clear_prepared_world3d()
		for key in _session_before: session.set(key,_session_before[key])
		session.editor_playtest = null; _session_before.clear()
		editor.process_mode = _editor_mode
		if editor._mcp != null: editor._mcp.process_mode = _mcp_mode
		for pair in _layers:
			if is_instance_valid(pair[0]): pair[0].visible = pair[1]
		_layers.clear()
	if not directory.is_empty() and Paths.allowed(directory) and directory.get_base_dir() == Paths.cache_directory("playtests"):
		Io._remove_tree(directory)
	directory = ""; map_path = ""; phase = "idle"
	if is_instance_valid(editor._status): editor._status.text = "已结束试玩，编辑状态已恢复"
