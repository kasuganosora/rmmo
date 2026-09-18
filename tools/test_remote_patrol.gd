extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Mock = load("res://scripts/net/mock_server.gd")
	var Coll = load("res://tools/test_remote_patrol_collision.gd")
	var srv = Mock.new()
	get_root().add_child(srv)
	srv.player_cell = Vector2i(10, 10)
	srv.map_collision = Coll.new()
	await process_frame
	var r: Dictionary = srv.try_remote_debug_spawn("巡逻测试")
	if not bool(r.get("ok", false)):
		push_error("FAIL spawn")
		quit(1)
	var rid := str(r.get("remote_id", ""))
	var d0: Dictionary = srv.get_remote_player(rid)
	if int(d0.get("wander_radius", 0)) <= 0:
		push_error("FAIL no wander_radius")
		quit(1)
	var moved := false
	var start: Variant = d0.get("cell", {})
	for _i in range(50):
		var acts: Array = srv._tick_remote_patrol(3.0)
		for a in acts:
			if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "remote_move":
				moved = true
				break
		if moved:
			break
	var d1: Dictionary = srv.get_remote_player(rid)
	print("start=", start, " end=", d1.get("cell", {}), " moved=", moved)
	if not moved:
		push_error("FAIL: remote never moved")
		quit(1)
	print("PASS remote patrol")
	quit(0)
