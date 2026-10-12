extends "res://tools/preview_bridge_details_20261007.gd"
const SPACING_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_house_spacing_20261007"
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=30
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SPACING_OUT+"/plan.json"))
	var plan_sha:=FileAccess.get_sha256(SPACING_OUT+"/plan.json")
	check(plan.failures==0,"pose candidate passed")
	var doc:=Doc.new();var area:=AABB(Vector3(255,-20,120),Vector3(145,70,150))
	for r:Dictionary in plan.records:
		if Geometry.bounds([r]).intersects(area):doc.records.append(r)
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();scene.add_child(env)
	var sun:=DirectionalLight3D.new();scene.add_child(sun)
	preload("res://scripts/world3d/environment_settings.gd").apply(plan.metadata.environment,sun,env.environment)
	var camera:=Camera3D.new();camera.far=500;camera.fov=60;scene.add_child(camera)
	var old_origin:=Vector3(304,0,199);var basis:=Basis(Vector3.UP,PI/4)
	for shot:Dictionary in [{"name":"houses_after","eye":old_origin+basis*Vector3(-2,4,-17),"target":old_origin+basis*Vector3(0,2,-4)},{"name":"houses_overview","eye":Vector3(287,25,176),"target":Vector3(313,1,190)}]:
		camera.position=shot.eye;camera.look_at(shot.target)
		for frame in 20:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(SPACING_OUT+"/"+shot.name+".png")
	check(plan_sha==FileAccess.get_sha256(SPACING_OUT+"/plan.json"),"candidate unchanged during outdoor preview")
	FileAccess.open(SPACING_OUT+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"plan_sha256":plan_sha,"scope":"house spacing, roofs and outdoor entrance; no interior retest"},"\t"))
	scene.free();print("HOUSE_SPACING_PREVIEW failures=",failures);quit(failures)
