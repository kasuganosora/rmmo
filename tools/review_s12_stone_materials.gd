extends "res://tools/review_guild_full_batch.gd"
## Isolated native roundtrip; one source per process prevents cached A/B aliasing.
## --source=<GLB> --out=<isolated folder> --kind=arch|relief --variant=baseline|candidate
var asset_kind := "arch"
var variant := "candidate"
const OUT_ROOT := "D:/code/rmmo/review_artifacts/s12_stone_materials_20261015/"
const SOURCE_ROOT := "D:/code/rmmo_runtime/art_sources/s12_stone_materials_20261015/"
const OLD_SOURCES := [
	"D:/code/rmmo_runtime/packs/default/assets/11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be.glb",
	"D:/code/rmmo_runtime/packs/default/assets/d0ca66d5b04913d4bc9ffd56fcc01bb2f4761332dc28fcd98337ad21026dd240.glb"
]

func texture_pixels(texture:Texture2D)->Dictionary:
	if texture==null:return {}
	var img:=texture.get_image()
	if img==null:return {"invalid":true}
	if img.is_compressed():img.decompress()
	img.clear_mipmaps();img.convert(Image.FORMAT_RGBA8)
	return {"size":[img.get_width(),img.get_height()],"rgba_base_sha256":sha(img.get_data())}

func gallery(scene:Node,folder:String)->void:
	var bounds:=scene_bounds(scene);var center:=bounds.get_center()
	var distance:=bounds.size.length()*.5/sin(deg_to_rad(21))*1.08
	var vp:=SubViewport.new();vp.size=Vector2i(1100,1100);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.40;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=80;vp.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);ground.mesh=plane;ground.position.y=bounds.position.y-.008
	var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.25,.27,.25);gm.roughness=1.;ground.material_override=gm;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=150;vp.add_child(cam)
	var direction:=Vector3(.40,.16,1.5).normalized();var views:Array=[]
	for pair in [["near",1.0],["medium",1.8],["far",3.0]]:views.append({"name":pair[0],"eye":center+direction*distance*pair[1],"aim":center})
	views.append({"name":"back","eye":center+Vector3(-.45,.18,-1.5).normalized()*distance,"aim":center})
	var detail:=center+Vector3(0,bounds.size.y*.18,bounds.size.z*.46)
	var detail_dist:=maxf(1.5,bounds.size.y*.40)
	if asset_kind=="arch":detail=Vector3(bounds.end.x-.5,bounds.position.y+bounds.size.y*.55,bounds.end.z-.15)
	var upper:=Vector3(center.x,bounds.position.y+bounds.size.y*.88,bounds.end.z-.12)
	views.append({"name":"detail","eye":detail+Vector3(.35,.12,1).normalized()*detail_dist,"aim":detail})
	views.append({"name":"upper","eye":upper+Vector3(.35,.2,1).normalized()*maxf(2.2,bounds.size.x*.9),"aim":upper})
	for label in ["grazing_right","grazing_left"]:views.append({"name":label,"eye":detail+Vector3(.35,.12,1).normalized()*detail_dist,"aim":detail})
	views.append({"name":"overcast","eye":center+direction*distance,"aim":center})
	if variant.begins_with("side_seams"):
		# Supplemental oblique-camera inspection of rear-facing tube UV seams.
		# This is diagnostic coverage, separate from the nine matched A/B views.
		views.clear()
		for sign_ in [-1.0,1.0]:
			views.append({"name":"side_left" if sign_<0 else "side_right","eye":detail+Vector3(sign_*3.0,.12,.8).normalized()*detail_dist,"aim":detail})
	report.render_environment={"image_size":[1100,1100],"fov":42,"msaa":4,"taa":false,"ambient":.4,"sun":1.5,"exposure":1,"renderer":RenderingServer.get_current_rendering_method(),"normal_reference":"model front is +Z; L points from front surface towards light"}
	report.actual_materials=[]
	for node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for slot in node.mesh.get_surface_count():
			var mat:=node.get_active_material(slot) as StandardMaterial3D
			check(mat!=null,"runtime PBR "+str(node.name))
			if mat==null:continue
			var arrays:=node.mesh.surface_get_arrays(slot)
			var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			# The arch also has real iron ties/anchors. Only its first surface is stone.
			var stone_surface:=asset_kind=="relief" or (str(node.name).ends_with("_part_0") and slot==0)
			if stone_surface:
				check(mat.normal_enabled and mat.normal_texture!=null,"actual stone normal binding "+str(node.name))
				check(not mat.emission_enabled and mat.metallic==0,"stone nonmetal and nonemissive "+str(node.name))
			check(tangents.size()>0,"runtime tangent data "+str(node.name))
			report.actual_materials.append({"node":str(node.name),"surface":slot,"material_name":mat.resource_name,"stone_surface":stone_surface,"albedo_color":var_to_str(mat.albedo_color),"metallic":mat.metallic,"roughness":mat.roughness,"roughness_channel":mat.roughness_texture_channel,"ao_enabled":mat.ao_enabled,"ao_channel":mat.ao_texture_channel,"normal_enabled":mat.normal_enabled,"normal_scale":mat.normal_scale,"normal":texture_pixels(mat.normal_texture),"albedo":texture_pixels(mat.albedo_texture),"roughness_map":texture_pixels(mat.roughness_texture),"ao_map":texture_pixels(mat.ao_texture),"tangent_floats":tangents.size()})
	report.screenshots=[]
	for view:Dictionary in views:
		var light_dir:=Vector3(.65,.8,1).normalized()
		if view.name=="grazing_right":light_dir=Vector3(1,.25,.23).normalized()
		if view.name=="grazing_left":light_dir=Vector3(-1,.25,.23).normalized()
		if view.name=="back":light_dir=Vector3(-.65,.8,-1).normalized()
		sun.position=center+light_dir*20;sun.look_at(center)
		sun.light_energy=.15 if view.name=="overcast" else 1.5
		env.ambient_light_energy=.75 if view.name=="overcast" else .40
		cam.position=view.eye;cam.look_at(view.aim)
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(view.name)+".png")
		check(vp.get_texture().get_image().save_png(path)==OK,"screenshot "+str(view.name))
		report.screenshots.append({"name":view.name,"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"light_direction_to_source":vec(light_dir),"front_N_dot_L":light_dir.z,"ambient":env.ambient_light_energy,"sun":sun.light_energy,"sun_color":var_to_str(sun.light_color),"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--kind="):asset_kind=arg.trim_prefix("--kind=")
		if arg.begins_with("--variant="):variant=arg.trim_prefix("--variant=")
	if DisplayServer.get_name()=="headless":print("S12_REVIEW_SYNTAX_OK");quit();return
	if (not source.begins_with(SOURCE_ROOT) and source not in OLD_SOURCES) or not out.begins_with(OUT_ROOT) or asset_kind not in ["arch","relief"]:push_error("Outside isolated review scope");quit(2);return
	var identity:={"id":"s12_"+asset_kind,"variant":variant,"path":source,"sha256":FileAccess.get_sha256(source),"source_bytes":size_of(source)}
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	if doc.append_from_file(source,state)!=OK:push_error("GLB import failed");quit(2);return
	var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
	await review_one(scene,identity,out)
	if report.get("conservative_estimate",{}).is_empty():
		report.erase("conservative_estimate");report.erase("footprint_stats")
		report.footprint_scope="Actual production Compiled/Preparation footprint recorded by formal importer; isolated roundtrip does not forge a validated-native marker."
	check(report.get("gallery_completed",false),"gallery completed")
	check(FileAccess.get_sha256(source)==identity.sha256,"source unchanged")
	report.passed=report.failures.is_empty();put(out.path_join("report.json"),report)
	print("S12_REVIEW_COMPLETE ",asset_kind," ",variant," passed=",report.passed);quit(0 if report.passed else 1)
