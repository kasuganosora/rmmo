extends SceneTree
## Standalone sky equivalence/work fixture. No map, player or authoring mutation.
## One baseline pass is saved completely before the candidate pass begins.
const Clouds=preload("res://scripts/world3d/cloud_resources.gd")
const Presented=preload("res://scripts/util/frame_presentation.gd")
var output:=""
var before_shader:=""
var after_shader:=""
var checks:=0
var failures:Array[String]=[]
var results:Array=[]
var host:Node3D
var camera:Camera3D
var environment:Environment
var sky:Sky
var material:ShaderMaterial
var report:Dictionary={}
var phase:="setup"
var sample_frames:=360

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func flush()->void:
	report.merge({"checks":checks,"failures":failures,"results":results,"current_phase":phase},true)
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
func cases()->Array:
	return [
		{"name":"night_off_moon","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(-.55,.65,-.6).normalized(),"night":1.,"cover":0.,"cirrus":0.,"quality":1,"fov":70.,"benchmark":true},
		{"name":"night_moon_center","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(.3,.7,.2).normalized(),"night":1.,"cover":0.,"cirrus":0.,"quality":1,"fov":35.,"benchmark":false},
		{"name":"day_no_lunar_contribution","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(.3,.7,.2).normalized(),"night":0.,"cover":0.,"cirrus":0.,"quality":1,"fov":70.,"benchmark":true},
		{"name":"tiny_twilight_weight","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(.3,.7,.2).normalized(),"night":.000001,"cover":0.,"cirrus":0.,"quality":1,"fov":12.,"benchmark":false},
		{"name":"night_cloud_volume","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(.3,.7,.2).normalized(),"night":1.,"cover":.8,"cirrus":.35,"quality":1,"fov":70.,"benchmark":false},
		{"name":"night_layer_fallback","axis":Vector3(.3,.7,.2).normalized(),"look":Vector3(.3,.7,.2).normalized(),"night":1.,"cover":.7,"cirrus":.25,"quality":-1,"fov":70.,"benchmark":false},
		{"name":"reference_axis_pole","axis":Vector3(0.,.1,.995).normalized(),"look":Vector3(0.,.1,.995).normalized(),"night":1.,"cover":0.,"cirrus":0.,"quality":1,"fov":35.,"benchmark":false},
		{"name":"half_weight_small_moon","axis":Vector3(-.3,.9,-.2).normalized(),"look":Vector3(-.3,.9,-.2).normalized(),"night":.5,"cover":0.,"cirrus":0.,"quality":1,"fov":90.,"benchmark":false}
	]

func configure(row:Dictionary)->void:
	camera.position=Vector3(0,1.5,0);camera.fov=row.fov
	camera.look_at(camera.position+row.look,Vector3.UP)
	var night:float=row.night
	var parameters:={
		"zenith":Color(.015,.025,.05) if night>0. else Color(.25,.48,.72),
		"horizon":Color(.035,.045,.065) if night>0. else Color(.64,.74,.82),
		"cloud_tint":Color(.08,.10,.15) if night>0. else Color(.9,.92,.94),
		"sun_tint":Color(1.,.91,.75),"sun_direction":Vector3(-.4,.65,-.3).normalized(),
		"moon_direction":row.axis,"cloud_cover":row.cover,"cirrus_amount":row.cirrus,
		"daylight":1.,"night_amount":night,"dusk_amount":0.,
		"star_intensity":night,"star_seed":12345678,"star_time":123.5,
		"drift":Vector2(11.25,-2.75),"cloud_seed_offset":Clouds.seed_offset(12345678),
		"cloud_quality":row.quality,"cloud_altitude":1500.,"cloud_thickness":450.,"cloud_scale":1800.,"cloud_storm":0.,"cloud_flash":Vector4.ZERO
	}
	var zeros:=PackedFloat32Array();zeros.resize(8)
	var directions:=PackedVector3Array();directions.resize(8);directions.fill(Vector3.UP)
	parameters.merge({"meteor_heads":directions,"meteor_tails":directions,"meteor_energies":zeros,"meteor_kinds":zeros,"meteor_brightness":zeros})
	for key:String in parameters:material.set_shader_parameter(key,parameters[key])
	# No Weather process, TIME uniform, moving clock, TAA jitter or changing light.
	# The complete real star/cloud shader and real shared cloud volumes stay bound.
	check(row.axis.is_normalized() and row.look.is_normalized(),row.name+" finite normalized axes")

func settle(frames:int=48)->void:
	for i:int in frames:await process_frame
	await Presented.drawn()

func capture(variant:String,row:Dictionary)->Dictionary:
	phase=variant+"/"+row.name+"/capture"
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),phase+" has actual viewport pixels")
	check(image.get_size()==Vector2i(1920,1080),phase+" preserves the fixed full-screen resolution")
	var prefix:=output.get_base_dir().path_join(variant+"_"+row.name)
	var png:=prefix+".png";var webp:=prefix+".webp"
	check(not FileAccess.file_exists(png) and not FileAccess.file_exists(webp),phase+" preserves fresh original artifacts")
	check(image.save_png(png)==OK,phase+" saves local lossless pixel evidence")
	check(image.save_webp(webp,true,.90)==OK,phase+" saves quality90 visual review copy")
	return {"png":png,"png_sha256":FileAccess.get_sha256(png),"webp":webp,"webp_sha256":FileAccess.get_sha256(webp),"webp_lossy":true,"webp_quality":.9,"size":[image.get_width(),image.get_height()],"format":image.get_format()}

func measure(variant:String,row:Dictionary)->Dictionary:
	phase=variant+"/"+row.name+"/steady"
	# Warm timestamps after readback and compilation; these frames are excluded
	# from measured steady work but their duration is retained separately below.
	var warm_began:=Time.get_ticks_usec();await settle(90);var warm_us:=Time.get_ticks_usec()-warm_began
	var gpu:Array=[];var cpu:Array=[];var wall:Array=[]
	var last:=Time.get_ticks_usec()
	for i:int in sample_frames:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();wall.append((now-last)/1000.);last=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	check(gpu.all(func(v):return is_finite(v) and v>0.),phase+" has valid official GPU timestamp samples")
	return {"frames":sample_frames,"gpu_ms":gpu,"cpu_ms":cpu,"frame_interval_ms":wall,"warm_us":warm_us,"clock":"official RenderingServer viewport GPU/CPU timestamps; GPU result may lag frame, constant steady input; process interval separately retained"}

func variant_pass(variant:String,path:String)->void:
	phase=variant+"/compile"
	var began:=Time.get_ticks_usec()
	var shader:=Shader.new();shader.code=FileAccess.get_file_as_string(path)
	material.shader=shader
	check(Clouds.bind(material),variant+" binds actual production 3D cloud noise volumes")
	var compile_us:=Time.get_ticks_usec()-began
	for row:Dictionary in cases():
		phase=variant+"/"+row.name+"/settle";began=Time.get_ticks_usec()
		configure(row);await settle()
		var settled_us:=Time.get_ticks_usec()-began
		var image:Dictionary=capture(variant,row)
		var benchmark:Dictionary={}
		if row.benchmark:benchmark=await measure(variant,row)
		results.append({"variant":variant,"case":row.name,"shader_sha256":FileAccess.get_sha256(path),"case_parameters":row,"initial_settle_us":settled_us,"material_assignment_us":compile_us,"image":image,"benchmark":benchmark})
		flush()
	phase=variant+"/complete";flush()

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--before-shader="):before_shader=arg.trim_prefix("--before-shader=")
		elif arg.begins_with("--after-shader="):after_shader=arg.trim_prefix("--after-shader=")
	check(not output.is_empty() and FileAccess.file_exists(before_shader) and FileAccess.file_exists(after_shader),"explicit external shader and output paths")
	if failures.size()>0:quit(2);return
	check(DisplayServer.get_name()!="headless","real GPU renderer is active")
	root.size=Vector2i(1920,1080);root.use_taa=false;root.msaa_3d=Viewport.MSAA_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	host=Node3D.new();root.add_child(host)
	camera=Camera3D.new();host.add_child(camera);camera.current=true
	environment=Environment.new();environment.background_mode=Environment.BG_SKY
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;environment.tonemap_exposure=1.;environment.glow_enabled=false;environment.fog_enabled=false
	material=ShaderMaterial.new();sky=Sky.new();sky.sky_material=material;sky.radiance_size=Sky.RADIANCE_SIZE_64;sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	environment.sky=sky;camera.environment=environment
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	report={"engine":Engine.get_version_info(),"size":[1920,1080],"frozen_star_time":123.5,"before_shader":before_shader,"after_shader":after_shader,"scope":"One original then one candidate pass, frozen full-screen sky component. Does not measure map loading/lamps/gameplay or default engine delivery. Real star/cloud includes and noise volumes; all images and compilation settle retained; steady timestamps exclude compilation and readback."}
	await variant_pass("before",before_shader)
	# The complete original path is on disk before any candidate rendering.
	await variant_pass("after",after_shader)
	phase="complete";flush();host.free();quit(0 if failures.is_empty() else 1)
