extends SceneTree
## Native collision preparation must survive debug presentation changes.
## Run headless in an empty external project; timings exclude signal/ray checks.
var failures:Array[String]=[]
var checks:=0
var output:=""
var cells:=96
var changes:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures.append(label)
		push_error(label)

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--cells="):cells=int(arg.trim_prefix("--cells="))
	call_deferred("run")

func prepare(faces:PackedVector3Array)->Dictionary:
	var began:=Time.get_ticks_usec()
	var packet:Dictionary=PhysicsServer3D.call(&"prepare_concave_shape_data",faces,false)
	return {"packet":packet,"us":Time.get_ticks_usec()-began}

func changed()->void:
	changes+=1

func ray(world:Node3D,up:bool)->Dictionary:
	var xz:=cells*.5+.25
	var start:=Vector3(xz,3. if up else -2.,xz)
	var end:=Vector3(xz,-2. if up else 3.,xz)
	var query:=PhysicsRayQueryParameters3D.create(start,end)
	query.hit_back_faces=true
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func run()->void:
	check(not output.is_empty() and cells>=2 and cells<=256,"bounded workload and explicit external output")
	check(ClassDB.class_has_method(&"PhysicsServer3D",&"prepare_concave_shape_data"),"native CPU preparation is available")
	if not failures.is_empty():quit(1);return
	var faces:=PackedVector3Array()
	faces.resize(cells*cells*6)
	var cursor:=0
	for x in cells:
		for z in cells:
			var a:=Vector3(x,0,z)
			var b:=Vector3(x,0,z+1)
			var c:=Vector3(x+1,0,z)
			var d:=Vector3(x+1,0,z+1)
			# Godot front faces use clockwise winding when seen from above.
			for vertex in [a,c,b,c,d,b]:
				faces[cursor]=vertex
				cursor+=1
	print("COLLISION_DEBUG_PHASE prepare")
	var worker:=Thread.new()
	check(worker.start(prepare.bind(faces))==OK,"preparation worker starts")
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	var worker_prepare_us:int=prepared.us
	var shape:=ConcavePolygonShape3D.new()
	check(shape.has_method(&"set_prepared_faces"),"native prepared install is available")
	if not failures.is_empty():quit(1);return
	print("COLLISION_DEBUG_PHASE prepared_install")
	var began:=Time.get_ticks_usec()
	shape.call(&"set_prepared_faces",prepared.packet)
	var install_us:=Time.get_ticks_usec()-began
	var original_rid:=shape.get_rid()
	var world:=Node3D.new()
	root.add_child(world)
	var body:=StaticBody3D.new()
	world.add_child(body)
	var node:=CollisionShape3D.new()
	body.add_child(node)
	print("COLLISION_DEBUG_PHASE bind")
	began=Time.get_ticks_usec()
	node.shape=shape
	var bind_us:=Time.get_ticks_usec()-began
	await physics_frame
	await physics_frame
	await process_frame
	var first_hit:=ray(world,true)
	check(not first_hit.is_empty() and absf(first_hit.get("position",Vector3.ZERO).y)<.001,"prepared front face has collision")
	check(ray(world,false).is_empty(),"prepared back face is disabled")
	shape.changed.connect(changed)
	# Shared shape owners must still receive color/fill change notifications.
	var other:=CollisionShape3D.new()
	other.shape=shape
	var colors:Array[int]=[]
	var fills:Array[int]=[]
	print("COLLISION_DEBUG_PHASE presentation")
	for i in 12:
		for color in [Color.RED,Color.GREEN]:
			began=Time.get_ticks_usec()
			node.debug_color=color
			colors.append(Time.get_ticks_usec()-began)
			check(other.debug_color==color,"shared owner receives debug color")
		began=Time.get_ticks_usec()
		node.debug_fill=not node.debug_fill
		fills.append(Time.get_ticks_usec()-began)
		check(other.debug_fill==node.debug_fill,"shared owner receives fill state")
	check(changes==36,"each real presentation edit emits one change")
	var before_noop:=changes
	node.debug_color=node.debug_color
	node.debug_fill=node.debug_fill
	check(changes==before_noop,"unchanged debug properties remain no-ops")
	check(shape.get_rid()==original_rid and shape.get_faces()==faces,"presentation keeps RID and geometry")
	await physics_frame
	await process_frame
	check(not ray(world,true).is_empty() and ray(world,false).is_empty(),"presentation changes preserve front/back collision")
	print("COLLISION_DEBUG_PHASE backface_edit")
	shape.backface_collision=true
	await physics_frame
	await process_frame
	check(not ray(world,false).is_empty(),"real backface edit still reaches physics")
	print("COLLISION_DEBUG_PHASE geometry_edit")
	var moved:=faces.duplicate()
	for i in moved.size():
		var vertex:=moved[i]
		vertex.y=1.
		moved[i]=vertex
	shape.set_faces(moved)
	await physics_frame
	await process_frame
	var moved_hit:=ray(world,true)
	check(not moved_hit.is_empty() and absf(moved_hit.get("position",Vector3.ZERO).y-1.)<.001,"real geometry edit still updates collision")
	check(shape.get_rid()==original_rid,"geometry and backface edits preserve RID identity")
	other.free()
	world.free()
	shape=null
	prepared.clear()
	await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"cells":cells,"triangles":cells*cells*2,"worker_prepare_us":worker_prepare_us,"install_us":install_us,"bind_us":bind_us,"color_us":colors,"fill_us":fills,"changes":changes,"not_map_performance":true}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COLLISION_DEBUG_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
