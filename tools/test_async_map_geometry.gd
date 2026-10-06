extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const TerrainCache=preload("res://scripts/world3d/terrain_context_cache.gd")
var failed:=0
var emitted:=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failed+=1
func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var doc:=Doc.new()
	for x in [0,8]:
		var id:=doc.add_box("grass",Vector3(x,0,0),Vector3(8,1,8))
		var r:Dictionary=doc._find(id)
		r.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-4.,"heights":[0.,.2,.4,.1,.3,.5,.2,.4,.6],"holes":[false,false,false,x==0]}
		if x==0:
			r.terrain_regions={"materials":[{"name":"soil","color":[.5,.3,.2,1.],"roughness":1.}],"regions":[{"id":"field","polygon":[[-3.,-3.],[3.,-3.],[3.,3.],[-3.,3.]],"feather":1.,"opacity":1.,"layer":0,"furrows":{"spacing":1.6,"height":.18,"angle":12.,"phase":0.,"margin":.5,"setback":.2}}]}
	var road:=doc.add_box("stone",Vector3(0,1,10),Vector3(8,.2,8))
	doc._find(road).road_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.4,.5],[-.3,.4]]],"uv_origin":[0,1,10],"grade":[.05,-.02]}
	doc.add_box("wood",Vector3(0,2,0),Vector3.ONE)
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("async_geometry_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"map_ref":"test/async","rmmo_records":doc.records}}]}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	# Use the same serialized values as a normal reopen, including number types.
	doc.records=JSON.parse_string(JSON.stringify(doc.records));doc.terrain_neighbors.update(doc.records)
	for record:Dictionary in doc.records:
		if record.has("terrain_regions"):doc.terrain_neighbors.data[record.uuid].region_mask=preload("res://scripts/world3d/terrain_regions.gd").mask(record)
	var snapshot:=TerrainCache.pack(doc.terrain_neighbors)
	var restored:=TerrainCache.restore(snapshot,doc.records)
	check(restored!=null and TerrainCache.pack(restored)==snapshot and restored.update(doc.records).is_empty(),"derived context round trip preserves normals, pixels and incremental identity")
	var first_id:String=snapshot.keys()[0]
	for mode in ["pixels","normal","padding","neighbor"]:
		var bad:=snapshot.duplicate(true)
		if mode=="pixels":bad[first_id].image.bytes=PackedByteArray([0])
		elif mode=="normal":bad[first_id].normals[-1]=Vector3.UP
		elif mode=="padding":bad[first_id].padding=Vector2(NAN,0)
		else:bad[first_id].neighbors.append("absent")
		check(TerrainCache.restore(bad,doc.records)==null,"reject malformed terrain cache: "+mode)
	var changed:Array=doc.records.duplicate(true);changed[0].terrain_mesh.heights[0]+=.1
	check(TerrainCache.restore(snapshot,changed)==null,"changed terrain cannot reuse old seam context")
	var expected:Dictionary={}
	for r:Dictionary in doc.records:
		var node:=doc._mesh(r);expected[r.uuid]=Stream._spec(node);node.free()
	for pass_index in 4:
		if pass_index==2:
			var Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
			var cache:=Cook.read(path,FileAccess.get_sha256(path),Cook.generator_key())
			cache.terrain_context[first_id].image.bytes=PackedByteArray([0]);Cook.write(path,cache)
		var loader:=Loader.new();root.add_child(loader);loader.start(path)
		var loaded:Array=await loader.finished
		check(loaded[0]!=null,"async native load succeeds, pass %d"%pass_index)
		if loaded[0]==null:print(loaded[2]);quit(1);return
		check(bool(loaded[0].get_meta("load_profile").terrain_context_cache_hit)==(pass_index%2==1),"derived terrain context rebuilds cold/corrupt data and restores warm/repaired data")
		var library:Array=loaded[0].get_meta("stream_library")
		var equal_:bool=library.size()==expected.size()
		for spec:Dictionary in library:
			var original:Dictionary=expected[spec.uuid]
			equal_=equal_ and spec.transform==original.transform and spec.chunk_min==original.chunk_min and spec.chunk_max==original.chunk_max
			equal_=equal_ and var_to_bytes(Cpu.capture(spec.mesh).surfaces)==var_to_bytes(Cpu.capture(original.mesh).surfaces)
			var actual_collision:Mesh=spec.get("collision_mesh",spec.mesh)
			var expected_collision:Mesh=original.get("collision_mesh",original.mesh)
			equal_=equal_ and actual_collision.get_faces()==expected_collision.get_faces()
		check(equal_,"cold/warm geometry preserves slopes, holes, furrows, UVs, normals, tangents and collision")
		check(loaded[0].has_meta("stream_collision_index") and loaded[0].has_meta("stream_index"),"worker returns render and physics indices")
		loaded[0].free()
		while is_instance_valid(loader):await process_frame
	var cancelled:=Loader.new();root.add_child(cancelled)
	cancelled.finished.connect(func(scene,_path,_error):emitted=true;if scene!=null:scene.free())
	cancelled.start(path);cancelled.cancel()
	while is_instance_valid(cancelled):await process_frame
	check(not emitted,"cancelled async load retires all workers without handing off a scene")
	print("ASYNC_MAP_GEOMETRY_FINISHED failures=",failed);quit(1 if failed else 0)
