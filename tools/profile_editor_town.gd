extends SceneTree
## Real editor workload, read-only source map; output and drafts stay in test cache.
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const SOURCE = "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var editor: Node3D
var report := {}
var output := ""
var source := SOURCE
var sample_frames := 180
var views := ["spawn", "bridge", "overview"]
var schematic_records: Array=[]
var render_timing:=false
var minimap_candidate:=""
var frozen_candidate:=""
var building_shadow_compare:=false
var static_preview_compare:=false
var editor_shadow_candidate:=false
var shadow_sources:Array=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 0
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	output = OS.get_cmdline_user_args()[0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source=argument.trim_prefix("--source=")
		if argument.begins_with("--view="): views=[argument.trim_prefix("--view=")]
		if argument.begins_with("--samples="): sample_frames=clampi(int(argument.trim_prefix("--samples=")),30,600)
		if argument.begins_with("--minimap-candidate="): minimap_candidate=argument.trim_prefix("--minimap-candidate=")
		if argument.begins_with("--frozen-candidate="): frozen_candidate=argument.trim_prefix("--frozen-candidate=")
	if "--frozen-compare" in OS.get_cmdline_user_args() and frozen_candidate.is_empty():
		push_error("Frozen comparison requires an explicit external candidate script.")
		quit(1);return
	if "--minimap-compare" in OS.get_cmdline_user_args() and minimap_candidate.is_empty():
		push_error("Minimap experiments require an external candidate script; production keeps direct drawing.")
		quit(1); return
	render_timing="--render-timing" in OS.get_cmdline_user_args()
	building_shadow_compare="--building-shadow-compare" in OS.get_cmdline_user_args()
	static_preview_compare="--static-preview-compare" in OS.get_cmdline_user_args()
	editor_shadow_candidate="--editor-shadow-candidate" in OS.get_cmdline_user_args()
	if building_shadow_compare:preload("res://scripts/world_editor/building_shadow_preview.gd").enabled=editor_shadow_candidate
	if static_preview_compare and (building_shadow_compare or not minimap_candidate.is_empty() or not frozen_candidate.is_empty() or "--road-details" in OS.get_cmdline_user_args()):
		push_error("Static preview comparison must run without other experiments.");quit(1);return
	if building_shadow_compare:
		if "--overlay-only" in OS.get_cmdline_user_args() or "--frozen-compare" in OS.get_cmdline_user_args() or "--minimap-compare" in OS.get_cmdline_user_args() or "--motion" in OS.get_cmdline_user_args():
			push_error("Building shadow comparison requires the unmodified full scene and no concurrent experiments.")
			quit(1);return
		render_timing=true
	var source_hash := FileAccess.get_sha256(source)
	report.source=source
	report.source_sha256=source_hash
	var start := Time.get_ticks_usec()
	var doc
	if "--overlay-only" in OS.get_cmdline_user_args():
		# Read-only attribution fixture: only the authoritative layout is needed,
		# not validation/building of thousands of unrelated scene records.
		var metadata: Dictionary=Doc.authoritative_extras(source)
		if metadata.has("error") or not metadata.has("extras"): quit(1); return
		doc=Doc.new(); doc.map_meta.editor_layout=metadata.extras.get("editor_layout",{}).duplicate(true)
		if "--schematic-records" in OS.get_cmdline_user_args(): schematic_records=metadata.extras.get("rmmo_records",[])
		report.fixture_mode="layout_only_without_document_record_validation"
	else:
		doc=Doc.open_file(source)
		report.fixture_mode="full_document"
	if doc == null: quit(1); return
	report.headless=DisplayServer.get_name()=="headless"
	report.open_ms = (Time.get_ticks_usec()-start)/1000.0
	var directory := Paths.cache_directory("editor_profile_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = directory.path_join("map.gltf")
	session.world3d_editor_doc = doc
	start = Time.get_ticks_usec()
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	editor._safety.enabled = false
	if "--wind-on" in OS.get_cmdline_user_args(): editor._wind_tools.set_preview(true)
	editor._ground_batches.flush()
	if not frozen_candidate.is_empty():
		editor._ground_batches.clear();editor._ground_batches.free()
		editor._ground_batches=load(frozen_candidate).new();editor.add_child(editor._ground_batches)
		editor._sync_ground_batches();editor._ground_batches.flush()
		report.frozen_candidate=frozen_candidate
	if not minimap_candidate.is_empty():
		var old: Control=editor._city.overlay
		var candidate: Control=load(minimap_candidate).new()
		old.get_parent().add_child(candidate); candidate.setup(editor._city)
		editor._city.overlay=candidate; old.free()
		report.minimap_candidate=minimap_candidate
	if "--road-details" in OS.get_cmdline_user_args():
		var old: Control=editor._city.overlay
		var detail:=preload("res://tools/profile_editor_road_overlay.gd").new()
		old.get_parent().add_child(detail); detail.setup(editor._city)
		editor._city.overlay=detail; old.free()
	if static_preview_compare:
		var old:Control=editor._city.overlay
		var probe:=preload("res://tools/profile_editor_static_preview.gd").new()
		old.get_parent().add_child(probe);probe.setup(editor._city)
		editor._city.overlay=probe;old.free()
	editor._city.overlay.profile_enabled=true
	if not schematic_records.is_empty():
		# Only the existing record-space schematic is prepared. No scene build,
		# save or frame runs with these unvalidated read-only probe records.
		doc.records=schematic_records
		editor._city.overlay.refresh()
		doc.records=[]
		report.fixture_mode="layout_and_exact_record_schematic_without_3d_build"
		report.schematic_source_records=schematic_records.size()
		schematic_records=[]
	if render_timing:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		RenderingServer.viewport_set_measure_render_time(editor._camera.get_viewport().get_viewport_rid(),true)
	report.build_ms = (Time.get_ticks_usec()-start)/1000.0
	report.records = doc.records.size()
	report.batches = editor._ground_batches.stats()
	var road_samples := 0
	for points in editor._city.analysis.get("paths",{}).values(): road_samples+=points.size()
	report.roads={"edges":editor._city.data.roads.edges.size(),"nodes":editor._city.data.roads.nodes.size(),"samples":road_samples,"zones":editor._city.data.get("zones",[]).size()}
	print("EDITOR_PROFILE_LOADED ", JSON.stringify(report))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for i in 60: await process_frame
	if building_shadow_compare:
		prepare_building_shadows()
		if shadow_sources.is_empty():
			push_error("No eligible frozen building shadow sources; comparison is invalid.")
			quit(1);return
	if "--motion" in OS.get_cmdline_user_args():
		await motion_samples()
	for view in ([] if "--motion-only" in OS.get_cmdline_user_args() else views):
		var center := Vector3(261.7, 0, 125.9) if view == "bridge" else Vector3.ZERO
		editor._city.apply_camera({"center":[center.x,center.y,center.z],"distance":35.0,"pitch":-35.0,"yaw":0.0,"span":1500.0,"projection":"top" if view=="overview" else "perspective"})
		for i in 30: await process_frame
		if static_preview_compare:
			editor._city.pending=[[center.x,0.,center.z],[center.x+4.,0.,center.z+3.]]
			for round_index in 2:
				for phase in 4:
					editor._city.overlay.repeat_road_redraw=phase in [0,3]
					var label:String=view+"_preview_abba_%d_%d"%[round_index,phase]
					await sample(label,false)
					report[label].road_mode="repeated" if phase in [0,3] else "retained"
			editor._city.pending.clear()
			continue
		if building_shadow_compare:
			for round_index in 2:
				for phase in 4:
					var proxy_mode:bool=phase in [1,2]
					set_building_shadows(proxy_mode)
					var label:String=view+"_shadow_abba_%d_%d"%[round_index,phase]
					await sample(label,true)
					report[label].building_shadow_mode="proxy" if proxy_mode else "original"
					if "--shadow-screenshots" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
						for i in 3:await process_frame
						await RenderingServer.frame_post_draw
						var image_path:String=output.get_basename()+"_"+label+".png"
						var capture_error:Error=editor._camera.get_viewport().get_texture().get_image().save_png(image_path)
						report[label].screenshot={"path":image_path,"error":capture_error,"note":"Same restored camera; live environment may advance. This is a visual inspection aid, not deterministic pixel equivalence."}
			set_building_shadows(false)
			continue
		if "--frozen-compare" in OS.get_cmdline_user_args():
			for phase in ["direct","merged","direct_repeat"]:
				editor._ground_batches.frozen_houses_enabled=phase=="merged"
				editor._ground_batches.sync(editor._view.get_children(),editor._selection_tools.ids)
				editor._ground_batches.flush()
				for i in 90:await process_frame
				report[view+"_"+phase+"_batches"]=editor._ground_batches.stats()
				await sample(view+"_"+phase,true)
			continue
		if "--minimap-compare" in OS.get_cmdline_user_args():
			if "--abba" in OS.get_cmdline_user_args():
				for round_index in 2:
					for phase in 4:
						editor._city.overlay.minimap_cache_enabled=phase in [1,2]
						await sample(view+"_abba_%d_%d"%[round_index,phase],true)
				continue
			editor._city.overlay.minimap_cache_enabled=false
			await sample(view+"_minimap_direct",true)
			editor._city.overlay.minimap_cache_enabled=true
			await sample(view+"_minimap_cached",true)
			editor._city.overlay.minimap_cache_enabled=false
			await sample(view+"_minimap_direct_repeat",true)
			continue
		await sample(view+"_normal", false)
		await sample(view+"_moving", true)
		if "--road-details" in OS.get_cmdline_user_args():
			report[view+"_hoist_equivalent"]=editor._city.overlay.check_hoist()
			editor._city.overlay.hoisted_cull=true
			await sample(view+"_moving_hoisted",true)
			editor._city.overlay.hoisted_cull=false
		editor._city.overlay._roads_layer.hide()
		await sample(view+"_moving_no_roads", true)
		editor._city.overlay._roads_layer.show()
		editor._city.overlay.set_process(false)
		editor._city.overlay.hide()
		await sample(view+"_moving_no_overlay", true)
		await sample(view+"_no_overlay", false)
		editor._city.overlay.set_process(true)
		editor._city.overlay.show()
	report.source_unchanged = FileAccess.get_sha256(source)==source_hash
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EDITOR_PROFILE_DONE ", output)
	editor.queue_free()
	for i in 6: await process_frame
	quit(0 if report.source_unchanged else 1)

func sample(label: String, moving: bool) -> void:
	for i in (90 if building_shadow_compare or static_preview_compare else (60 if "--minimap-compare" in OS.get_cmdline_user_args() else 10)): await process_frame
	var frames: Array = []
	var process: Array = []
	var physics: Array = []
	var draw: Array = []
	var render_parts: Dictionary={"root_cpu_ms":[],"root_gpu_ms":[],"scene_cpu_ms":[],"scene_gpu_ms":[]}
	var render_calls:Dictionary={"scene_visible":[],"scene_shadow":[],"root_visible":[],"root_shadow":[]}
	var overlay = editor._city.overlay
	var parts := {}; var totals := {}; var calls := {}
	for key in overlay.profile_cpu_us:
		parts[key]=[]; totals[key]=0; calls[key]=0
	var overall: Array=[]
	var previous_cpu: Dictionary=overlay.profile_cpu_us.duplicate()
	var previous_calls: Dictionary=overlay.profile_calls.duplicate()
	var initial_batches: Dictionary=editor._ground_batches.stats()
	var initial_camera: Transform3D=editor._camera.transform
	var initial_center: Vector3=editor._orbit_center
	var before := Time.get_ticks_usec()
	for i in sample_frames:
		if moving: editor._city.move_camera(Vector3(.05 if i<sample_frames/2 else -.05,0,0))
		await process_frame
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now-before)/1000.0); before=now
		process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if render_timing:
			for entry in [["root",root],["scene",editor._camera.get_viewport()]]:
				var rid: RID=entry[1].get_viewport_rid()
				render_parts[entry[0]+"_cpu_ms"].append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
				render_parts[entry[0]+"_gpu_ms"].append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
				render_calls[entry[0]+"_visible"].append(entry[1].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
				render_calls[entry[0]+"_shadow"].append(entry[1].get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		var inclusive := 0
		for key in parts:
			var elapsed: int=overlay.profile_cpu_us[key]-previous_cpu[key]
			parts[key].append(elapsed/1000.0); totals[key]+=elapsed
			calls[key]+=overlay.profile_calls[key]-previous_calls[key]
			if key!="projection" and not key.ends_with("_detail"): inclusive+=elapsed # Nested timers are already included.
		overall.append(inclusive/1000.0)
		previous_cpu=overlay.profile_cpu_us.duplicate(); previous_calls=overlay.profile_calls.duplicate()
	editor._camera.transform=initial_camera; editor._orbit_center=initial_center; editor._city.update_grid()
	frames.sort(); process.sort(); physics.sort(); draw.sort(); overall.sort()
	var mid:=sample_frames/2; var p95:=mini(sample_frames-1,int(sample_frames*.95)); var p99:=mini(sample_frames-1,int(sample_frames*.99))
	report[label] = {"median_ms":frames[mid],"p95_ms":frames[p95],"p99_ms":frames[p99],"max_ms":frames[-1],"process_median_ms":process[mid],"draw_calls":draw[mid],"sample_frames":sample_frames}
	report[label].physics_monitor_median_ms=physics[mid]
	if render_timing:
		report[label].render_time={"note":"Viewport timestamp queries may lag; compare steady-state medians, not exact frame attribution."}
		for key in render_parts:
			render_parts[key].sort()
			report[label].render_time[key]={"median":render_parts[key][mid],"p95":render_parts[key][p95]}
		report[label].viewport_draw_calls={}
		for key in render_calls:
			render_calls[key].sort()
			report[label].viewport_draw_calls[key]={"median":render_calls[key][mid],"p95":render_calls[key][p95]}
	if "minimap_cache_enabled" in overlay:
		report[label].minimap_cache={"enabled":overlay.minimap_cache_enabled,"active":overlay._mini_cached,"schematic_boxes":overlay.boxes.size()}
	report[label].monitor_note="Performance process/physics monitors are coarse diagnostics, not per-frame callback attribution."
	report[label].overlay_cpu={"median_ms":overall[mid],"p95_ms":overall[p95],"max_ms":overall[-1],"parts":{},"projection_inclusive":true,"detail_clock_overhead":"road detail wrappers add per-call clocks; use normal mode for final frame comparison"}
	for key in parts:
		parts[key].sort()
		report[label].overlay_cpu.parts[key]={"median_ms":parts[key][mid],"p95_ms":parts[key][p95],"max_ms":parts[key][-1],"total_ms":totals[key]/1000.0,"calls":calls[key]}
	var final_batches: Dictionary=editor._ground_batches.stats()
	report[label].batch_delta={"sync":final_batches.sync_count-initial_batches.sync_count,"rebuild":final_batches.rebuild_count-initial_batches.rebuild_count,"groups":final_batches.groups,"pending":final_batches.pending_groups}
	print("EDITOR_SAMPLE ",label," ",JSON.stringify(report[label]))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func prepare_building_shadows()->void:
	var shadow=preload("res://scripts/world3d/building_shadow_proxy.gd")
	var started:=Time.get_ticks_usec()
	var was_enabled:bool=shadow.enabled
	shadow.enabled=true
	var before:Dictionary=shadow.stats()
	var candidates:=0
	var groups:Dictionary={}
	# Use an explicit snapshot: attach adds a runtime-only mesh child. Never
	# traverse that child again or expose it to editor selection/body generation.
	var nodes:Array=preload("res://scripts/world3d/surface_materials.gd").meshes(editor._view)
	for node:MeshInstance3D in nodes:
		var record:Dictionary=node.get_meta("ground_batch_record",{})
		if not record.has("house_prefab") or not record.has("building"):continue
		candidates+=1
		var original:int=node.cast_shadow
		if editor_shadow_candidate:
			if not node.has_meta("editor_shadow_monitor") or not node.has_meta("building_shadow_proxy"):continue
			original=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif not shadow.attach(node):continue
		shadow_sources.append({"source":node,"proxy":node.get_meta("building_shadow_proxy"),"original":original})
		var role:String="fixture" if record.has("fixture") else str(record.building.get("role","unknown"))
		if not groups.has(role):groups[role]={"sources":0,"source_surfaces":0,"proxy_surfaces":0}
		groups[role].sources+=1;groups[role].source_surfaces+=node.mesh.get_surface_count()
		groups[role].proxy_surfaces+=node.get_meta("building_shadow_proxy").mesh.get_surface_count()
	shadow.enabled=was_enabled
	report.building_shadow_setup={"ms":(Time.get_ticks_usec()-started)/1000.,"candidates":candidates,"attached":shadow_sources.size(),"before":before,"after":shadow.stats(),"groups":groups,"production_editor_unchanged":not editor_shadow_candidate,"restricted_editor_contract":editor_shadow_candidate}
	set_building_shadows(false)
	print("EDITOR_SHADOW_SETUP ",JSON.stringify(report.building_shadow_setup))

func set_building_shadows(proxy_mode:bool)->void:
	for row:Dictionary in shadow_sources:
		row.source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if proxy_mode else row.original
		row.proxy.visible=proxy_mode

func motion_samples() -> void:
	for kind in ["asset", "building"]:
		var record: Dictionary = {}
		for candidate in editor._doc.records:
			if kind=="asset" and candidate.get("kind")=="asset" and not candidate.has("house_prefab"): record=candidate; break
			if kind=="building" and candidate.has("building"): record=candidate; break
		if record.is_empty(): continue
		var start := Time.get_ticks_usec()
		editor._selection_tools.set_ids([str(record.uuid)])
		var selection_ms := (Time.get_ticks_usec()-start)/1000.0
		editor._ground_batches.flush()
		var origin: Vector3 = editor._selection_tools.pivot()
		editor._city.apply_camera({"center":[origin.x,origin.y,origin.z],"distance":45.,"pitch":-35.,"yaw":0.,"span":100.,"projection":"perspective"})
		for i in 10: await process_frame
		var screen: Vector2 = editor._camera.unproject_position(origin)
		start = Time.get_ticks_usec()
		var begun: bool = editor._transform_drag.begin(editor,screen,0)
		var begin_ms := (Time.get_ticks_usec()-start)/1000.0
		var updates: Array=[]
		if begun:
			for i in 5:
				start=Time.get_ticks_usec()
				editor._transform_drag.update(screen+Vector2(5+i*2,0),true)
				updates.append((Time.get_ticks_usec()-start)/1000.0)
				await process_frame
		start=Time.get_ticks_usec()
		editor._transform_drag.finish(true)
		var cancel_ms := (Time.get_ticks_usec()-start)/1000.0
		start=Time.get_ticks_usec()
		var moved: Dictionary=editor._selection_tools.apply_transform(Vector3(0,50,0),Basis.IDENTITY,1.)
		var commit_ms := (Time.get_ticks_usec()-start)/1000.0
		report[kind+"_motion"]={"uuid":record.uuid,"members":editor._selection_tools.ids.size(),"selection_ms":selection_ms,"begin_ms":begin_ms,"update_ms":updates,"cancel_ms":cancel_ms,"commit_ms":commit_ms,"result":moved}
		if moved.get("ok",false) and moved.get("changed",false):
			start=Time.get_ticks_usec(); editor._undo()
			report[kind+"_motion"].undo_ms=(Time.get_ticks_usec()-start)/1000.0
			start=Time.get_ticks_usec(); editor._redo()
			report[kind+"_motion"].redo_ms=(Time.get_ticks_usec()-start)/1000.0
			editor._undo()
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("EDITOR_MOTION ",kind," ",JSON.stringify(report[kind+"_motion"]))
		editor._selection_tools.set_ids([]); editor._ground_batches.flush()
		editor._city.refresh()
