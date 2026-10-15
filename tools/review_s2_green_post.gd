extends "res://tools/review_guild_full_batch.gd"
## Isolated native roundtrip and fixed-camera review for one S2 post.
## --source=<GLB> --out=<folder> --label=master|runtime
var review_label := "runtime"

func gallery(scene:Node, folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1000,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.58;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=60;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane;floor.position.y=-.008
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.25,.27,.25);mat.roughness=1.;floor.material_override=mat;vp.add_child(floor)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=100;vp.add_child(cam)
	var center:=Vector3(0,1.53,0);var direction:=Vector3(.7,.2,1.55).normalized()
	var views:Array=[]
	for pair in [["near",4.9],["medium",9.0],["far",18.0]]:views.append({"name":pair[0],"eye":center+direction*pair[1],"aim":center})
	views.append_array([
		{"name":"back","eye":center+Vector3(-.8,.2,-1.4).normalized()*4.9,"aim":center},
		{"name":"wood_ribbon_detail","eye":Vector3(.8,1.75,1.25),"aim":Vector3(0,1.65,0)},
		{"name":"upper_join_detail","eye":Vector3(1.1,3.3,1.5),"aim":Vector3(0,2.62,0)},
		{"name":"base_detail","eye":Vector3(.8,.55,1.3),"aim":Vector3(0,.35,0)},
		{"name":"grazing","eye":Vector3(.8,1.75,1.25),"aim":Vector3(0,1.65,0)},
		{"name":"overcast","eye":center+direction*4.9,"aim":center}
	])
	report.render_environment={"image_size":[1000,1000],"fov":42,"msaa":4,"taa":false,"ambient":.58,"sun":1.5,"sun_rotation":[-38,-28,0],"exposure":1,"renderer":RenderingServer.get_current_rendering_method()}
	report.actual_materials=[]
	for node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for s in node.mesh.get_surface_count():
			var m:=node.get_active_material(s) as StandardMaterial3D
			var arrays:=node.mesh.surface_get_arrays(s)
			var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			check(m!=null,"runtime PBR material: "+str(node.name))
			if m==null:continue
			check(m.normal_enabled and m.normal_texture!=null,"normal enabled: "+str(node.name))
			check(tangents.size()>0,"runtime tangents: "+str(node.name))
			check(not m.emission_enabled,"wood and ribbon are not emissive: "+str(node.name))
			report.actual_materials.append({"node":str(node.name),"surface":s,"metallic":m.metallic,"roughness":m.roughness,"normal_enabled":m.normal_enabled,"normal_scale":m.normal_scale,"normal_image":normalized_image(m.normal_texture.get_image()) if m.normal_texture!=null else {},"albedo_image":normalized_image(m.albedo_texture.get_image()) if m.albedo_texture!=null else {},"roughness_image":normalized_image(m.roughness_texture.get_image()) if m.roughness_texture!=null else {},"albedo_color":var_to_str(m.albedo_color),"emission":m.emission_enabled,"tangent_floats":tangents.size()})
	report.screenshots=[]
	for view:Dictionary in views:
		cam.position=view.eye;cam.look_at(view.aim)
		sun.rotation_degrees=Vector3(-14,65,0) if view.name=="grazing" else Vector3(-38,-28,0)
		sun.light_energy=.15 if view.name=="overcast" else 1.5
		env.ambient_light_energy=.78 if view.name=="overcast" else .58
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(view.name)+".png")
		check(vp.get_texture().get_image().save_png(path)==OK,"screenshot "+str(view.name))
		report.screenshots.append({"name":view.name,"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"ambient":env.ambient_light_energy,"sun":sun.light_energy,"sun_rotation":vec(sun.rotation_degrees)})
	report.wind_scope="Rigid post and tightly bound ribbon retain original no-wind semantics; separately deployed bunting is unchanged."
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--label="):review_label=arg.trim_prefix("--label=")
	if DisplayServer.get_name()=="headless":print("S2_REVIEW_SYNTAX_OK");quit();return
	if not source.begins_with("D:/code/rmmo_runtime/art_sources/s2_green_pennant_post_20261015/") or not out.begins_with("D:/code/rmmo/review_artifacts/s2_green_pennant_post_20261015/"):push_error("Source/output outside isolated scope");quit(2);return
	var identity:={"id":"s2_green_pennant_post","variant":review_label,"path":source,"sha256":FileAccess.get_sha256(source),"source_bytes":size_of(source)}
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	if doc.append_from_file(source,state)!=OK:push_error("GLB import failed");quit(2);return
	var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
	await review_one(scene,identity,out)
	# Footprint.measure requires the production loader's validated-native marker.
	# This isolated ResourceLoader roundtrip intentionally does not forge it.
	# The formal importer below measures through Compiled/Preparation instead.
	if report.get("conservative_estimate",{}).is_empty():
		report.erase("conservative_estimate")
		report.erase("footprint_stats")
		report.footprint_scope="Pending production Compiled/Preparation measurement in formal import receipt; isolated native bytes are measured, not RSS/VRAM."
	check(report.get("gallery_completed",false),"gallery completed")
	check(FileAccess.get_sha256(source)==identity.sha256,"source unchanged")
	report.passed=report.failures.is_empty();put(out.path_join("report.json"),report)
	print("S2_REVIEW_COMPLETE ",review_label," passed=",report.passed);quit(0 if report.passed else 1)
