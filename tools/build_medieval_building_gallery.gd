extends "res://tools/build_medieval_material_demo.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")

func run() -> void:
	Engine.max_fps=30
	if OS.get_cmdline_user_args().has("--interior-detail"):
		await render_interior_detail();return
	if OS.get_cmdline_user_args().has("--refresh") or OS.get_cmdline_user_args().has("--capture-only") or OS.get_cmdline_user_args().has("--from-draft"):
		await refresh_gallery();return
	create_timer(1800).timeout.connect(func():push_error("Gallery timeout");quit(2))
	root.size=Vector2i(1920,1200); root.content_scale_size=root.size
	review_directory="building_v5"
	var directory:=Paths.cache_directory("medieval_gallery_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var ground: String=doc.add_box("ground",Vector3(0,-.25,0),Vector3(90,.5,85)); assignments[ground]="street"
	check(doc.save(path)==OK,"create separate gallery document")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start gallery HTTP MCP")
	var discovery:=await rpc("tools/list");check(discovery.result.tools.size()==69,"discover current gallery and fixture controls")
	var catalog:=await call_tool("list_surface_materials",{"limit":200})
	var snapshot:=CatalogSnapshot.new();snapshot.rows=catalog.materials;editor._material_tool.library=snapshot
	for row in catalog.materials:definitions[row.material_id]=row.material
	var presets: Array=Blueprint.medieval_presets(); var selected: Array=[4,0,5,1,6,2]; var placements: Array=[]; var houses: Array=[]
	for i in selected.size():
		var preset: Dictionary=presets[selected[i]]; var at:=Vector3((i%3-1)*28.0,0,(floori(i/3.0)*2-1)*20.0)
		placements.append({"parameters":preset.parameters,"position":Blueprint.arr(at)})
		houses.append({"preset":preset.id,"name":preset.name,"parameters":preset.parameters,"position":Blueprint.arr(at)})
	var made:=await call_tool("generate_buildings",{"placements":placements})
	if not made.get("ok",false):quit(1);return
	for i in houses.size():houses[i].building_id=made.building_ids[i]
	await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_color":[1,.96,.89],"sun_energy":1.35,"ambient_color":[.78,.82,.89],"ambient_energy":.48,"background_color":[.56,.61,.65],"sun_shadows":true,"ambient_occlusion":true})
	await paint_world()
	await call_tool("save_world"); var before: Array=doc.records.duplicate(true)
	await call_tool("open_world",{"path":path});doc=editor._doc
	check(equivalent(doc.records,before) and Paint.missing(doc.records).is_empty(),"six textured houses and normal maps survive save/reopen")
	check(editor._buildings.instances().size()==6,"all six houses retain independent whole-building identity")
	await capture_gallery(houses,ground)
	var report: Dictionary={"map_path":path,"houses":houses,"objects":doc.records.size(),"failures":failed,"materials":IDS}
	var file:=FileAccess.open(Review.review_path("building_v5/gallery.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MEDIEVAL_GALLERY_FINISHED ",JSON.stringify(report))
	editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)

func capture_gallery(houses: Array, ground: String, save_document:=true) -> void:
	var doc=editor._doc
	editor._grid.hide(); editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	await capture("gallery",Vector3(85,100,-100),Vector3(0,3,0),93)
	for house in houses:
		var own: Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==house.building_id)
		var bounds: AABB=preload("res://scripts/world_editor/selection_geometry.gd").bounds(own)
		var target:=bounds.get_center()+Vector3(0,.5,0)
		var size: float=maxf(20,maxf(bounds.size.y+5,bounds.size.z*1.2))
		var others: Array=[]
		for record in doc.records:
			if record.has("building") and record.building.id!=house.building_id:
				var node: Node3D=editor._view.get_node(NodePath(record.uuid));others.append(node);node.hide()
		await capture(house.preset,target+Vector3(23,17,-28),target,size)
		if house.preset in ["courtyard","wing_house","tall_house"]: await capture(house.preset+"_rear",target+Vector3(-24,20,30),target,size)
		for node in others:node.show()
	# Show the same door/window assembled in two states through the actual MCP API.
	var hero: Dictionary=houses[1];var at:=Blueprint.vec(hero.position)
	var listing:=await call_tool("list_building_components",{"id":hero.building_id})
	var edited: Array=[]
	for row in listing.components:
		if row.id.begins_with("f0/north/"):
			await call_tool("set_building_component_state",{"id":hero.building_id,"component_id":row.id,"open":0});edited.append(row)
	await capture("components_closed",at+Vector3(8,4.4,-17),at+Vector3(.0,1.4,-6),9)
	for row in edited:await call_tool("set_building_component_state",{"id":hero.building_id,"component_id":row.id,"open":1})
	await capture("components_open",at+Vector3(8,4.4,-17),at+Vector3(.0,1.4,-6),9)
	for row in edited:await call_tool("set_building_component_state",{"id":hero.building_id,"component_id":row.id,"open":row.open})
	# An isolated view exposes the generated foundation; no authored visibility changes.
	editor._view.get_node(NodePath(ground)).hide()
	await capture("foundation",at+Vector3(17,8,-21),at+Vector3(0,1,-1),18)
	editor._view.get_node(NodePath(ground)).show()
	var hidden: Array=[]
	for record in doc.records:
		if record.get("building",{}).get("id")!=hero.building_id:continue
		if record.building.floor>=1 or record.building.part.contains("/north/") or record.building.part.contains("/east/") or record.building.part.begins_with("porch/"):
			var node: Node3D=editor._view.get_node(NodePath(record.uuid));hidden.append(node);node.hide()
	await capture("interior",at+Vector3(16,19,-23),at+Vector3(0,1,0),18)
	for node in hidden:node.show()
	if save_document: await call_tool("save_world")

func refresh_gallery() -> void:
	create_timer(900).timeout.connect(func():quit(2))
	root.size=Vector2i(1920,1200);root.content_scale_size=root.size;review_directory="building_v5"
	var report_path:=Review.review_path("building_v5/gallery.json")
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var path: String=report.map_path
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	var arguments:=OS.get_cmdline_user_args()
	if arguments.has("--from-draft"):
		var draft_path: String=arguments[arguments.find("--from-draft")+1]
		var store_=preload("res://scripts/world_editor/draft_store.gd").new(draft_path.get_base_dir())
		var recovery: Dictionary=store_.read(draft_path.get_file().trim_suffix(".draft"))
		check(recovery.ok,"read checksummed completed authoring checkpoint")
		if not recovery.ok:quit(1);return
		var restored=Doc.new();restored.apply_recovery(recovery.state);session.world3d_editor_doc=restored
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("review_drafts")
	root.add_child(editor);await settle();editor._safety.enabled=false;check(not editor._load_failed,"reopen saved gallery for final inspection")
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start final review MCP")
	check(editor._buildings.instances().size()==6 and Paint.missing(editor._doc.records).is_empty(),"all six houses and PBR dependencies reopen")
	if arguments.has("--from-draft"):
		for house in report.houses:house.parameters=editor._buildings.instances()[house.building_id].parameters.duplicate(true)
		check(editor._buildings.instances().keys().all(func(id):return editor._buildings.conflicts(id).is_empty()),"restored samples retain clean geometry ownership")
		var ground: String=editor._doc.records.filter(func(r):return not r.has("building"))[0].uuid
		await capture_gallery(report.houses,ground)
		report.objects=editor._doc.records.size();report.failures=failed;report.materials=IDS
		var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
		print("MEDIEVAL_GALLERY_CHECKPOINT_FINISHED failures=",failed)
		editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0);return
	if OS.get_cmdline_user_args().has("--capture-only"):
		var ground: String=editor._doc.records.filter(func(r):return not r.has("building"))[0].uuid
		await capture_gallery(report.houses,ground,false)
		print("MEDIEVAL_GALLERY_CAPTURE_FINISHED failures=",failed)
		editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0);return
	var catalog:=await call_tool("list_surface_materials",{"limit":200})
	var snapshot:=CatalogSnapshot.new();snapshot.rows=catalog.materials;editor._material_tool.library=snapshot
	for row in catalog.materials:definitions[row.material_id]=row.material
	for house in report.houses:
		if house.parameters.dormers==0:continue
		if editor._buildings.instances()[house.building_id].parts.has("roof/dormer0/back"):continue
		await call_tool("update_building",{"id":house.building_id,"parameters":{"seed":int(house.parameters.seed)+7}})
		house.parameters=editor._buildings.instances()[house.building_id].parameters.duplicate(true)
	var doc=editor._doc
	editor._material_tool.action="paint";editor._material_tool.start_stroke()
	for record in doc.records.duplicate(true):
		if not str(record.get("building",{}).get("part","")).contains("/dormer"):continue
		var listing: Dictionary=editor._material_tool.list_faces(record.uuid,0,200)
		for face in listing.get("faces",[]):
			var role:=material_role(record,face)
			var result: Dictionary=editor._material_tool.paint(record.uuid,face.target,IDS[role],settings_for(record,face,role))
			if not result.ok: check(false,str(result))
		await process_frame
	editor._material_tool.finish()
	check(editor._buildings.instances().keys().all(func(id):return editor._buildings.conflicts(id).is_empty()),"final samples retain clean building identity after material refinement")
	var ground: String=doc.records.filter(func(r):return not r.has("building"))[0].uuid
	await capture_gallery(report.houses,ground)
	report.objects=doc.records.size();report.failures+=failed
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MEDIEVAL_GALLERY_REVIEW_FINISHED failures=",failed)
	editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)

func render_interior_detail() -> void:
	# A render-only cutaway: keep saved walls/roofs intact and remove their attached
	# porch from this view as well, so the inspection never shows a floating canopy.
	root.size=Vector2i(1582,997);root.content_scale_size=root.size;root.msaa_3d=Viewport.MSAA_4X
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Review.review_path("building_v5/gallery.json")))
	var doc=Doc.open_file(report.map_path)
	if doc==null:quit(1);return
	var hero: Dictionary=report.houses[1];var at:=Blueprint.vec(hero.position)
	doc.records=doc.records.filter(func(r):
		if not r.has("building"):return true
		var b: Dictionary=r.building
		return b.id==hero.building_id and b.floor==0 and not b.part.contains("/north/") and not b.part.contains("/east/") and not b.part.begins_with("porch/")
	)
	var scene: Node3D=doc.build();root.add_child(scene)
	var sun:=DirectionalLight3D.new();root.add_child(sun)
	var camera:=Camera3D.new();camera.environment=Environment.new();root.add_child(camera)
	Settings.apply(Settings.resolve(doc.map_meta),sun,camera.environment)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=18;camera.position=at+Vector3(16,19,-23);camera.look_at(at+Vector3(0,1,0));camera.current=true
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(Review.review_path("building_v5/interior.png"))
	print("MEDIEVAL_INTERIOR_RENDER ",error_string(result));quit(0 if result==OK else 1)
