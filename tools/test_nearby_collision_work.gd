extends SceneTree
## Reproduce per-physics-tick work with live publication/removal and mutable
## bounds. No cached readiness: absent/freed bodies must be seen immediately.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var checks:=0
var failures:=0
var map:Node3D
var library:Array=[]
var bodies:Dictionary={}
class CountedMesh:
	extends Mesh
	var bounds:=AABB(-Vector3.ONE*.5,Vector3.ONE)
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
func current_data()->Dictionary:
	var result:Dictionary={}
	for key:StringName in map.get_meta_list():
		if str(key).begins_with("stream_"):result[key]=map.get_meta(key)
	return result
func legacy(origin:Vector3)->bool:
	var area:=Rect2(origin.x-2,origin.z-2,4,4)
	var low:=Stream.chunk_key(Vector3(area.position.x,0,area.position.y))
	var high:=Stream.chunk_key(Vector3(area.end.x,0,area.end.y))
	var index:Dictionary=map.get_meta("stream_collision_index",{})
	var batched:Dictionary=map.get_meta("fortification_collision_sources",{})
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for item:Dictionary in index.get(Vector2i(x,z),[]):
				var extra:Dictionary=item.get("extras",{})
				if item.get("native_visual",false) or extra.get("hostile",false) or extra.get("ally",false) or extra.get("rmmo_collision","")=="none":continue
				var bounds:AABB=item.transform*item.mesh.get_aabb()
				if not area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)):continue
				if not batched.has(item.uuid) and not is_instance_valid(bodies.get(item.uuid)):return false
	return true
func compare(origin:Vector3,expected:bool,label:String)->void:
	check(legacy(origin)==expected and Stream.nearby_collision_ready(map,origin)==expected,label)
func run()->void:
	map=Node3D.new();root.add_child(map);map.set_meta("stream_bodies",bodies)
	var shared:=CountedMesh.new()
	# All four buckets share these sources, as long terrain/house members do.
	for i in 1000:
		var row:=spec("solid_%d"%i,Vector3(32,0,32),shared)
		row.chunk_min=Vector2i.ZERO;row.chunk_max=Vector2i.ONE
		library.append(row)
	var body:=StaticBody3D.new();map.add_child(body)
	for row:Dictionary in library:bodies[row.uuid]=body
	adopt(Index.build(library))
	var origin:=Vector3(32,0,32)
	compare(origin,true,"resident multi-cell neighborhood is ready")
	shared.reads=0;var began:=Time.get_ticks_usec()
	for i in 120:Stream.nearby_collision_ready(map,origin)
	var elapsed:=Time.get_ticks_usec()-began
	print("NEARBY_WORK ",JSON.stringify({"calls":120,"sources":1000,"bounds_reads":shared.reads,"total_ms":elapsed/1000.,"candidates":Stream.collision_candidate_cache_stats(map)}))
	check(shared.reads==0,"resident colliders need no bounds queries across 120 ticks")
	bodies.erase("solid_999");compare(origin,false,"same-cell collider removal immediately blocks")
	var last:Dictionary=library.back();last.transform.origin=Vector3(60,0,60)
	compare(origin,true,"missing body outside exact footprint does not block")
	shared.reads=0
	check(Stream.nearby_collision_ready(map,origin) and shared.reads==1,"missing cross-cell source is examined once per query")
	last.transform.origin=origin;last.extras.rmmo_collision="none"
	compare(origin,true,"live collision-none source is excluded")
	last.extras.rmmo_collision="block";compare(origin,false,"restored collision mode requires body")
	last.extras.ally=true;compare(origin,true,"ally exclusion remains live");last.extras.erase("ally")
	last.extras.hostile=true;compare(origin,true,"hostile exclusion remains live");last.extras.erase("hostile")
	last.native_visual=true;compare(origin,true,"native visual exclusion remains live");last.erase("native_visual")
	map.set_meta("fortification_collision_sources",{last.uuid:last})
	compare(origin,true,"legacy aggregate source presence contract is preserved")
	map.get_meta("fortification_collision_sources").clear()
	compare(origin,false,"aggregate source removal is visible on next call")
	var replacement:=CountedMesh.new();last.mesh=replacement;last.transform.origin=Vector3(35,0,32)
	compare(origin,true,"replacement mesh initially outside footprint")
	replacement.bounds=AABB(Vector3(-3,-.5,-.5),Vector3(6,1,1))
	compare(origin,false,"bounds mutation without changed signal is visible")
	bodies[last.uuid]=body;compare(origin,true,"body publication immediately removes blocker")
	body.free();compare(origin,false,"freed references never inherit cached readiness")
	body=StaticBody3D.new();map.add_child(body)
	for row:Dictionary in library:bodies[row.uuid]=body
	var missing:=spec("new_missing",origin,shared)
	var added:=Index.append(current_data(),[missing]);library.append(missing);adopt(added.data)
	compare(origin,false,"append within cached cells blocks immediately")
	var removed:=Index.retire(current_data(),library,[missing.uuid]);adopt(removed.data)
	compare(origin,true,"retirement releases cached membership")
	var door_mesh:=BoxMesh.new();door_mesh.size=Vector3(3,2,.15)
	var door:=spec("door",Vector3(30.9,1,8),door_mesh)
	door.extras={"building":{"id":"house"},"fixture":{"id":"front","kind":"door","pivot":[1.5,0,0],"angle":90.,"open":0.}}
	Fixtures.prepare_spec(door);library.append(door);adopt(Index.build(library));map.set_meta("stream_library",library)
	compare(Vector3(29,1,8),false,"missing closed hinge blocks near footprint")
	check(Fixtures.set_runtime(map,"house","front",1.,0.).ok,"real runtime hinge publisher changes pose")
	compare(Vector3(29,1,8),true,"hinge moving away is observed within same indexed cells")
	compare(door.position,false,"hinge moving into footprint is immediately required")
	var old_cache:Dictionary=map.get_meta("stream_collision_candidate_cache")
	library.erase(door);adopt(Index.build(library));map.set_meta("stream_collision_candidate_cache",old_cache)
	compare(door.position,true,"rebuilt index identity rejects previous cached membership")
	map.remove_meta("stream_collision_revision")
	compare(origin,true,"unversioned callers retain the uncached path")
	Stream.collision_candidate_cache_enabled=false
	compare(origin,true,"diagnostic cache-off path remains equivalent")
	Stream.collision_candidate_cache_enabled=true
	map.free()
	print("NEARBY_COLLISION_WORK checks=",checks," failures=",failures)
	quit(1 if failures else 0)
