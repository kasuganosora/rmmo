extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Data=preload("res://scripts/world3d/rock_bank_mesh.gd")
const Author=preload("res://tools/arrange_bridge_terrain.gd")
const OUT=Author.OUT_BANK
var camera:Camera3D
var scene:Node3D
var failures:=0
func _initialize()->void:run.call_deferred()
func capture(label_:String,eye:Vector3,at:Vector3)->void:
	camera.position=eye;camera.look_at(at)
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+label_+".png")
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var metadata:Dictionary=Doc.authoritative_extras("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf").extras
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"));var doc:=Doc.new()
	var area:=AABB(Vector3(230,-30,85),Vector3(140,70,130))
	for record:Dictionary in metadata.rmmo_records:
		if Geometry.bounds([record]).intersects(area) and not record.has("building") and not str(record.uuid).begins_with("bridge_reference_"):doc.records.append(record)
	for r:Dictionary in plan.banks:doc.records.append(r)
	print("TERRAIN_REVIEW records=",doc.records.size());scene=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_SKY
	var sky:=Sky.new();var material:=ProceduralSkyMaterial.new();material.sky_top_color=Color(.2,.45,.7);material.sky_horizon_color=Color(.7,.83,.9);sky.sky_material=material;env.environment.sky=sky
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;env.environment.ambient_light_energy=.8;env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;scene.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.5;sun.shadow_enabled=true;scene.add_child(sun)
	camera=Camera3D.new();camera.far=500;camera.fov=60;scene.add_child(camera)
	var bridge:Dictionary=metadata.rmmo_records.filter(func(r):return r.uuid=="stone_e_0be972769041dbc9")[0]
	var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=Data.vec(bridge.position)
	await capture("terrain_bridge",center+basis*Vector3(0,6,19),center+basis*Vector3(34,0,0))
	await capture("terrain_left_bank",center+basis*Vector3(8,2,-27),center+basis*Vector3(27,0,-20))
	await capture("terrain_right_bank",center+basis*Vector3(7,2,27),center+basis*Vector3(24,0,23))
	await capture("terrain_overview",center+basis*Vector3(17,48,0),center+basis*Vector3(26,0,0))
	for record:Dictionary in plan.banks:
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=Data.mesh(record).create_trimesh_shape();body.add_child(shape);body.position=Data.vec(record.position);scene.add_child(body)
	for i in 4:await physics_frame
	var checks:Array=[]
	for record:Dictionary in plan.banks:
		var rows:=Data.sections(record);var pose:=Data.vec(record.position)
		for index in [rows.size()/3,rows.size()/2,rows.size()*2/3]:
			var row:Dictionary=rows[int(index)];var cap:Vector3=pose+row.outer.lerp(row.inner,.4)
			var hit:Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cap+Vector3.UP*3,cap+Vector3.DOWN*3))
			var ok:bool=not hit.is_empty() and absf(hit.position.y-cap.y)<.12
			if not ok:failures+=1
			checks.append({"bank":record.uuid,"cap_hit":ok})
	var report:=FileAccess.open(OUT+"/visual_collision_result.json",FileAccess.WRITE);report.store_string(JSON.stringify({"failures":failures,"checks":checks,"scope":"native local geometry, isolated daylight review; not full world validation"},"  "));report.close()
	print("BANK_VISUAL failures=",failures);scene.free();quit(failures)
