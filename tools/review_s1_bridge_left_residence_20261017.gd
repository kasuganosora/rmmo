extends "res://tools/review_guild_full_batch.gd"
const SOURCE_ROOT="D:/code/rmmo_runtime/art_sources/s1_bridge_left_residence_20261017/"
const OUTPUT_ROOT="D:/code/rmmo_runtime/review_artifacts/s1_bridge_left_residence_20261017/"
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const Authority=preload("res://scripts/world3d/world_authority.gd")
var authoring:Dictionary={}
var view_filter:=PackedStringArray()
class EditorProbe:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass
class Pawn extends CharacterBody3D:
	var surface_id:="wood"
	func _sense_surface()->void:pass

func make_bodies(editor:Node,scene:Node)->void:
	for body:Node in editor._bodies_by_uuid.get("s1_review",[]):body.free()
	editor._bodies_by_uuid.erase("s1_review");editor._picking_shapes.clear();editor._add_bodies(scene)

func hit(scene:Node3D,a:Vector3,b:Vector3,mask:int)->Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,mask))

func functional(scene:Node3D,vp:SubViewport)->void:
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false)
	scene.set_meta("asset_uuid","s1_review");make_bodies(editor,scene);await physics_frame;await physics_frame
	var bodies:Array=editor._bodies_by_uuid.get("s1_review",[]);report.picking_body_count=bodies.size()
	check(not bodies.is_empty(),"production editor picking bodies")
	for body:StaticBody3D in bodies:
		var visual:MeshInstance3D=body.get_meta("visual");check((body.collision_layer&1)!=0,"pick mask "+str(visual.name));check(bool(body.collision_layer&Walk.WALK_MASK)==Walk.physical(visual.get_meta("extras",{})),"physical mask "+str(visual.name))
	var descriptor:=Imported.describe(scene);report.component_descriptor=descriptor;check(not descriptor.is_empty(),"authored building regions/component descriptor")
	var leaves:Array=[]
	for node:Node3D in scene.find_children("*","Node3D",true,false):
		if node.get_meta("extras",{}).has("rmmo_hinge"):leaves.append(node)
	check(leaves.size()==1,"one complete independent entrance door")
	report.door_samples=[]
	if leaves.size()==1:
		var leaf:Node3D=leaves[0];var original:=leaf.transform;var h:Dictionary=leaf.get_meta("extras").rmmo_hinge
		for amount in [0.,.5,1.]:
			leaf.transform=Fixtures.pose(original,h,amount);make_bodies(editor,scene);await physics_frame;await physics_frame
			var ray:=hit(scene,Vector3(.6,1.5,8.4),Vector3(.6,1.5,5.9),Walk.WALK_MASK)
			check(not ray.is_empty() if amount==0 else true,"closed door blocks entry")
			if amount==1:check(ray.is_empty(),"open door clears entry")
			report.door_samples.append({"amount":amount,"transform":var_to_str(leaf.transform),"central_ray_clear":ray.is_empty()})
		leaf.transform=Fixtures.pose(original,h,1.);make_bodies(editor,scene);await physics_frame;await physics_frame
	for p in [Vector3(-2,2,8),Vector3(0,5,8)]:check(not hit(scene,p,p-Vector3(0,0,2),Walk.WALK_MASK).is_empty(),"front wall physical "+str(p))
	check(hit(scene,Vector3(0,8.3,8),Vector3(0,8.3,6),Walk.WALK_MASK).is_empty(),"tall window is a genuine through-opening")
	if authoring.anchors.has("foundation_bottom_y"):
		for x in [-3.,0.,3.]:check(not hit(scene,Vector3(x,-.6,8),Vector3(x,-.6,6),Walk.WALK_MASK).is_empty(),"front below-ground foundation continuous "+str(x))
		for x in [-5.,5.]:check(not hit(scene,Vector3(x,-.6,0),Vector3(signf(x)*3.5,-.6,0),Walk.WALK_MASK).is_empty(),"side below-ground foundation continuous "+str(x))
	# Finite real-controller path samples cover both new stairs and doorway.
	var floor:=StaticBody3D.new();floor.collision_layer=Walk.WALK_MASK
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,.1,30);shape.shape=box;floor.add_child(shape);vp.add_child(floor);floor.position.y=-.05
	report.routes=[]
	var routes:Array=[{"name":"entry","start":Vector3(.60,0,8.5),"goals":[Vector3(.60,.16,5.8),Vector3(.60,0,8.5)]},{"name":"ground_upper","start":Vector3(-2.8,.16,3.6),"goals":[Vector3(-2.8,3.25,-3.65),Vector3(-2.8,.16,3.6)]},{"name":"upper_loft","start":Vector3(.9,3.25,-3.7),"goals":[Vector3(.9,6.50,3.6),Vector3(.9,3.25,-3.7)]}]
	for row:Dictionary in routes:
		var pawn:=Pawn.new();var sh:=CollisionShape3D.new();sh.name="CollisionShape3D";var cap:=CapsuleShape3D.new();cap.radius=.30;cap.height=1.8;sh.shape=cap;pawn.add_child(sh);vp.add_child(pawn)
		pawn.position=row.start+Vector3.UP*.92;pawn.floor_snap_length=.2;pawn.collision_layer=2;pawn.collision_mask=Walk.WALK_MASK
		for frame in 5:await physics_frame
		var authority:=Authority.new();authority.mount(pawn,null,"isolated_s1_house");var published:=Engine.get_physics_frames()-2
		authority.traversal_guard=func(_bounds:AABB):return {"ok":true,"physics_published_frame":published}
		var seq:=0
		for target:Vector3 in row.goals:
			var reached:=false;var trace:Array=[]
			for tick in 390:
				await physics_frame;seq+=1;var delta:Vector3=target-pawn.position;delta.y=0
				if delta.length()<.06:reached=true;break
				var moved:Dictionary=authority.move_intent(seq,delta.normalized(),minf(2.2,delta.length()*60))
				if tick%30==0:trace.append({"feet":vec(pawn.position-Vector3.UP*.9),"ok":moved.get("ok",false)})
			var feet:=pawn.position-Vector3.UP*.9;var correct_height:=absf(feet.y-target.y)<.04
			report.routes.append({"name":row.name,"target":vec(target),"reached":reached,"correct_height":correct_height,"feet":vec(feet),"trace":trace});check(reached and correct_height,"production traversal "+str(row.name)+" "+str(target))
		authority.release();pawn.free();await physics_frame
	report.traversal_contract={"controller_sha":FileAccess.get_sha256("res://scripts/world3d/world_authority.gd"),"capsule_radius":.30,"capsule_height":1.8,"speed":2.2,"scope":"Actual triangle colliders, six finite entrance/stair route samples; no invisible ramps."}
	if leaves.size()==1:
		var leaf:Node3D=leaves[0];var h:Dictionary=leaf.get_meta("extras").rmmo_hinge;leaf.transform=Fixtures.pose(leaf.transform,h,-1.)
	editor.free();floor.free();await physics_frame

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(scene)
	await functional(scene,vp)
	if authoring.anchors.has("foundation_bottom_y"):
		var stairs_path:="D:/code/rmmo_runtime/art_sources/s1_five_step_doorstep_20261017/v1/s1_doorstep_stairs_5.glb"
		var d:=GLTFDocument.new();var s:=GLTFState.new();check(d.append_from_file(stairs_path,s)==OK,"separate five-step assembly import")
		var stairs:=Io.generate_scene(d,s) as Node3D;scene.add_child(stairs);stairs.position=Vector3(.6,-.72,9.84)
		report.assembly_inputs=[{"id":"s1_doorstep_stairs_5","path":stairs_path,"sha256":FileAccess.get_sha256(stairs_path),"position":[.6,-.72,9.84],"scope":"Separate instance, top 8cm below existing threshold; not embedded in house GLB"}]
		await approach(scene,vp)
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.15,.18,.21);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.9,.94,1);environment.ambient_light_energy=.48;environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.tonemap_exposure=1.
	var world:=WorldEnvironment.new();world.environment=environment;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=180;vp.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(150,150);ground.mesh=plane;ground.position.y=float(authoring.anchors.get("foundation_bottom_y",0))-.01;var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.24,.25,.23);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=250;vp.add_child(cam)
	var views:Array=[{"name":"near","eye":Vector3(-18,9,28),"aim":Vector3(0,5.8,0)},{"name":"medium","eye":Vector3(-30,11,46),"aim":Vector3(0,5.8,0)},{"name":"far","eye":Vector3(-48,16,75),"aim":Vector3(0,5.8,0)},{"name":"back","eye":Vector3(18,10,-26),"aim":Vector3(0,5.5,0)},{"name":"front","eye":Vector3(0,7,26),"aim":Vector3(0,6.0,7)},{"name":"entrance","eye":Vector3(4,3.7,14),"aim":Vector3(.6,1.75,7)},{"name":"roof_eave","eye":Vector3(-10,10,13),"aim":Vector3(-3.5,7.3,5.9)},{"name":"roof_tiles","eye":Vector3(-6.8,11,4),"aim":Vector3(-2.9,8.1,3.4)},{"name":"grazing_stone","eye":Vector3(3.3,4.6,10),"aim":Vector3(1.6,4.0,7.18)},{"name":"door_open","eye":Vector3(1.8,2.2,11),"aim":Vector3(.6,1.5,6.7)},{"name":"loft","eye":Vector3(1.5,8.2,5),"aim":Vector3(0,8.8,-2)},{"name":"floor_cutaway","eye":Vector3(9,14,17),"aim":Vector3(0,3,0)}]
	report.screenshots=[]
	if authoring.anchors.has("foundation_bottom_y"):
		views.append({"name":"foundation","eye":Vector3(-8,1.7,12),"aim":Vector3(-2,-.25,6.8)})
		views.append({"name":"five_step_approach","eye":Vector3(4.5,2.5,15),"aim":Vector3(.6,.75,8.1)})
	for view:Dictionary in views:
		if not view_filter.is_empty() and str(view.name) not in view_filter:continue
		var light:=Vector3(-.8,.9,1.2).normalized()
		if view.name=="back":light=Vector3(.8,.9,-1.2).normalized()
		if view.name in ["roof_tiles","grazing_stone"]:light=Vector3(-1,.45,.23).normalized()
		sun.position=Vector3(0,6,0)+light*30;sun.look_at(Vector3(0,6,0));cam.position=view.eye;cam.look_at(view.aim)
		for node:Node3D in scene.find_children("*","Node3D",true,false):
			var e:Dictionary=node.get_meta("extras",{});var part:Dictionary=e.get("rmmo_part",{})
			node.visible=not(view.name=="floor_cutaway" and (int(part.get("floor",0))>0 or part.get("role","")=="roof"))
			var h:Dictionary=e.get("rmmo_hinge",{})
			if not h.is_empty():
				if not node.has_meta("review_closed"):node.set_meta("review_closed",node.transform)
				node.transform=Fixtures.pose(node.get_meta("review_closed"),h,1. if view.name=="door_open" else 0.)
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(view.name)+".png");check(vp.get_texture().get_image().save_png(path)==OK,"capture "+str(view.name))
		report.screenshots.append({"name":view.name,"path":path,"sha256":FileAccess.get_sha256(path),"eye":vec(cam.position),"aim":vec(view.aim),"light":vec(light),"draw_calls_with_fixture":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1400,1000],"fov":42,"ambient":.48,"sun":1.5,"exposure":1,"msaa":4,"taa":false,"renderer":RenderingServer.get_current_rendering_method()};report.gallery_completed=true;vp.remove_child(scene);vp.queue_free();await process_frame

func approach(scene:Node3D,vp:SubViewport)->void:
	var originals:Dictionary={}
	for node:Node3D in scene.find_children("*","Node3D",true,false):
		var h:Dictionary=node.get_meta("extras",{}).get("rmmo_hinge",{})
		if not h.is_empty():originals[node]=node.transform;node.transform=Fixtures.pose(node.transform,h,1.)
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false);make_bodies(editor,scene)
	var ground:=StaticBody3D.new();ground.collision_layer=Walk.WALK_MASK;var cs:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,.1,30);cs.shape=box;ground.add_child(cs);vp.add_child(ground);ground.position.y=-.77
	var pawn:=Pawn.new();var sh:=CollisionShape3D.new();sh.name="CollisionShape3D";var cap:=CapsuleShape3D.new();cap.radius=.30;cap.height=1.8;sh.shape=cap;pawn.add_child(sh);vp.add_child(pawn)
	pawn.position=Vector3(.6,.20,10.5);pawn.floor_snap_length=.2;pawn.collision_layer=2;pawn.collision_mask=Walk.WALK_MASK
	for frame in 5:await physics_frame
	var authority:=Authority.new();authority.mount(pawn,null,"isolated_s1_approach");var published:=Engine.get_physics_frames()-2
	authority.traversal_guard=func(_bounds:AABB):return {"ok":true,"physics_published_frame":published}
	var seq:=0;report.approach_routes=[]
	for target in [Vector3(.6,.16,5.8),Vector3(.6,-.72,10.5)]:
		var reached:=false
		for tick in 270:
			await physics_frame;seq+=1;var delta:Vector3=target-pawn.position;delta.y=0
			if delta.length()<.06:reached=true;break
			authority.move_intent(seq,delta.normalized(),minf(2.2,delta.length()*60))
		var feet:=pawn.position-Vector3.UP*.9;var ok:=reached and absf(feet.y-target.y)<.04
		report.approach_routes.append({"target":vec(target),"feet":vec(feet),"passed":ok});check(ok,"five steps / threshold / interior connected "+str(target))
	authority.release();pawn.free();editor.free();ground.free()
	for node:Node3D in originals:node.transform=originals[node]
	await physics_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--views="):view_filter=arg.trim_prefix("--views=").split(",")
	if DisplayServer.get_name()=="headless":print("S1_RESIDENCE_SYNTAX_OK");quit();return
	if not source.begins_with(SOURCE_ROOT) or not out.begins_with(OUTPUT_ROOT) or FileAccess.file_exists(out.path_join("report.json")):push_error("Invalid or existing review target");quit(2);return
	authoring=read_json(source.get_basename()+"_authoring.json")
	if authoring.get("sha256")!=FileAccess.get_sha256(source):push_error("Source SHA mismatch");quit(2);return
	var d:=GLTFDocument.new();var s:=GLTFState.new()
	if d.append_from_file(source,s)!=OK:quit(2);return
	await review_one(Io.generate_scene(d,s),{"id":authoring.id,"path":source,"sha256":authoring.sha256,"source_bytes":size_of(source)},out)
	check(report.get("gallery_completed",false),"gallery completed");check(FileAccess.get_sha256(source)==authoring.sha256,"source unchanged");check(report.generator==Compiled.generator(),"stable generator")
	report.passed=report.failures.is_empty();report.visual_review="pending actual image inspection";put(out.path_join("report.json"),report);print("S1_RESIDENCE_COMPLETE passed=",report.passed);quit(0 if report.passed else 1)
