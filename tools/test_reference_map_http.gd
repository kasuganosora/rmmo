extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const MODEL_NAME="方窗石砌窗套"
const MODEL_PATH="D:/code/rmmo_runtime/packs/default/assets/f1259543701ac5bf03968f2b2d24913c3a3b722dbea543fe43bd2c823311ea8f.glb"
const LIBRARY_PATH="D:/code/rmmo_runtime/packs/default/assets/library.json"
var report:Dictionary={"runs":[]}
var output_path:String
var map_path:String
var directory:String

func persist()->void:
	report.failures=failed
	if output_path.is_empty():return
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()

func attach_editor(doc:RefCounted)->void:
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc;session.world3d_editor_path=map_path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual 3D HTTP MCP started")
	var discovery:=await rpc("tools/list")
	check(Pose.same(discovery.get("result",{}).get("tools",[]),preload("res://scripts/world_editor/mcp_schema.gd").tools()),"real HTTP tools/list matches current 3D schema")

func save_phase(label:String,zero_resources:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	var pending:=await call_tool("save_world",{"background":true})
	check(pending.get("pending",false),label+" starts background save through HTTP")
	var next_print:=Time.get_ticks_msec()+15000
	while editor._save_job.active:
		if Time.get_ticks_msec()>next_print:
			print("REFERENCE_SAVE_PROGRESS ",label," ",JSON.stringify(editor._save_job.state()));next_print+=15000
		await process_frame
	var result:Dictionary=editor._save_job.result.duplicate(true)
	var metrics:Dictionary=result.get("timings",{}).get("export",{})
	check(result.get("saved",false) and metrics.get("mode")=="reference_map",label+" saves reference map")
	check(metrics.get("images_written",-1)==0 and metrics.get("texture_export_passes",-1)==0,label+" never exports textures")
	if zero_resources:
		check(metrics.get("resources_written",-1)==0,label+" reuses every geometry resource")
		check(metrics.get("compression_count",-1)==0,label+" does not recompress unchanged definitions")
	var input:=FileAccess.open(map_path,FileAccess.READ)
	var sample:={"phase":label,"endpoint_ms":(Time.get_ticks_usec()-started)/1000.,"result":result,
		"map_bytes":input.get_length() if input!=null else 0,"records":editor._doc.records.size(),"sha256":FileAccess.get_sha256(map_path)}
	report.runs.append(sample);persist();print("REFERENCE_SAVE_METRICS ",JSON.stringify(sample))
	return metrics

func model_asset_id()->String:
	var listed:=await call_tool("list_assets",{"query":MODEL_NAME,"limit":200})
	var rows:Array=listed.get("assets",[]).filter(func(row):return row.get("name")==MODEL_NAME)
	var entries:Array=editor.asset_items(MODEL_NAME).filter(func(row):return row.get("asset_path")==MODEL_PATH)
	check(rows.size()==1 and entries.size()==1,"real stone window GLB found in current library")
	return str(rows[0].asset_id) if rows.size()==1 and entries.size()==1 else ""

func material_evidence(holder:Node)->Dictionary:
	var value:={"meshes":0,"surfaces":0,"materials":0,"textures":0,"vertices":0,"valid":holder!=null}
	if holder==null:return value
	for visual:MeshInstance3D in Paint.meshes(holder):
		value.meshes+=1
		if visual.mesh==null:value.valid=false;continue
		for slot in visual.mesh.get_surface_count():
			value.surfaces+=1;value.vertices+=visual.mesh.surface_get_array_len(slot)
			var material:BaseMaterial3D=visual.get_active_material(slot) as BaseMaterial3D
			if material==null:value.valid=false;continue
			value.materials+=1
			for texture_slot in BaseMaterial3D.TEXTURE_MAX:
				var texture:Texture2D=material.get_texture(texture_slot)
				if texture==null:continue
				value.textures+=1
				var pixels:Image=texture.get_image()
				if pixels==null or pixels.is_empty():value.valid=false
	value.valid=value.valid and value.meshes>0 and value.materials>0 and value.textures>0 and value.vertices>24
	return value

func external_proxies(expected_records:int)->void:
	var native:=Io.load_scene(map_path)
	check(native!=null,"ordinary external glTF importer sees valid proxy scene")
	if native==null:return
	var visuals:Array=Paint.meshes(native)
	check(visuals.size()==expected_records and visuals.all(func(v):return v.mesh.get_surface_count()==1 and v.mesh.surface_get_array_len(0)==24),"external importer sees only one cube per author UUID")
	native.free()

func game_check(expected_records:Array,expected_meta:Dictionary,model_id:String)->Dictionary:
	var started:=Time.get_ticks_usec()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader)
	loader.start(map_path)
	var loaded:Array=await loader.finished
	var evidence:Dictionary={"elapsed_ms":(Time.get_ticks_usec()-started)/1000.,"error":str(loaded[2])}
	check(loaded[0]!=null and str(loaded[2]).is_empty(),"game MapLoader resolves reference map")
	if loaded[0]==null:return evidence
	var scene:Node3D=loaded[0]
	evidence.load_profile=scene.get_meta("load_profile",{}).duplicate(true)
	var host:=Node3D.new();root.add_child(host);host.add_child(scene)
	var extras:Dictionary=Io.extras_of(scene)
	check(Pose.same(extras.get("rmmo_records"),expected_records),"game loader restores every exact author record")
	for key in expected_meta:check(Pose.same(extras.get(key),expected_meta[key]),"game metadata retains "+str(key))
	var holder:Node3D=Io.find_named(scene,model_id)
	evidence.model=material_evidence(holder)
	check(evidence.model.valid,"game has actual stone-window geometry materials and readable textures")
	var position:Vector3=holder.global_position if holder!=null else Vector3.ZERO
	Stream.sync(scene,host,position)
	var library:Array=scene.get_meta("stream_library",[])
	evidence.stream_specs=library.size();evidence.collision_bodies=scene.get_meta("stream_bodies",{}).size()
	check(library.size()>=expected_records.size(),"runtime stream library contains true source geometry")
	check(library.any(func(spec):return spec.get("mesh")!=null and spec.mesh.get_surface_count()>0),"stream meshes are available to real rendering")
	check(evidence.collision_bodies>0,"runtime creates real collision bodies near new model")
	evidence.model_stream_ids=[]
	for spec:Dictionary in library:
		if str(spec.uuid)==model_id or str(spec.uuid).begins_with(model_id+"__"):evidence.model_stream_ids.append(spec.uuid)
	check(not evidence.model_stream_ids.is_empty(),"new real model keeps independent stream identity")
	host.free();await settle()
	return evidence

func detach_editor()->void:
	editor._mcp.stop();editor.queue_free();await settle();await RenderingServer.frame_post_draw
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=null;session.world3d_editor_path=""

func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size;rpc_timeout_ms=60000
	create_timer(600).timeout.connect(func():persist();quit(2))
	directory=Paths.cache_directory("reference_http_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	map_path=directory.path_join("map.gltf");output_path=Art.review_path("reference_map_http_20261007.json")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
	if not Paths.allowed(output_path,Art.review_path("")):quit(1);return
	var model_sha:=FileAccess.get_sha256(MODEL_PATH);var library_sha:=FileAccess.get_sha256(LIBRARY_PATH)
	report={"runs":[],"map":map_path,"model_sha256":model_sha}
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.5,0),Vector3(160,1,160))
	var painted:String=doc.add_box("block",Vector3(-30,1,0),Vector3(2,2,2))
	await attach_editor(doc)
	var generated:=await call_tool("generate_buildings",{"parameters":{"floors":2},"placements":[{"position":[0,0,0]}]})
	if not generated.get("ok",false):persist();quit(1);return
	var building_id:String=generated.building_ids[0]
	var registry:Dictionary=doc.map_meta.building_instances[building_id]
	var member:String=registry.parts.values()[0]
	check(registry.get("baked",false),"building fixture automatically baked")
	var fixtures:Array=preload("res://scripts/world3d/building_fixtures.gd").rows(doc.records,building_id)
	check(not fixtures.is_empty(),"generated building retains articulated fixtures")
	if not fixtures.is_empty():await call_tool("set_building_component_state",{"id":building_id,"component_id":fixtures[0].id,"open":.4})
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color(.7,.3,.1))
	var image_path:=directory.path_join("paint.png");check(image.save_png(image_path)==OK,"create temporary paint source")
	var material:=await call_tool("import_surface_material",{"path":image_path,"name":"reference roundtrip paint"})
	var faces:=await call_tool("list_object_surfaces",{"id":painted})
	if material.get("ok",false) and not faces.get("faces",[]).is_empty():await call_tool("paint_surface",{"id":painted,"target":faces.faces[0].target,"material_id":material.material_id})
	check(doc._find(painted).has("surface_paint"),"real HTTP face paint prepared before reference baseline")
	await save_phase("baseline")
	var before:Array=doc.records.duplicate(true);var history:int=doc._undo.size();var disk:=FileAccess.get_sha256(map_path)
	await call_tool("place_asset",{"asset_id":"missing_reference_fixture","position":[0,0,0]},false)
	await call_tool("set_object_transform",{"id":painted,"size":[0,1,1]},false)
	await call_tool("save_world",{"incremental":true},false)
	check(Pose.same(before,doc.records) and history==doc._undo.size() and FileAccess.get_sha256(map_path)==disk,"invalid HTTP operations leave document history and disk unchanged")
	await call_tool("select_objects",{"ids":[member]})
	await call_tool("transform_selection",{"translation":[10,2,6]})
	check(Geometry.vector(doc.map_meta.building_instances[building_id],"position").is_equal_approx(Vector3(10,2,6)),"whole baked building moves on all XYZ axes")
	await save_phase("building_xyz_move",true)
	await call_tool("undo");await save_phase("undo_building_move",true)
	await call_tool("redo");await save_phase("redo_building_move",true)
	var building_members:Array=doc.map_meta.building_instances[building_id].parts.values()
	await call_tool("set_object_properties",{"ids":building_members,"hidden":true,"locked":true})
	check(building_members.all(func(id):return doc._find(id).get("editor_hidden",false) and doc._find(id).get("editor_locked",false)),"every baked building member is hidden and locked")
	await save_phase("building_hidden_locked",true)
	await call_tool("set_object_properties",{"ids":building_members,"hidden":false,"locked":false})
	await save_phase("building_visible_unlocked",true)
	await call_tool("set_floor_view",{"isolation":true,"base_height":2,"floor_height":3,"outside":"hide"})
	await save_phase("floor_view",true)
	await call_tool("set_floor_view",{"isolation":false})
	var asset_id:=await model_asset_id()
	if asset_id.is_empty():persist();quit(1);return
	var placed:=await call_tool("place_asset",{"asset_id":asset_id,"position":[35,0,10]})
	var ids:Array=placed.get("ids",[])
	if ids.size()!=1:check(false,"one real model created");persist();quit(1);return
	var model_id:String=ids[0]
	report.live_model=material_evidence(editor._view.get_node_or_null(NodePath(model_id)))
	check(report.live_model.valid,"editor displays real textured stone-window GLB")
	await save_phase("add_real_model")
	await call_tool("undo");check(doc._find(model_id).is_empty(),"undo removes model");await save_phase("undo_real_model",true)
	await call_tool("redo");check(not doc._find(model_id).is_empty(),"redo restores model UUID");await save_phase("redo_real_model",true)
	await call_tool("select_objects",{"ids":[model_id]});await call_tool("delete_selection")
	await save_phase("delete_real_model",true)
	await call_tool("undo");await save_phase("restore_deleted_model",true)
	for stage:String in ["resources_ready","before_publish"]:
		disk=FileAccess.get_sha256(map_path)
		Io.save_fault=func(point:String)->bool:return point==stage
		await call_tool("save_world",{},false);Io.save_fault=Callable()
		check(FileAccess.get_sha256(map_path)==disk and not editor.saving(),"failed HTTP save preserves map at "+stage)
		await save_phase("retry_"+stage,true)
	var external_bytes:=FileAccess.get_file_as_bytes(map_path);external_bytes.append(32)
	Io.save_fault=func(point:String)->bool:
		if point=="before_publish":
			var external:=FileAccess.open(map_path,FileAccess.WRITE);external.store_buffer(external_bytes);external.close()
		return false
	await call_tool("save_world",{},false);Io.save_fault=Callable()
	check(FileAccess.get_file_as_bytes(map_path)==external_bytes and not editor.saving(),"late external writer survives conflicting HTTP save")
	await call_tool("open_world",{"path":map_path,"discard_changes":true});doc=editor._doc
	await save_phase("retry_after_external_conflict",true)
	var expected:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
	await call_tool("open_world",{"path":map_path})
	check(Pose.same(editor._doc.records,expected) and Pose.same(editor._doc.map_meta,meta),"HTTP reopen restores fixtures floors paint pose and editor state")
	check(editor._doc._find(painted).has("surface_paint"),"surface paint survives reference reopen")
	external_proxies(expected.size())
	await detach_editor()
	report.game=await game_check(expected,meta,model_id)
	check(FileAccess.get_sha256(MODEL_PATH)==model_sha and FileAccess.get_sha256(LIBRARY_PATH)==library_sha,"real model and catalog unchanged")
	persist();print("REFERENCE_HTTP_FINISHED failures=",failed," report=",output_path)
	quit(0 if failed==0 else 1)
