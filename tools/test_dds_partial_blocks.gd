extends SceneTree

var failures := 0
var rows: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for spec: Dictionary in manifest["images"]:
		var image := Image.new()
		var error := image.load_dds_from_buffer(FileAccess.get_file_as_bytes(spec["path"]))
		var row := {"path": spec["path"], "error": error, "empty": image.is_empty()}
		var valid := error == OK and not image.is_empty()
		if valid:
			row["width"] = image.get_width()
			row["height"] = image.get_height()
			row["mipmaps"] = image.get_mipmap_count()
			row["bytes"] = image.get_data_size()
			valid = image.get_width() == int(spec["width"]) and image.get_height() == int(spec["height"])
			valid = valid and image.get_mipmap_count() == int(spec["mipmaps"])
			valid = valid and image.get_data_size() == int(spec["bytes"])
			var decoded := image.duplicate() as Image
			valid = valid and decoded.decompress() == OK
			if valid:
				# Both edge blocks and interior texels carry the same known color.
				for uv: Vector2i in [Vector2i.ZERO, Vector2i(image.get_width() - 1, image.get_height() - 1), Vector2i(image.get_width() / 2, image.get_height() / 2)]:
					var pixel := decoded.get_pixelv(uv)
					valid = valid and absf(pixel.r - 0.25) < 0.04 and absf(pixel.g - 0.75) < 0.04
			if manifest.get("gpu", false) and valid:
				var texture := ImageTexture.create_from_image(image)
				var readback := texture.get_image()
				valid = readback != null and readback.get_size() == image.get_size() and readback.get_data() == image.get_data()
				row["gpu_exact_bytes"] = valid
		row["ok"] = valid
		if not valid:
			failures += 1
		rows.append(row)
	var output := {"failures": failures, "cases": rows.size(), "rows": rows, "gpu": manifest.get("gpu", false)}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(output, "\t"))
	print("DDS_PARTIAL_BLOCKS ", JSON.stringify({"failures": failures, "cases": rows.size(), "gpu": manifest.get("gpu", false)}))
	quit(1 if failures else 0)
