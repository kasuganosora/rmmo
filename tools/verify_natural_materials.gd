extends "res://tools/test_world3d_roof_material.gd"
## Accept actual installed content through current 3D HTTP MCP in a temporary map.
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Natural material acceptance timeout"); quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/fab_unreal_natural_materials.json"))
	var directory:=Paths.cache_directory("natural_materials_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var ids: Array[String]=[]
	for i in spec.materials.size():
		ids.append(doc.add_box("block",Vector3((i%4)*5.0-7.5,0,floori(i/4.0)*5.0-5.0),Vector3(4.5,.2,4.5)))
	check(doc.save(path)==OK,"create isolated natural material gallery")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start loopback HTTP MCP")
	var discovery:=await rpc("tools/list")
	var tool_names: Array=[]
	for tool in discovery.result.tools: tool_names.append(tool.name)
	check("list_surface_materials" in tool_names and "paint_surface" in tool_names,"3D material tool discovery")
	var normal_materials: Array=[]
	for i in spec.materials.size():
		var item: Dictionary=spec.materials[i]
		var material_id: String="pack:default:"+item.folder+"/material"
		var catalog:=await call_tool("list_surface_materials",{"category":item.category,"limit":200})
		var rows: Array=catalog.materials.filter(func(row):return row.material_id==material_id)
		check(rows.size()==1,"HTTP catalog: "+item.name)
		if rows.size()!=1: continue
		var row: Dictionary=rows[0]
		check(row.material.normal_format=="directx" and row.source.type=="unreal_native_export","source and normal convention: "+item.name)
		for field in ["texture_path","normal_path","roughness_path"]:
			var texture:=Paint.texture(row.material,field)
			check(texture!=null and texture.get_width()==2048 and texture.get_height()==2048,"2K channel "+field+": "+item.name)
		var source_normal:=Image.load_from_file(row.material.normal_path)
		var converted:=Paint.texture(row.material,"normal_path").get_image()
		check(absf(converted.get_pixel(317,291).g-(1-source_normal.get_pixel(317,291).g))<.01,"single DirectX conversion: "+item.name)
		var faces:=await call_tool("list_object_surfaces",{"id":ids[i]})
		var top: Array=faces.faces.filter(func(face):return float(face.normal[1])>.99)
		if top.is_empty(): check(false,"resolve top face"); continue
		var args: Dictionary={"id":ids[i],"target":top[0].target,"material_id":material_id,"mapping":"meters"}
		var before: Array=doc.records.duplicate(true)
		await call_tool("paint_surface",args)
		var painted: Array=doc.records.duplicate(true)
		await call_tool("undo"); check(doc.records==before,"undo: "+item.name)
		await call_tool("redo"); check(doc.records==painted,"redo: "+item.name)
		var history: int=doc._undo.size()
		await call_tool("paint_surface",args.merged({"mapping":"invalid"},true),false)
		check(doc.records==painted and doc._undo.size()==history,"invalid call atomic: "+item.name)
		await call_tool("set_object_properties",{"ids":[ids[i]],"locked":true})
		var protected: Array=doc.records.duplicate(true)
		await call_tool("paint_surface",args.merged({"material_id":"builtin:white"},true),false)
		check(doc.records==protected,"locked object protected: "+item.name)
		await call_tool("undo")
		editor._material_panel.refresh(material_id)
		var panel=editor._material_panel
		var category_found:=false
		for c in panel.category_picker.item_count:
			if panel.category_picker.get_item_metadata(c)==item.category:
				panel.category_picker.select(c); panel._refresh_materials(); category_found=true
		check(category_found and panel.picker.item_count==catalog.total,"UI matches HTTP category: "+item.name)
	await call_tool("set_environment",{"preset":"day","sky_enabled":true,"sun_rotation":[-45,140,0],"sun_energy":1.0,"ambient_energy":.5})
	var snapshot: Array=doc.records.duplicate(true)
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,snapshot) and Paint.missing(editor._doc.records).is_empty(),"all 12 materials survive save/reopen without missing dependencies")
	var runtime:=Io.load_scene(path)
	var found: Dictionary={}
	for mesh in Paint.meshes(runtime):
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled and mat.roughness_texture!=null: found[mat.resource_name]=true
	check(found.size()==12,"runtime glTF carries all 12 PBR materials"); runtime.free()
	for id in ids:
		var mesh=editor._view.get_node(NodePath(id))
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled:
				normal_materials.append(mat)
				check(mesh.mesh.surface_get_arrays(slot)[Mesh.ARRAY_TANGENT]!=null,"normal tangent data present")
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=24
	editor._camera.position=Vector3(0,22,15); editor._camera.look_at(Vector3.ZERO)
	var with_normal:=await natural_shot("gallery")
	for mat in normal_materials: mat.normal_enabled=false
	var without_normal:=await natural_shot("without_normal")
	check(image_difference(with_normal,without_normal)>.1,"normal maps visibly affect GPU lighting")
	for mat in normal_materials: mat.normal_enabled=true
	editor._camera.size=6; editor._camera.position=Vector3(3,5,5); editor._camera.look_at(Vector3(2.5,0,0))
	await natural_shot("sand_detail")
	print("NATURAL_MATERIALS_VERIFIED failures=",failed," fixture=",path)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)

func natural_shot(label: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var picture: Image=editor._canvas.get_child(0).get_texture().get_image()
	picture.save_png(Review.review_path("natural_materials/"+label+".png"))
	return picture
