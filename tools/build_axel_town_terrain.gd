extends "res://tools/test_world3d_mcp.gd"
## A new, native editable terrain document. No old-town records are imported.
const T = preload("res://scripts/world3d/terrain_surface.gd")
const City = preload("res://scripts/world3d/city_layout.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const OUT = "D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014"
const CANDIDATE = "D:/code/rmmo_runtime/cache/world3d/axel_town_terrain_20261014/map.gltf"
const OLD = "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const GRASS = "pack:default:terrain/mossy_grass_vcjmej0s/material"
const ROCK = "pack:default:terrain/icelandic_jagged_slate/material"
var recipe: Dictionary
var report: Dictionary = {}

func persist_report() -> void:
	report.failures = failed
	var file := FileAccess.open(OUT.path_join("terrain_build.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()

func stop_on_error() -> bool:
	if failed == 0: return false
	persist_report()
	if is_instance_valid(editor) and editor._mcp != null: editor._mcp.stop()
	quit(1)
	return true

func wait_view() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if editor._load_job != null and editor._load_job.active: continue
		if editor._ground_batches.stats().get("pending_groups", 0) > 0: continue
		await settle()
		return
	check(false, "native geometry preparation finished")

func ground_at(x: float, z: float) -> float:
	for r: Dictionary in editor._doc.records:
		if not r.has("terrain_mesh"): continue
		var local := Vector3(x-r.position[0],0,z-r.position[2])
		if absf(local.x) <= r.size[0]*.5+.0001 and absf(local.z) <= r.size[2]*.5+.0001:
			return T.sample(r,local)+r.position[1]
	return NAN

func capture(label: String, camera: Dictionary) -> void:
	await call_tool("set_editor_camera", camera)
	await settle()
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = editor._camera.get_viewport().get_texture().get_image()
	var path := OUT.path_join(label+".webp")
	check(frame.save_webp(path, false, .94) == OK, "WebP capture " + label)
	report.images.append({"path":path,"sha256":FileAccess.get_sha256(path),"size":[frame.get_width(),frame.get_height()],"camera":camera})

func tune_water() -> void:
	var metadata: Dictionary=editor._doc.map_meta.duplicate(true)
	for layer: Dictionary in metadata.terrain_rivers:
		var ids: Array=layer.water.map(func(part):return part.id)
		await call_tool("set_river_materials",{"water_ids":ids,"absorption":2.6 if layer.id=="axel_s12_stream" else 2.2,"shallow_color":[.13,.27,.31],"deep_color":[.055,.14,.205]})
		if failed>0:return
		for part: Dictionary in layer.water:
			part.signature=City.token(editor._doc._find(part.id))
	# This is this map's authoring recipe, not a global material-tool bypass.
	# Register the finished water with the same river layer for native rerouting.
	editor._doc.checkpoint_recovery()
	editor._doc.map_meta=metadata
	editor._commit_records([])
	report.water_absorption={"main":2.2,"s12":2.6}

func audit() -> void:
	var terrains: Array = editor._doc.records.filter(func(r): return r.has("terrain_mesh"))
	var maximum_seam := 0.0
	# Sample both sides of every tile edge at the finest shared metre.
	for a: Dictionary in terrains:
		for b: Dictionary in terrains:
			if str(a.uuid) >= str(b.uuid): continue
			var ax := float(a.position[0]); var az := float(a.position[2])
			var bx := float(b.position[0]); var bz := float(b.position[2])
			if absf(absf(ax-bx)-(a.size[0]+b.size[0])*.5)<.001 and absf(az-bz)<.001:
				var x: float = ax+a.size[0]*.5*signf(bx-ax)
				for z in range(int(az-a.size[2]*.5),int(az+a.size[2]*.5)+1):
					maximum_seam=maxf(maximum_seam,absf(T.sample(a,Vector3(x-ax,0,z-az))-T.sample(b,Vector3(x-bx,0,z-bz))))
			if absf(absf(az-bz)-(a.size[2]+b.size[2])*.5)<.001 and absf(ax-bx)<.001:
				var z: float = az+a.size[2]*.5*signf(bz-az)
				for x in range(int(ax-a.size[0]*.5),int(ax+a.size[0]*.5)+1):
					maximum_seam=maxf(maximum_seam,absf(T.sample(a,Vector3(x-ax,0,z-az))-T.sample(b,Vector3(x-bx,0,z-bz))))
	report.max_seam_m=maximum_seam
	check(maximum_seam<.001,"all terrain seams continuous after carving and reopen")
	check(absf(ground_at(156,209)-7.5)<.001,"guild-front spawn pad remains at +7.5m")
	var bridges: Array=[]
	for bridge: Dictionary in recipe.report.bridges:
		var sampled: Array=[]
		for endpoint: Array in bridge.ends: sampled.append(ground_at(endpoint[0],endpoint[1]))
		bridges.append({"ends":bridge.ends,"target":bridge.target,"actual":sampled})
		check(sampled.all(func(h):return absf(h-bridge.target)<.3),"future bridge landing elevations " + str(bridge.ends))
	report.bridge_landings=bridges
	check(editor._doc.records.all(func(r):return r.has("terrain_mesh") or r.get("surface_id")=="water"),"terrain and water only; no buildings, props or characters")
	check(editor._doc.map_meta.terrain_rivers.size()==2,"main river and separate high-level shallow stream saved")
	check(City.valid(editor._doc.map_meta),"native planning and river metadata valid")
	report.records=editor._doc.records.size()
	report.terrain_count=terrains.size()
	report.ground_batching=editor._ground_batches.stats()
	check(report.ground_batching.get("pending_groups",1)==0,"shared static batches ready")
	check(report.ground_batching.get("source_surfaces",0)>report.ground_batching.get("render_surfaces",0),"shared static batching actually reduces source surfaces; spatial singletons remain independent")
	check(FileAccess.get_sha256(OLD)==report.old_map_sha256,"old town file unchanged")

func review_existing() -> void:
	report=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("terrain_build.json")))
	report.images=[];report.phase="candidate_review"
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor);await settle();await wait_view()
	var probe:=TCPServer.new();port=31320
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"review existing candidate over HTTP")
	if "--tune-only" in OS.get_cmdline_user_args():
		for region: Dictionary in preload("res://tools/axel_river_ground_regions.gd").requests(recipe):
			await call_tool("paint_terrain_region",region)
			if stop_on_error():return
		await tune_water()
		await call_tool("save_world")
		await call_tool("open_world",{"path":CANDIDATE})
		await wait_view()
	audit()
	if stop_on_error():return
	if editor._grid!=null:editor._grid.visible=false
	if editor._authoring.marker!=null:editor._authoring.marker.visible=false
	for view:Dictionary in editor._doc.map_meta.editor_layout.bookmarks:
		await capture(view.id,view.camera)
	report.phase="candidate_complete";report.map_sha256=FileAccess.get_sha256(CANDIDATE);persist_report()
	editor._mcp.stop();editor.queue_free();await settle()
	print("AXEL_TERRAIN_REVIEW_COMPLETE failures=",failed)
	quit(0 if failed==0 else 1)

func run() -> void:
	create_timer(850).timeout.connect(func():check(false,"build timeout");persist_report();quit(2))
	rpc_timeout_ms=180000
	Engine.max_fps=60
	root.size=Vector2i(1600,1000)
	root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(OUT)
	recipe=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("recipe.json")))
	if "--review-only" in OS.get_cmdline_user_args() or "--tune-only" in OS.get_cmdline_user_args():
		await review_existing()
		return
	report={"candidate":CANDIDATE,"old_map_sha256":FileAccess.get_sha256(OLD),"recipe_sha256":FileAccess.get_sha256(OUT.path_join("recipe.json")),"images":[],"recipe_report":recipe.report,"phase":"initial_native_document"}
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var grass: Dictionary=library.find(GRASS)
	check(Paint.material_valid(grass) and Paint.missing([{"terrain_material":grass}]).is_empty(),"existing grass PBR available")
	if stop_on_error():return
	var doc=Doc.new()
	doc.records=recipe.records.duplicate(true)
	for r: Dictionary in doc.records:
		r.terrain_material=grass.duplicate(true)
		r.color=[1,1,1]
	check(doc.records.all(func(r):return T.valid(r)),"native heightfield records valid")
	doc.map_meta={"name":"阿克塞尔新城镇 · 地形","map_ref":"default/axel_town","spawn":[156,8.4,209],"editor_view":{"spawn":[156,7.5,209]},"editor_layout":City.defaults(),"environment":{"preset":"day","sun_rotation":[-48,32,0],"sun_energy":1.1,"ambient_energy":.5,"ambient_color":[.85,.9,1.0],"fog_enabled":false,"sky_enabled":true,"weather":"clear","time_hours":12,"time_speed":0,"celestial_cycle":false,"sun_shadows":true,"ambient_occlusion":true,"wind_speed":2,"environment_audio":false},"town_reference":{"core_bounds_xz":[0,0,450,360],"terrain_bounds_xz":[-30,-30,480,390],"phase":"terrain_only","source":"docs/medieval_town_visual_references.md","design_note":"项目补充设计：按450×360米布局分区起伏；参考未给实测标高。建筑、道路、桥梁、城门与植被留待地形后布置。","main_water_level":recipe.main_river.water_level,"s12_water_level":recipe.s12_stream.water_level,"required_shots":["S1 石桥居民街","S2 彩旗居民巷","S10 果树住宅院落","S12 夕阳浅溪汀步街"]}}
	if FileAccess.file_exists(CANDIDATE):
		# This task-owned candidate uses the ordinary conflict-aware save baseline.
		var existing=Doc.open_file(CANDIDATE)
		check(existing!=null,"existing candidate readable")
		if stop_on_error():return
		doc.accept_save(CANDIDATE,existing._disk_signature)
	check(doc.save(CANDIDATE)==OK,"save new candidate through native atomic writer")
	if stop_on_error():return
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false
	editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor)
	await settle();await wait_view()
	var probe:=TCPServer.new();port=31320
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP current 3D editor MCP")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var discovery:=await rpc("tools/list")
	var names: Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(["generate_terrain_river","set_terrain_slope_materials","save_world","open_world"].all(func(n):return n in names),"terrain authoring tools discoverable")
	await call_tool("set_terrain_slope_materials",{"terrain_ids":doc.records.map(func(r):return r.uuid),"rock_material_id":ROCK,"steep_start":38,"steep_end":62})
	if stop_on_error():return
	report.phase="local_river_ground_materials";persist_report()
	var ground_regions: Array=preload("res://tools/axel_river_ground_regions.gd").requests(recipe)
	check(not ground_regions.is_empty(),"localized soft riverbed material requests available")
	for region: Dictionary in ground_regions:
		await call_tool("paint_terrain_region",region)
		if stop_on_error():return
	report.local_ground_regions=ground_regions.size()
	var safe_before: Dictionary=editor._doc.recovery_snapshot()
	var bad_river: Dictionary=recipe.main_river.duplicate(true);bad_river.width=0
	await call_tool("generate_terrain_river",bad_river,false)
	check(equivalent(safe_before,editor._doc.recovery_snapshot()),"invalid river request has no document side effects")
	for key: String in ["main_river","s12_stream"]:
		report.phase=key;persist_report()
		var preview:=await call_tool("preview_terrain_river",recipe[key])
		report[key+"_preview"]=preview
		if stop_on_error():return
		var generated:=await call_tool("generate_terrain_river",recipe[key])
		report[key+"_generated"]=generated
		if stop_on_error():return
	# Test one actual content transaction after HTTP generation.
	var finish:=preload("res://tools/axel_s12_water_finish.gd").apply(editor)
	check(finish.ok,"native S12 round water ends and bank closure")
	if not finish.ok:print(finish)
	report.s12_finish=finish
	if stop_on_error():return
	var after: Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");await call_tool("redo")
	check(equivalent(after,editor._doc.recovery_snapshot()),"shallow stream undo/redo restores native content")
	await tune_water()
	if stop_on_error():return
	var reserves: Array=[[104,77,27,24],[348,75,26,26],[352,146,22,28],[215,205,24,24],[86,235,24,24]]
	var zones: Array=[]
	for i in reserves.size():
		var p: Array=reserves[i]
		zones.append({"id":"R%d"%(i+1),"name":"特殊建筑保留 R%d"%(i+1),"polygon":[[p[0],p[1]],[p[0]+p[2],p[1]],[p[0]+p[2],p[1]+p[3]],[p[0],p[1]+p[3]]],"min_y":-20,"max_y":80,"purpose":"no_build","locked":false,"hidden":false})
	var city:=await call_tool("get_city_layout")
	await call_tool("update_planning_zones",{"expected_token":city.zone_token,"zones":zones})
	var views: Array=[
		["terrain_overview","地形总览",{"projection":"perspective","center":[225,4,180],"distance":455,"yaw":0,"pitch":-58}],
		["s1_bridge_banks","S1 石桥缓岸",{"projection":"perspective","center":[289,4,246],"distance":46,"yaw":-42,"pitch":-23}],
		["s12_stream","S12 浅溪地形",{"projection":"perspective","center":[357,7.8,125.5],"distance":35,"yaw":-70,"pitch":-30}],
		["s2_residential_lane","S2 彩旗居民巷预留机位",{"projection":"perspective","center":[345,7.5,270],"distance":27,"yaw":-90,"pitch":-5}],
		["s10_fruit_court","S10 果树院落预留机位",{"projection":"perspective","center":[106,9.5,130],"distance":16.5,"yaw":-166,"pitch":-5}],
		["spawn_guild_apron","出生点与公会前场",{"projection":"perspective","center":[156,7.5,209],"distance":48,"yaw":-20,"pitch":-32}]
	]
	for view: Array in views:
		await call_tool("set_editor_camera",view[2])
		await call_tool("save_view_bookmark",{"id":view[0],"name":view[1]})
	await call_tool("set_editor_camera",views[0][2])
	await call_tool("save_world")
	if stop_on_error():return
	var before: Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":CANDIDATE})
	await wait_view()
	check(equivalent(before,editor._doc.recovery_snapshot()),"native saved document reopens without data loss")
	audit()
	if stop_on_error():return
	if editor._grid!=null:editor._grid.visible=false
	if editor._city.overlay!=null:editor._city.overlay.visible=false
	if editor._authoring.marker!=null:editor._authoring.marker.visible=false
	for view: Array in views:await capture(view[0],view[2])
	report.phase="candidate_complete";report.map_sha256=FileAccess.get_sha256(CANDIDATE);persist_report()
	editor._mcp.stop();editor.queue_free();await settle()
	print("AXEL_TERRAIN_COMPLETE failures=",failed," report=",OUT.path_join("terrain_build.json"))
	quit(0 if failed==0 else 1)
