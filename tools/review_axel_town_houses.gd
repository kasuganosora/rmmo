extends "res://tools/review_axel_town_roads.gd"
## Outdoor-only review against the builder's actual saved placement receipt.
## Launch via run_godot_background.py. No house interiors, doors, maps or assets are edited.
const HOUSE_OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var build_path:=HOUSE_OUT+"/build.json"
var build_receipt:Dictionary={}
var house_recipe:Dictionary={}
var terrain_records:Array=[]
var sampled_houses:Dictionary={}
var entrance_steps:Array[Dictionary]=[]
var entrance_component_ids:Array=[]
var entrance_building_id:=""

func prepare_steps(h:Dictionary)->void:
	entrance_steps.clear();entrance_component_ids=h.get("component_ids",[]);entrance_building_id=str(h.building_id)
	var plan:Dictionary=preload("res://scripts/world3d/building_blueprint.gd").generate(h.parameters)
	var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(h.yaw))),vector(h.position))
	for r:Dictionary in plan.get("records",[]):
		if r.get("building",{}).get("role","")!="entry_step":continue
		var step_pose:=pose*Transform3D(Basis.from_euler(vector(r.get("rotation",[0,0,0]))*PI/180),vector(r.position))
		entrance_steps.append({"inverse":step_pose.affine_inverse(),"box":AABB(-vector(r.size)*.5,vector(r.size)),"part":r.building.part})

func step_owner(id:String)->bool:
	var owner:Dictionary=records.get(id,{}).get("building",{})
	return id in entrance_component_ids and str(owner.get("id",""))==entrance_building_id and owner.get("role","") in ["shell","entry_step"]

func authored_step(point:Vector3,id:String)->bool:
	# Freeze batches entry treads with the storey's shell. Match the original
	# native step's real volume/top, never blanket-accept the merged shell.
	if not step_owner(id):return false
	for step:Dictionary in entrance_steps:
		var local:Vector3=step.inverse*point;var box:AABB=step.box
		if absf(local.y-box.end.y)<.025 and box.grow(.02).has_point(local):return true
	return false

func step_contact_points(feet_point:Vector3,id:String,points:PackedVector3Array)->Dictionary:
	# Classify actual collision pairs, not the separate centre ray's ground hit.
	# Both endpoints of every pair must be inside the current house's authored
	# tread OBBs. A rotated step's empty AABB corners, walls and upper jambs are
	# never accepted merely because they share the frozen shell's object ID.
	var bad:Array=[];var highest:=-INF
	if not step_owner(id) or points.is_empty() or points.size()%2!=0 or points.size()>=256:return {"passed":false,"reason":"unknown owner or missing/truncated contact pairs","contact_points":points.size()}
	for point:Vector3 in points:
		highest=maxf(highest,point.y)
		var in_step:=false
		if point.is_finite() and point.y<=feet_point.y+.32 and point.y>=feet_point.y-.025:
			for step:Dictionary in entrance_steps:
				if step.box.grow(.015).has_point(step.inverse*point):in_step=true;break
		if not in_step:bad.append(xyz(point))
	return {"passed":bad.is_empty(),"contact_points":points.size(),"highest_contact":highest,"height_above_ground":highest-feet_point.y,"invalid_points":bad}

func ground_point(at:Vector3)->Vector3:
	var y:=BridgeTools.ground_height(terrain_records,at)
	return Vector3(at.x,y,at.z)

func capsule_clear(point:Vector3)->Dictionary:
	var shape:CollisionShape3D=world._player.get_node("CollisionShape3D")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape
	query.transform=world._player.global_transform*shape.transform
	query.transform.origin=point+Vector3.UP*.94+shape.position
	query.exclude=[world._player.get_rid()];query.collision_mask=world._player.collision_mask;query.margin=.001
	var contacts:Array=world._player.get_world_3d().direct_space_state.intersect_shape(query,64)
	var blocked:Array=[];var supports:Array=[]
	var step_contacts:Array=[];var visited:Dictionary={}
	if contacts.size()>=64:blocked.append({"reason":"capsule contact list reached limit; cannot certify all contacts"})
	for contact:Dictionary in contacts:
		var id:=object_id(contact.collider);var r:Dictionary=records.get(id,{})
		var rid:RID=contact.get("rid",RID())
		if visited.has(rid):continue
		visited[rid]=true
		# Ground slopes/entry treads can touch the bottom of an upright capsule.
		# Record those contacts separately; the physical local walk below still
		# has to climb them. House walls, foundations, planters and trees may not
		# be excused as support just because a ray found ground below them.
		if r.has("terrain_mesh") or r.has("road_mesh") or r.get("building",{}).get("role","") in ["floor","entry_step"]:supports.append(id)
		elif step_owner(id) and rid.is_valid():
			# intersect_shape supplies owner RIDs but no contact locations. Exclude
			# every other overlapping body for this read-only collide_shape probe;
			# all shapes of the target RID remain included, including its walls.
			var excluded:Array[RID]=[world._player.get_rid()]
			for other:Dictionary in contacts:
				var other_rid:RID=other.get("rid",RID())
				if other_rid.is_valid() and other_rid!=rid and not excluded.has(other_rid):excluded.append(other_rid)
			query.exclude=excluded
			var points:PackedVector3Array=world._player.get_world_3d().direct_space_state.collide_shape(query,128)
			var classified:=step_contact_points(point,id,points);classified.id=id;step_contacts.append(classified)
			if classified.passed:supports.append(id)
			else:blocked.append({"id":id,"role":r.get("building",{}).get("role",""),"reason":"frozen contact is not wholly inside authored low steps","classification":classified})
		else:blocked.append({"id":id,"name":r.get("editor_name",r.get("name","")),"role":r.get("building",{}).get("role","")})
	return {"passed":blocked.is_empty(),"blocked":blocked,"support_contacts":supports,"authored_step_contact_pairs":step_contacts,"capsule_origin":xyz(query.transform.origin)}

static func local_support_sample_valid(on_floor:bool,floor_normal:Vector3,radius:float,radial_distance:float,bottom_y:float,hit_y:float,hit_normal:Vector3,known_low_step:bool,center_ground:bool)->bool:
	if not on_floor or floor_normal.y<cos(deg_to_rad(45)) or hit_normal.y<cos(deg_to_rad(45)):return false
	if not is_finite(bottom_y) or not is_finite(hit_y) or radius<=0 or radial_distance>radius:return false
	if not known_low_step and not (center_ground and radial_distance<.001):return false
	# Compare against the actual spherical capsule foot at this radial offset,
	# not against a widened centre-ray gap. A wall/high ledge or void fails.
	var sphere_y:=bottom_y+radius-sqrt(maxf(0,radius*radius-radial_distance*radial_distance))
	return absf(hit_y-sphere_y)<=.035

func doorway_support(point:Vector3)->Dictionary:
	var collider:CollisionShape3D=world._player.get_node("CollisionShape3D")
	var capsule:CapsuleShape3D=collider.shape
	var center:Vector3=collider.global_transform.origin
	var bottom_y:float=center.y-capsule.height*.5
	var grounded:bool=world._player.is_on_floor();var normal:Vector3=world._player.get_floor_normal()
	var evidence:Array=[];var accepted:Array=[]
	for ring in [0.,.4,.6,.8,.95]:
		for index in (1 if ring==0 else 16):
			var offset:Vector3=Vector3(cos(index*TAU/16.),0,sin(index*TAU/16.))*capsule.radius*ring
			var at:Vector3=Vector3(center.x,bottom_y,center.z)+offset
			var hit:=ray_surface(at,.36,.1)
			if not hit.ok:continue
			var owner:Dictionary=records.get(hit.id,{})
			var known:=authored_step(vector(hit.position),hit.id)
			var ground:bool=owner.has("terrain_mesh") or owner.has("road_mesh") or owner.get("building",{}).get("role","")=="floor"
			var valid:=local_support_sample_valid(grounded,normal,capsule.radius,offset.length(),bottom_y,float(hit.position[1]),vector(hit.normal),known,ground)
			var sample:={"position":hit.position,"id":hit.id,"normal":hit.normal,"radial_m":offset.length(),"authored_low_step":known,"accepted":valid}
			evidence.append(sample)
			if valid:accepted.append(sample)
	# Discrete ray rings can straddle a tread edge. CharacterBody supplies the
	# actual solver contact there; validate it against the same precise foot
	# geometry and authored tread OBB, never against the shell ID alone.
	var contacts:Array=[]
	for slide_index in world._player.get_slide_collision_count():
		var collision:KinematicCollision3D=world._player.get_slide_collision(slide_index)
		for contact_index in collision.get_collision_count():
			var contact_point:Vector3=collision.get_position(contact_index)
			var contact_normal:Vector3=collision.get_normal(contact_index)
			var id:=object_id(collision.get_collider(contact_index))
			var radial:=Vector2(contact_point.x-center.x,contact_point.z-center.z).length()
			var known:=authored_step(contact_point,id)
			var valid:=local_support_sample_valid(grounded,normal,capsule.radius,radial,bottom_y,contact_point.y,contact_normal,known,false)
			var sample:={"source":"native_slide_collision","slide_index":slide_index,"contact_index":contact_index,"position":xyz(contact_point),"normal":xyz(contact_normal),"id":id,"radial_m":radial,"authored_low_step":known,"accepted":valid}
			contacts.append(sample)
			if valid:accepted.append(sample)
	var clear:=capsule_clear(point)
	return {"ok":not accepted.is_empty() and clear.passed,"native_on_floor":grounded,"native_floor_normal":xyz(normal),"actual_feet":xyz(point),"capsule_bottom_y":bottom_y,"accepted":accepted,"rays":evidence,"native_slide_contacts":contacts,"clearance":clear}

func walk_doorway(target:Vector3,label:String)->Dictionary:
	var start:=feet();var request:Dictionary=world._player.set_click_target(target,"ground")
	var began:=Time.get_ticks_msec();var unsupported:=0;var max_unsupported:=0;var ticks:=0
	var final_support:Dictionary={};var arrived:=false
	while Time.get_ticks_msec()-began<15000:
		await physics_frame;ticks+=1
		var point:=feet();final_support=doorway_support(point)
		unsupported=0 if final_support.ok else unsupported+1;max_unsupported=maxi(max_unsupported,unsupported)
		var xz:=Vector2(point.x-target.x,point.z-target.z).length()
		var same_step:bool=final_support.ok and final_support.accepted.any(func(e):return e.authored_low_step)
		# A low tread edge can support the capsule off-centre above the ray
		# target. Only measured same-house OBB/spherical-foot support allows it.
		arrived=xz<.1 and final_support.ok and (absf(point.y-target.y)<.1 or (same_step and absf(point.y-target.y)<=.32))
		if unsupported>20 or arrived:break
		if not world._player.path_status.get("ok",false) and world._player.path_status.get("reason","")!="pending":break
	var end:=feet();var result:={"label":label,"start":xyz(start),"end":xyz(end),"target":xyz(target),"remaining_m":end.distance_to(target),"remaining_xz_m":Vector2(end.x-target.x,end.z-target.z).length(),"remaining_y_m":end.y-target.y,"support_evidence":final_support,"elapsed_ms":Time.get_ticks_msec()-began,"unsupported_ticks":max_unsupported,"physics_samples":ticks,"request_reason":request.get("reason",""),"final_path_reason":world._player.path_status.get("reason",""),"passed":arrived and max_unsupported<=20}
	check(result.passed,"actual player reaches outdoor doorstep target "+label,result);stop_route();return result

func audit_house(h:Dictionary)->void:
	var id:=str(h.id);report.phase="entrance_"+id
	prepare_steps(h)
	var params:Dictionary=h.parameters;var outward:=Basis(Vector3.UP,deg_to_rad(float(h.yaw)))*Vector3.FORWARD
	var sideways:=Vector3(-outward.z,0,outward.x)
	# Native plan.entrance is 1 m outside the wall, on exterior ground datum.
	var entrance:=vector(h.entrance);var threshold:=entrance-outward+Vector3.UP*float(params.get("base_height",0))
	var start:=ground_point(threshold+outward*2.6)
	if not check(is_finite(start.y),"native exterior terrain exists "+id):return
	if not await relocate(start+Vector3.UP*.04,"house "+id):return
	var samples:Array=[];var invalid:Array=[];var center_hits:Dictionary={}
	for offset in [2.3,1.8,1.3,.9,.55]:
		for lane in [-.36,0.0,.36]:
			var expected:=threshold+outward*float(offset)+sideways*float(lane)
			var hit:=ray_surface(expected,.7,3.0)
			var owner:Dictionary=records.get(hit.get("id",""),{})
			var walkable_owner:bool=owner.has("terrain_mesh") or owner.has("road_mesh") or owner.get("building",{}).get("role","") in ["floor","entry_step"] or (hit.ok and authored_step(vector(hit.position),str(hit.id)))
			var valid:bool=hit.ok and walkable_owner and absf(float(hit.get("position",[0,-10000,0])[1])-threshold.y)<1.5
			var clearance:Dictionary={}
			if valid:
				clearance=capsule_clear(vector(hit.position));valid=clearance.passed
			var row:={"offset_m":offset,"lane_m":lane,"surface":hit,"capsule":clearance,"passed":valid}
			samples.append(row)
			if not valid:invalid.append(row)
			if lane==0.0 and hit.ok:center_hits[str(offset)]=hit
	check(invalid.is_empty(),"outdoor doorway support and actual capsule clearance "+id,{"samples":samples.size(),"invalid":invalid})
	var joins:Array=[]
	var previous:Dictionary={}
	for row:Dictionary in samples:
		if row.lane_m!=0.0 or not row.surface.ok:continue
		if not previous.is_empty():
			var rise:=absf(float(row.surface.position[1])-float(previous.surface.position[1]))
			joins.append({"from_m":previous.offset_m,"to_m":row.offset_m,"height_change_m":rise,"passed":rise<=.32})
		previous=row
	check(joins.size()==4 and joins.all(func(j):return j.passed),"outdoor doorstep has no unsupported vertical jump "+id,{"joins":joins})
	var walks:Array=[]
	# Preserve any static failure above, but still gather both physical outdoor
	# directions. No probe exemption can substitute for actually walking here.
	if center_hits.has("2.3") and center_hits.has("0.55"):
		var a:=vector(center_hits["2.3"].position);var b:=vector(center_hits["0.55"].position)
		if await relocate(a+Vector3.UP*.025,id+" short approach"):
			walks.append(await walk_doorway(b,id+" approach stops outside wall"))
		if not walks.is_empty() and walks.back().passed:
			# Continue from the real supported arrival, never teleport the capsule
			# down onto a centre-ray point underneath its neighbouring tread.
			walks.append(await walk_doorway(a,id+" return to street side"))
	check(walks.size()==2 and walks.all(func(w):return w.passed),"both outdoor approach directions completed "+id)
	var result:={"id":id,"shot":h.shot,"building_id":h.building_id,"position":h.position,"threshold":xyz(threshold),"outward":xyz(outward),"samples":samples,"joins":joins,"walks":walks}
	report.houses.append(result);sampled_houses[id]=result;save_report()

func audit_access(h:Dictionary)->void:
	var authored:Array=house_recipe.get("houses",[]).filter(func(row):return row.id==h.id)
	if not check(authored.size()==1,"saved exterior access recipe found "+str(h.id)):return
	var points:Array=authored[0].get("access_points",[]).duplicate();points.reverse()
	if not check(points.size()>=2,"exterior route has two endpoints "+str(h.id)):return
	# Only walk the final 24 metres near each representative house; never turn
	# this fixture into another whole-town travel or interior test.
	var selected:Array=[];var length_:=0.0
	for i in range(points.size()-1,-1,-1):
		if not selected.is_empty():length_+=Vector2(points[i][0],points[i][1]).distance_to(Vector2(selected[0][0],selected[0][1]))
		if length_>24:break
		selected.push_front(points[i])
	if not check(selected.size()>=2,"representative local route retained "+str(h.id)):return
	var initial:=ground_point(Vector3(selected[0][0],0,selected[0][1]))
	if not check(is_finite(initial.y),"route terrain sampled "+str(h.id)) or not await relocate(initial+Vector3.UP*.04,str(h.id)+" exterior access"):return
	var walks:Array=[]
	for i in range(1,selected.size()):
		var at:=ground_point(Vector3(selected[i][0],0,selected[i][1]))
		var hit:=ray_surface(at,1.0,2.0)
		if not check(hit.ok,"local outdoor access surface "+str(h.id),hit):break
		walks.append(await walk_route(vector(hit.position),str(h.id)+" exterior segment "+str(i)))
		if not walks.back().passed:break
	check(walks.size()==selected.size()-1 and walks.all(func(w):return w.passed),"complete representative outdoor access "+str(h.id))
	report.routes.append({"house":h.id,"shot":h.shot,"points":selected,"walks":walks,"scope":"outdoor path to outside doorstep; no interior target"});save_report()
	var result:Dictionary=sampled_houses.get(str(h.id),{})
	if not result.is_empty():
		var target:=vector(result.threshold)+Vector3.UP*1.3
		await capture(str(h.shot)+"_outdoor_entrance",target+vector(result.outward)*6+Vector3.UP*2,target)

func audit_landmark_access(key:String,start_xz:Vector2,end_xz:Vector2)->void:
	# Only the new public exterior approach; no guild interior or tower access.
	var placed:Array=build_receipt.get("landmarks",{}).get("placements",[]).filter(func(row):return row.key==key)
	if not check(placed.size()==1 and records.has(str(placed[0].id)),"saved landmark identity "+key):return
	entrance_component_ids.clear();entrance_steps.clear();entrance_building_id=""
	var start:=ground_point(Vector3(start_xz.x,0,start_xz.y))
	if not check(is_finite(start.y),"landmark approach terrain "+key) or not await relocate(start+Vector3.UP*.04,key+" exterior"):return
	var samples:Array=[];var targets:Array=[]
	for i in 7:
		var xz:=start_xz.lerp(end_xz,float(i)/6.)
		var at:=ground_point(Vector3(xz.x,0,xz.y));var hit:=ray_surface(at,.8,1.6)
		var owner:Dictionary=records.get(hit.get("id",""),{});var clearance:Dictionary={}
		var valid:bool=hit.ok and (owner.has("terrain_mesh") or owner.has("road_mesh"))
		if valid:clearance=capsule_clear(vector(hit.position));valid=clearance.passed
		samples.append({"xz":[xz.x,xz.y],"surface":hit,"capsule":clearance,"passed":valid})
		if i in [0,6] and hit.ok:targets.append(vector(hit.position))
	var clear:bool=samples.all(func(s):return s.passed)
	check(clear,"public landmark approach has ground and capsule clearance "+key,{"samples":samples})
	var walks:Array=[]
	if clear and targets.size()==2:
		walks.append(await walk_route(targets[1],key+" approach"))
		if walks.back().passed:walks.append(await walk_route(targets[0],key+" return"))
	check(walks.size()==2 and walks.all(func(w):return w.passed),"public landmark approach walked both ways "+key)
	report.landmarks.append({"key":key,"id":placed[0].id,"samples":samples,"walks":walks,"scope":"public exterior only; tower has no traversable entrance"});save_report()

func capture(label:String,eye:Vector3,target:Vector3)->void:
	var model:Node3D=world._player.get_node("CharacterModel3D");var was_visible:=model.visible
	var processing_before:=world.is_processing();var camera:Camera3D=world._camera.camera;var transform_before:=camera.global_transform;var layers:Array=[]
	for child in world.get_children():
		if child is CanvasLayer:layers.append([child,child.visible]);child.hide()
	model.hide();world.set_process(false);camera.global_position=eye;camera.look_at(target)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	var im:=root.get_texture().get_image();var path:=output.path_join(label+".webp");var error:=im.save_webp(path,false,.9)
	camera.global_transform=transform_before;world.set_process(processing_before);model.visible=was_visible
	for layer:Array in layers:layer[0].visible=layer[1]
	check(error==OK,"lossy quality90 WebP outdoor capture "+label)
	check(model.visible==was_visible and not world._player.get_node("CollisionShape3D").disabled,"capture preserves actor collision and restores rendering "+label)
	if error==OK:report.screenshots.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":im.get_width(),"height":im.get_height(),"encoding":"lossy WebP quality90","eye":xyz(eye),"target":xyz(target)})

func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf";output=HOUSE_OUT+"/runtime"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
		elif arg.begins_with("--build="):build_path=arg.trim_prefix("--build=").replace("\\","/").simplify_path()
	report={"scope":"saved residential outdoor doorways, representative street/courtyard routes, new stream bridge and any new landmark public approaches","not_tested":["interiors","indoor door/window operation","full-town performance","all five older bridges again"],"checks":[],"screenshots":[],"houses":[],"routes":[],"bridges":[],"landmarks":[],"map_path":map_path,"phase":"metadata"}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(900).timeout.connect(func():
		if not finished:check(false,"outdoor house review timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","actual renderer required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"saved candidate map exists"):finish();return
	if not check(Paths.allowed(build_path) and FileAccess.file_exists(build_path),"native build receipt exists"):finish();return
	build_receipt=JSON.parse_string(FileAccess.get_file_as_string(build_path));house_recipe=JSON.parse_string(FileAccess.get_file_as_string(build_path.get_base_dir()+"/housing_recipe.json"))
	report.map_sha256=FileAccess.get_sha256(map_path);report.build_sha256=FileAccess.get_sha256(build_path)
	if not check(build_receipt.get("phase")=="candidate_complete" and int(build_receipt.get("failures",-1))==0 and build_receipt.get("candidate_sha256")==report.map_sha256,"runtime map matches successful native candidate receipt"):finish();return
	document=Document.open_file(map_path)
	if not check(document!=null,"native house map opens read-only"):finish();return
	for record:Dictionary in document.records:records[str(record.uuid)]=record
	terrain_records=document.records.filter(func(r):return r.has("terrain_mesh"))
	var houses:Array=build_receipt.get("houses",[])
	if not check(not houses.is_empty(),"actual saved houses are enumerated"):finish();return
	for h:Dictionary in houses:check(document.map_meta.get("building_instances",{}).has(str(h.building_id)),"saved native house identity "+str(h.id))
	if failures:finish();return
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading"
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"enter production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"runtime loading failed",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	check(canonical_path(world._map_path)==canonical_path(map_path),"runtime loaded exact candidate")
	check(is_instance_valid(world._player) and not world._player.get_node("CollisionShape3D").disabled,"normal character collision retained")
	for h:Dictionary in houses:await audit_house(h)
	for id in ["s1_north_courtyard","s10_front_home","s12_arch_home"]:
		var selected:Array=houses.filter(func(h):return h.id==id)
		if check(selected.size()==1,"representative outdoor house found "+id):await audit_access(selected[0])
	if build_receipt.get("watercourse",{}).get("continuous",false):
		layout=City.resolve(document.map_meta)
		var binding:Dictionary=Ports.resolve(layout)
		if check(binding.get("ok",false),"continuous tributary bridge bindings remain native"):
			var crossings:Array=binding.portals.filter(func(p):return records.get(p.get("deck_id",""),{}).get("bridge_mesh",{}).get("clearance_mode","")=="stream")
			if check(crossings.size()==1,"one new non-navigable stream bridge found"):
				await audit_bridge(crossings[0],5)
				await capture("s12_stream_bridge_runtime",Vector3(321,13,117),Vector3(332,8,126))
	if not build_receipt.get("landmarks",{}).get("placements",[]).is_empty():
		await audit_landmark_access("landmark/guild",Vector2(156,209),Vector2(156,204.4))
		await audit_landmark_access("landmark/alarm",Vector2(141,154),Vector2(141,148.2))
	check(report.houses.size()==houses.size(),"all actual saved house entrances reviewed")
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"runtime outdoor review leaves map unchanged")
	report.phase="complete";finish()
