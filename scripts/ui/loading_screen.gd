extends Control
const Net = preload("res://scripts/net/net.gd")
const MapFieldScript = preload("res://scripts/map/map_field.gd")

@onready var status_label: Label = %Status
@onready var bar: ProgressBar = %Bar

var _gate_failed: bool = false
var _gate_error: String = ""
var progress_history: Array = []
var _map_loader: Node
var _cancelled := false

func _stage(label: String, done: int = -1, total: int = 0) -> void:
	status_label.text = label + (" %d / %d" % [done,total] if total>0 else "…")
	bar.visible = true
	bar.modulate.a = 1.0 if total>0 else 0.0
	bar.max_value = maxi(total,1)
	bar.value = maxi(done,0)
	if progress_history.is_empty() or progress_history[-1].label!=status_label.text:
		progress_history.append({"label":status_label.text,"done":done,"total":total,"time_ms":Time.get_ticks_msec()})

func transition_visual() -> Control:
	var visual:=Control.new()
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual.add_child($Bg.duplicate())
	visual.add_child($Center.duplicate())
	return visual


func _ready() -> void:
	bar.modulate.a = 0.0
	Net.session().last_loading_profile={"started_ms":Time.get_ticks_msec()}
	var mode: String = str(Net.session().loading_mode)
	Net.session().world3d_loading = mode == "world3d_preview" or (mode != "transfer" and Net.session().use_world3d())
	ResourceLoader.load_threaded_request(Net.session().world_scene(),"PackedScene")
	if mode == "world3d_preview":
		if not Net.session().has_active_character():
			status_label.text = "请先选择角色，试玩不会生成替代人物"
			_show_transfer_fail_actions()
		elif Net.session().has_world3d_snapshot():
			_prepare_world3d()
		else:
			Net.session().selected_character = Net.session().active_character()
			_run_enter()
		return
	if mode == "transfer":
		_run_transfer()
	else:
		_run_enter()


func _asset_manager() -> Node:
	return get_node_or_null("/root/AssetManager")


func _exit_tree() -> void:
	_cancelled = true
	if is_instance_valid(_map_loader):
		_map_loader.cancel()
	## Drop the enter_world_ready subscription so a stale (freed) loading screen
	## never receives the signal after the scene is swapped away.
	if Net.server() != null and Net.server().enter_world_ready.is_connected(_on_enter_ready):
		Net.server().enter_world_ready.disconnect(_on_enter_ready)


func _run_enter() -> void:
	var ch: Dictionary = Net.session().selected_character
	status_label.text = "正在进入世界：%s…" % str(ch.get("name", ""))
	Net.server().enter_world_ready.connect(_on_enter_ready)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if Net.session().world3d_loading:
		if not Net.server().has_method("enter_world3d"):
			status_label.text = "当前服务器尚不支持三维世界"
			_show_transfer_fail_actions()
			return
		Net.server().enter_world3d(int(Net.session().selected_character.get("id", -1)))
	else:
		Net.server().enter_world(int(Net.session().selected_character.get("id", -1)))


func _run_transfer() -> void:
	## Map warp: MockServer.try_transfer already switched pack -- do NOT call enter_world.
	var spawn: Dictionary = Net.session().spawn_data
	var message: String = str(spawn.get("transfer_message", "")).strip_edges()
	var map_id: String = str(spawn.get("map_id", "")).strip_edges()


	if message != "":
		if message.begins_with("进入"):
			status_label.text = message
		else:
			status_label.text = "进入%s…" % message
	elif map_id != "":
		status_label.text = "正在进入 %s…" % map_id
	else:
		status_label.text = "正在切换地图…"

	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	var pack_path: String = _resolve_spawn_pack_path(spawn)
	var cell_v: Variant = spawn.get("cell", {})
	var spawn_cell := Vector2i(-1, -1)
	if typeof(cell_v) == TYPE_DICTIONARY:
		spawn_cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	_stage("准备地图通行数据")
	await get_tree().process_frame
	var sv = Net.server()
	# A successful server warp already loaded collision. Editor playtests do
	# not set bags_cleared and must reload even when their draft path is unchanged.
	if sv != null and sv.has_method("load_world_pack") and not bool(spawn.get("bags_cleared",false)):
		if not bool(sv.load_world_pack(pack_path, map_id, spawn_cell)):
			_gate_error = "无法加载地图碰撞：%s" % pack_path
			status_label.text = _gate_error
			bar.value = 0
			_show_transfer_fail_actions()
			return
	var ok: bool = await _bake_spawn_map()
	if not is_instance_valid(self):
		return
	if not ok:
		status_label.text = _gate_error if _gate_error != "" else "地图资源加载失败"
		bar.value = 0
		_show_transfer_fail_actions()
		return
	_stage("场景准备就绪")
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	Net.session().loading_mode = ""
	_stage("正在进入城镇")
	Net.session().go_world()


func _show_transfer_fail_actions() -> void:
	bar.visible=false
	Net.session().map_bake={}
	## Avoid infinite stuck loading: offer return to character select.
	if has_node("FailActions"):
		return
	var row := HBoxContainer.new()
	row.name = "FailActions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -80
	row.offset_bottom = -40
	var back := Button.new()
	back.text = "返回角色选择"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func():
		Net.session().loading_mode = ""
		Net.session().go_character_select()
	)
	row.add_child(back)


func _on_enter_ready(ok: bool, message: String, spawn: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	if not ok:
		status_label.text = message
		_show_transfer_fail_actions()
		return
	Net.session().spawn_data = spawn.duplicate(true)
	var spawn_ch: Variant = spawn.get("character", null)
	if typeof(spawn_ch) == TYPE_DICTIONARY and not (spawn_ch as Dictionary).is_empty():
		Net.session().selected_character = (spawn_ch as Dictionary).duplicate(true)
	status_label.text = message if message.strip_edges() != "" else "正在准备地图…"
	if Net.session().world3d_loading:
		_prepare_world3d()
		return
	var bake_ok: bool = await _bake_spawn_map()
	if not is_instance_valid(self):
		return
	if not bake_ok:
		status_label.text = _gate_error if _gate_error != "" else "资源加载失败"
		_show_transfer_fail_actions()
		return
	Net.session().loading_mode = ""
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	_stage("正在进入城镇")
	Net.session().go_world()


func _prepare_world3d() -> void:
	if not Net.session().has_active_character():
		status_label.text = "缺少角色外观，请重新选择角色"
		_show_transfer_fail_actions()
		return
	_stage("读取三维地图")
	var cancel := Button.new()
	cancel.text = "取消加载"
	cancel.position = Vector2(24, 24)
	cancel.pressed.connect(func():
		_cancelled = true
		if is_instance_valid(_map_loader):
			_map_loader.cancel()
		Net.session().clear_prepared_world3d()
		if Net.session().editor_return:
			Net.session().go_world_editor()
		else:
			Net.session().go_character_select()
	)
	add_child(cancel)
	await get_tree().process_frame
	if _cancelled:
		return
	var Loader = preload("res://scripts/world3d/map_loader.gd")
	var requested: String = Net.session().world3d_map_path
	if requested.is_empty():
		requested = str(ProjectSettings.get_setting("rmmo/world3d_start_map", ""))
	var path: String = Loader.resolve_path(requested)
	if path.is_empty() or not FileAccess.file_exists(path):
		status_label.text = "三维地图不存在，请检查启动地图设置"
		_show_transfer_fail_actions()
		return
	_map_loader = Loader.new()
	Net.session().add_child(_map_loader)
	_map_loader.finished.connect(_on_world3d_loaded)
	_map_loader.progress.connect(func(stage: String, done: int, total: int): _stage(stage, done, total))
	_map_loader.start(path)


func _on_world3d_loaded(scene: Node, path: String, error: String) -> void:
	if _cancelled:
		if scene != null:
			scene.free()
		return
	if scene == null:
		status_label.text = error
		_show_transfer_fail_actions()
		return
	Net.session().clear_prepared_world3d()
	Net.session().prepared_world3d = scene
	Net.session().world3d_map_path = path
	Net.session().loading_mode = ""
	_stage("准备三维场景和附近碰撞")
	Net.session().go_world()


func _resolve_spawn_pack_path(spawn: Dictionary) -> String:
	var am: Node = _asset_manager()
	var pack_path: String = str(spawn.get("pack_path", "")).strip_edges()
	# An explicit local pack is authoritative, including an editor draft with
	# the same content_id as an installed release.
	if pack_path != "" and FileAccess.file_exists(pack_path.path_join("pack.json")):
		return pack_path
	if pack_path == "" and am != null and am.has_method("start_map_pack_ref"):
		pack_path = str(am.start_map_pack_ref())
	var content_id: String = str(spawn.get("content_id", "")).strip_edges()
	if am != null and am.has_method("resolve_map_pack_path"):
		var resolved := ""
		if content_id != "":
			resolved = str(am.resolve_map_pack_path(content_id))
		if resolved == "" or not FileAccess.file_exists("%s/pack.json" % resolved):
			# Prefer spawn.pack_path when content_id has no local pack yet
			var via_path := str(am.resolve_map_pack_path(pack_path))
			if FileAccess.file_exists("%s/pack.json" % via_path):
				return via_path
			var glob_path := ProjectSettings.globalize_path(via_path) if via_path.begins_with("res://") else via_path
			if FileAccess.file_exists("%s/pack.json" % glob_path):
				return via_path
		if resolved != "" and (FileAccess.file_exists("%s/pack.json" % resolved) or (
				resolved.begins_with("res://") and FileAccess.file_exists("%s/pack.json" % ProjectSettings.globalize_path(resolved)))):
			return resolved
		return str(am.resolve_map_pack_path(pack_path))
	return pack_path


func _ensure_gate_resources(pack_path: String) -> bool:
	_gate_failed = false
	_gate_error = ""
	var am: Node = _asset_manager()
	if am == null:
		# No autoload — legacy path continues without Gate phase.
		status_label.text = "跳过资源门控（无 AssetManager）…"
		return true
	var deps: Array = []
	if am.has_method("collect_map_pack_deps"):
		deps = am.collect_map_pack_deps(pack_path)
	if deps.is_empty():
		deps = [pack_path]
	var err: Error = OK
	var done:=0
	for dependency in deps:
		_stage("检查地图资源",done,deps.size())
		await get_tree().process_frame
		var result: Error=am.ensure_many([dependency],"校验素材",true)
		if result!=OK:err=result
		done+=1
	_stage("检查地图资源",done,deps.size())
	# Hard-fail only if map pack itself is missing
	var pack_ok := true
	if am.has_method("has"):
		# Filesystem pack path or content map_pack
		pack_ok = bool(am.has(pack_path))
		if not pack_ok and am.has_method("resolve_map_pack_path"):
			var resolved: String = str(am.resolve_map_pack_path(pack_path))
			pack_ok = FileAccess.file_exists("%s/pack.json" % resolved)
			if not pack_ok:
				var glob := ProjectSettings.globalize_path(resolved)
				pack_ok = FileAccess.file_exists("%s/pack.json" % glob)
	if err != OK and not pack_ok:
		_gate_failed = true
		_gate_error = "地图包缺失：%s" % pack_path
		return false
	if _gate_failed and not pack_ok:
		return false
	status_label.text = "资源就绪，开始绘制地图…"
	return true



func _bake_spawn_map() -> bool:
	## Report completed work within named stages, never pretend they are time percentages.
	var spawn: Dictionary = Net.session().spawn_data
	var pack_path: String = _resolve_spawn_pack_path(spawn)
	# Keep session spawn pack_path normalized for World.
	spawn["pack_path"] = pack_path
	Net.session().spawn_data = spawn

	if not await _ensure_gate_resources(pack_path):
		return false

	_stage("读取地图数据")
	Net.session().map_bake = {}
	var mf: Node2D = MapFieldScript.new()
	mf.pack_path = pack_path
	var server=Net.server()
	if server!=null and server.get("_map_pack")!=null:
		var loaded=server._map_pack
		var same_path:=ProjectSettings.globalize_path(str(loaded.pack_dir)).replace("\\","/").rstrip("/")==ProjectSettings.globalize_path(pack_path).replace("\\","/").rstrip("/")
		var map_id:=str(spawn.get("map_id",""))
		if same_path and (map_id.is_empty() or map_id==str(loaded.map_id)):
			mf.prepared_pack=loaded.render_snapshot()
	mf.skip_ready_rebuild = true
	mf.visible = false
	add_child(mf)
	var progress := func(_v: float) -> void:
		var state: Dictionary=mf.loading_state
		match str(state.get("phase","map")):
			"map":_stage("读取地图数据")
			"overview":_stage("准备地图预览")
			"visible":_stage("准备附近场景",int(state.done),int(state.total))
			"ready":_stage("附近场景准备就绪")
	await mf.rebuild_async(progress)
	if not is_instance_valid(self):
		return false
	if mf.pack == null or not mf._stream_ready or not mf._chunk_stream_module_logic.visible_ready():
		_gate_error = "地图烘焙失败：%s" % pack_path
		mf.queue_free()
		return false
	Net.session().map_bake = mf.export_bake()
	mf.queue_free()
	await get_tree().process_frame
	if not is_instance_valid(self):
		return false
	return true
