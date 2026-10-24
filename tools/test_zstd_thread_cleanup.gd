extends SceneTree
## Paired with a debugger breakpoint on ZstdDecompressionContext's destructor.
## Twelve short-lived decoders must each release their thread-local workspace.
func _initialize()->void:run.call_deferred()
func run()->void:
	var raw:=PackedByteArray();raw.resize(256*1024);raw.fill(37)
	var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array[Thread]=[]
	for i:int in 12:
		var thread:=Thread.new()
		thread.start(func():
			ready.post();start.wait()
			for n:int in 32:
				if packed.decompress(raw.size(),FileAccess.COMPRESSION_ZSTD)!=raw:return false
			return true)
		threads.append(thread)
	for i:int in 12:ready.wait()
	for i:int in 12:start.post()
	var matched:=0
	for thread:Thread in threads:
		if thread.wait_to_finish():matched+=1
	print("ZSTD_CONTEXT_WORKERS matched=",matched," expected=12")
	quit(0 if matched==12 else 1)
