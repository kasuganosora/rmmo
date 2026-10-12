extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var directory:String
var shots:Array=[{"name":"detail","center":[40.5,8.3,0],"distance":10.,"pitch":-30.,"yaw":65.},{"name":"near","center":[39,5,0],"distance":24.,"pitch":-18.,"yaw":90.},{"name":"mid","center":[28,5,0],"distance":52.,"pitch":-27.,"yaw":78.},{"name":"far","center":[0,4,0],"distance":115.,"pitch":-42.,"yaw":65.}]
var metrics:Array=[]
var lod_audit:Dictionary={}

func check_art_lods(settings:Dictionary)->void:
	if DisplayServer.get_name()=="headless":return
	var prepared:Dictionary=editor._fortifications.prepare(settings)
	check(prepared.ok,"procedural wall source prepares for LOD audit")
	if not prepared.ok:return
	var Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
	for source:Dictionary in prepared.records:
		if source.get("fortification_art",{}).get("module","") not in ["wall","round_tower","corner_tower"]:continue
		var mesh:ArrayMesh=preload("res://scripts/world3d/fortification_art.gd").new().build(source)
		if mesh==null:continue
		var levels:Array=[]
		for slot in mesh.get_surface_count():levels.append(Cpu.capture_lods(mesh,slot))
		if not levels.any(func(level):return not level.is_empty()):continue
		var cpu:Mesh=Cpu.capture(mesh)
		check(cpu.lods==levels,"Art.build retains generated GPU LOD indices in CPU capture")
		cpu.source_reference=null
		var restored:ArrayMesh=cpu.restore()
		var restored_levels:Array=[]
		for slot in restored.get_surface_count():restored_levels.append(Cpu.capture_lods(restored,slot))
		check(restored_levels==levels,"procedural wall CPU restore retains every generated LOD")
		lod_audit={"part":source.fortification.part,"module":source.fortification_art.module,"levels_per_surface":levels.map(func(level):return level.size()),"source_sha256":FileAccess.get_sha256(source.fortification_art.asset_path),"source":source.fortification_art.asset_path}
		return
	check(false,"at least one actual generated stone wall exposes LOD levels")

func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size;root.use_taa=false;editor._grid.hide()
	for shot:Dictionary in shots:
		var args:Dictionary=shot.duplicate();args.erase("name");args.projection="perspective"
		await call_tool("set_editor_camera",args)
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		var viewport:Viewport=editor._camera.get_viewport()
		check(viewport.get_texture().get_image().save_png(directory.path_join(shot.name+"_"+label+".png"))==OK,"capture "+shot.name+" "+label)
		metrics.append({"name":shot.name,"stage":label,"primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"camera":args})

func run()->void:
	create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	directory=Paths.cache_directory("water_crown_follow_review_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"isolated water crown fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31910
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"water crown review HTTP starts")
	var terrain:=await call_tool("create_terrain",{"center":[0,0,0],"width":104.,"depth":104.,"cell_size":2.})
	var settings:={"id":"review_water_crown","shape":"ellipse","radius_x":40.,"radius_z":40.,"height":8.,"thickness":3.5,"corner_towers":false,"follow_terrain":true,"style":"medieval_stone","arrow_slits":false,"wall_access":false,"gates":[{"id":"water","angle":0.,"kind":"water","width":24.,"height":5.,"open":.4,"grille":true}]}
	await check_art_lods(settings)
	var generated:=await call_tool("generate_fortification",settings)
	if not generated.get("ok",false):editor._mcp.stop();editor.queue_free();await settle();quit(1);return
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	await capture("baseline")
	var before:Dictionary=editor._doc.recovery_snapshot()
	var stroke:={"id":terrain.id,"mode":"lower","points":[[40,0]],"radius":12.,"hardness":.25,"strength":.35}
	await call_tool("preview_terrain_stroke",stroke);check(equivalent(before,editor._doc.recovery_snapshot()),"lower water bed preview is read only")
	await call_tool("sculpt_terrain",stroke)
	check(editor._fortifications.catalog().regions.all(func(r):return r.modified_or_missing.is_empty()),"water crown follower signatures remain valid")
	var leaves:Array=editor._doc.records.filter(func(r):return r.has("fixture"))
	check(leaves.size()==6 and leaves.all(func(r):return is_equal_approx(r.fixture.open,.4)),"three water arches retain six independent partially-open leaves")
	var changed:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"water crown and bed restore in one undo")
	await call_tool("redo");check(equivalent(changed,editor._doc.recovery_snapshot()),"water crown and bed redo exactly")
	await call_tool("set_fortification_terrain_follow",{"id":settings.id,"enabled":false});await call_tool("undo")
	check(equivalent(changed,editor._doc.recovery_snapshot()),"water follow toggle exact undo after lower bed")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"lowered bed frozen water crown save reopen exact")
	await capture("lowered")
	var resources:Array=[];var materials:Dictionary={}
	for record:Dictionary in editor._doc.records:
		if not record.has("house_prefab"):continue
		resources.append({"id":record.uuid,"sha256":record.house_prefab.sha256,"uncompressed_bytes":record.house_prefab.length,"compressed_bytes":Marshalls.base64_to_raw(record.house_prefab.data).size(),"fixture":record.get("fixture",{})})
		for material:Dictionary in record.get("prefab_materials",[]):
			for field:String in ["texture_path","normal_path","roughness_path","metallic_path","ao_path","height_path"]:
				var source:String=material.get(field,"")
				if not source.is_empty():materials[source]=FileAccess.get_sha256(source)
	var code:Dictionary={}
	for source:String in ["res://scripts/world3d/fortification_terrain.gd","res://scripts/world3d/fortification_art.gd","res://scripts/world3d/fortification_ring.gd","res://scripts/world_editor/terrain_follow_tools.gd","res://scripts/world_editor/fortification_tools.gd","res://tools/test_water_crown_follow_review.gd"]:code[source]=FileAccess.get_sha256(source)
	var report:={"map":path,"map_sha256":FileAccess.get_sha256(path),"code_sha256":code,"frozen_resources":resources,"texture_sources":materials,"settings":settings,"stroke":stroke,"shots":metrics,"art_lod":lod_audit,"renderer":RenderingServer.get_video_adapter_name(),"headless":DisplayServer.get_name()=="headless","failures":failed}
	FileAccess.open(directory.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATER_CROWN_REVIEW_ARTIFACTS ",directory)
	editor._mcp.stop();editor.queue_free();await settle();print("WATER_CROWN_REVIEW_FINISHED failures=",failed);quit(failed)
