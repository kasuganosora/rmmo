extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
const Nearby=preload("res://scripts/world3d/collision_neighborhood_index.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var map:Node3D
var library:Array=[]
var bodies:Dictionary={}
var checks:=0
var failures:=0
class CountedMesh:
	extends Mesh
	var bounds:=AABB(-Vector3.ONE*.2,Vector3.ONE*.4)
	var reads:=0
	func _get_aabb()->AABB:reads+=1;return bounds
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func spec(id:String,at:Vector3,mesh:Mesh)->Dictionary:
	var pose:=Transform3D(Basis.IDENTITY,at);var bounds:=pose*mesh.get_aabb()
	return {"uuid":id,"mesh":mesh,"transform":pose,"position":at,"chunk":Stream.chunk_key(at),"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end),"extras":{}}
func adopt(data:Dictionary)->void:
	for key:String in data:map.set_meta(key,data[key])
func current()->Dictionary:
	var data:Dictionary={}
	for key:StringName in map.get_meta_list():
		if str(key).begins_with("stream_"):data[key]=map.get_meta(key)
	return data
func compare(at:Vector3,expected:bool,label:String)->void:
	Stream.collision_neighborhood_index_enabled=false
	var original:=Stream.nearby_collision_ready(map,at)
	Stream.collision_neighborhood_index_enabled=true
	check(original==expected and Stream.nearby_collision_ready(map,at)==expected,label)
func compare_physics(clip:AABB,expected:bool,label:String)->void:
	Stream.collision_neighborhood_index_enabled=false
	var original:=Stream.collision_readiness(map,clip)
	Stream.collision_neighborhood_index_enabled=true
	var receipt:=Stream.collision_readiness(map,clip)
	check(original==receipt and receipt.ok==expected,label)
func prepared(row:Dictionary)->RefCounted:
	var source:Array=[row];var prep:=Preparation.new();prep.begin_runtime_owned(source)
	while not prep.advance(1000):pass
	return prep
func append_owned(row:Dictionary)->bool:
	var prep:=prepared(row);var before:int=row.mesh.reads if row.mesh is CountedMesh else 0
	var result:=Index.append(current(),prep.runtime_source,prep)
	check(not row.mesh is CountedMesh or row.mesh.reads==before,"owned commit does not reread geometry bounds")
	if result.ok:library.append(row);adopt(result.data)
	return result.ok
func boundaries()->void:
	var nearby:=Nearby.new();var boxes:Dictionary={};var rng:=RandomNumberGenerator.new();rng.seed=20261030
	# Independent brute-force envelope oracle, including exact grid contacts,
	# negative coordinates, transformed boxes and several spatial levels.
	for i in 180:
		var mesh:=BoxMesh.new();mesh.size=Vector3(rng.randf_range(.05,60),1,rng.randf_range(.05,60))
		var row:=spec("random_%d"%i,Vector3(rng.randi_range(-32,32)*4,0,rng.randi_range(-32,32)*4),mesh)
		row.transform.basis=Basis(Vector3.UP,rng.randf_range(-PI,PI))
		var box:AABB=row.transform*mesh.get_aabb();boxes[row.uuid]=Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
		nearby.add(row,box,true)
	var missing:=0
	for i in 400:
		var area:=Rect2(rng.randi_range(-32,32)*4,rng.randi_range(-32,32)*4,rng.randi_range(0,12),rng.randi_range(0,12))
		var found:Dictionary={}
		for candidate:RefCounted in nearby.candidates(area):found[candidate.spec.uuid]=true
		for id:String in boxes:
			if area.intersects(boxes[id],true) and not found.has(id):missing+=1
	check(missing==0,"400 brute-force queries preserve negative coordinates, cell-edge contacts and rotated/multilevel geometry")
func detached_mesh_watch(index:Dictionary)->WeakRef:
	var mesh:=CountedMesh.new();var row:=spec("retire_owner",Vector3(1,0,1),mesh)
	var prep:=prepared(row);var registered:=Index.append(index,prep.runtime_source,prep)
	check(registered.ok,"private spatial fragment transfers before owner-release check")
	prep.dispose()
	return weakref(mesh)
func release_owners()->void:
	var index:=Index.build([],true);var nearby:Nearby=index.stream_collision_neighborhood
	var watch:=detached_mesh_watch(index)
	nearby.candidates(Rect2(0,0,4,4))
	var owned:Array=index.stream_by_id.values();var removed:=Index.retire(index,owned,["retire_owner"])
	check(removed.ok and owned.is_empty() and nearby.members.is_empty() and nearby.levels.is_empty() and nearby.ranges.is_empty(),"retirement releases all fine buckets and cached range owners synchronously")
	check(watch.get_ref()!=null,"retirement receipt deliberately retains the mesh for the caller's cleanup")
	removed={}
	check(watch.get_ref()==null,"retired mesh has no hidden spatial or disposed-publication owner")
func loader_append_paths()->void:
	var index:=Index.build([],true);var mesh:=CountedMesh.new()
	var small:=spec("small",Vector3(20,0,20),mesh)
	var result:=Index.append(index,[small],null,true)
	var nearby:Nearby=index.stream_collision_neighborhood
	check(result.ok and is_same(nearby.members.small.spec,small) and nearby.candidates(Rect2(0,0,4,4)).is_empty(),"small runtime append narrows geometry and binds the original source")
	var floor:=spec("floor",Vector3(24,0,24),mesh)
	floor.ground_batch_record={"kind":"box","surface_id":"ground","size":[.4,.4,.4]}
	var source:Array=[floor];var prep:=Preparation.new();prep.begin(source,true)
	while not prep.advance(100):pass
	check(not prep.runtime_owned and prep.neighborhood!=null,"copied native landscape prepares its fine bounds in existing slices")
	result=Index.append(index,source,prep,true);prep.dispose()
	check(result.ok and is_same(nearby.members.floor.spec,floor) and nearby.candidates(Rect2(0,0,4,4)).is_empty(),"copied runtime projection keeps narrow bounds and original identity after disposal")
	var changed:=spec("changed",Vector3(28,0,28),mesh);source=[changed];prep=Preparation.new();prep.begin(source,true)
	while not prep.advance(100):pass
	changed.transform.origin=Vector3.ZERO
	result=Index.append(index,source,prep,true)
	check(not result.ok and result.error=="stale_private_index" and not nearby.members.has(changed.uuid),"stale copied envelope rejects atomically before spatial publication")
	prep.dispose()
func run()->void:
	boundaries();release_owners();loader_append_paths()
	map=Node3D.new();root.add_child(map);map.set_meta("stream_bodies",bodies)
	var mesh:=CountedMesh.new()
	for z in 32:
		for x in 32:library.append(spec("cell_%d_%d"%[x,z],Vector3(x+.5,0,z+.5),mesh))
	adopt(Index.build(library,true))
	var body:=StaticBody3D.new();map.add_child(body)
	for row:Dictionary in library:bodies[row.uuid]=body
	var at:=Vector3(2.5,0,2.5);var area:=Rect2(.5,.5,4,4)
	compare(at,true,"dense resident neighborhood agrees with original query")
	var nearby:Nearby=map.get_meta("stream_collision_neighborhood")
	var candidates:=nearby.candidates(area)
	check(candidates.size()<100 and nearby.members.size()==1024,"4 m lookup excludes most of the 1024 sources in one 32 m bucket")
	mesh.reads=0
	for i in 120:Stream.nearby_collision_ready(map,at)
	check(mesh.reads==0 and nearby.hits>=120 and is_same(candidates,nearby.candidates(area)),"stationary checks reuse small candidates without geometry reads")
	print("NEIGHBORHOOD_WORK ",JSON.stringify(nearby.snapshot()))
	var clip:=AABB(Vector3(.5,-1,.5),Vector3(4,3,4))
	body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	compare_physics(clip,false,"fine physical query still waits on the publication physics frame")
	await physics_frame;await physics_frame;await process_frame
	compare_physics(clip,true,"fine physical query accepts synchronized collider")
	body.collision_layer=0;compare_physics(clip,false,"fine physical query reads disabled collision layer immediately")
	body.collision_layer=1
	map.remove_child(body);compare_physics(clip,false,"fine physical query rejects body removed from tree")
	map.add_child(body);body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	compare_physics(clip,false,"fine physical query rechecks replacement publication stamp")
	await physics_frame;await physics_frame;await process_frame
	compare_physics(clip,true,"fine physical query accepts republished body after synchronization")
	bodies.erase("cell_2_2");compare(at,false,"same-tick body removal is never hidden by spatial reuse")
	bodies.cell_2_2=body;compare(at,true,"same-tick body publication is immediately visible")
	body.free();compare(at,false,"unexpected freed body also blocks immediately")
	body=StaticBody3D.new();map.add_child(body)
	for row:Dictionary in library:bodies[row.uuid]=body
	bodies.erase("cell_7_2")
	compare(Vector3(4.9,0,2.5),true,"exact footprint still excludes nearby-cell missing source")
	compare(Vector3(5.6,0,2.5),false,"movement inside cached cell union discovers missing source")
	bodies.cell_7_2=body
	var far:=spec("distant",Vector3(1000,0,1000),mesh)
	candidates=nearby.candidates(area)
	check(append_owned(far),"runtime-owned far publication succeeds")
	check(is_same(candidates,nearby.candidates(area)),"far publication preserves current neighborhood cache")
	var removed:=Index.retire(current(),library,[far.uuid]);adopt(removed.data)
	check(removed.ok and is_same(candidates,nearby.candidates(area)),"far retirement preserves current neighborhood cache")
	var close:=spec("close",at,mesh)
	check(append_owned(close),"runtime-owned local publication succeeds")
	compare(at,false,"new local geometry immediately requires its collider")
	check(not is_same(candidates,nearby.candidates(area)),"local publication replaces affected query membership")
	removed=Index.retire(current(),library,[close.uuid]);adopt(removed.data)
	check(removed.ok and nearby.ranges.is_empty() and not nearby.members.has(close.uuid),"local retirement releases query owners before another query")
	compare(at,true,"retired local geometry no longer blocks")
	var wide:=spec("wide_solid",Vector3(18,0,2),mesh)
	var solid:=BoxMesh.new();solid.size=Vector3(32,2,2);wide.collision_mesh=solid
	check(append_owned(wide),"separate collision geometry enters the prepared spatial envelope")
	body.set_meta("stream_physics_published_frame",Engine.get_physics_frames()-1)
	compare(at,true,"distant visual remains outside legacy presence footprint")
	compare_physics(clip,false,"larger collision mesh still blocks exact physics query outside visual bounds")
	bodies.wide_solid=body;compare_physics(clip,true,"collision publication is live in fine physical query")
	removed=Index.retire(current(),library,[wide.uuid]);adopt(removed.data);bodies.erase(wide.uuid)
	compare_physics(clip,true,"collision-only envelope retirement immediately removes its obligation")
	# Public/mutable append must keep its old coarse coverage. It can move
	# within that indexed coverage or change bounds without Resource.changed.
	var dynamic_mesh:=CountedMesh.new();var dynamic:=spec("mutable",Vector3(25,0,25),dynamic_mesh)
	var result:=Index.append(current(),[dynamic]);library.append(dynamic);adopt(result.data)
	compare(at,true,"mutable public append outside footprint does not block")
	dynamic.transform.origin=at;compare(at,false,"public source movement stays live without sealing")
	dynamic.transform.origin=Vector3(10,0,2.5)
	dynamic_mesh.bounds=AABB(Vector3(-10,-1,-1),Vector3(20,2,2))
	compare(at,false,"public CPU bounds mutation without signal stays visible")
	dynamic.extras.rmmo_collision="none";compare(at,true,"collision mode remains live")
	var door_mesh:=BoxMesh.new();door_mesh.size=Vector3(3,2,.15)
	var door:=spec("door",Vector3(30.9,1,8),door_mesh)
	door.extras={"building":{"id":"house"},"fixture":{"id":"front","kind":"door","pivot":[1.5,0,0],"angle":90.,"open":0.}}
	Fixtures.prepare_spec(door)
	check(append_owned(door),"owned hinge publishes full sweep bounds")
	map.set_meta("stream_library",library)
	compare(Vector3(29,1,8),false,"closed hinge blocks its real footprint")
	check(Fixtures.set_runtime(map,"house","front",1.,0.).ok,"real hinge update succeeds")
	compare(Vector3(29,1,8),true,"open hinge leaves closed footprint immediately")
	compare(door.position,false,"open hinge entering another fine cell remains required")
	# A kilometre-scale source must not create millions of fine-cell owners.
	var huge_mesh:=BoxMesh.new();huge_mesh.size=Vector3(100000,1,100000)
	var huge:=spec("huge",Vector3.ZERO,huge_mesh);var large:=Nearby.new()
	large.add(huge,huge.transform*huge_mesh.get_aabb(),true)
	check(large.snapshot().references<=16 and large.candidates(Rect2(20000,20000,4,4)).size()==1,"large terrain uses a coarse level with bounded references")
	for i in 20:nearby.candidates(Rect2(i*20,100,4,4))
	check(nearby.ranges.size()<=Nearby.CACHE_RANGES,"moving player keeps bounded query cache")
	var replaced:=Index.build(library,true);adopt(replaced)
	map.set_meta("stream_collision_neighborhood",nearby)
	compare(door.position,false,"stale neighborhood owner cannot override a rebuilt coarse index")
	adopt(Index.build(library))
	check(not map.has_meta("stream_collision_neighborhood"),"public rebuild releases prior immutable neighborhood owner")
	compare(door.position,false,"public rebuild preserves ordinary live query fallback")
	map.free()
	print("COLLISION_NEIGHBORHOOD_INDEX checks=",checks," failures=",failures)
	quit(1 if failures else 0)
