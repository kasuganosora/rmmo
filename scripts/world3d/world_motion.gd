extends RefCounted
## Camera-relative ground motion in meters per second. Positions stay decimal.

const WALK_MPS := 1.6
const RUN_MPS := 4.0
const STOP_M := 0.05


static func horizontal_basis(yaw: float) -> Dictionary:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return {"forward": forward, "right": right}


## input.x is strafe right, input.y is forward. Pitch is ignored.
static func wish_direction(yaw: float, input: Vector2) -> Vector3:
	var basis := horizontal_basis(yaw)
	var wish: Vector3 = basis.right * input.x + basis.forward * input.y
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	elif wish.length_squared() > 0.0001:
		wish = wish.normalized()
	else:
		wish = Vector3.ZERO
	return wish


static func integrate(position: Vector3, wish: Vector3, speed_mps: float, dt: float) -> Vector3:
	if dt <= 0.0 or not is_finite(dt):
		return position
	return position + wish * speed_mps * dt


static func approach(position: Vector3, target: Vector3, speed_mps: float, dt: float) -> Vector3:
	var flat := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if flat.length() <= STOP_M:
		return Vector3(target.x, position.y, target.z)
	return position + flat.normalized() * minf(flat.length(), maxf(0.0, speed_mps * dt))


static func same_distance(steps_a: int, dt_a: float, steps_b: int, dt_b: float, speed_mps: float) -> bool:
	var wish := Vector3(0.0, 0.0, -1.0)
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	for _i in steps_a:
		a = integrate(a, wish, speed_mps, dt_a)
	for _j in steps_b:
		b = integrate(b, wish, speed_mps, dt_b)
	return a.distance_to(b) <= 0.001
