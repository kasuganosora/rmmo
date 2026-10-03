extends "res://tools/apply_medieval_town_materials.gd"
var progress: FileAccess
func check(ok: bool,label_: String) -> void:
	super.check(ok,label_)
	if progress: progress.store_line(("PASS " if ok else "FAIL ")+label_); progress.flush()
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_river_materials"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_river_materials/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT); progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--publish" in OS.get_cmdline_user_args():
		var tests: Variant=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/river_materials/result.json"))
		check(tests is Dictionary and tests.get("failures",1)==0,"HTTP/UI/runtime regression passed")
		if failed: quit(1); return
		publish(); return
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open town")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true)
	var result:=preload("res://tools/medieval_town_river_materials.gd").apply(doc)
	check(result.ok,"shared river material operation: "+JSON.stringify(result))
	if not result.ok: quit(1); return
	var stripped: Array=doc.records.duplicate(true)
	for r in stripped:
		r.erase("terrain_depth_blend"); r.erase("water_depth_effect")
	var before: Array=original.duplicate(true)
	for r in before:
		r.erase("terrain_depth_blend"); r.erase("water_depth_effect")
	check(equivalent(stripped,before),"all geometry, collision, roads, heights, holes, original materials and IDs unchanged")
	check(result.water_count==163 and result.terrain_count>0,"all 163 water chunks and riverbed terrain targeted")
	check(Paint.missing(doc.records).is_empty(),"2K sand/rock/water dependencies available")
	if failed: quit(1); return
	if not "--review" in OS.get_cmdline_user_args(): check(doc.save(CANDIDATE)==OK,"atomic native candidate save")
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and equivalent(doc.records,reopened.records),"river materials survive native reopen")
	if failed: quit(1); return
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=reopened
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30560
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"full town HTTP MCP")
	var terrains:=await call_tool("list_terrains")
	check(terrains.terrains.filter(func(r):return not r.depth_blend.is_empty()).size()==result.terrain_count,"HTTP reports configured town terrain")
	var errors:=0; var count:=0
	for n in editor._view.get_children():
		if n.has_meta("paint_error") or n.has_meta("tile_error"): errors+=1
		if n is MeshInstance3D and n.get_active_material(0) is ShaderMaterial: count+=1
	check(errors==0 and count==result.water_count+result.terrain_count,"all target meshes render shader effects without geometry errors")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-48,"yaw":-18})
	var overlays:={}
	for r in editor._doc.records:
		if r.has("terrain_depth_blend"):
			var n: MeshInstance3D=editor._view.get_node(NodePath(r.uuid)); overlays[r.uuid]=n.get_surface_override_material(0); n.set_surface_override_material(0,null)
	await capture("river_bridge_original_ground",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-48,"yaw":-18})
	for id in overlays: editor._view.get_node(NodePath(id)).set_surface_override_material(0,overlays[id])
	await capture("river_close",{"projection":"perspective","center":[338,-1.5,-125],"distance":34,"pitch":-38,"yaw":30})
	await capture("south_bank",{"projection":"perspective","center":[215,-1,350],"distance":200,"pitch":-55,"yaw":0})
	for r in editor._doc.records:
		if r.has("water_depth_effect"): editor._view.get_node(NodePath(r.uuid)).hide()
	await capture("exposed_bed",{"projection":"perspective","center":[338,-1.5,-125],"distance":34,"pitch":-50,"yaw":30})
	var report:={"failures":failed,"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"configuration":result,"reviewed":true}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
