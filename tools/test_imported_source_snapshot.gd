extends SceneTree
## CPU-only source/annotation identity regression, including a warmed cache.
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Fixture=preload("res://tools/test_asset_bounds_manifest.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var failures:=0
var checks:=0
var directory:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func write(path:String,data:Dictionary,payload:PackedByteArray)->void:
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(bytes.size()+payload.size()+28)
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(payload.size());file.store_32(0x004e4942);file.store_buffer(payload);file.close()
func run()->void:
	directory=preload("res://scripts/world3d/map_paths.gd").cache_directory("source_snapshot_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("source.glb")
	var fixture:=Fixture.new();var data:Dictionary=fixture.data();fixture.free()
	data.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":[{"id":"hall","floor":0,"min":[-1,0,-1],"max":[1,3,1]}]}}
	data.nodes[1].extras={"rmmo_source_uuid":"floor","rmmo_part":{"floor":0,"floor_y":0,"role":"floor","part":"slab"}}
	var payload:=PackedByteArray();payload.resize(8*1024*1024+36);payload.fill(7)
	data.buffers[0].byteLength=payload.size();write(path,data,payload)
	var digest:=FileAccess.get_sha256(path)
	var old:=Imported.source_descriptor(path,digest)
	check(not old.is_empty(),"reference accepts complete fixture")
	Imported._sources.clear();Trace.start()
	var fresh:=Imported.read_source_descriptor(path,digest)
	var trace:Dictionary=Trace.stop()
	var reads:Array=trace.events.filter(func(e):return e.label=="imported.source_read")
	check(Imported.same(fresh,old),"one-read descriptor equals the original complete check")
	check(reads.size()==1 and reads[0].details.bytes==FileAccess.get_file_as_bytes(path).size() and reads[0].details.binary_chunks==3,"one complete bounded read covers JSON, binary headers and all payload bytes")
	check(Imported.same(Imported.read_source_descriptor(path),old),"unspecified digest still authenticates the complete source")
	fresh.members.floor.role="roof"
	check(Imported.read_source_descriptor(path,digest).members.floor.role=="floor","caller mutations cannot poison cached descriptors")
	check(Imported.read_source_descriptor(path,"a".repeat(64)).is_empty(),"wrong expected digest rejected even with a warm descriptor cache")
	var stamp:=FileAccess.get_modified_time(path)
	payload[payload.size()-1]=8;write(path,data,payload)
	check(Imported.read_source_descriptor(path,digest).is_empty(),"same-length binary replacement rejected after cache warmup")
	var changed:=Imported.read_source_descriptor(path)
	check(not changed.is_empty() and changed.source_sha!=digest,"new complete source gets its own authenticated identity")
	data.nodes[1].extras.rmmo_part.role="roof";write(path,data,payload)
	check(Imported.read_source_descriptor(path,changed.source_sha).is_empty(),"changed metadata cannot borrow previous payload identity")
	var roof:=Imported.read_source_descriptor(path)
	check(roof.members.floor.role=="roof" and roof.source_sha==FileAccess.get_sha256(path),"annotations and SHA derive from the same replacement bytes")
	var record:={"kind":"asset","asset_path":path,"size":[1,1,1],"model_building":roof}
	check(Imported.verify_source(record),"real record verification accepts current complete source")
	data.nodes[1].extras.rmmo_part.role="bad";write(path,data,payload)
	check(not Imported.verify_source(record) and Imported.read_source_descriptor(path).is_empty(),"invalid metadata rejected independently of digest cache")
	var bytes:=FileAccess.get_file_as_bytes(path)
	for cut:int in [0,19,27,bytes.size()-1]:
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes.slice(0,cut));file.close()
		check(Imported.read_source_descriptor(path).is_empty(),"truncated source rejected at %d"%cut)
	DirAccess.remove_absolute(path)
	check(Imported.read_source_descriptor(path,digest).is_empty(),"removed source cannot be supplied from descriptor cache")
	DirAccess.remove_absolute(directory)
	print("SOURCE_SNAPSHOT checks=",checks," failures=",failures," initial_timestamp=",stamp)
	quit(0 if failures==0 else 1)
