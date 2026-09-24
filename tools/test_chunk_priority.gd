extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Field = load("res://scripts/map/map_field.gd")
	var field = Field.new()
	field.skip_ready_rebuild = true
	root.add_child(field)
	field.grid_width = 256
	field.grid_height = 256
	field.tile_size = 48
	field._obs_cell = Vector2i(200,200)
	field._obs_facing = 2
	field._chunk_queue.assign([Vector2i(0,0),Vector2i(1,1),Vector2i(12,12)])
	field._refresh_chunk_set()
	assert(not field._chunk_queue.has(Vector2i(0,0)), "teleport discards obsolete queued region")
	assert(not field._chunk_queue.has(Vector2i(1,1)), "teleport discards obsolete queued neighbor")
	assert(field._chunk_queue[0] == Vector2i(12,12), "current observer chunk precedes distant prefetch")
	print("PASS teleport queue pruning and observer-first HD loading")
	field.free()
	quit(0)
