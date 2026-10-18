extends "res://tools/test_deferred_backpressure.gd"
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var queue:=Deferred.new();var rng:=RandomNumberGenerator.new();rng.seed=473011
	for i:int in 2400:
		var row:=item("item%d"%i,rng.randf_range(-3000,3000))
		row.bounds=AABB(Vector3(row.bounds.position.x,0,rng.randf_range(-3000,3000)),Vector3(400 if i%37==0 else 10,1,400 if i%37==0 else 10))
		row.published=i%9==0;queue.pending.append(row)
	var equivalent:=true
	for i:int in 400:
		var size_:float=[0.,4.,32.,600.,12000.][i%5]
		var clip:=AABB(Vector3(rng.randf_range(-4000,4000),rng.randf_range(-200,200),rng.randf_range(-4000,4000)),Vector3(size_,1,size_))
		equivalent=equivalent and queue._has_pending_in_clip(clip)==not queue._in_clip(clip).is_empty()
	check(equivalent,"existence matches full query across dense/sparse cells, large objects, inclusive edges and Y noise")
	var clip:=AABB(Vector3.ZERO,Vector3(4,1,4))
	queue.free();queue=Deferred.new();queue.pending=[item("first",0),item("second",0)]
	check(not queue.geometry_published(clip),"unpublished first hit keeps geometry unready")
	queue.pending[0].published=true
	check(not queue.geometry_published(clip),"published first hit does not hide the next pending source")
	queue.pending[1].published=true
	check(queue.geometry_published(clip),"last publication is observed immediately without caching readiness")
	queue.pending[0].published=false
	check(not queue.geometry_published(clip),"requeued source makes the same stationary footprint unready again")
	queue.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	print("GEOMETRY_READINESS_EXISTENCE passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
