extends "res://tools/test_world3d_mcp.gd"
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
const River=preload("res://scripts/world_editor/terrain_river_tools.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")

func ripple_normal(base:Vector3,ripple:Vector3)->Vector3:
	base=base.normalized()
	var axis:=Vector3.RIGHT if absf(base.x)<.99 else Vector3.BACK
	var along:Vector3=(axis-base*axis.dot(base)).normalized()
	return (along*ripple.x*.7+base*ripple.z+along.cross(base).normalized()*ripple.y*.7).normalized()

func run()->void:
	check(ripple_normal(Vector3.UP,Vector3(.2,-.3,.9)).is_equal_approx(Vector3(.14,.9,-.21).normalized()),"water ripple is exactly horizontal-compatible")
	check(ripple_normal(Vector3(.1,1,.05),Vector3(0,0,1)).is_equal_approx(Vector3(.1,1,.05).normalized()),"neutral normal map follows true sloping surface")
	check(not ripple_normal(Vector3(.1,1,.05),Vector3(0,0,1)).is_equal_approx(Vector3.UP),"sloping water no longer forces world-up normal")
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var args:={"id":"slope","terrain_ids":["pending"],"points":[[-12,-2],[0,1],[12,-1]],"water_level":-.3,"water_levels":[-.3,-.8,-1.3],"width":3.,"bank_width":1.,"depth":.6,"natural_materials":false}
	var curve:=Profile.prepare(args)
	check(curve.ok and curve.path.size()==curve.levels.size(),"profile shares exact spline sample count")
	for i in curve.anchors.size():check(absf(curve.levels[curve.anchors[i]]-args.water_levels[i])<.000001,"control point water level preserved")
	check(curve.levels[0]==-.3 and curve.levels[-1]==-1.3,"profile preserves endpoint water levels")
	var monotone:=true
	for i in curve.levels.size()-1:monotone=monotone and curve.levels[i]>=curve.levels[i+1]
	check(monotone,"interpolation cannot overshoot uphill")
	var bad:=args.duplicate(true);bad.water_levels[1]=NAN;check(not Profile.prepare(bad).ok,"nonfinite profile rejected before geometry")
	var flat:=args.duplicate(true);flat.erase("water_levels");check(Profile.prepare(flat).levels.all(func(y):return y==-.3),"legacy scalar preserves flat levels")
	var directory:=Paths.cache_directory("terrain_river_profile_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31921
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"profile real HTTP MCP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_terrain_river" and t.inputSchema.properties.has("water_levels")),"3D discovery exposes shared profile schema")
	var terrain:=await call_tool("create_terrain",{"center":[0,0,0],"width":32.,"depth":32.,"cell_size":1.})
	args.terrain_ids=[terrain.id]
	for invalid in [[-.3,-.8],[-.3,.1,-1.3],["bad",-.8,-1.3]]:
		bad=args.duplicate(true);bad.water_levels=invalid
		var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
		await call_tool("preview_terrain_river",bad,false);await call_tool("generate_terrain_river",bad,false)
		check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"invalid profile HTTP is atomic")
	bad=args.duplicate(true);bad.natural_materials=true;await call_tool("generate_terrain_river",bad,false)
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("preview_terrain_river",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"profile preview is read only")
	var generated:=await call_tool("generate_terrain_river",args)
	check(generated.get("water_ids",[]).size()>1,"profile commits native adaptive water chunks")
	var heights:Dictionary={};var seam:=true;var min_y:=INF;var max_y:=-INF;var sloped:=false
	for id in generated.get("water_ids",[]):
		var r:Dictionary=editor._doc._find(id);check(Channel.valid(r) and r.channel_mesh.has("elevations"),"water uses valid per-vertex elevations")
		for poly:Array in Channel.local_polygons(r):
			for p:Vector3 in poly:
				p+=Vector3(r.position[0],r.position[1],r.position[2]);min_y=minf(min_y,p.y);max_y=maxf(max_y,p.y)
				var key:="%.4f,%.4f"%[p.x,p.z]
				if heights.has(key):seam=seam and absf(heights[key]-p.y)<.00001
				heights[key]=p.y
			if absf(poly[0].y-poly[-1].y)>.00001:sloped=true
	check(seam and sloped and absf(min_y+1.3)<.0001 and absf(max_y+.3)<.0001,"clipped continuous sloped surface preserves endpoints and shared vertices")
	var panel=editor._terrain_panel.river_panel
	check(panel.load_river(args.id) and panel.args().water_levels==args.water_levels,"UI loads exact persisted per-point levels")
	check(panel.profile_toggle.button_pressed and panel.settings.fields.natural_materials.disabled,"UI explains/disables incompatible scalar wet bank")
	panel.point_list.select(1);panel.point_list.item_selected.emit(1);panel.point_level.value=-.9;panel.replace_point()
	check(is_equal_approx(float(panel.args().water_levels[1]),-.9) and equivalent(panel.args().points,args.points),"UI selected point replacement edits water level without changing XZ")
	panel.load_river(args.id)
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"one undo restores profile terrain and water")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores same native profile")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(Layer.valid(editor._doc.map_meta) and editor._doc.map_meta.terrain_rivers[0].request.water_levels==args.water_levels,"profile saves and reopens native metadata")
	await call_tool("remove_terrain_river",{"id":args.id})
	check(editor._doc.map_meta.terrain_rivers.is_empty(),"native profile removal restores terrain")
	print("TERRAIN_RIVER_PROFILE_HTTP failures=",failed," path=",path);quit(failed)
