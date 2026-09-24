extends RefCounted
## Read-only acceptance: resolved disk/cache identity and real MV rendering.
const TileId = preload("res://scripts/map/tile_id.gd")
const TileBlit = preload("res://scripts/map/tile_blit.gd")
const SIZES := [Vector2i(768,576), Vector2i(768,576), Vector2i(768,384), Vector2i(768,720), Vector2i(384,768), Vector2i(768,768), Vector2i(768,768), Vector2i(768,768), Vector2i(768,768)]
var _owner: WeakRef
var ctrl:
	get:
		return _owner.get_ref()

func _init(c):
	_owner = weakref(c)

func op_names() -> Array:
	return ["audit_tileset", "preview_autotile_cases"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("audit_tileset", "Read-only MV dimensions, B0, resolved file hashes and stale image cache audit. Technical results do not certify art style.", {
			"tileset_id": {"type":"string"}, "expected_sha256": {"type":"object", "description":"Sheet name to SHA256; every requested name must exist."}}),
		ctrl.mcp._tool("preview_autotile_cases", "Read-only native 48px fixtures rendered by the actual MV blitter: island, hole, L, narrow path, all legal shapes. Does not edit the map.", {
			"tileset_id":{"type":"string"}, "kinds":{"type":"array","items":{"type":"integer"},"minItems":1,"maxItems":8},
			"frame":{"type":"integer","minimum":0,"maximum":3}, "path":{"type":"string"}, "max_px":{"type":"integer"}}, ["kinds"])
	]

func _tileset(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return {}
	var d = ctrl.doc()
	var id := str(args.get("tileset_id", d.tileset_id if d else ""))
	return p.tilesets.get(id, {})

static func image_errors(im: Image, slot: int) -> Array:
	var errors: Array = []
	if im == null or im.is_empty():
		return ["missing_or_unreadable"]
	var expected_size: Vector2i = SIZES[slot] if slot >= 0 and slot < SIZES.size() else Vector2i(768,768)
	if im.get_size() != expected_size:
		errors.append("dimensions")
	if slot == 5:
		for y in range(mini(48, im.get_height())):
			for x in range(mini(48, im.get_width())):
				if im.get_pixel(x,y).a > 0:
					errors.append("B0_not_transparent")
					return errors
	return errors

func audit_tileset(args: Dictionary) -> Dictionary:
	var ts := _tileset(args)
	if ts.is_empty():
		return ctrl.mcp._err("tileset not found")
	var names: Array = TileId.sheet_names(ts)
	if typeof(args.get("expected_sha256", {})) != TYPE_DICTIONARY:
		return ctrl.mcp._err("expected_sha256 must be an object")
	var expected: Dictionary = args.get("expected_sha256", {})
	var sheets: Array = ctrl._load_sheets(ts)
	var palette = ctrl.ed().get("_palette") if ctrl.ed() else null
	if palette != null and palette.tileset == ts and palette.sheets.size() == names.size():
		sheets = palette.sheets
	var am = Engine.get_main_loop().root.get_node_or_null("AssetManager")
	var rows: Array = []
	var errors: Array = []
	var seen := {}
	for i in range(names.size()):
		var n := str(names[i]).strip_edges()
		if n.is_empty():
			continue
		seen[n] = true
		var path := str(am.path("content://tilesheet/" + n)) if am else ""
		if not FileAccess.file_exists(path) and ctrl.pack():
			path = ProjectSettings.globalize_path("%s/assets/tilesheet/%s.png" % [ctrl.pack().root, n.get_basename()])
		var disk: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
		var issues := image_errors(disk,i)
		var sha := FileAccess.get_sha256(path) if disk else ""
		if expected.has(n) and str(expected[n]).to_lower() != sha:
			issues.append("unexpected_sha256")
		var cached: Image = sheets[i]
		if disk != null:
			disk.convert(Image.FORMAT_RGBA8)
			if cached == null or cached.get_data() != disk.get_data():
				issues.append("stale_or_missing_cache")
		for issue in issues:
			errors.append(n + ": " + str(issue))
		rows.append({"slot":i,"name":n,"path":path,"sha256":sha,"errors":issues})
	for n in expected:
		if not seen.has(n):
			errors.append(str(n) + ": expected_sheet_not_declared")
	if rows.is_empty():
		errors.append("no_sheets_declared")
	return ctrl.mcp._ok({"technical_passed":errors.is_empty(),"errors":errors,"sheets":rows,"visual_review_required":true,"map_modified":false})

static func fixture_image(sheets: Array, kinds: Array, frame: int, flags := PackedInt32Array()) -> Image:
	# Each row: four 5x5 topology fixtures, then every legal shape in 8 columns.
	var img := Image.create(28*48, kinds.size()*6*48, false, Image.FORMAT_RGBA8)
	img.fill(Color("34383b"))
	var masks := [
		["00000","01110","01110","01110","00000"],
		["11111","11111","11011","11111","11111"],
		["01000","01000","01110","00000","00000"],
		["00100","00100","11111","00100","00100"]]
	for row in range(kinds.size()):
		var kind := int(kinds[row])
		var id: int = TileId.make_autotile_id(kind,0)
		var waterfall: bool = TileId.is_waterfall_kind(kind)
		var wall: bool = TileId.is_wall_autotile(id)
		for m in range(masks.size()):
			var mask: Array = masks[m]
			for y in range(5):
				for x in range(5):
					if not _filled(mask,x,y):
						continue
					var l := not _filled(mask,x-1,y)
					var u := not _filled(mask,x,y-1)
					var r := not _filled(mask,x+1,y)
					var b := not _filled(mask,x,y+1)
					var shape := TileId.floor_shape(l,u,r,b,not _filled(mask,x-1,y-1),not _filled(mask,x+1,y-1),not _filled(mask,x+1,y+1),not _filled(mask,x-1,y+1))
					if waterfall:
						shape = int(l) + int(r)*2
					elif wall:
						shape = int(l) + int(u)*2 + int(r)*4 + int(b)*8
					TileBlit.blit_tile(img,TileId.make_autotile_id(kind,shape),(m*5+x)*48,(row*6+y)*48,sheets,48,48,flags,frame)
		var count := 4 if waterfall else (16 if wall else 48)
		for s in range(count):
			TileBlit.blit_tile(img,TileId.make_autotile_id(kind,s),(20+s%8)*48,(row*6+s/8)*48,sheets,48,48,flags,frame)
	return img

static func _filled(mask: Array, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < 5 and y < 5 and str(mask[y])[x] == "1"

func preview_autotile_cases(args: Dictionary) -> Dictionary:
	if typeof(args.get("kinds", [])) != TYPE_ARRAY:
		return ctrl.mcp._err("kinds must be an array")
	var kinds: Array = args.get("kinds", [])
	if kinds.is_empty() or kinds.size() > 8:
		return ctrl.mcp._err("kinds must contain 1..8 integers")
	for k in kinds:
		if (typeof(k) != TYPE_INT and typeof(k) != TYPE_FLOAT) or float(k) != int(k) or int(k) < 0 or int(k) > 127:
			return ctrl.mcp._err("kind must be an integer in 0..127")
	var frame := int(args.get("frame",0))
	if frame < 0 or frame > 3:
		return ctrl.mcp._err("frame must be 0..3")
	var ts := _tileset(args)
	if ts.is_empty():
		return ctrl.mcp._err("tileset not found")
	var sheets: Array = ctrl._load_sheets(ts)
	for k in kinds:
		var slot := 0 if int(k)<16 else (1 if int(k)<48 else (2 if int(k)<80 else 3))
		var issues := image_errors(sheets[slot],slot)
		if not issues.is_empty():
			return ctrl.mcp._err("invalid source sheet: " + str(issues))
	var img := fixture_image(sheets,kinds,frame,ctrl._flags_of(ts))
	var opts := args.duplicate()
	if not opts.has("max_px"):
		opts["max_px"] = 4096
	return ctrl._png_payload(img,{"kinds":kinds,"frame":frame,"tile_px":48,"row_px":288,"fixtures":["island","hole","L","cross","all_shapes"],"visual_review_required":true,"map_modified":false},opts,"res://.grok/autotile_cases.png")
