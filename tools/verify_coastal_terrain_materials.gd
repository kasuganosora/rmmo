extends "res://tools/test_world3d_roof_material.gd"
func run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("coastal_terrain_%d"%Time.get_ticks_usec())
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var ground: String=doc.add_box("block",Vector3.ZERO,Vector3(16,.2,16))
	check(doc.save(path)==OK,"isolated grass fixture")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real loopback HTTP")
	var tools_: Array=(await rpc("tools/list")).result.tools
	check(tools_.any(func(t):return t.name=="paint_surface"),"3D paint tool discovery")
	var specs: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tools/fab_coastal_terrain_materials.json")).materials
	for spec in specs:
		doc=editor._doc
		print("VERIFY_MATERIAL ",spec.slug)
		var catalog:=await call_tool("list_surface_materials",{"category":spec.category,"limit":200})
		var rows: Array=catalog.materials.filter(func(r):return r.material_id=="pack:default:terrain/"+str(spec.slug)+"/material")
		check(rows.size()==1,str(spec.slug)+" discovered through HTTP")
		if rows.size()!=1: quit(1); return
		var row: Dictionary=rows[0]
		check(row.material.tile_size==spec.tile_size,"scanned repeat size")
		for key in spec.maps.keys():
			var tex:=Paint.texture(row.material,key)
			check(tex!=null and tex.get_width()==2048 and tex.get_height()==2048,"2K channel: "+key)
		var surfaces:=await call_tool("list_object_surfaces",{"id":ground})
		var face: Dictionary=surfaces.faces.filter(func(f):return float(f.normal[1])>.99)[0]
		var args:={"id":ground,"target":face.target,"material_id":row.material_id,"mapping":"meters"}
		var before: Array=doc.records.duplicate(true)
		await call_tool("paint_surface",args)
		var painted: Array=doc.records.duplicate(true)
		await call_tool("undo"); check(doc.records==before,"undo restores records")
		await call_tool("redo"); check(doc.records==painted,"redo restores paint")
		var history: int=doc._undo.size()
		await call_tool("paint_surface",args.merged({"mapping":"invalid"},true),false)
		check(doc.records==painted and doc._undo.size()==history,"invalid call has no side effects")
		await call_tool("set_object_properties",{"ids":[ground],"locked":true})
		var locked: Array=doc.records.duplicate(true)
		await call_tool("paint_surface",args.merged({"material_id":"builtin:white"},true),false)
		check(doc.records==locked,"lock protects material"); await call_tool("undo")
		var panel=editor._material_panel; panel.refresh(row.material_id)
		var matched:=false
		for c in panel.category_picker.item_count:
			if panel.category_picker.get_item_metadata(c)==spec.category:
				panel.category_picker.select(c); panel._refresh_materials(); matched=panel.picker.item_count==catalog.total
		check(matched,"UI matches MCP category")
		await call_tool("set_environment",{"preset":"day","sky_enabled":false,"background_color":[.12,.15,.18],"sun_rotation":[-35,30,0],"sun_energy":1,"ambient_energy":.5})
		var expected: Array=doc.records.duplicate(true)
		await call_tool("save_world"); await call_tool("open_world",{"path":path})
		check(equivalent(expected,editor._doc.records) and Paint.missing(editor._doc.records).is_empty(),"save/reopen preserves material")
		var runtime:=Io.load_scene(path); var found:=false
		for mesh in Paint.meshes(runtime):
			for i in mesh.mesh.get_surface_count():
				var mat=mesh.get_active_material(i)
				if mat is StandardMaterial3D and mat.normal_enabled and mat.ao_enabled==spec.maps.has("ao_path") and mat.roughness_texture!=null: found=true
		check(found,"runtime glTF retains PBR channels"); runtime.free()
		editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
		editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=20
		editor._camera.position=Vector3(0,15,10); editor._camera.look_at(Vector3.ZERO)
		await terrain_shot(str(spec.slug)+"/repeat")
		editor._camera.size=float(spec.tile_size[0])*1.5
		editor._camera.position=Vector3(0,5,4); editor._camera.look_at(Vector3.ZERO)
		var enabled:=await terrain_shot(str(spec.slug)+"/detail")
		var mesh=editor._view.get_node(NodePath(ground)); var normals: Array=[]
		for i in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(i)
			if mat is StandardMaterial3D and mat.normal_enabled: normals.append(mat); mat.normal_enabled=false
		var disabled:=await terrain_shot(str(spec.slug)+"/without_normal")
		var difference:=image_difference(enabled,disabled)
		check(difference>.1,"normal changes actual ground lighting; difference="+str(difference))
		for mat in normals: mat.normal_enabled=true
	print("COASTAL_TERRAIN_VERIFIED failures=",failed," fixture=",path)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)

func terrain_shot(label: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var picture: Image=editor._camera.get_viewport().get_texture().get_image()
	picture.save_png(Review.review_path("coastal_terrain/"+label+".png")); return picture
