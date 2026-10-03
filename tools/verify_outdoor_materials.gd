extends "res://tools/test_world3d_roof_material.gd"
## Verify this asset import through real 3D UI/MCP and a separate review map.
func run() -> void:
	create_timer(300).timeout.connect(func():quit(2))
	root.size=Vector2i(1700,1100); root.content_scale_size=root.size
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/fab_outdoor_materials.json"))
	var folder:=Paths.cache_directory("outdoor_materials_%d"%Time.get_ticks_usec()); var path:=folder.path_join("map.gltf")
	var doc:=Doc.new(); var ids: Array[String]=[]
	for i in spec.materials.size(): ids.append(doc.add_box("ground",Vector3((i%4)*5-7.5,0,(i/4)*5-2.5),Vector3(4.6,.18,4.6)))
	check(doc.save(path)==OK,"independent material review map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=folder.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real loopback HTTP")
	var tools_: Array=(await rpc("tools/list")).result.tools
	check(tools_.any(func(t):return t.name=="paint_surface") and tools_.any(func(t):return t.name=="list_surface_materials"),"3D material tool discovery")
	for i in spec.materials.size():
		var item: Dictionary=spec.materials[i]; var material_id: String="pack:default:"+item.folder+"/material"
		var catalog:=await call_tool("list_surface_materials",{"category":item.category,"limit":200})
		var rows: Array=catalog.materials.filter(func(r):return r.material_id==material_id)
		check(rows.size()==1,"discover "+item.name)
		if rows.size()!=1: continue
		var material: Dictionary=rows[0].material
		check(material.normal_format=="opengl" and not material.has("roughness_path") and is_equal_approx(material.roughness,item.roughness),"corrected normals and explicit scalar roughness")
		for key in ["texture_path","normal_path","ao_path"]:
			var texture:=Paint.texture(material,key)
			check(texture!=null and texture.get_width()==2048 and texture.get_height()==2048,"2K "+key+" "+item.name)
		var faces:=await call_tool("list_object_surfaces",{"id":ids[i]})
		var top: Dictionary=faces.faces.filter(func(face):return float(face.normal[1])>.99)[0]
		var args:={"id":ids[i],"target":top.target,"material_id":material_id,"mapping":"meters"}
		var before: Array=doc.records.duplicate(true)
		await call_tool("paint_surface",args)
		if i==0:
			var painted: Array=doc.records.duplicate(true)
			await call_tool("undo"); check(doc.records==before,"undo paint")
			await call_tool("redo"); check(doc.records==painted,"redo paint")
			var history: int=doc._undo.size()
			await call_tool("paint_surface",args.merged({"mapping":"invalid"},true),false)
			check(doc.records==painted and doc._undo.size()==history,"invalid call has no content/history side effects")
			await call_tool("set_object_properties",{"ids":[ids[i]],"locked":true})
			var locked: Array=doc.records.duplicate(true)
			await call_tool("paint_surface",args.merged({"material_id":"builtin:white"},true),false)
			check(doc.records==locked,"lock prevents replacement"); await call_tool("undo")
		var panel=editor._material_panel; panel.refresh(material_id)
		var matched:=false
		for c in panel.category_picker.item_count:
			if panel.category_picker.get_item_metadata(c)==item.category:
				panel.category_picker.select(c); panel._refresh_materials(); matched=panel.picker.item_count==catalog.total
		check(matched,"UI and HTTP category agree: "+item.category)
	await call_tool("set_environment",{"preset":"day","sky_enabled":false,"background_color":[.12,.15,.18],"sun_rotation":[-45,140,0],"sun_energy":1,"ambient_energy":.5})
	var expected: Array=doc.records.duplicate(true)
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(expected,editor._doc.records) and Paint.missing(editor._doc.records).is_empty(),"all eight materials survive native save and reopen")
	var runtime:=Io.load_scene(path); var names: Dictionary={}
	for mesh in Paint.meshes(runtime):
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled and mat.ao_enabled: names[mat.resource_name]=true
	check(names.size()==8,"runtime glTF has eight normal/AO materials"); runtime.free()
	var normals: Array=[]
	for id in ids:
		var mesh=editor._view.get_node(NodePath(id))
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled: normals.append(mat)
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"distance":12,"pitch":-65,"yaw":0})
	await outdoor_shot("gallery")
	# Measure a close-up with static background, avoiding sky animation and the
	# dilution of normal-map differences by empty pixels in the full gallery.
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-2.5,0,2.5],"distance":3.5,"pitch":-50,"yaw":0})
	var normal_image:=await outdoor_shot("flagstone_detail")
	for mat in normals: mat.normal_enabled=false
	var flat_image:=await outdoor_shot("without_normal")
	var difference:=image_difference(normal_image,flat_image)
	check(difference>.1,"normals visibly change rendered lighting; pixel difference="+str(difference))
	for mat in normals: mat.normal_enabled=true
	var f:=FileAccess.open(Review.review_path("outdoor_materials/result.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failed,"materials":8,"review_map":path},"\t")); f.close()
	print("OUTDOOR_MATERIALS_VERIFIED failures=",failed," fixture=",path)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)

func outdoor_shot(label: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var picture: Image=editor._camera.get_viewport().get_texture().get_image()
	picture.save_png(Review.review_path("outdoor_materials/"+label+".png")); return picture
