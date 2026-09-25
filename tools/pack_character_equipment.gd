extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Import independently generated transparent garment layers; never writes Body textures.
var ROOT:String = ArtPaths.path("character_creator")
const TYPES := ["Male", "Female", "YoungMale", "YoungFemale"]
const SOURCE_DIRS := ["front", "left", "left", "back", "front_left", "front_left", "back_left", "back_left"]
const CATS := ["Clothing1", "Clothing2", "Boots", "Belt"]
const POSES := [[0,0,0,0], [0,1,0,2], [3,4,5,0], [6,7,6,7], [8,9,9,8], [0,10,11,11], [0,12,13,13], [0,14,15,15]]

func _initialize() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/source/motion_index.json"))
	var chair_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/source/chair_index.json"))
	for cat in CATS:
		var chair := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "/source/chair_" + cat + ".png"))
		chair.resize(int(chair_index["size"][0]), int(chair_index["size"][1]), Image.INTERPOLATE_NEAREST)
		var sources := {}
		for direction in SOURCE_DIRS:
			if sources.has(direction):
				continue
			var path: String = ROOT + "/source/gear_" + direction + "_" + cat + ".png"
			if not FileAccess.file_exists(path):
				push_error("Missing independent garment source: " + path)
				quit(1)
				return
			var source := Image.load_from_file(ProjectSettings.globalize_path(path))
			var size: Array = index["motion_" + direction]["size"]
			source.resize(int(size[0]), int(size[1]), Image.INTERPOLATE_NEAREST)
			sources[direction] = source
		for type_idx in range(4):
			var sheet := Image.create(384, 6144, false, Image.FORMAT_RGBA8)
			var standing := Image.create(144, 576, false, Image.FORMAT_RGBA8)
			for d in range(8):
				var source_name: String = SOURCE_DIRS[d]
				var row: Array = index["motion_" + source_name]["rows"][type_idx]
				var normal: Array = row[0]["rect"]
				var scale_factor := (58.0 if type_idx < 2 else 54.0) / float(normal[3])
				var mirrored := d in [2,5,7]
				var source: Image = sources[source_name]
				for action in range(8):
					for f in range(4):
						var pose: int = POSES[action][f]
						if d == 3 and pose == 0:
							pose = 1
						var r: Array = row[pose]["rect"]
						var frame_scale := scale_factor
						var frame_mirrored := mirrored
						var frame_source := source
						if pose == 15:
							r = chair_index["rows"][type_idx][d]["rect"]
							frame_scale = (46.0 if type_idx < 2 else 43.0) / float(r[3])
							frame_mirrored = false
							frame_source = chair
						var body_rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
						var rect := body_rect.grow(5).intersection(Rect2i(Vector2i.ZERO, frame_source.get_size()))
						var part := frame_source.get_region(rect)
						var size := Vector2i(maxi(1, roundi(rect.size.x * frame_scale)), maxi(1, roundi(rect.size.y * frame_scale)))
						part.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
						var body_size := Vector2i(roundi(body_rect.size.x * frame_scale), roundi(body_rect.size.y * frame_scale))
						var offset := Vector2i(48 - body_size.x / 2, 80 - body_size.y) + Vector2i(Vector2(rect.position - body_rect.position) * frame_scale)
						# Fit trouser length to the body's waist-to-ankle span. Source
						# generators otherwise give the smaller bodies adult-length pants.
						if cat == "Clothing2" and type_idx >= 2 and pose < 10:
							var used := _opaque_bounds(part)
							if used.has_area():
								var center_x := offset.x + used.get_center().x
								part = part.get_region(used)
								var height := maxi(4, roundi(body_size.y * 0.49))
								var width := maxi(3, roundi(used.size.x * float(height) / used.size.y))
								part.resize(width,height,Image.INTERPOLATE_NEAREST)
								size = part.get_size()
								offset = Vector2i(center_x-width/2,78-height)
						# Footwear uses the foot-floor anchor, independent of source padding.
						if cat == "Boots":
							var used := _opaque_bounds(part)
							offset.y = 80 - used.end.y
							if pose == 15:
								var foot_x: float = chair_index["rows"][type_idx][d]["foot_x"]
								offset.x = roundi(48 - body_size.x / 2 + (foot_x-body_rect.position.x)*frame_scale - used.get_center().x)
						var cell := Image.create(96,96,false,Image.FORMAT_RGBA8)
						cell.blit_rect(part, Rect2i(Vector2i.ZERO, size), offset)
						if frame_mirrored:
							cell.flip_x()
						sheet.blit_rect(cell, Rect2i(0,0,96,96), Vector2i(f*96, (action*8+d)*96))
						if action == 0 and f == 0:
							for col in range(3):
								standing.blit_rect(cell, Rect2i(24,14,48,72), Vector2i(col*48,d*72))
			var type_name: String = TYPES[type_idx]
			var name := "/TV_%s_p01_m007.png" % cat
			assert(sheet.save_png(ROOT + "/Motion/" + type_name + name) == OK)
			assert(standing.save_png(ROOT + "/TV/" + type_name + name) == OK)
		print("Packed independent " + cat + " layers for all four bodies")
	quit()

func _opaque_bounds(img: Image) -> Rect2i:
	var low := img.get_size()
	var high := Vector2i(-1,-1)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x,y).a > 0.5:
				low = low.min(Vector2i(x,y))
				high = high.max(Vector2i(x,y))
	return Rect2i(low,high-low+Vector2i.ONE) if high.x >= 0 else Rect2i()
