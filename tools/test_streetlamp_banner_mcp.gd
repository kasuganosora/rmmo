extends "res://tools/test_world3d_buildings.gd"
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/banner_streetlamp"

func material_wind(runtime:Node3D,material:ShaderMaterial)->Vector3:
	if not material.get_shader_parameter("wind_state_enabled"):return material.get_shader_parameter("wind_velocity")
	check(material.get_shader_parameter("wind_state")==runtime._shared_state.texture,"cloth samples its runtime state texture")
	var state:Color=runtime._shared_state.image.get_pixel(0,0)
	return Vector3(state.r,state.g,state.b)*float(material.get_shader_parameter("wind_exposure"))

func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	var directory:=Paths.external_root().path_join("__banner_mcp_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE);metadata.store_string('{"id":"banner_test","name":"旗帜临时验收包"}');metadata.close()
	var path:=directory.path_join("map.gltf")
	var library:=Library.new(directory)
	var imported:=library.import_file("D:/code/rmmo_runtime/assets/banner_streetlamp/banner_streetlamp.glb")
	check(imported.ok,"import independent Blender cloth slot")
	if not imported.ok:quit(1);return
	var doc:=Doc.new();var ids:Array=[]
	for i in 2:ids.append(doc.add_asset(imported.entry,Vector3(i*3,0,0)))
	check(doc.save(path)==OK,"temporary lamp map saved")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback MCP")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.any(func(tool):return tool.name=="set_streetlamp_banner"),"new 3D banner tool and schema discovered")
	await call_tool("select_objects",{"ids":ids})
	check(editor._inspector.banner_panel.visible,"selected lamps expose convenient banner controls")
	var snapshot:=doc.recovery_snapshot();var history:int=doc._undo.size()
	for settings_ in [{"shape":"invalid"},{"design":"flag","texture_path":"C:/Windows/not_allowed.png"},{"design":"emblem","texture_path":directory+"/missing.png"}]:
		await call_tool("set_streetlamp_banner",{"ids":ids,"settings":settings_},false)
	check(doc.recovery_snapshot()==snapshot and doc._undo.size()==history,"bad schema, outside-root and missing images are atomic")
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"shape":"swallowtail","color":[.04,.12,.5]}})
	check(ids.all(func(id):return doc._find(id).banner.shape=="swallowtail"),"batch changes cloth only")
	await call_tool("undo");check(doc.records==snapshot.records,"one undo restores both lamps")
	await call_tool("redo");check(doc._find(ids[0]).banner.shape=="swallowtail","redo keeps banner settings")
	await call_tool("set_object_properties",{"ids":[ids[1]],"locked":true})
	snapshot=doc.recovery_snapshot();history=doc._undo.size()
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"shape":"rectangle"}},false)
	check(doc.recovery_snapshot()==snapshot and doc._undo.size()==history,"locked batch fails without changing first lamp")
	await call_tool("undo")
	var emblem:=Image.create(96,96,false,Image.FORMAT_RGBA8);emblem.fill(Color.TRANSPARENT);emblem.fill_rect(Rect2i(35,4,26,88),Color(1,.8,.1));emblem.fill_rect(Rect2i(4,35,88,26),Color(1,.8,.1))
	var texture_path:=directory.path_join("test_emblem.png");emblem.save_png(texture_path)
	await call_tool("set_streetlamp_banner",{"ids":[ids[0]],"settings":{"design":"flag","texture_path":texture_path}})
	check(doc._find(ids[0]).banner.design=="flag" and doc._find(ids[1]).banner.design=="plain","whole-flag replacement is independent per lamp")
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"shape":"rectangle","design":"emblem","texture_path":texture_path}})
	var changed:Array=doc.records.duplicate(true)
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(equivalent(doc.records,changed) and doc.missing_assets().is_empty(),"save/reopen preserves independent banner and texture dependencies")
	await call_tool("select_objects",{"ids":[ids[0]]})
	var saved:=await call_tool("save_prefab",{"name":"活动旗路灯","pack_root":directory})
	check(saved.get("ok",false),"native prefab packaging copies banner image")
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[6,0,0]})
	check(doc.records.size()==3 and doc.records.back().banner.material.texture_path!=texture_path and FileAccess.file_exists(doc.records.back().banner.material.texture_path),"library relocation resolves packaged emblem")
	await call_tool("undo")
	# Runtime uses the same streamed geometry and weather wind receiver system.
	await call_tool("set_environment",{"preset":"night","time_speed":0})
	editor._camera.position=Vector3(1,2,6);editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.size()==2 and editor._weather.streetlamps.fixtures.values().all(func(r):return r.lit and r.glow.visible),"real HTTP night environment lights both editor streetlamp crystals and halos")
	check(editor._weather.streetlamps.lights.filter(func(l):return l.visible).size()==2,"both editor lamps illuminate simultaneously")
	editor._camera.position=Vector3(300,2,300);editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.lights.all(func(l):return l.visible),"editor night lamps stay on regardless of camera distance")
	await call_tool("undo");editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.values().all(func(r):return not r.lit) and editor._weather.streetlamps.lights.all(func(l):return not l.visible),"environment undo extinguishes streetlamps")
	await call_tool("redo");editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.values().all(func(r):return r.lit),"environment redo restores night lights")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc;editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.size()==2 and editor._weather.streetlamps.fixtures.values().all(func(r):return r.lit),"saved night environment restores streetlamps on editor reopen")
	var viewport:=SubViewport.new();viewport.size=Vector2i(800,900);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var host:=Node3D.new();viewport.add_child(host);var scene:=doc.build();host.add_child(scene);Stream.sync(scene,host,Vector3.ZERO)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(1,2.5,6);camera.look_at(Vector3(-.4,2.3,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.7
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.15,.18,.22);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.8;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);viewport.add_child(sun)
	var wind:=preload("res://scripts/world3d/wind_runtime.gd").new();viewport.add_child(wind);wind.camera=camera
	await physics();wind.refresh()
	check(wind.receivers.size()==2,"only two fabric slots receive wind; metal and crystal stay rigid")
	wind.advance(Vector3(8,0,0),1.2)
	var wind_ok:=true
	for row:Dictionary in wind.receivers.values():
		wind_ok=wind_ok and row.config.anchor=="top" and row.config.profile=="cloth"
		for material:ShaderMaterial in row.materials:wind_ok=wind_ok and material_wind(wind,material)==Vector3(8,0,0) and material.get_shader_parameter("anchor_reverse")
	check(wind_ok,"game wind vector drives top-anchored cloth shader")
	wind.set_physics_process(false)
	for mode in ["still","wind_a","wind_b"]:
		wind.advance(Vector3.ZERO if mode=="still" else Vector3(12,0,0),1.2 if mode!="wind_b" else 2.1)
		for i in 4:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT+"/banner_"+mode+".png")
	wind.advance(Vector3(0,0,-7),3)
	check(wind.receivers.values().all(func(row):return material_wind(wind,row.materials[0])==Vector3(0,0,-7)),"changed game wind direction reaches cloth")
	viewport.free()
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"wind_enabled":false}})
	var node:Node3D=doc._asset(doc._find(ids[0]));check(not Banner.slot(node).get_meta("extras").has("rmmo_wind"),"wind can be disabled without changing design");node.free()
	var file:=FileAccess.open(OUT+"/banner_mcp.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failed,"lamps":ids.size(),"temporary_map":path},"\t"));file.close()
	editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("BANNER_MCP_FINISHED failures=",failed);quit(1 if failed else 0)
