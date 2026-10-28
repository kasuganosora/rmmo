extends SceneTree
## Mutate each CPU atlas immediately after queuing its previous upload. Readback
## happens only after the burst, so it cannot serialize away the tested overlap.
var output := ""
var font_path := ""
var mode := ""
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var render_thread := 0
var thread_mutex := Mutex.new()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.substr(9)
		elif arg.begins_with("--font="): font_path = arg.substr(7)
		elif arg.begins_with("--mode="): mode = arg.substr(7)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"pass": ok, "label": label})
	print("PASS " if ok else "FAIL ", label)

func capture_thread() -> void:
	thread_mutex.lock()
	render_thread = OS.get_thread_caller_id()
	thread_mutex.unlock()

func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	Engine.max_fps = 120
	RenderingServer.call_on_render_thread(capture_thread)
	for frame in 8: await process_frame
	thread_mutex.lock()
	var observed_thread := render_thread
	thread_mutex.unlock()
	check(observed_thread != 0, "render callback executed")
	check((observed_thread == OS.get_main_thread_id()) == (mode == "safe"), "actual render thread matches requested mode")
	var font_bytes := FileAccess.get_file_as_bytes(font_path)
	check(not font_bytes.is_empty(), "external font read")
	var interfaces: Array[String] = []
	var skipped: Array[String] = []
	for index in TextServerManager.get_interface_count():
		var server := TextServerManager.get_interface(index)
		if not server.has_feature(TextServer.FEATURE_FONT_DYNAMIC):
			skipped.append(server.get_name())
			continue
		interfaces.append(server.get_name())
		for mipmaps in [false, true]:
			for trigger in ["rid", "size", "draw", "outline"]:
				await run_case(server, font_bytes, mipmaps, trigger)
	check(not cases.is_empty(), "at least one compiled text server exercised")
	var failed := checks.filter(func(row: Dictionary): return not row["pass"]).size()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed, "cases": cases,
		"interfaces": interfaces, "skipped_no_dynamic_font": skipped, "engine": Engine.get_version_info(), "mode": mode,
		"main_thread": OS.get_main_thread_id(), "render_thread": observed_thread,
		"scope": "queued glyph atlas update integrity; readbacks are test-only, not performance evidence"}, "\t"))
	file.close()
	quit(0 if failed == 0 else 1)

func run_case(server: TextServer, font_bytes: PackedByteArray, mipmaps: bool, trigger: String) -> void:
	var font := server.create_font()
	server.font_set_data(font, font_bytes)
	server.font_set_generate_mipmaps(font, mipmaps)
	var canvas := Node2D.new()
	root.add_child(canvas)
	var size := Vector2i(32, 2 if trigger == "outline" else 0)
	var atlases: Dictionary = {}
	var glyph_count := 0
	for codepoint in range(33, 255):
		var glyph := server.font_get_glyph_index(font, size.x, codepoint, 0)
		if glyph == 0: continue
		server.font_render_glyph(font, size, glyph)
		var atlas_index := server.font_get_glyph_texture_idx(font, size, glyph)
		if atlas_index < 0: continue
		match trigger:
			"rid": server.font_get_glyph_texture_rid(font, size, glyph)
			"size": server.font_get_glyph_texture_size(font, size, glyph)
			"draw": server.font_draw_glyph(font, canvas.get_canvas_item(), size.x, Vector2(20, 50), glyph)
			"outline": server.font_draw_glyph_outline(font, canvas.get_canvas_item(), size.x, size.y, Vector2(20, 50), glyph)
		atlases[atlas_index] = glyph
		glyph_count += 1
	var label := "%s/%s/mips=%s" % [server.get_name(), trigger, mipmaps]
	check(glyph_count >= 90, label + ": many distinct glyph updates")
	var identical := not atlases.is_empty()
	var bytes := 0
	for atlas_index: int in atlases:
		var rid := server.font_get_glyph_texture_rid(font, size, atlases[atlas_index])
		var cpu := server.font_get_texture_image(font, size, atlas_index).duplicate() as Image
		if mipmaps: cpu.generate_mipmaps()
		var gpu := RenderingServer.texture_2d_get(rid)
		if gpu == null or gpu.is_empty():
			identical = false
			continue
		cpu.convert(Image.FORMAT_RGBA8)
		gpu.convert(Image.FORMAT_RGBA8)
		identical = identical and cpu.get_size() == gpu.get_size() and cpu.get_data() == gpu.get_data()
		bytes += gpu.get_data_size()
	check(identical, label + ": GPU atlas and complete mip bytes equal CPU snapshot")
	cases.append({"server": server.get_name(), "trigger": trigger, "mipmaps": mipmaps,
		"glyphs": glyph_count, "atlases": atlases.size(), "rgba_bytes": bytes, "equal": identical})
	canvas.queue_free()
	for frame in 4: await process_frame
	server.free_rid(font)
