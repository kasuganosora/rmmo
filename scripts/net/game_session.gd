extends Node
## Client-side session state shared across UI and world scenes.

const SCENE_LOGIN := "res://scenes/login.tscn"
const SCENE_CHAR := "res://scenes/character_select.tscn"
const SCENE_CREATE := "res://scenes/character_create.tscn"
const SCENE_LOADING := "res://scenes/loading.tscn"
const SCENE_WORLD := "res://scenes/world.tscn"
const SCENE_EDITOR := "res://scenes/content_editor.tscn"

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
## Last hotbar page index (0..1).
var hotbar_page: int = 0
## Return to content editor after playtest.
var editor_return: bool = false
var editor_pack_root: String = ""
var editor_map_id: String = ""

func go_login() -> void:
	selected_character = {}
	spawn_data = {}
	loading_mode = ""
	map_bake = {}
	pending_select_id = -1
	hotbar_bindings = {}
	hotbar_page = 0
	get_tree().change_scene_to_file(SCENE_LOGIN)

func go_character_select() -> void:
	get_tree().change_scene_to_file(SCENE_CHAR)

func go_character_create() -> void:
	get_tree().change_scene_to_file(SCENE_CREATE)

func go_loading() -> void:
	get_tree().change_scene_to_file(SCENE_LOADING)

func go_world() -> void:
	get_tree().change_scene_to_file(SCENE_WORLD)


func go_content_editor() -> void:
	get_tree().change_scene_to_file(SCENE_EDITOR)

func active_character() -> Dictionary:
	## Single source of truth for HUD / world: spawn snapshot, else selection.
	var spawn_ch: Variant = spawn_data.get("character", null)
	if typeof(spawn_ch) == TYPE_DICTIONARY and not (spawn_ch as Dictionary).is_empty():
		return (spawn_ch as Dictionary).duplicate(true)
	if not selected_character.is_empty():
		return selected_character.duplicate(true)
	return {}
