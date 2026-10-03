extends "res://tools/test_world3d_roads.gd"
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/terrain_regions"
const DIRT="pack:default:terrain/natural_dirt/material"
const STONE="pack:default:paving/outdoor_flagstone/material"
func batches() -> void:
	while editor._ground_batches.stats().pending_groups>0: await process_frame
	await settle()
func shot(label_: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var image: Image=editor._camera.get_viewport().get_texture().get_image(); image.save_png(OUT.path_join(label_+".png")); return image
func run() -> void:
	create_timer(400).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1500,1100); root.content_scale_size=root.size
	directory=Paths.cache_directory("terrain_regions_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf"); DirAccess.make_dir_recursive_absolute(OUT)
	var doc:=Doc.new(); check(doc.save(map_path)==OK,"temporary fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30985
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP MCP")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="paint_terrain_region") and defs.any(func(d):return d.name=="remove_terrain_region") and defs.all(func(d):return d.name!="paint_tile"),"discover both 3D region tools; old 2D disabled")
	var ids: Array=[]
	for x in [16,48]:
		var created:=await call_tool("create_terrain",{"center":[x,0,32],"width":32,"depth":32,"cell_size":1,"material_id":"pack:default:terrain/mossy_grass/material"}); ids.append(created.id)
	var args:={"id":"courtyard","terrain_ids":ids,"polygon":[[10,24],[50,21],[56,40],[14,44]],"material_id":DIRT,"feather":5.}
	var original: Array=editor._doc.records.duplicate(true); var history: int=editor._doc._undo.size()
	await call_tool("paint_terrain_region",args); await batches()
	var expected: Array=editor._doc.records.duplicate(true)
	check(history+1==editor._doc._undo.size() and expected.all(func(r):return r.has("terrain_regions")),"cross-chunk region is one transaction")
	await call_tool("undo"); check(equivalent(original,editor._doc.records),"undo removes region, no geometry changes"); await call_tool("redo")
	history=editor._doc._undo.size(); await call_tool("paint_terrain_region",args); check(history==editor._doc._undo.size(),"idempotent region update")
	for bad in [{"polygon":[[-5,-5],[5,5],[-5,5],[5,-5]]},{"material_id":"missing"},{"feather":0},{"terrain_ids":[ids[0],ids[0]]},{"id":"bad id"},{"opacity":2}]: await atomic_reject("paint_terrain_region",args.merged(bad,true))
	for property in ["hidden","locked"]:
		await call_tool("set_object_properties",{"ids":[ids[1]],property:true}); await atomic_reject("paint_terrain_region",args.merged({"feather":6.},true)); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":40}); await atomic_reject("paint_terrain_region",args); await call_tool("undo")
	await call_tool("paint_terrain_region",args.merged({"id":"paving","material_id":STONE,"polygon":[[22,27],[41,27],[41,35],[22,35]],"feather":2.},true)); await batches()
	await atomic_reject("paint_terrain_region",args.merged({"id":"third","material_id":"pack:default:terrain/natural_sand/material"},true))
	var a:=Regions.mask(editor._doc._find(ids[0])); var b:=Regions.mask(editor._doc._find(ids[1])); var seam:=0.
	for y in Regions.RESOLUTION: seam=maxf(seam,absf(a.get_pixel(256,y).r-b.get_pixel(0,y).r)+absf(a.get_pixel(256,y).g-b.get_pixel(0,y).g))
	check(seam<.00001,"shared edge coverage identical, no chunk clipping")
	var record: Dictionary=editor._doc._find(ids[0]); var broken:=record.duplicate(true); broken.terrain_regions.materials[0].normal_path="C:/escape.png"; check(not Paint.valid(broken),"nested path escape rejected")
	broken=record.duplicate(true); broken.terrain_regions.materials[0].normal_path=directory.path_join("missing.png"); check(not Paint.missing([broken]).is_empty(),"missing nested region dependency reported")
	await call_tool("sculpt_terrain",{"id":ids[0],"mode":"raise","points":[[24,32]],"radius":5,"strength":2}); check(editor._doc._find(ids[0]).terrain_regions==record.terrain_regions,"sculpt retains editable polygons")
	await call_tool("set_river_materials",{"terrain_ids":ids,"water_level":-1.5,"sand_material_id":"pack:default:terrain/natural_sand/material","rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"})
	await atomic_reject("set_terrain_material",{"id":ids[0],"material_id":DIRT,"saturation":-1})
	await call_tool("set_terrain_material",{"id":ids[0],"saturation":.45})
	check(is_equal_approx(editor._doc._find(ids[0]).terrain_saturation,.45),"HTTP grading stored separately from source PBR")
	await call_tool("undo"); check(not editor._doc._find(ids[0]).has("terrain_saturation"),"grading undo exact"); await call_tool("redo")
	await call_tool("set_terrain_material",{"id":ids[1],"material_id":"pack:default:terrain/mossy_grass/material","saturation":.45})
	await call_tool("set_environment",{"preset":"day","sky_enabled":true,"sun_rotation":[-55,32,0],"ambient_energy":.65})
	await call_tool("save_world"); expected=editor._doc.records.duplicate(true); await call_tool("open_world",{"path":map_path}); await batches(); check(equivalent(expected,editor._doc.records),"native save/reopen preserves polygons and full PBR")
	var catalog:=await call_tool("list_terrains"); check(catalog.terrains[0].ground_regions.regions.size()==2,"MCP exposes editable region data")
	var node: MeshInstance3D=editor._view.get_node(NodePath(ids[0])); var material: ShaderMaterial=node.get_active_material(0)
	check(material.get_shader_parameter("region_a_normal")!=null and material.get_shader_parameter("region_b_albedo")!=null,"region normal/roughness maps bound")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide(); await call_tool("set_editor_camera",{"projection":"perspective","center":[32,0,32],"distance":66,"pitch":-62,"yaw":0})
	var merged:=await shot("merged"); var stats: Dictionary=editor._ground_batches.stats(); check(stats.source_objects>=2 and stats.render_surfaces<stats.source_surfaces,"region masks retain terrain batching")
	editor._ground_batches.clear(); await settle(); var unmerged:=await shot("unmerged")
	var sum:=0.; var n:=0
	for y in range(0,merged.get_height(),4):
		for x in range(0,merged.get_width(),4):
			var ca:=merged.get_pixel(x,y); var cb:=unmerged.get_pixel(x,y); sum+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b); n+=1
	check(sum/n<.008,"batched region render matches source PBR: "+str(sum/n))
	editor._sync_ground_batches(); await batches()
	var pack=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("prefab_pack")); var captured:=preload("res://scripts/world_editor/prefab_library.gd").capture([editor._doc._find(ids[0])],pack,"Painted ground")
	check(captured.ok,"prefab captures region PBR dependencies")
	if captured.ok:
		var loaded:=preload("res://scripts/world_editor/prefab_library.gd").read(captured.entry); check(loaded.ok and loaded.records[0].terrain_regions.materials[0].normal_path.contains("material_textures"),"prefab resolves nested region normals")
	await call_tool("remove_terrain_region",{"id":"courtyard","terrain_ids":ids}); check(editor._doc.records.all(func(r):return r.terrain_regions.regions.size()==1),"remove compacts palette and retains other region"); await call_tool("undo")
	# UI feeds the same transaction, with real canvas events.
	await call_tool("set_editor_camera",{"projection":"top","center":[32,0,32],"span":85})
	check(editor._ground_draw.begin({"material_id":DIRT,"feather":2.,"opacity":.6},false).ok,"UI starts polygon mode")
	await atomic_reject("paint_terrain_region",args)
	for p in [Vector3(-26,0,-14),Vector3(-18,0,-14),Vector3(-18,0,-10),Vector3(-26,0,-10)]:
		var e:=InputEventMouseButton.new(); e.button_index=MOUSE_BUTTON_LEFT; e.pressed=true; e.position=editor._canvas.global_position+editor._camera.unproject_position(p+Vector3(32,0,32)); Input.parse_input_event(e); await settle(); e=e.duplicate(); e.pressed=false; Input.parse_input_event(e); await settle()
	check(editor._ground_draw.points.size()==4,"UI collects polygon vertices")
	var enter:=InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=true; Input.parse_input_event(enter); await settle()
	check(not editor._ground_draw.active and editor._doc._find(ids[0]).terrain_regions.regions.size()==3,"Enter commits UI region: "+str(editor._status.text))
	var untouched: int=editor._view.get_node(NodePath(ids[1])).get_instance_id()
	await call_tool("undo")
	check(editor._view.get_node(NodePath(ids[1])).get_instance_id()==untouched,"region undo preserves untouched scene nodes and collision")
	check(equivalent(expected,editor._doc.records),"UI region undo restores saved document")
	check(editor._ground_draw.begin({"material_id":DIRT,"feather":2.,"opacity":.4},true).ok,"UI starts rectangle mode")
	await settle()
	for pair in [[Vector3(5,0,43),true],[Vector3(14,0,47),false]]:
		var e:=InputEventMouseButton.new(); e.button_index=MOUSE_BUTTON_LEFT; e.pressed=pair[1]; e.position=editor._canvas.global_position+editor._camera.unproject_position(pair[0]); Input.parse_input_event(e); await settle()
	check(not editor._ground_draw.active and editor._doc._find(ids[0]).terrain_regions.regions.size()==3,"drag-release commits rectangle"); await call_tool("undo")
	check(equivalent(expected,editor._doc.records),"rectangle undo exact")
	# Teardown intentionally occurs while a render-batch worker may still run:
	# no worker owns GPU uploads, so scene exit must complete instead of deadlock.
	var scene:=Io.load_scene(map_path); check(scene!=null and Paint.meshes(scene).any(func(m):return m.get_active_material(0) is ShaderMaterial and m.get_active_material(0).get_shader_parameter("ground_enabled")),"runtime restores region shader"); if scene!=null: scene.free()
	var f:=FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify({"failures":failed,"fixture":map_path,"seam_error":seam,"batch_difference":sum/n,"batching":stats},"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); print("TERRAIN_REGIONS_FINISHED failures=",failed); quit(1 if failed else 0)
