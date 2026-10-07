extends SceneTree
var SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var editor: Node3D
const SLOW_FRAME_LIMIT:=12

func progress_sample()->Dictionary:
	return {"phase":editor._load_job.phase,"completed":editor._load_job.completed,"total":editor._load_job.total}

func remember_slow_frame(rows:Array,value:Dictionary)->void:
	if rows.size()>=SLOW_FRAME_LIMIT and value.ms<=rows.back().ms:return
	var index:=0
	while index<rows.size() and rows[index].ms>=value.ms:index+=1
	rows.insert(index,value)
	if rows.size()>SLOW_FRAME_LIMIT:rows.pop_back()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1440,960); root.content_scale_size=root.size
	var output:=OS.get_cmdline_user_args()[0]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):SOURCE=arg.trim_prefix("--source=")
	var hash_before:=FileAccess.get_sha256(SOURCE)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=null; session.world3d_editor_path=SOURCE
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=preload("res://scripts/world3d/map_paths.gd").cache_directory("load_profile_drafts")
	var started:=Time.get_ticks_usec(); root.add_child(editor); editor._safety.enabled=false
	var editor_attach_ms:=(Time.get_ticks_usec()-started)/1000.
	var load_start_offset_ms:float=(editor._load_job._started-started)/1000.
	var frames:=0; var phases:={}; var last:=Time.get_ticks_usec(); var worst:=0.
	var previous:=progress_sample();var slow_frames:Array=[];var capture_us:=0
	while editor._load_job.active:
		await process_frame; frames+=1
		var now:=Time.get_ticks_usec();var gap_ms:=(now-last)/1000.;var current:=progress_sample()
		worst=maxf(worst,gap_ms)
		remember_slow_frame(slow_frames,{"ms":gap_ms,"frame":frames,"elapsed_ms":(now-started)/1000.,"before":previous,"after":current,"probe_capture_ms":capture_us/1000.})
		last=now;previous=current;capture_us=0
		var phase: String=editor._load_job.phase
		if not phases.has(phase):
			phases[phase]=editor._load_job.state()
			if phase in ["read","build"]:
				var capture_started:=Time.get_ticks_usec()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.get_basename()+"_"+phase+".png")
				capture_us=Time.get_ticks_usec()-capture_started
		if Time.get_ticks_usec()-started>500000000: break
	var result:={"load":editor._load_job.state(),"frames":frames,"phases":phases,"max_frame_ms":worst,"slow_frames":slow_frames,"records":editor._doc.records.size(),"source_unchanged":hash_before==FileAccess.get_sha256(SOURCE),"batches":editor._ground_batches.stats()}
	result.source=SOURCE;result.source_sha256=hash_before
	result.editor_attach_ms=editor_attach_ms;result.load_start_offset_ms=load_start_offset_ms
	result.total_editor_elapsed_ms=(Time.get_ticks_usec()-started)/1000.
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("EDITOR_LOAD_PROFILE ",JSON.stringify(result))
	var ok: bool=result.source_unchanged and result.records>0 and editor._load_job.result.get("ok",false)
	# Final visual evidence is captured after metrics are frozen and written.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.get_basename()+"_complete.png")
	editor.queue_free(); for i in 6: await process_frame
	quit(0 if ok else 1)
