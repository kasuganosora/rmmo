extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Narrow=preload("res://scripts/world3d/road_bridge_approach.gd")

func run()->void:
	create_timer(170).timeout.connect(func():quit(2));rpc_timeout_ms=80000
	var directory:String=Paths.cache_directory("road_bridge_approach_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:String=directory.path_join("map.gltf");var doc=Doc.new()
	var heights:Array=[];heights.resize(289);heights.fill(0.);var holes:Array=[];holes.resize(256);holes.fill(false)
	doc.records=[{"uuid":"flat_ground","kind":"box","surface_id":"ground","position":[16.,0.,16.],"rotation":[0,0,0],"size":[32.,1.,32.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":16,"rows":16,"floor":-8.,"heights":heights,"holes":holes}}]
	doc.map_meta.editor_layout=City.defaults()
	doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[6.,0.,16.]},{"id":"b","position":[26.,0.,16.]}],"edges":[{"id":"crossing","from":"a","to":"b","width_start":4.,"width_end":4.,"kind":"bridge"}]}
	check(doc.save(path)==OK,"isolated native bridge approach fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31950
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"bridge approach HTTP listens on loopback")
	var listed:=await rpc("tools/list");var names:Array=listed.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(names.has("generate_bridge") and names.has("preview_road_surface") and not names.has("paint_tile"),"existing 3D bridge and road tools discovered without new parameters or 2D")
	await call_tool("generate_bridge",{"id":"fixture_bridge","road_edge_id":"crossing","prefab_id":"stone_segmental","start":[10.,.025,16.],"end":[22.,.025,16.],"width":5.2,"depth":2.,"camber":.25,"arches":1,"wing_length":1.5})
	var bridge:Dictionary=editor._doc._find("fixture_bridge")
	check(bridge.has("house_prefab") and bridge.get("prefab_locked",false),"actual generated bridge uses its frozen native collision source")
	var unknown:Dictionary=bridge.duplicate(true);var frozen=preload("res://scripts/world3d/house_prefab.gd")
	var packet:Dictionary=frozen.decode(unknown.house_prefab);packet.entries[0][0]=[7]
	var bytes:=var_to_bytes(packet);unknown.house_prefab={"version":1,"sha256":frozen.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	check(not Narrow.collision_faces(unknown).known,"unknown frozen entry layout keeps conservative collision protection")
	var args:Dictionary={"follow_terrain":true,"material_id":"pack:default:paving/outdoor_flagstone/material"}
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var preview:=await call_tool("preview_road_surface",args)
	check(equivalent(preview,editor._roads.summary(args)),"HTTP and shared UI business agree on clear wing-wall approaches")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"clear approach preview leaves map and undo history unchanged")
	await call_tool("generate_road_surface",args)
	var generated:Dictionary=editor._doc.recovery_snapshot();var roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"));var bounds:=Foot.record_shape(bridge)
	check(roads.any(func(r):return Foot.batches_overlap(Foot.record_shapes(r),[bounds])),"valid approach really overlaps bridge broad bounds rather than bypassing the regression")
	check(roads.all(func(r):return not Narrow.intersects(r,bridge,Foot.record_shapes(r),bounds,{})),"both bridge-end approaches remain clear of actual frozen collision triangles")
	var body:Dictionary={"uuid":"body","kind":"box","surface_id":"road","position":[16.,0.,16.],"rotation":[0,0,0],"size":[1.,.2,1.],"road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[16.,0.,16.]},"road_clearance":3.}
	check(Narrow.intersects(body,bridge,Foot.record_shapes(body),bounds,{}),"bridge body occupancy is never waived by the approach refinement")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"undo removes generated approach pavement as one transaction")
	await call_tool("redo");check(equivalent(generated,editor._doc.recovery_snapshot()),"redo restores approach geometry and ownership")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(generated.records,editor._doc.records) and equivalent(generated.map_meta,editor._doc.map_meta),"bridge plus clear approaches survive native save and reopen")
	before=editor._doc.recovery_snapshot()
	await call_tool("sculpt_terrain",{"id":"flat_ground","mode":"raise","points":[[4.,16.]],"radius":1.,"strength":.05})
	check(not equivalent(before.records,editor._doc.records),"ordinary terrain sculpt can refit the same clear bridge approaches without a bounds-only false collision")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"approach follower sculpt remains one reversible terrain-and-road transaction")
	var layout:=City.resolve(editor._doc.map_meta);var graph:Dictionary=layout.roads.duplicate(true)
	graph.nodes.append_array([{"id":"bad_a","position":[23.,0.,19.22]},{"id":"bad_b","position":[25.,0.,19.22]}])
	graph.edges.append({"id":"through_wing_post","from":"bad_a","to":"bad_b","width_start":1.,"width_end":1.,"kind":"ground"})
	await call_tool("update_road_graph",{"expected_token":City.token(layout.roads),"nodes":graph.nodes,"edges":graph.edges})
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	var rejected:=await call_tool("preview_road_surface",args,false)
	check("fixture_bridge" in rejected.get("conflicts",[]),"actual wing-wall end post still rejects the road with its exact bridge identity")
	await call_tool("generate_road_surface",args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"real bridge collision failure is atomic for preview and generation")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("ROAD_BRIDGE_APPROACH_HTTP ",directory," failures=",failed);quit(failed)
