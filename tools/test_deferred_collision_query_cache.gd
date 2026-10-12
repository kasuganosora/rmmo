extends "res://tools/test_collision_asset_descriptor.gd"
## Real sealed map + tiny GLB/sidecar/Store; no author files or render gate.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const MapFixture=preload("res://tools/test_map_dependency_index.gd")
class Service extends "res://scripts/world3d/collision_dependency_loader.gd":
	var submissions:=0
	var checks:=0
	func request(entries:Array,priority:int=0,id:String="default")->Dictionary:
		submissions+=1;return super.request(entries,priority,id)
	func coverage(entries:Array)->Dictionary:
		checks+=1;return super.coverage(entries)

func entry(index:Dictionary,at:int)->Dictionary:
	var row:Dictionary=index.rows[at]
	return {"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}
func pending_entry(value:Dictionary)->Dictionary:
	return {"record":value.compact_record,"path":value.asset_path,"bounds":value.bounds,"reference_entry":value,"native_reference":false,"group_id":value.group_id}
func uuids(values:Array)->Array:
	return values.map(func(value):return value.record.uuid)
func wait_ready(queue:Node,clip:AABB)->bool:
	for i in 900:
		await process_frame
		if queue.ensure_collision(clip):return true
	return false

func candidate_cases()->void:
	var queue:=Deferred.new();var rows:Array=[]
	for i in 120:
		rows.append({"record":{"uuid":str(i)},"bounds":AABB(Vector3((i%12)*17-80,0,(i/12)*19-80),Vector3(14,1,14))})
	rows.insert(3,{"record":{"uuid":"large"},"bounds":AABB(Vector3(-400,0,-400),Vector3(800,1,800))})
	queue.pending=rows
	var equivalent:=true
	for i in 180:
		var clip:=AABB(Vector3((i%20)*3-34,i,(i%17)*2-32),Vector3(9,2,8))
		if uuids(queue._collision_in_clip(clip,"moving","exact"))!=uuids(queue._in_clip(clip)):equivalent=false
	check(equivalent,"cached candidate ordering equals legacy for cell edges, large objects, XZ motion and Y noise")
	var clip:=AABB(Vector3(-5,0,-5),Vector3(10,1,10))
	queue._collision_in_clip(clip,"mutation","exact")
	rows[3].published=true
	check(uuids(queue._collision_in_clip(clip,"mutation","exact"))==uuids(queue._in_clip(clip)),"published candidate aliases are filtered immediately without a cached-ready result")
	rows.append({"record":{"uuid":"appended"},"bounds":clip})
	check("appended" in uuids(queue._collision_in_clip(clip,"mutation","exact")),"pending append invalidates candidate membership and the underlying spatial index")
	rows.erase(rows[-1]);check(not "appended" in uuids(queue._collision_in_clip(clip,"mutation","exact")),"in-place pending removal cannot leave a cached candidate")
	queue.pending=[{"record":{"uuid":"replacement"},"bounds":clip}]
	check(uuids(queue._collision_in_clip(clip,"mutation","exact"))==["replacement"],"pending array replacement immediately invalidates prior membership")
	queue.pending=[{"record":{"uuid":"same_length"},"bounds":clip}]
	check(uuids(queue._collision_in_clip(clip,"mutation","exact"))==["same_length"],"same-length replacement array also invalidates cached spatial membership")
	for i in 40:queue._collision_in_clip(clip,"ticket"+str(i),"exact")
	check(queue._collision_queries.size()<=Deferred.COLLISION_QUERY_CACHE_LIMIT,"per-ticket query references have a fixed bound")
	queue.free()

func run()->void:
	create_timer(45).timeout.connect(func():push_error("collision query timeout");quit(2))
	var errors:=Errors.new();OS.add_logger(errors)
	var old_first:=Deferred.collision_first_enabled;var old_cache:=Deferred.collision_query_cache_enabled;var old_profile:=Deferred.collision_query_profile_enabled
	Deferred.collision_first_enabled=true;Deferred.collision_query_cache_enabled=true;Deferred.collision_query_profile_enabled=false
	candidate_cases()
	folder=Paths.cache_directory("collision_query_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("fixture.glb");fixture(model)
	var product:=await worker(Builder.build.bind(model,folder,Builder.estimate(model,folder).estimated_bytes))
	check(product.ok,"tiny actual GLB supplies a verified collision sidecar");Drainer.dispose_result(product)
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i in 8:records.append({"uuid":"item"+str(i),"kind":"asset","asset_path":model,"position":[i*10,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	var author:=helper.fixture("map",records)
	check(Index.build(author.path,folder,records).ok,"real authored map produces the ownership directory")
	var issued:=Index.read_for_loading(author.path,folder)
	check(issued.ok,"real directory reader issues a sealed proof")
	if not issued.ok:
		helper.free();finish(errors);return
	var map:=Node3D.new();root.add_child(map);map.set_meta("extras",{"rmmo_records":[]})
	var service:=Service.new();map.add_child(service)
	check(service.configure(issued.index,author.path,folder,issued.proof,map,7).ok,"real map service owns its collision state and physics Store")
	var queue:=Deferred.new();var rows:Array=[]
	for i in 8:rows.append(pending_entry(entry(issued.index,i)))
	queue.pending=rows;queue.configure_references(issued.index,author.path,folder,issued.proof);map.add_child(queue);queue.activate(map);queue._active=false;queue.set_process(false)
	var bounds:AABB=rows[0].bounds
	var clip:=AABB(bounds.position-Vector3(.1,1,.1),bounds.size+Vector3(.2,2,.2))
	check(not queue.ensure_collision(clip),"first request cannot treat prepared or unrequested state as ready")
	var requested:=service.submissions;var checked:=service.checks
	var all_pending:=true
	for i in 180:
		var moving:=clip;moving.position+=Vector3((i%8)*.001,float(i%20),0)
		if queue.ensure_collision(moving):all_pending=false
	check(all_pending and service.submissions==requested and service.checks==checked+180,"stable 180 physics ticks reuse one sealed ticket while checking current coverage every tick")
	check(queue.profile.collision_candidate_builds<=2 and queue.profile.collision_candidate_hits>=360,"stable movement reuses both exact-cell and camera-hold candidate sets")
	check(not queue.profile.has("collision_guard_us") and not queue.profile.has("collision_candidate_us"),"ordinary mode performs no detailed guard timer accounting")
	Deferred.collision_query_cache_enabled=false
	var legacy_pending:=true
	for i in 12:
		if queue.ensure_collision(clip):legacy_pending=false
	check(legacy_pending,"legacy switch preserves pending readiness")
	check(service.submissions==requested+12,"disabled cache executes the original request validation every call")
	Deferred.collision_query_cache_enabled=true;Deferred.collision_query_profile_enabled=true
	check(await wait_ready(queue,clip),"real worker preparation and physics synchronization eventually satisfy the live cached query")
	check(queue.profile.collision_guard_us>0 and queue.profile.collision_coverage_us>0,"opt-in phase timers expose candidate, request and actual coverage cost")
	var exact:Array=[]
	for value:Dictionary in queue._in_clip(clip):exact.append(value.reference_entry)
	var body:StaticBody3D=service._store._instances.item0.rows[0].body
	var layer:=body.collision_layer;body.collision_layer=0
	check(not queue.ensure_collision(clip),"disabled actual body invalidates coverage immediately despite an unchanged ticket")
	body.collision_layer=layer
	# Rebuild is controlled by withdrawing the ticket, never by cached readiness.
	queue.release_demand("player_collision");var before:=service.submissions
	queue.ensure_collision(clip)
	check(service.submissions==before+1,"release and reacquisition submit a new exact ticket")
	queue.retry_failed(clip);before=service.submissions;queue.ensure_collision(clip)
	check(service.submissions==before+1,"retry invalidates stable ticket and candidate state")
	queue.configure_references(issued.index,author.path,folder,issued.proof);before=service.submissions;queue.ensure_collision(clip)
	check(service.submissions==before+1,"reference reconfiguration requires a fresh validated submission")
	queue.set_demand_scope(["navigation"]);queue.ensure_collision(clip)
	check(not service._tickets.has("player_collision") and not queue._collision_queries.has("player_collision"),"scope exclusion immediately withdraws ownership and cached ticket")
	queue.set_demand_scope([]);queue.ensure_collision(clip)
	var first:Dictionary=rows[0];first.published=true;queue._remove_published_demand([first]);before=service.submissions
	queue.ensure_collision(clip)
	check(service.submissions==before+1 and not service._tickets.player_collision.entries.has("item0"),"publication drops only the finished item while preserving camera-area ownership")
	check(queue.requeue_reference(first.reference_entry),"retired authored reference rejoins the pending catalog")
	before=service.submissions;check(not queue.ensure_collision(clip) and service.submissions==before+1 and service._tickets.player_collision.entries.has("item0"),"retirement invalidates membership and never reuses its old ready result")
	var current:Dictionary=queue.pending.filter(func(value):return value.record.uuid=="item0")[0]
	var original_entry:Dictionary=current.reference_entry
	current.reference_entry=original_entry.duplicate();current.reference_entry.bounds=AABB(Vector3(999,0,0),Vector3.ONE)
	before=service.submissions;check(not queue.ensure_collision(clip) and service.submissions==before+1,"mutable wrapper bounds change goes back through exact entry validation")
	current.reference_entry=original_entry;queue.ensure_collision(clip)
	queue._reference_proof=Deferred.OwnershipProof.new();before=service.submissions
	check(not queue.ensure_collision(clip) and service.submissions==before+1,"foreign proof cannot use the cached request shortcut")
	queue._reference_proof=issued.proof
	service.cancel("fixture_cancel");before=service.submissions
	check(not queue.ensure_collision(clip) and service.submissions==before+1,"cancelled coordinator cannot inherit a previously accepted ticket or ready result")
	var planning:RefCounted=service._planning;var preparing:RefCounted=service._preparing
	service.free()
	map.get_node("CollisionInstanceResidency").free()
	var source_bytes:=FileAccess.get_file_as_bytes(model);put(model,source_bytes+" ".to_utf8_buffer())
	service=Service.new();map.add_child(service)
	check(service.configure(issued.index,author.path,folder,issued.proof,map,8).ok,"replacement coordinator owns a fresh live epoch")
	check(not queue.ensure_collision(clip) and service.submissions==1,"replacement service identity cannot reuse its predecessor's submission")
	for i in 600:
		await process_frame
		queue.ensure_collision(clip)
		if service.status("item0").state=="fallback":break
	check(service.status("item0").state=="fallback" and not queue.ensure_collision(clip) and service._store.debug_snapshot().instances==0,"changed source SHA still fails actual worker validation and never grants collision readiness")
	queue.release_demand("player_collision");map.free();helper.free()
	for i in 300:
		if planning.count()==0 and preparing.count()==0:break
		await process_frame
	check(planning.count()==0 and preparing.count()==0,"cancelled old generation drains its actual worker reservations")
	Deferred.collision_first_enabled=old_first;Deferred.collision_query_cache_enabled=old_cache;Deferred.collision_query_profile_enabled=old_profile
	await process_frame;await process_frame
	finish(errors)
