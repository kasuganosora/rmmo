extends SceneTree
## Real headless Recast with a low ceiling, deferred geometry and a live worker.
const Nav=preload("res://scripts/world3d/world_navigation.gd")
class PendingLegacy extends "res://scripts/world3d/world_navigation.gd":
	func build(specs:Array,_origin:Variant=null)->void:
		map=NavigationServer3D.map_create();_specs=specs.duplicate()
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if value:passed+=1
	else:failures+=1
func box(id:String,size_:Vector3,position_:Vector3)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size_
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position_),"extras":{"rmmo_collision":"walk"}}
static func blocked_faces(gate:Semaphore)->PackedVector3Array:
	gate.wait();return PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
func resize(nav:Node,height:float,state:Dictionary)->void:
	await nav.resize_agent(height,nav._specs,Vector3(5,.9,0));state.done=true
func cancel(nav:Node,state:Dictionary)->void:
	await nav.cancel_resize();state.done=true
func wait_result(state:Dictionary)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while not state.done and Time.get_ticks_msec()<deadline:await process_frame
	check(state.done,"local resize completes within bounded test deadline")
func run()->void:
	var readiness:={"ready":true,"calls":0}
	var provider:=func(_clip:AABB)->bool:readiness.calls+=1;return readiness.ready
	var nav:=Nav.new();root.add_child(nav);nav.agent_height=1.1
	check(nav.configure_streaming_geometry(provider),"configure streaming resize fixture")
	var floor:=box("floor",Vector3(20,.2,20),Vector3(0,-.1,0))
	var ceiling:=box("ceiling",Vector3(4,.2,8),Vector3(0,1.5,0))
	nav.build([floor,ceiling],Vector3(5,.9,0))
	var deadline:=Time.get_ticks_msec()+10000
	while not nav.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
	check(nav.ready_for_queries and not nav.fully_ready and nav.near_surface(Vector3(0,.05,0),.35,.4),"short capsule has a real route surface under low ceiling")
	if not nav.ready_for_queries:nav.free();quit(1);return
	var node_id:=nav.get_instance_id();var old_map:RID=nav.map;var old_version:int=nav.version
	readiness.ready=false
	var gate:=Semaphore.new();nav._face_worker=Thread.new()
	check(nav._face_worker.start(blocked_faces.bind(gate))==OK,"old navigation owns an unfinished CPU face snapshot")
	var state:={"done":false};resize(nav,2.1,state)
	for frame in 3:await process_frame
	check(not state.done and nav._resizing and nav.map==old_map and is_equal_approx(nav.agent_height,1.1),"resize keeps old map and height while replacement geometry waits")
	check(nav.near_surface(Vector3(0,.05,0),.35,.4),"old low-ceiling query stays usable during replacement preparation")
	check(not nav.try_retire_specs(["floor"]).ok,"resize holds source retirement lease across both navigators")
	var late:=box("late",Vector3(2,.2,2),Vector3(12,-.1,0))
	check(nav.append_specs([late]).ok and nav._resize_replacement._spec_ids.has("late"),"new geometry arriving during resize reaches independent replacement")
	gate.post()
	deadline=Time.get_ticks_msec()+5000
	while nav._face_worker!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(nav._face_worker==null and not state.done and nav.map==old_map,"finished old worker is joined without waiting for replacement readiness")
	readiness.ready=true
	await wait_result(state)
	check(nav.get_instance_id()==node_id and nav.map!=old_map and nav.version>old_version and is_equal_approx(nav.agent_height,2.1),"published local replacement swaps map in stable navigation Node")
	check(nav.ready_for_queries and not nav.fully_ready and not nav._resizing and nav._resize_replacement==null and nav._spec_ids.has("late"),"resize retains streaming lifecycle and late geometry without leaked candidate")
	check(not nav.near_surface(Vector3(0,.05,0),.35,.4),"tall capsule excludes the real low-ceiling floor")
	check(nav.find_path(Vector3(4,.05,-2),Vector3(6,.05,2)).ok,"tall capsule still navigates the unobstructed local floor")
	state={"done":false};resize(nav,1.1,state);await wait_result(state)
	check(is_equal_approx(nav.agent_height,1.1) and nav.near_surface(Vector3(0,.05,0),.35,.4),"lowering capsule height restores low-ceiling navigation")
	old_map=nav.map;old_version=nav.version;readiness.ready=false
	state={"done":false};resize(nav,2.1,state)
	await process_frame
	check(is_instance_valid(nav._resize_replacement),"failed-resize fixture has an isolated candidate")
	nav._resize_replacement.set_geometry_error("injected geometry failure")
	await wait_result(state)
	check(nav.map==old_map and nav.version==old_version and is_equal_approx(nav.agent_height,1.1) and nav.geometry_error.is_empty(),"candidate failure preserves old map, height and healthy geometry state")
	check(not nav._resizing and nav._resize_replacement==null and nav.near_surface(Vector3(0,.05,0),.35,.4),"candidate failure releases resize lease and keeps gameplay queryable")
	readiness.ready=true
	state={"done":false};resize(nav,2.1,state);await wait_result(state)
	check(is_equal_approx(nav.agent_height,2.1) and not nav.loading_profile.has("resize_error"),"corrected geometry can retry resize successfully")
	old_map=nav.map;old_version=nav.version;readiness.ready=false
	gate=Semaphore.new();nav._face_worker=Thread.new()
	check(nav._face_worker.start(blocked_faces.bind(gate))==OK,"cancellation fixture owns an unfinished source lease")
	state={"done":false};resize(nav,1.1,state)
	var cancelled:={"done":false};cancel(nav,cancelled)
	for frame in 3:await process_frame
	check(not state.done and not cancelled.done and nav._resizing and nav.map==old_map,"cancel request keeps coroutine and old map alive until real worker completion")
	gate.post();await wait_result(cancelled)
	check(state.done and nav._face_worker==null and nav._resize_replacement==null and not nav._resizing,"cancel drains live worker and candidate without freeing an active resize coroutine")
	check(nav.map==old_map and nav.version==old_version and is_equal_approx(nav.agent_height,2.1) and nav.geometry_error.is_empty(),"cancelled resize never commits height or navigation changes")
	await nav.cancel_resize()
	check(not nav._resizing,"cancel of an idle navigator is a no-op")
	nav.free()
	var legacy:=PendingLegacy.new();root.add_child(legacy);legacy.build([])
	legacy.ready_for_queries=true;legacy.fully_ready=true;legacy.agent_height=1.8
	var legacy_map:RID=legacy.map;state={"done":false};resize(legacy,1.9,state)
	check(legacy._resizing and is_instance_valid(legacy._resize_replacement),"legacy resize also exposes its candidate lifetime")
	cancelled={"done":false};cancel(legacy,cancelled);await wait_result(cancelled)
	check(state.done and legacy.map==legacy_map and is_equal_approx(legacy.agent_height,1.8) and legacy._resize_replacement==null,"legacy cancellation preserves old map and retires candidate before transfer")
	legacy.free()
	print("NAVIGATION_STREAMING_RESIZE_FINISHED passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
