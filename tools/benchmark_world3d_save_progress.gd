extends "res://tools/test_world3d_save_progress.gd"
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280,900); root.content_scale_size = root.size
	create_timer(600).timeout.connect(func(): quit(2))
	var source := "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var signature := FileAccess.get_sha256(source)
	var path := Paths.cache_directory("town_progress_%d" % Time.get_ticks_usec()).path_join("map.gltf")
	var doc = Doc.open_file(source)
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc = doc; session.world3d_editor_path = path
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=path.get_base_dir().path_join("drafts")
	root.add_child(editor); editor._safety.enabled=false
	await settle()
	process_frame.connect(track_frame)
	var reports := []
	for i in 2:
		phases.clear(); frame_gaps.clear(); previous_frame=0
		editor._save_async()
		var captured := false
		while editor.saving():
			await process_frame
			if not captured and editor._save_job.state().phase=="textures":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(Art.review_path("save_progress/town_status_%d.png" % i))
				captured=true
		frame_gaps.sort()
		reports.append({"save":editor._save_job.state(),"phases":phases.keys(),"frames":frame_gaps.size(),"max_frame_ms":frame_gaps.max(),"p95_frame_ms":frame_gaps[int(frame_gaps.size()*.95)]})
		print("TOWN_PROGRESS ",reports.back())
	var reopened = Doc.open_file(path)
	var ok: bool = reopened!=null and equivalent(reopened.records,doc.records) and FileAccess.get_sha256(source)==signature and reports.all(func(r): return r.save.result.ok)
	var file := FileAccess.open(Art.review_path("save_progress/town.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"source":source,"source_sha256":signature,"output":path,"runs":reports},"\t")); file.close()
	editor.queue_free(); await settle(); quit(0 if ok else 1)
