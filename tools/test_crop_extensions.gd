extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("crop_extensions_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"crop fixture saved")
	var library:=Library.new(directory.path_join("assets"));var asset_ids:Array=[]
	for variant in ["ripe","green"]:
		var imported:=library.import_file("D:/code/rmmo_runtime/art_sources/editor_extensions_20261012/wheat_lod_v2/wheat_"+variant+".glb")
		check(imported.ok,"crop native import "+variant)
		if imported.ok:asset_ids.append(imported.entry.asset_path)
	if asset_ids.size()!=2:quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._shared_assets.append(library)
	var probe:=TCPServer.new();port=30820
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"crop HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_vegetation_scatter" and t.inputSchema.properties.has("pattern") and t.inputSchema.properties.has("follow_terrain")),"rows and terrain schema discovered")
	var t:=await call_tool("create_terrain",{"center":[0,0,0],"width":16.,"depth":16.,"cell_size":1.,"material_id":"pack:default:terrain/natural_dirt/material"})
	if not t.get("ok",false):quit(1);return
	await call_tool("paint_terrain_region",{"id":"field","terrain_ids":[t.id],"polygon":[[-7,-7],[7,-7],[7,7],[-7,7]],"material_id":"pack:default:terrain/natural_dirt/material","feather":1.})
	await call_tool("set_terrain_furrows",{"id":"field","terrain_ids":[t.id],"spacing":1.5,"height":.18,"angle":0.,"margin":1.})
	var args:={"id":"wheat_field","polygon":[[-6,-6],[6,-6],[6,6],[-6,6]],"asset_ids":asset_ids,"count":80,"seed":19,"pattern":"rows","row_angle":90.,"row_spacing":1.5,"spacing":.65,"follow_terrain":true,"boundary_margin":.5,"collision":false,"scale_min":.85,"scale_max":1.05}
	var before:Dictionary=editor._doc.recovery_snapshot()
	var preview:=await call_tool("preview_vegetation_scatter",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"crop preview has no mutation")
	if not preview.get("ok",false):quit(1);return
	check(preview.count>40 and preview.count+preview.shortfall==80,"crop placement reports bounded capacity and shortfall")
	var result:=await call_tool("generate_vegetation_scatter",args.merged({"plan_token":preview.plan_token}))
	check(result.get("count",0)==preview.count,"rows planted through HTTP match preview")
	var plants:Array=editor._doc.records.filter(func(r):return r.get("vegetation_batch",false))
	check(plants.any(func(r):return r.position[1]>.08),"crop roots sit on raised cultivation geometry")
	for i in 80:await process_frame
	print("CROP_BATCH_STATS ",editor._ground_batches.stats("vegetation"))
	check(not editor._ground_batches.groups.values().filter(func(g):return g.category=="vegetation" and is_instance_valid(g.get("visual")) and g.visual is MultiMeshInstance3D).is_empty(),"repeated crops actually share spatial instancing batches")
	if DisplayServer.get_name()!="headless":
		var has_lod:=false
		for group:Dictionary in editor._ground_batches.groups.values():
			if group.category!="vegetation" or not is_instance_valid(group.get("visual")) or not group.visual is MultiMeshInstance3D:continue
			var mesh:Mesh=group.visual.multimesh.mesh
			for slot in mesh.get_surface_count():
				if not RenderingServer.mesh_get_surface(mesh.get_rid(),slot).get("lods",[]).is_empty():has_lod=true
		check(has_lod,"actual spatial MultiMesh retains crop LOD indices")
	var created:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"whole crop operation undo")
	await call_tool("redo");check(equivalent(created,editor._doc.recovery_snapshot()),"whole crop operation redo")
	await call_tool("generate_vegetation_scatter",args.merged({"row_spacing":-.1},true),false)
	check(equivalent(created,editor._doc.recovery_snapshot()),"invalid crop spacing no effects")
	await call_tool("select_objects",{"ids":[plants[0].uuid]})
	check(not editor._ground_batches._member_groups.has(plants[0].uuid),"selected crop leaves batch for individual editing")
	await call_tool("set_object_properties",{"ids":[plants[0].uuid],"locked":true})
	var locked:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("generate_vegetation_scatter",args,false)
	check(equivalent(locked,editor._doc.recovery_snapshot()),"locked crop rejects region regeneration atomically")
	await call_tool("undo")
	await call_tool("set_object_properties",{"ids":[plants[0].uuid],"wind":{"profile":"foliage","amplitude":.12,"anchor":"bottom","stiffness":.6}})
	check(not preload("res://scripts/world3d/vegetation_render.gd").eligible(editor._doc._find(plants[0].uuid)),"wind crop is excluded from static instancing")
	await call_tool("set_editor_wind_preview",{"enabled":true});await settle()
	var wind_root:Node3D=editor._view.get_node(NodePath(plants[0].uuid))
	check(not preload("res://scripts/world3d/wind_response.gd").catalog(wind_root).is_empty(),"crop has compatible selectable wind meshes")
	await call_tool("set_editor_wind_preview",{"enabled":false});await call_tool("undo")
	check(equivalent(created,editor._doc.recovery_snapshot()),"wind preview and undo preserve crop authoring state")
	await call_tool("save_world");var saved:Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":path});check(equivalent(saved,editor._doc.records),"crop references and recipes save/reopen")
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,1000);root.content_scale_size=root.size;editor._grid.hide()
		for shot:Array in [["field_near",[0,.7,0],6,-14,25],["field_mid",[0,0,0],14,-30,25],["field_far",[0,0,0],30,-30,25],["crop_detail",[plants[0].position[0],plants[0].position[1]+.65,plants[0].position[2]],3.,-8,15]]:
			await call_tool("set_editor_camera",{"projection":"perspective","center":shot[1],"distance":shot[2],"pitch":shot[3],"yaw":shot[4]});await settle();await RenderingServer.frame_post_draw
			editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0]+".png"))
	print("CROP_ARTIFACTS ",directory)
	editor._mcp.stop();editor.queue_free();await settle();print("CROP_EXTENSIONS_FINISHED failures=",failed);quit(0 if failed==0 else 1)
