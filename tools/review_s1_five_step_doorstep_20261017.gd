extends "res://tools/review_guild_full_batch.gd"
const BASE="D:/code/rmmo_runtime/review_artifacts/s1_five_step_doorstep_20261017"
const OLD="D:/code/rmmo_runtime/packs/default/assets/0711766e3b6adb7a4f3916888e5497e6732faea878bb7eb19ea1be1ebac5e543.glb"
const NEW="D:/code/rmmo_runtime/art_sources/s1_five_step_doorstep_20261017/v1/s1_doorstep_stairs_5.glb"
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const Authority=preload("res://scripts/world3d/world_authority.gd")
var baseline:=false
class EditorProbe:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass
class Pawn extends CharacterBody3D:
	var surface_id:="stone"
	func _sense_surface()->void:pass

func physical(scene:Node3D,vp:SubViewport)->void:
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false)
	scene.set_meta("asset_uuid","stairs_review");editor._add_bodies(scene)
	await physics_frame;await physics_frame
	var bodies:Array=editor._bodies_by_uuid.get("stairs_review",[])
	check(not bodies.is_empty(),"actual editor picking bodies")
	for body:StaticBody3D in bodies:check((body.collision_layer&Walk.WALK_MASK)!=0 and (body.collision_layer&1)!=0,"rendered stone/mortar both physical and pickable")
	var space:=vp.find_world_3d().direct_space_state;report.tread_rays=[]
	for x:float in [0.,-.001,.001,-.01,.01,-.55,.55]:
		for k in 5:
			var z:float=-.2-k*.4
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,1.,z),Vector3(x,-.1,z),Walk.WALK_MASK)
			var hit:=space.intersect_ray(ray);var y:float=hit.position.y if not hit.is_empty() else -99.
			report.tread_rays.append({"x":x,"step":k+1,"hit":not hit.is_empty(),"y":y})
			if not baseline:check(absf(y-(k+1)*.16)<.006,"step support and shallow recess "+str(Vector2(x,k)))
	if baseline:report.baseline_central_through_seams=report.tread_rays.filter(func(row):return row.x==0.).all(func(row):return not row.hit)
	# Only the ground below the lowest step is a fixture. No upper platform,
	# ramp or enlarged collider supplies support through the stair route.
	var ground:=StaticBody3D.new();ground.collision_layer=Walk.WALK_MASK
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(12,.1,12);shape.shape=box;ground.add_child(shape);vp.add_child(ground);ground.position.y=-.05
	report.routes=[]
	for x:float in ([0.] if baseline else [0.,-.001,.001,-.55,.55]):
		var body:=Pawn.new();var sh:=CollisionShape3D.new();sh.name="CollisionShape3D"
		var cap:=CapsuleShape3D.new();cap.radius=.30;cap.height=1.8;sh.shape=cap;body.add_child(sh);vp.add_child(body)
		body.position=Vector3(x,.93,.50);body.floor_snap_length=.2;body.collision_layer=2;body.collision_mask=Walk.WALK_MASK
		for frame in 5:await physics_frame
		var authority:=Authority.new();authority.mount(body,null,"isolated_s12_stair_repair")
		var published:=Engine.get_physics_frames()-2
		authority.traversal_guard=func(_bounds:AABB):return {"ok":true,"physics_published_frame":published}
		var seq:=0
		for target:Vector3 in [Vector3(x,.80,-2.1),Vector3(x,0,.50)]:
			var reached:=false;var trace:Array=[]
			for tick in 250:
				await physics_frame;seq+=1
				var delta:Vector3=target-body.position;delta.y=0
				if delta.length()<.045:reached=true;break
				var moved:Dictionary=authority.move_intent(seq,delta.normalized(),minf(1.6,delta.length()*60))
				if tick%15==0:trace.append({"feet":vec(body.position-Vector3.UP*.9),"ok":moved.get("ok",false)})
			var feet:=body.position-Vector3.UP*.9
			var correct_height:=absf(feet.y-target.y)<.025
			report.routes.append({"x":x,"target":vec(target),"reached":reached,"correct_height":correct_height,"feet":vec(feet),"trace":trace})
			if not baseline:check(reached and correct_height,"production authority roundtrip "+str(target))
		authority.release();body.free();await physics_frame
	report.traversal_contract={"controller":"world_authority.gd","controller_sha":FileAccess.get_sha256("res://scripts/world3d/world_authority.gd"),"capsule_radius":.30,"capsule_height":1.8,"speed":1.6,"scope":"New independently sized rendered stone triangles used by actual editor collision; ground at base only; no invisible ramp. Finite five-lane roundtrip samples, not whole-map traversal."}
	editor.free();ground.free();await physics_frame

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	await physical(scene,vp)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.9,.94,1);env.ambient_light_energy=.48;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(50,50);floor.mesh=plane;floor.position.y=-.012
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.24,.25,.23);mat.roughness=1;floor.material_override=mat;vp.add_child(floor)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.005;cam.far=200;vp.add_child(cam)
	var views:Array=[{"name":"near","eye":Vector3(3.1,2.5,3.5),"aim":Vector3(0,.30,-.85)},{"name":"medium","eye":Vector3(5,3.5,6.8),"aim":Vector3(0,.30,-.85)},{"name":"far","eye":Vector3(8,5,11),"aim":Vector3(0,.30,-.85)},{"name":"back","eye":Vector3(-2.6,2.4,-5.2),"aim":Vector3(0,.30,-.85)},{"name":"joint","eye":Vector3(.38,.90,.25),"aim":Vector3(0,.30,-.53)},{"name":"side","eye":Vector3(3.9,.7,-.9),"aim":Vector3(0,.30,-.9)},{"name":"grazing_stone","eye":Vector3(.65,1.25,.65),"aim":Vector3(.20,.32,-.75)}]
	report.screenshots=[]
	for view:Dictionary in views:
		var light:=Vector3(.8,.9,1.2).normalized()
		if view.name=="back":light=Vector3(-.8,.9,-1.2).normalized()
		if view.name=="grazing_stone":light=Vector3(.25,.25,1).normalized()
		sun.position=Vector3(0,.3,-.85)+light*30;sun.look_at(Vector3(0,.3,-.85));cam.position=view.eye;cam.look_at(view.aim)
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(view.name+".png");check(vp.get_texture().get_image().save_png(path)==OK,"capture "+view.name)
		report.screenshots.append({"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"light":vec(light),"draw_calls_with_fixture":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1400,1000],"fov":42,"ambient":.48,"sun":1.5,"exposure":1,"msaa":4,"taa":false,"renderer":RenderingServer.get_current_rendering_method()}
	for mesh:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for slot in mesh.mesh.get_surface_count():
			var m:StandardMaterial3D=mesh.get_active_material(slot)
			check(m!=null and m.metallic==0 and not m.emission_enabled,"nonmetallic nonemissive stone/mortar")
	report.gallery_completed=true;vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("S1_FIVE_STAIRS_SYNTAX_OK");quit();return
	baseline="--baseline" in OS.get_cmdline_user_args();Engine.max_fps=120
	if DisplayServer.get_name()=="headless":quit(2);return
	var path:String=OLD if baseline else NEW;var folder:String=BASE.path_join("baseline" if baseline else "v1")
	if FileAccess.file_exists(folder.path_join("report.json")):push_error("Existing review output");quit(2);return
	var hash:=FileAccess.get_sha256(path);var d:=GLTFDocument.new();var s:=GLTFState.new()
	if d.append_from_file(path,s)!=OK:quit(2);return
	await review_one(Io.generate_scene(d,s),{"id":"s1_doorstep_stairs_5","path":path,"sha256":hash,"source_bytes":size_of(path)},folder)
	check(FileAccess.get_sha256(path)==hash,"source immutable")
	report.passed=report.failures.is_empty();report.stage="baseline defect evidence" if baseline else "candidate awaiting manual visual review";put(folder.path_join("report.json"),report)
	quit(0 if report.passed else 1)
