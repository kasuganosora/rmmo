extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Packs ImageGen artwork into the existing paperdoll coordinate system.
## No third-party images are read. Run with Godot --headless --path . --script this_file.
var ROOT:String = ArtPaths.path("character_creator")
const TYPES := ["Male", "Female", "YoungMale", "YoungFemale"]
const CATS := ["Eyes", "Eyebrows", "Nose", "Mouth"]
const DIRS := ["front", "left", "right", "back", "front_left", "front_right", "back_left", "back_right"]

func _initialize() -> void:
	var body := Image.load_from_file(ROOT + "/source/body.png")
	if body == null:
		quit(1)
		return
	var hairs: Array[Image] = []
	var faces: Array[Image] = []
	for v in range(1, 3):
		hairs.append(Image.load_from_file(ROOT + "/source/hair_%d.png" % v))
		faces.append(Image.load_from_file(ROOT + "/source/face_%d.png" % v))
	for img in hairs + faces:
		if img == null:
			quit(1)
			return
	var overview := Image.create(48 * 8, 72 * 12, false, Image.FORMAT_RGBA8)
	for type_idx in range(4):
		var folder: String = ROOT + "/TV/" + TYPES[type_idx]
		DirAccess.make_dir_recursive_absolute(folder)
		var sheets := {"Body1": _sheet()}
		for v in range(1, 3):
			sheets["FrontHair1%d" % v] = _sheet()
			for cat in CATS:
				sheets[cat + str(v)] = _sheet()
		for d in range(8):
			var rows := [0, 274, 540, 782, 1024]
			var column := [0, 2, 1, 3, 4, 5, 6, 7][d] as int
			var source_cell := body.get_region(Rect2i(column * 192, rows[type_idx], 192, rows[type_idx + 1] - rows[type_idx]))
			var bounds := _opaque_bounds(source_cell)
			var cropped := source_cell.get_region(bounds)
			var h := 58 if type_idx < 2 else 54
			var w := roundi(float(bounds.size.x) * h / bounds.size.y)
			cropped.resize(w, h, Image.INTERPOLATE_NEAREST)
			var top := 66 - h
			var base := _cell()
			base.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), Vector2i(24 - w / 2, top))
			_stamp(sheets["Body1"], base, d)
			overview.blit_rect(base, Rect2i(0, 0, 48, 72), Vector2i(d * 48, type_idx * 216))
			for v in range(1, 3):
				var hair_source: Image = hairs[v - 1].get_region(Rect2i(d * 192, 0, 192, 1024))
				var hair := hair_source.get_region(_opaque_bounds(hair_source))
				var hair_width := 15 if type_idx < 2 else 14
				var hair_height := 15 if v == 1 else 18
				hair.resize(hair_width, hair_height, Image.INTERPOLATE_NEAREST)
				var layer := _cell()
				layer.blit_rect(hair, Rect2i(Vector2i.ZERO, hair.get_size()), Vector2i(24 - hair_width / 2, top - 2))
				_stamp(sheets["FrontHair1%d" % v], layer, d)
				var composed := base.duplicate()
				for cat_idx in range(4):
					var cat: String = CATS[cat_idx]
					var feature := _cell()
					if d not in [3, 6, 7]:
						var region := Rect2i(d * 192, cat_idx * 256, 192, 256)
						# Variant 2 source packs the mouth directly below the nose.
						if v == 2 and cat_idx == 2:
							region = Rect2i(d * 192, 620, 192, 50)
						elif v == 2 and cat_idx == 3:
							region = Rect2i(d * 192, 675, 192, 35)
						var raw: Image = faces[v - 1].get_region(region)
						var rect := _opaque_bounds(raw)
						if rect.has_area():
							var part := raw.get_region(rect)
							var width := [8, 8, 2, 3][cat_idx] as int
							var height := [3, 1, 2, 1][cat_idx] as int
							var shift := 0
							if d in [1, 2]:
								width = maxi(1, width / 2)
								shift = -5 if d == 1 else 5
							elif d in [4, 5]:
								width = maxi(1, width - 2)
								shift = -2 if d == 4 else 2
							part.resize(width, height, Image.INTERPOLATE_NEAREST)
							var fy := top + ([7, 5, 10, 12][cat_idx] as int)
							feature.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(24 + shift - width / 2, fy))
					_stamp(sheets[cat + str(v)], feature, d)
					composed.blend_rect(feature, Rect2i(0, 0, 48, 72), Vector2i.ZERO)
				composed.blend_rect(layer, Rect2i(0, 0, 48, 72), Vector2i.ZERO)
				overview.blit_rect(composed, Rect2i(0, 0, 48, 72), Vector2i(d * 48, type_idx * 216 + v * 72))
		_save(sheets["Body1"], folder + "/TV_Body_p01_m001.png")
		for v in range(1, 3):
			_save(sheets["FrontHair1%d" % v], folder + "/TV_FrontHair1_p%02d_m003.png" % v)
			for cat in CATS:
				var material := 2 if cat == "Eyes" else (3 if cat == "Eyebrows" else 0)
				_save(sheets[cat + str(v)], folder + "/TV_%s_p%02d_m%03d.png" % [cat, v, material])
	# Original project palette, not the RPG Maker gradient image.
	var palette := Image.create(256, 4 * 12, false, Image.FORMAT_RGBA8)
	var colors := [Color("f6d8c4"), Color("9b6848"), Color("ebc5a5"), Color("674233"), Color("553522"), Color("a46b35"), Color("d4b365"), Color("323545"), Color("b6aaa0"), Color("526d77"), Color("637c54"), Color("915e69")]
	for row in range(colors.size()):
		for x in range(256):
			var color: Color = colors[row]
			var t := 1.0 - float(x) / 255.0
			color = color.darkened((0.5 - t) * 1.6) if t < 0.5 else color.lightened((t - 0.5) * 1.5)
			palette.fill_rect(Rect2i(x, row * 4, 1, 4), color)
	_save(palette, ROOT + "/gradients.png")
	_save(overview, ROOT + "/overview_native.png")
	overview.resize(1536, 3456, Image.INTERPOLATE_NEAREST)
	_save(overview, ROOT + "/overview.png")
	var manifest := {"version": 1, "origin": "OpenAI built-in ImageGen; original prompts; no RTP inputs", "types": TYPES, "directions": DIRS, "cell": [48,72], "sheet": [144,576], "poses": "standing; three identical columns reserved for future walk cycles", "parts_per_type": {"Body": 1, "FrontHair1": 2, "Eyes": 2, "Eyebrows": 2, "Nose": 2, "Mouth": 2}}
	var file := FileAccess.open(ROOT + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("Packed 44 original paperdoll layers; 4 bodies x 8 directions.")
	quit()

func _opaque_bounds(img: Image) -> Rect2i:
	var low := img.get_size()
	var high := Vector2i(-1, -1)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i()

func _cell() -> Image:
	return Image.create(48, 72, false, Image.FORMAT_RGBA8)

func _sheet() -> Image:
	return Image.create(144, 576, false, Image.FORMAT_RGBA8)

func _stamp(sheet: Image, cell: Image, row: int) -> void:
	for col in range(3):
		sheet.blit_rect(cell, Rect2i(0, 0, 48, 72), Vector2i(col * 48, row * 72))

func _save(img: Image, path: String) -> void:
	assert(img.save_png(path) == OK, "Cannot save " + path)
