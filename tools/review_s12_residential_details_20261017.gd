extends "res://tools/review_guild_full_batch.gd"
## Isolated S12 native roundtrip + fixed gallery. Never writes a formal map/catalogue.
const SOURCE_ROOT="D:/code/rmmo_runtime/art_sources/s12_residential_details_20261017/"
const OUTPUT_ROOT="D:/code/rmmo_runtime/review_artifacts/s12_residential_details_20261017/"
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
var kind:=""
var view_filter:=PackedStringArray()
var jar_override:=""
var authoring:Dictionary={}
class EditorProbe:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass

func load_source(path:String)->Node3D:
	var d:=GLTFDocument.new();var s:=GLTFState.new()
	if d.append_from_file(path,s)!=OK:return null
	return Io.generate_scene(d,s) as Node3D

func assembly_node(parent:Node3D,id:String,path:String,anchor:Dictionary)->void:
	var node:=load_source(path)
	if not check(node!=null,"assembly import "+id):return
	parent.add_child(node);node.position=vector(anchor.position);node.rotation_degrees.y=float(anchor.get("yaw_degrees",0));node.scale=vector(anchor.get("scale",[1,1,1]))
	report.assembly_inputs.append({"id":id,"path":path,"sha256":FileAccess.get_sha256(path),"anchor":anchor})

func make_bodies(editor:Node,scene:Node)->void:
	for body:Node in editor._bodies_by_uuid.get("s12_review",[]):body.free()
	editor._bodies_by_uuid.erase("s12_review");editor._picking_shapes.clear();editor._add_bodies(scene)

func hit(scene:Node3D,a:Vector3,b:Vector3,mask:int)->Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,mask))

func functional(scene:Node3D,vp:SubViewport)->void:
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false)
	scene.set_meta("asset_uuid","s12_review");make_bodies(editor,scene)
	await physics_frame;await physics_frame
	var bodies:Array=editor._bodies_by_uuid.get("s12_review",[]);report.picking_body_count=bodies.size()
	check(not bodies.is_empty(),"native model remains editor-pickable")
	for body:StaticBody3D in bodies:
		var visual:MeshInstance3D=body.get_meta("visual");check((body.collision_layer&1)!=0,"pick mask "+str(visual.name));check(bool(body.collision_layer&Walk.WALK_MASK)==Walk.physical(visual.get_meta("extras",{})),"physical mask "+str(visual.name))
	if kind=="house":
		var descriptor:=Imported.describe(scene);check(not descriptor.is_empty(),"authored house component/region descriptor")
		report.component_descriptor=descriptor
		for x in [1.45,2.25,3.05]:
			for y in [.3,1.5,3.6]:check(not hit(scene,Vector3(x,y,9),Vector3(x,y,5.0),Walk.WALK_MASK).is_empty(),"restored solid gable behind separate yard gate "+str(Vector2(x,y)))
		var hinge_nodes:Array=[]
		for node:Node3D in scene.find_children("*","Node3D",true,false):
			if node.get_meta("extras",{}).has("rmmo_hinge"):hinge_nodes.append(node)
		check(hinge_nodes.size()==1,"one independent complete side door")
		if hinge_nodes.size()==1:
			var leaf:Node3D=hinge_nodes[0];var original:=leaf.transform;var hinge:Dictionary=leaf.get_meta("extras").rmmo_hinge
			report.door_samples=[]
			for amount in [0.0,.5,1.0]:
				leaf.transform=Fixtures.pose(original,hinge,amount);make_bodies(editor,scene);await physics_frame;await physics_frame
				var ray:=hit(scene,Vector3(5.7,1.3,4.15),Vector3(3.3,1.3,4.15),Walk.WALK_MASK)
				check(not ray.is_empty() if amount==0 else true,"closed side door blocks path")
				if amount==1:check(ray.is_empty(),"open side door clears central passage")
				report.door_samples.append({"amount":amount,"transform":var_to_str(leaf.transform),"central_ray_clear":ray.is_empty()})
			leaf.transform=original
		# Opaque walls remain physical; glass panes do not fill the window's walk mask.
		check(not hit(scene,Vector3(6,2.9,-1),Vector3(3.6,2.9,-1),Walk.WALK_MASK).is_empty(),"river solid wall physical")
	elif kind=="banner":
		check(bodies.all(func(b):return (b.collision_layer&Walk.WALK_MASK)==0),"hung cloth and brackets do not block walking")
	elif kind=="gate":
		for x in [-.8,0,.8]:
			for y in [.25,1.5,3.0]:
				for side in [-1,1]:check(hit(scene,Vector3(x,y,side*2),Vector3(x,y,-side*2),Walk.WALK_MASK).is_empty(),"freestanding gateway clear both ways "+str(Vector3(x,y,side)))
		for x in [-1.28,1.28]:check(not hit(scene,Vector3(x,1.5,2),Vector3(x,1.5,-2),Walk.WALK_MASK).is_empty(),"slender column remains physical "+str(x))
	else:
		check(not hit(scene,Vector3(0,.45,2),Vector3(0,.45,0),Walk.WALK_MASK).is_empty(),"jar body physical")
		var inside:=hit(scene,Vector3(0,1.2,0),Vector3(0,-.1,0),Walk.WALK_MASK)
		check(not inside.is_empty() and inside.position.y<.12,"jar mouth opens to real low interior floor")
		if not inside.is_empty():report.jar_cavity_floor_y=inside.position.y
	editor.free();await physics_frame

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	await functional(scene,vp)
	if kind=="house":
		report.assembly_inputs=[]
		var a:Dictionary=authoring.anchors
		assembly_node(scene,"independent_courtyard_gate",source.get_base_dir().path_join("s12_freestanding_courtyard_gate.glb"),a.courtyard_gate)
		assembly_node(scene,"reviewed_relief","D:/code/rmmo_runtime/packs/default/assets/141d49724ce3c328e913d0e7e3d6091bda06a6fb37353e0065ecd49787392434.glb",a.relief)
		for label in ["a","b"]:assembly_node(scene,"banner_"+label,source.get_base_dir().path_join("s12_red_gold_pennant_"+label+".glb"),a["banner_"+label])
		assembly_node(scene,"jar",jar_override if not jar_override.is_empty() else source.get_base_dir().path_join("s12_doorstep_jar.glb"),a.jar)
	var bounds:=scene_bounds(scene);var center:=bounds.get_center();var distance:=maxf(.8,bounds.size.length()*.5/sin(deg_to_rad(21))*1.04)
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.15,.18,.21);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.9,.94,1);environment.ambient_light_energy=.48;environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.tonemap_exposure=1.
	var world:=WorldEnvironment.new();world.environment=environment;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=150;vp.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100);ground.mesh=plane;ground.position.y=bounds.position.y-.01;var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.24,.25,.23);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	if kind=="banner":
		ground.position.y=-3.1
		var wall:=MeshInstance3D.new();wall.name="ReviewBackdrop";var cube:=BoxMesh.new();cube.size=Vector3(2.8,3.7,.10);wall.mesh=cube;wall.position=Vector3(0,-1.1,-.06);var wm:=StandardMaterial3D.new();wm.albedo_color=Color(.46,.43,.36);wm.roughness=1;wall.material_override=wm;vp.add_child(wall)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=250;vp.add_child(cam)
	var direction:=Vector3(.6,.30,1.5).normalized();var views:Array=[]
	for pair in [["near",1.0],["medium",1.8],["far",3.0]]:views.append({"name":pair[0],"eye":center+direction*distance*pair[1],"aim":center})
	views.append({"name":"back","eye":center+Vector3(-.7,.35,-1.5).normalized()*distance,"aim":center})
	if kind=="banner":
		views.append_array([{"name":"bracket","eye":Vector3(.75,.48,1.35),"aim":Vector3(.15,-.06,.23)},{"name":"cloth","eye":Vector3(.32,-.62,1.55),"aim":Vector3(.04,-.63,.45)},{"name":"wind_t1","eye":center+direction*distance,"aim":center,"time":1.0},{"name":"wind_t4","eye":center+direction*distance,"aim":center,"time":4.0}])
	elif kind=="jar":views.append_array([{"name":"rim_cavity","eye":Vector3(.80,1.23,1.25),"aim":Vector3(0,.63,0)},{"name":"top_cavity","eye":Vector3(.08,1.6,.12),"aim":Vector3(0,.60,0)},{"name":"clay_surface","eye":Vector3(.52,.65,.92),"aim":Vector3(0,.52,.22)}])
	elif kind=="gate":views.append_array([{"name":"front","eye":Vector3(0,2.8,9.5),"aim":Vector3(0,2.45,0)},{"name":"side_depth","eye":Vector3(7,4,2),"aim":Vector3(0,2.5,0)},{"name":"capital","eye":Vector3(2.6,4.1,2.0),"aim":Vector3(1.2,3.4,0)},{"name":"grazing_stone","eye":Vector3(1.9,2.6,1.5),"aim":Vector3(1.28,2.45,0)}])
	else:
		views.clear();views.append_array([{"name":"near","eye":Vector3(19,10,26),"aim":Vector3(0,4.7,0)},{"name":"medium","eye":Vector3(30,12,39),"aim":Vector3(0,4.7,0)},{"name":"far","eye":Vector3(47,17,65),"aim":Vector3(0,4.7,0)},{"name":"back","eye":Vector3(-17,10,-23),"aim":Vector3(0,4,0)},{"name":"entrance","eye":Vector3(10,4.4,10.8),"aim":Vector3(3.8,2.8,5.6)},{"name":"gable_arch","eye":Vector3(6.6,6.5,20),"aim":Vector3(1.0,5.2,6.7)},{"name":"roof_dormers","eye":Vector3(12,12,8),"aim":Vector3(2,8.1,1.4)},{"name":"side_elevation","eye":Vector3(23,6,1),"aim":Vector3(4.3,3.3,0)},{"name":"door_open","eye":Vector3(9,3,7),"aim":Vector3(4.3,1.5,4.15)},{"name":"grazing_stone","eye":Vector3(7,3.7,-.5),"aim":Vector3(4.3,2.9,-.4)}])
	if kind=="house":views.append({"name":"courtyard_gap","eye":Vector3(12,6.5,13),"aim":Vector3(2.8,2.5,7.4)})
	var wind_materials:Array=[]
	for node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		var config:Dictionary=node.get_meta("extras",{}).get("rmmo_wind",{})
		if config.is_empty():continue
		for slot in node.mesh.get_surface_count():
			var material:=Wind.make(node.get_active_material(slot),config,node.get_aabb());node.set_surface_override_material(slot,material);wind_materials.append(material)
	report.wind_surface_count=wind_materials.size();report.screenshots=[]
	if kind=="banner":check(wind_materials.size()==2,"red and gold are both cloth wind surfaces")
	for view:Dictionary in views:
		if not view_filter.is_empty() and str(view.name) not in view_filter:continue
		if kind=="banner":vp.get_node("ReviewBackdrop").visible=view.name!="back"
		var light:=Vector3(.8,.9,1.2).normalized()
		if view.name=="back":light=Vector3(-.8,.9,-1.2).normalized()
		if view.name=="grazing_stone":light=Vector3(.35,.30,1).normalized()
		sun.position=center+light*30;sun.look_at(center);cam.position=view.eye;cam.look_at(view.aim)
		for m:ShaderMaterial in wind_materials:m.set_shader_parameter("wind_velocity",Vector3(3,0,1) if view.has("time") else Vector3.ZERO);m.set_shader_parameter("wind_time",float(view.get("time",0)))
		if view.name=="door_open":
			for leaf:Node3D in scene.find_children("*","Node3D",true,false):
				var h:Dictionary=leaf.get_meta("extras",{}).get("rmmo_hinge",{})
				if not h.is_empty():leaf.transform=Fixtures.pose(leaf.transform,h,1.)
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(view.name)+".png");check(vp.get_texture().get_image().save_png(path)==OK,"capture "+str(view.name))
		report.screenshots.append({"name":view.name,"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"light":vec(light),"wind_time":view.get("time",0),"draw_calls_with_fixture":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1400,1000],"fov":42,"ambient":.48,"sun":1.5,"exposure":1,"msaa":4,"taa":false,"renderer":RenderingServer.get_current_rendering_method()};report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--kind="):kind=arg.trim_prefix("--kind=")
		if arg.begins_with("--views="):view_filter=arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--jar-source="):jar_override=arg.trim_prefix("--jar-source=")
	if DisplayServer.get_name()=="headless":print("S12_RESIDENTIAL_SYNTAX_OK");quit();return
	if not source.begins_with(SOURCE_ROOT) or not out.begins_with(OUTPUT_ROOT) or kind not in ["banner","jar","house","gate"] or FileAccess.file_exists(out.path_join("report.json")):push_error("Invalid or existing review target");quit(2);return
	if not jar_override.is_empty() and not jar_override.begins_with(SOURCE_ROOT):push_error("Invalid jar override");quit(2);return
	authoring=read_json(source.get_basename()+"_authoring.json")
	if authoring.get("sha256")!=FileAccess.get_sha256(source):push_error("Authoring source SHA mismatch");quit(2);return
	var scene:=load_source(source)
	if scene==null:quit(2);return
	await review_one(scene,{"id":authoring.id,"path":source,"sha256":authoring.sha256,"source_bytes":size_of(source)},out)
	if report.get("conservative_estimate",{}).is_empty():report.erase("conservative_estimate");report.erase("footprint_stats")
	check(report.get("gallery_completed",false),"gallery completed");check(FileAccess.get_sha256(source)==authoring.sha256,"source unchanged");check(report.generator==Compiled.generator(),"stable generator")
	report.passed=report.failures.is_empty();report.visual_review="pending actual image inspection";put(out.path_join("report.json"),report)
	print("S12_RESIDENTIAL_REVIEW_COMPLETE ",kind," passed=",report.passed);quit(0 if report.passed else 1)
