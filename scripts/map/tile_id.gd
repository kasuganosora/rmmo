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


static func is_waterfall(tile_id: int) -> bool:
	if tile_id >= TILE_ID_A1 + 192 and tile_id < TILE_ID_A2:
		return autotile_kind(tile_id) % 2 == 1
	return false


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
