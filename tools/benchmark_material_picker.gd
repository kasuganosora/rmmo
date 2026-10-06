extends "res://tools/test_material_picker_ui.gd"

func wait_thumbnails(panel) -> void:
	for i in 600:
		await process_frame
		if panel._catalog_thread == null and not panel._visible_dirty and panel._loader._thread == null and panel._loader._pending.is_empty(): return
	check(false, "thumbnail worker completes within the test budget")

func review_workspace(editor: Node3D) -> void:
	var panel = editor._material_panel
	editor._dock_tabs.current_tab = 3
	await wait_thumbnails(panel)
	var cache_dir := Paths.cache_directory("surface_material_thumbnails").path_join("__benchmark_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(cache_dir)
	panel._loader.directory = cache_dir
	panel._loader.cache.clear(); panel._loader._lru.clear()
	panel._loader.decode_count = 0; panel._loader.max_upload_usec = 0
	panel._loader.source_decode_count = 0; panel._loader.disk_hit_count = 0; panel._loader.cache_write_count = 0
	panel._refresh_materials(); panel._show_current()
	await wait_thumbnails(panel)
	var first_loads: int = panel._loader.decode_count
	check(first_loads <= panel._visible_indices.size() + 1 and first_loads < panel._entries.size(), "cold open loads only visible thumbnails and current selection")
	check(panel._loader.cache_write_count == first_loads, "missing thumbnails are generated and persisted in the background")
	var count: int = panel._loader.decode_count
	var refresh_start := Time.get_ticks_usec()
	panel.refresh()
	var refresh_ms := (Time.get_ticks_usec() - refresh_start) / 1000.0
	await wait_thumbnails(panel)
	check(panel._loader.decode_count == count, "library refresh reuses unchanged thumbnails")
	panel.search.text = "no_such_material_999"; panel.search.text_changed.emit(panel.search.text)
	await wait_thumbnails(panel)
	panel.search.text = ""; panel.search.text_changed.emit("")
	await wait_thumbnails(panel)
	check(panel._loader.decode_count == count, "clearing and restoring search reuses thumbnail cache")
	panel.picker.get_v_scroll_bar().value = panel.picker.get_v_scroll_bar().max_value
	await wait_thumbnails(panel)
	check(panel._visible_indices.has(panel.picker.item_count - 1), "scrolling schedules bottom-of-list thumbnails")
	check(panel._loader.decode_count > count, "newly visible materials decode on demand")
	var unpinned := true
	for index in panel.picker.item_count:
		if not panel._visible_indices.has(index): unpinned = unpinned and panel.picker.get_item_icon(index) == panel._placeholder
	check(unpinned, "offscreen list items release texture references")
	editor._dock_tabs.current_tab = 0
	count = panel._loader.decode_count
	await frames(20)
	check(panel._loader.decode_count == count and panel._loader._pending.is_empty(), "hidden material page schedules no more decoding")
	var second = preload("res://scripts/world_editor/material_thumbnails.gd").new()
	second.directory = cache_dir; second.placeholder = panel._placeholder; root.add_child(second)
	var wanted: Array = []
	for index in panel._visible_indices: wanted.append(panel._filtered[index])
	second.request(wanted)
	for i in 600:
		await process_frame
		if second._thread == null and second._pending.is_empty(): break
	check(second.disk_hit_count > 0 and second.source_decode_count == 0, "new loader reads persistent small images without decoding original textures")
	var synthetic: Array = []
	for i in 110:
		var entry := {"material_id":"fixture_%d" % i, "material":{"name":"fixture_%d" % i,"color":[0.3,0.4,0.5,1.0]}}
		preload("res://scripts/world_editor/material_thumbnails.gd").prepare(entry)
		synthetic.append(entry)
	second.request(synthetic)
	for i in 1000:
		await process_frame
		if second._thread == null and second._pending.is_empty(): break
	check(second.cache.size() <= 96 and second.cache_write_count == 110, "memory cache stays bounded after browsing over 96 materials")
	second.queue_free(); await frames()
	var result := {"library_count":panel._entries.size(),"cold_open_decodes":first_loads,"cache_count":panel._loader.cache.size(),"refresh_ms":refresh_ms,"source_decodes":panel._loader.source_decode_count,"generated_files":panel._loader.cache_write_count,"max_main_thread_upload_ms":panel._loader.max_upload_usec / 1000.0}
	print("THUMBNAIL_OPTIMIZED ", JSON.stringify(result))
	var file := FileAccess.open(preload("res://scripts/asset/art_paths.gd").review_path("material_picker/performance_after.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result)); file.close()
	editor._dock_tabs.current_tab = 3
	panel.picker.get_v_scroll_bar().value = 0
	await wait_thumbnails(panel); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("material_picker/optimized.png"))
	panel._loader.request([])
	await wait_thumbnails(panel)
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(cache_dir)
