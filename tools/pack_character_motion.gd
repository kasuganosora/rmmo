extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Atlas packing and attachment transforms only. All artwork comes from ImageGen source PNGs.
var ROOT:String = ArtPaths.path("character_creator")
const TYPES := ["Male", "Female", "YoungMale", "YoungFemale"]
const DIRS := ["front", "left", "right", "back", "front_left", "front_right", "back_left", "back_right"]
const SOURCE_DIRS := ["front", "left", "left", "back", "front_left", "front_left", "back_left", "back_left"]
const POSES := [[0,0,0,0], [0,1,0,2], [3,4,5,0], [6,7,6,7], [8,9,9,8], [0,10,11,11], [0,12,13,13], [0,14,15,15]]

func _initialize() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/source/motion_index.json"))
	var sources := {}
	var chair_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/source/chair_index.json"))
	var chair := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "/source/chair.png"))
	for direction in SOURCE_DIRS:
		if not sources.has(direction):
			sources[direction] = Image.load_from_file(ROOT + "/source/motion_" + direction + ".png")
	var sample := Image.create(96 * 4, 96 * 8, false, Image.FORMAT_RGBA8)
	sample.fill(Color("252936"))
	for type_idx in range(4):
		var type_name: String = TYPES[type_idx]
		var folder := ROOT + "/Motion/" + type_name
		DirAccess.make_dir_recursive_absolute(folder)
		var layers := {}
		var output := {"TV_Body_p01_m001.png": _sheet()}
		for file in DirAccess.get_files_at(ROOT + "/TV/" + type_name):
			if file.ends_with(".png") and ("_FrontHair" in file or "_Eyes_" in file or "_Eyebrows_" in file or "_Nose_" in file or "_Mouth_" in file):
				layers[file] = Image.load_from_file(ROOT + "/TV/" + type_name + "/" + file)
				output[file] = _sheet()
		for d in range(8):
			var source_name: String = SOURCE_DIRS[d]
			var row: Array = index["motion_" + source_name]["rows"][type_idx]
			var normal: Array = row[0]["rect"]
			var scale_factor := (58.0 if type_idx < 2 else 54.0) / float(normal[3])
			var mirrored := d in [2,5,7]
			for action in range(8):
				for f in range(4):
					var pose: int = POSES[action][f]
					# Back-view source's neutral cell is front-facing; use its back walking stance.
					if d == 3 and pose == 0:
						pose = 1
					var record: Dictionary = row[pose]
					var frame_scale := scale_factor
					var frame_mirrored := mirrored
					var source: Image = sources[source_name]
					if pose == 15:
						record = chair_index["rows"][type_idx][d]
						frame_scale = (46.0 if type_idx < 2 else 43.0) / float(record["rect"][3])
						frame_mirrored = false
						source = chair
					var r: Array = record["rect"]
					var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
					var sprite: Image = source.get_region(rect)
					var size := Vector2i(maxi(1, roundi(rect.size.x * frame_scale)), maxi(1, roundi(rect.size.y * frame_scale)))
					sprite.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
					if frame_mirrored:
						sprite.flip_x()
					var offset := Vector2i(48 - size.x / 2, 80 - size.y)
					var body := Image.create(96, 96, false, Image.FORMAT_RGBA8)
					body.blit_rect(sprite, Rect2i(Vector2i.ZERO, size), offset)
					_stamp(output["TV_Body_p01_m001.png"], body, action, d, f)
					var anchor: Array = record["head"]
					var head := Vector2((float(anchor[0]) - rect.position.x) * frame_scale, (float(anchor[1]) - rect.position.y) * frame_scale)
					if frame_mirrored:
						head.x = size.x - head.x
					head += Vector2(offset)
					var old_head := Vector2(24, (8 if type_idx < 2 else 12) + 6)
					var angle := 0.0
					if pose == 11:
						angle = deg_to_rad(70 if mirrored else -70)
					var composed := body.duplicate()
					for file in layers:
						var src: Image = layers[file].get_region(Rect2i(48, d * 72, 48, 72))
						var part := _attach(src, old_head, head, angle)
						_stamp(output[file], part, action, d, f)
						if "p01_" in file:
							composed.blend_rect(part, Rect2i(0,0,96,96), Vector2i.ZERO)
					if type_idx == 0 and d == 0:
						sample.blend_rect(composed, Rect2i(0,0,96,96), Vector2i(f * 96, action * 96))
		for file in output:
			assert(output[file].save_png(folder + "/" + file) == OK)
		print("Packed motion layers for " + type_name)
	assert(sample.save_png(ROOT + "/motion_review.png") == OK)
	quit()

func _sheet() -> Image:
	return Image.create(384, 6144, false, Image.FORMAT_RGBA8)

func _stamp(sheet: Image, cell: Image, action: int, direction: int, frame: int) -> void:
	sheet.blit_rect(cell, Rect2i(0,0,96,96), Vector2i(frame * 96, (action * 8 + direction) * 96))

func _attach(src: Image, old_head: Vector2, head: Vector2, angle: float) -> Image:
	var result := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in range(96):
		for x in range(96):
			var point := (Vector2(x,y) - head).rotated(-angle) + old_head
			var p := Vector2i(roundi(point.x), roundi(point.y))
			if p.x >= 0 and p.x < 48 and p.y >= 0 and p.y < 72:
				result.set_pixel(x, y, src.get_pixel(p.x, p.y))
	return result
