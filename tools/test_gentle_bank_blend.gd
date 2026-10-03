extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain"
var failed:=0
var camera: Camera3D
func _init() -> void: run.call_deferred()
func check(ok: bool,label_: String) -> void:
	print(("PASS " if ok else "FAIL ")+label_)
	if not ok: failed+=1
func shot() -> Image:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func pixel(image: Image,x: float,z: float) -> Color:
	var p:=camera.unproject_position(Vector3(x,x*.25-1.,z))
	return image.get_pixel(roundi(p.x),roundi(p.y))
func run() -> void:
	create_timer(60).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1024,768); root.content_scale_size=root.size
	var doc:=Doc.new(); var id:=doc.add_box("grass",Vector3.ZERO,Vector3(32,1,24)); var r: Dictionary=doc._find(id)
	var heights: Array=[]; var holes: Array=[]; holes.resize(32*24); holes.fill(false)
	for z in 25:
		for x in 33: heights.append((x-16.)*.25-1.)
	r.terrain_mesh={"version":1,"columns":32,"rows":24,"floor":-12.,"heights":heights,"holes":holes}
	var m:={"name":"diagnostic","color":[1,1,1,1],"roughness":1.}
	r.terrain_depth_blend={"water_level":0.,"shore_start":.15,"shore_end":.9,"rock_start":.6,"rock_end":2.2,"bank_profile":"natural","sand_material":m,"rock_material":m,"transition_material":m,"transition_width":2.,"edge_noise":.7,"height_blend_strength":0.}
	var mesh:=doc._mesh(r); root.add_child(mesh)
	var material: ShaderMaterial=mesh.get_active_material(0)
	# Read actual GPU coverage independently of the PBR textures/lighting.
	var debug:=Shader.new(); debug.code=material.shader.code.replace("specular_schlick_ggx;","specular_schlick_ggx, unshaded;").replace("NORMAL=normalize((VIEW_MATRIX*vec4(surface,0.)).xyz);","ALBEDO=weights.xyw;")
	material.shader=debug
	camera=Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,30,.001); camera.look_at(Vector3.ZERO); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=32.; camera.current=true
	var noisy:=await shot(); noisy.save_png(OUTPUT.path_join("gentle_weights.png"))
	check(pixel(noisy,12,0).r>.98 and pixel(noisy,12,0).b<.01,"dry plateau remains grass")
	check(pixel(noisy,-12,0).r<.01 and pixel(noisy,-12,0).b<.01,"deep bed never acquires grass or shoreline soil")
	check(pixel(noisy,6.1,0).b>.5,"gentle shore exposes transition soil without a steep cliff")
	var low:=1.; var high:=0.
	for z in range(-8,9): low=minf(low,pixel(noisy,6.1,z).r); high=maxf(high,pixel(noisy,6.1,z).r)
	check(high-low>.04,"equal-height shoreline varies in world space")
	material.set_shader_parameter("edge_noise",0.)
	var smooth:=await shot(); low=1.; high=0.
	for z in range(-8,9): low=minf(low,pixel(smooth,6.1,z).r); high=maxf(high,pixel(smooth,6.1,z).r)
	check(high-low<.015,"zero edge noise is deterministic and restores a straight boundary")
	material.set_shader_parameter("height_blend_strength",.0001)
	var tiny:=await shot(); var delta:=0.
	for x in [5.,5.5,6.,6.5,7.]:
		var a:=pixel(smooth,x,0); var b:=pixel(tiny,x,0)
		delta=maxf(delta,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	check(delta<.01,"near-zero height strength does not abruptly sharpen the boundary")
	material.set_shader_parameter("transition_width",0.)
	var disabled:=await shot(); check(pixel(disabled,6.1,0).b<.01,"zero transition width disables shoreline soil")
	material.set_shader_parameter("transition_width",2.); material.set_shader_parameter("slope_aware",false)
	var legacy:=await shot(); check(pixel(legacy,6.1,0).b<.01,"legacy depth profile remains unchanged")
	var file:=FileAccess.open(OUTPUT.path_join("gentle_result.json"),FileAccess.WRITE); file.store_string(JSON.stringify({"failures":failed})); file.close()
	quit(1 if failed else 0)
