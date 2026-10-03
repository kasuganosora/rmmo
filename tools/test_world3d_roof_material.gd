extends "res://tools/test_world3d_mcp.gd"
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Review = preload("res://scripts/asset/art_paths.gd")

func shot(label: String) -> Image:
	await settle()
	await RenderingServer.frame_post_draw
	var result: Image=editor._canvas.get_child(0).get_texture().get_image()
	result.save_png(Review.review_path("generated_roof/"+label+".png"))
	return result

func image_difference(a: Image, b: Image) -> float:
	var x:=a.get_data(); var y:=b.get_data(); var total:=0.0
	if x.size()!=y.size(): return 0.0
	for index in range(0,x.size(),17): total+=absf(float(x[index])-float(y[index]))
	return total/(float(x.size())/17)

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Roof material test timeout"); quit(2))
	root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("roof_material_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	doc.add_box("ground",Vector3(0,-.1,0),Vector3(26,.2,26))
	check(doc.save(path)==OK,"create isolated roof fixture")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real roof HTTP fixture")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.size()==113,"current 3D material tools remain discoverable")
	var catalog:=await call_tool("list_surface_materials",{"category":"屋顶／陶瓦"})
	var selected: Array=catalog.materials.filter(func(row):return row.material_id=="pack:default:roofs/terracotta_plain/material")
	check(selected.size()==1,"generated roof discovered in classified default pack")
	if selected.size()!=1: quit(1); return
	var row: Dictionary=selected[0]
	check(row.source.type=="generated" and row.material.normal_format=="opengl","generated provenance and normal convention retained")
	var normal:=Paint.texture(row.material,"normal_path")
	check(normal!=null and Paint.texture(row.material,"roughness_path")!=null,"normal and roughness maps load")
	var made:=await call_tool("generate_buildings",{"parameters":Blueprint.medieval_presets()[0].parameters,"placements":[{"position":[0,0,0]}]})
	if not made.get("ok",false): quit(1); return
	var roofs: Array=doc.records.filter(func(record):return record.get("building_shape")=="roof_prism" and record.roof_mesh.semantic=="roof_top")
	check(roofs.size()>=2,"generated gable roof has paintable final slope fragments")
	var roof_ids: Array=[]
	for record in roofs:
		roof_ids.append(record.uuid)
		var surfaces:=await call_tool("list_object_surfaces",{"id":record.uuid})
		var top: Array=surfaces.faces.filter(func(face):return int(face.target.surface)==0)
		check(top.size()==1,"resolve upper face on sloped generated roof")
		if top.size()!=1: continue
		var before: Array=doc.records.duplicate(true)
		var side: float=-1 if float(record.position[0])<0 else 1
		# The final roof's metre UVs share a building-local anchor across cuts.
		# Rotate before scaling into the material's physical tile dimensions.
		var tile: Array=row.material.get("tile_size",[1,.72])
		await call_tool("paint_surface",{"id":record.uuid,"target":top[0].target,"material_id":row.material_id,"mapping":"uv","rotation":side*90,"scale":[1.0/float(tile[0]),1.0/float(tile[1])]})
		await call_tool("undo"); check(doc.records==before,"roof paint undo restores generated building")
		await call_tool("redo")
		var visual=editor._view.get_node(NodePath(record.uuid))
		var connected:=false
		for slot in visual.mesh.get_surface_count():
			var mat=visual.get_active_material(slot)
			if mat is StandardMaterial3D and mat.resource_name==row.material.name:
				connected=mat.normal_enabled and mat.normal_texture==normal and mat.roughness_texture!=null
				check(visual.mesh.surface_get_arrays(slot)[Mesh.ARRAY_TANGENT]!=null,"sloped roof has matching normal tangent space")
		check(connected,"generated roof renders real normal and roughness textures")
	var snapshot: Array=doc.records.duplicate(true)
	await call_tool("paint_surface",{"id":roof_ids[0],"target":{"mesh":".","surface":0,"face":0,"geometry":"bad"},"material_id":row.material_id},false)
	check(doc.records==snapshot,"invalid roof target fails without side effects")
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,snapshot) and Paint.missing(editor._doc.records).is_empty(),"roof normal and roughness survive save and reopen")
	var runtime:=Io.load_scene(path); var found:=false
	for mesh in Paint.meshes(runtime):
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled and mat.roughness_texture!=null: found=true
	check(found,"exported glTF carries roof normal and roughness for runtime"); runtime.free()
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=19
	editor._camera.position=Vector3(17,17,21); editor._camera.look_at(Vector3(0,4,0))
	await shot("house")
	editor._camera.size=7; editor._camera.position=Vector3(12,16,4); editor._camera.look_at(Vector3(1.6,8.4,0))
	await shot("roof_detail")
	editor._camera.size=2
	var with_normal:=await shot("roof_macro")
	# Compare actual normal-enabled and normal-disabled renders under identical light.
	var materials: Array=[]
	for id in roof_ids:
		var mesh=editor._view.get_node(NodePath(id))
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot)
			if mat is StandardMaterial3D and mat.normal_enabled: materials.append(mat)
	for mat in materials: mat.normal_enabled=false
	var without_normal:=await shot("roof_without_normal")
	check(image_difference(with_normal,without_normal)>.2,"normal texture visibly changes roof shading")
	for mat in materials: mat.normal_enabled=true
	editor._sun.rotation_degrees.y+=100
	var alternate_light:=await shot("roof_alternate_light")
	check(image_difference(with_normal,alternate_light)>1.0,"normal-enabled roof reacts to alternate light direction")
	print("ROOF_MATERIAL_TEST_FINISHED failures=",failed," fixture=",path)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
