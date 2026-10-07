extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")

func prefab(id: String,span: float,color: Color) -> Dictionary:
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(span,0,0),Vector3(0,0,span)])
	var data:={"materials":[{"values":{"albedo_color":color,"roughness":.6}}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3.ZERO,Vector3(span,0,span)),"box_size":Vector3.ZERO}],"entries":[[["fixture"],[0,0]]]}
	var bytes:=var_to_bytes(data)
	return {"uuid":id,"kind":"box","surface_id":"block","collision":"block","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"prefab_locked":true,"building":{"id":"test","part":id,"role":"wall","floor":0,"floor_y":0.},"house_prefab":{"version":1,"length":bytes.size(),"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))},"prefab_materials":[]}

func run() -> void:
	Engine.max_fps=60
	var frozen:=Doc.new(); var original_color:=Color(.6,.7,.8)
	frozen.records=[prefab("first",1.,original_color),prefab("second",2.,original_color)]
	var prior_pool: Dictionary={"existing_context":true}; frozen.load_material_pool=prior_pool
	var view: Node3D=frozen.build()
	var material: StandardMaterial3D=view.get_node("first").mesh.surface_get_material(0)
	check(material==view.get_node("second").mesh.surface_get_material(0),"different frozen geometry shares identical immutable material during one build")
	check(is_same(frozen.load_material_pool,prior_pool) and prior_pool.size()==1,"build restores caller material context without writing into it")
	# Frozen geometry/material regeneration replaces authored payloads, never
	# mutates a shared Material; retain the first view to catch cross-view changes.
	frozen.records[0]=prefab("first",1.,Color(.2,.3,.4))
	var rebuilt: Node3D=frozen.build()
	check(rebuilt.get_node("first").mesh.surface_get_material(0).albedo_color==Color(.2,.3,.4) and rebuilt.get_node("second").mesh.surface_get_material(0).albedo_color==original_color and material.albedo_color==original_color,"new material payload leaves other prefab and earlier view unchanged")
	view.free(); rebuilt.free()
	var directory:=Paths.cache_directory("load_material_context_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var asset_path:=directory.path_join("box.glb")
	var model:=Node3D.new(); model.name="Model"
	var mesh:=MeshInstance3D.new(); mesh.name="Mesh"; mesh.mesh=BoxMesh.new(); model.add_child(mesh)
	check(Io.save_scene(model,asset_path)==OK,"real tiny imported asset exported")
	model.free()
	var texture_path:=directory.path_join("paint.png")
	var image:=Image.create(1,1,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE); image.save_png(texture_path)
	var definition:={"name":"Scoped paint","color":[.7,.5,.3,1.],"roughness":.8,"texture_path":texture_path}
	var doc:=Doc.new(); var first: String=doc.add_asset({"asset_path":asset_path},Vector3.ZERO); var second: String=doc.add_asset({"asset_path":asset_path},Vector3(5,0,0))
	var unpainted: Node3D=doc._asset(doc._find(first)); var node: MeshInstance3D=Paint.meshes(unpainted)[0]
	var geo: Dictionary=Paint.geometry(node); var target:={"mesh":str(unpainted.get_path_to(node)),"surface":0,"face":geo.surfaces[0].faces.keys()[0],"geometry":geo.surfaces[0].signature}
	unpainted.free()
	var paint: Dictionary=target.merged({"material":definition,"scale":[1.,1.],"offset":[0.,0.],"rotation":0.,"mapping":"uv"})
	for record in doc.records: record.surface_paint=[paint.duplicate(true)]
	doc.load_paint_validation={}; doc.load_texture_checks={}
	var painted: Node3D=doc._asset(doc._find(first))
	check(not painted.has_meta("paint_error") and not doc.load_paint_validation.is_empty() and not doc.load_texture_checks.is_empty(),"asset paint uses existing operation validation and texture check caches")
	painted.free(); doc.load_paint_validation=null; doc.load_texture_checks=null
	var path:=directory.path_join("map.gltf"); check(doc.save(path)==OK,"small painted map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); editor._material_directory=directory.path_join("materials")
	root.add_child(editor); editor._safety.enabled=false; await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP material-context server")
	await call_tool("open_world",{"path":path})
	check(editor._doc.load_material_pool==null and editor._doc.load_paint_validation==null and editor._doc.load_texture_checks==null,"async open restores operation-only caches")
	var old_second: MeshInstance3D=Paint.meshes(editor._view.get_node(second))[0]
	var old_mesh: Mesh=old_second.mesh
	var blue_path:=directory.path_join("blue.png"); image.fill(Color.BLUE); image.save_png(blue_path)
	var imported:=await call_tool("import_surface_material",{"path":blue_path,"name":"New blue paint"})
	await call_tool("paint_surface",{"id":first,"target":target,"material_id":imported.material_id})
	check(editor._doc._find(second).surface_paint[0].material==definition and old_second.mesh==old_mesh and editor._doc._find(first).surface_paint[0].material!=definition,"supported HTTP material edit leaves other instance and its mesh unchanged")
	await call_tool("undo"); check(editor._doc._find(first).surface_paint[0].material==definition,"material undo restores authored definition")
	await call_tool("redo"); check(editor._doc._find(first).surface_paint[0].material!=definition,"material redo restores only edited definition")
	# Open the original on-disk map again after removing a previously accepted
	# texture. Validation stays schema-only; painting must report the missing file.
	DirAccess.remove_absolute(texture_path)
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(editor._view.get_node(first).has_meta("paint_error") and editor._view.get_node(second).has_meta("paint_error"),"next async load rechecks removed texture despite previous operation cache")
	image.fill(Color.WHITE); image.save_png(texture_path)
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(not editor._view.get_node(first).has_meta("paint_error") and not editor._view.get_node(second).has_meta("paint_error"),"later repaired texture is checked in a fresh load")
	editor.queue_free(); await settle()
	print("EDITOR_LOAD_MATERIAL_CONTEXT_FAILED=",failed); quit(1 if failed else 0)
