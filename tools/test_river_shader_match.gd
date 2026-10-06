extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/river_materials"
func _init() -> void: call_deferred("run")
func run() -> void:
	create_timer(30).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(800,600)
	var doc:=Doc.new(); var id:=doc.add_box("grass",Vector3.ZERO,Vector3(16,1,16))
	var r: Dictionary=doc._find(id); r.color=[.34,.4,.23]; r.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-5,"heights":[0,0,0,0,0,0,0,0,0],"holes":[false,false,false,false]}
	var m:={"name":"solid","color":[1,1,1,1],"roughness":.9}
	r.terrain_depth_blend={"water_level":-10,"shore_start":.25,"shore_end":1.3,"rock_start":.6,"rock_end":2.2,"sand_material":m,"rock_material":m}
	var host:=Node3D.new(); root.add_child(host); var node:=doc._mesh(r); host.add_child(node)
	var sun:=DirectionalLight3D.new(); host.add_child(sun); sun.rotation_degrees=Vector3(-55,32,0)
	var cam:=Camera3D.new(); host.add_child(cam); cam.position=Vector3(0,20,.01); cam.look_at(Vector3.ZERO); cam.projection=Camera3D.PROJECTION_ORTHOGONAL; cam.size=12; cam.current=true
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(.1,.1,.1); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(.85,.88,.92); env.environment.ambient_light_energy=.55; host.add_child(env)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw; var a:=root.get_texture().get_image(); a.save_png(OUTPUT+"/dry_shader.png")
	node.set_surface_override_material(0,null)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw; var b:=root.get_texture().get_image(); b.save_png(OUTPUT+"/dry_standard.png")
	var ca:=a.get_pixel(400,300); var cb:=b.get_pixel(400,300); var delta:=(absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b))*255./3.
	print("DRY_MATCH ",ca," vs ",cb," delta ",delta)
	quit(0 if delta<1. else 1)
