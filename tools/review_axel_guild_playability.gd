extends "res://tools/review_axel_guild_whitebox.gd"
## Offline asset review with production motion authority and camera collision.
## No editor/catalog/map mutation. Navigation baking and door interaction are separate.
var CURRENT_OUT := "D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v2"
const Authority = preload("res://scripts/world3d/world_authority.gd")
const CameraRig = preload("res://scripts/world3d/third_person_camera.gd")
class ReviewActor extends CharacterBody3D:
	var surface_id := "guild_review"
	func _sense_surface(): pass
class FloorGate extends Node3D:
	var ready_for_queries := true
	var exclude: Array[RID] = []
	func near_surface(point: Vector3, _flat: float, vertical: float) -> bool:
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*vertical)
		query.exclude=exclude
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		return not hit.is_empty() and hit.normal.y>.65
var actor: ReviewActor
var rig: Node3D
var authority: RefCounted
var space: PhysicsDirectSpaceState3D
var tick_id := 0
var camera_samples := 0
var camera_errors: Array = []
var min_arm := INF
var route_results: Array = []
var orbit_results: Array = []
var snapshot_names: Array = []

func run() -> void:
	var landmark_v12 := "--landmarks-v12" in OS.get_cmdline_user_args()
	var landmark_review := "--landmarks-v11" in OS.get_cmdline_user_args() or landmark_v12
	var exterior_review := "--exterior-v10" in OS.get_cmdline_user_args()
	var statue_review := "--statue-v9" in OS.get_cmdline_user_args()
	var panel_review := "--panels" in OS.get_cmdline_user_args() or statue_review or landmark_review
	var furniture_review := "--furniture" in OS.get_cmdline_user_args()
	var furnishings_review := "--furnishings" in OS.get_cmdline_user_args()
	var textiles_review := "--textiles-sanitary" in OS.get_cmdline_user_args()
	var guestroom_review := "--guestroom" in OS.get_cmdline_user_args()
	var layout_review := "--layout-v8" in OS.get_cmdline_user_args()
	furniture_review = furniture_review or furnishings_review or textiles_review or guestroom_review or layout_review
	if panel_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v3"
	if furniture_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v4"
	if furnishings_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v5"
	if textiles_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v6"
	if guestroom_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v7"
	if layout_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v8"
	if statue_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v9"
	if exterior_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v10"
	if landmark_review: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v11"
	if landmark_v12: CURRENT_OUT="D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v12"
	root.size=Vector2i(1280,800)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CURRENT_OUT+"/manifest.json"))
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	check(doc.append_from_file(CURRENT_OUT+"/axel_guild_whitebox.glb",state)==OK,"GLB load")
	var scene:=doc.generate_scene(state)
	if scene==null:quit(1);return
	if panel_review or furniture_review or exterior_review:
		# GLTFDocument's scene generation does not flatten authored extras into
		# Node metadata. Bind from the parsed file, before interpreting collisions.
		for index in state.json.get("nodes",[]).size():
			var mapped:Node=state.get_scene_node(index)
			if mapped==null:continue
			var authored:Dictionary=state.json.nodes[index].get("extras",{})
			for key:String in authored:mapped.set_meta(key,authored[key])
	root.add_child(scene)
	if exterior_review:
		var balcony_hinges := 0
		for candidate in scene.find_children("*","Node3D",true,false):
			if candidate.has_meta("open_angle_degrees"):
				balcony_hinges += 1
				candidate.rotation.y = deg_to_rad(float(candidate.get_meta("open_angle_degrees",0.0)))
		check(balcony_hinges==2,"two operable balcony hinge groups")
	collisions(scene)
	var base:=StaticBody3D.new();var bs:=CollisionShape3D.new();var box:=BoxShape3D.new()
	box.size=Vector3(100,.2,100);bs.shape=box;base.add_child(bs);base.position=Vector3(16,-.42,-7);scene.add_child(base)
	for child in scene.find_children("*","MeshInstance3D",true,false):
		if semantic(child).begins_with("60_"):child.visible=false
		for body in child.get_children():
			if body is StaticBody3D:
				body.set_meta("semantic_group",semantic(child))
				if semantic(child).begins_with("33_") or semantic(child).begins_with("50_") or semantic(child).begins_with("51_"):body.collision_layer=3
	actor=ReviewActor.new();actor.floor_snap_length=.2
	var shape:=CollisionShape3D.new();shape.name="CollisionShape3D"
	var cap:=CapsuleShape3D.new();cap.height=2.1;cap.radius=.3;shape.shape=cap;shape.position.y=.15;actor.add_child(shape);root.add_child(actor)
	# Visible dimensional avatar: full-size capsule, not a shrunken character.
	var avatar:=MeshInstance3D.new();var cm:=CapsuleMesh.new();cm.height=2.1;cm.radius=.3;avatar.mesh=cm;avatar.position.y=.15
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.7,.3,.12);avatar.material_override=mat;actor.add_child(avatar)
	var nav:=FloorGate.new();root.add_child(nav);nav.exclude=[actor.get_rid()]
	authority=Authority.new();authority.mount(actor,nav,"offline_guild_review")
	rig=CameraRig.new();var cam:=Camera3D.new();cam.name="Camera3D";cam.current=true;cam.fov=55;cam.near=.05;rig.add_child(cam);root.add_child(rig)
	rig.actor_height=2.1;rig.distance=3.2;rig._want_distance=3.2;rig.indoor_distance=3.2;rig.exclude_body(actor.get_rid())
	# Physical ceilings stay visible/collidable. This test does not fake cutaway.
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.6,.66,.71)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.85,.89,1);environment.environment.ambient_light_energy=.85;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.8;sun.shadow_enabled=true;root.add_child(sun)
	for p in [Vector3(16,7,-6),Vector3(26.4,7.7,-6),Vector3(5,7.7,-6),Vector3(25,3.7,-8)]:
		var light:=OmniLight3D.new();light.position=p;light.omni_range=13;light.light_energy=1.4;root.add_child(light)
	for frame in 5:await physics_frame
	space=scene.get_world_3d().direct_space_state
	var headroom:Dictionary={} if panel_review or furniture_review or exterior_review else scan_headroom()
	var doors:Dictionary={} if panel_review or furniture_review or exterior_review else scan_doors(data.rooms)
	if "--normal-views" in OS.get_cmdline_user_args():
		await capture_normal_views()
		var view_report:={"failures":failures,"camera_errors":camera_errors,"screenshots":snapshot_names,
			"glb_sha256":FileAccess.get_sha256(CURRENT_OUT+"/axel_guild_whitebox.glb"),"fov":55,"cutaway":false}
		var vf:=FileAccess.open(CURRENT_OUT+"/normal_view_review.json",FileAccess.WRITE);vf.store_string(JSON.stringify(view_report,"  "));vf.close()
		quit(0 if failures.is_empty() and camera_errors.is_empty() else 1);return
	for route_name:String in data.route_probes_xyz_blender:
		if exterior_review and route_name not in ["main_entry_to_reception","entry_to_stair","meeting_access","balcony_access"]:continue
		if layout_review and route_name not in ["main_entry_to_reception","entry_to_stair","stair","reception_staff"]:continue
		if guestroom_review:continue # Dedicated approaches below cover all four changed rooms.
		if panel_review and route_name not in ["entry_to_stair","main_entry_to_reception","reception_staff"]:continue
		if furniture_review and not textiles_review and not layout_review and route_name in ["stair","upper_main","washroom"]:continue
		if textiles_review and route_name not in ["washroom","main_entry_to_reception"]:continue
		if furnishings_review and float(data.route_probes_xyz_blender[route_name][0][2])>2.0:continue
		for reverse in [false,true]:
			var points:Array=data.route_probes_xyz_blender[route_name].duplicate(true)
			if reverse:points.reverse()
			await walk_route(route_name,points,reverse)
	# Continuous five-degree orbit, including the camera's allowed extreme pitches.
	var stations:={"entrance":[16,1.8,0],"hall":[21,6,0],"reception":[24,8.3,0],
		"stair_middle":[7.05,9.95,2.24],"landing":[1.7,9.95,4.48],"rear_gallery":[16,12.25,4.48],
		"office_corridor":[1.7,6,4.48],"guest_corridor":[26.4,6.5,4.48],
		"single_room":[23.8,1.7,4.48],"twin_room":[29.1,1.7,4.48],"office":[4.3,5.75,4.48]}
	if panel_review:
		stations={"panel_front":[16,5.0,0],"panel_left_passage":[14.45,7.5,0],"panel_right_passage":[17.55,7.5,0]}
		var panel_roots:Array=[]
		for candidate in scene.find_children("*","Node3D",true,false):
			if candidate.get_meta("asset_id","")=="guild_statue_decorative_panel":panel_roots.append(candidate)
		check(panel_roots.size()==2,"two independent decorative panel roots survive GLB")
		for node:Node3D in panel_roots:
			check(not bool(node.get_meta("structural_wall",true)),"decorative panel is not a structural wall")
		check(scene.find_children("*Statue_screen_independent_envelope*","Node3D",true,false).is_empty(),"old box panels removed")
		await walk_route("behind_panels",[[19.5,9.2,0],[16,9.2,0],[13.5,9.2,0]],false)
		await walk_route("behind_panels",[[13.5,9.2,0],[16,9.2,0],[19.5,9.2,0]],true)
		if statue_review:
			var imported:Array=[]
			for candidate in scene.find_children("*","Node3D",true,false):
				if candidate.get_meta("asset_id","")=="guild_fab_knight_statue":imported.append(candidate)
			check(imported.size()==1,"exactly one independent Fab statue root")
			if imported.size()==1:
				check(imported[0].find_children("*","MeshInstance3D",true,false).size()==2,"separate statue and sword meshes")
	if furniture_review:
		if furnishings_review:
			await walk_route("quest_board_approach",[[12,11.65,0],[14,11.65,0],[16,11.2,0]],false)
			await walk_route("quest_board_approach",[[12,11.65,0],[14,11.65,0],[16,11.2,0]],true)
		stations={"panel_front":[16,5,0],"panel_left_passage":[14.45,7.5,0],
			"single_room":[23.8,1.7,4.48],"twin_room":[29.1,1.7,4.48],"office":[4.3,5.75,4.48]}
		if furnishings_review:
			stations={"quest_board":[16,11.2,0],"registration_crystal":[23.3,9.2,0],"dining":[9,5.7,0],"entry_planters":[16,2.8,0]}
		if textiles_review:
			stations={"washroom_circulation":[29.1,11.1,4.48],"washbasins":[30.35,10.75,4.48],"hanging_textiles":[16,4.8,0]}
			for reversed in [false,true]:
				var shower_points:Array=[[29.0,10.9,4.48],[28.7,11.8,4.48],[28.7,12.55,4.53]]
				var privy_points:Array=[[29.0,10.9,4.48],[30.5,11.3,4.48],[30.5,11.95,4.48]]
				if reversed:shower_points.reverse();privy_points.reverse()
				await walk_route("shower_access",shower_points,reversed)
				await walk_route("privy_access",privy_points,reversed)
		if guestroom_review:
			stations={"single_room":[23.10,2.9,4.48],"twin_room":[29.6,3.0,4.48]}
			for offset in [0.0,4.1]:
				for reversed in [false,true]:
					var single:Array=[[26.4,1.2+offset,4.48],[24.2,1.2+offset,4.48],[23.8,1.75+offset,4.48],[23.2,1.85+offset,4.48],[23.10,2.9+offset,4.48]]
					var twin:Array=[[26.4,1.2+offset,4.48],[28.60,1.2+offset,4.48],[29.30,1.85+offset,4.48],[29.60,2.10+offset,4.48],[29.6,3.0+offset,4.48]]
					if reversed:single.reverse();twin.reverse()
					await walk_route("guest_single_"+str(offset),single,reversed)
					await walk_route("guest_twin_"+str(offset),twin,reversed)
		if layout_review:
			stations={"quest_board":[23.7,8.05,0],"registration_crystal":[24.65,9.2,0],
				"statue_left_passage":[14.45,7.5,0],"statue_right_passage":[17.55,7.5,0],
				"stair_middle":[7.05,9.95,2.24],"landing":[1.7,9.95,4.48],"hanging_silhouettes":[16,4.8,0]}
			for reversed in [false,true]:
				var board_route:Array=[[24,5.5,0],[24,7,0],[23.7,8.05,0],[24.65,9.2,0]]
				if reversed:board_route.reverse()
				await walk_route("quest_to_registration",board_route,reversed)
		var count:=0
		for candidate in scene.find_children("*","Node3D",true,false):
			if str(candidate.get_meta("asset_source","")).begins_with("../furniture_v1/") or str(candidate.get_meta("asset_source","")).begins_with("../furnishings_v1/") or str(candidate.get_meta("asset_source","")).begins_with("../textiles_sanitary_v1/") or str(candidate.get_meta("asset_source","")).begins_with("../guestroom_v1/"):
				count+=1
				check(bool(candidate.get_meta("independent_prop",false)),"furniture independent root")
		check(count==data.furniture_instances.size(),"all furniture roots preserved")
	if exterior_review:
		stations={"entry_under_gallery":[16,1.6,0],"balcony_gallery":[11.8,1.6,4.48],"balcony_door":[16,1.5,4.48],"balcony_platform":[14.1,-1.2,4.48]}
	if landmark_review:
		stations={"skeleton_front":[16,4.8,0],"skeleton_left":[14.45,7.5,0],"skeleton_rear_gallery":[16,12.25,4.48]}
	for label:String in stations:
		await orbit_station(label,from_blender(stations[label]))
	check(camera_errors.is_empty(),"camera sphere/visibility checks")
	check(triangles==int(data.triangles_evaluated),"export triangles match manifest")
	var result:={"failures":failures,"glb_sha256":FileAccess.get_sha256(CURRENT_OUT+"/axel_guild_whitebox.glb"),
		"actor":{"height":2.1,"radius":.3,"origin_height":.9},"camera":{"distance":3.2,"fov":55,"sphere_radius":.2,"cutaway":false},
		"headroom":headroom,"door_probes":doors,"routes":route_results,"orbits":orbit_results,
		"camera_samples":camera_samples,"minimum_camera_arm":min_arm,"camera_errors":camera_errors,"screenshots":snapshot_names,
		"limitations":["Uses production WorldAuthority movement and ThirdPersonCamera, with a ray-based floor gate; no baked navmesh/click navigation.",
		"Doors remain authored open; active fixture, floor cutaway, batching and editor save/reopen are not yet integrated.",
		"Close side-on cameras are expected in rooms/corridors; no guarantee of full 3.2m orbit in all directions."]}
	result["scope"]="changed decorative panels and ground-floor routes only" if panel_review else "full building"
	var filename:="panel_playability_review.json" if panel_review else "playability_review.json"
	if furniture_review:
		result["scope"]="furniture replacement routes and camera stations; no structural headroom or stair retest"
		filename="furniture_playability_review.json"
	if furnishings_review:
		result["scope"]="additional furnishing and quest/crystal placement; existing upper-floor geometry unchanged"
		filename="furnishings_playability_review.json"
	if textiles_review:
		result["scope"]="new textiles and sanitary circulation only; no existing bedroom/house retests"
		filename="textiles_sanitary_playability_review.json"
	if guestroom_review:
		result["scope"]="U15/U22 guestroom furniture and four room approaches; no unchanged staircase retest"
		filename="guestroom_playability_review.json"
	if layout_review:
		result["scope"]="v8 reception return/board, statue passages, changed timber stairs and hanging geometry; unchanged guest rooms not retested"
		filename="layout_playability_review.json"
	if statue_review:
		result["scope"]="v9 Fab statue, two side passages and rear circulation only; building and guest rooms unchanged"
		filename="statue_playability_review.json"
	if exterior_review:
		result["scope"]="v10 entry doors, added balcony door/access gallery and changed meeting-room opening; unchanged guest rooms/stair not retested"
		result["balcony_pose"]="Both authored hinge roots opened 90 degrees with mesh collision attached; closed leaves remain the delivered default. No runtime interaction binding."
		filename="exterior_playability_review.json"
	if landmark_review:
		result["scope"]="hanging skeleton: hall circulation, upward camera and rear gallery; existing rooms not retested"
		filename="landmark_playability_review.json"
	var f:=FileAccess.open(CURRENT_OUT+"/"+filename,FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	print("GUILD_PLAYABILITY failures=",failures.size()," camera_samples=",camera_samples," min_arm=",min_arm)
	quit(0 if failures.is_empty() else 1)

func scan_headroom() -> Dictionary:
	var lowest:=INF;var samples:=0;var open_wells:=0
	for ix in range(2,63):
		for iz in range(2,27):
			var feet:=Vector3(ix*.5,4.48,-iz*.5)
			var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.08,feet-Vector3.UP*.1))
			if floor_hit.is_empty() or not str(floor_hit.collider.get_meta("semantic_group","")).begins_with("20_"):continue
			var query:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.02,feet+Vector3.UP*15,2)
			var roof_hit:=space.intersect_ray(query)
			if roof_hit.is_empty():open_wells+=1;continue
			var clear:float=roof_hit.position.y-feet.y
			lowest=minf(lowest,clear);samples+=1
	check(samples>700 and lowest>=3.59,"upper floor real ceiling clearance >=3.6m")
	return {"samples":samples,"minimum":lowest,"open_rooflight_rays":open_wells}

func scan_doors(rooms:Array)->Dictionary:
	var samples:=0
	for room:Dictionary in rooms:
		var x:float=room.door[0];var y:float=room.door[1]
		for h in [1.2,2.1,2.95]:
			for i in range(16):
				var at:=Vector3(x,4.48+h,-(y+.08+i*.1))
				var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.LEFT*.3,at+Vector3.RIGHT*.3))
				check(hit.is_empty(),str(room.code)+" door aperture physical width/height")
				samples+=1
	return {"samples":samples,"clear_width_tested":1.5,"top_tested":2.95}

func frame_move(direction:Vector3,speed:float)->void:
	await physics_frame
	tick_id+=1
	var accepted:Dictionary=authority.move_intent(tick_id,direction,speed)
	check(accepted.get("ok",false),"production motion accepted")
	rig.follow(actor.position,1.0/60)
	check_camera()

func check_camera()->void:
	camera_samples+=1
	var arm:float=rig.global_position.distance_to(rig.last_focus);min_arm=minf(min_arm,arm)
	var q:=PhysicsShapeQueryParameters3D.new();var ball:=SphereShape3D.new();ball.radius=.195
	q.shape=ball;q.transform.origin=rig.global_position;q.exclude=[actor.get_rid()];q.margin=.001
	var overlaps:=space.intersect_shape(q,1)
	var ray:=PhysicsRayQueryParameters3D.create(rig.last_focus,rig.global_position);ray.exclude=[actor.get_rid()]
	var obstructed:=space.intersect_ray(ray)
	if (not overlaps.is_empty() or not obstructed.is_empty()) and camera_errors.size()<30:
		camera_errors.append({"tick":tick_id,"sphere_overlap":not overlaps.is_empty(),"focus_obstructed":not obstructed.is_empty(),"feet":str(actor.position-Vector3.UP*.9),"camera":str(rig.global_position)})

func walk_route(label:String,points:Array,reverse:bool)->void:
	actor.position=from_blender(points[0])+Vector3.UP*.905;actor.velocity=Vector3.ZERO
	rig._initialized=false;rig.pitch=deg_to_rad(18)
	var misses:Array=[];var count_before:=camera_samples;var route_min:=INF
	for point:Array in points.slice(1):
		var target:=from_blender(point)
		var ticks:=0
		while ticks<650:
			var delta:=target-(actor.position-Vector3.UP*.9);delta.y=0
			if delta.length()<.10 and absf(actor.position.y-.9-target.y)<.19:break
			if delta.length()>.001:
				var yaw:=atan2(-delta.x,-delta.z)
				rig.yaw=rotate_toward(rig.yaw,yaw,deg_to_rad(4))
			await frame_move(delta.normalized(),minf(2.5,delta.length()*60))
			route_min=minf(route_min,rig.global_position.distance_to(rig.last_focus));ticks+=1
		if ticks==650:
			misses.append({"target":str(target),"actual_feet":str(actor.position-Vector3.UP*.9)})
			break
	check(misses.is_empty(),label+" reverse="+str(reverse)+" actual authority walk")
	route_results.append({"name":label,"reverse":reverse,"misses":misses,"frames":camera_samples-count_before,"min_camera_arm":route_min})
	print("GUILD_ROUTE ",label," reverse=",reverse," misses=",misses.size())

func orbit_station(label:String,feet:Vector3)->void:
	actor.position=feet+Vector3.UP*.905;actor.velocity=Vector3.ZERO;rig._initialized=false
	var lowest:=INF;var max_step:=0.0
	for pitch_degrees in [-10,0,18,35,55]:
		rig.pitch=deg_to_rad(pitch_degrees);rig.yaw=0;rig._initialized=false
		for settle in 12:await frame_move(Vector3.ZERO,0)
		var last:Vector3=rig.position
		for angle in range(0,361,5):
			rig.yaw=deg_to_rad(angle)
			await frame_move(Vector3.ZERO,0)
			lowest=minf(lowest,rig.position.distance_to(rig.last_focus));max_step=maxf(max_step,rig.position.distance_to(last));last=rig.position
		if pitch_degrees==18 and label in ["landing","guest_corridor","single_room","office_corridor","panel_front"]:
			rig.yaw=0
			for settle in 24:await frame_move(Vector3.ZERO,0)
			await process_frame;await RenderingServer.frame_post_draw
			var file:="third_person_"+label+".png"
			root.get_texture().get_image().save_png(CURRENT_OUT+"/"+file);snapshot_names.append(file)
	orbit_results.append({"station":label,"minimum_arm":lowest,"max_step_per_5_degree_turn":max_step})
	check(lowest>=.55,label+" orbit leaves camera space")
	print("GUILD_ORBIT ",label," min_arm=",lowest," max_step=",max_step)

func capture_normal_views()->void:
	# Entry-facing views supplement, never replace the close wall-facing orbit images.
	for item in [
		["single_room_entry",[23.8,1.7,4.48],90.0],
		["twin_room_entry",[29.1,1.7,4.48],-90.0],
		["office_entry",[4.3,5.75,4.48],-90.0],
		["stair_ascent",[7.05,9.95,2.24],90.0]]:
		actor.position=from_blender(item[1])+Vector3.UP*.905;actor.velocity=Vector3.ZERO
		rig._initialized=false;rig.pitch=deg_to_rad(18);rig.yaw=deg_to_rad(item[2])
		for settle in 40:await frame_move(Vector3.ZERO,0)
		var arm:float=rig.position.distance_to(rig.last_focus)
		check(arm>=3.0,str(item[0])+" normal approach keeps full indoor camera arm")
		await process_frame;await RenderingServer.frame_post_draw
		var file:="third_person_"+str(item[0])+".png"
		root.get_texture().get_image().save_png(CURRENT_OUT+"/"+file);snapshot_names.append(file)
		print("GUILD_NORMAL_VIEW ",item[0]," arm=",arm)
