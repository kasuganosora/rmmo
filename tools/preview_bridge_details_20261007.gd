extends "res://tools/arrange_town_reference_styles.gd"
const Author=preload("res://tools/finish_bridge_details_20261007.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Author.DETAIL_OUT+"/plan.json"))
	var doc:=Doc.new();var area:=AABB(Vector3(220,-30,85),Vector3(210,80,240))
	for r:Dictionary in plan.records:
		if Geometry.bounds([r]).intersects(area):doc.records.append(r)
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();scene.add_child(env)
	var sun:=DirectionalLight3D.new();scene.add_child(sun)
	preload("res://scripts/world3d/environment_settings.gd").apply(plan.metadata.environment,sun,env.environment)
	var camera:=Camera3D.new();camera.far=500;camera.fov=60;scene.add_child(camera)
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	for shot:Dictionary in [{"name":"preview_bridge","eye":center+basis*Vector3(4,5.2,12),"target":center+basis*Vector3(53,4,0)},{"name":"preview_street","eye":Vector3(307,3.2,160),"target":Vector3(340,3,211)},{"name":"preview_district","eye":Vector3(285,110,260),"target":Vector3(345,0,218)}]:
		camera.position=shot.eye;camera.look_at(shot.target)
		for i in 30:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(Author.DETAIL_OUT+"/"+shot.name+".png")
	scene.free();quit()
