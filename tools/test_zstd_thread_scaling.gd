extends SceneTree
## Exercises the same engine Compression::decompress used by native .scn reads.
## Fixed bytes, independent outputs, exact equality; no files or renderer work.
const TOTAL_BYTES:=384*1024*1024
var failures:=0
func _initialize()->void:run.call_deferred()
func sample(raw:PackedByteArray,packed:PackedByteArray,workers:int)->Dictionary:
	var threads:Array[Thread]=[];var ready:=Semaphore.new();var start:=Semaphore.new()
	var loops:=int(TOTAL_BYTES/raw.size()/workers)
	for i:int in workers:
		var thread:=Thread.new()
		thread.start(func():
			ready.post();start.wait();var began:=Time.get_ticks_usec();var matches:=0
			for n:int in loops:
				var restored:=packed.decompress(raw.size(),FileAccess.COMPRESSION_ZSTD)
				if restored==raw:matches+=1
			return {"matches":matches,"wall_us":Time.get_ticks_usec()-began})
		threads.append(thread)
	for i:int in workers:ready.wait()
	var began:=Time.get_ticks_usec()
	for i:int in workers:start.post()
	var matches:=0;var sum_wall:=0
	for thread:Thread in threads:
		var row:Dictionary=thread.wait_to_finish();matches+=row.matches;sum_wall+=row.wall_us
	var result:={"workers":workers,"block_bytes":raw.size(),"compressed_bytes":packed.size(),"calls":loops*workers,"bytes":loops*workers*raw.size(),"matches":matches,"wall_us":Time.get_ticks_usec()-began,"sum_task_wall_us":sum_wall}
	if matches!=loops*workers or result.bytes!=TOTAL_BYTES:failures+=1
	return result
func run()->void:
	for size:int in [4096,262144]:
		var values:=PackedFloat32Array();values.resize(size/4)
		for i:int in values.size():values[i]=sin(i*.031)*12.0+float(i%37)*.013
		var raw:=values.to_byte_array();var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
		for workers:int in [1,3,12,12,3,1]:print("ZSTD_THREAD_SCALING ",JSON.stringify(sample(raw,packed,workers)))
	print("ZSTD_THREAD_SCALING failures=",failures);quit(1 if failures else 0)
