extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_response.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const BASE="D:/code/rmmo_runtime"
const ART=BASE+"/art_sources/wall_guild_banners/soviet_variant/optimized"
const LABEL="写实朱红燕尾长旗·苏联五星镰刀锤子"
func triangles(mesh:ArrayMesh)->Dictionary:
	var faces=mesh.get_faces();var result={}
	for k in range(0,faces.size(),3):
		var vertices=[]
		for j in 3:
			var p=faces[k+j]*100000.0
			vertices.append("%d,%d,%d"%[roundi(p.x),roundi(p.y),roundi(p.z)])
		# Cyclic normalization preserves winding while ignoring index/triangle order.
		var keys=[";".join(vertices),";".join([vertices[1],vertices[2],vertices[0]]),";".join([vertices[2],vertices[0],vertices[1]])];keys.sort()
		result[keys[0]]=result.get(keys[0],0)+1
	return result
func compare_native(source:String,destination:String)->void:
	var a=Library.instantiate_preview(source);var b=Library.instantiate_preview(destination)
	var aa=Paint.meshes(a);var bb=Paint.meshes(b)
	check(aa.size()==bb.size(),"normalized mesh count")
	for i in mini(aa.size(),bb.size()):
		check(triangles(aa[i].mesh)==triangles(bb[i].mesh),"normalized triangle positions and winding")
		check(aa[i].mesh.get_surface_count()==bb[i].mesh.get_surface_count(),"normalized material surfaces")
		for j in mini(aa[i].mesh.get_surface_count(),bb[i].mesh.get_surface_count()):
			var am=aa[i].mesh.surface_get_material(j);var bm=bb[i].mesh.surface_get_material(j)
			for prop in ["albedo_color","roughness","metallic","normal_scale"]:
				check(am.get(prop)==bm.get(prop),"normalized material "+prop)
			for prop in ["albedo_texture","normal_texture","roughness_texture"]:
				var at=am.get(prop);var bt=bm.get(prop)
				check((at==null)==(bt==null),"normalized texture presence")
				if at!=null and bt!=null:check(at.get_image().get_data()==bt.get_image().get_data(),"normalized texture pixels")
	a.free();b.free()
func inspect(model:Node)->void:
	var meshes=Paint.meshes(model)
	check(meshes.size()==2,"two meshes: support and cloth")
	var cloths=meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_wind"))
	check(cloths.size()==1,"one cloth wind receiver")
	for cloth in cloths:
		check(Wind.mesh_error(cloth).is_empty(),"wind compatibility")
		var m=Wind.base_material(cloth,0)
		check(m.albedo_texture!=null and m.normal_texture!=null and m.roughness_texture!=null,"woven PBR preserved")
		check(cloth.get_meta("extras",{}).get("rmmo_collision","")=="none","cloth nonblocking")
func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(ART+"/manifest.json"))
	var source=ART+"/soviet_swallowtail_tall.glb"
	check(FileAccess.get_sha256(source)==manifest.sha256,"optimized source hash")
	var directory=Paths.cache_directory("soviet_banner_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets");var imported=local.import_file(source)
	check(imported.ok,"native import");if not imported.ok:quit(1);return
	var model=Library.instantiate_preview(imported.entry.asset_path);inspect(model);model.free()
	if failed:quit(1);return
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=local;editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="save_prefab"),"3D tool discovery")
	await call_tool("list_resource_packs")
	await call_tool("place_asset",{"asset_id":Thumb.key_for(imported.entry),"position":[0,0,0]})
	var id=doc.records.back().uuid
	await call_tool("select_objects",{"ids":[id]})
	var lib=Library.new(BASE+"/packs/default/assets")
	var existing=lib.entries.filter(func(e):return e.get("label","")==LABEL and e.has("prefab_path"))
	check(existing.size()<=1,"no duplicate label");if failed:quit(1);return
	var saved:Dictionary
	if existing.is_empty():saved=await call_tool("save_prefab",{"name":LABEL,"pack_root":BASE+"/packs/default"})
	else:saved={"entry":existing[0],"asset_id":Thumb.key_for(existing[0])}
	if not saved.has("entry"):quit(1);return
	check(DirAccess.copy_absolute(ART+"/preview.png",saved.entry.thumbnail_path)==OK,"thumbnail")
	lib=Library.new(BASE+"/packs/default/assets")
	var payload=JSON.parse_string(FileAccess.get_file_as_string(saved.entry.prefab_path))
	var dependency=lib.directory.path_join(payload.records[0].asset_path).simplify_path()
	check(FileAccess.get_sha256(dependency)==dependency.get_file().get_basename(),"content addressed dependency hash")
	# Native import reserializes GLB; verify the normalized source, not Blender bytes.
	compare_native(imported.entry.asset_path,dependency)
	lib.entries=lib.entries.filter(func(e):return str(e.get("asset_path","")).simplify_path()!=dependency)
	check(lib.save()==OK,"single prefab catalog slot")
	editor._shared_assets=[Library.new(lib.directory)]
	var listing=await call_tool("list_assets",{"query":LABEL});check(listing.total==1,"discoverable once")
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[3,0,0]})
	var count=doc.records.size();await call_tool("undo");check(doc.records.size()==count-1,"undo placement");await call_tool("redo");check(doc.records.size()==count,"redo placement")
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"missing_banner","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement has no side effects")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==2 and doc.missing_assets().is_empty(),"save and reopen")
	for record in doc.records:
		model=doc._asset(record);inspect(model);model.free()
	editor.queue_free();await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"game async load")
	if loaded[0]!=null:loaded[0].free()
	if is_instance_valid(loader):loader.queue_free()
	FileAccess.open(ART+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"label":LABEL,"entry":saved.entry,"source_sha256":manifest.sha256,"real_http":true,"user_maps_modified":false,"test_map":path},"\t"))
	print("SOVIET_BANNER_PUBLICATION_FAILURES ",failed);quit(1 if failed else 0)
