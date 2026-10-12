extends "res://tools/test_physical_traversal.gd"
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012"
const MAP="D:/code/rmmo_runtime/cache/world3d/nonperformance_fixes_20261012/map.gltf"
var authority:RefCounted
var camera:Camera3D
func capture(label:String,eye:Vector3,target:Vector3)->void:
	camera.position=eye;camera.look_at(target)
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/access_"+label+".png")
func follow(points:Array,label:String)->void:
	var first:Array=points[0];body.position=Vector3(first[0],1.05,first[1]);body.velocity=Vector3.ZERO
	for i in 20:await move(authority,Vector3.ZERO)
	for at:Array in points.slice(1):
		var target:=Vector3(at[0],body.position.y,at[1]);var deadline:=Time.get_ticks_msec()+20000
		while Vector2(body.position.x-target.x,body.position.z-target.z).length()>.15 and Time.get_ticks_msec()<deadline:
			var direction:=target-body.position;direction.y=0
			await move(authority,direction.normalized())
		var distance:=Vector2(body.position.x-target.x,body.position.z-target.z).length()
		check(distance<.2 and body.position.y>.85 and body.position.y<1.3,label+" distance="+str(distance))
		if distance>=.2:break
func run()->void:
	create_timer(500).timeout.connect(func():print("ACCESS_RUNTIME_TIMEOUT");quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/access_result.json"))
	check(report.failures==0 and report.candidate_sha256==FileAccess.get_sha256(MAP),"candidate matches reviewed document")
	var doc=Doc.open_file(MAP);var clip:=AABB(Vector3(285,-20,155),Vector3(140,70,135))
	# A disposable exterior fixture using unchanged native geometry and physics.
	# No avatar renderer is created, and no authored map is written by this test.
	doc.records=doc.records.filter(func(r):return Geometry.bounds([r]).intersects(clip))
	host=Node3D.new();root.add_child(host);var scene:Node3D=doc.build(true);host.add_child(scene)
	var missing:=false;var collisions:=0
	for node:Node in scene.get_children():missing=missing or node.has_meta("missing_asset") or node.has_meta("paint_error")
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if Stream._make_body(host,spec)!=null:collisions+=1
	check(not missing and collisions>0,"native exterior geometry materials and collision bodies")
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.shadow_enabled=true;host.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.42,.60,.76);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;host.add_child(environment)
	camera=Camera3D.new();host.add_child(camera);camera.current=true;camera.fov=65
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);authority=Authority.new();authority.mount(body,nav,"test/residential-access");authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":0}
	await physics_frame;await physics_frame
	for path:Dictionary in (report.paths if not "--photos-only" in OS.get_cmdline_user_args() else []):
		var points:Array=path.points
		await follow(points,path.house+" outward")
		var back:=points.duplicate(true);back.reverse();await follow(back,path.house+" return")
		var a:Array=points[0];var b:Array=points[1];var at:=Vector3(a[0],0,a[1]);var direction:=(Vector3(b[0],0,b[1])-at).normalized()
		await capture(path.house,at+direction*13+Vector3(0,5,0),at+Vector3.UP*1.5)
	await capture("west_overview",Vector3(345,42,274),Vector3(335,0,240))
	await capture("east_overview",Vector3(355,45,262),Vector3(386,0,242))
	await capture("tree_window",Vector3(288,5,185),Vector3(310,3,179))
	await capture("tree_stairs",Vector3(406,18,212),Vector3(390,3,228))
	if not "--photos-only" in OS.get_cmdline_user_args():FileAccess.open(OUT+"/access_runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"passed":passed,"candidate_sha256":FileAccess.get_sha256(MAP),"fixture":"native exterior meshes and WorldStream collisions; no interior retest","collisions":collisions},"\t"))
	authority.release();host.free();print("ACCESS_RUNTIME passed=",passed," failures=",failures);quit(1 if failures else 0)
