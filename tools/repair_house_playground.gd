extends "res://tools/build_house_playground.gd"
## Authorized repair of the seven-house review map, through native atomic save.
func run()->void:
	DEST="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
	review_directory="house_revision_v10";rpc_timeout_ms=300000;Engine.max_fps=30
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	create_timer(1800).timeout.connect(func():quit(2))
	var doc=Doc.open_file(DEST)
	check(doc!=null,"open current review map")
	if doc==null:quit(1);return
	var original:Dictionary={}
	for r:Dictionary in doc.records:original[r.uuid]=r
	var registry:Dictionary=doc.map_meta.building_instances
	for id:String in registry:
		for part:String in registry[id].parts:
			var r:Dictionary=original.get(registry[id].parts[part],{})
			if r.is_empty() or Blueprint.geometry_signature(r)!=registry[id].signatures[part]:check(false,"source was edited "+part)
	if failed:quit(1);return
	doc.checkpoint_recovery()
	var records:Array=doc.records.filter(func(r):return not registry.has(r.get("building",{}).get("id","")))
	var repaint:Dictionary={}
	for id:String in registry.keys():
		var old:Dictionary=registry[id]
		var plan:=Blueprint.generate(old.parameters)
		check(plan.ok,"generate repaired house "+id)
		if not plan.ok:quit(1);return
		var basis:=Basis(Vector3.UP,deg_to_rad(old.yaw));var origin:=Blueprint.vec(old.position)
		var next:Dictionary=old.duplicate(true);next.parts={};next.signatures={}
		for r:Dictionary in plan.records:
			r.position=Blueprint.arr(origin+basis*Blueprint.vec(r.position))
			r.rotation=Blueprint.arr((basis*Basis.from_euler(Blueprint.vec(r.rotation)*PI/180)).get_euler()*180/PI)
			r.building.floor_y+=origin.y
			var part:String=r.building.part
			var previous:Dictionary=original.get(old.parts.get(part,""),{})
			r.uuid=previous.uuid if not previous.is_empty() else "obj_%d"%doc._next
			if previous.is_empty():doc._next+=1
			r.building.id=id;r.editor_group=id;r.editor_group_name=Blueprint.LABELS[plan.parameters.template]
			var same:bool=not previous.is_empty() and Blueprint.geometry_signature(r)==Blueprint.geometry_signature(previous)
			if same and previous.has("surface_paint") and r.get("building_shape")!="draped_cloth":r.surface_paint=previous.surface_paint.duplicate(true)
			else:repaint[r.uuid]=true
			for key:String in ["event","event_template","editor_name"]:
				if previous.has(key):r[key]=previous[key]
			if r.has("fixture") and previous.has("fixture"):r.fixture.open=previous.fixture.open
			next.parts[part]=r.uuid;next.signatures[part]=Blueprint.geometry_signature(r);records.append(r)
		registry[id]=next
		houses.append({"building_id":id,"position":old.position,"parameters":old.parameters})
	doc.records=records
	check(Blueprint.valid_ownership(doc.map_meta,records),"repaired geometry ownership valid")
	if failed:quit(1);return
	preload("res://scripts/net/net.gd").session().world3d_editor_path=DEST;preload("res://scripts/net/net.gd").session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=DEST.get_base_dir().path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"repair real HTTP MCP")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.any(func(t):return t.name=="set_environment" and t.inputSchema.properties.has("interior_cutaway")),"camera setting discovered")
	await call_tool("set_environment",{"interior_cutaway":false})
	check(not (await call_tool("get_environment")).environment.interior_cutaway,"automatic upper-storey hiding disabled")
	for row:Dictionary in (await call_tool("list_surface_materials",{"limit":200})).materials:definitions[row.material_id]=row.material
	var validation:Dictionary={};var n:=0
	for r:Dictionary in records:
		if not repaint.has(r.uuid):continue
		if r.get("building",{}).get("role")=="light_sconce":continue
		var listing:=author_faces(r)
		if not listing.ok:quit(1);return
		var entries:Array=[]
		for face:Dictionary in listing.faces:
			var role:=material_role(r,face);var entry:Dictionary=face.target.duplicate(true)
			entry.merge({"mapping":"meters","scale":[1,1],"rotation":0,"offset":[0,0]})
			entry.merge(settings_for(r,face,role));entry.material=definitions[IDS[role]].duplicate(true);entries.append(entry)
			r.surface_paint=entries
		if not Paint.valid(r,false,"",validation):check(false,"paint invalid "+str(r.uuid))
		n+=1
		if n%100==0:print("REPAIR_PAINT ",n,"/",repaint.size());await process_frame
	if failed:quit(1);return
	editor._dirty=true;editor._rebuild();await settle()
	await render_repair()
	var checkpoint:=FileAccess.open(Review.review_path(review_directory+"/checkpoint.json"),FileAccess.WRITE)
	checkpoint.store_string(JSON.stringify({"records":records,"meta":doc.map_meta,"houses":houses}));checkpoint.close()
	if "--preview-only" in OS.get_cmdline_user_args():editor._mcp.stop();quit(0);return
	await call_tool("save_world",{"background":true})
	while editor.saving():await create_timer(.5).timeout
	check(editor._save_job.state().result.get("saved",false),"native atomic save complete")
	var reopened:=await call_tool("open_world",{"path":DEST})
	if not reopened.get("ok",false):editor._mcp.stop();quit(1);return
	check(equivalent(editor._doc.records,records),"repair survives save/reopen")
	check(not Settings.resolve(editor._doc.map_meta).interior_cutaway,"disabled cutaway survives reopen")
	print("HOUSE_REPAIR_FINISHED failures=",failed," records=",records.size()," repaint=",repaint.size())
	editor._mcp.stop();quit(1 if failed else 0)

func render_repair()->void:
	editor._ground_batches.enabled=false;editor._ground_batches.clear();editor._grid.hide()
	editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	editor._canvas.get_child(0).use_taa=true
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.fov=65
	var origin:=Blueprint.vec(houses[0].position)
	for elevation in ["north","south","west","east"]:
		var poles:Array=editor._doc.records.filter(func(r):return r.get("building",{}).get("id")==houses[0].building_id and r.building.floor==1 and r.building.part.contains("/"+elevation+"/") and r.building.role=="curtain_rod")
		if poles.is_empty():continue
		var target:=Blueprint.vec(poles[0].position)-Vector3.UP*.5
		var inward:Vector3={"north":Vector3.BACK,"south":Vector3.FORWARD,"west":Vector3.RIGHT,"east":Vector3.LEFT}[elevation]
		editor._camera.position=target+inward*2.4+inward.cross(Vector3.UP)*.7+Vector3.UP*.35
		editor._camera.look_at(target)
		await settle();await RenderingServer.frame_post_draw
		editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/curtain_"+elevation+".png"))
	for i in 5:
		editor._camera.position=origin+Vector3(-1+i*.3,6.1,-4.5);editor._camera.look_at(origin+Vector3(-5.3,4.46,-4.5))
		await settle();await RenderingServer.frame_post_draw
		editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/floor_%d.png"%i))
	editor._camera.position=origin+Vector3(-1,6.1,-1.8);editor._camera.look_at(origin+Vector3(3.5,5.1,1.5))
	await settle();await RenderingServer.frame_post_draw
	editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/stairs.png"))
	for house:Dictionary in houses:
		origin=Blueprint.vec(house.position)
		if house.parameters.get("style")=="timber":
			await capture("timber_alignment",origin+Vector3(-24,7,1),origin+Vector3(0,4,0),22)
		if house.parameters.compound=="courtyard":
			var seam:=origin+Vector3(float(house.parameters.width)/2,4.45,float(house.parameters.depth)/2)
			for i in 3:
				editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.position=seam+Vector3(3+i*.5,.2,4-i*.5);editor._camera.look_at(seam)
				await settle();await RenderingServer.frame_post_draw
				editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/junction_%d.png"%i))
		if house.parameters.compound=="courtyard":await capture("courtyard_steps",origin+Vector3(12,5,30),origin+Vector3(0,1,15),19)
		if house.parameters.template=="shop":await capture("shopfront",origin+Vector3(8,5,-14),origin+Vector3(3,2,-7),10)
		if house.parameters.get("front_canopy",false) and house.parameters.template!="shop":
			var canopy:Array=editor._doc.records.filter(func(r):return r.get("building",{}).get("id")==house.building_id and r.building.part=="porch/canopy")
			if canopy.is_empty():continue
			var at:=Blueprint.vec(canopy[0].position)
			editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE
			editor._camera.position=at+Vector3(-2,-.7,-2);editor._camera.look_at(at)
			await settle();await RenderingServer.frame_post_draw
			editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/canopy.png"))
