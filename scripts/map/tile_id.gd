extends RefCounted
## Tile ID helpers for classic 48px tilemap packs (tilemap_pack_v1).

const TILE_ID_B := 0
const TILE_ID_C := 256
const TILE_ID_D := 512
const TILE_ID_E := 768
const TILE_ID_A5 := 1536
const TILE_ID_A1 := 2048
const TILE_ID_A2 := 2816
const TILE_ID_A3 := 4352
const TILE_ID_A4 := 5888
const TILE_ID_MAX := 8192

## MV tileset flags: dirs blocked + higher (star). Other bits (bush/boat/…) are preserved.
const FLAG_DOWN := 0x01
const FLAG_LEFT := 0x02
const FLAG_RIGHT := 0x04
const FLAG_UP := 0x08
const FLAG_DIRS := 0x0F
const FLAG_HIGHER := 0x10
const PASS_O := 0
const PASS_X := 1
const PASS_STAR := 2


static func is_visible(tile_id: int) -> bool:
	return tile_id > 0 and tile_id < TILE_ID_MAX


static func is_autotile(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A1


static func autotile_kind(tile_id: int) -> int:
	return int(floor(float(tile_id - TILE_ID_A1) / 48.0))


static func autotile_shape(tile_id: int) -> int:
	return (tile_id - TILE_ID_A1) % 48


static func is_tile_a1(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A1 and tile_id < TILE_ID_A2


static func is_tile_a2(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A2 and tile_id < TILE_ID_A3


static func is_tile_a3(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A3 and tile_id < TILE_ID_A4


static func is_tile_a4(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A4 and tile_id < TILE_ID_MAX


static func is_tile_a5(tile_id: int) -> bool:
	return tile_id >= TILE_ID_A5 and tile_id < TILE_ID_A1


static func make_autotile_id(kind: int, shape: int) -> int:
	return TILE_ID_A1 + kind * 48 + shape


static func passage_kind(flag: int) -> int:
	if (flag & FLAG_HIGHER) != 0:
		return PASS_STAR
	if (flag & FLAG_DIRS) == FLAG_DIRS:
		return PASS_X
	return PASS_O


static func with_passage_kind(flag: int, kind: int) -> int:
	var keep: int = flag & ~0x1F
	match kind:
		PASS_X:
			return keep | FLAG_DIRS
		PASS_STAR:
			return keep | FLAG_HIGHER
		_:
			return keep


static func with_dir_blocked(flag: int, dir_bit: int, blocked: bool) -> int:
	if blocked:
		return (flag | (dir_bit & FLAG_DIRS)) & ~FLAG_HIGHER
	return flag & ~(dir_bit & FLAG_DIRS)


static func passage_ids_for(tile_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if tile_id <= 0 or tile_id >= TILE_ID_MAX:
		return out
	if not is_autotile(tile_id):
		out.append(tile_id)
		return out
	var kind := autotile_kind(tile_id)
	var n := 48
	if is_waterfall_kind(kind):
		n = 4
	elif is_wall_autotile(make_autotile_id(kind, 0)):
		n = 16
	for s in range(n):
		var id: int = make_autotile_id(kind, s)
		if id < TILE_ID_MAX:
			out.append(id)
	return out


static func is_waterfall_kind(kind: int) -> bool:
	return kind >= 5 and kind <= 15 and kind % 2 == 1


static func is_waterfall(tile_id: int) -> bool:
	if tile_id >= TILE_ID_A1 + 192 and tile_id < TILE_ID_A2:
		return autotile_kind(tile_id) % 2 == 1
	return false


static func is_wall_autotile(tile_id: int) -> bool:
	if is_tile_a3(tile_id):
		return true
	if is_tile_a4(tile_id):
		return int(autotile_kind(tile_id) / 8) % 2 == 1
	return false


## KilloZapit / MV editor: true = that side is a border (neighbor missing or other kind).
static func floor_shape(left: bool, up: bool, right: bool, down: bool, nw: bool, ne: bool, se: bool, sw: bool) -> int:
	var edge := 0
	if left:
		edge |= 1
	if up:
		edge |= 2
	if right:
		edge |= 4
	if down:
		edge |= 8
	match edge:
		0:
			var index := 0
			if nw:
				index |= 1
			if ne:
				index |= 2
			if se:
				index |= 4
			if sw:
				index |= 8
			return index
		1:
			return 16 + (1 if ne else 0) + (2 if se else 0)
		2:
			return 20 + (1 if se else 0) + (2 if sw else 0)
		3:
			return 35 if se else 34
		4:
			return 24 + (1 if sw else 0) + (2 if nw else 0)
		5:
			return 32
		6:
			return 37 if sw else 36
		7:
			return 42
		8:
			return 28 + (1 if nw else 0) + (2 if ne else 0)
		9:
			return 41 if ne else 40
		10:
			return 33
		11:
			return 43
		12:
			return 39 if nw else 38
		13:
			return 44
		14:
			return 45
		15:
			return 46
		_:
			return 47


static func wall_shape(left: bool, up: bool, right: bool, down: bool) -> int:
	var index := 0
	if left:
		index |= 1
	if up:
		index |= 2
	if right:
		index |= 4
	if down:
		index |= 8
	return index


static func waterfall_shape(left: bool, right: bool) -> int:
	var index := 0
	if left:
		index |= 1
	if right:
		index |= 2
	return index


static func reverse_dir(d: int) -> int:
	match d:
		2:
			return 8
		4:
			return 6
		6:
			return 4
		8:
			return 2
		_:
			return 0


static func dir_delta(d: int) -> Vector2i:
	match d:
		2:
			return Vector2i(0, 1)
		4:
			return Vector2i(-1, 0)
		6:
			return Vector2i(1, 0)
		8:
			return Vector2i(0, -1)
		_:
			return Vector2i.ZERO


static func dir_from_vec(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 6 if v.x > 0.0 else 4
	if absf(v.y) > 0.0:
		return 2 if v.y > 0.0 else 8
	return 0
