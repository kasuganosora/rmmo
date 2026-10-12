extends SceneTree
## CPU/headless: no import, no GPU readback, no blocking join of a live worker.
const Nav=preload("res://scripts/world3d/world_navigation.gd")
const Nearby=preload("res://scripts/world3d/nearby_navigation.gd")
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if value:passed+=1
	else:failures+=1
func spec(id:String,mesh:Mesh,door:bool=false)->Dictionary:
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,Vector3(300,0,0)),"extras":{"fixture":{"kind":"door","id":id,"open":0.0}} if door else {}}
func state(nav:Node)->Dictionary:
	return {"ids":nav._spec_ids.duplicate(),"specs":nav._specs.duplicate(),"doors":nav._doors.duplicate(),"faces":nav._faces.duplicate(),"cursor":nav._cursor,"phase":nav._phase,"source":nav.source,"mesh":nav.mesh,"version":nav.version}
func rejected_unchanged(nav:Node,ids:Array,reason:String,label_:String)->void:
	var before:=state(nav)
	var result:Dictionary=nav.try_retire_specs(ids)
	check(not result.ok and result.reason==reason and state(nav)==before,label_)
static func blocked_worker(gate:Semaphore)->PackedVector3Array:
	gate.wait();return PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
func run()->void:
	var ordinary:=Nav.new();root.add_child(ordinary);ordinary.set_process(false);ordinary.set_physics_process(false)
	check(ordinary.set_geometry_pending(false) and not ordinary.geometry_pending,"non-streaming completion behavior remains unchanged")
	rejected_unchanged(ordinary,["anything"],"not_streaming","non-streaming navigation rejects the new retirement path")
	ordinary.free()
	var nav:=Nav.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	var provider_state:={"ready":true,"calls":0}
	var provider:=func(_clip:AABB)->bool:provider_state.calls+=1;return provider_state.ready
	check(not nav.configure_streaming_geometry(Callable()) and not nav.streaming_geometry,"invalid provider cannot enter streaming lifecycle")
	check(nav.configure_streaming_geometry(provider) and nav.geometry_pending and nav.streaming_geometry,"streaming lifecycle is configured before build")
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true;nav._staged=true;nav._phase="waiting_geometry"
	check(not nav.configure_streaming_geometry(provider),"already built navigation cannot switch lifecycle")
	var clip:=AABB(Vector3.ZERO,Vector3(8,10,8))
	check(nav._ensure_geometry(clip) and provider_state.calls==1,"streaming readiness consults region provider")
	check(not nav.set_geometry_pending(false) and nav.geometry_pending and not nav.fully_ready,"empty pending queue cannot mark resident world permanently complete")
	provider_state.ready=false
	check(not nav._ensure_geometry(clip) and provider_state.calls==2,"unloaded region becomes pending again on revisit")
	nav._start_full_bake()
	check(not nav._full_started and nav._phase=="waiting_geometry" and nav._full_mesh==null,"streaming completion never starts a full-map bake")
	var shared:=BoxMesh.new();var unique:=BoxMesh.new();var door_mesh:=BoxMesh.new()
	var keep:=spec("keep",shared);var leave:=spec("leave",shared);var solo:=spec("solo",unique);var door:=spec("door",door_mesh,true)
	check(nav.append_specs([keep,leave,solo,door]).ok and nav._doors.size()==1,"streaming navigation accepts complete model and door records")
	nav._faces[shared.get_instance_id()]=PackedVector3Array([Vector3.ONE])
	nav._faces[unique.get_instance_id()]=PackedVector3Array([Vector3.RIGHT])
	nav._faces[door_mesh.get_instance_id()]=PackedVector3Array([Vector3.UP])
	rejected_unchanged(nav,["missing"],"unknown_uuid","unknown retirement UUID fails without mutation")
	rejected_unchanged(nav,[42],"invalid_uuid","invalid retirement UUID fails without mutation")
	nav._phase="source";nav._cursor=2
	rejected_unchanged(nav,["leave"],"source_in_use","active source cursor protects its immutable input order")
	nav._phase="waiting_geometry"
	nav._nearby=Nearby.new(nav.mesh,clip);nav._nearby.cursor=2
	rejected_unchanged(nav,["leave"],"source_in_use","active nearby cursor rejects even unrelated removals")
	check(nav._nearby.cursor==2,"refusal preserves nearby cursor")
	nav._nearby=null;nav._nearby_request=clip
	rejected_unchanged(nav,["leave"],"source_in_use","queued nearby footprint stays pinned until consumed")
	nav._nearby_request=null
	var source_job:=RefCounted.new();nav._source_jobs[nav.source]=source_job
	rejected_unchanged(nav,["leave"],"worker_in_use","source worker snapshot prevents premature release")
	nav._source_jobs.clear();nav._orphan_sources.append(source_job)
	rejected_unchanged(nav,["leave"],"worker_in_use","orphan source snapshot remains charged until joined")
	nav._orphan_sources.clear()
	var gate:=Semaphore.new();nav._face_worker=Thread.new()
	check(nav._face_worker.start(blocked_worker.bind(gate))==OK,"start bounded CPU face worker fixture")
	rejected_unchanged(nav,["leave"],"worker_in_use","live face worker is rejected without blocking main thread")
	await process_frame
	check(nav._face_worker.is_alive(),"frame continues while refused worker still owns its snapshot")
	gate.post()
	while nav._face_worker.is_alive():await process_frame
	rejected_unchanged(nav,["leave"],"worker_in_use","completed but unconsumed worker still owns its result")
	nav._face_worker.wait_to_finish();nav._face_worker=null
	nav.source.set_meta("pending_faces",[[PackedVector3Array([Vector3.ZERO]),Transform3D.IDENTITY]])
	rejected_unchanged(nav,["leave"],"bake_in_use","queued source-face data blocks retirement before a worker starts")
	nav.source.remove_meta("pending_faces");nav._bake_pending="initial"
	rejected_unchanged(nav,["leave"],"bake_in_use","submitted bake cannot lose source leases")
	nav._bake_pending="";nav._baking_mesh=nav.mesh
	rejected_unchanged(nav,["leave"],"bake_in_use","completed bake must be consumed before source release")
	nav._baking_mesh=null;nav._nearby_publish_wait=1
	rejected_unchanged(nav,["leave"],"publication_in_use","pending server publication cannot be retired")
	nav._nearby_publish_wait=0
	var original_mesh:NavigationMesh=nav.mesh;var original_map:RID=nav.map
	var result:Dictionary=nav.try_retire_specs(["leave","solo","door"])
	check(result.ok and result.removed==3 and nav._specs.size()==1 and nav._spec_ids.size()==1 and nav._doors.is_empty(),"idle window atomically removes specs, doors and UUID ownership")
	keep.extras.identity_probe=true
	check(nav._specs[0].extras.get("identity_probe",false),"survivor spec retains original identity and order")
	check(nav._faces.has(shared.get_instance_id()) and not nav._faces.has(unique.get_instance_id()) and not nav._faces.has(door_mesh.get_instance_id()),"only face caches without surviving geometry owners are released")
	check(nav.mesh==original_mesh and nav.map==original_map and nav.ready_for_queries,"retiring source references preserves published navigation queries")
	check(nav.append_specs([leave,solo,door]).ok and nav._spec_ids.has("leave") and nav._doors.size()==1,"revisit can append the same UUID and rebind door data")
	check(not nav.append_specs([leave]).ok,"live duplicate UUID remains rejected")
	check(nav.try_retire_specs([]).ok,"empty retirement is an idempotent no-op")
	nav.free()
	await integration()
	print("NAVIGATION_STREAMING_RETIREMENT_FINISHED passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)

func integration()->void:
	var nav:=Nav.new();root.add_child(nav)
	var readiness:={"remote":true,"calls":0}
	var remote_bounds:=AABB(Vector3(94,-2,-6),Vector3(12,4,12))
	var provider:=func(clip:AABB)->bool:
		readiness.calls+=1
		return readiness.remote or not Rect2(clip.position.x,clip.position.z,clip.size.x,clip.size.z).intersects(Rect2(94,-6,12,12))
	check(nav.configure_streaming_geometry(provider),"real navigation uses explicit resident geometry lifecycle")
	var floor_mesh:=BoxMesh.new();floor_mesh.size=Vector3(12,.2,12)
	var local:=spec("local_floor",floor_mesh);local.transform.origin=Vector3(0,-.1,0)
	var remote:=spec("remote_floor",floor_mesh);remote.transform.origin=Vector3(100,-.1,0)
	nav.build([local,remote],Vector3.ZERO)
	var deadline:=Time.get_ticks_msec()+10000
	while not nav.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
	check(nav.ready_for_queries and not nav.fully_ready and nav._phase=="waiting_geometry","real initial region publishes without a full-map bake")
	if not nav.ready_for_queries:nav.free();return
	check(nav.find_path(Vector3(-2,.05,0),Vector3(2,.05,0)).ok,"local route is usable before retirement")
	var retired:Dictionary=nav.try_retire_specs(["remote_floor"])
	check(retired.ok and not nav._spec_ids.has("remote_floor"),"inactive remote source retires after initial native bake finishes")
	readiness.remote=false
	check(nav.find_path(Vector3.ZERO,remote_bounds.get_center()).reason=="pending" and nav._nearby==null and nav._nearby_request!=null,"revisit waits for remote source demand instead of querying stale global completeness")
	check(nav.find_path(Vector3(-2,.05,0),Vector3(2,.05,0)).ok,"local route survives remote readiness wait")
	check(nav.append_specs([remote]).ok,"same remote UUID republishes after a real retirement")
	readiness.remote=true
	var old_version:int=nav.version;deadline=Time.get_ticks_msec()+10000
	while nav.version==old_version and Time.get_ticks_msec()<deadline:await process_frame
	check(nav.version>old_version and not nav.fully_ready and not nav._full_started,"revisit publishes a bounded nearby bake and stays in streaming lifecycle")
	check(nav.find_path(Vector3(98,.05,0),Vector3(102,.05,0)).ok,"newly reloaded remote floor supports a real navigation route")
	check(nav.find_path(Vector3(-2,.05,0),Vector3(2,.05,0)).ok,"revisit replacement keeps source region covered when requested together")
	nav.free()
