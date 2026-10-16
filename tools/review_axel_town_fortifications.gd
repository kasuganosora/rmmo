extends "res://tools/review_axel_town_roads.gd"
## Only run with run_godot_background.py. No editor/map/config writes.
const FortPlan=preload("res://scripts/world3d/fortification_plan.gd")
const FortFit=preload("res://scripts/world3d/fortification_terrain.gd")
const RiverProfile=preload("res://scripts/world3d/terrain_river_profile.gd")
const FortCollision=preload("res://scripts/world3d/fortification_collision_batcher.gd")
const FortAccess=preload("res://scripts/world3d/fortification_access.gd")
const TowerWalkSupport=preload("res://tools/axel_tower_walk_support.gd")
const IMAGE_PREP="C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py"
var region:Dictionary
var settings:Dictionary
var fitted_plan:Dictionary
var fort_ids:Dictionary={}
var routes:Array=[]
var land_gates:Array=[]
var water_gates:Array=[]
var saved_fixture_states:Dictionary={}
var shot_count:=0
var extra_camera_path:=""
var extra_cameras:Array=[]
var capture_fov:=55.0
var capture_directory:=""

func derive_coordinates()->bool:
	var groups:Array=layout.get("fortifications",[])
	if not check(groups.size()==1,"saved town has one continuous fortification group",{"count":groups.size()}):return false
	region=groups[0];settings=region.settings
	check(settings.closed and settings.wall_access and settings.follow_terrain,"closed native wall with internal tower access and terrain following")
	if not check(settings.shape=="path","current town review targets the saved traced path wall"):return false
	var invalid_members:Array=[]
	for part:Dictionary in region.parts:
		fort_ids[part.id]=true
		if not records.has(part.id) or City.token(records.get(part.id,{}))!=part.signature:invalid_members.append(part.id)
	if not check(invalid_members.is_empty(),"all saved fortification ownership signatures match",{"count":region.parts.size(),"invalid":invalid_members}):return false
	var raw:Dictionary=FortPlan.new().build(settings)
	if not check(raw.ok,"native saved wall recipe resolves",{"error":raw.get("error","")}):return false
	var fit:Dictionary=FortFit.fit(raw.records,document.records.filter(func(r):return r.has("terrain_mesh")),settings.base_height,settings.foundation,settings)
	if not check(fit.ok,"native wall terrain datum resolves",{"error":fit.get("error","")}):return false
	fitted_plan=raw;fitted_plan.records=fit.records;routes=raw.get("access_routes",[])
	for route:Dictionary in routes:
		var part_name:="access_tower_%d_internal_stair"%route.tower;var offset:=0.0
		for r:Dictionary in fit.records:
			if r.fortification.part==part_name:offset=fit.height_offsets[r.uuid];break
		for key in ["entry","room","deck","stairs_bottom","stairs_top"]:route[key][1]+=offset
		for p:Array in route.arrow_ports:p[1]+=offset
	for gate:Dictionary in raw.gates:
		for r:Dictionary in fit.records:
			if str(r.fortification.part).begins_with("door_"+str(gate.id).sha256_text().left(10)+"_"):gate.center[1]+=fit.height_offsets[r.uuid];break
		var authored:Array=settings.gates.filter(func(g):return g.id==gate.id)
		gate.request=authored[0].duplicate(true)
		if gate.request.get("kind","land")=="water":water_gates.append(gate)
		else:land_gates.append(gate)
	check(land_gates.size()==4 and water_gates.size()==3,"four land gates and three distinct water crossings saved",{"land":land_gates.size(),"water":water_gates.size()})
	check(routes.size()==settings.get("tower_indices",[]).size() and not routes.is_empty(),"all selected round towers have internal access routes",{"count":routes.size()})
	report.geometry={"region_id":settings.id,"length_m":raw.length,"source_parts":raw.records.size(),"frozen_parts":region.parts.size(),"tower_routes":routes,"gate_coordinates":raw.gates,"coordinate_source":"saved recipe plus current native Plan/Fit; checked below against actual runtime collision"}
	return failures==0

func relocate_fortification(point:Vector3,label:String)->bool:
	# Review points describe terrain/structural surfaces. Native pavement sits
	# 0.025 m above terrain, and a slope supports the rounded capsule off-axis.
	# Start 0.04 m above the requested surface, then require normal physics to
	# settle and the inherited strict support/streaming checks to pass.
	# Measured zero/+0.04 comparisons: transfer_surface_probe/result.json.
	return await relocate(point+Vector3.UP*.04,label)

func terrain_point(at:Vector3)->Vector3:
	var h:float=BridgeTools.ground_height(document.records.filter(func(r):return r.has("terrain_mesh")),at)
	return Vector3(at.x,h,at.z)

func gate_frame(gate:Dictionary)->Dictionary:
	var path:Dictionary=preload("res://scripts/world3d/fortification_spline.gd").resolve(settings).settings
	var request:Dictionary=path.gates.filter(func(g):return g.id==gate.id)[0]
	var i:=int(request.segment);var a:=Vector2(path.points[i][0],path.points[i][1]);var b:=Vector2(path.points[(i+1)%path.points.size()][0],path.points[(i+1)%path.points.size()][1])
	var tangent:=Vector3(b.x-a.x,0,b.y-a.y).normalized();var normal:=Vector3(-tangent.z,0,tangent.x)
	return {"center":vector(gate.center),"tangent":tangent,"normal":normal,"a":a,"b":b}

func hit_ray(a:Vector3,b:Vector3)->Dictionary:
	var q:=PhysicsRayQueryParameters3D.create(a,b);q.exclude=[world._player.get_rid()];q.collision_mask=world._player.collision_mask
	var hit:Dictionary=world._player.get_world_3d().direct_space_state.intersect_ray(q)
	return {} if hit.is_empty() else {"id":FortCollision.hit_uuid(hit),"point":xyz(hit.position),"normal":xyz(hit.normal)}

func ray_surface(point:Vector3,up:float=4.0,down:float=8.0)->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*up,point-Vector3.UP*down)
	query.exclude=[world._player.get_rid()];query.collision_mask=world._player.collision_mask
	var hit:Dictionary=world._player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return {"ok":false,"at":xyz(point)}
	# Native static fortification batches carry per-face ownership, not one UUID
	# per collider. Dynamic gate leaves retain their ordinary object UUID.
	return {"ok":hit.normal.y>=cos(deg_to_rad(45)),"position":xyz(hit.position),"normal":xyz(hit.normal),"id":FortCollision.hit_uuid(hit)}

func set_fixture(id:String,amount:float)->bool:
	var key:="fortification:"+str(settings.id)
	if not saved_fixture_states.has(id):
		var previous:Array=world.list_building_components(key).filter(func(r):return r.id==id)
		if not check(previous.size()==1,"runtime fixture exists "+id):return false
		saved_fixture_states[id]=previous[0].open
	var result:Dictionary=world.set_building_component_state(key,id,amount,0.)
	check(result.get("ok",false),"runtime-only fixture pose "+id,{"open":amount,"error":result.get("error","")})
	for tick in 4:await physics_frame
	return result.get("ok",false)

func restore_fixture(id:String)->void:
	if saved_fixture_states.has(id):
		await set_fixture(id,saved_fixture_states[id]);saved_fixture_states.erase(id)

func shell_support(at:Vector3,label_:String,tolerance:=.12,room_patch:=false)->Dictionary:
	var hit:=ray_surface(at,.35,.7)
	var good:bool=hit.ok and fort_ids.has(hit.get("id","")) and absf(float(hit.get("position",[0,-999,0])[1])-at.y)<=tolerance
	var details:={"expected":xyz(at),"hit":hit}
	# A point ray exactly on a triangulated floor fan's shared vertex can miss
	# all triangles (reproduced on tower 11's saved frozen collision). Only room
	# floors may use this small contact patch, and only above lower terrain.
	# Require four coplanar hits on one real fortification body; no wall/deck
	# edge checks, missing floor, raised obstruction or mixed owners are waived.
	if not good and room_patch and hit.ok and records.get(hit.get("id",""),{}).has("terrain_mesh"):
		var patch:Array=[];var owner:="";var level:=0.0;var valid:=true
		for offset:Vector2 in [Vector2(.017,.023),Vector2(-.017,-.023),Vector2(.043,-.031),Vector2(-.043,.031)]:
			var sample:=ray_surface(at+Vector3(offset.x,0,offset.y),.35,.7);patch.append(sample)
			var sample_y:float=sample.get("position",[0,-999,0])[1]
			if owner.is_empty():owner=str(sample.get("id",""));level=sample_y
			valid=valid and sample.ok and fort_ids.has(sample.get("id","")) and sample.get("id","")==owner and absf(sample_y-at.y)<=tolerance and absf(sample_y-level)<=.002
		good=valid and float(hit.position[1])<level-.001
		details.contact_patch=patch;details.contact_patch_passed=good
		if good:hit=patch[0]
	check(good,label_,details);return hit

func gate_blocked(at:Vector3,normal:Vector3,distance:float,id:String)->Dictionary:
	var pose:Transform3D=world._player.global_transform;pose.origin=at+Vector3.UP*1.12
	var collision:=KinematicCollision3D.new();var blocked:bool=world._player.test_move(pose,normal*distance,collision,.001,false)
	var owner:String=object_id(collision.get_collider()) if blocked else ""
	var result:={"blocked":blocked,"owner":owner,"normal":xyz(collision.get_normal()) if blocked else [],"fixture":records.get(owner,{}).get("fixture",{}).get("id","")}
	result.passed=blocked and fort_ids.has(owner) and result.fixture==id and absf(collision.get_normal().y)<.7
	return result

func audit_land_gate(gate:Dictionary,index:int)->void:
	report.phase="land_gate_"+str(gate.id);var frame:=gate_frame(gate);var center:Vector3=frame.center;var n:Vector3=frame.normal
	var first:=terrain_point(center-n*5.);var last:=terrain_point(center+n*5.);var walks:Array=[]
	if not await relocate_fortification(first,"gate_"+str(gate.id)):return
	await set_fixture(gate.id,1.)
	var open_ray:=hit_ray(first+Vector3.UP*1.2,last+Vector3.UP*1.2)
	check(open_ray.is_empty(),"opened gate clear across wall thickness "+str(gate.id),{"hit":open_ray})
	walks.append(await walk_route(last,"gate_"+str(gate.id)+"_forward"))
	# A failed first crossing remains a failure but does not suppress reverse diagnostics.
	if not walks.back().passed:await relocate_fortification(last,"gate_"+str(gate.id)+"_reverse_start")
	walks.append(await walk_route(first,"gate_"+str(gate.id)+"_reverse"))
	await relocate_fortification(first,"gate_"+str(gate.id)+"_closed_probe")
	await set_fixture(gate.id,0.)
	var closed:=gate_blocked(first,n,10.,gate.id)
	check(closed.passed,"closed land gate blocks actual capsule "+str(gate.id),closed)
	await restore_fixture(gate.id)
	report.gates.append({"id":gate.id,"walks":walks,"closed_probe":closed,"authored_open":gate.request.open})
	await capture("land_gate_%d_near"%(index+1),center-n*23.+frame.tangent*10.+Vector3.UP*10.,center+Vector3.UP*4.)
	save_report()

func fitted_wall_top(at:Vector3)->Dictionary:
	# Fit deforms each curtain part to its own plane. Ground directly below a
	# probe is not that plane, especially at a tower's rigid-to-sloping joint.
	var hit:Dictionary={}
	for record:Dictionary in fitted_plan.records:
		var part:=str(record.fortification.part)
		if not (part.begins_with("s") and part.substr(1,1).is_valid_int() or part.begins_with("joint_")):continue
		if not FortAccess.polys(record).any(func(poly):return Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),poly)):continue
		var basis:=Basis.from_euler(vector(record.rotation)*PI/180)
		var local:Vector3=basis.inverse()*(at-vector(record.position))
		var grade:Array=record.get("terrain_grade",[0.,0.])
		var top:float=record.position[1]+record.size[1]*.5+grade[0]*local.x+grade[1]*local.z
		if hit.is_empty() or top>float(hit.y):hit={"y":top,"part":part}
	return hit

func tower_links(route:Dictionary)->Array:
	var center:=Vector2(route.room[0],route.room[2]);var points:Array=settings.points;var nearest:=0;var distance:=INF
	for i in points.size():
		var d:float=center.distance_to(Vector2(points[i][0],points[i][1]))
		if d<distance:distance=d;nearest=i
	var links:Array=[]
	for i in [(nearest-1+points.size())%points.size(),(nearest+1)%points.size()]:
		var toward:=Vector2(points[i][0],points[i][1])-center;toward=toward.normalized()
		for radius:float in [route.radius-.15,route.radius+.15,route.radius+1.2]:
			var p:=Vector3(center.x+toward.x*radius,float(route.deck[1]),center.y+toward.y*radius)
			var plane:Dictionary={"y":p.y,"part":"tower_roof"} if radius<=route.radius else fitted_wall_top(p)
			if not plane.is_empty():p.y=plane.y
			links.append({"point":p,"plane":plane})
	return links

func tower_stair_support(point:Vector3,stair:Dictionary)->Dictionary:
	var center_hit:=support(point,.6,.3)
	if center_hit.ok:return {"ok":true,"method":"unchanged_center_ray","center_ray":center_hit}
	var collider:CollisionShape3D=world._player.get_node("CollisionShape3D")
	var capsule:CapsuleShape3D=collider.shape
	var center:Vector3=collider.global_position
	var bottom_y:float=center.y-capsule.height*.5
	var grounded:bool=world._player.is_on_floor()
	var floor_normal:Vector3=world._player.get_floor_normal()
	var accepted:Array=[];var contacts:Array=[];var rays:Array=[]
	if grounded:
		for ring:float in [.4,.6,.8,.95]:
			for index in 16:
				var offset:=Vector3(cos(index*TAU/16.),0,sin(index*TAU/16.))*capsule.radius*ring
				var at:=Vector3(center.x,bottom_y,center.z)+offset
				var hit:=ray_surface(at,.36,.1)
				if not hit.ok:continue
				var position:=vector(hit.position)
				var known:bool=fort_ids.has(hit.id) and TowerWalkSupport.authored_tread(position,stair)
				var valid:=TowerWalkSupport.contact_valid(grounded,floor_normal,capsule.radius,offset.length(),bottom_y,position,vector(hit.normal),known)
				var evidence:={"source":"capsule_foot_ring","position":hit.position,"normal":hit.normal,"id":hit.id,"radial_m":offset.length(),"authored_tread":known,"accepted":valid}
				rays.append(evidence)
				if valid:accepted.append(evidence)
		# Ring samples can straddle a narrow radial tread edge. The native solver
		# contact remains acceptable only on the same exact authored stair face.
		for slide_index in world._player.get_slide_collision_count():
			var collision:KinematicCollision3D=world._player.get_slide_collision(slide_index)
			for contact_index in collision.get_collision_count():
				var position:=collision.get_position(contact_index)
				var normal:=collision.get_normal(contact_index)
				var body:=collision.get_collider(contact_index)
				var owned:=body is StaticBody3D and (body.has_meta("fortification_collision_ranges") or fort_ids.has(object_id(body)))
				var known:bool=owned and TowerWalkSupport.authored_tread(position,stair)
				var radial:=Vector2(position.x-center.x,position.z-center.z).length()
				var valid:=TowerWalkSupport.contact_valid(grounded,floor_normal,capsule.radius,radial,bottom_y,position,normal,known)
				var evidence:={"source":"native_slide_contact","position":xyz(position),"normal":xyz(normal),"radial_m":radial,"authored_tread":known,"accepted":valid}
				contacts.append(evidence)
				if valid:accepted.append(evidence)
	return {"ok":not accepted.is_empty(),"method":"native_capsule_tread_contact","center_ray":center_hit,"native_on_floor":grounded,"native_floor_normal":xyz(floor_normal),"capsule_bottom_y":bottom_y,"capsule_radius":capsule.radius,"accepted":accepted,"rays":rays,"contacts":contacts}

func walk_tower_route(target:Vector3,label_:String,route:Dictionary)->Dictionary:
	var stair:Dictionary={}
	for record:Dictionary in fitted_plan.records:
		if record.fortification.part=="access_tower_%d_internal_stair"%route.tower:stair=record;break
	if not check(not stair.is_empty(),"exact authored stair available "+label_):return {"passed":false,"reason":"missing_authored_stair"}
	var start:=feet();var request:Dictionary=world._player.set_click_target(target,"ground")
	var began:=Time.get_ticks_msec();var unsupported:=0;var max_unsupported:=0;var samples:=0
	var min_y:=start.y;var center_rejected:=0;var contact_supported:=0
	var final_support:Dictionary={};var first_rejection:Dictionary={};var first_unsupported:Dictionary={}
	while Time.get_ticks_msec()-began<45000:
		await physics_frame
		var point:=feet();samples+=1;min_y=minf(min_y,point.y)
		final_support=tower_stair_support(point,stair)
		if not final_support.center_ray.ok:
			center_rejected+=1
			if final_support.ok:contact_supported+=1
			if first_rejection.is_empty():first_rejection={"feet":xyz(point),"tick":samples,"support":final_support}
		unsupported=0 if final_support.ok else unsupported+1;max_unsupported=maxi(max_unsupported,unsupported)
		if not final_support.ok and first_unsupported.is_empty():first_unsupported={"feet":xyz(point),"tick":samples,"support":final_support}
		if unsupported>20 or point.distance_to(target)<.35:break
		if not world._player.path_status.get("ok",false) and world._player.path_status.get("reason","")!="pending":break
	var result:={"label":label_,"start":xyz(start),"end":xyz(feet()),"target":xyz(target),"remaining_m":feet().distance_to(target),"elapsed_ms":Time.get_ticks_msec()-began,"unsupported_ticks":max_unsupported,"minimum_y":min_y,"physics_samples":samples,"center_ray_rejected_ticks":center_rejected,"native_tread_supported_ticks":contact_supported,"first_center_rejection":first_rejection,"first_unsupported":first_unsupported,"final_support":final_support,"request_reason":request.get("reason",""),"final_path_reason":world._player.path_status.get("reason",""),"final_velocity":xyz(world._player.velocity),"remaining_route_points":world._player._route.size(),"support_contract":"original .12m center ray or native grounded spherical foot on this tower's actual horizontal tread; original 20 unsupported ticks and 45 second timeout retained"}
	result.passed=result.remaining_m<.45 and max_unsupported<=20 and final_support.get("ok",false)
	check(result.passed,"actual player follows internal tower route "+label_,result)
	stop_route();return result

func audit_tower(route:Dictionary,representative:bool)->void:
	report.phase="tower_%d"%route.tower;var entry:=terrain_point(vector(route.entry));var room:=vector(route.room);var deck:=vector(route.deck)
	if not await relocate_fortification(entry,"tower_%d_entrance"%route.tower):return
	await set_fixture(route.door_id,1.)
	var doorway:=hit_ray(entry+Vector3.UP*1.3,room+Vector3.UP*1.3)
	check(doorway.is_empty(),"tower %d city-side door is clear"%route.tower,{"hit":doorway})
	shell_support(room+Vector3.UP*.03,"tower %d paved room support"%route.tower,.12,true)
	var walks:Array=[]
	if representative:
		walks.append(await walk_tower_route(deck,"tower_%d_internal_ascent"%route.tower,route))
		if not walks.back().passed:await relocate_fortification(deck,"tower_%d_deck_diagnostic"%route.tower)
		walks.append(await walk_tower_route(entry,"tower_%d_internal_descent"%route.tower,route))
	await relocate_fortification(deck,"tower_%d_roof"%route.tower)
	shell_support(deck,"tower %d roof has actual fortification collision"%route.tower)
	var links:Array=[]
	for link:Dictionary in tower_links(route):
		if not check(not link.plane.is_empty(),"tower %d joint has a fitted curtain surface"%route.tower,{"point":xyz(link.point)}):continue
		links.append({"point":xyz(link.point),"expected_surface":link.plane,"hit":shell_support(link.point,"tower %d roof-wall joint support"%route.tower,.16)})
	var ports:Array=[]
	for raw:Array in route.arrow_ports:
		var p:=vector(raw);var outward:=Vector3(p.x-room.x,0,p.z-room.z).normalized();var hit:=hit_ray(p-outward*.8,p+outward*.8)
		ports.append({"at":raw,"clear":hit.is_empty(),"hit":hit})
	check(not ports.is_empty() and ports.all(func(p):return p.clear),"tower %d real outward arrow slits remain open"%route.tower,{"ports":ports})
	await restore_fixture(route.door_id)
	report.towers.append({"index":route.tower,"representative_internal_walk":representative,"door_ray":doorway,"roof_links":links,"arrow_ports":ports,"walks":walks})
	if representative:
		var inside:Vector3=(vector(route.entry)-room).normalized()
		await capture("tower_%d_access_detail"%route.tower,room+inside*21.+Vector3.UP*12.,room+Vector3.UP*4.5)
	save_report()

func wet_crossing(frame:Dictionary)->Dictionary:
	var a:Vector2=frame.a;var b:Vector2=frame.b
	for river:Dictionary in document.map_meta.get("terrain_rivers",[]):
		var profile:=RiverProfile.prepare(river.request)
		if not profile.ok:continue
		for i in profile.path.size()-1:
			var c:=Vector2(profile.path[i][0],profile.path[i][1]);var d:=Vector2(profile.path[i+1][0],profile.path[i+1][1]);var at:Variant=Geometry2D.segment_intersects_segment(a,b,c,d)
			if at==null:continue
			if at.distance_to(Vector2(frame.center.x,frame.center.z))>32.:continue
			var level:float=lerpf(profile.levels[i],profile.levels[i+1],c.distance_to(at)/c.distance_to(d))
			return {"id":river.id,"point":Vector3(at.x,level,at.y),"direction":Vector3(d.x-c.x,0,d.y-c.y).normalized(),"width":float(river.request.width)}
	return {}

func wet_bays(gate:Dictionary,frame:Dictionary,water:Dictionary)->Array:
	# A narrow stream can pass the inner ends of two wide bays while neither
	# bay center is wet. Intersect each real aperture with the saved wet band.
	var side:Vector3=Vector3.UP.cross(water.direction).normalized()
	var rate:float=frame.tangent.dot(side)
	if absf(rate)<.0001:return []
	var center:float=(frame.center-water.point).dot(side);var half:float=float(water.width)*.5-.10
	var first:float=(-half-center)/rate;var last:float=(half-center)/rate
	var lo_wet:=minf(first,last);var hi_wet:=maxf(first,last)
	var count:=maxi(1,ceili(float(gate.width)/8.));var span:float=(float(gate.width)-(count-1))/count
	var result:Array=[]
	for i in count:
		var start:float=-float(gate.width)*.5+i*(span+1.)
		var lo:=maxf(start+.20,lo_wet);var hi:=minf(start+span-.20,hi_wet)
		if hi-lo>.10:result.append({"bay":i,"offset":(lo+hi)*.5,"wet_interval":[lo,hi]})
	return result

func closed_grille_bar(gate:Dictionary,frame:Dictionary,water:Dictionary,wet:Dictionary)->Dictionary:
	var part_prefix:="water_grille_"+str(gate.id).sha256_text().left(10)+"_%d_"%int(wet.bay)
	var best:Dictionary={};var closest:=INF
	# Saved render/collision groups have baked_* identities. Use the exact native
	# fitted recipe only to select a bar point; require the runtime ray below to
	# hit a saved frozen member of this same articulated gate.
	for record:Dictionary in fitted_plan.records:
		var part:=str(record.get("fortification",{}).get("part",""))
		if not part.begins_with(part_prefix) or not part.contains("_bar") or record.get("fixture",{}).get("id","")!=gate.id:continue
		var point:=vector(record.position);point.y=water.point.y+.30
		if point.y<record.position[1]-record.size[1]*.5 or point.y>record.position[1]+record.size[1]*.5:continue
		var offset:float=(point-frame.center).dot(frame.tangent)
		if offset<wet.wet_interval[0] or offset>wet.wet_interval[1]:continue
		var distance:=absf(offset-float(wet.offset))
		if distance<closest:closest=distance;best={"id":record.uuid,"part":part,"point":point,"fixture_id":gate.id}
	return best

func audit_water_gate(gate:Dictionary,index:int)->void:
	report.phase="water_gate_"+str(gate.id);var frame:=gate_frame(gate);var center:Vector3=frame.center;var tangent:Vector3=frame.tangent;var normal:Vector3=frame.normal
	var water:=wet_crossing(frame)
	if not check(not water.is_empty(),"water gate crosses actual saved river "+str(gate.id)):return
	var deck:=Vector3(center.x,float(gate.request.get("base_height",settings.base_height))+float(settings.height),center.z)
	var bays:=maxi(1,ceili(float(gate.width)/8.));var span:float=(float(gate.width)-(bays-1))/bays
	var channel_probes:Array=[];var deck_probes:Array=[];var grille_probes:Array=[]
	var wet_apertures:=wet_bays(gate,frame,water)
	for i in bays:
		var offset:float=-float(gate.width)*.5+i*(span+1.)+span*.5;var at:=deck+tangent*offset
		if not await relocate_fortification(at,"water_gate_"+str(gate.id)+"_bay_%d"%i):continue
		for lane:float in [-.8,0.,.8]:deck_probes.append(shell_support(at+normal*lane,"water gate bay crown support "+str(gate.id)))
		for wet:Dictionary in wet_apertures:
			if int(wet.bay)!=i:continue
			var direction:Vector3=water.direction
			if gate.request.get("grille",false):
				await set_fixture(gate.id,0.)
				var bar:=closed_grille_bar(gate,frame,water,wet);var closed:Dictionary={}
				if not bar.is_empty():closed=hit_ray(bar.point-direction*.5,bar.point+direction*.5)
				var owner:=str(closed.get("id",""))
				var blocked:bool=not bar.is_empty() and fort_ids.has(owner) and records.get(owner,{}).get("fixture",{}).get("id","")==gate.id
				var probe:={"bay":i,"passed":blocked,"expected_bar":bar.get("id",""),"source_part":bar.get("part",""),"expected_fixture":gate.id,"hit":closed}
				check(blocked,"closed water grille has its actual bar collision "+str(gate.id),probe)
				grille_probes.append(probe)
				await set_fixture(gate.id,1.)
			var p:Vector3=frame.center+tangent*float(wet.offset);p.y=water.point.y+.3
			# Follow the water through the skew wall, not its normal into a bank.
			var distance:float=(float(settings.thickness)*.5+.8)/maxf(.001,absf(direction.dot(normal)))
			var hit:=hit_ray(p-direction*distance,p+direction*distance)
			channel_probes.append({"bay":i,"at":xyz(p),"wet_interval":wet.wet_interval,"clear":hit.is_empty(),"hit":hit})
	check(not channel_probes.is_empty() and channel_probes.all(func(p):return p.clear),"actual river remains open beneath native water gate "+str(gate.id),{"channels":channel_probes})
	if gate.request.get("grille",false):await restore_fixture(gate.id)
	# Independently load both long-opening jambs before probing their joins.
	var jambs:Array=[]
	for sign_:float in [-1.,1.]:
		var at:=deck+tangent*sign_*(float(gate.width)*.5-.05)
		await relocate_fortification(at,"water_jamb_"+str(gate.id)+str(sign_))
		for delta:float in [-.15,.15]:
			var point:=deck+tangent*sign_*(float(gate.width)*.5+delta)
			jambs.append(shell_support(point,"water gate wall-walk jamb "+str(gate.id)))
	report.water_gates.append({"id":gate.id,"river":water.id,"water_level":water.point.y,"bank_datum":gate.request.get("base_height",settings.base_height),"deck":xyz(deck),"crown_probes":deck_probes,"channel_probes":channel_probes,"closed_grille_probes":grille_probes,"jambs":jambs})
	await capture("water_gate_%d_mid"%(index+1),center-normal*29.+tangent*17.+Vector3.UP*13.,center+Vector3.UP*3.5)
	save_report()

func valid_coordinates(value:Variant,count:int)->bool:
	if not value is Array or value.size()!=count:return false
	return value.all(func(v):return (v is float or v is int) and is_finite(float(v)))

func load_extra_cameras()->bool:
	if extra_camera_path.is_empty():return true
	if not check(Paths.allowed(extra_camera_path) and FileAccess.file_exists(extra_camera_path),"extra camera recipe exists in content root"):return false
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(extra_camera_path))
	var rows:Variant=parsed.get("cameras",[]) if parsed is Dictionary else parsed
	if not check(rows is Array and rows.size()<=16,"extra camera recipe contains up to sixteen cameras"):return false
	var names:Dictionary={}
	for row:Variant in rows:
		if not check(row is Dictionary,"extra camera is a structured object"):return false
		var id:=str(row.get("id",""));var eye:Variant=row.get("eye",row.get("position",[]));var target:Variant=row.get("target",[]);var anchor:Variant=row.get("anchor",[])
		var fov_value:Variant=row.get("fov",55.0)
		if not check(id.is_valid_identifier() and not names.has(id) and valid_coordinates(eye,3) and valid_coordinates(target,3) and (valid_coordinates(anchor,2) or valid_coordinates(anchor,3)) and (fov_value is int or fov_value is float),"extra camera has safe unique ID, finite eye/target and explicit loading anchor",{"id":id}):return false
		if not check(float(fov_value)>=30.0 and float(fov_value)<=100.0 and vector(eye).distance_to(vector(target))>.01,"extra camera has usable vertical FOV and look direction",{"id":id}):return false
		names[id]=true;extra_cameras.append({"id":id,"eye":eye,"target":target,"anchor":anchor,"fov":float(fov_value)})
	report.extra_camera_recipe={"path":extra_camera_path,"sha256":FileAccess.get_sha256(extra_camera_path),"cameras":extra_cameras}
	return true

func distributions(values:Array)->Dictionary:
	if values.is_empty():return {}
	var sorted:=values.duplicate();sorted.sort();var total:=0.0
	for value:float in sorted:total+=value
	return {"min":sorted[0],"mean":total/sorted.size(),"p50":sorted[floori((sorted.size()-1)*.50)],"p95":sorted[ceili((sorted.size()-1)*.95)],"max":sorted[-1],"samples":sorted.size()}

func runtime_batch_stats()->Dictionary:
	var map_root:Node=world.get("_map_root")
	var ground:Node=map_root.get_node_or_null("GroundRenderBatches")
	var collision:Node=map_root.get_node_or_null("FortificationCollisionBatches")
	return {"ground":ground.stats() if ground!=null and ground.has_method("stats") else {},"fortification_collision":collision.stats() if collision!=null and collision.has_method("stats") else {},"source":"runtime _map_root/GroundRenderBatches.stats(); current streamed set, not editor _ground_batches or whole-map resource counts"}

func measure_fixed_camera(label:String,camera:Camera3D)->void:
	# Character, collision and normal loading remain intact throughout timing.
	var viewport:=camera.get_viewport();var rid:=viewport.get_viewport_rid();var stable:=0;var waited:=0;var started:=Time.get_ticks_msec()
	while waited<600 and Time.get_ticks_msec()-started<15000:
		await process_frame;waited+=1
		var batch:=runtime_batch_stats()
		stable=stable+1 if batch.ground.get("pending_groups",-1)==0 else 0
		if stable>=36:break
	var before:=runtime_batch_stats();var rebuild_before:int=before.ground.get("rebuild_count",-1)
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var samples:={"render_cpu_ms":[],"render_gpu_ms":[],"process_ms":[],"physics_ms":[],"draw_calls":[],"objects":[],"primitives":[],"static_memory_bytes":[],"fps":[]}
	for frame in 30:
		await process_frame;await RenderingServer.frame_post_draw
		samples.render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		samples.render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		samples.process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.)
		samples.physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.)
		samples.fps.append(Performance.get_monitor(Performance.TIME_FPS))
		samples.static_memory_bytes.append(Performance.get_monitor(Performance.MEMORY_STATIC))
		for key:String in ["draw_calls","objects","primitives"]:
			var metric:int={"draw_calls":RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,"objects":RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME,"primitives":RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME}[key]
			samples[key].append(float(RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,metric)))
	RenderingServer.viewport_set_measure_render_time(rid,false)
	var after:=runtime_batch_stats();var summarized:Dictionary={}
	for key:String in samples:summarized[key]=distributions(samples[key])
	var settled:bool=stable>=36 and after.ground.get("pending_groups",-1)==0 and after.ground.get("rebuild_count",-2)==rebuild_before
	report.fixed_view_metrics.append({"id":label,"scope":"Thirty rendered frames at this fixed runtime review camera, max FPS 60; camera-follow process paused, character render/collision retained. Not a full-town traversal benchmark.","samples":30,"settled":settled,"warmup_frames":waited,"warmup_ms":Time.get_ticks_msec()-started,"metrics":summarized,"ground_batches_before":before,"ground_batches_after":after,"gpu_timing_available":samples.render_gpu_ms.max()>0.0,"cpu_timing_available":samples.render_cpu_ms.max()>0.0,"memory_scope":"Godot MEMORY_STATIC monitor, not process RSS or actual VRAM"})
	check(not before.ground.is_empty(),"actual runtime render batching stats available "+label)
	# A busy batcher is evidence, not mislabeled stable benchmark data.
	if not settled:report.metric_warnings.append({"id":label,"reason":"batcher did not remain settled during bounded fixed-view sample"})

func capture(label:String,eye:Vector3,target:Vector3)->void:
	await await_visual_residency(label)
	var model:Node3D=world._player.get_node("CharacterModel3D");var visible_before:=model.visible;var processing_before:bool=world.is_processing()
	var camera:Camera3D=world._camera.camera;var pose:=camera.global_transform;var fov:=camera.fov;var layers:Array=[]
	for child in world.get_children():
		if child is CanvasLayer:layers.append([child,child.visible]);child.hide()
	world.set_process(false);camera.global_position=eye;camera.look_at(target);camera.fov=capture_fov
	await measure_fixed_camera(label,camera)
	model.hide()
	for tick in 10:await process_frame
	await RenderingServer.frame_post_draw
	var img:=camera.get_viewport().get_texture().get_image();var raw:=capture_directory.path_join(label+".png");var err:=img.save_png(raw)
	camera.global_transform=pose;camera.fov=fov;world.set_process(processing_before);model.visible=visible_before
	for row:Array in layers:row[0].visible=row[1]
	check(err==OK,"capture image "+label)
	check(not world._player.get_node("CollisionShape3D").disabled and model.visible==visible_before,"capture restores rendering and keeps character collision "+label)
	if err!=OK:return
	var stdout:Array=[];var code:=OS.execute("python",PackedStringArray([IMAGE_PREP,raw]),stdout,true,false);var receipt:Dictionary={}
	if code==0:
		for line:String in "\n".join(stdout).split("\n"):
			if not line.strip_edges().begins_with("{"):continue
			var parsed:Variant=JSON.parse_string(line)
			if parsed is Dictionary and parsed.has("path"):receipt=parsed
	var good:bool=code==0 and receipt.get("quality",0)==90 and receipt.get("lossless",true)==false and FileAccess.get_sha256(receipt.get("path",""))==receipt.get("sha256","")
	check(good,"actual skill quality90 WebP receipt "+label,{"encoder_exit":code})
	if good:report.screenshots.append({"id":label,"path":receipt.path,"sha256":receipt.sha256,"dimensions":receipt.dimensions,"quality":90,"lossless":false,"method":6,"eye":xyz(eye),"target":xyz(target),"fov_vertical":capture_fov,"receipt":receipt});shot_count+=1

func finish(code:int=-1)->void:
	if finished:return
	# Last-resort restore also runs after timeout; authored map is never saved.
	if is_instance_valid(world) and is_instance_valid(world.get("_map_root")):
		for id:String in saved_fixture_states:world.set_building_component_state("fortification:"+str(settings.get("id","")),id,saved_fixture_states[id],0.)
		saved_fixture_states.clear()
	report.passed=failures==0 and code!=2 and report.get("phase","")=="complete"
	super.finish(code)

func run()->void:
	started_ms=Time.get_ticks_msec();map_path=FORMAL;output="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/fortification_runtime"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
		elif arg.begins_with("--extra-cameras="):extra_camera_path=arg.trim_prefix("--extra-cameras=").replace("\\","/").simplify_path()
	report={"phase":"metadata","map_path":map_path,"checks":[],"screenshots":[],"gates":[],"towers":[],"water_gates":[],"fixed_view_metrics":[],"metric_warnings":[],"scope":"one native fortification group; four land gates, all tower entries/roof joints, two representative internal stairs, three river apertures/crowns; optional functional-area fixed cameras","not_tested":["residential interiors","full-town performance","every meter of wall walked","combat AI","closed grille hydraulic simulation"]}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(1500).timeout.connect(func():
		if not finished:check(false,"fortification runtime review timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","actual GPU renderer required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"saved native target exists"):finish();return
	report.map_sha256=FileAccess.get_sha256(map_path);document=Document.open_file(map_path)
	if not check(document!=null,"native map opens read-only"):finish();return
	if not load_extra_cameras():finish();return
	capture_directory=output.path_join("images_"+report.map_sha256.left(12)+"_"+str(Time.get_unix_time_from_system()).replace(".","_"))
	if not check(DirAccess.make_dir_recursive_absolute(capture_directory)==OK,"fresh capture directory preserves previous evidence"):finish();return
	layout=City.resolve(document.map_meta)
	for r:Dictionary in document.records:records[r.uuid]=r
	if not derive_coordinates():finish();return
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"enter production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"native loading error",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	check(canonical_path(world._map_path)==canonical_path(map_path),"runtime target identity matches")
	check(not world._player.get_node("CollisionShape3D").disabled,"production character capsule retained")
	for i in land_gates.size():await audit_land_gate(land_gates[i],i)
	var sorted:Array=routes.duplicate();sorted.sort_custom(func(a,b):return a.room[1]<b.room[1]);var representative:Array=[sorted[0].tower,sorted[-1].tower]
	report.representative_tower_indices=representative
	for route:Dictionary in routes:await audit_tower(route,route.tower in representative)
	for i in water_gates.size():await audit_water_gate(water_gates[i],i)
	var center:=Vector3(220,15,180)
	await relocate_fortification(terrain_point(Vector3(156,0,209)),"final_overview")
	await capture("city_fortification_overview",center+Vector3(-180,250,260),center)
	for camera:Dictionary in extra_cameras:
		report.phase="extra_camera_"+camera.id
		var anchor:Array=camera.anchor
		var point:=terrain_point(Vector3(anchor[0],0,anchor[1])) if anchor.size()==2 else vector(anchor)
		if not await relocate_fortification(point,"extra_camera_"+camera.id):continue
		capture_fov=camera.fov
		await capture("area_"+camera.id,vector(camera.eye),vector(camera.target))
		capture_fov=55.0;save_report()
	check(shot_count==10+extra_cameras.size(),"all ten fortification and optional area WebP images prepared",{"count":shot_count,"expected":10+extra_cameras.size()})
	check(report.gates.size()==land_gates.size() and report.towers.size()==routes.size() and report.water_gates.size()==water_gates.size(),"all saved fortification elements received runtime diagnostics")
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"read-only runtime review leaves map bytes unchanged")
	report.phase="complete";finish()
