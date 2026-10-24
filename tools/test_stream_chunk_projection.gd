extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Location=preload("res://scripts/world3d/world_location.gd")
func _initialize()->void:
	var values:Array=[NAN,INF,-INF,0.,-0.,-32.,32.,-32.00001,-31.99999,31.99999,32.00001,-.00001,.00001,-100000.,100000.]
	var failures:=0;var count:=0
	for x:float in values:
		for z:float in values:
			var p:=Vector3(x,NAN,z)
			var expected:=Vector2i(Location.chunk_index(p.x,0.,32.),Location.chunk_index(p.z,0.,32.))
			if Stream.chunk_key(p)!=expected:failures+=1
			count+=1
	var old_us:=0;var new_us:=0;var checksum:=Vector2i.ZERO
	for trial:int in 4:
		var began:=Time.get_ticks_usec()
		for i:int in 50000:checksum+=Vector2i(Location.chunk_index(float(i)-25000.,0.,32.),Location.chunk_index(float(i)*-.5,0.,32.))
		old_us+=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		for i:int in 50000:checksum-=Stream.chunk_key(Vector3(float(i)-25000.,0.,float(i)*-.5))
		new_us+=Time.get_ticks_usec()-began
	if checksum!=Vector2i.ZERO:failures+=1
	print("STREAM_CHUNK_PROJECTION ",JSON.stringify({"cases":count,"old_us":old_us,"new_us":new_us,"failures":failures}));quit(1 if failures else 0)
