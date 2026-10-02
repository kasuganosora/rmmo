extends Node
## Client-side session state shared across UI and world scenes.

const SCENE_LOGIN := "res://scenes/login.tscn"
const SCENE_CHAR := "res://scenes/character_select.tscn"
const SCENE_CREATE := "res://scenes/character_create.tscn"
const SCENE_LOADING := "res://scenes/loading.tscn"
const SCENE_WORLD := "res://scenes/world.tscn"
const SCENE_WORLD_3D := "res://scenes/world_3d.tscn"
const SCENE_EDITOR := "res://scenes/world_editor.tscn" # Legacy alias; 2D editor retired.
const SCENE_WORLD_EDITOR := "res://scenes/world_editor.tscn"

var username: String = ""
var server_address: String = "127.0.0.1:7777"
var characters: Array = []
var selected_character: Dictionary = {}
var spawn_data: Dictionary = {}
## "enter" (char select) or "transfer" (map warp via loading). Empty = enter.
var loading_mode: String = ""
## Loading-phase MapField bake (pack + ground/upper/radar atlas). Consumed on world enter.
var map_bake: Dictionary = {}
## After create, select screen focuses this character id (-1 = none).
var pending_select_id: int = -1
## UI hotbar bindings survive Loading/World scene changes: "page:slot" -> {kind,id}.
var hotbar_bindings: Dictionary = {}
var hotbar_initialized: bool = false
var hotbar_profile_key: String = ""
## Last hotbar page index (0..5).
var hotbar_page: int = 0
## Return to content editor after playtest.
var editor_return: bool = false
var editor_pack_root: String = ""
var editor_map_id: String = ""
var last_loading_progress: Array = []
var _world_transition_active: bool = false
var _loading_transition_active: bool = false
var last_loading_profile: Dictionary = {}
## External glTF chosen for this visit. Empty rebuilds the sample yard.
## The Axel whitebox is a subsystem check, not a shipped map, and is never chosen here.
var world3d_map_path: String = ""
var world3d_spawn := Vector3(0, 0.9, 4)
## Talk and gather flags for the 3D profile. Survives a map reload. Not the 2D save.
var world3d_switches: Dictionary = {}
## Editor document kept across playtest. Not written to the 2D save.
var world3d_editor_doc = null
var world3d_editor_path := ""
var prepared_world3d: Node = null
var world3d_loading := false
var world3d_requested := false
var pending_world3d_playtest := false
var editor_playtest: Node


func world_scene() -> String:
	return SCENE_WORLD_3D if world3d_loading else SCENE_WORLD


func use_world3d() -> bool:
	return world3d_requested or str(ProjectSettings.get_setting("rmmo/startup_profile", "world2d")) == "world3d"


func clear_prepared_world3d() -> void:
	if is_instance_valid(prepared_world3d):
		prepared_world3d.free()
	prepared_world3d = null


func world3d_travel():
	var travel = load("res://scripts/world3d/world_travel.gd").new()
	travel.switches = world3d_switches
	return travel

func go_login() -> void:
	if is_instance_valid(editor_playtest): editor_playtest.stop(); return
	world3d_requested = false
	pending_world3d_playtest = false
	clear_prepared_world3d()
	selected_character = {}
	spawn_data = {}
	loading_mode = ""
	map_bake = {}
	pending_select_id = -1
	hotbar_bindings = {}
	hotbar_initialized = false
	hotbar_profile_key = ""
	hotbar_page = 0
	get_tree().change_scene_to_file(SCENE_LOGIN)

func go_character_select() -> void:
	if is_instance_valid(editor_playtest): editor_playtest.stop(); return
	get_tree().change_scene_to_file(SCENE_CHAR)

func go_character_create() -> void:
	get_tree().change_scene_to_file(SCENE_CREATE)

func go_loading() -> void:
	if _loading_transition_active or _world_transition_active:return
	_loading_transition_active=true
	var cover:=CanvasLayer.new();cover.name="LoadingTransition";cover.layer=100
	var shade:=ColorRect.new();shade.color=Color(.05,.06,.09,1)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.modulate.a=0.0
	add_child(cover);cover.add_child(shade)
	var previous=get_tree().current_scene
	var player=previous.get_node_or_null("Player") if previous!=null else null
	var locked: bool=player.input_locked if player!=null else false
	if player!=null:player.input_locked=true
	await get_tree().process_frame
	await get_tree().process_frame
	var fade:=create_tween()
	fade.tween_property(shade,"modulate:a",1.0,.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await fade.finished
	var error:=get_tree().change_scene_to_file(SCENE_LOADING)
	if error==OK:
		await get_tree().scene_changed
	else:
		if is_instance_valid(player):player.input_locked=locked
		push_error("Cannot open loading scene: %s"%error)
	cover.queue_free();_loading_transition_active=false

func go_world() -> void:
	if _world_transition_active:return
	_world_transition_active=true
	last_loading_profile["handoff_ms"]=Time.get_ticks_msec()
	var previous=get_tree().current_scene
	var cover:=CanvasLayer.new()
	cover.name="WorldTransition"
	cover.layer=100
	add_child(cover)
	var visual: Control
	if previous!=null and previous.has_method("transition_visual"):
		last_loading_progress=previous.progress_history.duplicate(true)
		visual=previous.transition_visual()
	else:
		var background:=ColorRect.new()
		background.color=Color(.05,.06,.09,1)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visual=background
	cover.add_child(visual)
	var destination := world_scene()
	var status:=ResourceLoader.load_threaded_get_status(destination)
	while status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status=ResourceLoader.load_threaded_get_status(destination)
	var scene: PackedScene=ResourceLoader.load_threaded_get(destination) if status==ResourceLoader.THREAD_LOAD_LOADED else load(destination)
	var error:=get_tree().change_scene_to_packed(scene) if scene!=null else ERR_CANT_OPEN
	if error!=OK:
		cover.queue_free();_world_transition_active=false
		if is_instance_valid(previous) and previous.has_method("_show_transfer_fail_actions"):
			previous.status_label.text="无法进入场景，请返回后重试"
			previous._show_transfer_fail_actions()
		return
	await get_tree().scene_changed
	last_loading_profile["world_ready_ms"]=Time.get_ticks_msec()
	var world=get_tree().current_scene
	while is_instance_valid(world) and world.has_method("is_world_ready") and not world.is_world_ready():
		await get_tree().process_frame
	if not is_instance_valid(world):
		cover.queue_free()
		_world_transition_active = false
		return
	var player=world.get_node_or_null("Player")
	if player!=null:player.input_locked=true
	# Keep the loading visual through the first rendered world frame, including
	# shader compilation and HUD setup, instead of exposing a blank scene frame.
	if DisplayServer.get_name()=="headless":await get_tree().process_frame
	else:await RenderingServer.frame_post_draw
	last_loading_profile["first_frame_ms"]=Time.get_ticks_msec()
	# A slow first draw must not count as elapsed animation time and swallow
	# the whole fade on its first tick.
	await get_tree().process_frame
	await get_tree().process_frame
	var fade:=create_tween()
	fade.tween_property(visual,"modulate:a",0.0,.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await fade.finished
	cover.queue_free()
	if is_instance_valid(player) and get_tree().current_scene==world:player.input_locked=false
	_world_transition_active=false
	last_loading_profile["finished_ms"]=Time.get_ticks_msec()


func go_world_3d() -> void:
	world3d_requested = true
	if not has_active_character():
		pending_world3d_playtest = true
		get_tree().change_scene_to_file(SCENE_CHAR if not username.is_empty() else SCENE_LOGIN)
		return
	loading_mode = "world3d_preview"
	go_loading()

func go_world_editor() -> void:
	if is_instance_valid(editor_playtest): editor_playtest.stop(); return
	get_tree().change_scene_to_file(SCENE_WORLD_EDITOR)

func go_content_editor() -> void:
	go_world_editor()

func active_character() -> Dictionary:
	## Single source of truth for HUD / world: spawn snapshot, else selection.
	var spawn_ch: Variant = spawn_data.get("character", null)
	if typeof(spawn_ch) == TYPE_DICTIONARY and not (spawn_ch as Dictionary).is_empty():
		if selected_character.is_empty() or int(selected_character.get("id", -1)) == int(spawn_ch.get("id", -2)):
			return (spawn_ch as Dictionary).duplicate(true)
	if not selected_character.is_empty():
		return selected_character.duplicate(true)
	return {}


func has_active_character() -> bool:
	var character := active_character()
	return str(character.get("gender", "")) in ["male", "female", "young_male", "young_female"] and character.get("customization", {}) is Dictionary

func has_world3d_snapshot() -> bool:
	var character := active_character()
	var snapshot: Dictionary = spawn_data.get("character", {})
	return has_active_character() and not snapshot.is_empty() and int(character.get("id", -1)) == int(snapshot.get("id", -2)) and spawn_data.has("equipment") and spawn_data.get("world_mode") == "world3d"
