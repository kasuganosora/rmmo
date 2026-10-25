extends SceneTree
## Actual terrain shader, all six binding layers, planar/triplanar paths.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
var failures:Array[String]=[]
var samples:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func capture(viewport:SubViewport,output:String)->Image:
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image();image.save_png(output);return image
func difference(a:Image,b:Image)->float:
	var total:=0.0
	for y in range(100,220):
		for x in range(60,260):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			total+=absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)
	return total/(120.*200.*3.)
func run()->void:
	var source:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=").replace("\\","/")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if source.is_empty() or output.is_empty():quit(2);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.12,.12);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.25;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-35,0);light.light_energy=1.6;world.add_child(light)
	var mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4);mesh.mesh=plane;world.add_child(mesh)
	var camera:=Camera3D.new();camera.position=Vector3(0,2.03,2.9);world.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
	var definition:={"name":"BC5 custom shader fixture","color":[.55,.55,.55,1.],"roughness":.8,"normal_path":source,"normal_strength":.7,"tile_size":[4,4]}
	for layer:String in ["base","sand","rock","region_a","region_b","soil"]:
		for slope:bool in [false,true]:
			if layer=="soil" and not slope:continue
			var images:Array[Image]=[]
			for compressed:bool in [false,true]:
				Paint.compressed_sidecars_enabled=compressed;Paint.refresh_sources();River.cache.clear()
				var material:=ShaderMaterial.new();material.shader=preload("res://scripts/world3d/river_terrain.gdshader")
				for prefix:String in ["base","sand","rock","region_a","region_b","soil"]:
					River.bind(material,prefix,definition)
					check((material.get_shader_parameter(prefix+"_normal_xy")==true)==compressed,"BC5 format flag "+prefix+" "+str(compressed))
					if prefix!=layer:material.set_shader_parameter(prefix+"_strength",0.)
				material.set_shader_parameter("slope_aware",slope)
				material.set_shader_parameter("height_blend_strength",0.)
				material.set_shader_parameter("edge_noise",0.)
				if layer in ["sand","rock","soil"]:
					material.set_shader_parameter("depth_enabled",true)
					material.set_shader_parameter("water_level",4. if layer=="rock" else (-.775 if layer=="soil" else 0.))
				if layer=="soil":
					material.set_shader_parameter("transition_width",1.)
					var heights:=Image.create(4,4,false,Image.FORMAT_RF);heights.fill(Color(0,0,0))
					material.set_shader_parameter("terrain_heights",ImageTexture.create_from_image(heights))
				if layer in ["region_a","region_b"]:
					var mask:=Image.create(2,2,false,Image.FORMAT_RG8);mask.fill(Color(1,0,0) if layer=="region_a" else Color(0,1,0))
					material.set_shader_parameter("ground_enabled",true);material.set_shader_parameter("ground_mask",ImageTexture.create_from_image(mask))
				mesh.material_override=material
				images.append(await capture(viewport,output.path_join(layer+"_"+str(slope)+("_bc5.png" if compressed else "_png.png"))))
			var error:=difference(images[0],images[1]);samples.append({"layer":layer,"slope":slope,"mean_rgb_error":error})
			check(error<.015,"actual terrain normal RGB/BC5 match "+layer+" slope="+str(slope)+" error="+str(error))
	var standard:=Paint.make_material(definition)
	var water:=River.water({"absorption":.45,"shallow_color":[.24,.42,.34],"deep_color":[.055,.16,.14]},standard)
	check(water.get_shader_parameter("normal_xy")==true,"water inherits BC5 normal format without image readback")
	mesh.material_override=water;await capture(viewport,output.path_join("water_compile.png"))
	Paint.compressed_sidecars_enabled=true;Paint.refresh_sources();River.cache.clear()
	var report:={"checks":checks,"samples":samples,"failures":failures}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("TERRAIN_BC5 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
