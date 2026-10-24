extends SceneTree
const Legacy=preload("res://scripts/world3d/road_surface.gd")
const Bulk=Legacy
const Fixture=preload("res://tools/test_native_road_preparation.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func real_roads()->Dictionary:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
	var before:=FileAccess.get_sha256(path);var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var seen:Dictionary={};var roads:Dictionary={};var count:=0;var old_us:=0;var new_us:=0;var exact:=true
	for compact:Dictionary in document.nodes[0].extras.rmmo_records:
		if not compact.has("rmmo_ref"):continue
		var source:=path.get_base_dir().path_join(compact.rmmo_ref.uri)
		if not seen.has(source):
			seen[source]=FileAccess.get_sha256(source)
			var bytes:=FileAccess.get_file_as_bytes(source)
			var definition:Dictionary=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
			if definition.has("road_mesh"):roads[source]=true
		if not roads.has(source):continue
		var hydrated:=preload("res://scripts/world3d/map_resource_store.gd").read_records([compact],path,"D:/code/rmmo_runtime",null,1,true)
		if not hydrated.ok:exact=false;continue
		var record:Dictionary=hydrated.records[0]
		if not record.road_mesh.has("kerbs"):continue
		var began:=Time.get_ticks_usec();var old:=Legacy.arrays_legacy(record);old_us+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var current:=Legacy.arrays(record);new_us+=Time.get_ticks_usec()-began
		if var_to_bytes(old)!=var_to_bytes(current):print("MISMATCH ",compact.uuid);exact=false
		count+=1
	check(exact and count>200,"all real axel_town road channels are byte-identical to the previous implementation")
	var unchanged:=FileAccess.get_sha256(path)==before
	for source:String in seen:unchanged=unchanged and FileAccess.get_sha256(source)==seen[source]
	check(unchanged,"real map and all authored resources remain byte-identical")
	return {"roads":count,"old_us":old_us,"new_us":new_us}
func run()->void:
	var helper:=Fixture.new();var records:Array=[]
	for i in 32:
		var record:=helper.road();record.road_mesh.kerbs=[]
		record.road_mesh.polygons=[];record.road_mesh.elevations=[]
		for k in 96:
			var polygon:Array=[];var heights:Array=[]
			for vertex in 8:
				var angle:float=TAU*vertex/8.;polygon.append([cos(angle)*.1,sin(angle)*.1]);heights.append(k*.01+vertex*.007)
			record.road_mesh.polygons.append(polygon);record.road_mesh.elevations.append(heights)
		record.terrain_grade=[.01,-.02];record.road_mesh.uv_origin=[i*.23,-i*.17,i*.11]
		for j in 128:
			var part:=helper.part(j%2==0,j%3==0)
			for side:String in ["a","b"]:
				for p:Array in part[side]:p[0]+=j*.13;p[1]+=float(p[0])*.037+float(p[2])*.011;p[2]+=i*.07
			part.u=i*17.3+j*.31;record.road_mesh.kerbs.append(part)
		records.append(record)
	
	var before:=var_to_bytes(records);var old_us:=0;var new_us:=0;var expected:Array=[]
	for record:Dictionary in records:
		var began:=Time.get_ticks_usec();var old:=Legacy.arrays_legacy(record);old_us+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var newer:=Bulk.arrays(record);new_us+=Time.get_ticks_usec()-began
		check(var_to_bytes(old)==var_to_bytes(newer),"all channels including exact winding, normals, UV and tangent bytes match")
		expected.append(newer)
	var threads:Array=[]
	for i in 4:
		var thread:=Thread.new();thread.start(Bulk.arrays.bind(records[i]));threads.append(thread)
	for i in threads.size():check(var_to_bytes(threads[i].wait_to_finish())==var_to_bytes(expected[i]),"independent worker channels preserve exact output")
	check(before==var_to_bytes(records),"source records remain unchanged")
	helper.free()
	var real:=real_roads()
	print("ROAD_SURFACE_ARRAYS ",JSON.stringify({"roads":records.size(),"kerbs_per_road":128,"old_us":old_us,"new_us":new_us,"real":real,"failures":failures}));quit(1 if failures else 0)
