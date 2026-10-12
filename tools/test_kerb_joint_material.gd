extends "res://tools/test_world3d_mcp.gd"
const MATERIAL="pack:default:paving/automatic_limestone_kerb_readable/material"
const OUT="D:/code/rmmo_runtime/review_artifacts/bridge_road_edges_20261007"
func run()->void:
	rpc_timeout_ms=90000;create_timer(300).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("kerb_joint_material_%d"%OS.get_process_id());var path:=directory.path_join("map.gltf")
	var d:=Doc.new();d.add_box("ground",Vector3(0,-.25,0),Vector3(70,.5,30));check(d.save(path)==OK,"temporary material review map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=d
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP material review")
	await call_tool("create_road_path",{"points":[[-20,0,0],[20,0,0]],"width":4})
	var args:={"kerb_enabled":true,"kerb_width":.24,"kerb_height":.035,"kerb_material_id":MATERIAL,"material_id":"pack:default:paving/historic_cobble/material"}
	var preview:=await call_tool("preview_road_surface",args)
	check(preview.get("ok",false),"new joint material available through current 3D MCP")
	if not preview.get("ok",false):quit(1);return
	await call_tool("generate_road_surface",args.merged({"plan_token":preview.plan_token}))
	var snapshot:=d.recovery_snapshot();await call_tool("undo");await call_tool("redo");check(equivalent(snapshot,d.recovery_snapshot()),"material and continuous profile undo/redo")
	await review(d)
	await call_tool("save_world");var reopened=Doc.open_file(path)
	check(reopened!=null and equivalent(reopened.records,d.records),"PBR material and UVs survive native save/reopen")
	FileAccess.open(OUT+"/material_result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"material":MATERIAL,"temporary_map":path},"\t"))
	print("KERB_MATERIAL failures=",failed);editor.free();quit(failed)
func review(d:RefCounted)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1440,900);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.48,.64,.76);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.78,.82,.89);env.environment.ambient_light_energy=.58;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,145,0);sun.shadow_enabled=true;sun.light_energy=1.15;vp.add_child(sun)
	var sources:Array=[]
	for r:Dictionary in d.records:
		var node:MeshInstance3D=d._mesh(r);vp.add_child(node)
		if r.has("road_mesh"):sources.append(node)
		else:
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.17,.23,.08);node.material_override=mat
	var cam:=Camera3D.new();cam.position=Vector3(4,1.4,5);vp.add_child(cam);cam.look_at(Vector3(4,.04,1.5));cam.fov=55
	var original:Dictionary=preload("res://scripts/world_editor/surface_material_library.gd").new().find("pack:default:paving/automatic_limestone_kerb/material")
	for version in ["before","after"]:
		for node:MeshInstance3D in sources:
			for slot in node.mesh.get_surface_count():
				var mat:Material=node.mesh.surface_get_material(slot)
				if mat.resource_name.begins_with("自动路缘"):
					node.set_surface_override_material(slot,preload("res://scripts/world3d/surface_materials.gd").make_material(original) if version=="before" else null)
		await settle();await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/stone_joints_"+version+".png")
	vp.queue_free();await settle()
