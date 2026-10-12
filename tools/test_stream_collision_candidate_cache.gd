extends SceneTree
## Small headless equivalence fixtures; no triangle upload or town benchmark.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var checks:=0
var failures:=0
var map:Node3D
var library:Array=[]
var bodies:Dictionary={}
var original_enabled:=Stream.collision_candidate_cache_enabled
var original_profile:=Stream.collision_readiness_profile_enabled
class FortLookup:
	extends Node3D
	var body:StaticBody3D
	func body_for(_uuid:String)->Variant:return body
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func item(id:String,at:Vector3,size:=Vector3.ONE)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size
	var pose:=Transform3D(Basis.IDENTITY,at);var bounds:=pose*AABB(-size*.5,size)
	return {"uuid":id,"mesh":mesh,"transform":pose,"position":at,"chunk":Stream.chunk_key(at),"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end),"extras":{}}
func adopt(data:Dictionary)->void:
	for key:String in data:map.set_meta(key,data[key])
func rebuild()->void:adopt(Index.build(library))
func current_data()->Dictionary:
	var data:Dictionary={}
	for key:StringName in map.get_meta_list():
		if str(key).begins_with("stream_"):data[key]=map.get_meta(key)
	return data
func body_for(source:Dictionary,published:bool=true)->StaticBody3D:
	var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape)
	map.add_child(body);body.global_transform=source.transform
	if published:body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	bodies[source.uuid]=body
	return body
func compare(clip:AABB,expected:bool,label:String)->Dictionary:
	Stream.collision_candidate_cache_enabled=false
	var old:=Stream.collision_readiness(map,clip)
	Stream.collision_candidate_cache_enabled=true
	var fresh:=Stream.collision_readiness(map,clip)
	check(old==fresh and fresh.ok==expected,label)
	return fresh
func settle()->void:
	await physics_frame;await physics_frame;await process_frame
func run()->void:
	map=Node3D.new();root.add_child(map);map.set_meta("stream_bodies",bodies)
	var floor:=item("floor",Vector3(8,-.25,8),Vector3(16,.5,16))
	var wall:=item("wall",Vector3(12,1,8),Vector3(1,2,4))
	library=[floor,wall];rebuild()
	var clip:=AABB(Vector3(7.5,-1,7.5),Vector3(1,3,1))
	compare(clip,false,"catalogue alone remains pending")
	var floor_body:=body_for(floor)
	compare(clip,false,"actual collider is pending on publication tick")
	await settle()
	compare(clip,true,"physics-synchronized floor is ready")
	var cache:Dictionary=map.get_meta("stream_collision_candidate_cache")
	var key:=Vector4i(0,0,0,0)
	var candidates:Array=cache.ranges[key].items
	compare(clip,true,"unchanged footprint reuses candidates without a ready cache")
	check(Stream.collision_candidate_cache_stats(map).hits>0 and is_same(candidates,cache.ranges[key].items),"cache hit keeps candidate identity")
	var moved_clip:=AABB(Vector3(11.5,-1,7.5),Vector3(1,3,1))
	compare(moved_clip,false,"moving exact footprint inside same cell sees missing wall")
	wall.transform.origin=Vector3(8,1,8)
	compare(clip,false,"current spec pose is read on cache hit")
	wall.transform.origin=Vector3(12,1,8)
	compare(clip,true,"moving spec back restores prior exact overlap")
	wall.mesh.size=Vector3(9,2,4)
	compare(clip,false,"in-place primitive bounds change is visible on cache hit")
	wall.mesh.size=Vector3(1,2,4)
	var replacement:=BoxMesh.new();replacement.size=Vector3(9,2,4);wall.collision_mesh=replacement
	compare(clip,false,"replacement collision mesh is read without membership change")
	var cpu:=Cpu.new();cpu.bounds=AABB(Vector3(-.5,-1,-2),Vector3(1,2,4));wall.collision_mesh=cpu
	compare(clip,true,"replacement CPU bounds use current source")
	cpu.bounds=AABB(Vector3(-4.5,-1,-2),Vector3(9,2,4))
	compare(clip,false,"CPU bounds mutate without Resource.changed and still invalidate")
	wall.erase("collision_mesh")
	wall.extras.rmmo_collision="none"
	compare(moved_clip,true,"live collision mode none is not cached")
	wall.extras.rmmo_collision="block"
	compare(moved_clip,false,"live collision mode restored requires real body")
	var wall_body:=body_for(wall)
	compare(moved_clip,false,"new body on cached candidate waits for physics frame")
	await settle();compare(moved_clip,true,"new body becomes ready after sync")
	wall_body.collision_layer=0;compare(moved_clip,false,"disabled body layer is checked on every hit")
	wall_body.collision_layer=1
	map.remove_child(wall_body);compare(moved_clip,false,"body removed from SceneTree cannot satisfy receipt")
	map.add_child(wall_body);wall_body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	compare(moved_clip,false,"reinserted body publication tick is live")
	await settle();compare(moved_clip,true,"reinserted collider sync is live")
	var new_shape:=BoxShape3D.new();new_shape.size=Vector3(1,3,4)
	wall_body.get_child(0).shape=new_shape
	wall_body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	compare(moved_clip,false,"shape replacement publication watermark is never cached")
	await settle();compare(moved_clip,true,"replacement shape is accepted after publisher sync")
	wall_body.free();compare(moved_clip,false,"freed body reference cannot inherit readiness")
	wall_body=body_for(wall,false);compare(moved_clip,false,"replacement body without publication evidence is pending")
	wall_body.set_meta("stream_physics_published_frame",Engine.get_physics_frames()-1)
	compare(moved_clip,true,"replacement body evidence is read directly")
	wall_body.queue_free();compare(moved_clip,false,"queued deletion blocks even before actual free")
	await process_frame;bodies.erase(wall.uuid)
	var fort:=FortLookup.new();fort.name="FortificationCollisionBatches";map.add_child(fort)
	map.set_meta("fortification_collision_sources",{wall.uuid:wall})
	compare(moved_clip,false,"fortification source dictionary is not physical evidence")
	fort.body=body_for(wall);bodies.erase(wall.uuid)
	compare(moved_clip,false,"actual fort body still requires later physics tick")
	await settle();compare(moved_clip,true,"fortification body lookup remains live")
	fort.body.collision_layer=0;compare(moved_clip,false,"disabled aggregate fort body blocks cached candidates")
	fort.body.free();fort.free();map.remove_meta("fortification_collision_sources")
	# An append and a retirement mutate the same index object: revision and
	# immediate cache clearing must cover both, including an equal-count ABA.
	var data:=current_data();var revision:int=data.stream_collision_revision
	var addition:=item("new_prop",Vector3(8,1,8))
	var appended:=Index.append(data,[addition]);library.append(addition);adopt(appended.data)
	check(appended.ok and data.stream_collision_revision==revision+1 and cache.is_empty(),"append invalidates and releases prior candidate owners immediately")
	compare(clip,false,"same-cell append is visible on next call")
	cache=map.get_meta("stream_collision_candidate_cache")
	var removed:=Index.retire(current_data(),library,[addition.uuid]);adopt(removed.data)
	check(removed.ok and cache.is_empty(),"retirement drops cached references before another query")
	compare(clip,true,"retired missing body no longer blocks")
	var before:int=map.get_meta("stream_collision_revision")
	cache=map.get_meta("stream_collision_candidate_cache")
	var rejected:=Index.append(current_data(),[floor])
	check(not rejected.ok and int(map.get_meta("stream_collision_revision"))==before and not cache.is_empty(),"rejected append does not invalidate successful current index")
	var empty:=Index.append(current_data(),[])
	check(empty.ok and empty.data.stream_collision_revision==before,"empty append leaves membership revision unchanged")
	# Full rebuild is independent of numerical revision values. This also
	# models static authored movement across indexed cells: rebuild, not a new
	# source residency revision, is the ownership publication boundary.
	wall.transform.origin=Vector3(40,1,8);wall.chunk=Vector2i(1,0);wall.chunk_min=wall.chunk;wall.chunk_max=wall.chunk
	cache=map.get_meta("stream_collision_candidate_cache");rebuild()
	map.set_meta("stream_collision_candidate_cache",cache)
	compare(moved_clip,true,"rebuilt membership replaces cached index identity")
	compare(AABB(Vector3(39.5,-1,7.5),Vector3(1,3,1)),false,"cross-cell authored move after rebuild requires destination body")
	# Fixtures index the complete hinge sweep once, and current pose/bounds and
	# publication frame continue changing without a membership rebuild.
	var door:=item("door",Vector3(30.9,1,8),Vector3(3,2,.15))
	door.extras={"building":{"id":"house"},"fixture":{"id":"front","kind":"door","pivot":[1.5,0,0],"angle":90.,"open":0.}}
	Fixtures.prepare_spec(door);library.append(door);rebuild();map.set_meta("stream_library",library)
	var door_body:=body_for(door);await settle()
	var door_clip:=AABB(Vector3(30.7,0,7.8),Vector3(.4,2,.4))
	compare(door_clip,true,"closed hinge member is synchronized")
	var changed:=Fixtures.set_runtime(map,"house","front",1.,0.)
	check(changed.ok and door_body.global_transform==door.transform,"real fixture publisher updates authored pose and body together")
	compare(door_clip,true,"opened hinge leaves prior exact footprint even on cache hit")
	var open_clip:=AABB(door.position-Vector3(.2,1,.2),Vector3(.4,2,.4))
	compare(open_clip,false,"opening hinge into another footprint observes new sync watermark")
	await settle();compare(open_clip,true,"opened hinge becomes ready after actual physics tick")
	var multi:=AABB(Vector3(29,0,6),Vector3(5,3,5))
	compare(multi,true,"multi-cell hinge scan stays equivalent")
	var stats:=Stream.collision_candidate_cache_stats(map)
	check(stats.candidate_references>=1,"candidate counters expose retained references")
	for cell in 12:
		compare(AABB(Vector3(100+cell*32,0,100),Vector3(1,2,1)),true,"bounded cache range %d"%cell)
	check(Stream.collision_candidate_cache_stats(map).ranges<=Stream.COLLISION_CANDIDATE_RANGES,"LRU range capacity is bounded")
	compare(AABB(Vector3.ZERO,Vector3(-1,1,1)),false,"negative footprint remains invalid")
	compare(AABB(Vector3(INF,0,0),Vector3.ONE),false,"nonfinite footprint remains invalid")
	# Opt-in counters prove bounds reuse without requiring a noisy benchmark.
	Stream.collision_readiness_profile_enabled=true;Stream.collision_candidate_cache_enabled=true
	Stream.collision_readiness(map,clip);Stream.collision_readiness(map,clip)
	stats=Stream.collision_candidate_cache_stats(map)
	check(stats.profile.calls==2 and stats.profile.last.bounds_updates==0 and stats.profile.last.candidates>0 and stats.profile.last.intersections>0,"diagnostics distinguish candidate hits, bounds reuse and live body checks")
	check(stats.profile.total_us>=stats.profile.bounds_us+stats.profile.body_us,"diagnostic phases are included in total time")
	Stream.collision_candidate_cache_enabled=original_enabled;Stream.collision_readiness_profile_enabled=original_profile
	map.free()
	print("STREAM_COLLISION_CANDIDATE_CACHE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
