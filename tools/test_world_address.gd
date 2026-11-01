extends SceneTree
const Address = preload("res://scripts/world3d/world_address.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _run() -> void:
	var basic := Address.parse("default:000123:30,5,100")
	_check(basic.ok and basic.map_number == "123" and basic.pack_id == "default", "canonical identity")
	_check(basic.position_m == [30.0, 5.0, 100.0], "meter position")
	_check(basic.address == "default:123:30,5,100", "compact integral coordinates")
	_check(Address.parse(basic.address).address == basic.address, "canonical idempotence")
	_check(Address.normalize_number("9223372036854775807").ok, "int64 maximum")
	_check(not Address.normalize_number("9223372036854775808").ok, "int64 overflow")
	_check(Address.normalize_number("000").map_number == "0", "zero number")
	for value: String in ["", "-1", "+1", "1.0", "1e2", " 1", "1 ", "１", "12345678901234567890"]:
		_check(not Address.normalize_number(value).ok, "invalid number " + value)
	for value: String in ["", "default:1", "default:1:1,2", "default:1:1,2,3,4", "default:1:1,2,3:4", "default::1,2,3", ":1:1,2,3", "默认:1:1,2,3", "a/b:1:1,2,3", "a.b:1:1,2,3", "a-b:1:1,2,3", "default:1:1,,3", "default:1:NaN,2,3", "default:1:Inf,2,3", "default:1:-Infinity,2,3", "default:1:1x,2,3", "default:1:1e,2,3", "default:1:0x1,2,3", "default:1:1e999,2,3", "default:1:1e-999,2,3", "default:1:.00001e-999,2,3", "default:1:1 2,2,3", "default:1:1，2，3"]:
		_check(not Address.parse(value).ok, "invalid address " + value)
	_check(not Address.parse("a".repeat(129) + ":1:0,0,0").ok, "pack length bound")
	_check(not Address.parse("default:1:" + "0".repeat(600) + ",0,0").ok, "address length bound")
	_check(not Address.parse("default:1:" + "0".repeat(97) + ",0,0").ok, "coordinate length bound")
	var signs := Address.parse(" default:0:-0,+0.0,-0e12 ")
	_check(signs.ok and signs.address == "default:0:0,0,0", "negative zero normalization")
	_check(Address.parse("default:0:0e9999999999999999999999999,0e-999999999999999999999,0").ok, "zero mantissa does not overflow")
	_check(Address.parse("default:0:0.00000000000000000001e32,0,0").ok, "compensating decimal exponent remains in range")
	_check(not Address.parse("default:0:1e-324,0,0").ok, "smallest decimal rounds to zero")
	_check(Address.parse("default:0:1000000000000,-1000000000000,0").ok, "coordinate envelope boundary")
	_check(Address.parse("default:0:1000000000001,0,0").reason_code == "coordinate_out_of_range", "coordinate envelope positive overflow")
	_check(Address.parse("default:0:0,-1000000000001,0").reason_code == "coordinate_out_of_range", "coordinate envelope negative overflow")
	_check(Address.parse("default:0:1e999,0,0").reason_code == "coordinate_out_of_range", "huge exponent rejects without engine warning")
	_check(Address.format_address("default", "0", [1e13, 0, 0]).reason_code == "coordinate_out_of_range", "structured coordinate envelope")
	var decimals := Address.parse("default:1:-32.001, +.5, 1.e2")
	_check(decimals.ok and decimals.position_m == [-32.001, 0.5, 100.0], "negative decimal exponent whitespace")
	_check(Address.parse("A_b9:1:0,0,0").ok, "pack case remains valid")
	_check(Address.parse("A_b9:1:0,0,0").pack_id == "A_b9", "pack case retained")
	for scalar: float in [0.1, -0.00000000000000123456789012345, 123456789012.125, 16777217.125, 1.2345678901234567, 2.2250738585072014e-308, 1.0e-320, 5.0e-324, 1.0e12]:
		var formatted := Address.format_address("default", "001", [scalar, -scalar, 0.0])
		_check(formatted.ok, "format finite %.17f" % scalar)
		var parsed := Address.parse(formatted.address)
		_check(parsed.ok and absf(parsed.position_m[0] - scalar) <= 0.001 and absf(parsed.position_m[1] + scalar) <= 0.001, "millimeter roundtrip " + formatted.address)
	var random := RandomNumberGenerator.new()
	random.seed = 160601
	for i in 256:
		var scalar := random.randf_range(1.0, 9.0) * pow(10.0, random.randi_range(-300, 11))
		var formatted := Address.format_address("default", "1", [scalar, -scalar, 0.0])
		var parsed := Address.parse(formatted.address)
		_check(parsed.ok and absf(parsed.position_m[0] - scalar) <= 0.001 and absf(parsed.position_m[1] + scalar) <= 0.001, "sampled millimeter roundtrip " + formatted.address)
	for coordinates: Array in [[], [1, 2], [1, 2, 3, 4], [true, 2, 3], ["1", 2, 3], [NAN, 2, 3], [INF, 2, 3], [9223372036854775807, 2, 3]]:
		_check(not Address.format_address("default", "1", coordinates).ok, "invalid structured position " + str(coordinates))
	_check(not Address.format_address("默认", "1", [0, 0, 0]).ok, "invalid structured pack")
	_check(not Address.format_address("default", "-1", [0, 0, 0]).ok, "invalid structured number")
	_check(not Address.feet_from_body(null).ok, "missing body")
	var body := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.2
	capsule.radius = 0.3
	collider.shape = capsule
	collider.position.y = 0.2
	body.add_child(collider)
	_check(not Address.feet_from_body(body).ok, "detached body")
	root.add_child(body)
	body.global_position = Vector3(10, 8.9, -20)
	body.rotation.y = 0.75
	var feet := Address.feet_from_body(body)
	_check(feet.ok and absf(feet.position_m[1] - 8.0) < 0.00001 and feet.anchor_kind == "feet", "tall capsule offset preserves feet")
	var back := Address.body_position_from_feet(body, feet.position_m)
	_check(back.ok and absf(back.position_m[1] - float(body.global_position.y)) < 0.00001, "capsule body roundtrip")
	var original := body.global_transform
	var destination := Address.body_position_from_feet(body, [5.0, 6.0, 7.0])
	_check(destination.ok and absf(destination.position_m[1] - 6.9) < 0.00001, "target feet conversion")
	_check(body.global_transform == original, "conversion has no side effects")
	capsule.height = 1.8
	collider.position.y = 0.9
	body.global_position = Vector3(4, 2, 9)
	feet = Address.feet_from_body(body)
	_check(feet.ok and absf(feet.position_m[1] - 2.0) < 0.00001, "feet-origin editor walk capsule")
	body.scale = Vector3(1, 2, 1)
	_check(not Address.feet_from_body(body).ok, "reject nonuniform scale")
	body.scale = Vector3.ONE
	body.rotation.x = 0.3
	_check(not Address.feet_from_body(body).ok, "reject tilted capsule")
	body.rotation.x = 0.0
	collider.disabled = true
	_check(not Address.feet_from_body(body).ok, "reject disabled shape")
	collider.disabled = false
	var other := CollisionShape3D.new()
	other.shape = SphereShape3D.new()
	body.add_child(other)
	_check(not Address.feet_from_body(body).ok, "reject ambiguous shapes")
	other.free()
	collider.shape = BoxShape3D.new()
	_check(not Address.feet_from_body(body).ok, "reject unsupported shape")
	body.free()
	print("WORLD_ADDRESS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
