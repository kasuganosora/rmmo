extends "res://tools/test_world3d_mcp.gd"
## Content-only replacement. Review a separate candidate before --publish.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var OUTPUT:="D:/code/rmmo_runtime/review_artifacts/medieval_town_materials"
var CANDIDATE:="D:/code/rmmo_runtime/cache/world3d/medieval_town_materials/map.gltf"
var ROAD:="pack:default:paving/granite_cobble/material"
const WATER="pack:default:water/river_ripples/material"
var road_only:=false

func run() -> void:
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--flagstone" in OS.get_cmdline_user_args():
		road_only=true
		ROAD="pack:default:paving/outdoor_flagstone/material"
		OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_flagstone"
		CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_flagstone/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if "--publish" in OS.get_cmdline_user_args(): publish(); return
	var doc=Doc.open_file(SOURCE)
	check(doc!=null,"open original town")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE)
	var original: Array=doc.records.duplicate(true)
	var library:=Library.new(); var road:=library.find(ROAD); var water:=library.find(WATER)
	check(not road.is_empty() and not water.is_empty(),"both finished materials resolve from default pack")
	if failed: quit(1); return
	var roads:=0; var rivers:=0; var road_tool:=preload("res://scripts/world_editor/road_tools.gd").new()
	for record in doc.records:
		if record.has("road_mesh"):
			var result:=road_tool.paint_default(record,road)
			if not result.ok: check(false,"road paint: "+str(result)); quit(1); return
			roads+=1
		elif record.has("channel_mesh") and record.surface_id=="water":
			if road_only:
				rivers+=1
				continue
			var node:=MeshInstance3D.new(); node.mesh=preload("res://scripts/world3d/channel_surface.gd").mesh(record,null)
			var geometry:=Paint.geometry(node); node.free()
			if not geometry.ok: check(false,"water geometry"); quit(1); return
			var surface: Dictionary=geometry.surfaces[0]; var entries: Array=[]
			for face in surface.faces:
				entries.append({"mesh":".","surface":0,"face":face,"geometry":surface.signature,"material":water.duplicate(true),"mapping":"uv","scale":[.25,.25],"offset":[0,0],"rotation":0.0})
			record.surface_paint=entries
			if not Paint.valid(record): check(false,"water paint schema"); quit(1); return
			rivers+=1
	var stripped: Array=doc.records.duplicate(true); var before: Array=original.duplicate(true)
	for rows in [stripped,before]:
		for r in rows:
			if not road_only or r.has("road_mesh"): r.erase("surface_paint")
	check(equivalent(stripped,before),"geometry, identities, terrain and collision remain identical")
	check(roads==793 and rivers==155,"793 road/plaza chunks; 155 river chunks "+("preserved" if road_only else "repainted"))
	check(Paint.missing(doc.records).is_empty(),"all material dependencies available")
	print("SAVING_CANDIDATE")
	check(doc.save(CANDIDATE)==OK,"save independent native candidate")
	if failed: quit(1); return
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and equivalent(reopened.records,doc.records),"paint geometry signatures survive native reopen")
	if failed: quit(1); return
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=reopened
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30410
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real loopback HTTP MCP")
	var catalog:=await call_tool("list_surface_materials",{})
	for id in ([ROAD] if road_only else [ROAD,WATER]): check(catalog.materials.any(func(r):return r.material_id==id),"MCP discovers "+id)
	var painted:=0; var errors:=0
	for child in editor._view.get_children():
		if child.has_meta("paint_error"): errors+=1
		if not child is MeshInstance3D: continue
		var found:=false
		for slot in child.mesh.get_surface_count():
			var mat=child.get_active_material(slot)
			if mat is StandardMaterial3D and mat.resource_name in ([road.name] if road_only else [road.name,water.name]):
				found=found or (mat.normal_enabled and mat.normal_texture!=null)
		if found: painted+=1
	check(errors==0 and painted==(793 if road_only else 948),"all replaced meshes render correct materials with normals")
	if not road_only:
		await call_tool("set_environment",{"sky_enabled":true})
		await call_tool("save_world")
	await call_tool("open_world",{"path":CANDIDATE})
	check(equivalent(editor._doc.records,reopened.records),"HTTP save/reopen retains all material records")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	await capture("market",{"projection":"perspective","center":[-35,0,1.4],"distance":65,"pitch":-35,"yaw":22})
	await capture("paving_close",{"projection":"perspective","center":[-35,0,1.4],"distance":9,"pitch":-42,"yaw":22})
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-42,"yaw":-18})
	if not road_only: await capture("river_close",{"projection":"perspective","center":[350,-1.5,-125],"distance":24,"pitch":-30,"yaw":35})
	await call_tool("recall_view_bookmark",{"id":"whole_town"})
	# Camera calls are view-only; persist the overview, not the last close-up.
	if not road_only: await call_tool("save_world")
	var report:={"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"road_chunks":roads,"water_chunks":rivers,"failures":failed,"road_material":ROAD,"road_only":road_only,"water_material":("unchanged" if road_only else WATER),"terrain_materials":"unchanged; bank/grass distribution is separate authoring work"}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle()
	print("TOWN_MATERIALS_VERIFIED failures=",failed); quit(1 if failed else 0)

func capture(label: String, camera: Dictionary) -> void:
	await call_tool("set_editor_camera",camera); await settle(); await RenderingServer.frame_post_draw
	check(editor._camera.get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))==OK,"render "+label)

func publish() -> void:
	var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("result.json")))
	if not report is Dictionary or report.get("failures",1)!=0: check(false,"verified candidate required"); quit(1); return
	if FileAccess.get_sha256(SOURCE)!=report.source_sha256 or FileAccess.get_sha256(CANDIDATE)!=report.candidate_sha256:
		check(false,"source or reviewed candidate changed; refusing overwrite"); quit(1); return
	var original=Doc.open_file(SOURCE); var candidate=Doc.open_file(CANDIDATE)
	if original==null or candidate==null: quit(1); return
	original.records=candidate.records.duplicate(true); original.map_meta=candidate.map_meta.duplicate(true)
	check(original.save(SOURCE)==OK,"atomic native publication with original conflict baseline")
	var published=Doc.open_file(SOURCE)
	check(published!=null and equivalent(published.records,candidate.records) and equivalent(published.map_meta,candidate.map_meta),"published town matches reviewed candidate")
	if failed==0:
		DirAccess.copy_absolute(OUTPUT.path_join("overview.png"),SOURCE.get_base_dir().path_join("preview.png"))
		report.published_sha256=FileAccess.get_sha256(SOURCE)
		var f:=FileAccess.open(OUTPUT.path_join("published.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("TOWN_MATERIALS_PUBLISHED failures=",failed); quit(1 if failed else 0)
