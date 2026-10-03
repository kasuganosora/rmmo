extends "res://tools/test_world3d_mcp.gd"
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Materials = preload("res://scripts/world_editor/surface_material_library.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")

func json_file(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()

func front_of(id: String) -> Dictionary:
	var result := await call_tool("list_object_surfaces", {"id":id})
	for face in result.faces:
		if Vector3(face.normal[0],face.normal[1],face.normal[2]).dot(Vector3.BACK) > .99: return face.target
	return {}

func run() -> void:
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	var directory := Paths.external_root().path_join("__pack_pbr_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory.path_join("materials"))
	json_file(directory.path_join("metadata.json"), {"id":"pbr_test","name":"PBR 临时测试"})
	var path := directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	var wall: String = doc.add_box("block", Vector3(0,1.5,0), Vector3(6,3,.3))
	var untouched: String = doc.add_box("block", Vector3(8,1.5,0), Vector3(2,3,.3))
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path; session.world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); await settle()
	editor._material_tool.library.directory = directory.path_join("materials")
	var probe := TCPServer.new()
	while probe.listen(port,"127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok,"start PBR HTTP fixture")
	var discovery := await rpc("tools/list")
	var specs: Array = discovery.result.tools
	check(specs.size()==118 and not specs.any(func(s):return s.name=="paint_tile"),"only current 3D MCP tools")
	var listing: Dictionary = specs.filter(func(s):return s.name=="list_surface_materials")[0]
	var painting: Dictionary = specs.filter(func(s):return s.name=="paint_surface")[0]
	check(listing.inputSchema.properties.has("category") and painting.inputSchema.properties.mapping.enum.has("meters"),"discovery advertises category and meter mapping")
	var catalog := await call_tool("list_surface_materials", {"category":"墙面／灰泥"})
	check(catalog.total>=1 and catalog.materials[0].material_id.begins_with("pack:default:"),"shared pack appears in temporary map via HTTP")
	if catalog.total==0: quit(1); return
	var row: Dictionary = catalog.materials[0]
	var material: Dictionary = row.material
	for field in Paint.MAP_FIELDS: check(FileAccess.file_exists(material[field]),"default PBR channel exists: "+field)
	var shared := Paint.make_material(material)
	check(shared == Paint.make_material(material.duplicate(true)),"equivalent faces share an immutable PBR material")
	var darker: Dictionary=material.duplicate(true); darker.color=[.3,.2,.1,1]
	var variant:=Paint.make_material(darker)
	check(variant!=shared and shared.albedo_color==Color(material.color[0],material.color[1],material.color[2],material.color[3]),"changing one paint definition does not tint other faces")
	check(Paint.make_material(material,BaseMaterial3D.CULL_DISABLED)!=shared and shared.cull_mode==BaseMaterial3D.CULL_BACK,"shared materials preserve independent source culling")
	var target := await front_of(wall)
	var before: Array = doc.records.duplicate(true); var undo_size: int = doc._undo.size()
	var args := {"id":wall,"target":target,"material_id":row.material_id,"mapping":"meters"}
	await call_tool("paint_surface",args)
	check(doc._undo.size()==undo_size+1 and not doc._find(untouched).has("surface_paint"),"PBR painting is isolated and one undo transaction")
	var visual: MeshInstance3D = editor._view.get_node(NodePath(wall))
	var slot := -1
	for i in visual.mesh.get_surface_count():
		var candidate = visual.get_active_material(i)
		if candidate != null and candidate.resource_name==material.name: slot=i
	check(slot>=0,"painted face uses actual default pack")
	if slot<0: quit(1); return
	var rendered: StandardMaterial3D = visual.get_active_material(slot)
	check(rendered.normal_enabled and rendered.normal_texture!=null and rendered.ao_enabled and rendered.roughness_texture!=null and rendered.metallic_texture!=null,"all five PBR channels connected")
	var arrays := visual.mesh.surface_get_arrays(slot)
	check(arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()==arrays[Mesh.ARRAY_VERTEX].size()*4,"tangents regenerated after UV projection")
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bounds := Rect2(uv[0],Vector2.ZERO)
	for point in uv: bounds=bounds.expand(point)
	check(bounds.size.is_equal_approx(Vector2(3,1.5)),"six meter wall repeats two meter material without stretching")
	var source_normal := Image.load_from_file(material.normal_path)
	var converted := Paint.texture(material,"normal_path").get_image()
	var pixel := Vector2i(317,291)
	check(absf(converted.get_pixelv(pixel).g-(1-source_normal.get_pixelv(pixel).g))<.01,"DirectX normal green channel converted once")
	await call_tool("undo"); check(doc.records==before,"undo restores original records")
	await call_tool("redo"); var painted_records: Array = doc.records.duplicate(true)
	await call_tool("paint_surface",args); check(doc._undo.size()==undo_size+1,"identical PBR paint is no-op")
	await call_tool("paint_surface",args.merged({"mapping":"unknown"},true),false)
	await call_tool("list_surface_materials",{"category":123},false)
	check(doc.records==painted_records and doc._undo.size()==undo_size+1,"invalid HTTP calls have no document/history side effects")
	var bad := material.duplicate(true); bad.normal_path="C:/outside.png"
	check(not Paint.material_valid(bad),"normal channel obeys external resource root")
	bad.normal_path=directory.path_join("missing_normal.png")
	json_file(directory.path_join("materials/broken.json"),{"material":bad})
	await call_tool("paint_surface",args.merged({"material_id":"broken"},true),false)
	check(doc.records==painted_records and doc._undo.size()==undo_size+1,"missing normal rejects before paint mutation")
	await call_tool("set_object_properties",{"ids":[wall],"locked":true})
	var protected: Array=doc.records.duplicate(true)
	await call_tool("paint_surface",args.merged({"material_id":"builtin:white"},true),false)
	check(doc.records==protected,"locked objects protected for PBR paint")
	await call_tool("undo")
	editor._material_panel.refresh(row.material_id)
	var panel=editor._material_panel
	var found_category := false
	for index in panel.category_picker.item_count:
		if panel.category_picker.get_item_metadata(index)=="墙面／灰泥":
			panel.category_picker.select(index); panel._refresh_materials(); found_category=true
	check(found_category and panel.picker.item_count==catalog.total,"UI category uses same catalog as HTTP")
	await call_tool("save_world",{"path":path})
	await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,painted_records) and Paint.missing(editor._doc.records).is_empty(),"save/reopen retains complete PBR record and dependencies")
	var runtime := Io.load_scene(path)
	var runtime_pbr := false
	for mesh in Paint.meshes(runtime):
		for index in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(index)
			if mat is StandardMaterial3D and mat.normal_enabled and mat.roughness_texture!=null and mat.ao_enabled: runtime_pbr=true
	check(runtime_pbr,"plain runtime glTF preserves PBR maps without editor records")
	runtime.free()
	var library := Library.new(directory.path_join("assets"))
	var captured := Prefabs.capture([editor._doc._find(wall)],library,"PBR fixture")
	check(captured.ok,"capture PBR prefab")
	if captured.ok:
		var loaded := Prefabs.read(captured.entry)
		check(loaded.ok,"read PBR prefab")
		if loaded.ok:
			for field in Paint.MAP_FIELDS:
				var copied: String=loaded.records[0].surface_paint[0].material[field]
				check(copied.begins_with(library.directory) and FileAccess.get_sha256(copied)==FileAccess.get_sha256(material[field]),"prefab copies independent channel: "+field)
	# Render a material gallery from actual shared pack entries for visual acceptance.
	var all_materials := await call_tool("list_surface_materials",{"limit":200})
	var gallery: Array=all_materials.materials.filter(func(e):return str(e.material_id).begins_with("pack:default:"))
	for index in gallery.size():
		var id: String=editor._doc.add_box("block",Vector3((index%4)*4-6,1.5,-float(index/4)*5-5),Vector3(3.5,3,.25))
		editor._doc._find(id).editor_name=gallery[index].material.name
	editor._rebuild(); await settle()
	var added: Array=editor._doc.records.slice(2)
	for index in added.size():
		var face := await front_of(added[index].uuid)
		await call_tool("paint_surface",{"id":added[index].uuid,"target":face,"material_id":gallery[index].material_id,"mapping":"meters"})
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=19
	editor._camera.position=Vector3(10,8,16); editor._camera.look_at(Vector3(0,1.5,-7.5))
	await settle()
	if not DisplayServer.get_name()=="headless":
		await RenderingServer.frame_post_draw
		editor._canvas.get_child(0).get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("fab_materials/gallery.png"))
	print("PBR_PACK_TEST_FINISHED failures=",failed," fixture=",directory)
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
