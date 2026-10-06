extends SceneTree

class ResolverScreen extends "res://scripts/ui/loading_screen.gd":
	func _ready() -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Pack = load("res://scripts/editor/domain/content_pack.gd")
	var pack = Pack.new()
	pack.new_blank("playtest_path_regression", "Path regression", 8, 8)
	assert(pack.save_dir())
	var screen = load("res://scenes/loading.tscn").instantiate()
	screen.set_script(ResolverScreen)
	root.add_child(screen)
	var explicit := str(pack.root)
	var resolved: String = screen._resolve_spawn_pack_path({"pack_path": explicit, "content_id": "default"})
	assert(resolved == explicit, "Explicit editor pack must win over installed content_id")
	assert(screen._resolve_spawn_pack_path({"pack_path": ProjectSettings.globalize_path(explicit), "content_id": "default"}) == ProjectSettings.globalize_path(explicit))
	screen.free()
	print("PASS explicit editor pack path survives same-id installed release")
	quit(0)
