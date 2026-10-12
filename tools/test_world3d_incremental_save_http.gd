extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
var fixture_directory:String
var map_path:String
var model_a:String
var model_b:String
var entry_a:Dictionary
var entry_b:Dictionary

func make_source(path:String,color:Color)->void:
	var model:=Node3D.new();model.name="TexturedModel"
	var nested:=Node3D.new();nested.name="Nested";nested.position=Vector3(.2,0,.1);model.add_child(nested)
	var pixels:=Image.create(8,8,false,Image.FORMAT_RGBA8);pixels.fill(color)
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(pixels);material.roughness=.7
	for index in 2:
		var part:=MeshInstance3D.new();part.name="Part%d"%index;part.position=Vector3(index*1.5,0,0)
		var mesh:=BoxMesh.new();mesh.size=Vector3(.8,1,1);mesh.material=material;part.mesh=mesh;nested.add_child(part)
	check(Io.save_scene(model,path)==OK,"create nested textured source "+path.get_extension())
	model.free()

func resources()->Dictionary:
	var value:=Pose.dependencies(Pose._json(map_path),map_path,Paths.external_root(),Io)
	check(value.ok,"published resource closure is readable")
	return value.get("files",{})

func retained(before:Dictionary,label:String)->void:
	var after:=resources();var intact:=true
	for uri:String in before:
		if after.get(uri)!=before[uri]:intact=false
	check(intact,label+" preserves original resource URIs and bytes")

func metrics(result:Dictionary)->Dictionary:return result.get("timings",{}).get("export",{})

func save_checked(mode:String,label:String,zero_images:bool=true)->Dictionary:
	var result:=await call_tool("save_world")
	var value:=metrics(result)
	check(result.get("saved",false) and value.get("mode")==mode,label+" uses "+mode)
	if zero_images:check(value.get("images_written",-1)==0 and value.get("texture_export_passes",-1)==0,label+" exports no textures")
	print("INCREMENTAL_HTTP_METRICS ",label," ",JSON.stringify(value))
	if value.get("mode")!=mode:print("INCREMENTAL_HTTP_FALLBACK ",label," ",JSON.stringify(result.get("timings",{})))
	return value

func native_matches(label:String)->void:
	var scene:=Io.load_scene(map_path)
	check(scene!=null,label+" native glTF loads")
	if scene==null:return
	var raw:=Pose._json(map_path);var root_index:=Pose._root(raw)
	check(root_index>=0 and raw.nodes[root_index].get("children",[]).size()==editor._doc.records.size(),label+" has exactly the live instance roots")
	var author:Dictionary=Io.extras_of(scene)
	check(Pose.same(author.get("rmmo_records"),editor._doc.records),label+" authoring records agree")
	for record:Dictionary in editor._doc.records:
		var node:Node3D=Io.find_named(scene,str(record.uuid))
		var pose_matches:bool=node!=null and node.transform.is_equal_approx(Pose.pose(record))
		check(pose_matches,label+" native pose "+str(record.uuid))
		if not pose_matches:
			print("INCREMENTAL_NATIVE_FAILURE ",label," uuid=",record.uuid," found=",node!=null," scene_names=",scene.find_children("*","Node3D",true,false).map(func(item):return str(item.name)))
			var evidence:=FileAccess.open(fixture_directory.path_join("native_failure.gltf"),FileAccess.WRITE)
			evidence.store_buffer(FileAccess.get_file_as_bytes(map_path));evidence.close()
		if record.get("kind")=="asset" and node!=null:
			check(preload("res://scripts/world3d/surface_materials.gd").meshes(node).size()==2,label+" nested model keeps both meshes")
	scene.free()

func asset_id_for(label:String)->String:
	var result:=await call_tool("list_assets",{"query":label})
	var rows:Array=result.get("assets",[])
	check(rows.size()==1,"temporary model discoverable: "+label)
	return str(rows[0].asset_id) if not rows.is_empty() else ""

func duplicate(id:String)->String:
	await call_tool("select_objects",{"ids":[id]})
	await call_tool("duplicate_selection")
	return str(editor._selection_tools.ids[0]) if not editor._selection_tools.ids.is_empty() else ""

func remove(id:String)->void:
	await call_tool("select_objects",{"ids":[id]})
	await call_tool("delete_selection")

func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=20000
	fixture_directory=Paths.cache_directory("incremental_http_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture_directory)
	map_path=fixture_directory.path_join("map.gltf")
	model_a=fixture_directory.path_join("source_a/model.gltf");model_b=fixture_directory.path_join("source_b/model.glb")
	make_source(model_a,Color.RED);make_source(model_b,Color.GREEN)
	entry_a={"label":"IncrementalFixtureA","category":"fixture","asset_path":model_a,"bounds_position":[-.4,-.5,-.5]}
	entry_b={"label":"IncrementalFixtureB","category":"fixture","asset_path":model_b,"bounds_position":[-.4,-.5,-.5]}
	var doc:=Doc.new();var original:String=doc.add_asset(entry_a,Vector3(0,2,0))
	doc.add_box("block",Vector3(10,2,0),Vector3(2,2,2))
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=map_path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	# Registration belongs to the temporary fixture; all edits/save/reopen below
	# use real HTTP tools and the same model entries as this initial document.
	editor._assets.entries=[entry_a,entry_b];editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start actual HTTP 3D MCP")
	var discovered:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	check(Pose.same(discovered,preload("res://scripts/world_editor/mcp_schema.gd").tools()),"HTTP discovery matches unchanged current tool schemas")
	var first:=await save_checked("full_export","first HTTP baseline",false)
	check(first.get("images_written",0)>0,"baseline exports a real texture")
	var initial:=resources();native_matches("baseline")
	var previous:Array=editor._doc.records.duplicate(true);var history:int=editor._doc._undo.size();var disk:=FileAccess.get_sha256(map_path)
	await call_tool("place_asset",{"asset_id":"absent_fixture","position":[0,0,0]},false)
	await call_tool("save_world",{"incremental":true},false)
	await call_tool("set_object_transform",{"id":original,"size":[0,1,1]},false)
	check(Pose.same(previous,editor._doc.records) and history==editor._doc._undo.size() and FileAccess.get_sha256(map_path)==disk,"invalid HTTP calls have no document/history/disk side effects")
	var clone:=await duplicate(original)
	var cloned:=await save_checked("incremental_reuse","add existing nested model")
	check(cloned.get("cloned_instances")==1 and cloned.get("exported_instances")==0,"existing source clones instance nodes without exporter")
	retained(initial,"clone");native_matches("clone")
	var b_id:=await asset_id_for("IncrementalFixtureB")
	var placed:=await call_tool("place_asset",{"asset_id":b_id,"position":[20,0,0]})
	var second:String=placed.get("ids",[""])[0]
	var added:=await save_checked("incremental_reuse","add distinct GLB source",false)
	check(added.get("added_instances")==1 and added.get("exported_instances")==1 and added.get("images_written",0)>0,"new source exports precisely one newly added instance")
	check(added.get("partial_export",{}).get("meshes")==2,"partial export contains only the new nested model's two meshes")
	retained(initial,"new source");native_matches("new source")
	var with_b:=resources()
	await remove(second)
	var removed:=await save_checked("incremental_reuse","delete last source reference")
	check(removed.get("removed_instances")==1 and removed.get("exported_instances")==0,"deletion changes membership without exporter")
	retained(with_b,"deletion");native_matches("deletion")
	var count_before:int=editor._doc.records.size()
	await remove(clone)
	placed=await call_tool("place_asset",{"asset_id":b_id,"position":[25,0,0]})
	check(editor._doc.records.size()==count_before,"mixed edit keeps same record count but changes UUIDs")
	var mixed:=await save_checked("incremental_reuse","same-count add/delete",false)
	check(mixed.get("added_instances")==1 and mixed.get("removed_instances")==1,"same-count reconciliation reports both membership changes")
	retained(initial,"mixed edit");native_matches("mixed edit")
	var expected:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");await save_checked("incremental_reuse","undo added instance")
	await call_tool("redo");await save_checked("incremental_reuse","redo added instance",false)
	await call_tool("open_world",{"path":map_path})
	check(Pose.same(editor._doc.records,expected),"HTTP reopen retains mixed edit after undo/redo saves")
	await call_tool("set_object_transform",{"id":original,"position":[1,3,0]})
	await save_checked("pose_reuse","ordinary pose after incremental saves")
	retained(initial,"pose after incremental");native_matches("pose after incremental")
	for stage:String in ["resources_ready","before_publish"]:
		await duplicate(original)
		disk=FileAccess.get_sha256(map_path)
		Io.save_fault=func(at):return at==stage
		await call_tool("save_world",{},false)
		Io.save_fault=Callable()
		check(editor._dirty and not editor.saving() and FileAccess.get_sha256(map_path)==disk,"failed incremental publication preserves dirty map and unlocks at "+stage)
		await save_checked("incremental_reuse","retry after "+stage)
	var external_bytes:=FileAccess.get_file_as_bytes(map_path);external_bytes.append(10)
	await duplicate(original)
	Io.save_fault=func(stage):
		if stage=="before_publish":
			var external:=FileAccess.open(map_path,FileAccess.WRITE);external.store_buffer(external_bytes);external.close()
		return false
	await call_tool("save_world",{},false);Io.save_fault=Callable()
	check(editor._dirty and not editor.saving() and FileAccess.get_file_as_bytes(map_path)==external_bytes,"late external writer remains untouched by stale HTTP save")
	await call_tool("open_world",{"path":map_path,"discard_changes":true})
	# Modify real source image bytes. A cached red material must never be bound
	# to a fresh blue source hash, regardless of the fallback strategy used.
	var source_raw:=Pose._json(model_a)
	var uri:String=source_raw.images[0].uri
	var image_path:=model_a.get_base_dir().path_join(Io.decode_dependency_uri(uri))
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.BLUE);check(image.save_png(image_path)==OK,"change source texture to blue")
	var changed:=await call_tool("save_world")
	check(changed.get("saved",false),"source content update saves through validated rebuild")
	var native:=Io.load_scene(map_path);var holder:Node3D=Io.find_named(native,original) if native!=null else null
	var blue:=holder!=null
	if holder!=null:
		for mesh:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(holder):
			var material:BaseMaterial3D=mesh.get_active_material(0)
			blue=blue and material!=null and material.albedo_texture!=null and material.albedo_texture.get_image().get_pixel(0,0).b>.9 and material.albedo_texture.get_image().get_pixel(0,0).r<.1
	check(blue,"native reload uses changed source pixels rather than cached red")
	if native!=null:native.free()
	native_matches("changed source")
	editor._mcp.stop();editor.queue_free();await settle()
	if failed==0:Io._remove_tree(fixture_directory)
	else:print("INCREMENTAL_HTTP_FAILED_FIXTURE ",fixture_directory)
	print("INCREMENTAL_HTTP_FINISHED failures=",failed)
	quit(0 if failed==0 else 1)
