extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Trees=preload("res://scripts/world3d/parametric_tree.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const BASE="D:/code/rmmo_runtime"
var out=BASE+"/review_artifacts/pine_parametric"
var timings:Dictionary={}
func call_tool(name_:String,args:Dictionary={},expected_ok:bool=true)->Dictionary:
	var started=Time.get_ticks_msec();var result=await super.call_tool(name_,args,expected_ok)
	timings[name_]=maxi(int(timings.get(name_,0)),Time.get_ticks_msec()-started);return result
func check(ok:bool,label:String)->void:
	super.check(ok,label)
	var f=FileAccess.open(out+"/progress.log",FileAccess.READ_WRITE) if FileAccess.file_exists(out+"/progress.log") else FileAccess.open(out+"/progress.log",FileAccess.WRITE)
	if f!=null:f.seek_end();f.store_line(("PASS " if ok else "FAIL ")+label);f.close()
func fingerprint(model:Node)->String:
	var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	for m in Paint.meshes(model):
		for s in m.mesh.get_surface_count():hash_.update(var_to_bytes(m.mesh.surface_get_arrays(s)))
	return hash_.finish().hex_encode()
func triangle_count(model:Node)->int:
	var count=0
	for m in Paint.meshes(model):
		for s in m.mesh.get_surface_count():count+=m.mesh.surface_get_array_index_len(s)/3
	return count
func run()->void:
	DirAccess.make_dir_recursive_absolute(out);create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory=Paths.external_root().path_join("__parametric_pine_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var metadata=FileAccess.open(directory+"/metadata.json",FileAccess.WRITE);metadata.store_string(JSON.stringify({"id":"parametric_pine_test","name":"参数化松树临时测试包"}));metadata.close()
	var lib=Library.new(directory+"/assets")
	var rows=[]
	for variant in ["compact","mature","windswept"]:
		var result=lib.import_file(BASE+"/assets/pine_parametric/"+variant+".glb");check(result.ok,"import "+variant)
		if not result.ok:quit(1);return
		var model=Library.instantiate(result.entry.asset_path);var source=Trees.recipe(model);check(source.get("anchors",[]).size()==583,"583 tagged branches")
		var settings=Trees.defaults(source);var before=triangle_count(model)
		check(Trees.apply(model,{"kind":"asset","tree_settings":settings}).is_empty(),"default generation")
		check(triangle_count(model)==before,"default triangle budget preserved")
		model.free();rows.append({"variant":variant,"entry":result.entry})
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temp map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false;editor._assets=lib;editor._shared_assets=[]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP server")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="set_tree_parameters") and discovery.result.tools.any(func(t):return t.name=="get_tree_parameters"),"3D tools discovered")
	var asset_id=preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(rows[1].entry)
	await call_tool("place_asset",{"asset_id":asset_id,"position":[0,0,0]});var id=doc.records.back().uuid
	var described=await call_tool("get_tree_parameters",{"id":id});check(described.supported,"parameter capability")
	var baseline=doc._asset(doc._find(id));var original=fingerprint(baseline);var original_count=triangle_count(baseline);baseline.free()
	var before=doc.recovery_snapshot()
	for invalid in [{"height":0},{"density":4},{"seed":1.5},{"bare_trunk":8,"height":5},{"unknown":2}]:await call_tool("set_tree_parameters",{"ids":[id],"settings":invalid},false)
	check(doc.recovery_snapshot()==before,"invalid parameters atomic")
	await call_tool("set_object_properties",{"ids":[id],"locked":true});var locked=doc.recovery_snapshot();await call_tool("set_tree_parameters",{"ids":[id],"settings":{"density":.7}},false);check(doc.recovery_snapshot()==locked,"locked protected");await call_tool("undo")
	await call_tool("set_tree_parameters",{"ids":[id],"settings":{"height":8.,"bare_trunk":.7,"crown_scale":1.2,"trunk_scale":1.3,"lean":.4,"density":.75,"seed":17}})
	var changed=doc._asset(doc._find(id));var revised=fingerprint(changed);check(revised!=original and triangle_count(changed)<original_count,"seed/shape/density affect geometry")
	check(Paint.meshes(changed).filter(func(m):return m.visibility_range_end>0 or m.visibility_range_begin>0).size()==3,"three updated LODs")
	changed.free();await call_tool("undo");var restored=doc._asset(doc._find(id));check(fingerprint(restored)==original,"undo restores exact original");restored.free();await call_tool("redo")
	var replay=doc._asset(doc._find(id));check(fingerprint(replay)==revised,"redo deterministic");replay.free()
	# Exercise the actual inspector action rather than a separate UI-only implementation.
	await call_tool("select_objects",{"ids":[id]});editor._inspector.tree_panel.refresh()
	var panel=editor._inspector.tree_panel
	check(panel.visible,"tree inspector visible");panel.form.fields.density.value=1.25;panel.apply()
	var dense=doc._asset(doc._find(id));check(triangle_count(dense)>original_count,"UI density adds complete branch copies");dense.free();await call_tool("undo")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	var reopened=doc._asset(doc._find(id));check(fingerprint(reopened)==revised,"save reopen deterministic");reopened.free()
	await call_tool("select_objects",{"ids":[id]});await call_tool("list_resource_packs")
	var prefab=await call_tool("save_prefab",{"name":"测试参数化松树","pack_root":directory})
	await call_tool("place_asset",{"asset_id":prefab.asset_id,"position":[12,0,0]})
	var copy_id=doc.records.back().uuid
	check(doc._find(copy_id).tree_settings==doc._find(id).tree_settings,"prefab keeps all editable settings")
	var first_view=doc._asset(doc._find(id));var second_view=doc._asset(doc._find(copy_id))
	check(Paint.meshes(first_view)[0].mesh==Paint.meshes(second_view)[0].mesh,"identical recipes share generated meshes")
	first_view.free();second_view.free()
	await call_tool("set_object_properties",{"ids":[copy_id],"hidden":true});var snapshot=doc.recovery_snapshot()
	await call_tool("set_tree_parameters",{"ids":[id,copy_id],"settings":{"height":9.}},false);check(doc.recovery_snapshot()==snapshot,"mixed batch failure leaves first tree unchanged");await call_tool("undo")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==2 and doc.missing_assets().is_empty(),"prefab dependency save reopen")
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"runtime tree load")
	if loaded[0]!=null:
		var host=Node3D.new();root.add_child(host);host.add_child(loaded[0]);preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		var meshes:Array=loaded[0].get_meta("stream_meshes",{}).values()
		check(meshes.filter(func(m):return is_instance_valid(m) and m.get_meta("extras",{}).has("rmmo_visibility_range")).size()==6,"runtime preserves both trees' three LODs")
		check(not loaded[0].get_meta("stream_bodies",{}).is_empty(),"updated trunk collision in runtime")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	await render_examples(rows,doc._find(id))
	var f=FileAccess.open(out+"/validation.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"real_http":true,"entries":rows,"user_maps_modified":false,"test_map":path,"rpc_max_ms":timings},"\t"));f.close()
	print("PARAMETRIC_TREE_FAILURES ",failed);editor.queue_free();await settle();quit(1 if failed else 0)
func render_examples(rows:Array,record:Dictionary)->void:
	var vp=SubViewport.new();vp.size=Vector2i(1200,900);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.32,.36,.39);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.6;vp.add_child(env)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.shadow_enabled=true;vp.add_child(light)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=13;camera.position=Vector3(12,8,20);vp.add_child(camera);camera.look_at(Vector3(0,5,0))
	var doc=Doc.new()
	for label in ["approved","default","edited","dense"]:
		var copy=record.duplicate(true)
		if label in ["approved","default"]:copy.erase("tree_settings")
		if label=="dense":copy.tree_settings.density=1.5
		if label=="approved":
			var proof=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_dense_v3_game/published.json"));copy.asset_path=proof.items[1].entry.asset_path
		var model=doc._asset(copy);vp.add_child(model)
		for i in 24:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/"+label+".png");model.queue_free();await process_frame
	vp.queue_free()
