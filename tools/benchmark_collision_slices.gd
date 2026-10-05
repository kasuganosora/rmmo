extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var faces:=PackedVector3Array()
	for z in 92:
		for x in 92:
			var a:=Vector3(x,0,z);var b:=a+Vector3.RIGHT;var c:=a+Vector3(1,0,1);var d:=a+Vector3.BACK
			faces.append_array(PackedVector3Array([a,c,b,a,d,c]))
	for size_ in [faces.size(),3072]:
		var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0
		root.add_child(body)
		var maximum:=0.;var total:=0.
		for start in range(0,faces.size(),size_):
			var t:=Time.get_ticks_usec();var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces.slice(start,mini(start+size_,faces.size())))
			var made:=Time.get_ticks_usec();var child:=CollisionShape3D.new();child.shape=shape;body.add_child(child)
			var elapsed:=(Time.get_ticks_usec()-t)/1000.;maximum=maxf(maximum,elapsed);total+=elapsed
			print("SLICE size=",size_," make_ms=",(made-t)/1000.," attach_ms=",elapsed-(made-t)/1000.)
			await process_frame
		var t:=Time.get_ticks_usec();body.collision_layer=1;body.collision_mask=1
		print("SLICE_RESULT size=",size_," max=",maximum," total=",total," activation_ms=",(Time.get_ticks_usec()-t)/1000.)
		await physics_frame;body.free()
	quit()
