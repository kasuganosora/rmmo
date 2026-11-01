extends RefCounted
## Public map-local addresses. Parsing never resolves a file or grants entry.
## Scalar arrays preserve float64 until an explicit runtime-coordinate adapter.
const MAX_ADDRESS_LENGTH := 512
const MAX_PACK_LENGTH := 128
const MAX_COORDINATE_LENGTH := 96
const MAX_MAP_NUMBER := "9223372036854775807"
## This protocol envelope retains the existing 1 mm address roundtrip budget.
## It is not a promise that engine Vector3/physics support these large values.
const MAX_COORDINATE_M := 1.0e12


static func normalize_number(value: String) -> Dictionary:
	if value.is_empty() or value.length() > 19:
		return _error("invalid_map_number", "地图编号须为不超过 19 位的非负十进制整数。")
	for i in value.length():
		var c := value.unicode_at(i)
		if c < 48 or c > 57:
			return _error("invalid_map_number", "地图编号只能包含十进制数字。")
	var first := 0
	while first < value.length() - 1 and value[first] == "0":
		first += 1
	var canonical := value.substr(first)
	if canonical.length() == MAX_MAP_NUMBER.length() and canonical > MAX_MAP_NUMBER:
		return _error("invalid_map_number", "地图编号超过 64 位有符号整数上限。")
	return {"ok": true, "map_number": canonical}


static func parse(value: String) -> Dictionary:
	if value.length() > MAX_ADDRESS_LENGTH:
		return _error("invalid_address", "世界地址过长。")
	var parts := value.strip_edges().split(":", true)
	if parts.size() != 3 or not _pack_ok(parts[0]):
		return _error("invalid_address", "地址格式应为资源包ID:地图编号:x,y,z。")
	var number := normalize_number(parts[1])
	if not number.ok:
		return _error("invalid_address", number.message)
	var coordinates := parts[2].split(",", true)
	if coordinates.size() != 3:
		return _error("invalid_address", "地址需要恰好三个坐标。")
	var position: Array = []
	var decimal := RegEx.new()
	decimal.compile("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")
	for raw: String in coordinates:
		var token := raw.strip_edges()
		if token.is_empty() or token.length() > MAX_COORDINATE_LENGTH or decimal.search(token) == null:
			return _error("invalid_address", "坐标须为有效十进制数。")
		var magnitude := _decimal_magnitude(token)
		if not magnitude.ok:
			return _error(magnitude.reason_code, "坐标超过 ±1000000000000 米，或太小而无法保留非零值。")
		# Validate the decimal order before to_float(), whose implementation
		# warns on extreme exponents even when this is ordinary invalid input.
		var coordinate := 0.0 if magnitude.zero else str(magnitude.token).to_float() * pow(10.0, magnitude.scale_exponent)
		if not is_finite(coordinate):
			return _error("invalid_address", "坐标不能是无穷大或非数值。")
		if absf(coordinate) > MAX_COORDINATE_M:
			return _error("coordinate_out_of_range", "坐标超出 ±1000000000000 米的地址范围。")
		# A finite zero must not hide an underflowing nonzero mantissa.
		if coordinate == 0.0 and _nonzero_mantissa(token):
			return _error("invalid_address", "坐标太小，转换会丢失非零值。")
		position.append(0.0 if coordinate == 0.0 else coordinate)
	return _success(parts[0], number.map_number, position)


static func format_address(pack_id: String, map_number: String, position_m: Array) -> Dictionary:
	if not _pack_ok(pack_id):
		return _error("invalid_address", "资源包ID只能包含 ASCII 字母、数字和下划线。")
	var number := normalize_number(map_number)
	if not number.ok:
		return _error("invalid_address", number.message)
	var checked := _position(position_m)
	if not checked.ok:
		return checked
	return _success(pack_id, number.map_number, checked.position_m)


## Returns the actual capsule's bottom, including its authored centre offset.
## The position is a point only: support/surface/readiness remain caller-owned.
static func feet_from_body(body: CharacterBody3D) -> Dictionary:
	var capsule := _capsule_offset(body)
	if not capsule.ok:
		return capsule
	var centre := body.global_position
	var offset: Array = capsule.offset_m
	return {"ok": true, "anchor_kind": "feet", "position_m": [float(centre.x) + offset[0], float(centre.y) + offset[1], float(centre.z) + offset[2]]}


## Does not move the body. The caller must validate the point before adoption.
static func body_position_from_feet(body: CharacterBody3D, feet: Array) -> Dictionary:
	var point := _position(feet)
	if not point.ok:
		return point
	var capsule := _capsule_offset(body)
	if not capsule.ok:
		return capsule
	var offset: Array = capsule.offset_m
	var result: Array = []
	for axis in 3:
		var coordinate: float = point.position_m[axis] - offset[axis]
		if not is_finite(coordinate):
			return _error("invalid_address", "转换后的角色位置超出有效范围。")
		result.append(coordinate)
	return {"ok": true, "anchor_kind": "body_origin", "position_m": result}


static func _pack_ok(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_PACK_LENGTH:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95):
			return false
	return true


static func _nonzero_mantissa(token: String) -> bool:
	for i in token.length():
		var c := token.unicode_at(i)
		if c == 101 or c == 69:
			break
		if c >= 49 and c <= 57:
			return true
	return false


static func _decimal_magnitude(token: String) -> Dictionary:
	var parts := token.to_lower().split("e", true)
	var mantissa: String = parts[0].trim_prefix("+").trim_prefix("-")
	var dot := mantissa.find(".")
	var integral_digits := mantissa.length() if dot < 0 else dot
	var digits := mantissa.replace(".", "")
	var first := 0
	while first < digits.length() and digits[first] == "0":
		first += 1
	if first == digits.length():
		return {"ok": true, "zero": true}
	var exponent := 0
	if parts.size() == 2:
		var raw: String = parts[1]
		var negative := raw.begins_with("-")
		raw = raw.trim_prefix("+").trim_prefix("-")
		while raw.length() > 1 and raw.begins_with("0"):
			raw = raw.substr(1)
		if raw.length() > 4:
			return {"ok": false, "reason_code": "invalid_address" if negative else "coordinate_out_of_range"}
		exponent = raw.to_int() * (-1 if negative else 1)
	var order := exponent + integral_digits - first - 1
	var significand := digits.substr(first)
	var normalized := ("-" if token.begins_with("-") else "") + significand[0]
	if significand.length() > 1:
		normalized += "." + significand.substr(1)
	# Godot's decimal decoder can underflow an intermediate for long fractional
	# mantissas near the normal/subnormal boundary. Scale in two finite steps.
	var scale_exponent := mini(0, order + 280)
	normalized += "e" + str(order - scale_exponent)
	# Normalize scale before conversion, and reject huge exponents without
	# the engine warning that a direct String.to_float() would produce.
	return {"ok": order >= -324 and order <= 12, "reason_code": "coordinate_out_of_range" if order > 12 else "invalid_address", "zero": false, "token": normalized, "scale_exponent": scale_exponent}


static func _position(value: Array) -> Dictionary:
	if value.size() != 3:
		return _error("invalid_address", "位置需要恰好三个坐标。")
	var result: Array = []
	for item: Variant in value:
		if not (item is int or item is float) or not is_finite(float(item)):
			return _error("invalid_address", "位置只能包含三个有限数值。")
		var scalar := float(item)
		if absf(scalar) > MAX_COORDINATE_M:
			return _error("coordinate_out_of_range", "坐标超出 ±1000000000000 米的地址范围。")
		result.append(0.0 if scalar == 0.0 else scalar)
	return {"ok": true, "position_m": result}


static func _success(pack_id: String, map_number: String, position: Array) -> Dictionary:
	var encoded := PackedStringArray()
	for scalar: float in position:
		# full_precision avoids the default JSON display precision. No Vector3
		# conversion occurs; the bounded protocol preserves its 1 mm tolerance.
		encoded.append("0" if scalar == 0.0 else JSON.stringify(scalar, "", true, true).trim_suffix(".0"))
	return {"ok": true, "pack_id": pack_id, "map_number": map_number, "position_m": position, "address": "%s:%s:%s" % [pack_id, map_number, ",".join(encoded)]}


static func _capsule_offset(body: CharacterBody3D) -> Dictionary:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return _error("invalid_anchor", "角色尚未进入运行场景。")
	var collider := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.disabled or not collider.shape is CapsuleShape3D:
		return _error("invalid_anchor", "角色需要启用的直立胶囊碰撞形状。")
	var owners := body.get_shape_owners()
	if owners.size() != 1 or body.shape_owner_get_shape_count(owners[0]) != 1 or body.shape_owner_get_owner(owners[0]) != collider:
		return _error("invalid_anchor", "多个碰撞形状无法确定唯一脚点。")
	var shape := collider.shape as CapsuleShape3D
	var pose := collider.global_transform
	if not pose.is_finite() or not body.global_transform.is_finite() or not is_finite(shape.height) or not is_finite(shape.radius) or shape.radius <= 0.0 or shape.height < shape.radius * 2.0:
		return _error("invalid_anchor", "胶囊尺寸或变换无效。")
	var axes := pose.basis
	var scale_y := axes.y.length()
	if scale_y <= 0.0 or not is_equal_approx(axes.x.length(), scale_y) or not is_equal_approx(axes.z.length(), scale_y) or axes.determinant() <= 0.0:
		return _error("invalid_anchor", "脚点转换不支持非均匀或镜像缩放。")
	var basis := axes.scaled(Vector3.ONE / scale_y)
	if not basis.y.is_equal_approx(Vector3.UP) or absf(basis.x.dot(basis.y)) > 0.00001 or absf(basis.z.dot(basis.y)) > 0.00001 or absf(basis.x.dot(basis.z)) > 0.00001:
		return _error("invalid_anchor", "脚点转换只支持直立胶囊。")
	var centre := body.global_position
	return {"ok": true, "offset_m": [float(pose.origin.x) - float(centre.x), float(pose.origin.y) - float(centre.y) - float(shape.height) * float(scale_y) * 0.5, float(pose.origin.z) - float(centre.z)]}


static func _error(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason_code": reason, "message": message}
