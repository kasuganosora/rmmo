extends "res://tools/test_world3d_mcp.gd"
const H=preload("res://scripts/world3d/house_prefab.gd")
const W=preload("res://scripts/world_editor/building_window_tools.gd")

func review_windows(doc:RefCounted,window:Dictionary)->void:
	var output:="D:/code/rmmo_runtime/review_artifacts/house_appearance"
	DirAccess.make_dir_recursive_absolute(output)
	var vp:=SubViewport.new();vp.size=Vector2i(640,640);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.25,.28,.3);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.9;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=1.3;vp.add_child(sun)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	for style in W.STYLES:
		var holder:=Node3D.new();vp.add_child(holder)
		for uuid in window.members:
			var prepared:=W.prepare(doc._find(uuid),style)
			check(prepared.ok,"render preparation "+style)
			if not prepared.ok:continue
			prepared.record.fixture.open=0
			holder.add_child(H.visual(prepared.record,true))
		var bounds:=preload("res://scripts/world_editor/asset_library.gd").bounds_of(holder)
		cam.size=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))*1.35
		cam.position=bounds.get_center()+(Vector3(.15,.12,-3) if bounds.size.x>bounds.size.z else Vector3(-3,.12,.15));cam.look_at(bounds.get_center())
		await settle();await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(output+"/"+style+".png")
		holder.free()
	vp.queue_free();await settle()

func run()->void:
	rpc_timeout_ms=120000
	create_timer(480).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("appearance_%d"%OS.get_process_id())
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(path)==OK,"temporary map created")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP MCP started")
	var discovery:=await rpc("tools/list")
	var names:Array=discovery.result.tools.map(func(t):return t.name)
	check(names.has("list_building_windows") and names.has("set_building_window_style"),"both new tools discoverable")
	var made:=await call_tool("generate_buildings",{"parameters":{"floors":1,"roof":"gable","window_style":"casement"},"placements":[{"position":[0,0,0]}]})
	if not made.get("ok",false):quit(1);return
	var id:String=made.building_ids[0]
	var windows:=await call_tool("list_building_windows",{"building_id":id})
	if not windows.get("ok",false) or windows.windows.is_empty():quit(1);return
	var window:Dictionary=windows.windows[0];var member:String=window.members[0]
	await call_tool("set_building_component_state",{"id":id,"component_id":doc._find(member).fixture.id,"open":.4})
	var before:Array=doc.records.duplicate(true)
	var args:Dictionary={"building_id":id,"window_id":window.id,"style":"diamond_lattice"}
	var result:=await call_tool("set_building_window_style",args)
	if not result.get("ok",false):quit(1);return
	for record in doc.records:
		if record.uuid in window.members:
			check(record.window_design=="diamond_lattice" and record.fixture==before.filter(func(r):return r.uuid==record.uuid)[0].fixture,"replacement preserves window hinge state")
		else:check(record==before.filter(func(r):return r.uuid==record.uuid)[0],"unselected component unchanged")
	await call_tool("undo");check(doc.records==before,"undo restores exact original window data")
	await call_tool("redo")
	editor._building_panel.refresh_list(id)
	var panel:VBoxContainer=editor._building_panel.fixtures
	panel.window_picker.select(0);panel.style_picker.select(1)
	panel.get_node("ReplaceWindowStyle").pressed.emit()
	check(doc._find(member).window_design=="cross_lattice","UI invokes shared per-window transaction")
	await call_tool("undo")
	before=doc.records.duplicate(true)
	var invalid:=args.duplicate();invalid.style="round_arch"
	await call_tool("set_building_window_style",invalid,false)
	invalid=args.duplicate();invalid.window_id="missing"
	await call_tool("set_building_window_style",invalid,false)
	doc._find(member).editor_locked=true
	invalid=args.duplicate();invalid.style="cross_lattice"
	await call_tool("set_building_window_style",invalid,false)
	doc._find(member).erase("editor_locked")
	check(doc.records==before,"invalid and locked changes have no side effects")
	var shell:Dictionary={}
	for record in doc.records:
		if record.get("building",{}).get("role")=="shell":shell=record;break
	var faces:=await call_tool("list_object_surfaces",{"id":shell.uuid,"limit":200})
	if not faces.get("ok",false):quit(1);return
	var target:Dictionary={}
	for face in faces.faces:
		if absf(float(face.normal[1]))<.01:target=face.target;break
	check(not target.is_empty(),"wall face available on baked house")
	before=doc.records.duplicate(true)
	result=await call_tool("paint_surface",{"id":shell.uuid,"target":target,"material_id":"builtin:checker"})
	if not result.get("ok",false):quit(1);return
	check(H.valid(shell) and not H.geometry(shell).is_empty(),"painted baked geometry stays valid")
	await call_tool("undo");check(doc.records==before,"paint undo restores baked source")
	await call_tool("redo")
	await settle()
	await call_tool("select_objects",{"ids":[]})
	var deadline:=Time.get_ticks_msec()+30000
	while editor._ground_batches.stats().get("pending_groups",0)>0 and Time.get_ticks_msec()<deadline:await process_frame
	print("BATCH_STATS ",editor._ground_batches.stats())
	check(doc.records.size()==before.size(),"appearance edits retain baked floor groups without restoring source pieces")
	var original:=shell.duplicate();original.erase("surface_paint")
	check(H.geometry(shell).mesh.get_surface_count()<=H.geometry(original).mesh.get_surface_count()+1,"wall paint adds at most one material surface to existing combined floor mesh")
	var saved:=await call_tool("save_world")
	if not saved.get("ok",false):quit(1);return
	var opened:=await call_tool("open_world",{"path":path})
	if not opened.get("ok",false):quit(1);return
	doc=editor._doc
	check(doc._find(member).get("window_design")=="diamond_lattice","window style survives save/reopen")
	check(doc._find(shell.uuid).has("surface_paint"),"wall material survives save/reopen")
	check(editor._buildings.conflicts(id).is_empty(),"ownership and component signatures remain valid")
	await review_windows(doc,window)
	editor.free();await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start.call_deferred(path)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null,"runtime async loader accepts painted house and window variants")
	if loaded[0]!=null:loaded[0].free()
	await process_frame # Loader queues itself for deletion after emitting finished.
	print("APPEARANCE FAILURES ",failed)
	quit(0 if failed==0 else 1)
