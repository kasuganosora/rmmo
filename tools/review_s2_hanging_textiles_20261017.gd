extends "res://tools/review_guild_full_batch.gd"
const SOURCE_ROOT="D:/code/rmmo_runtime/art_sources/s2_hanging_textiles_20261017/"
const OUTPUT_ROOT="D:/code/rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/"
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
var authoring:Dictionary={}
class EditorProbe:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1600,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var bounds:=scene_bounds(scene);var center:=bounds.get_center();var lamp:bool="bronze_lamp" in authoring.id
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false);scene.set_meta("asset_uuid","s2_textile_review");editor._add_bodies(scene)
	await physics_frame;await physics_frame
	var bodies:Array=editor._bodies_by_uuid.get("s2_textile_review",[]);check(not bodies.is_empty(),"actual editor pick bodies exist")
	for body:StaticBody3D in bodies:
		var visual:MeshInstance3D=body.get_meta("visual");check((body.collision_layer&1)!=0,"editor selection "+str(visual.name))
		var physical:=bool(body.collision_layer&Walk.WALK_MASK);check(physical==Walk.physical(visual.get_meta("extras",{})),"actual collision semantic "+str(visual.name))
		if not lamp or visual.get_meta("extras",{}).has("rmmo_wind"):check(not physical,"cloth and suspension never block movement "+str(visual.name))
	var wind_materials:Array=[];var wind_count:=0;report.anchor_checks=[];report.active_cloth_materials=[]
	for node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		var config:Dictionary=node.get_meta("extras",{}).get("rmmo_wind",{})
		if config.is_empty():continue
		wind_count+=1
		var aabb:=node.get_aabb();var max_pin_displacement:=0.0
		for pin:Array in node.get_meta("extras",{}).get("cloth_top_vertices",[]):
			var u:=clampf((aabb.end.y-float(pin[1]))/aabb.size.y,0,1)
			var weight:=pow(u,lerpf(1.4,3.8,float(config.stiffness)))
			max_pin_displacement=maxf(max_pin_displacement,float(config.amplitude)*1.5*(1-float(config.stiffness)*.65)*weight*1.6)
		check(max_pin_displacement<.001,"top attachment below 1 mm at shader maximum wind "+str(node.name))
		report.anchor_checks.append({"node":str(node.name),"max_top_displacement_bound_m":max_pin_displacement,"bounds":var_to_str(aabb)})
		for slot in node.mesh.get_surface_count():
			var base:=node.get_active_material(slot) as StandardMaterial3D
			check(base!=null and base.metallic==0 and base.roughness>=.85,"nonmetal matte woven cloth "+str(node.name)+"/"+str(slot))
			check(base.normal_enabled and base.normal_texture!=null,"real imported weave normal active")
			var pixels:=base.normal_texture.get_image();pixels.clear_mipmaps();pixels.convert(Image.FORMAT_RGBA8)
			report.active_cloth_materials.append({"node":str(node.name),"surface":slot,"normal_scale":base.normal_scale,"normal_pixel_sha256":sha(pixels.get_data()),"normal_size":[pixels.get_width(),pixels.get_height()],"roughness":base.roughness,"metallic":base.metallic})
			var m:=Wind.make(base,config,aabb);node.set_surface_override_material(slot,m);wind_materials.append(m)
			check(m.get_shader_parameter("normal_tex")==base.normal_texture,"wind preserves actual normal texture")
			check(m.get_shader_parameter("anchor_reverse")==true,"each cloth has independent top anchor")
	check(wind_count==int(authoring.expected_wind_meshes),"only authored cloth receives wind")
	report.wind_mesh_count=wind_count;report.pick_body_count=bodies.size();editor.free();await physics_frame
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.12,.16,.21);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.91,.95,1);environment.ambient_light_energy=.28;environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.tonemap_exposure=1
	var world:=WorldEnvironment.new();world.environment=environment;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.;sun.shadow_enabled=true;vp.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);ground.mesh=plane;ground.position.y=0 if lamp else (-4.7 if "festoon" in authoring.id else -3.8);var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.25,.25,.23);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.01;cam.far=200;vp.add_child(cam)
	var distance:=bounds.size.length()*.5/sin(deg_to_rad(21))*1.10;var direction:=Vector3(.18,.13,1).normalized();var views:Array=[]
	for pair in [["near",1.0],["medium",1.8],["far",3.0]]:views.append({"name":pair[0],"eye":center+direction*distance*pair[1],"aim":center})
	views.append({"name":"back","eye":center+Vector3(-.18,.13,-1).normalized()*distance,"aim":center})
	var detail_aim:=Vector3(-.318,-.5,.01);var mount_aim:=Vector3(-4,0,0)
	if "laundry" in authoring.id:detail_aim=Vector3(-.19,-.70,0);mount_aim=Vector3(-1.75,0,0)
	elif "banner" in authoring.id:detail_aim=Vector3(-.61,1.9,.04) if lamp else Vector3(0,-1,0);mount_aim=Vector3(-.61,2.835,.038) if lamp else Vector3(0,0,0)
	views.append({"name":"cloth_detail","eye":detail_aim+Vector3(.25,.07,1.7),"aim":detail_aim})
	views.append({"name":"attachment","eye":mount_aim+Vector3(.42,.28,.85),"aim":mount_aim})
	for t in [1.0,4.0]:views.append({"name":"wind_t"+str(int(t)),"eye":center+direction*distance,"aim":center,"time":t})
	report.screenshots=[]
	for view:Dictionary in views:
		var light:=Vector3(.7,.8,1.2).normalized() if view.name!="back" else Vector3(-.7,.8,-1.2).normalized()
		sun.position=center+light*30;sun.look_at(center);cam.position=view.eye;cam.look_at(view.aim)
		for m:ShaderMaterial in wind_materials:m.set_shader_parameter("wind_velocity",Vector3(3,0,4) if view.has("time") else Vector3.ZERO);m.set_shader_parameter("wind_time",float(view.get("time",0)))
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(view.name)+".png");check(vp.get_texture().get_image().save_png(path)==OK,"capture "+str(view.name))
		report.screenshots.append({"name":view.name,"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"light":vec(light),"wind_time":view.get("time",0),"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1600,1000],"fov":42,"exposure":1,"sun":1.,"ambient":.28,"wind_velocity":[3,0,4],"msaa":4,"taa":false,"renderer":RenderingServer.get_current_rendering_method()};report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	if DisplayServer.get_name()=="headless":print("S2_TEXTILES_SYNTAX_OK");quit();return
	if not source.begins_with(SOURCE_ROOT) or not out.begins_with(OUTPUT_ROOT) or FileAccess.file_exists(out.path_join("report.json")):quit(2);return
	authoring=read_json(source.get_basename()+"_authoring.json")
	if authoring.get("sha256")!=FileAccess.get_sha256(source):quit(2);return
	var d:=GLTFDocument.new();var s:=GLTFState.new();if d.append_from_file(source,s)!=OK:quit(2);return
	var scene:Node=Io.generate_scene(d,s)
	await review_one(scene,{"id":authoring.id,"path":source,"sha256":authoring.sha256,"source_bytes":size_of(source)},out)
	check(report.get("gallery_completed",false),"gallery completed");check(FileAccess.get_sha256(source)==authoring.sha256,"immutable source");check(report.generator==Compiled.generator(),"stable pipeline")
	report.passed=report.failures.is_empty();report.visual_review="pending actual WebP inspection";put(out.path_join("report.json"),report);quit(0 if report.passed else 1)
