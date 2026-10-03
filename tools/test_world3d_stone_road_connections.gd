extends "res://tools/test_world3d_road_connections.gd"
func bridge_spec() -> Dictionary:
	return super.bridge_spec().merged({"prefab_id":"stone_segmental","camber":.6},true)
