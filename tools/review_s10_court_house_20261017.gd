extends "res://tools/review_guild_full_batch.gd"
const Imported10=preload("res://scripts/world3d/imported_building.gd")
const Fix10=preload("res://scripts/world3d/building_fixtures.gd")
const SOURCE10="D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017/v5/s10_court_shutter_house.glb"
const OUT10="D:/code/rmmo_runtime/review_artifacts/s10_court_variants_20261017/v5/s10_court_shutter_house"
func gallery(scene:Node,folder:String)->void:
	var desc:=Imported10.describe(scene);check(not desc.is_empty(),"complete authored floor/roof/hinge descriptor")
	report.building_descriptor=desc
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.5;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.position=Vector3(-12,20,-18);sun.look_at_from_position(sun.position,Vector3.ZERO);sun.light_energy=1.4;sun.shadow_enabled=true;vp.add_child(sun)
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(150,150);ground.position.y=-.01;var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.27,.29,.27);mat.roughness=1;ground.material_override=mat;vp.add_child(ground)
	var camera:=Camera3D.new();camera.current=true;camera.fov=42;camera.near=.02;camera.far=250;vp.add_child(camera)
	var meshes:Array=scene.find_children("*","MeshInstance3D",true,false);var closed:Dictionary={};var fixtures:Dictionary={}
	for mesh:MeshInstance3D in meshes:
		closed[mesh]=mesh.transform
		var hinge:Dictionary=mesh.get_meta("extras",{}).get("rmmo_hinge",{})
		if not hinge.is_empty():
			fixtures[hinge.id]=hinge
			check(hinge.get("pivot",[]).size()==3,"hinge pivot present "+str(hinge.id))
		if mesh.get_meta("extras",{}).get("rmmo_collision","none")!="none":
			var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=mesh.mesh.create_trimesh_shape();body.add_child(shape);mesh.add_child(body)
	var entrance:="f0/north/entrance/door";check(fixtures.has(entrance),"specific moved entrance exists")
	report.door_samples=[]
	for amount in [0.,.5,1.]:
		for mesh:MeshInstance3D in meshes:
			var h:Dictionary=mesh.get_meta("extras",{}).get("rmmo_hinge",{})
			if h.get("id","")==entrance:mesh.transform=Fix10.pose(closed[mesh],h,amount-float(h.open))
		for f in 3:await physics_frame
		var space:=vp.find_world_3d().direct_space_state
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2.5,1.5,-6.8),Vector3(2.5,1.5,-4.7)))
		if amount==0:check(not hit.is_empty(),"closed entry blocks")
		if amount==1:check(hit.is_empty(),"open entry clears")
		report.door_samples.append({"amount":amount,"hit":not hit.is_empty()})
	for m:MeshInstance3D in meshes:m.transform=closed[m]
	var views:Array=[{"name":"near","eye":Vector3(14,10,-23),"aim":Vector3(0,2.8,0)},{"name":"medium","eye":Vector3(28,17,-46),"aim":Vector3(0,2.8,0)},{"name":"far","eye":Vector3(56,31,-92),"aim":Vector3(0,2.8,0)},{"name":"front","eye":Vector3(0,4,-24),"aim":Vector3(0,2.7,-3)},{"name":"back","eye":Vector3(-16,9,22),"aim":Vector3(0,2.8,0)},{"name":"door_detail","eye":Vector3(3.7,2.4,-11),"aim":Vector3(2.5,1.5,-5.4)},{"name":"shutter_detail","eye":Vector3(5.7,2.7,-10),"aim":Vector3(5,2,-5.4)},{"name":"roof_join","eye":Vector3(1.8,10,-13),"aim":Vector3(0,5,-3.2)},{"name":"door_open","eye":Vector3(3.7,2.4,-10),"aim":Vector3(2.5,1.5,-5.4)},{"name":"shutter_closed","eye":Vector3(5.7,2.7,-10),"aim":Vector3(5,2,-5.4)},{"name":"cutaway","eye":Vector3(12,15,-18),"aim":Vector3(0,1.7,0)}]
	report.screenshots=[]
	for view:Dictionary in views:
		for m:MeshInstance3D in meshes:
			m.transform=closed[m];var e:Dictionary=m.get_meta("extras",{});var h:Dictionary=e.get("rmmo_hinge",{})
			m.visible=not (view.name=="cutaway" and (int(e.rmmo_part.floor)>0 or e.rmmo_part.role in ["roof","ceiling"]))
			if not h.is_empty():
				if view.name=="door_open" and h.id==entrance:m.transform=Fix10.pose(closed[m],h,1.-float(h.open))
				if view.name=="shutter_closed" and str(h.id).begins_with("f0/north/shutter_court_window_0"):m.transform=Fix10.pose(closed[m],h,-float(h.open))
		camera.position=view.eye;camera.look_at(view.aim)
		sun.look_at_from_position(Vector3(14,17,16) if view.name=="back" else Vector3(-12,20,-18),Vector3.ZERO)
		for f in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(view.name+".png");check(vp.get_texture().get_image().save_png(path)==OK,"capture "+view.name)
		report.screenshots.append({"name":view.name,"path":path,"eye":vec(view.eye),"aim":vec(view.aim),"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1400,1000],"fov":42,"ambient":.5,"sun":1.4,"exposure":1,"msaa":4,"renderer":RenderingServer.get_current_rendering_method()};report.gallery_completed=true
	for m:MeshInstance3D in meshes:
		m.transform=closed[m];m.visible=true
		for child in m.get_children():
			if child is StaticBody3D:child.free()
	vp.remove_child(scene);vp.queue_free();await process_frame
func run()->void:
	if DisplayServer.get_name()=="headless":print("S10_SYNTAX_OK");quit();return
	if FileAccess.file_exists(OUT10+"/report.json"):quit(2);return
	var author:Dictionary=read_json(SOURCE10.get_basename()+"_authoring.json")
	check(FileAccess.get_sha256(SOURCE10)==author.sha256,"exact authoring SHA")
	var doc:=GLTFDocument.new();var state:=GLTFState.new();if doc.append_from_file(SOURCE10,state)!=OK:quit(2);return
	var scene:=Io.generate_scene(doc,state);doc=null;state=null
	await review_one(scene,{"id":author.id,"path":SOURCE10,"sha256":author.sha256,"source_bytes":size_of(SOURCE10)},OUT10)
	check(report.get("gallery_completed",false),"gallery completed");report.passed=report.failures.is_empty();put(OUT10+"/report.json",report)
	print("S10_HOUSE_REVIEW ",report.passed);quit(0 if report.passed else 1)
