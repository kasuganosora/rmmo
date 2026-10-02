extends SceneTree
# GPU probes execute the production include, not a CPU copy of its algorithm.
var failed := 0
var viewport: SubViewport
var material: ShaderMaterial

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failed += 1

func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	if DisplayServer.get_name()=="headless":
		push_error("Use tools/run_godot_background.py: this test requires a real GPU")
		quit(2); return
	viewport=SubViewport.new(); viewport.size=Vector2i(256,256)
	viewport.use_hdr_2d=true; viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect:=ColorRect.new(); rect.size=Vector2(256,256); viewport.add_child(rect)
	material=ShaderMaterial.new(); var shader:=Shader.new()
	shader.code='''shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://scripts/world3d/star_field.gdshaderinc"
uniform int mode=0;
uniform float resolution=16.;
uniform float shift=0.;
void fragment() {
    ivec2 cell=ivec2(floor(UV*256.))-ivec2(128);
    vec2 point=vec2(star_hash(cell,13u),star_hash(cell,71u));
    vec2 p=(vec2(cell)+point)/STAR_GRID;
    vec3 direction=star_unproject(p);
    if (mode==0) {
        vec4 s=star_candidate(cell);
        COLOR=vec4(s.xy,s.z/8.,s.z>=0.?1.:0.);
    } else if (mode==1) {
        COLOR=vec4(direction.y,abs(dot(direction,normalize(vec3(.18,.45,.875)))),star_density(direction),dot(p,p)<1.?1.:0.);
    } else if (mode==2) {
        float step_size=.02/resolution;
        vec2 offset=(UV-.5)*.02-vec2(shift*step_size,0.);
        COLOR=vec4(vec3(star_psf(dot(offset,offset),step_size*step_size/12.)),1.);
    } else {
        COLOR=vec4(star_flux(1.),star_flux(6.),0.,1.);
    }
}'''
	material.shader=shader; material.set_shader_parameter("star_seed",12345678); rect.material=material
	var stars:=await capture(); var repeat:=await capture()
	check(stars.get_data()==repeat.get_data(),"GPU catalogue repeats exactly with same server seed")
	material.set_shader_parameter("star_seed",7654321)
	var other:=await capture()
	check(stars.get_data()!=other.get_data(),"another server seed changes catalogue")
	material.set_shader_parameter("star_seed",12345678); material.set_shader_parameter("mode",1)
	var geometry:=await capture()
	var bins: Array[int]=[0,0,0,0,0]; var counts: Array[int]=[0,0]; var areas: Array[int]=[0,0]
	var magnitude: Array[int]=[0,0,0]; var count:=0
	for y in range(256):
		for x in range(256):
			var g:=geometry.get_pixel(x,y)
			if g.a<.5: continue
			bins[clampi(int(g.r*5),0,4)]+=1
			var region:=0 if g.g<.15 else 1
			areas[region]+=1
			var s:=stars.get_pixel(x,y)
			if s.a<.5: continue
			count+=1; counts[region]+=1
			var mag:=s.b*8.
			magnitude[0 if mag<3. else (1 if mag<5. else 2)]+=1
	var average:=float(areas[0]+areas[1])/5.
	var equal_area:=true
	for n in bins: equal_area=equal_area and abs(n-average)/average<.025
	var density_ratio:=float(counts[0])/areas[0]/(float(counts[1])/areas[1])
	print("STATS stars=%d height_bins=%s magnitude_bins(<3,<5,>=5)=%s galactic_density_ratio=%.3f"%[count,bins,magnitude,density_ratio])
	check(equal_area,"equal solid-angle bands have equal candidate density within 2.5%")
	check(count>1400 and count<3000 and density_ratio>1.7,"density follows galaxy rather than horizon projection distortion")
	check(magnitude[2]>magnitude[1]*2 and magnitude[1]>magnitude[0]*2,"many faint stars and rare bright stars")
	material.set_shader_parameter("mode",3)
	var flux_image:=await capture(); var flux:=flux_image.get_pixel(0,0)
	check(abs(flux.r/flux.g-100.)<.2,"five magnitudes equal 100x flux in production shader")
	material.set_shader_parameter("mode",2)
	var energy: Array[float]=[]
	for size in [8,16,32,64]:
		viewport.size=Vector2i(size,size); rect.size=Vector2(size,size)
		material.set_shader_parameter("resolution",float(size))
		for shift in [0.,.25,.5,.75]:
			material.set_shader_parameter("shift",shift)
			var psf:=await capture(); var sum:=0.
			for y in range(size):
				for x in range(size): sum+=psf.get_pixel(x,y).r
			energy.append(sum*pow(.02/size,2))
	var variation:float=energy.max()/energy.min()-1.
	print("STATS filtered_flux_relative_range=%.5f"%variation)
	check(variation<.035,"stellar flux stays within 3.5% across resolution and subpixel shifts")
	viewport.queue_free()
	await sky_review()
	print("test_world3d_starfield: "+("PASS" if failed==0 else "FAIL"))
	quit(0 if failed==0 else 1)

func sky_review() -> void:
	viewport=SubViewport.new(); viewport.size=Vector2i(1280,720); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world:=WorldEnvironment.new(); world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_SKY; world.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	world.environment.sky=Sky.new(); world.environment.sky.radiance_size=Sky.RADIANCE_SIZE_64
	viewport.add_child(world)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.current=true; camera.fov=72
	camera.look_at(Vector3(-.32,.83,-.36).normalized(),Vector3.FORWARD)
	var paths: Array[String]=["res://scripts/world3d/weather_sky.gdshader"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): paths.push_front(arg.trim_prefix("--baseline="))
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	for path in paths:
		var sky_shader:=Shader.new(); sky_shader.code=FileAccess.get_file_as_string(path)
		var sky_material:=ShaderMaterial.new(); sky_material.shader=sky_shader
		var values:Dictionary={"zenith":Color(.005,.009,.022),"horizon":Color(.025,.035,.065),"cloud_tint":Color(.035,.05,.085),"cloud_cover":0.,"daylight":0.,"night_amount":1.,"star_intensity":1.7,"star_seed":12345678,"star_time":100.}
		for key in values:
			sky_material.set_shader_parameter(key,values[key])
		world.environment.sky.sky_material=sky_material
		for i in range(30): await process_frame
		var times: Array[float]=[]
		for i in range(45):
			await process_frame
			times.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		times.sort()
		var label:="after" if path.begins_with("res://") else "before"
		print("STATS sky_%s_720p_median_gpu_ms=%.4f"%[label,times[times.size()/2]])
		var rendered:=await capture()
		rendered.save_png(preload("res://scripts/asset/art_paths.gd").review_path("weather3d/starfield_%s.png"%label))
	viewport.queue_free()
