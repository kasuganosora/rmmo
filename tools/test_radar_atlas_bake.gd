extends SceneTree
## Headless: bake demo_map and report radar atlas non-transparent pixel stats.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var MapFieldScript = load("res://scripts/map/map_field.gd")
	var mf = MapFieldScript.new()
	mf.pack_path = "res://demo_map"
	root.add_child(mf)
	mf.rebuild()
	var atlas: Image = mf.get_radar_atlas_image()
	var gtex = mf.get_ground_texture()
	var utex = mf.get_upper_texture()
	if atlas == null:
		print("FAIL atlas null")
		quit(1)
		return
	var w := atlas.get_width()
	var h := atlas.get_height()
	var opaque := 0
	var buckets := {}
	var step := maxi(1, int((w * h) / 2000))
	var i := 0
	for y in range(h):
		for x in range(w):
			var c := atlas.get_pixel(x, y)
			if c.a > 0.05:
				opaque += 1
			if (i % step) == 0 and c.a > 0.05:
				var key := "%d,%d,%d" % [int(c.r * 15.0), int(c.g * 15.0), int(c.b * 15.0)]
				buckets[key] = int(buckets.get(key, 0)) + 1
			i += 1
	print("OK atlas %dx%d opaque=%d/%d scale=%s" % [w, h, opaque, w * h, str(mf.get_radar_atlas_scale())])
	print("ground_tex=", gtex != null, " upper_tex=", utex != null, " grid=", mf.grid_width, "x", mf.grid_height, " ts=", mf.tile_size)
	print("color_buckets=", buckets.size())
	atlas.save_png("C:/Users/luna/Desktop/radar_atlas_demo.png")
	print("saved C:/Users/luna/Desktop/radar_atlas_demo.png")
	quit(0 if opaque > 100 else 2)

