extends SceneTree
## No background opt-in and no preloaded server graph: the original autoload
## contract must finish before this main loop starts, including shader includes.
func _initialize() -> void:
	_check_ready.call_deferred()

func _check_ready() -> void:
	var server: Node = root.get_node("MockServer")
	var profile: Dictionary = server.get_meta("mock_server_preparation_profile", {})
	var ok := server.has_method("login") and server.is_processing()
	ok = ok and not server.has_meta("mock_server_preparation")
	ok = ok and not profile.get("background", true) and int(profile.get("scripts", 0)) > 200
	print("SYNC_MOCK_SERVER ", JSON.stringify({"ok": ok, "profile": profile}))
	quit(0 if ok else 1)
