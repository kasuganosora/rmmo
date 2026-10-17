extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Importer=preload("res://scripts/world_editor/terrain_heightmap.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
var count:=0
var link_test:="not_run"
var link_source:=""
var output:="D:/code/rmmo_runtime/review_artifacts/heightmap_import_20261017"
func check(ok_:bool,label_:String)->void:count+=1;super.check(ok_,label_)
func snapshot()->String:return City.token([editor._doc.recovery_snapshot(),editor._doc._undo,editor._doc._redo,editor._dirty,editor._selection_tools.ids])
func reject(name_:String,args:Dictionary)->Dictionary:
	var before:=snapshot();var result:=await call_tool(name_,args,false);check(snapshot()==before,"atomic rejection: "+name_);return result
func run()->void:
	create_timer(420).timeout.connect(func():quit(2));rpc_timeout_ms=120000;root.size=Vector2i(1600,1000)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--link-source="):link_source=argument.trim_prefix("--link-source=")
	DirAccess.make_dir_recursive_absolute(output)
	var directory:=Paths.cache_directory("heightmap_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var raw:=PackedByteArray();raw.resize(129*129*2)
	for z in 129:
		for x in 129:
			var value:=mini(65535,(x+z)*256);var at:=(z*129+x)*2;raw[at]=value&255;raw[at+1]=(value>>8)&255
	var source:=directory.path_join("input.r16");FileAccess.open(source,FileAccess.WRITE).store_buffer(raw)
	var png:=Image.create(17,17,false,Image.FORMAT_L8)
	for z in 17:
		for x in 17:png.set_pixel(x,z,Color(float(x)/16.,float(x)/16.,float(x)/16.))
	var png_path:=directory.path_join("input.png");check(png.save_png(png_path)==OK,"native 8-bit grayscale PNG fixture")
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native empty map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32950
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private current 3D loopback server")
	var definitions:Array=(await rpc("tools/list")).result.tools
	for name_:String in ["preview_heightmap_import","apply_heightmap_import","discard_heightmap_import"]:check(definitions.any(func(t):return t.name==name_),"discovered "+name_)
	var args:Dictionary={"path":source,"format":"r16le","samples_x":129,"samples_z":129,"center":[32.,0.,32.],"width":32.,"depth":32.,"height_scale":1.,"bedrock_depth":16.,"name":"R16 测试地形","flip_z":false}
	var before:=snapshot();var plan:=await call_tool("preview_heightmap_import",args)
	if not plan.get("ok",false):quit(1);return
	check(snapshot()==before and plan.tile_count==4 and plan.cell_count==16384 and plan.bit_depth==16,"private R16 preview creates four native tiles without author side effects")
	check(absf(plan.quantization_step-1./65535.)<1e-12 and plan.source_sha256==FileAccess.get_sha256(source),"true 16-bit source identity and quantization reported")
	var again:=await call_tool("preview_heightmap_import",args);check(again.plan_token==plan.plan_token,"same request and source reuse candidate")
	var precise:=await call_tool("preview_heightmap_import",args.merged({"height_scale":1.00000001},true));check(precise.plan_token!=plan.plan_token,"sub-microunit input changes cannot reuse another height candidate")
	plan=await call_tool("preview_heightmap_import",args)
	var records:Array=editor._heightmap.visual(plan.plan_token)
	check(records[0].terrain_mesh.heights[1]==256./65535.,"R16 low byte precision is retained without 8-bit conversion")
	var max_seam:=0.
	for a:Dictionary in records:
		for b:Dictionary in records:
			if a.uuid==b.uuid or not Batch.adjacent(a,b):continue
			for vertex:Dictionary in Batch.edge_vertices(a):
				var height:=Batch.edge_height(b,vertex.p)
				if is_finite(height):max_seam=maxf(max_seam,absf(height-vertex.p.y))
	check(max_seam<.000001,"all native split edges share source samples")
	var flipped:=await call_tool("preview_heightmap_import",args.merged({"flip_z":true},true));check(editor._heightmap.visual(flipped.plan_token)[0].terrain_mesh.heights[0]==32768./65535.,"explicit flip_z changes source-row orientation")
	await call_tool("discard_heightmap_import",{"plan_token":flipped.plan_token});check(snapshot()==before,"discard is authoring read-only")
	await reject("apply_heightmap_import",{"plan_token":flipped.plan_token})
	await reject("preview_heightmap_import",args.merged({"path":ProjectSettings.globalize_path("res://project.godot")},true))
	if not link_source.is_empty():
		var linked:=await reject("preview_heightmap_import",args.merged({"path":link_source,"samples_x":17,"samples_z":17,"width":4.,"depth":4.},true))
		check(linked.code=="heightmap_source_invalid","actual Windows junction source is rejected before image decoding")
		link_test="real directory junction rejected before decode"
	else:link_test="not supplied; link guard not exercised"
	await reject("preview_heightmap_import",args.merged({"samples_x":65},true))
	await reject("preview_heightmap_import",args.merged({"width":2.},true))
	var invalid_png:=FileAccess.get_file_as_bytes(png_path);invalid_png[24]=16;var invalid_path:=directory.path_join("png16.png");FileAccess.open(invalid_path,FileAccess.WRITE).store_buffer(invalid_png)
	var png_args:Dictionary={"path":png_path,"format":"png8","center":[-20.,0.,0.],"width":16.,"depth":16.,"height_scale":1.}
	await reject("preview_heightmap_import",png_args.merged({"path":invalid_path},true))
	var oversized:=directory.path_join("oversized.r16");var oversized_file:=FileAccess.open(oversized,FileAccess.WRITE);oversized_file.seek(Importer.MAX_BYTES);oversized_file.store_8(0);oversized_file.close()
	await reject("preview_heightmap_import",args.merged({"path":oversized},true))
	var eight:=await call_tool("preview_heightmap_import",png_args);check(eight.bit_depth==8 and eight.tile_count==1,"8-bit grayscale PNG imports without implicit resampling")
	plan=await call_tool("preview_heightmap_import",args);editor._heightmap.candidate.after.records[0].size[0]=-1.
	await reject("apply_heightmap_import",{"plan_token":plan.plan_token})
	plan=await call_tool("preview_heightmap_import",args);FileAccess.open(source,FileAccess.WRITE).store_buffer(raw+PackedByteArray([0]))
	await reject("apply_heightmap_import",{"plan_token":plan.plan_token});FileAccess.open(source,FileAccess.WRITE).store_buffer(raw)
	plan=await call_tool("preview_heightmap_import",args)
	await call_tool("create_terrain",{"center":[100.,0.,100.],"width":4.,"depth":4.,"cell_size":1.})
	await reject("apply_heightmap_import",{"plan_token":plan.plan_token});await call_tool("undo")
	var ui=editor._terrain_panel.heightmap;var values:=args.duplicate();values.erase("path");ui.path.text=source;ui.fields.update_values(values)
	check(equivalent(ui.request(),args),"UI exposes the same explicit import parameters")
	var ui_before:=snapshot();var ui_plan:Dictionary=ui.preview();check(ui_plan.ok and ui_plan.source_sha256==plan.source_sha256 and ui_plan.tile_count==4 and snapshot()==ui_before,"real UI preview matches HTTP geometry and source")
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._terrain_panel):editor._dock_tabs.current_tab=i
	for i in editor._terrain_panel.tasks.get_tab_count():
		if editor._terrain_panel.tasks.get_tab_title(i)=="高度图":editor._terrain_panel.tasks.current_tab=i
	await call_tool("set_editor_camera",{"projection":"perspective","center":[32.,0.,32.],"distance":65.,"pitch":-42.,"yaw":25.});await settle();await RenderingServer.frame_post_draw
	var screen:=root.get_texture().get_image();screen.save_webp(output+"/ui.webp",true,.9)
	FileAccess.open(output+"/compression.json",FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(output+"/ui.webp"),"quality":90,"lossy":true,"width":screen.get_width(),"height":screen.get_height(),"encoder":"Godot Image.save_webp(lossy=true, quality=0.9)"},"\t"))
	ui.fields.fields.height_scale.value=2.;check(ui.token.is_empty() and ui.apply_button.disabled and not is_instance_valid(ui.ghost),"UI edit invalidates entire preview")
	ui.fields.fields.height_scale.value=1.;ui.preview_button.pressed.emit();var ui_apply:Dictionary=ui.apply_candidate();check(ui_apply.ok and editor._doc.records.size()==4,"UI applies full group once")
	await call_tool("undo");check(editor._doc.records.is_empty(),"one undo removes entire UI import")
	plan=await call_tool("preview_heightmap_import",args);await call_tool("apply_heightmap_import",{"plan_token":plan.plan_token})
	await reject("preview_heightmap_import",args)
	check(plan.terrain_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id)) and not editor._bodies_by_uuid.get(id,[]).is_empty()),"each tile has independent selection and native picking/collision")
	await call_tool("undo");check(editor._doc.records.is_empty(),"HTTP group undoes atomically");await call_tool("redo")
	check(plan.terrain_ids.all(func(id):return editor._doc.has_uuid(id)),"redo restores stable tile IDs")
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	var stats:Dictionary=editor._ground_batches.stats();check(stats.pending_groups==0 and stats.source_surfaces>stats.render_surfaces,"native shared batches actually combine imported terrain surfaces")
	var saved:Array=editor._doc.records.duplicate(true)
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(saved,editor._doc.records) and editor._doc.validate_save()==OK,"native save/reopen retains editable heights and tile identity")
	var sampled:=await call_tool("sample_terrain_height",{"id":plan.terrain_ids[0],"point":[32.,32.]});check(absf(sampled.height-32768./65535.)<.00001,"reopened shared tile corner samples original 16-bit height")
	await call_tool("sculpt_terrain",{"id":plan.terrain_ids[0],"mode":"raise","points":[[25.,25.]],"radius":.5,"strength":.1,"hardness":1.,"cross_tiles":true});await call_tool("undo")
	check(equivalent(saved,editor._doc.records),"imported native terrain remains sculptable and undoable")
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":count,"failures":failed,"link_test":link_test,"plan":plan,"max_seam":max_seam,"batch_stats":stats,"map":path,"map_sha256":FileAccess.get_sha256(path),"source":source,"source_sha256":FileAccess.get_sha256(source)},"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("HEIGHTMAP_IMPORT checks=",count," failures=",failed);quit(1 if failed else 0)
