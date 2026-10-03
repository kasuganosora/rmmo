extends "res://tools/test_world3d_roof_material.gd"
## Isolated content acceptance; never changes a user map.
func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	root.size=Vector2i(1440,900); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("river_material_%d"%Time.get_ticks_usec())
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var water: String=doc.add_box("water",Vector3(0,0,0),Vector3(24,.2,32))
	doc.add_box("ground",Vector3(-14,-.1,0),Vector3(4,.4,32))
	doc.add_box("ground",Vector3(14,-.1,0),Vector3(4,.4,32))
	check(doc.save(path)==OK,"create isolated water preview")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start loopback HTTP")
	var catalog:=await call_tool("list_surface_materials",{"category":"水面／河流"})
	var rows: Array=catalog.materials.filter(func(row):return row.material_id=="pack:default:water/river_ripples/material")
	check(rows.size()==1,"generated water discovered through real HTTP MCP")
	if rows.size()!=1: quit(1); return
	var row: Dictionary=rows[0]
	var faces:=await call_tool("list_object_surfaces",{"id":water})
	var face: Dictionary=faces.faces.filter(func(f):return float(f.normal[1])>.99)[0]
	var before: Array=doc.records.duplicate(true)
	await call_tool("paint_surface",{"id":water,"target":face.target,"material_id":row.material_id,"mapping":"meters"})
	await call_tool("undo"); check(doc.records==before,"water paint undo")
	await call_tool("redo")
	var snapshot: Array=doc.records.duplicate(true)
	await call_tool("paint_surface",{"id":water,"target":face.target,"material_id":row.material_id,"mapping":"invalid"},false)
	check(doc.records==snapshot,"invalid material operation is atomic")
	await call_tool("set_environment",{"preset":"day","sky_enabled":true,"sun_rotation":[-25,150,0],"sun_energy":1.2,"ambient_energy":.5})
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,snapshot) and Paint.missing(editor._doc.records).is_empty(),"water normal survives native save and reopen")
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	editor._camera.position=Vector3(8,8,15); editor._camera.look_at(Vector3(0,0,-2))
	var normal:=Paint.texture(row.material,"normal_path")
	check(normal!=null and normal.get_width()<=2048,"normal enabled within 2K budget")
	var visual=editor._view.get_node(NodePath(water))
	var water_material: StandardMaterial3D
	for i in visual.mesh.get_surface_count():
		var mat=visual.get_active_material(i)
		if mat is StandardMaterial3D and mat.resource_name==row.material.name: water_material=mat
	check(water_material!=null and water_material.normal_enabled,"real scene uses generated normal")
	if water_material==null: quit(1); return
	var with_normal:=await river_shot("preview")
	water_material.normal_enabled=false
	var without_normal:=await river_shot("without_normal")
	check(image_difference(with_normal,without_normal)>.1,"generated normal visibly affects water lighting")
	water_material.normal_enabled=true
	print("RIVER_MATERIAL_VERIFIED failures=",failed," fixture=",path)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)

func river_shot(label: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var picture: Image=editor._canvas.get_child(0).get_texture().get_image()
	picture.save_png(Review.review_path("generated_river/"+label+".png"))
	return picture
