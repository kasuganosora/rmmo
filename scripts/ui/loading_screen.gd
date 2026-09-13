extends Control
const Net = preload("res://scripts/net/net.gd")
const MapFieldScript = preload("res://scripts/map/map_field.gd")

@onready var status_label: Label = %Status
@onready var bar: ProgressBar = %Bar

var _gate_failed: bool = false
var _gate_error: String = ""


func _ready() -> void:
	bar.value = 0
	var mode: String = str(Net.session().loading_mode)
	if mode == "transfer":
		_run_transfer()
	else:
		_run_enter()


func _asset_manager() -> Node:
	return get_node_or_null("/root/AssetManager")


func _run_enter() -> void:
	var ch: Dictionary = Net.session().selected_character
	status_label.text = "正在进入世界：%s…" % str(ch.get("name", ""))
	Net.server().enter_world_ready.connect(_on_enter_ready)
	bar.value = 5
	await get_tree().create_timer(0.15).timeout
	bar.value = 8
	Net.server().enter_world(int(Net.session().selected_character.get("id", -1)))


func _run_transfer() -> void:
	## Map warp: MockServer.try_transfer already switched pack -- do NOT call enter_world.
	var spawn: Dictionary = Net.session().spawn_data
	var message: String = str(spawn.get("transfer_message", "")).strip_edges()
	var map_id: String = str(spawn.get("map_id", "")).strip_edges()
	var bags_cleared := bool(spawn.get("bags_cleared", false))

	# Phase 1: acknowledge cleanup (bags/remotes already cleared server-side).
	status_label.text = "清理上一张地图状态…"
	bar.value = 3
	await get_tree().create_timer(0.08).timeout
	if bags_cleared:
		status_label.text = "地面掉落已留在旧图 · 准备进入新图"
		bar.value = 6
		await get_tree().create_timer(0.1).timeout

	if message != "":
		if message.begins_with("进入"):
			status_label.text = message
		else:
			status_label.text = "进入%s…" % message
	elif map_id != "":
		status_label.text = "正在进入 %s…" % map_id
	else:
		status_label.text = "正在切换地图…"

	bar.value = 8
	await get_tree().create_timer(0.06).timeout
	var ok: bool = await _bake_spawn_map()
	if not ok:
		status_label.text = _gate_error if _gate_error != "" else "地图资源加载失败"
		bar.value = 0
		_show_transfer_fail_actions()
		return
	status_label.text = "即将进入…"
	bar.value = 100
	await get_tree().create_timer(0.12).timeout
	Net.session().loading_mode = ""
	Net.session().go_world()


func _show_transfer_fail_actions() -> void:
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
	if not ok:
		status_label.text = message
		await get_tree().create_timer(1.2).timeout
		Net.session().loading_mode = ""
		Net.session().go_character_select()
		return
	Net.session().spawn_data = spawn.duplicate(true)
	var spawn_ch: Variant = spawn.get("character", null)
	if typeof(spawn_ch) == TYPE_DICTIONARY and not (spawn_ch as Dictionary).is_empty():
		Net.session().selected_character = (spawn_ch as Dictionary).duplicate(true)
	status_label.text = message if message.strip_edges() != "" else "正在准备地图…"
	bar.value = 10
	var bake_ok: bool = await _bake_spawn_map()
	if not bake_ok:
		status_label.text = _gate_error if _gate_error != "" else "资源加载失败，返回角色选择…"
		await get_tree().create_timer(1.4).timeout
		Net.session().loading_mode = ""
		Net.session().go_character_select()
		return
	bar.value = 100
	Net.session().loading_mode = ""
	await get_tree().create_timer(0.12).timeout
	Net.session().go_world()


func _resolve_spawn_pack_path(spawn: Dictionary) -> String:
	var am: Node = _asset_manager()
	var pack_path: String = str(spawn.get("pack_path", "res://demo_map")).strip_edges()
	if pack_path == "":
		pack_path = "res://demo_map"
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
		bar.value = 30
		return true
	var deps: Array = []
	if am.has_method("collect_map_pack_deps"):
		deps = am.collect_map_pack_deps(pack_path)
	if deps.is_empty():
		deps = [pack_path]
	status_label.text = "拉取地图包…"
	bar.value = 5
	if not am.gate_progress.is_connected(_on_gate_progress):
		am.gate_progress.connect(_on_gate_progress)
	var err: Error = am.ensure_many(deps, "校验素材", true)
	if am.gate_progress.is_connected(_on_gate_progress):
		am.gate_progress.disconnect(_on_gate_progress)
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
	bar.value = 35
	status_label.text = "资源就绪，开始绘制地图…"
	return true



func _on_gate_progress(phase: String, frac: float, label: String) -> void:
	status_label.text = label
	# Resource phase 5–35%
	bar.value = 5.0 + clampf(frac, 0.0, 1.0) * 30.0
	if phase == "error":
		_gate_failed = true
		_gate_error = label


func _bake_spawn_map() -> bool:
	## Resource Gate (5–35%) then heavy MapField paint + radar (35–95%).
	var spawn: Dictionary = Net.session().spawn_data
	var pack_path: String = _resolve_spawn_pack_path(spawn)
	# Keep session spawn pack_path normalized for World.
	spawn["pack_path"] = pack_path
	Net.session().spawn_data = spawn

	if not _ensure_gate_resources(pack_path):
		return false

	status_label.text = "正在烘焙地图与雷达…"
	Net.session().map_bake = {}

	var mf: Node2D = MapFieldScript.new()
	mf.pack_path = pack_path
	mf.skip_ready_rebuild = true
	add_child(mf)
	var progress := func(v: float) -> void:
		bar.value = 35.0 + clampf(v, 0.0, 1.0) * 60.0
	await mf.rebuild_async(progress)
	if mf.pack == null:
		_gate_error = "地图烘焙失败：%s" % pack_path
		mf.queue_free()
		return false
	Net.session().map_bake = mf.export_bake()
	var atlas_tex = Net.session().map_bake.get("radar_atlas_tex", null)
	var sc = float(Net.session().map_bake.get("radar_atlas_scale", 0.5))
	if atlas_tex != null:
		status_label.text = "雷达图集就绪 (%.2fx %dx%d)" % [
			sc, atlas_tex.get_width(), atlas_tex.get_height()
		]
	mf.queue_free()
	await get_tree().process_frame
	bar.value = 95
	return true
