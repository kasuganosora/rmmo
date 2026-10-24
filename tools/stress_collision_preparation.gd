extends SceneTree
## Fixed total work; main-thread physics installation is timed separately.
var failures:=0
var output:=""
var jobs:=48
var rows:Array=[]
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func faces()->PackedVector3Array:
	var result:=PackedVector3Array()
	for z:int in 32:
		for x:int in 64:
			var a:=Vector3(x,sin(x*.2)*cos(z*.3),z)
			var b:=Vector3(x+1,sin((x+1)*.2)*cos(z*.3),z)
			var c:=Vector3(x,sin(x*.2)*cos((z+1)*.3),z+1)
			var d:=Vector3(x+1,sin((x+1)*.2)*cos((z+1)*.3),z+1)
			result.append_array(PackedVector3Array([a,c,b,b,c,d]))
	return result
static func prepare(source:PackedVector3Array,count:int,gate:Semaphore)->Dictionary:
	gate.wait()
	var began:=Time.get_ticks_usec();var packets:Array=[]
	for i:int in count:packets.append(PhysicsServer3D.call(&"prepare_concave_shape_data",source,false))
	return {"packets":packets,"us":Time.get_ticks_usec()-began,"thread":OS.get_thread_caller_id()}
func run()->void:
	var source:=faces();var original:=source.to_byte_array()
	var available:=PhysicsServer3D.has_method(&"prepare_concave_shape_data")
	var legacy:Array=[];var began:=Time.get_ticks_usec()
	for i:int in jobs:
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(source);legacy.append(shape)
	var legacy_us:=Time.get_ticks_usec()-began
	check(legacy.size()==jobs,"baseline completes fixed 48 shapes")
	if available:
		for workers:int in [1,3,12,12,3,1]:
			var threads:Array=[];var gate:=Semaphore.new()
			for i:int in workers:
				var thread:=Thread.new();threads.append(thread)
				check(thread.start(prepare.bind(source,jobs/workers,gate))==OK,"worker starts")
			began=Time.get_ticks_usec()
			for i:int in workers:gate.post()
			var packets:Array=[];var worker_us:=0
			for thread:Thread in threads:
				var result:Dictionary=thread.wait_to_finish();packets.append_array(result.packets);worker_us+=result.us
				check(result.thread!=OS.get_main_thread_id(),"BVH prepared off main thread")
			var wall:=Time.get_ticks_usec()-began
			var shapes:Array=[];began=Time.get_ticks_usec()
			for packet:Dictionary in packets:
				var shape:=ConcavePolygonShape3D.new();shape.call(&"set_prepared_faces",packet);shapes.append(shape)
			var install:=Time.get_ticks_usec()-began
			check(shapes.size()==jobs,"same fixed shape count")
			var exact:=true
			for shape:ConcavePolygonShape3D in shapes:exact=exact and shape.get_faces().to_byte_array()==original
			check(exact,"all source faces remain byte exact")
			rows.append({"workers":workers,"jobs":jobs,"prepare_wall_us":wall,"worker_wall_sum_us":worker_us,"main_install_us":install})
			await compare_queries(legacy[0],shapes[0],"prepared")
			# Editing input after preparation must not install a stale BVH.
			var changed:Dictionary=packets[0].duplicate();changed.faces=Transform3D(Basis.IDENTITY,Vector3(0,5,0))*changed.faces
			var edited:=ConcavePolygonShape3D.new();edited.call(&"set_prepared_faces",changed)
			var control:=ConcavePolygonShape3D.new();control.set_faces(changed.faces)
			await compare_queries(control,edited,"changed input fallback")
			var two_sided:Dictionary=packets[0].duplicate();two_sided.backface_collision=true
			var backface:=ConcavePolygonShape3D.new();backface.call(&"set_prepared_faces",two_sided)
			var backface_control:=ConcavePolygonShape3D.new();backface_control.set_backface_collision_enabled(true);backface_control.set_faces(source)
			await compare_queries(backface_control,backface,"backface mode",true)
	check(source.to_byte_array()==original,"immutable shared input remains unchanged")
	var report:={"failures":failures,"api":available,"vertices":source.size(),"jobs":jobs,"legacy_main_us":legacy_us,"runs":rows}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COLLISION_STRESS ",JSON.stringify(report));quit(1 if failures else 0)
func compare_queries(a:Shape3D,b:Shape3D,label:String,from_above:bool=false)->void:
	var spaces:Array=[];var bodies:Array=[]
	for shape:Shape3D in [a,b]:
		var space:=PhysicsServer3D.space_create();PhysicsServer3D.space_set_active(space,true);spaces.append(space)
		var body:=PhysicsServer3D.body_create();bodies.append(body)
		PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(body,1)
		PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D.IDENTITY)
		PhysicsServer3D.body_add_shape(body,shape.get_rid());PhysicsServer3D.body_set_space(body,space)
	await physics_frame;await physics_frame;await process_frame
	var exact:=true;var hits:=0
	for i:int in 64:
		var start:=Vector3((i%16)*3+.25,10 if from_above else -10,(i/16)*7+.35)
		var query:=PhysicsRayQueryParameters3D.create(start,start+Vector3(0,-20 if from_above else 20,0))
		var left:=PhysicsServer3D.space_get_direct_state(spaces[0]).intersect_ray(query)
		var right:=PhysicsServer3D.space_get_direct_state(spaces[1]).intersect_ray(query)
		exact=exact and left.is_empty()==right.is_empty()
		if not left.is_empty() and not right.is_empty():
			hits+=1;exact=exact and left.position==right.position and left.normal==right.normal and left.face_index==right.face_index
	print("QUERY_COMPARE ",label," hits=",hits," exact=",exact)
	check(exact and hits==64,"exact ray position/normal/face index: "+label)
	for body:RID in bodies:PhysicsServer3D.free_rid(body)
	for space:RID in spaces:PhysicsServer3D.free_rid(space)
