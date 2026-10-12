extends SceneTree
## Isolated texture-stage diagnostic. Read-only source data; no production cache APIs.
## Run only via the private-desktop GPU runner. Timings are main-thread wall time,
## not GPU timestamps. Readback/byte verification happen after the timed stages.
const Frozen = preload("res://scripts/world3d/house_prefab.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const RECORD = "D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009/original_record.json"
const OUT = "D:/code/rmmo_runtime/review_artifacts/loading_optimization_20261009"
const EXPECTED_IMAGES = 11
const ORDER = ["A_original", "B_rgb8_to_rgba8", "B_rgb8_to_rgba8", "A_original"]
var output := OUT + "/texture_stages.json"
var report: Dictionary = {"version": 1, "failures": [], "checks": 0, "groups": [], "sources": [],
	"order": ORDER, "record": RECORD,
	"scope": "11 original bridge material images, already decoded with original mip generation. A retains original formats. B converts only RGB8 inputs to RGBA8 before upload; other formats are unchanged controls. Independent image/data copies per ABBA group. No resize, regenerated mipmaps, compression, material cache, model cache or production publication.",
	"timing_scope": "Paths.allowed, file_exists, CPU convert, detect_alpha, ImageTexture.create_from_image and RenderingServer.force_sync are separate main-thread wall durations. force_sync drains rendering-server work, not a GPU timestamp. GPU readback and all byte/alpha verification are outside these measured stages. Four sequential groups in one process are an isolation probe, not full-entry performance evidence.",
	"verification_scope": "All base/mipmap RGB channels compare as exact bytes after a native RGB8 roundtrip, and each RGBA8 mip has ALPHA_NONE (all alpha bytes opaque). GPU readback is normalized to the original format and compared per mip, including alpha for original RGBA inputs."}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	report.checks += 1
	if not ok:
		report.failures.append(label)
		push_error("TEXTURE_STAGE_CHECK " + label)
	return ok

func persist() -> void:
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write texture-stage report: " + output)
		return
	file.store_string(JSON.stringify(report, "\t")); file.close()

func feature_info() -> Dictionary:
	var features: Dictionary = {}
	for flag: String in ["editor", "editor_hint", "editor_runtime", "template", "debug", "release", "single", "double", "x86_64", "headless", "vulkan"]:
		features[flag] = OS.has_feature(flag)
	return {"executable": OS.get_executable_path(), "version": Engine.get_version_info(),
		"is_debug_build": OS.is_debug_build(), "editor_hint": Engine.is_editor_hint(),
		"debugger_active": EngineDebugger.is_active(), "features": features,
		"display_server": DisplayServer.get_name(), "processor_count": OS.get_processor_count(),
		"renderer": ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"),
		"thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", null),
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"api_version": RenderingServer.get_video_adapter_api_version(),
		"probe_sha256": FileAccess.get_sha256("res://tools/profile_surface_texture_stages.gd")}

func image_info(image: Image) -> Dictionary:
	return {"format": image.get_format(), "width": image.get_width(), "height": image.get_height(),
		"mipmap_count": image.get_mipmap_count(), "has_mipmaps": image.has_mipmaps(),
		"data_bytes": image.get_data_size(), "instance_id": image.get_instance_id()}

func independent_copy(source: Image) -> Image:
	# Duplicate the PackedByteArray too: distinct Image objects alone can share COW data.
	return Image.create_from_data(source.get_width(), source.get_height(), source.has_mipmaps(), source.get_format(), source.get_data().duplicate())

func mip_bytes(image: Image, bytes: PackedByteArray, level: int) -> PackedByteArray:
	var start: int = image.get_mipmap_offset(level)
	var end: int = image.get_mipmap_offset(level + 1) if level < image.get_mipmap_count() else bytes.size()
	return bytes.slice(start, end)

func shape_equal(a: Image, b: Image) -> bool:
	return a.get_width() == b.get_width() and a.get_height() == b.get_height() and a.has_mipmaps() == b.has_mipmaps() and a.get_mipmap_count() == b.get_mipmap_count()

func verify_exact(reference: Image, actual: Image, label: String) -> Dictionary:
	var result: Dictionary = {"reference_format": reference.get_format(), "actual_format": actual.get_format(), "levels": []}
	if not check(shape_equal(reference, actual), label + " dimensions/mip count"):
		result.ok = false; return result
	var normalized: Image = independent_copy(actual)
	if normalized.get_format() != reference.get_format(): normalized.convert(reference.get_format())
	var reference_bytes: PackedByteArray = reference.get_data()
	var actual_bytes: PackedByteArray = normalized.get_data()
	var same: bool = normalized.get_format() == reference.get_format() and shape_equal(reference, normalized)
	for level in reference.get_mipmap_count() + 1:
		var a: PackedByteArray = mip_bytes(reference, reference_bytes, level)
		var b: PackedByteArray = mip_bytes(normalized, actual_bytes, level)
		var equal: bool = a == b
		same = same and equal
		result.levels.append({"level": level, "width": maxi(1, reference.get_width() >> level), "height": maxi(1, reference.get_height() >> level), "bytes": a.size(), "exact_channels": equal})
	result.ok = check(same, label + " exact channels in every base/mipmap byte")
	return result

func verify_opaque_rgba(image: Image, label: String) -> Dictionary:
	var result: Dictionary = {"levels": []}
	if not check(image.get_format() == Image.FORMAT_RGBA8, label + " RGBA8 format"):
		result.ok = false; return result
	var bytes: PackedByteArray = image.get_data()
	var opaque := true
	for level in image.get_mipmap_count() + 1:
		var width: int = maxi(1, image.get_width() >> level)
		var height: int = maxi(1, image.get_height() >> level)
		var pixels: PackedByteArray = mip_bytes(image, bytes, level)
		if not check(pixels.size() == width * height * 4, label + " mip byte length " + str(level)):
			opaque = false; continue
		# A standalone mip makes detect_alpha scan that whole mip, not just level 0.
		var mip: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
		var alpha: int = mip.detect_alpha()
		opaque = opaque and alpha == Image.ALPHA_NONE
		result.levels.append({"level": level, "alpha_mode": alpha, "all_alpha_255": alpha == Image.ALPHA_NONE})
	result.ok = check(opaque, label + " alpha is exactly opaque in every mip")
	return result

func measure_group(images: Dictionary, paths: Array, case_name: String, ordinal: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var copies: Dictionary = {}
	for path: String in paths: copies[path] = independent_copy(images[path])
	var result: Dictionary = {"case": case_name, "ordinal": ordinal, "textures": [],
		"independent_copy_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"paths_allowed_ms": 0.0, "file_exists_ms": 0.0, "cpu_convert_ms": 0.0,
		"detect_alpha_ms": 0.0, "create_from_image_ms": 0.0, "converted_images": 0}
	var retained: Array[ImageTexture] = []
	# Drain prior groups/setup outside the measured create and upload synchronization.
	started = Time.get_ticks_usec(); RenderingServer.force_sync()
	result.pre_group_sync_ms = (Time.get_ticks_usec() - started) / 1000.0
	var measured_started: int = Time.get_ticks_usec()
	for path: String in paths:
		var image: Image = copies[path]
		var row: Dictionary = {"path": path, "before": image_info(image)}
		started = Time.get_ticks_usec(); var allowed: bool = Paths.allowed(path)
		row.paths_allowed_ms = (Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec(); var exists: bool = FileAccess.file_exists(path)
		row.file_exists_ms = (Time.get_ticks_usec() - started) / 1000.0
		check(allowed and exists, case_name + " allowed/existing " + path)
		row.cpu_convert_ms = 0.0
		row.converted = case_name == "B_rgb8_to_rgba8" and image.get_format() == Image.FORMAT_RGB8
		if row.converted:
			started = Time.get_ticks_usec(); image.convert(Image.FORMAT_RGBA8)
			row.cpu_convert_ms = (Time.get_ticks_usec() - started) / 1000.0
			result.converted_images += 1
		started = Time.get_ticks_usec(); var alpha: int = image.detect_alpha()
		row.detect_alpha_ms = (Time.get_ticks_usec() - started) / 1000.0
		row.alpha_mode = alpha
		started = Time.get_ticks_usec(); var texture: ImageTexture = ImageTexture.create_from_image(image)
		row.create_from_image_ms = (Time.get_ticks_usec() - started) / 1000.0
		check(texture != null, case_name + " ImageTexture created " + path)
		retained.append(texture)
		texture = null # retained owns every upload until the synchronization below.
		row.after = image_info(image)
		for key: String in ["paths_allowed_ms", "file_exists_ms", "cpu_convert_ms", "detect_alpha_ms", "create_from_image_ms"]:
			result[key] += row[key]
		result.textures.append(row)
	result.loop_wall_ms = (Time.get_ticks_usec() - measured_started) / 1000.0
	started = Time.get_ticks_usec(); RenderingServer.force_sync()
	result.force_sync_ms = (Time.get_ticks_usec() - started) / 1000.0
	result.measured_wall_ms = (Time.get_ticks_usec() - measured_started) / 1000.0
	result.retained_texture_count_at_sync = retained.size()
	result.texture_memory_after_sync = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	# All readback, normalization, per-mip comparison and readback alpha inspection
	# are deliberately outside create/force_sync/loop_wall timing above.
	var verification_started: int = Time.get_ticks_usec()
	var readback_ms := 0.0
	for i in paths.size():
		var path: String = paths[i]
		var reference: Image = images[path]
		var submitted: Image = copies[path]
		var row: Dictionary = result.textures[i]
		row.cpu_pixels = verify_exact(reference, submitted, case_name + " CPU " + path)
		if row.converted: row.cpu_alpha = verify_opaque_rgba(submitted, case_name + " converted " + path)
		if retained[i] == null: continue
		started = Time.get_ticks_usec(); var gpu: Image = retained[i].get_image()
		row.readback_ms = (Time.get_ticks_usec() - started) / 1000.0; readback_ms += row.readback_ms
		if not check(gpu != null and not gpu.is_empty(), case_name + " GPU readback " + path): continue
		row.readback_info = image_info(gpu)
		row.gpu_pixels = verify_exact(reference, gpu, case_name + " GPU " + path)
		if reference.get_format() == Image.FORMAT_RGB8:
			if row.converted: check(gpu.get_format() == Image.FORMAT_RGBA8, case_name + " GPU exposes converted RGBA8 alpha " + path)
			if gpu.get_format() == Image.FORMAT_RGBA8:
				row.gpu_alpha = verify_opaque_rgba(gpu, case_name + " GPU opaque " + path)
			else:
				# RGB8 get_image() exposes three stored channels, not the renderer's
				# alpha swizzle. Never manufacture alpha and call it GPU evidence.
				row.gpu_alpha = {"observable": false, "reason": "RGB8 readback exposes no alpha channel; only RGB channel equality is measured for this texture."}
	result.readback_ms = readback_ms
	result.verification_and_readback_ms = (Time.get_ticks_usec() - verification_started) / 1000.0
	# Locals in the verification loop contain only Images. Retained owns all texture
	# refs until synchronized/read back; release them on this main thread.
	started = Time.get_ticks_usec(); retained.clear(); copies.clear(); RenderingServer.force_sync()
	result.main_thread_cleanup_sync_ms = (Time.get_ticks_usec() - started) / 1000.0
	return result

func summarize() -> Dictionary:
	var summary: Dictionary = {}
	for case_name: String in ["A_original", "B_rgb8_to_rgba8"]:
		var rows: Array = report.groups.filter(func(row): return row["case"] == case_name)
		var values: Dictionary = {"samples": rows.size()}
		for key: String in ["paths_allowed_ms", "file_exists_ms", "cpu_convert_ms", "detect_alpha_ms", "create_from_image_ms", "force_sync_ms", "loop_wall_ms", "measured_wall_ms"]:
			var samples: Array = rows.map(func(row): return row[key]); samples.sort()
			values[key] = {"samples": samples, "mean": (float(samples[0]) + float(samples[1])) / 2.0} if samples.size() == 2 else {"samples": samples}
		summary[case_name] = values
	return summary

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		else: push_error("Unsupported argument: " + arg); quit(1); return
	if not Paths.allowed(output, OUT) or output.get_extension().to_lower() != "json":
		push_error("Output must be JSON beneath " + OUT); quit(1); return
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
		push_error("Cannot create review output directory"); quit(1); return
	report.engine_build = feature_info()
	if not check(DisplayServer.get_name() != "headless", "probe requires the real renderer on the private desktop"):
		persist(); quit(1); return
	var record_hash: String = FileAccess.get_sha256(RECORD)
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	if not check(record is Dictionary and record.has("house_prefab"), "original frozen stone bridge record"):
		persist(); quit(1); return
	var started: int = Time.get_ticks_usec()
	# Decodes the authored CPU packet in this private process; no meshes/materials
	# are published, and no filesystem-derived cache builder is invoked.
	var prepared: Dictionary = Frozen.prepare_cpu(record)
	report.prepare_cpu_ms = (Time.get_ticks_usec() - started) / 1000.0
	if not check(not prepared.is_empty(), "decoded original bridge CPU packet"):
		persist(); quit(1); return
	var images: Dictionary = {}; var paths: Array = []; var uses: Dictionary = {}
	for material: Dictionary in prepared.data.materials:
		for field: String in Paint.MAP_FIELDS:
			var path: String = material.get("paint", {}).get(field, "")
			if path.is_empty(): continue
			if not uses.has(path): uses[path] = []
			uses[path].append({"material": material.get("paint", {}).get("name", ""), "field": field})
			if not paths.has(path): paths.append(path)
	check(paths.size() == EXPECTED_IMAGES, "exactly 11 unique original material images")
	var eligible := 0
	for path: String in paths:
		if not check(Paths.allowed(path) and FileAccess.file_exists(path), "source path " + path): continue
		started = Time.get_ticks_usec(); var image: Image = Image.load_from_file(path)
		var decode_ms: float = (Time.get_ticks_usec() - started) / 1000.0
		if not check(image != null and not image.is_empty(), "decode " + path): continue
		started = Time.get_ticks_usec()
		var mip_error: Error = image.generate_mipmaps() if not image.has_mipmaps() else OK
		var mip_ms: float = (Time.get_ticks_usec() - started) / 1000.0
		check(mip_error == OK and image.has_mipmaps(), "prepared mips " + path)
		images[path] = image
		if image.get_format() == Image.FORMAT_RGB8: eligible += 1
		var info: Dictionary = image_info(image); info.path = path; info.uses = uses[path]
		info.decode_ms = decode_ms; info.generate_mipmaps_ms = mip_ms
		report.sources.append(info)
	report.rgb8_input_count = eligible
	check(eligible > 0, "RGB8 input exists for format conversion hypothesis")
	if not report.failures.is_empty(): persist(); quit(1); return
	prepared.clear()
	for frame in 3: await process_frame
	for ordinal in ORDER.size():
		var group: Dictionary = measure_group(images, paths, ORDER[ordinal], ordinal)
		report.groups.append(group)
		persist()
		print("TEXTURE_STAGES_GROUP ", ordinal, " ", ORDER[ordinal], " create_ms=", group.create_from_image_ms, " convert_ms=", group.cpu_convert_ms, " alpha_ms=", group.detect_alpha_ms, " force_sync_ms=", group.force_sync_ms)
		for frame in 3: await process_frame
	report.summary = summarize()
	check(FileAccess.get_sha256(RECORD) == record_hash, "author record remains unchanged")
	report.record_sha256 = record_hash
	images.clear(); RenderingServer.force_sync()
	persist()
	print("TEXTURE_STAGES_REPORT ", output, " failures=", report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
