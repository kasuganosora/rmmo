extends SceneTree
## Isolate editor construction from map parsing. Reads the real asset catalog,
## but uses an empty in-memory document and never opens or saves the town.
class TimedEditor extends "res://scripts/world_editor/world_editor.gd":
	var startup:Dictionary={}
	func _ready()->void:
		var start:=Time.get_ticks_usec();super._ready();startup.total_ms=(Time.get_ticks_usec()-start)/1000.
	func _load_asset_scope()->void:
		var start:=Time.get_ticks_usec();super._load_asset_scope();startup.asset_scope_ms=(Time.get_ticks_usec()-start)/1000.
	func _rebuild()->void:
		var start:=Time.get_ticks_usec();super._rebuild();startup.rebuild_ms=(Time.get_ticks_usec()-start)/1000.
	func _hud()->void:
		var start:=Time.get_ticks_usec();super._hud();startup.hud_ms=(Time.get_ticks_usec()-start)/1000.
	func _apply_environment()->void:
		var start:=Time.get_ticks_usec();super._apply_environment();startup.environment_ms=(Time.get_ticks_usec()-start)/1000.
	func _refresh_palette()->void:
		var start:=Time.get_ticks_usec();super._refresh_palette();startup.palette_ms=(Time.get_ticks_usec()-start)/1000.

func _initialize()->void:call_deferred("run")
func run()->void:
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=preload("res://scripts/world3d/world_document.gd").new()
	session.world3d_editor_path="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
	var editor:=TimedEditor.new();editor._mcp_autostart=false
	editor.set_meta("profile_startup",true)
	editor._draft_directory=preload("res://scripts/world3d/map_paths.gd").cache_directory("startup_profile_drafts")
	root.add_child(editor);editor._safety.enabled=false
	editor.startup.workspace=editor.get_meta("startup_workspace",{})
	print("EDITOR_STARTUP ",JSON.stringify(editor.startup))
	if not OS.get_cmdline_user_args().is_empty():FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(editor.startup,"\t"))
	editor.queue_free()
	for i in 6:await process_frame
	session.world3d_editor_doc=null
	quit()
