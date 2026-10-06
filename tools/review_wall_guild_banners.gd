extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_response.gd")
var OUT="D:/code/rmmo_runtime/art_sources/wall_guild_banners"
var failed=0
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func run()->void:
	create_timer(150).timeout.connect(func():quit(2))
	var soviet=OS.get_cmdline_user_args().has("--soviet")
	if soviet:OUT+="/soviet_variant"
	if soviet and OS.get_cmdline_user_args().has("--optimized"):OUT+="/optimized"
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/manifest.json"))
	var specs=[{"id":"soviet_swallowtail_tall","sha256":manifest.sha256}] if soviet else manifest.assets
	var vp=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.28,.30,.32);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.55;vp.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.shadow_enabled=true;sun.light_energy=1.5;vp.add_child(sun)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=11;cam.position=Vector3(3,9,18);vp.add_child(cam);cam.look_at(Vector3(0,3.8,0))
	var wind=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam
	var rows:Array=[];var locations=[0] if soviet else [-3.0,0,3.2]
	for i in specs.size():
		var spec=specs[i];var file=OUT+("/" if soviet else "/models/")+spec.id+".glb"
		check(FileAccess.get_sha256(file)==spec.sha256,"source hash")
		var model=Library.instantiate_preview(file);check(model!=null,"native GLB import")
		if model==null:continue
		vp.add_child(model);model.position.x=locations[i]
		var cloths=Paint.meshes(model).filter(func(m):return m.get_meta("extras",{}).has("rmmo_wind"))
		check(cloths.size()==1,"one cloth receiver / rigid bracket excluded")
		for cloth in cloths:
			check(Wind.mesh_error(cloth).is_empty(),"native wind compatible without morph targets")
			var m=Wind.base_material(cloth,0)
			check(m.albedo_texture!=null and m.normal_texture!=null and m.roughness_texture!=null,"portable woven PBR")
			check(cloth.get_meta("extras",{}).get("rmmo_collision","")=="none","cloth non-blocking")
			Wind.register(cloth)
		rows.append({"id":spec.id,"sha256":spec.sha256,"wind_receivers":cloths.size()})
	wind.refresh();check(wind.receivers.size()==specs.size(),"expected native wind receiver count")
	for j in 10:await process_frame
	await RenderingServer.frame_post_draw;var still=vp.get_texture().get_image();still.save_png(OUT+"/native_still.png")
	wind.advance(Vector3(7,0,2),.8)
	for j in 10:await process_frame
	await RenderingServer.frame_post_draw;var moving=vp.get_texture().get_image();moving.save_png(OUT+"/native_wind.png")
	check(still.get_data()!=moving.get_data(),"native cloth responds to wind")
	FileAccess.open(OUT+"/runtime_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"assets":rows,"published":false,"scope":"native material and wind smoke test; no user maps modified"},"\t"))
	print("WALL_BANNERS_FAILURES ",failed);quit(1 if failed else 0)
