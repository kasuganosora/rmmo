extends "res://tools/arrange_town_reference_styles.gd"
const Author=preload("res://tools/arrange_bridge_grass.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Author.GRASS_OUT+"/plan.json"))
	var doc:=Doc.new();var area:=AABB(Vector3(230,-30,85),Vector3(140,70,130))
	for record:Dictionary in extras.rmmo_records:
		if Geometry.bounds([record]).intersects(area) and not record.has("building"):doc.records.append(record)
	doc.records.append_array(plan.records)
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.46,.66,.8);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.9,.94,1);env.environment.ambient_light_energy=.7;scene.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.5;sun.shadow_enabled=true;scene.add_child(sun)
	var camera:=Camera3D.new();camera.far=500;camera.fov=55;scene.add_child(camera)
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	for shot:Dictionary in [{"name":"preview_bank","eye":Vector3(0,6,19),"target":Vector3(34,0,0)},{"name":"preview_grass_close","eye":Vector3(17.5,1.4,19),"target":Vector3(29,.2,5)}]:
		camera.position=center+basis*shot.eye;camera.look_at(center+basis*shot.target)
		for i in 30:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Author.GRASS_OUT+"/"+shot.name+".png")
	scene.free();quit()
