extends SceneTree
## Camera-relative motion stays in meters and does not depend on frame rate.

const Motion = preload("res://scripts/world3d/world_motion.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var north: Vector3 = Motion.wish_direction(0.0, Vector2(0, 1))
	failed += _expect(north.distance_to(Vector3(0, 0, -1)) <= 0.001, "yaw 0 forward is north")
	var east: Vector3 = Motion.wish_direction(0.0, Vector2(1, 0))
	failed += _expect(east.distance_to(Vector3(1, 0, 0)) <= 0.001, "yaw 0 strafe is east")
	var pitched: Vector3 = Motion.wish_direction(0.0, Vector2(0, 1))
	failed += _expect(absf(pitched.y) <= 0.001, "pitch is not part of wish direction")
	var diagonal: Vector3 = Motion.wish_direction(0.0, Vector2(1, 1))
	failed += _expect(absf(diagonal.length() - 1.0) <= 0.001, "diagonal is normalized")
	failed += _expect(Motion.same_distance(2, 1.0 / 60.0, 1, 1.0 / 30.0, Motion.WALK_MPS), "30 and 60 fps cover the same distance")
	var start := Vector3(1.25, 0.2, -3.5)
	var stepped := Motion.integrate(start, north, Motion.WALK_MPS, 0.5)
	failed += _expect(absf(stepped.x - 1.25) <= 0.001 and absf(stepped.y - 0.2) <= 0.001, "integration keeps the unused axes")
	failed += _expect(absf(stepped.z - (start.z - Motion.WALK_MPS * 0.5)) <= 0.001, "half a second walks 0.8 m north")
	print("test_world3d_motion: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_motion: FAIL %s" % label)
		return 1
	return 0
