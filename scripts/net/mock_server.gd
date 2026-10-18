extends "res://scripts/net/mock_server_api.gd"
## In-process server. Domain modules own their state and implementation.
## mock_server_api.gd is generated from their @server-* declarations.

func _ready() -> void:
	if preload("res://scripts/net/connection_config.gd").startup().mode != "mock":
		set_process(false)
		return
	_init_combat_layers()
	_load_pack(start_map_pack_path())

func _process(delta: float) -> void:
	if not has_meta("profile_frame"):
		_tick_frame(delta)
		return
	var began := Time.get_ticks_usec()
	_tick_frame(delta)
	set_meta("frame_timing", {"frame": Engine.get_process_frames(), "begin_us": began,
		"end_us": Time.get_ticks_usec(), "ms": (Time.get_ticks_usec() - began) / 1000.0})

func _exit_tree() -> void:
	world3d_release_actors()
