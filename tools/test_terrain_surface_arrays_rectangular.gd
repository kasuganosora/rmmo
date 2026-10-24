extends "res://tools/stress_terrain_surface_arrays.gd"
func run()->void:
	for dimensions:Vector2i in [Vector2i(2,64),Vector2i(64,2),Vector2i(3,7),Vector2i(63,31)]:
		var record:=Fixture.fixture();var t:Dictionary=record.terrain_mesh
		t.columns=dimensions.x;t.rows=dimensions.y
		t.heights.resize((dimensions.x+1)*(dimensions.y+1));t.holes.resize(dimensions.x*dimensions.y)
		for i in t.heights.size():t.heights[i]=sin(i*.12)*.7
		for i in t.holes.size():t.holes[i]=i%7==0
		var original:=var_to_bytes(record)
		for context:Dictionary in [{},{"normals":{0:Vector3.UP,dimensions.x:Vector3(.2,1.,.3).normalized()}}]:
			check(var_to_bytes(Terrain.arrays(record,context))==var_to_bytes(Terrain.arrays_legacy(record,context)),"rectangular grid all channels exact "+str(dimensions))
		check(var_to_bytes(record)==original,"rectangular source immutable")
	print("TERRAIN_RECTANGULAR failures=",failures);quit(1 if failures else 0)
