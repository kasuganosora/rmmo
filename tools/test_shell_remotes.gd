extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Mock = load("res://scripts/net/mock_server.gd")
	var Coll = load("res://tools/test_remote_patrol_collision.gd")
	var srv = Mock.new()
	get_root().add_child(srv)
	await process_frame
	srv.player_cell = Vector2i(10, 10)
	srv.map_collision = Coll.new()
	srv._remote_players.clear()
	srv._ensure_shell_remotes(1)
	var snap: Array = srv.snapshot_remote_players()
	print("remotes=", snap.size(), " ", snap)
	if snap.is_empty():
		push_error("FAIL no shell remotes")
		quit(1)
	var d: Dictionary = snap[0]
	if int(d.get("wander_radius", 0)) <= 0:
		push_error("FAIL no wander")
		quit(1)
	# patrol once
	var moved := false
	for _i in range(30):
		for a in srv._tick_remote_patrol(3.0):
			if str(a.get("type", "")) == "remote_move":
				moved = true
				break
		if moved:
			break
	print("moved=", moved)
	if not moved:
		push_error("FAIL no move")
		quit(1)
	print("PASS shell remotes")
	quit(0)
