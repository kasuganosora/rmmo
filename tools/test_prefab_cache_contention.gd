extends "res://tools/test_house_geometry_identity_reuse.gd"
const CALLS:=768
func sample(value:Dictionary,expected:Dictionary,workers:int)->Dictionary:
	var inputs:Array=[]
	for i:int in workers:
		var own:=value.duplicate();own.data=value.data.to_utf8_buffer().get_string_from_utf8();inputs.append(own)
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array[Thread]=[]
	for i:int in workers:
		var own:Dictionary=inputs[i];var calls:=int(CALLS/workers)
		var worker:=Thread.new()
		worker.start(func():
			ready.post();start.wait();var began:=Time.get_ticks_usec();var matches:=0
			for n:int in calls:
				if is_same(House._decode_packet(own),expected):matches+=1
			return {"calls":calls,"matches":matches,"wall_us":Time.get_ticks_usec()-began})
		threads.append(worker)
	for i:int in workers:ready.wait()
	var began:=Time.get_ticks_usec()
	for i:int in workers:start.post()
	var calls:=0;var matches:=0;var sum_wall:=0
	for worker:Thread in threads:
		var row:Dictionary=worker.wait_to_finish();calls+=row.calls;matches+=row.matches;sum_wall+=row.wall_us
	return {"workers":workers,"calls":calls,"matches":matches,"wall_us":Time.get_ticks_usec()-began,"sum_task_wall_us":sum_wall}
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	var data:=fixture();var bytes:=PackedByteArray();bytes.resize(2*1024*1024)
	var rng:=RandomNumberGenerator.new();rng.seed=104
	for i:int in bytes.size():bytes[i]=rng.randi()&255
	data.fixture_payload=bytes
	var value:=encode(data);var packet:=House._decode_packet(value)
	check(not packet.is_empty(),"large encoded immutable fixture decodes")
	var trace=preload("res://scripts/world3d/load_trace.gd");trace.minimum_event_us=0;trace.start()
	for workers:int in [1,3,2,2,3,1]:
		var row:=sample(value,packet,workers)
		check(row.calls==CALLS and row.matches==CALLS,"fixed work and canonical owner for "+str(workers)+" threads")
		print("PREFAB_CACHE_CONTENTION ",JSON.stringify(row))
	check(trace.stop().events.filter(func(e):return e.label=="prefab.decode_begin").is_empty(),"all thread counts perform zero duplicate decodes")
	House.evict_geometry({value.sha256:true});packet={}
	print("PREFAB_CACHE_CONTENTION failures=",failures);quit(1 if failures else 0)
