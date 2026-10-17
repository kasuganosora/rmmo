extends "res://tools/test_world3d_mcp.gd"
const Net=preload("res://scripts/net/net.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Vegetation=preload("res://scripts/world3d/vegetation_render.gd")
const Ground=preload("res://scripts/world3d/ground_batch_geometry.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018/"
var folder:String
var evidence:Dictionary={"checks":[],"views":[]}
func check(ok:bool,label_:String)->void:
	super.check(ok,label_);evidence.checks.append({"ok":ok,"label":label_})
func export_fixture(path:String)->void:
	var image:=Image.create(128,128,false,Image.FORMAT_RGBA8);image.fill(Color(0,0,0,0))
	for y in 128:
		for x in 128:
			var u:float=(x/127.-.5)*2.;var v:float=y/127.
			var opacity:float=clampf((pow(maxf(0.,sin(v*PI)),.7)*.65-absf(u))*90.,0.,1.)
			image.set_pixel(x,y,Color(.22+v*.13,.36+v*.14,.08+v*.05,opacity))
	image.generate_mipmaps()
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image);material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.alpha_scissor_threshold=.5;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=.95
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var angle:float=i*PI/6.;var axis:=Vector3(cos(angle),0,sin(angle))*.45;var base:=Vector3(sin(i*2.3),0,cos(i*2.3))*.25
		var corners:Array[Vector3]=[base-axis,base+axis,base+axis+Vector3.UP*(.9+i*.025),base-axis+Vector3.UP*(.9+i*.025)]
		for index:int in [0,1,2,0,2,3]:st.set_normal(Vector3.UP);st.set_uv([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][index]);st.add_vertex(corners[index])
	st.index();var mesh:=st.commit();mesh.surface_set_material(0,material)
	var holder:=Node3D.new();var visual:=MeshInstance3D.new();visual.mesh=mesh;holder.add_child(visual)
	var gltf:=GLTFDocument.new();var state:=GLTFState.new()
	check(gltf.append_from_scene(holder,state)==OK and gltf.write_to_filesystem(state,path)==OK,"export self-contained alpha-cutout contract fixture outside project")
	holder.free()
	# The generic exporter advertises a Godot-only root hint. The production
	# conservative static directory deliberately rejects that extension. Keep
	# its original export and emit the same closed standard glTF graph/buffer.
	var original:=FileAccess.get_file_as_bytes(path);var json_size:int=original.decode_u32(12)
	var data:Dictionary=JSON.parse_string(original.slice(20,20+json_size).get_string_from_utf8())
	data.extensionsUsed.erase("GODOT_single_root")
	if data.extensionsUsed.is_empty():data.erase("extensionsUsed")
	var binary:PackedByteArray=original.slice(28+json_size)
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	DirAccess.copy_absolute(path,path+".godot_export.glb")
	var output:=FileAccess.open(path,FileAccess.WRITE);output.store_32(0x46546c67);output.store_32(2);output.store_32(28+bytes.size()+binary.size());output.store_32(bytes.size());output.store_32(0x4e4f534a);output.store_buffer(bytes);output.store_32(binary.size());output.store_32(0x004e4942);output.store_buffer(binary);output.close()
func capture(view:SubViewport,label_:String)->Dictionary:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image();image.save_png(folder.path_join(label_+".png"))
	return {"image":image,"draw_calls":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
func run()->void:
	create_timer(210).timeout.connect(func():print("STATIC_CUTOUT_TIMEOUT");quit(2))
	check(Ground.static_scatter_instances_enabled,"guarded cutout rollout is enabled after candidate verification")
	Ground.static_scatter_instances_enabled=true
	folder=OUT.path_join("cutout_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":folder.get_file(),"name":"Isolated cutout contract"}))
	var path:=folder.path_join("cutout.glb");export_fixture(path)
	var library:=Library.new(folder.path_join("assets"));var imported:Dictionary=library.import_file(path)
	check(imported.ok,"actual library import creates checked immutable native product")
	if not imported.ok:quit(1);return
	check(imported.get("compiled_asset",{}).get("ok",false),"actual imported final bytes compile into a closed native product")
	if not imported.get("compiled_asset",{}).get("ok",false):print(imported.get("compiled_asset",{}));quit(1);return
	var doc:=Doc.new();doc.add_box("ground",Vector3(16,-.1,16),Vector3(32,.2,32));var map_path:=folder.path_join("maps/map.gltf");DirAccess.make_dir_recursive_absolute(map_path.get_base_dir());check(doc.save(map_path)==OK,"save isolated native scatter map")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=folder.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=library;editor._asset_pack_root=folder
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"isolated loopback current 3D MCP starts")
	var discovery:=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="generate_vegetation_scatter") and not discovery.result.tools.any(func(t):return t.name=="paint_tile"),"discover current scatter tools with retired 2D adapter absent")
	var args:={"id":"static_cutout","asset_ids":[imported.entry.asset_path],"polygon":[[2,2],[30,2],[30,30],[2,30]],"pattern":"random","count":64,"seed":717,"spacing":2.,"collision":false}
	var preview:=await call_tool("preview_vegetation_scatter",args)
	var before:Dictionary=doc.recovery_snapshot();var history:int=doc._undo.size()
	await call_tool("generate_vegetation_scatter",args.merged({"plan_token":"stale"}),false)
	check(equivalent(before,doc.recovery_snapshot()) and history==doc._undo.size(),"invalid generation keeps records and undo history unchanged")
	var result:=await call_tool("generate_vegetation_scatter",args.merged({"plan_token":preview.plan_token}))
	check(result.count==64 and doc.records.filter(func(r):return r.kind=="asset").all(func(r):return r.vegetation_batch),"ordinary random scatter opts eligible static sources into shared render path")
	var after:Dictionary=doc.recovery_snapshot();await call_tool("undo");check(equivalent(before,doc.recovery_snapshot()),"scatter undo restores exact previous document")
	await call_tool("redo");check(equivalent(after,doc.recovery_snapshot()),"redo restores every independent UUID and transform")
	var panel:VBoxContainer=editor._city.panel.scatter_panel;panel.refresh();panel.choice.select(1);panel.load_region()
	panel.fields.fields.seed.value=718;panel.show_preview();history=doc._undo.size();panel.apply()
	check(doc._undo.size()==history+1 and doc.records.filter(func(r):return r.kind=="asset").all(func(r):return r.vegetation_batch),"UI regeneration shares the same single transaction and automatic optimization")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path});doc=editor._doc
	check(doc.records.filter(func(r):return r.kind=="asset").all(func(r):return r.vegetation_batch),"save/reopen retains source identities and derived rendering eligibility")
	var state:=await call_tool("editor_state")
	check(state.has("vegetation_batching") and state.vegetation_batching.message==editor.vegetation_render_status().message,"HTTP and UI use the same vegetation status operation")
	panel.optimization_info.text=editor.vegetation_render_status().message
	check(panel.optimization_info.text==state.vegetation_batching.message,"scatter UI displays shared conservative render policy")
	var sha:=FileAccess.get_sha256(map_path)
	var view:=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.08,.1,.16);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;view.add_child(sun)
	var camera:=Camera3D.new();camera.current=true;camera.far=600;view.add_child(camera)
	var map:Node3D=doc.build();view.add_child(map);var sources:Array=map.get_children();var source_bytes:Array=[]
	for node:Node in sources:
		if node is MeshInstance3D:source_bytes.append(var_to_bytes(Cpu.capture(node.mesh).surfaces))
	var batch:=Batch.new();map.add_child(batch);batch.set_process(false)
	for v:Dictionary in [{"name":"near","eye":Vector3(16,7,38),"target":Vector3(16,0,16),"fov":60.},{"name":"detail","eye":Vector3(11,1.2,14),"target":Vector3(14,.5,16),"fov":58.},{"name":"mid","eye":Vector3(16,25,75),"target":Vector3(16,0,16),"fov":40.},{"name":"far","eye":Vector3(16,70,210),"target":Vector3(16,0,16),"fov":18.}]:
		camera.position=v.eye;camera.fov=v.fov;camera.look_at(v.target);batch.clear()
		var a:Dictionary=await capture(view,v.name+"_baseline");batch.sync(sources);batch.flush();batch.update_cutout_visibility();var b:Dictionary=await capture(view,v.name+"_candidate")
		var left:PackedByteArray=a.image.get_data();var right:PackedByteArray=b.image.get_data();var changed:=0;var maximum:=0
		for i in left.size():
			if left[i]!=right[i]:changed+=1;maximum=maxi(maximum,absi(left[i]-right[i]))
		evidence.views.append({"name":v.name,"baseline_calls":a.draw_calls,"candidate_calls":b.draw_calls,"changed_channels":changed,"max_difference":maximum,"baseline_primitives":a.primitives,"candidate_primitives":b.primitives})
		check(b.draw_calls<=a.draw_calls and b.primitives<=a.primitives,"guarded candidate retains fine culling without extra draw or triangles: "+v.name)
		if v.name=="detail":check(batch.stats().active_cutout_groups==0,"detail camera uses original independently culled source instances")
		if v.name=="far":check(batch.stats().active_cutout_groups==0,"small stand retains original automatic instancing below the measured dense threshold")
		check(maximum<=2 and float(changed)/left.size()<.001,"leaf alpha edges and shadows preserve image within output quantization: "+v.name)
	var all_exact:=true;var at:=0
	for node:Node in sources:
		if node is MeshInstance3D:all_exact=all_exact and source_bytes[at]==var_to_bytes(Cpu.capture(node.mesh).surfaces);at+=1
	check(all_exact and FileAccess.get_sha256(map_path)==sha,"batch source geometry and persisted author data stay byte exact")
	var cutout:MeshInstance3D=sources.filter(func(n):return n.has_meta("asset_uuid"))[0]
	var record:Dictionary=cutout.get_meta("ground_batch_record").duplicate(true)
	batch.clear();cutout.set_meta("extras",{"rmmo_wind":{"profile":"foliage"}});batch.sync(sources);batch.flush()
	check(not batch._member_groups.has(str(cutout.name)),"authored wind metadata remains independently rendered even without a record override")
	var holder:=Node3D.new();var wind_mesh:=MeshInstance3D.new();wind_mesh.mesh=BoxMesh.new();wind_mesh.set_meta("extras",{"rmmo_wind":{"profile":"foliage"}});holder.add_child(wind_mesh)
	check(Vegetation.flatten(holder,record)==holder,"flattening cannot strip authored wind receiver hierarchy");holder.free()
	evidence.asset={"source":path,"source_sha256":FileAccess.get_sha256(path),"import":imported.entry,"map_sha256":sha};evidence.failures=failed;evidence.media=folder
	evidence.rollout={"candidate_verified":true,"policy":"distant_interior_no_native_lod"}
	FileAccess.open(OUT+"cutout_guarded_http.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	view.free();editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("STATIC_CUTOUT_HTTP failures=",failed," media=",folder);quit(1 if failed else 0)
