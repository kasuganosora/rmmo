extends RefCounted
## Human labels for MV tile ids (A1–A5 / B–E). Used by palette and MCP find_tiles.

const TileId = preload("res://scripts/map/tile_id.gd")


static func label_of(tile_id: int) -> String:
	if tile_id <= 0:
		return "空"
	if TileId.is_tile_a1(tile_id):
		var k := TileId.autotile_kind(tile_id)
		if TileId.is_waterfall_kind(k):
			return "瀑布"
		if k <= 7:
			return "水面"
		return "A1 自动"
	if TileId.is_tile_a2(tile_id):
		var k2 := TileId.autotile_kind(tile_id)
		match k2:
			16:
				return "草地"
			17:
				return "深草"
			24:
				return "沙地"
			_:
				return "地面"
	if TileId.is_tile_a3(tile_id):
		return "外墙"
	if TileId.is_tile_a4(tile_id):
		if TileId.is_wall_autotile(tile_id):
			return "内墙"
		return "屋顶/地面"
	if TileId.is_tile_a5(tile_id):
		return "A5 普通"
	if tile_id >= TileId.TILE_ID_E:
		return "E 表"
	if tile_id >= TileId.TILE_ID_D:
		return "D 表"
	if tile_id >= TileId.TILE_ID_C:
		return "C 表"
	return "B 表"


static func search(query: String, tileset: Dictionary = {}) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return []
	var keys: Array = [
		{"q": ["草", "grass", "ground"], "id": TileId.TILE_ID_A2, "label": "草地"},
		{"q": ["深草", "dark"], "id": TileId.TILE_ID_A2 + 48, "label": "深草"},
		{"q": ["沙", "dirt", "sand"], "id": TileId.TILE_ID_A1 + 24 * 48, "label": "沙地"},
		{"q": ["水", "water", "河"], "id": TileId.TILE_ID_A1, "label": "水面"},
		{"q": ["瀑", "waterfall"], "id": TileId.TILE_ID_A1 + 4 * 48, "label": "瀑布"},
		{"q": ["墙", "wall", "城砖", "外墙"], "id": TileId.TILE_ID_A3, "label": "外墙"},
		{"q": ["顶", "roof", "屋"], "id": TileId.TILE_ID_A4, "label": "屋顶/地面"},
		{"q": ["a5"], "id": TileId.TILE_ID_A5, "label": "A5 普通"},
		{"q": ["b", "装饰"], "id": TileId.TILE_ID_B, "label": "B 表"},
		{"q": ["c"], "id": TileId.TILE_ID_C, "label": "C 表"},
		{"q": ["树", "tree"], "id": 80, "label": "B 树（约）"},
	]
	var out: Array = []
	for row in keys:
		var hit := false
		for s in row["q"]:
			if q.find(str(s)) >= 0 or str(s).find(q) >= 0:
				hit = true
				break
		if hit:
			out.append({"tile_id": int(row["id"]), "label": str(row["label"])})
	if tileset.is_empty():
		return out
	return out


static func info_line(tile_id: int) -> String:
	return "%d · %s" % [tile_id, label_of(tile_id)]


## 3×5 bitmap digits for overlaying ids on preview images.
const _DIGITS := [
	[1,1,1, 1,0,1, 1,0,1, 1,0,1, 1,1,1],
	[0,1,0, 1,1,0, 0,1,0, 0,1,0, 1,1,1],
	[1,1,1, 0,0,1, 1,1,1, 1,0,0, 1,1,1],
	[1,1,1, 0,0,1, 1,1,1, 0,0,1, 1,1,1],
	[1,0,1, 1,0,1, 1,1,1, 0,0,1, 0,0,1],
	[1,1,1, 1,0,0, 1,1,1, 0,0,1, 1,1,1],
	[1,1,1, 1,0,0, 1,1,1, 1,0,1, 1,1,1],
	[1,1,1, 0,0,1, 0,0,1, 0,1,0, 0,1,0],
	[1,1,1, 1,0,1, 1,1,1, 1,0,1, 1,1,1],
	[1,1,1, 1,0,1, 1,1,1, 0,0,1, 1,1,1],
]


static func blit_number(img: Image, n: int, x: int, y: int, col: Color = Color(1, 0.92, 0.2, 1)) -> void:
	if img == null:
		return
	var s := str(maxi(n, 0))
	var px := x
	for i in range(s.length()):
		var d := int(s.substr(i, 1))
		if d < 0 or d > 9:
			continue
		var bits: Array = _DIGITS[d]
		for row in range(5):
			for colx in range(3):
				if int(bits[row * 3 + colx]) == 0:
					continue
				var xx := px + colx
				var yy := y + row
				if xx < 0 or yy < 0 or xx >= img.get_width() or yy >= img.get_height():
					continue
				img.set_pixel(xx, yy, col)
		px += 4
