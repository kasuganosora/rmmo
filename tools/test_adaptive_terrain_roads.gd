extends "res://tools/test_world3d_mcp.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Fit=preload("res://scripts/world3d/terrain_projection.gd")
const Adaptive=preload("res://scripts/world3d/road_terrain_fit.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")

func terrain(undulating:bool=false)->Dictionary:
	var heights:Array=[]
	for z in 65:
		for x in 65:heights.append(.015*x*.5+.01*z*.5+(.025*sin(x*.75)*cos(z*.6)+.006*sin(x*1.73+z*1.27) if undulating else 0.))
	var holes:Array=[];holes.resize(4096);holes.fill(false)
	return {"uuid":"fine_ground","kind":"box","surface_id":"ground","collision":"walk","color":[.3,.4,.2],"position":[16.,0.,16.],"rotation":[0,0,0],"size":[32.,1.,32.],"terrain_mesh":{"version":1,"columns":64,"rows":64,"floor":-8.,"heights":heights,"holes":holes}}

func graph()->Dictionary:
	return {"nodes":[{"id":"a","position":[6.,.25,16.]},{"id":"b","position":[26.,.55,16.]}],"edges":[{"id":"lane","from":"a","to":"b","width_start":8.,"width_end":8.,"kind":"ground"}]}

func area(records:Array)->float:
	var total:=0.
	for record:Dictionary in records:
		for polygon:Array in Surface.local_polygons(record):total+=Poly.area(polygon.map(func(p):return Vector2(p.x,p.z)))
	return total

func kerb_length(records:Array)->float:
	var total:=0.
	for r:Dictionary in records:
		for k:Dictionary in r.road_mesh.get("kerbs",[]):total+=k.length
	return total

func paint_faces(record:Dictionary)->int:
	var mesh:=MeshInstance3D.new();mesh.mesh=Surface.mesh(record,null)
	var geometry:=Paint.geometry(mesh);mesh.free()
	return geometry.surfaces[0].faces.size() if geometry.ok else -1

func bridge_kerb_openings(records:Array,endpoints:Array)->bool:
	# This fixture runs east/west. Both portal planes must stay traversable,
	# with two open side strips ending at each portal and no transverse strip.
	for endpoint:Array in endpoints:
		var side_caps:=0
		for record:Dictionary in records:
			for kerb:Dictionary in record.road_mesh.get("kerbs",[]):
				var a:=City.vec(kerb.a[0])+City.vec(record.position)
				var b:=City.vec(kerb.b[0])+City.vec(record.position)
				if absf(a.x-endpoint[0])<.001 and absf(b.x-endpoint[0])<.001:return false
				if kerb.cap_a and absf(a.x-endpoint[0])<.001:side_caps+=1
				if kerb.cap_b and absf(b.x-endpoint[0])<.001:side_caps+=1
		if side_caps!=2:return false
	return true

func logical()->void:
	var ground:=terrain();var settings:=Plan.defaults().merged({"follow_terrain":true,"kerb_enabled":true},true)
	var plan:=Plan.build(graph(),settings);check(plan.ok,"fine terrain road footprint with continuous kerbs builds")
	if not plan.ok:print(plan);return
	var before:Array=plan.records.duplicate(true);var ground_before:=ground.duplicate(true)
	var raw:=Fit.fit(plan.records[0],[ground]);check(raw.get("code","")=="terrain_projection_piece_limit","dense half-metre terrain reproduces native 512-piece failure")
	var fitted:=Adaptive.fit(plan.records,[ground]);check(fitted.ok,"only over-budget derived cells automatically subdivide")
	if not fitted.ok:print(fitted);return
	check(fitted.chunks>plan.chunks and fitted.records.all(func(r):return Surface.valid(r) and r.road_mesh.polygons.size()<=512),"every adaptive child keeps native schema and 512-piece cap")
	check(absf(area(fitted.records)-area(plan.records))<.005,"adaptation preserves complete road area without holes or overlap")
	check(absf(kerb_length(fitted.records)-kerb_length(plan.records))<.001,"continuous kerb length survives subdivision")
	var cap_count:=func(records:Array)->int:
		var count:=0
		for r:Dictionary in records:
			for k:Dictionary in r.road_mesh.get("kerbs",[]):count+=int(k.cap_a)+int(k.cap_b)
		return count
	check(cap_count.call(fitted.records)==cap_count.call(plan.records),"internal subdivision boundaries do not add kerb end caps")
	var exact_height:=true
	for r:Dictionary in fitted.records:
		for polygon:Array in Surface.local_polygons(r):
			for point:Vector3 in polygon:
				var world:Vector3=point+City.vec(r.position)
				exact_height=exact_height and absf(world.y-(world.x*.015+world.z*.01+.025))<.0001
		for k:Dictionary in r.road_mesh.get("kerbs",[]):
			for side:String in ["a","b"]:
				for point:Array in k[side]:exact_height=exact_height and is_finite(point[1])
		check(City.vec(r.road_mesh.uv_origin).is_equal_approx(City.vec(r.position)),"child world paving UV phase retained")
	check(exact_height,"fitted child vertices remain on the actual analytical terrain plane")
	check(plan.records==before and ground==ground_before,"adaptive preparation leaves sources and terrain immutable")
	var repeated:=Adaptive.fit(plan.records,[ground]);check(repeated.ok and repeated.records==fitted.records,"same graph and terrain retain deterministic child IDs and geometry")
	var waves:=terrain(true);var unpainted:=Adaptive.fit(plan.records,[waves])
	var before_faces:Array=unpainted.get("records",[]).map(paint_faces)
	check(unpainted.ok and before_faces.max()>Paint.MAX_OVERRIDES,"gentle undulating terrain reproduces more than 128 paint faces below the 512-piece cap")
	var paint_bounded:=Adaptive.fit(plan.records,[waves],.025,Paint.MAX_OVERRIDES)
	var after_faces:Array=paint_bounded.get("records",[]).map(paint_faces)
	check(paint_bounded.ok and paint_bounded.records.all(func(r):return Adaptive.top_triangles(r)<=Paint.MAX_OVERRIDES) and after_faces.max()<=Paint.MAX_OVERRIDES,"textured adaptive cells reserve the existing paint budget even after future sculpt changes face groups")
	check(paint_bounded.ok and absf(area(paint_bounded.records)-area(plan.records))<.005 and absf(kerb_length(paint_bounded.records)-kerb_length(plan.records))<.001,"paint-budget subdivision preserves road area and continuous kerb length")
	print("PAINT_BUDGET ",JSON.stringify({"before_chunks":unpainted.get("chunks",0),"before_max_faces":before_faces.max(),"after_chunks":paint_bounded.get("chunks",0),"after_max_faces":after_faces.max()}))
	var holed:=ground.duplicate(true);holed.terrain_mesh.holes[32*64+32]=true
	check(not Adaptive.fit(plan.records,[holed]).ok,"real terrain holes still reject atomically")
	var steep:=ground.duplicate(true)
	for z in 65:
		for x in 65:steep.terrain_mesh.heights[z*65+x]=x*.25
	check(not Adaptive.fit(plan.records,[steep]).ok,"steep actual terrain remains rejected")
	var short:Dictionary={"nodes":[{"id":"c","position":[8.,0.,8.]},{"id":"d","position":[15.,.7,8.]}],"edges":[{"id":"short","from":"c","to":"d","width_start":6.,"width_end":6.,"kind":"ground"}]}
	check(not Plan.build(short,Plan.defaults()).ok,"legacy explicit ramp still rejects an over-steep shortened run")
	check(Plan.build(short,Plan.defaults().merged({"follow_terrain":true},true)).ok,"terrain-follow footprint does not impose legacy flat-end ramp geometry")
	var bridge_graph:Dictionary={"nodes":[{"id":"w","position":[0.,5.,16.]},{"id":"h1","position":[6.,5.,16.]},{"id":"h2","position":[26.,5.2,16.]},{"id":"e","position":[32.,5.2,16.]}],"edges":[{"id":"west","from":"w","to":"h1","width_start":4.,"width_end":4.,"kind":"ground"},{"id":"bridge","from":"h1","to":"h2","width_start":4.,"width_end":4.,"kind":"bridge"},{"id":"east","from":"h2","to":"e","width_start":4.,"width_end":4.,"kind":"ground"}]}
	var binding:Dictionary={"start":[10.,5.05,16.],"end":[22.,5.2,16.],"width":5.16}
	var portal:Dictionary={"road_stone":true,"edge_id":"bridge","endpoints":[binding.start,binding.end],"polygon":preload("res://scripts/world3d/road_bridges.gd").stone_polygon(binding),"nodes":["h1","h2"],"width":4.}
	var bridge_before:=bridge_graph.duplicate(true)
	var portal_before:=portal.duplicate(true)
	var port_plan:=Plan.build(bridge_graph,Plan.defaults().merged({"follow_terrain":true,"kerb_enabled":true},true),[portal])
	check(port_plan.ok,"sloped native bridge portal is cut before terrain-follow planar union")
	var overlap_area:=0.
	if port_plan.ok:
		for r:Dictionary in port_plan.records:
			for poly:Array in Surface.local_polygons(r):
				var world:Array=poly.map(func(p):return Vector2(p.x+r.position[0],p.z+r.position[2]))
				overlap_area+=Poly.area(Plan.intersection(world,portal.polygon))
	check(port_plan.ok and overlap_area<.0001 and bridge_graph==bridge_before,"physical bridge opening stays empty and authored bridge XYZ/binding remain unchanged")
	check(port_plan.ok and bridge_kerb_openings(port_plan.records,portal.endpoints) and kerb_length(port_plan.records)>20.,"elevated stone bridge has open kerbs at both portals and retains approach side strips")
	check(portal==portal_before,"kerb portal matching leaves original bridge endpoints and binding untouched")
	var river_graph:=bridge_graph.duplicate(true);river_graph.edges[1].bridge_ref={"waterway_id":"river","bridge_id":"deck"}
	var river_portal:Dictionary={"edge_id":"bridge","endpoints":[[6.,5.025,16.],[26.,5.225,16.]],"nodes":["h1","h2"],"width":4.}
	var river_plan:=Plan.build(river_graph,Plan.defaults().merged({"follow_terrain":true,"kerb_enabled":true},true),[river_portal])
	check(river_plan.ok and bridge_kerb_openings(river_plan.get("records",[]),river_portal.endpoints),"terrain-follow river deck retains both kerb openings at elevated ends")

func run()->void:
	create_timer(200).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	logical()
	if "--logic-only" in OS.get_cmdline_user_args():print("ADAPTIVE_TERRAIN_ROAD_LOGIC failures=",failed);quit(failed);return
	var textured:bool="--textured" in OS.get_cmdline_user_args()
	var directory:String=Paths.cache_directory("adaptive_terrain_roads_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:String=directory.path_join("map.gltf");var doc=Doc.new();doc.records=[terrain(textured)];doc.map_meta.editor_layout=City.defaults();doc.map_meta.editor_layout.roads=graph()
	check(doc.save(path)==OK,"isolated native road fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31920
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP listens on loopback")
	var discovery:=await rpc("tools/list")
	var names:Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(names.has("preview_road_surface") and names.has("generate_road_surface") and not names.has("paint_tile"),"current 3D road tools remain discoverable without legacy 2D")
	var args:Dictionary={"follow_terrain":true,"kerb_enabled":true,"kerb_width":.24,"kerb_height":.035}
	if textured:args.material_id="pack:default:paving/outdoor_flagstone/material"
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var preview:Dictionary=await call_tool("preview_road_surface",args)
	check(equivalent(preview,editor._roads.summary(args)),"HTTP preview matches shared UI business prepare")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"successful adaptive preview has no document/history side effects")
	# A real obstacle still rejects; the broad-phase only skips distant bounds
	# and the exact heightfields already accepted as this road's support.
	var obstacle_id:String=editor._doc.add_box("stone",Vector3(16,1,16),Vector3(2,2,2))
	var occupied:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("preview_road_surface",args,false)
	check(equivalent(occupied,editor._doc.recovery_snapshot()),"occupied road area still rejects without side effects")
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle_id)
	before=editor._doc.recovery_snapshot()
	await call_tool("sculpt_terrain",{"id":"fine_ground","mode":"hole","points":[[16.,16.]],"radius":1.})
	var holed:Dictionary=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	await call_tool("preview_road_surface",args,false);await call_tool("generate_road_surface",args,false)
	check(equivalent(holed,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"true terrain hole fails preview/generate without partial edits")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"hole undo restores original terrain before road generation")
	await call_tool("generate_road_surface",args)
	var generated:Dictionary=editor._doc.recovery_snapshot();var ids:Array=editor._doc.records.filter(func(r):return r.has("road_mesh")).map(func(r):return r.uuid)
	check(ids.size()>1,"real HTTP generation commits multiple bounded native cells")
	if textured:
		var painted_roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"))
		check(painted_roads.all(func(r):return Paint.valid(r) and r.get("surface_paint",[]).size()>0 and r.surface_paint.size()<=Paint.MAX_OVERRIDES),"HTTP textured undulating road uses valid native default paint within unchanged 128-entry cap")
		var instance:MeshInstance3D=editor._doc._mesh(painted_roads[0]);var bound_textures:=false
		for slot in instance.mesh.get_surface_count():
			var mat:Material=instance.mesh.surface_get_material(slot)
			if mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null:bound_textures=true
		instance.free();check(bound_textures,"generated native road actually binds existing paving albedo and normal textures")
	var again:Dictionary=await call_tool("generate_road_surface",args);check(not again.get("changed",true),"repeating generation is unchanged and retains stable IDs")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"undo restores exact pre-road content")
	await call_tool("redo");check(equivalent(generated,editor._doc.recovery_snapshot()),"redo restores adaptive road and kerb metadata")
	await call_tool("save_world");await call_tool("open_world",{"path":path});check(equivalent(generated.records,editor._doc.records) and equivalent(generated.map_meta,editor._doc.map_meta),"native save/reopen preserves adaptive cells and terrain-follow source")
	var before_sculpt:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("sculpt_terrain",{"id":"fine_ground","mode":"raise","points":[[16.,16.]],"radius":6.,"strength":.05})
	var sculpted:Dictionary=editor._doc.recovery_snapshot()
	var updated_roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"))
	check(updated_roads.map(func(r):return r.uuid)==ids and updated_roads.all(func(r):return Surface.valid(r) and r.road_mesh.polygons.size()<=512),"ordinary native sculpt refits adaptive children with unchanged stable IDs and face budget")
	check(not equivalent(before_sculpt.records,sculpted.records) and editor._doc.map_meta.editor_layout.road_surface.parts.all(func(p):return Surface.signature(editor._doc._find(p.id))==p.signature),"terrain sculpt updates actual road geometry and every manifest signature")
	await call_tool("undo");check(equivalent(before_sculpt,editor._doc.recovery_snapshot()),"sculpt undo restores terrain and all adaptive road children together")
	await call_tool("redo");check(equivalent(sculpted,editor._doc.recovery_snapshot()),"sculpt redo restores the complete follower transaction")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(sculpted.records,editor._doc.records) and equivalent(sculpted.map_meta,editor._doc.map_meta),"sculpted adaptive road children and ownership survive save/reopen")
	if textured:
		check(editor._doc.records.filter(func(r):return r.has("road_mesh")).all(func(r):return Paint.valid(r) and r.get("surface_paint",[]).size()>0 and r.surface_paint.size()<=Paint.MAX_OVERRIDES),"sculpted and reopened textured roads stay within the existing paint budget")
		await call_tool("clear_surface_material",{"id":ids[0]})
		await call_tool("generate_road_surface",args)
		check(not editor._doc._find(ids[0]).has("surface_paint"),"manual material clearing is preserved by automatic regeneration")
		await call_tool("undo")
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	await call_tool("sculpt_terrain",{"id":"fine_ground","mode":"hole","points":[[16.,16.]],"radius":1.},false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"hole sculpt beneath a bound road rejects and protects road/terrain transaction")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("ADAPTIVE_TERRAIN_ROAD_HTTP ",directory," failures=",failed);quit(failed)
