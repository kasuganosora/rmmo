extends SceneTree
const House=preload("res://scripts/world3d/house_prefab.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(300000)
	for i in 100000:
		vertices[i*3]=Vector3(i,0,0);vertices[i*3+1]=Vector3(i+1,0,0);vertices[i*3+2]=Vector3(i,1,0)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var data:={"materials":[{"null":true}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3.ZERO,Vector3(100000,1,0)),"box_size":Vector3.ZERO}],"entries":[[["shared"],[0,0]]],"specs":[]}
	var bytes:=var_to_bytes(data)
	return {"version":1,"length":bytes.size(),"sha256":House.Cook.Envelope.checksum(bytes).hex_encode(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func concurrent(value:Dictionary,coalesce:bool,valid:bool=true)->Dictionary:
	House.evict_geometry({value.sha256:true});House.coalesce_decodes=coalesce
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array[Thread]=[]
	Trace.minimum_event_us=0;Trace.start();var began:=Time.get_ticks_usec()
	for i in 8:
		var thread:=Thread.new()
		thread.start(func():ready.post();start.wait();return House._decode_packet(value));threads.append(thread)
	for i in 8:ready.wait()
	for i in 8:start.post()
	var packets:Array=[]
	for thread:Thread in threads:packets.append(thread.wait_to_finish())
	var trace:=Trace.stop();var decodes:int=trace.events.filter(func(e):return e.label=="prefab.decode_begin").size()
	check(packets.all(func(p):return not p.is_empty() and is_same(p,packets[0])) if valid else packets.all(func(p):return p.is_empty()),"all concurrent callers receive the same success or failure")
	check(House._decoding.is_empty(),"all flight waiters and pending entries finish")
	return {"coalesce":coalesce,"decode_count":decodes,"elapsed_ms":(Time.get_ticks_usec()-began)/1000.,"data":packets[0].get("data",{})}
func run()->void:
	var value:=fixture();var old:=concurrent(value,false);var current:=concurrent(value,true)
	check(old.decode_count>1,"baseline reproduces repeated decode for a shared prefab")
	check(current.decode_count==1,"eight simultaneous cold requests perform exactly one decode")
	check(var_to_bytes(old.data)==var_to_bytes(current.data),"coalesced decode preserves exact geometry and metadata")
	Trace.start()
	var ready:=true
	for i in 100:ready=House.warm(value) and ready
	check(ready,"100 resident shared prefab requests stay usable")
	check(Trace.stop().events.filter(func(e):return e.label=="prefab.decode_begin").is_empty(),"100 repeated resident requests perform zero extra decodes")
	var bad:=value.duplicate();bad.sha256="0".repeat(64)
	bad.data=Marshalls.raw_to_base64(PackedByteArray([1,2,3]))
	var rejected:=concurrent(bad,true,false)
	check(rejected.data.is_empty() and House._decoding.is_empty(),"failed decoding wakes every waiter and retains no pending job")
	House.evict_geometry({value.sha256:true,bad.sha256:true})
	old.erase("data");current.erase("data")
	print("PREFAB_SHARED_DECODE ",JSON.stringify({"baseline":old,"candidate":current,"failures":failures}))
	quit(1 if failures else 0)
