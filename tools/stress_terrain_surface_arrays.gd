extends SceneTree
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Fixture=preload("res://tools/test_terrain_surface.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func real_terrains()->Dictionary:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
	var before:=FileAccess.get_sha256(path);var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var seen:Dictionary={};var terrains:Dictionary={};var count:=0;var old_us:=0;var new_us:=0;var exact:=true
	for compact:Dictionary in document.nodes[0].extras.rmmo_records:
		if not compact.has("rmmo_ref"):continue
		var source:=path.get_base_dir().path_join(compact.rmmo_ref.uri)
		if not seen.has(source):
			seen[source]=FileAccess.get_sha256(source)
			var bytes:=FileAccess.get_file_as_bytes(source)
			var definition:Dictionary=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
			if definition.has("terrain_mesh"):terrains[source]=true
		if not terrains.has(source):continue
		var hydrated:=preload("res://scripts/world3d/map_resource_store.gd").read_records([compact],path,"D:/code/rmmo_runtime",null,1,true)
		if not hydrated.ok:exact=false;continue
		var record:Dictionary=hydrated.records[0]
		var began:=Time.get_ticks_usec();var old:=Terrain.arrays_legacy(record);old_us+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var current:=Terrain.arrays(record);new_us+=Time.get_ticks_usec()-began
		if var_to_bytes(old)!=var_to_bytes(current):print("MISMATCH ",compact.uuid);exact=false
		count+=1
	check(exact and count>=63,"all real axel_town terrain channels are byte-identical")
	var unchanged:=FileAccess.get_sha256(path)==before
	for source:String in seen:unchanged=unchanged and FileAccess.get_sha256(source)==seen[source]
	check(unchanged,"real map and authored resources remain byte-identical")
	return {"terrains":count,"old_us":old_us,"new_us":new_us}
func run()->void:
	var cases:Array=[];var contexts:Array=[];var expected:Array=[];var old_us:=0;var new_us:=0
	for trial in 32:
		var n:int=[2,16,32,64][trial%4];var record:=Fixture.fixture()
		record.terrain_mesh.columns=n;record.terrain_mesh.rows=n
		record.terrain_mesh.heights.resize((n+1)*(n+1));record.terrain_mesh.holes.resize(n*n)
		record.size=[.01 if trial%5==0 else 47.,.1 if trial%2==0 else 3.,71.]
		record.terrain_material={"tile_size":[.37,7.1]}
		for at in record.terrain_mesh.heights.size():record.terrain_mesh.heights[at]=sin(at*.23)*.5
		for at in record.terrain_mesh.holes.size():record.terrain_mesh.holes[at]=trial%3==0 and at%2==0
		var context:={"normals":{0:Vector3.UP,n+1:Vector3(.1,1,.2).normalized()}}
		cases.append(record);contexts.append(context)
	var field:=Fixture.fixture()
	field.terrain_regions={"materials":[{}],"regions":[{"id":"field","layer":0,"opacity":.8,"feather":.5,"polygon":[[-3,-3],[3,-3],[3,3],[-3,3]],"furrows":{"angle":17.,"height":.1,"margin":.5,"setback":.2,"spacing":2.,"phase":0.}}]}
	cases.append(field);contexts.append({})
	var before:=var_to_bytes([cases,contexts])
	for i in cases.size():
		var began:=Time.get_ticks_usec();var old:=Terrain.arrays_legacy(cases[i],contexts[i]);old_us+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var current:=Terrain.arrays(cases[i],contexts[i]);new_us+=Time.get_ticks_usec()-began
		check(var_to_bytes(old)==var_to_bytes(current),"exact indexed topology, seam normals, UV and tangent bytes "+str(i));expected.append(current)
	var threads:Array=[]
	for i in 4:
		var thread:=Thread.new();thread.start(Terrain.arrays.bind(cases[i+24],contexts[i+24]));threads.append(thread)
	for i in 4:check(var_to_bytes(threads[i].wait_to_finish())==var_to_bytes(expected[i+24]),"independent worker channels remain exact")
	check(before==var_to_bytes([cases,contexts]),"input heights, holes, paint and shared seam contexts remain unchanged")
	check(expected.back().size()==3,"cultivation surface remains present and exact")
	print("TERRAIN_SURFACE_ARRAYS ",JSON.stringify({"cases":cases.size(),"old_us":old_us,"new_us":new_us,"real":real_terrains(),"failures":failures}));quit(1 if failures else 0)
