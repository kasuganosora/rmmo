extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/house_flicker"
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	var fixed:bool="--fixed" in OS.get_cmdline_user_args()
	var path:="D:/code/rmmo_runtime/cache/world3d/house_flicker/map.gltf" if fixed else "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var doc=Doc.open_file(path);var id:="building_e5279e4cef254a55ba86";var inst:Dictionary=doc.map_meta.building_instances[id]
	var origin:=B.vec(inst.position);var yaw:=Basis(Vector3.UP,deg_to_rad(inst.yaw))
	var local:=Doc.new();local.records=doc.records.filter(func(r):return r.get("building",{}).get("id")==id).duplicate(true)
	for record:Dictionary in local.records:
		record.position=B.arr(yaw.inverse()*(B.vec(record.position)-origin));record.rotation=B.arr((yaw.inverse()*Basis.from_euler(B.vec(record.rotation)*PI/180)).get_euler()*180/PI)
	var view:=SubViewport.new();view.size=Vector2i(900,900);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var host:=Node3D.new();view.add_child(host);var scene:=local.build();host.add_child(scene);preload("res://scripts/world3d/world_stream.gd").sync(scene,host,Vector3(-5,1,-7))
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.22,.26,.25);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.8;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-140,0);view.add_child(sun)
	var camera:=Camera3D.new();view.add_child(camera);camera.near=.05;camera.far=300
	for i in 3:
		camera.position=Vector3(-5.30+i*.015,1.8,-8.1);camera.look_at(Vector3(-4.97,1.55,-6.99));camera.fov=45
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw;view.get_texture().get_image().save_png(OUT+("/fixed" if fixed else "/before")+str(i)+".png")
	print("REVIEW_DONE ","fixed" if fixed else "before");quit()
