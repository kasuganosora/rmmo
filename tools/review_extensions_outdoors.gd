extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/editor_extensions_20261012/outdoors"
var camera:Camera3D
func _initialize()->void:run.call_deferred()
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(OUT)
	var sha:=FileAccess.get_sha256(FORMAL);var read:=Doc.authoritative_extras(FORMAL)
	if not read.has("extras"):printerr("OUTDOOR_FAILED hydrate");quit(1);return
	var doc:=Doc.new();var area:=AABB(Vector3(280,-20,128),Vector3(155,65,155))
	doc.records=read.extras.rmmo_records.filter(func(r):return Geometry.bounds([r]).intersects(area))
	var scene:=doc.build(true);root.add_child(scene)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;scene.add_child(sun)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();scene.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.42,.60,.76);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
	camera=Camera3D.new();camera.fov=65;camera.far=450;camera.current=true;scene.add_child(camera)
	var shots:Array=[
		["courtyard_front",Vector3(304,7,164),Vector3(323,1,157)],
		["courtyard_back",Vector3(336,9,137),Vector3(326,1,154)],
		["courtyard_ground",Vector3(328,44,159),Vector3(328,0,159.1)],
		["windows_and_rails",Vector3(288,5,185),Vector3(310,3,179)],
		["roof_joints",Vector3(406,18,212),Vector3(390,3,228)],
		["street_and_access",Vector3(355,45,262),Vector3(386,0,242)]]
	for shot:Array in shots:
		camera.position=shot[1];camera.look_at(shot[2]);for i in 10:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT+"/"+shot[0]+".png")
	var missing:Array=[]
	for node:Node in scene.get_children():
		if node.has_meta("missing_asset") or node.has_meta("paint_error"):missing.append(str(node.name))
	var report:={"source_sha256":sha,"source_unchanged":sha==FileAccess.get_sha256(FORMAL),"records":doc.records.size(),"shots":shots.size(),"missing":missing,"scope":"outdoor only, avatar-free; no map writes or interior retest"}
	FileAccess.open(OUT+"/review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OUTDOOR_REVIEW ",report);scene.free();quit(0 if report.source_unchanged and missing.is_empty() else 1)
