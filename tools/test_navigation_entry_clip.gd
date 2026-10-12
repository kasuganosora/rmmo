extends SceneTree
## Default: pure scheduling/bounds checks, no mesh upload or Recast bake.
## --geometry: real Recast doorway/hole/seam regression, private GPU desktop.
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SPAWN:=Vector3(321.2,.9,160.3)
const CLIP:=AABB(Vector3(307.2,-100000,146.3),Vector3(44.8,200000,45.7))
var passed:=0
var failures:=0

class Probe extends "res://scripts/world3d/world_navigation.gd":
	var collected:Array=[]
	var submissions:=0
	func _add_source(_target:NavigationMeshSourceGeometryData3D,spec:Dictionary)->bool:
		collected.append(spec.uuid);return true
	func _submit_bake()->void:submissions+=1

func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if value:passed+=1
	else:failures+=1
func bounded(id:String,bounds:AABB)->Dictionary:
	var mesh:=CpuMesh.new();mesh.bounds=bounds
	return {"uuid":id,"mesh":mesh,"transform":Transform3D.IDENTITY,"extras":{"rmmo_collision":"walk"}}
func probe(state:Dictionary,clip:Variant=null)->Node:
	var nav:=Probe.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	nav.initial_geometry_clip=clip
	nav.configure_streaming_geometry(func(area:AABB)->bool:state.clips.append(area);return state.ready)
	return nav
func release_probe(nav:Node)->void:
	nav._nearby=null;nav._nearby_request=null;nav.free()

func scheduling()->void:
	var floor:=bounded("floor",AABB(Vector3(300,-.2,140),Vector3(70,.2,70)))
	var state:={"ready":false,"clips":[]}
	var legacy:=probe(state)
	legacy.build([floor],SPAWN);legacy._step_background()
	check(legacy._clip.size.x==160. and legacy._clip.size.z==160. and legacy._phase=="waiting_initial_geometry","unset initial clip retains original 160m geometry gate")
	check(not legacy._initial_geometry_clip_active,"default navigator never enables compact-entry follow mode")
	legacy.ready_for_queries=true;legacy._local_clip=CLIP;state.clips.clear()
	legacy.follow(SPAWN)
	check(legacy._nearby_request is AABB and legacy._nearby_request.size.x==192.,"legacy follow still uses original 48m interior and 192m request")
	release_probe(legacy)
	for invalid:Variant in ["bad",AABB(),AABB(Vector3(INF,0,0),Vector3.ONE),AABB(Vector3(0,0,0),Vector3(-1,1,1)),AABB(Vector3.ZERO,Vector3(4,4,4)),AABB(Vector3(400,0,400),Vector3(32,32,32))]:
		var nav:=probe(state,invalid);nav.build([floor],SPAWN)
		check(not nav.map.is_valid() and not nav.geometry_error.is_empty(),"invalid initial clip rejects before allocating navigation map: "+str(invalid))
		release_probe(nav)
	for margin in [0.,1.9,INF,30.]:
		var nav:=probe(state,CLIP);nav.follow_guard_margin=margin;nav.build([floor],SPAWN)
		check(not nav.map.is_valid() and not nav.geometry_error.is_empty(),"unsafe follow guard rejects without map allocation: "+str(margin))
		release_probe(nav)
	state={"ready":false,"clips":[]}
	var nav:=probe(state,CLIP)
	var across:=bounded("south_seam",AABB(Vector3(318,-.2,158),Vector3(8,.2,4)))
	var outside:=bounded("outside",AABB(Vector3(380,-.2,200),Vector3(10,.2,10)))
	nav.build([floor,across,outside],SPAWN);nav._step_background()
	check(nav._staged and nav._initial_geometry_clip_active and nav._phase=="waiting_initial_geometry" and nav.submissions==0,"compact first mesh waits for its own complete geometry")
	check(is_equal_approx(nav._clip.position.x,CLIP.position.x) and is_equal_approx(nav._clip.position.z,CLIP.position.z) and nav._clip.size.x==CLIP.size.x and nav._clip.size.z==CLIP.size.z,"entry-plan XZ is exact, not recentered or expanded to legacy radius")
	check(nav._clip.size.y<5. and nav.mesh.filter_baking_aabb==nav._clip,"all-height query sentinel does not become a 200km Recast allocation")
	check(state.clips.size()==1 and state.clips[0]==nav._clip,"provider receives precisely the declared horizontal safety closure")
	check(nav._inside_local(SPAWN,2) and not nav._inside_local(SPAWN,48),"problem spawn has safe local interior even though legacy margin cannot fit")
	var high:=bounded("upper_floor",AABB(Vector3(319,40,159),Vector3(4,.2,4)))
	check(nav.append_specs([high]).ok,"provider can append complete upper storey before readiness")
	state.ready=true;nav._step_background()
	check(nav.submissions==1 and nav._clip.end.y>40 and nav._clip.size.y<50.,"initial completion includes appended upper floor while keeping bounded height")
	check(nav.collected.has("floor") and nav.collected.has("south_seam") and nav.collected.has("upper_floor") and not nav.collected.has("outside"),"source gathering retains crossing geometry and all storeys, omits unrelated outside geometry")
	check(is_equal_approx(nav.mesh.agent_radius,.5) and is_equal_approx(nav.mesh.cell_size,.1) and is_equal_approx(nav.mesh.agent_max_climb,.4) and nav.mesh.border_size==0.,"compact mode does not change erosion, stair precision, climb or initial border behavior")
	check(nav._local_clip==nav._clip and nav.mesh.filter_baking_aabb==nav._clip,"ready clip, source clip and Recast filter retain the same completeness boundary")
	nav.ready_for_queries=true;nav._start_full_bake();state.ready=false;state.clips.clear()
	for i in 120:nav.follow(SPAWN)
	check(state.clips.is_empty() and nav._nearby_request==null and nav._nearby==null,"stationary compact-entry player does not demand a 192m district")
	nav.follow(SPAWN,SPAWN+Vector3(4,0,4))
	check(state.clips.is_empty(),"nearby goal wholly inside complete local clip keeps existing navigation")
	nav.follow(SPAWN,SPAWN+Vector3(300,0,0))
	check(state.clips.is_empty(),"map-wide goal preserves existing bounded distant-route behavior")
	nav.follow(SPAWN,SPAWN+Vector3(70,0,0))
	check(state.clips.size()==1 and nav._nearby_request is AABB and nav._nearby_request.size.x==102. and nav._nearby_request.size.z==32. and nav._nearby_request.has_point(SPAWN+Vector3(70,0,0)),"explicit goal beyond compact clip requests only its padded corridor")
	nav.cancel_foreground_request();state.clips.clear()
	var edge:=Vector3(CLIP.end.x-1,.9,170)
	nav.follow(edge)
	check(state.clips.size()==1 and nav._nearby_request is AABB,"normal movement entering two-metre guard requests adjacent geometry")
	nav._nearby_request=null;state.clips.clear();nav.fully_ready=true
	nav.follow(edge,edge+Vector3(70,0,0))
	check(state.clips.is_empty(),"fully ready map does not reacquire streamed geometry")
	release_probe(nav)

func box(id:String,size_:Vector3,position_:Vector3)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size_
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position_),"extras":{"rmmo_collision":"walk"}}
func rectangle(id:String,x0:float,z0:float,x1:float,z1:float)->Dictionary:
	return box(id,Vector3(x1-x0,.2,z1-z0),Vector3((x0+x1)*.5,-.1,(z0+z1)*.5))
func until_ready(nav:Node)->bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not nav.ready_for_queries and nav.geometry_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	return nav.ready_for_queries

func geometry()->void:
	if not check_native():return
	var state:={"ready":false,"clips":[]}
	var nav:=Navigation.new();root.add_child(nav);nav.initial_geometry_clip=CLIP
	nav.configure_streaming_geometry(func(area:AABB)->bool:state.clips.append(area);return state.ready)
	# Separate floor pieces meet on z160 (the current cell edge). The north
	# floor is a ring around a genuine 4x4m hole, not a solid placeholder.
	var south:=rectangle("south",300,140,360,160)
	var specs:Array=[south,rectangle("north_west",300,160,328,200),rectangle("north_east",332,160,360,200),rectangle("north_south",328,160,332,172),rectangle("north_north",328,176,332,200),
		box("door_west",Vector3(20.2,3,.3),Vector3(310.1,1.5,164)),box("door_east",Vector3(37.8,3,.3),Vector3(341.1,1.5,164))]
	nav.build(specs,SPAWN)
	for i in 4:await process_frame
	check(not nav.ready_for_queries and nav._bake_pending.is_empty(),"real Recast does not bake before safety closure is complete")
	state.ready=true
	if not await until_ready(nav):check(false,"real compact navigation publishes within deadline");nav.free();return
	check(nav._initial_geometry_clip_active and not nav.fully_ready and nav.mesh.get_polygon_count()>0,"real compact mesh publishes locally without implying full-map readiness")
	check(nav.find_path(Vector3(321.2,.05,157),Vector3(321.2,.05,168)).ok,"real route crosses z160 cell seam and retained two-metre doorway")
	check(not nav.near_surface(Vector3(330,.05,174),.2,.3),"real 4m terrain hole remains non-walkable")
	var route:Dictionary=nav.find_path(Vector3(326,.05,174),Vector3(334,.05,174))
	check(route.ok and route.path.size()>2,"navigation routes around the hole instead of filling it")
	check(not nav.near_surface(Vector3(321.2-1.2,.05,164),.15,.3),"wall next to doorway retains full agent-radius clearance")
	check(nav.near_surface(Vector3(CLIP.position.x+2.1,.05,155),.2,.3),"walkable surface inside two-metre guard survives Recast boundary erosion")
	state.clips.clear()
	for i in 20:nav.follow(SPAWN);await process_frame
	check(state.clips.is_empty() and nav._nearby==null,"real stationary publication does not launch legacy-radius bake")
	# A capsule-height change while still inside the compact footprint must
	# preserve its geometry contract instead of reviving the 160m entry gate.
	await nav.resize_agent(2.0,nav._specs,SPAWN)
	check(is_equal_approx(nav.agent_height,2.0) and nav._initial_geometry_clip_active and nav._local_clip.size.x==CLIP.size.x,"height resize preserves active compact first footprint")
	check(nav.find_path(Vector3(321.2,.05,157),Vector3(321.2,.05,168)).ok,"doorway remains traversable after compact height resize")
	state.clips.clear();state.ready=false
	nav.follow(Vector3(CLIP.end.x-1,.9,170))
	nav.cancel_foreground_request();state.clips.clear()
	nav.follow(Vector3(CLIP.end.x-1,.9,170))
	check(state.clips.size()==1 and state.clips[0].size.x==32. and nav._nearby_request is AABB,"real edge movement requests only a bounded adjacent footprint without publishing incomplete geometry")
	state.ready=true
	var deadline:=Time.get_ticks_msec()+15000
	while (nav._nearby_request!=null or nav._nearby!=null or nav._nearby_publish_wait>0) and Time.get_ticks_msec()<deadline:await process_frame
	check(nav._nearby==null and nav._nearby_request==null and nav._nearby_publish_wait==0 and not nav._initial_geometry_clip_active,"nearby clip changes only after actual server handoff")
	check(nav._local_clip.size.x==32. and nav.find_path(Vector3(350,.05,180),Vector3(350,.05,182)).ok,"adjacent compact mesh remains queryable inside its verified footprint")
	nav.free()

func check_native()->bool:
	var native:=DisplayServer.get_name()!="headless"
	check(native,"geometry mode requires private native GPU desktop")
	return native
func run()->void:
	create_timer(60).timeout.connect(func():print("ENTRY_NAV_TIMEOUT");quit(2))
	scheduling()
	if OS.get_cmdline_user_args().has("--geometry"):await geometry()
	print("ENTRY_NAVIGATION_FINISHED passed=",passed," failures=",failures)
	quit(1 if failures else 0)
