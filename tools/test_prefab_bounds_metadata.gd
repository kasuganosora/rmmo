extends "res://tools/test_house_geometry_identity_reuse.gd"
const Metadata=preload("res://scripts/world3d/prefab_bounds_metadata.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	var directory:=Paths.cache_directory("prefab_bounds_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var source:=fixture();var value:=encode(source)
	var original:=House.local_bounds(value)
	var cold=Metadata.new(directory)
	check(cold.bounds(value)==original and cold.misses==1,"first observation preserves exact stored bounds and padding")
	cold.save();evict(value.sha256)
	var cached=Metadata.new(directory)
	for i:int in 512:
		var r:=record(value);r.kind="asset";r.position=[i*.73,2.1,-i*.41];r.rotation=[i%13,i*7%360,i%17];r.size=[.8,1.3,2.1]
		var actual:=Index._prefab_bounds(r,cached)
		var pose:=Transform3D(Basis.from_euler(Vector3(r.rotation[0],r.rotation[1],r.rotation[2])*PI/180.).scaled_local(Vector3(.8,1.3,2.1)),Vector3(r.position[0],2.1,r.position[2]))
		if actual.bounds!=pose*original.bounds:failures+=1
	check(cached.hits==512 and cached.misses==0 and not House._decoded.has(value.sha256),"512 moved/scaled instances classify without decoding any prefab geometry")
	check(failures==0,"each instance uses current pose and exact source bounds")
	var wall:=record(value);wall.fortification={"id":"wall","part":"module","role":"prefab"};wall.prefab_locked=true;wall.prefab_materials=[]
	var expected_row:=Index._classify(wall,directory,{})
	check(expected_row.reason=="native_fortification","fixture is a supported frozen wall")
	evict(value.sha256)
	var actual_row:=Index._classify(wall,directory,{}, {},true,cached)
	check(actual_row==expected_row,"trusted structure keeps exact bounds, classification and owners")
	check(not House._decoded.has(value.sha256),"trusted structure eligibility does not secretly decode cached geometry again")
	var modified:=fixture();modified.meshes[0].bounds=AABB(Vector3(-5,-2,-1),Vector3(8,3,4));var changed:=encode(modified)
	check(cached.bounds(changed)==House.local_bounds(changed) and cached.misses==1,"changed content identity recomputes bounds")
	var wrong:=value.duplicate();wrong.length+=1
	# A length mismatch cannot use a stored bound, even with the same digest.
	cached.bounds(wrong);check(cached.misses==2,"mismatched length takes the normal decode path")
	var first:=cached.bounds(value);first.bounds=AABB()
	check(cached.bounds(value)==original,"returned observation cannot mutate cached bounds")
	var file:=FileAccess.open(cached._path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
	var corrupt=Metadata.new(directory)
	check(corrupt.bounds(value)==original and corrupt.misses==1,"truncated optional metadata falls back to geometry")
	corrupt._values[value.sha256]=["invalid derived entry"]
	check(corrupt.bounds(value)==original and corrupt.misses==2,"malformed optional metadata does not abort while holding its mutex")
	var worker:=Thread.new();worker.start(corrupt.bounds.bind(value))
	check(worker.wait_to_finish()==original,"another worker can read the repaired entry after malformed-cache fallback")
	DirAccess.remove_absolute(cached._path)
	print("PREFAB_BOUNDS_METADATA checks=",checks," failures=",failures);quit(1 if failures else 0)
