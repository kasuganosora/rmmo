extends "res://tools/apply_medieval_town_terrain.gd"
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/terrain_furrows/town"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_furrows/map.gltf"
	create_timer(600).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var report:={}
	for stage in (["after"] if "--after-only" in OS.get_cmdline_user_args() else ["before","after"]):
		var doc=Doc.open_file(SOURCE if stage=="before" else CANDIDATE)
		var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=SOURCE if stage=="before" else CANDIDATE; session.world3d_editor_doc=doc
		editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("review_drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
		var probe:=TCPServer.new(); port=31130
		while probe.listen(port,"127.0.0.1")!=OK: port+=1
		probe.stop(); check(editor.start_mcp(port).ok,"review MCP")
		editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
		await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":1480})
		report[stage]=await measure()
		if stage=="after":
			await capture("farm",{"projection":"perspective","center":[-350,0,-675],"distance":95,"pitch":-52,"yaw":15})
			await capture("farm_close",{"projection":"perspective","center":[-360,0,-675],"distance":10,"pitch":-40,"yaw":12})
			for i in 30: await process_frame
			await RenderingServer.frame_post_draw
			var image_a: Image=editor._camera.get_viewport().get_texture().get_image()
			for i in 30: await process_frame
			await RenderingServer.frame_post_draw
			var repeat: Image=editor._camera.get_viewport().get_texture().get_image()
			editor._ground_batches.clear()
			for i in 30: await process_frame
			await RenderingServer.frame_post_draw
			var image_b: Image=editor._camera.get_viewport().get_texture().get_image(); var difference:=0.
			image_a.save_png(OUTPUT.path_join("farm_merged.png")); image_b.save_png(OUTPUT.path_join("farm_unmerged.png")); repeat.save_png(OUTPUT.path_join("farm_repeat.png"))
			for z in range(0,image_a.get_height(),3):
				for x in range(0,image_a.get_width(),3):
					var a:=image_a.get_pixel(x,z); var b:=image_b.get_pixel(x,z); difference+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			difference/=float(image_a.get_width()*image_a.get_height())/3.
			check(difference<.001,"town farm merged/unmerged render agreement")
			report.farm_batch_image_difference=difference
		editor._mcp.stop(); editor.queue_free(); await settle()
	report.failures=failed; report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	report.note="Fresh after-only scene without simultaneous GPU tests; no previous scene material cache." if "--after-only" in OS.get_cmdline_user_args() else "Sequential same-size viewport without simultaneous GPU tests; texture memory after includes previous materials retained by static caches."
	var f:=FileAccess.open(OUTPUT.path_join("performance.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close(); quit(1 if failed else 0)
